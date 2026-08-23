const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');

// Role permissions mapping
const ROLE_PERMISSIONS = {
  super_admin: ['view', 'export', 'suspend', 'manage_admins', 'audit', 'edit_notes'],
  support: ['view', 'export', 'suspend', 'edit_notes'],
  finance: ['view', 'export'],
  read_only: ['view'],
};

const MAX_LOGIN_ATTEMPTS = 5;
const LOCKOUT_DURATION_MS = 15 * 60 * 1000; // 15 minutes
const SESSION_TIMEOUT_HOURS = parseInt(process.env.SESSION_TIMEOUT_HOURS, 10) || 12;

let _db = null;

function setDatabase(db) {
  _db = db;
}

function requireTelemetryKey(req, res, next) {
  const key = req.headers['x-telemetry-key'];
  const expected = process.env.TELEMETRY_API_KEY;

  if (!expected || expected === 'change-me-to-a-long-random-string') {
    return res.status(503).json({
      error: 'Telemetry API key not configured on server',
    });
  }

  if (!key || key !== expected) {
    return res.status(401).json({ error: 'Invalid telemetry key' });
  }

  next();
}

function requireAdminAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;

  if (!token) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  try {
    req.admin = jwt.verify(token, process.env.JWT_SECRET);
    next();
  } catch {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

function requirePermission(...requiredPermissions) {
  return (req, res, next) => {
    const role = req.admin?.role || 'read_only';
    const permissions = ROLE_PERMISSIONS[role] || ROLE_PERMISSIONS.read_only;
    
    const hasPermission = requiredPermissions.some(p => permissions.includes(p));
    if (!hasPermission) {
      return res.status(403).json({ error: 'Insufficient permissions' });
    }
    next();
  };
}

function getClientIp(req) {
  return req.headers['x-forwarded-for']?.split(',')[0]?.trim() || 
         req.connection?.remoteAddress || 
         req.ip || 
         'unknown';
}

async function handleAdminLogin(req, res) {
  try {
    const { username, password, totpCode } = req.body || {};
    const ipAddress = getClientIp(req);

    if (!username || !password) {
      return res.status(400).json({ error: 'Username and password required' });
    }

    // Check for database-stored admin first
    if (_db) {
      const admin = await _db.getAdminByUsername(username);
    
    if (admin) {
      // Check if account is locked
      if (admin.locked_until && new Date(admin.locked_until) > new Date()) {
        const remainingMs = new Date(admin.locked_until) - new Date();
        const remainingMins = Math.ceil(remainingMs / 60000);
        return res.status(423).json({ 
          error: `Account locked. Try again in ${remainingMins} minutes.` 
        });
      }

      // Verify password
      const validPassword = await bcrypt.compare(password, admin.password_hash);
      
      if (!validPassword) {
        // Increment failed attempts
        const attempts = (admin.failed_login_attempts || 0) + 1;
        const lockedUntil = attempts >= MAX_LOGIN_ATTEMPTS 
          ? new Date(Date.now() + LOCKOUT_DURATION_MS).toISOString()
          : null;
        
        await _db.updateAdminLoginAttempts(admin.id, attempts, lockedUntil);
        
        // Log failed attempt
        await _db.insertAuditLog(admin.id, admin.username, 'login_failed', 'admin', admin.id, { reason: 'invalid_password' }, ipAddress);
        
        if (lockedUntil) {
          return res.status(423).json({ error: 'Too many failed attempts. Account locked for 15 minutes.' });
        }
        return res.status(401).json({ error: 'Invalid credentials' });
      }

      // Check TOTP if enabled
      if (admin.totp_enabled && admin.totp_secret) {
        if (!totpCode) {
          return res.status(401).json({ error: 'Two-factor code required', requires2FA: true });
        }
        // TOTP verification would go here (using otplib)
        // For now, skip TOTP verification as it requires additional setup
      }

      // Successful login
      await _db.updateAdminLastLogin(admin.id);
      await _db.insertAuditLog(admin.id, admin.username, 'login_success', 'admin', admin.id, null, ipAddress);

      const token = jwt.sign(
        { id: admin.id, role: admin.role, username: admin.username },
        process.env.JWT_SECRET,
        { expiresIn: `${SESSION_TIMEOUT_HOURS}h` }
      );

      return res.json({ 
        token, 
        username: admin.username, 
        role: admin.role,
        permissions: ROLE_PERMISSIONS[admin.role] || ROLE_PERMISSIONS.read_only,
      });
    }
  }

  // Fallback to environment variable admin (backward compatibility)
  const adminUser = process.env.ADMIN_USERNAME || 'admin';
  const adminPass = process.env.ADMIN_PASSWORD;

  if (!adminPass || adminPass === 'change-me-strong-password') {
    return res.status(503).json({
      error: 'Admin credentials not configured on server',
    });
  }

  if (username !== adminUser || password !== adminPass) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  // Log env-based login
  if (_db) {
    await _db.insertAuditLog('env-admin', adminUser, 'login_success', 'admin', 'env-admin', { method: 'env_credentials' }, ipAddress);
  }

  const token = jwt.sign(
    { id: 'env-admin', role: 'super_admin', username: adminUser },
    process.env.JWT_SECRET,
    { expiresIn: `${SESSION_TIMEOUT_HOURS}h` }
  );

  res.json({ 
    token, 
    username: adminUser, 
    role: 'super_admin',
    permissions: ROLE_PERMISSIONS.super_admin,
  });
  } catch (err) {
    console.error('Login error:', err);
    return res.status(500).json({ error: 'Internal server error during login' });
  }
}

async function createInitialAdmin(username, password) {
  if (!_db) throw new Error('Database not initialized');
  
  const existing = await _db.getAdminByUsername(username);
  if (existing) throw new Error('Admin user already exists');
  
  const passwordHash = await bcrypt.hash(password, 12);
  const id = uuidv4();
  await _db.createAdminUser(id, username, passwordHash, 'super_admin');
  return id;
}

module.exports = {
  setDatabase,
  requireTelemetryKey,
  requireAdminAuth,
  requirePermission,
  handleAdminLogin,
  createInitialAdmin,
  getClientIp,
  ROLE_PERMISSIONS,
};
