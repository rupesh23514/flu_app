const fs = require('fs');
const path = require('path');
const Database = require('better-sqlite3');
const { Pool } = require('pg');

const SCHEMA = `
CREATE TABLE IF NOT EXISTS users (
  device_id TEXT PRIMARY KEY,
  email TEXT,
  display_name TEXT,
  app_version TEXT,
  platform TEXT DEFAULT 'android',
  customer_count INTEGER DEFAULT 0,
  loan_count INTEGER DEFAULT 0,
  active_loan_count INTEGER DEFAULT 0,
  overdue_loan_count INTEGER DEFAULT 0,
  payment_count INTEGER DEFAULT 0,
  total_outstanding REAL DEFAULT 0,
  total_principal_outstanding REAL DEFAULT 0,
  total_interest_outstanding REAL DEFAULT 0,
  monthly_collection REAL DEFAULT 0,
  loan_type_breakdown TEXT,
  last_backup_at TEXT,
  last_sign_in_at TEXT,
  first_seen_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  sign_in_count INTEGER DEFAULT 0,
  backup_count INTEGER DEFAULT 0,
  backup_fail_count INTEGER DEFAULT 0,
  session_count INTEGER DEFAULT 0,
  error_count INTEGER DEFAULT 0,
  suspended INTEGER DEFAULT 0,
  suspended_reason TEXT,
  admin_notes TEXT
);

CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id TEXT NOT NULL,
  email TEXT,
  event_type TEXT NOT NULL,
  payload TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (device_id) REFERENCES users(device_id)
);

CREATE INDEX IF NOT EXISTS idx_events_device ON events(device_id);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_created ON events(created_at);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_last_seen ON users(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_users_suspended ON users(suspended);

CREATE TABLE IF NOT EXISTS admin_users (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'read_only',
  totp_secret TEXT,
  totp_enabled INTEGER DEFAULT 0,
  failed_login_attempts INTEGER DEFAULT 0,
  locked_until TEXT,
  last_login_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  is_active INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS admin_audit_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  admin_id TEXT NOT NULL,
  admin_username TEXT,
  action TEXT NOT NULL,
  target_type TEXT,
  target_id TEXT,
  details TEXT,
  ip_address TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_admin ON admin_audit_logs(admin_id);
CREATE INDEX IF NOT EXISTS idx_audit_action ON admin_audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_created ON admin_audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_admin_users_username ON admin_users(username);

CREATE TABLE IF NOT EXISTS plans (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  customer_limit INTEGER,
  features TEXT,
  price_monthly INTEGER DEFAULT 0,
  price_yearly INTEGER DEFAULT 0,
  is_active INTEGER DEFAULT 1,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS subscriptions (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  email TEXT,
  plan_id TEXT NOT NULL,
  status TEXT DEFAULT 'active',
  started_at TEXT NOT NULL,
  expires_at TEXT,
  payment_provider TEXT,
  payment_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (device_id) REFERENCES users(device_id),
  FOREIGN KEY (plan_id) REFERENCES plans(id)
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_device ON subscriptions(device_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_email ON subscriptions(email);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions(status);

CREATE TABLE IF NOT EXISTS email_blocks (
  email TEXT PRIMARY KEY,
  reason TEXT NOT NULL,
  suspended_by TEXT,
  suspended_by_username TEXT,
  suspended_at TEXT NOT NULL,
  unsuspended_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_email_blocks_suspended_at ON email_blocks(suspended_at);
`;

const PG_SCHEMA = `
CREATE TABLE IF NOT EXISTS users (
  device_id TEXT PRIMARY KEY,
  email TEXT,
  display_name TEXT,
  app_version TEXT,
  platform TEXT DEFAULT 'android',
  customer_count INTEGER DEFAULT 0,
  loan_count INTEGER DEFAULT 0,
  active_loan_count INTEGER DEFAULT 0,
  overdue_loan_count INTEGER DEFAULT 0,
  payment_count INTEGER DEFAULT 0,
  total_outstanding REAL DEFAULT 0,
  total_principal_outstanding REAL DEFAULT 0,
  total_interest_outstanding REAL DEFAULT 0,
  monthly_collection REAL DEFAULT 0,
  loan_type_breakdown JSONB,
  last_backup_at TIMESTAMPTZ,
  last_sign_in_at TIMESTAMPTZ,
  first_seen_at TIMESTAMPTZ NOT NULL,
  last_seen_at TIMESTAMPTZ NOT NULL,
  sign_in_count INTEGER DEFAULT 0,
  backup_count INTEGER DEFAULT 0,
  backup_fail_count INTEGER DEFAULT 0,
  session_count INTEGER DEFAULT 0,
  error_count INTEGER DEFAULT 0,
  suspended INTEGER DEFAULT 0,
  suspended_reason TEXT,
  admin_notes TEXT
);

CREATE TABLE IF NOT EXISTS events (
  id SERIAL PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES users(device_id),
  email TEXT,
  event_type TEXT NOT NULL,
  payload JSONB,
  created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_device ON events(device_id);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_created ON events(created_at);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_last_seen ON users(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_users_suspended ON users(suspended);

CREATE TABLE IF NOT EXISTS admin_users (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'read_only',
  totp_secret TEXT,
  totp_enabled INTEGER DEFAULT 0,
  failed_login_attempts INTEGER DEFAULT 0,
  locked_until TIMESTAMPTZ,
  last_login_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  is_active INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS admin_audit_logs (
  id SERIAL PRIMARY KEY,
  admin_id TEXT NOT NULL,
  admin_username TEXT,
  action TEXT NOT NULL,
  target_type TEXT,
  target_id TEXT,
  details JSONB,
  ip_address TEXT,
  created_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_admin ON admin_audit_logs(admin_id);
CREATE INDEX IF NOT EXISTS idx_audit_action ON admin_audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_created ON admin_audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_admin_users_username ON admin_users(username);

CREATE TABLE IF NOT EXISTS plans (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  customer_limit INTEGER,
  features JSONB,
  price_monthly INTEGER DEFAULT 0,
  price_yearly INTEGER DEFAULT 0,
  is_active INTEGER DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS subscriptions (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES users(device_id),
  email TEXT,
  plan_id TEXT NOT NULL REFERENCES plans(id),
  status TEXT DEFAULT 'active',
  started_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ,
  payment_provider TEXT,
  payment_id TEXT,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_device ON subscriptions(device_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_email ON subscriptions(email);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON subscriptions(status);

CREATE TABLE IF NOT EXISTS email_blocks (
  email TEXT PRIMARY KEY,
  reason TEXT NOT NULL,
  suspended_by TEXT,
  suspended_by_username TEXT,
  suspended_at TIMESTAMPTZ NOT NULL,
  unsuspended_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_email_blocks_suspended_at ON email_blocks(suspended_at);
`;

class AdminDatabase {
  constructor() {
    this.mode = process.env.DATABASE_URL ? 'postgres' : 'sqlite';
    this.ready = this._init();
  }

  async _init() {
    if (this.mode === 'postgres') {
      this.pool = new Pool({
        connectionString: process.env.DATABASE_URL,
        ssl: process.env.NODE_ENV === 'production'
          ? { rejectUnauthorized: false }
          : false,
      });
      // Handle pool errors to prevent process crash on idle client errors
      this.pool.on('error', (err) => {
        console.error('PostgreSQL pool error:', err.message);
      });
      await this.pool.query(PG_SCHEMA);
      await this._migratePostgres();
      return;
    }

    const dataDir = path.join(__dirname, '..', 'data');
    if (!fs.existsSync(dataDir)) {
      fs.mkdirSync(dataDir, { recursive: true });
    }
    this.db = new Database(path.join(dataDir, 'admin.db'));
    this.db.pragma('journal_mode = WAL');
    this.db.exec(SCHEMA);
    await this._migrateSqlite();
  }

  // Add missing columns to existing SQLite database
  async _migrateSqlite() {
    const columns = this.db.prepare("PRAGMA table_info(users)").all();
    const existingCols = new Set(columns.map(c => c.name));

    const newColumns = [
      { name: 'overdue_loan_count', type: 'INTEGER DEFAULT 0' },
      { name: 'total_principal_outstanding', type: 'REAL DEFAULT 0' },
      { name: 'total_interest_outstanding', type: 'REAL DEFAULT 0' },
      { name: 'monthly_collection', type: 'REAL DEFAULT 0' },
      { name: 'loan_type_breakdown', type: 'TEXT' },
      { name: 'suspended', type: 'INTEGER DEFAULT 0' },
      { name: 'suspended_reason', type: 'TEXT' },
      { name: 'admin_notes', type: 'TEXT' },
    ];

    for (const col of newColumns) {
      if (!existingCols.has(col.name)) {
        try {
          this.db.exec(`ALTER TABLE users ADD COLUMN ${col.name} ${col.type}`);
          console.log(`Added column ${col.name} to users table`);
        } catch (err) {
          // Log migration errors for debugging (column likely already exists)
          if (!err.message?.includes('duplicate column')) {
            console.warn(`SQLite migration warning for column ${col.name}:`, err.message);
          }
        }
      }
    }
  }

  // Add missing columns to existing Postgres database
  async _migratePostgres() {
    const newColumns = [
      { name: 'overdue_loan_count', type: 'INTEGER DEFAULT 0' },
      { name: 'total_principal_outstanding', type: 'REAL DEFAULT 0' },
      { name: 'total_interest_outstanding', type: 'REAL DEFAULT 0' },
      { name: 'monthly_collection', type: 'REAL DEFAULT 0' },
      { name: 'loan_type_breakdown', type: 'JSONB' },
      { name: 'suspended', type: 'INTEGER DEFAULT 0' },
      { name: 'suspended_reason', type: 'TEXT' },
      { name: 'admin_notes', type: 'TEXT' },
    ];

    for (const col of newColumns) {
      try {
        await this.pool.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS ${col.name} ${col.type}`);
      } catch (err) {
        // Log migration errors for debugging (IF NOT EXISTS should handle most cases)
        if (!err.message?.includes('already exists')) {
          console.warn(`Postgres migration warning for column ${col.name}:`, err.message);
        }
      }
    }
  }

  async _run(sql, params = []) {
    await this.ready;
    if (this.mode === 'postgres') {
      const result = await this.pool.query(sql, params);
      return result;
    }
    return this.db.prepare(sql).run(...params);
  }

  async _all(sql, params = []) {
    await this.ready;
    if (this.mode === 'postgres') {
      const result = await this.pool.query(sql, params);
      return result.rows;
    }
    return this.db.prepare(sql).all(...params);
  }

  async _get(sql, params = []) {
    await this.ready;
    if (this.mode === 'postgres') {
      const result = await this.pool.query(sql, params);
      return result.rows[0] || null;
    }
    return this.db.prepare(sql).get(...params) || null;
  }

  async upsertUser(deviceId, fields) {
    const now = new Date().toISOString();
    const existing = await this._get(
      this.mode === 'postgres'
        ? 'SELECT device_id FROM users WHERE device_id = $1'
        : 'SELECT device_id FROM users WHERE device_id = ?',
      [deviceId]
    );

    // Serialize loan_type_breakdown for storage
    const loanTypeBreakdown = fields.loanTypeBreakdown 
      ? (this.mode === 'postgres' ? fields.loanTypeBreakdown : JSON.stringify(fields.loanTypeBreakdown))
      : null;

    if (!existing) {
      if (this.mode === 'postgres') {
        await this.pool.query(
          `INSERT INTO users (
            device_id, email, display_name, app_version, platform,
            customer_count, loan_count, active_loan_count, overdue_loan_count, payment_count,
            total_outstanding, total_principal_outstanding, total_interest_outstanding,
            monthly_collection, loan_type_breakdown, last_backup_at, last_sign_in_at,
            first_seen_at, last_seen_at, sign_in_count, backup_count,
            backup_fail_count, session_count, error_count, suspended, suspended_reason, admin_notes
          ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27)`,
          [
            deviceId,
            fields.email ?? null,
            fields.displayName ?? null,
            fields.appVersion ?? null,
            fields.platform ?? 'android',
            fields.customerCount ?? 0,
            fields.loanCount ?? 0,
            fields.activeLoanCount ?? 0,
            fields.overdueLoanCount ?? 0,
            fields.paymentCount ?? 0,
            fields.totalOutstanding ?? 0,
            fields.totalPrincipalOutstanding ?? 0,
            fields.totalInterestOutstanding ?? 0,
            fields.monthlyCollection ?? 0,
            loanTypeBreakdown,
            fields.lastBackupAt ?? null,
            fields.lastSignInAt ?? null,
            now,
            now,
            fields.signInCount ?? 0,
            fields.backupCount ?? 0,
            fields.backupFailCount ?? 0,
            fields.sessionCount ?? 1,
            fields.errorCount ?? 0,
            fields.suspended ?? 0,
            fields.suspendedReason ?? null,
            fields.adminNotes ?? null,
          ]
        );
      } else {
        this.db.prepare(
          `INSERT INTO users (
            device_id, email, display_name, app_version, platform,
            customer_count, loan_count, active_loan_count, overdue_loan_count, payment_count,
            total_outstanding, total_principal_outstanding, total_interest_outstanding,
            monthly_collection, loan_type_breakdown, last_backup_at, last_sign_in_at,
            first_seen_at, last_seen_at, sign_in_count, backup_count,
            backup_fail_count, session_count, error_count, suspended, suspended_reason, admin_notes
          ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`
        ).run(
          deviceId,
          fields.email ?? null,
          fields.displayName ?? null,
          fields.appVersion ?? null,
          fields.platform ?? 'android',
          fields.customerCount ?? 0,
          fields.loanCount ?? 0,
          fields.activeLoanCount ?? 0,
          fields.overdueLoanCount ?? 0,
          fields.paymentCount ?? 0,
          fields.totalOutstanding ?? 0,
          fields.totalPrincipalOutstanding ?? 0,
          fields.totalInterestOutstanding ?? 0,
          fields.monthlyCollection ?? 0,
          loanTypeBreakdown,
          fields.lastBackupAt ?? null,
          fields.lastSignInAt ?? null,
          now,
          now,
          fields.signInCount ?? 0,
          fields.backupCount ?? 0,
          fields.backupFailCount ?? 0,
          fields.sessionCount ?? 1,
          fields.errorCount ?? 0,
          fields.suspended ?? 0,
          fields.suspendedReason ?? null,
          fields.adminNotes ?? null
        );
      }
      return;
    }

    const sets = [];
    const params = [];
    let i = 1;

    const addField = (column, value) => {
      if (value === undefined) return;
      if (this.mode === 'postgres') {
        sets.push(`${column} = $${i++}`);
        params.push(value);
      } else {
        sets.push(`${column} = ?`);
        params.push(value);
      }
    };

    addField('email', fields.email);
    addField('display_name', fields.displayName);
    addField('app_version', fields.appVersion);
    addField('platform', fields.platform);
    addField('customer_count', fields.customerCount);
    addField('loan_count', fields.loanCount);
    addField('active_loan_count', fields.activeLoanCount);
    addField('overdue_loan_count', fields.overdueLoanCount);
    addField('payment_count', fields.paymentCount);
    addField('total_outstanding', fields.totalOutstanding);
    addField('total_principal_outstanding', fields.totalPrincipalOutstanding);
    addField('total_interest_outstanding', fields.totalInterestOutstanding);
    addField('monthly_collection', fields.monthlyCollection);
    if (fields.loanTypeBreakdown !== undefined) {
      addField('loan_type_breakdown', loanTypeBreakdown);
    }
    addField('last_backup_at', fields.lastBackupAt);
    addField('last_sign_in_at', fields.lastSignInAt);
    addField('sign_in_count', fields.signInCount);
    addField('backup_count', fields.backupCount);
    addField('backup_fail_count', fields.backupFailCount);
    addField('session_count', fields.sessionCount);
    addField('error_count', fields.errorCount);
    addField('suspended', fields.suspended);
    addField('suspended_reason', fields.suspendedReason);
    addField('admin_notes', fields.adminNotes);

    if (this.mode === 'postgres') {
      sets.push(`last_seen_at = $${i++}`);
      params.push(now);
      params.push(deviceId);
      await this.pool.query(
        `UPDATE users SET ${sets.join(', ')} WHERE device_id = $${i}`,
        params
      );
    } else {
      sets.push('last_seen_at = ?');
      params.push(now);
      params.push(deviceId);
      this.db.prepare(`UPDATE users SET ${sets.join(', ')} WHERE device_id = ?`).run(...params);
    }
  }

  async incrementUserCounter(deviceId, field, amount = 1) {
    await this.ready;
    const allowed = [
      'sign_in_count',
      'backup_count',
      'backup_fail_count',
      'session_count',
      'error_count',
    ];
    if (!allowed.includes(field)) return;

    if (this.mode === 'postgres') {
      await this.pool.query(
        `UPDATE users SET ${field} = COALESCE(${field}, 0) + $1, last_seen_at = $2 WHERE device_id = $3`,
        [amount, new Date().toISOString(), deviceId]
      );
    } else {
      this.db.prepare(
        `UPDATE users SET ${field} = COALESCE(${field}, 0) + ?, last_seen_at = ? WHERE device_id = ?`
      ).run(amount, new Date().toISOString(), deviceId);
    }
  }

  async insertEvent(deviceId, email, eventType, payload) {
    const now = new Date().toISOString();
    if (this.mode === 'postgres') {
      await this.pool.query(
        'INSERT INTO events (device_id, email, event_type, payload, created_at) VALUES ($1,$2,$3,$4,$5)',
        [deviceId, email ?? null, eventType, payload ? JSON.stringify(payload) : null, now]
      );
    } else {
      this.db.prepare(
        'INSERT INTO events (device_id, email, event_type, payload, created_at) VALUES (?,?,?,?,?)'
      ).run(deviceId, email ?? null, eventType, payload ? JSON.stringify(payload) : null, now);
    }
  }

  async getOverview() {
    const users = await this._get(
      this.mode === 'postgres'
        ? `SELECT
            COUNT(*)::int AS total_users,
            COUNT(*) FILTER (WHERE email IS NOT NULL)::int AS signed_in_users,
            COUNT(*) FILTER (WHERE suspended = 1)::int AS suspended_users,
            COALESCE(SUM(customer_count), 0)::int AS total_customers,
            COALESCE(SUM(loan_count), 0)::int AS total_loans,
            COALESCE(SUM(active_loan_count), 0)::int AS active_loans,
            COALESCE(SUM(overdue_loan_count), 0)::int AS overdue_loans,
            COALESCE(SUM(total_principal_outstanding), 0)::real AS total_principal_outstanding,
            COALESCE(SUM(total_interest_outstanding), 0)::real AS total_interest_outstanding,
            COALESCE(SUM(monthly_collection), 0)::real AS total_monthly_collection,
            COALESCE(SUM(backup_count), 0)::int AS total_backups,
            COALESCE(SUM(backup_fail_count), 0)::int AS total_backup_failures,
            COALESCE(SUM(error_count), 0)::int AS total_errors
          FROM users`
        : `SELECT
            COUNT(*) AS total_users,
            SUM(CASE WHEN email IS NOT NULL THEN 1 ELSE 0 END) AS signed_in_users,
            SUM(CASE WHEN suspended = 1 THEN 1 ELSE 0 END) AS suspended_users,
            COALESCE(SUM(customer_count), 0) AS total_customers,
            COALESCE(SUM(loan_count), 0) AS total_loans,
            COALESCE(SUM(active_loan_count), 0) AS active_loans,
            COALESCE(SUM(overdue_loan_count), 0) AS overdue_loans,
            COALESCE(SUM(total_principal_outstanding), 0) AS total_principal_outstanding,
            COALESCE(SUM(total_interest_outstanding), 0) AS total_interest_outstanding,
            COALESCE(SUM(monthly_collection), 0) AS total_monthly_collection,
            COALESCE(SUM(backup_count), 0) AS total_backups,
            COALESCE(SUM(backup_fail_count), 0) AS total_backup_failures,
            COALESCE(SUM(error_count), 0) AS total_errors
          FROM users`
    );

    const activeToday = await this._get(
      this.mode === 'postgres'
        ? `SELECT COUNT(*)::int AS count FROM users WHERE last_seen_at >= NOW() - INTERVAL '24 hours'`
        : `SELECT COUNT(*) AS count FROM users WHERE datetime(last_seen_at) >= datetime('now', '-1 day')`
    );

    const activeThisWeek = await this._get(
      this.mode === 'postgres'
        ? `SELECT COUNT(*)::int AS count FROM users WHERE last_seen_at >= NOW() - INTERVAL '7 days'`
        : `SELECT COUNT(*) AS count FROM users WHERE datetime(last_seen_at) >= datetime('now', '-7 days')`
    );

    const activeThisMonth = await this._get(
      this.mode === 'postgres'
        ? `SELECT COUNT(*)::int AS count FROM users WHERE last_seen_at >= NOW() - INTERVAL '30 days'`
        : `SELECT COUNT(*) AS count FROM users WHERE datetime(last_seen_at) >= datetime('now', '-30 days')`
    );

    // Backup health: users with backup in last 7 days
    const backupHealthy = await this._get(
      this.mode === 'postgres'
        ? `SELECT COUNT(*)::int AS count FROM users WHERE last_backup_at >= NOW() - INTERVAL '7 days'`
        : `SELECT COUNT(*) AS count FROM users WHERE datetime(last_backup_at) >= datetime('now', '-7 days')`
    );

    const recentEvents = await this._all(
      this.mode === 'postgres'
        ? `SELECT event_type, COUNT(*)::int AS count
           FROM events
           WHERE created_at >= NOW() - INTERVAL '7 days'
           GROUP BY event_type
           ORDER BY count DESC`
        : `SELECT event_type, COUNT(*) AS count
           FROM events
           WHERE datetime(created_at) >= datetime('now', '-7 days')
           GROUP BY event_type
           ORDER BY count DESC`
    );

    // App version distribution
    const versionDistribution = await this._all(
      this.mode === 'postgres'
        ? `SELECT app_version, COUNT(*)::int AS count
           FROM users
           WHERE app_version IS NOT NULL
           GROUP BY app_version
           ORDER BY count DESC`
        : `SELECT app_version, COUNT(*) AS count
           FROM users
           WHERE app_version IS NOT NULL
           GROUP BY app_version
           ORDER BY count DESC`
    );

    return {
      ...users,
      active_today: activeToday?.count ?? 0,
      active_this_week: activeThisWeek?.count ?? 0,
      active_this_month: activeThisMonth?.count ?? 0,
      backup_healthy_count: backupHealthy?.count ?? 0,
      backup_health_percent: users?.total_users > 0 
        ? Math.round((backupHealthy?.count ?? 0) / users.total_users * 100) 
        : 0,
      events_last_7_days: recentEvents,
      version_distribution: versionDistribution,
    };
  }

  async listUsers({ search = '', limit = 100, offset = 0 } = {}) {
    const like = `%${search}%`;
    if (this.mode === 'postgres') {
      return this._all(
        `SELECT * FROM users
         WHERE ($1 = '' OR email ILIKE $2 OR display_name ILIKE $2 OR device_id ILIKE $2)
         ORDER BY last_seen_at DESC NULLS LAST
         LIMIT $3 OFFSET $4`,
        [search, like, limit, offset]
      );
    }
    return this._all(
      `SELECT * FROM users
       WHERE (? = '' OR email LIKE ? OR display_name LIKE ? OR device_id LIKE ?)
       ORDER BY last_seen_at DESC
       LIMIT ? OFFSET ?`,
      [search, like, like, like, limit, offset]
    );
  }

  async getUser(deviceId) {
    return this._get(
      this.mode === 'postgres'
        ? 'SELECT * FROM users WHERE device_id = $1'
        : 'SELECT * FROM users WHERE device_id = ?',
      [deviceId]
    );
  }

  async getUserEvents(deviceId, limit = 50) {
    return this._all(
      this.mode === 'postgres'
        ? `SELECT * FROM events WHERE device_id = $1 ORDER BY created_at DESC LIMIT $2`
        : `SELECT * FROM events WHERE device_id = ? ORDER BY created_at DESC LIMIT ?`,
      [deviceId, limit]
    );
  }

  async getRecentEvents({ type, limit = 100 } = {}) {
    if (type) {
      return this._all(
        this.mode === 'postgres'
          ? `SELECT e.*, u.display_name FROM events e
             LEFT JOIN users u ON u.device_id = e.device_id
             WHERE e.event_type = $1
             ORDER BY e.created_at DESC LIMIT $2`
          : `SELECT e.*, u.display_name FROM events e
             LEFT JOIN users u ON u.device_id = e.device_id
             WHERE e.event_type = ?
             ORDER BY e.created_at DESC LIMIT ?`,
        [type, limit]
      );
    }
    return this._all(
      this.mode === 'postgres'
        ? `SELECT e.*, u.display_name FROM events e
           LEFT JOIN users u ON u.device_id = e.device_id
           ORDER BY e.created_at DESC LIMIT $1`
        : `SELECT e.*, u.display_name FROM events e
           LEFT JOIN users u ON u.device_id = e.device_id
           ORDER BY e.created_at DESC LIMIT ?`,
      [limit]
    );
  }

  async getSignInTrend(days = 14) {
    if (this.mode === 'postgres') {
      return this._all(
        `SELECT DATE(created_at) AS day, COUNT(*)::int AS count
         FROM events
         WHERE event_type = 'sign_in'
           AND created_at >= NOW() - ($1 || ' days')::interval
         GROUP BY DATE(created_at)
         ORDER BY day ASC`,
        [String(days)]
      );
    }
    return this._all(
      `SELECT date(created_at) AS day, COUNT(*) AS count
       FROM events
       WHERE event_type = 'sign_in'
         AND datetime(created_at) >= datetime('now', '-' || ? || ' days')
       GROUP BY date(created_at)
       ORDER BY day ASC`,
      [days]
    );
  }

  // ============================================================
  // ADMIN USER MANAGEMENT
  // ============================================================

  async getAdminByUsername(username) {
    return this._get(
      this.mode === 'postgres'
        ? 'SELECT * FROM admin_users WHERE username = $1 AND is_active = 1'
        : 'SELECT * FROM admin_users WHERE username = ? AND is_active = 1',
      [username]
    );
  }

  async getAdminById(id) {
    return this._get(
      this.mode === 'postgres'
        ? 'SELECT * FROM admin_users WHERE id = $1'
        : 'SELECT * FROM admin_users WHERE id = ?',
      [id]
    );
  }

  async createAdminUser(id, username, passwordHash, role = 'read_only') {
    const now = new Date().toISOString();
    if (this.mode === 'postgres') {
      await this.pool.query(
        `INSERT INTO admin_users (id, username, password_hash, role, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [id, username, passwordHash, role, now, now]
      );
    } else {
      this.db.prepare(
        `INSERT INTO admin_users (id, username, password_hash, role, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?)`
      ).run(id, username, passwordHash, role, now, now);
    }
  }

  async updateAdminLoginAttempts(adminId, attempts, lockedUntil = null) {
    const now = new Date().toISOString();
    if (this.mode === 'postgres') {
      await this.pool.query(
        `UPDATE admin_users SET failed_login_attempts = $1, locked_until = $2, updated_at = $3 WHERE id = $4`,
        [attempts, lockedUntil, now, adminId]
      );
    } else {
      this.db.prepare(
        `UPDATE admin_users SET failed_login_attempts = ?, locked_until = ?, updated_at = ? WHERE id = ?`
      ).run(attempts, lockedUntil, now, adminId);
    }
  }

  async updateAdminLastLogin(adminId) {
    const now = new Date().toISOString();
    if (this.mode === 'postgres') {
      await this.pool.query(
        `UPDATE admin_users SET last_login_at = $1, failed_login_attempts = 0, locked_until = NULL, updated_at = $1 WHERE id = $2`,
        [now, adminId]
      );
    } else {
      this.db.prepare(
        `UPDATE admin_users SET last_login_at = ?, failed_login_attempts = 0, locked_until = NULL, updated_at = ? WHERE id = ?`
      ).run(now, now, adminId);
    }
  }

  async listAdminUsers() {
    return this._all(
      this.mode === 'postgres'
        ? 'SELECT id, username, role, totp_enabled, last_login_at, created_at, is_active FROM admin_users ORDER BY created_at DESC'
        : 'SELECT id, username, role, totp_enabled, last_login_at, created_at, is_active FROM admin_users ORDER BY created_at DESC'
    );
  }

  async updateAdminUser(id, fields) {
    const now = new Date().toISOString();
    const sets = [];
    const params = [];
    let i = 1;

    const addField = (column, value) => {
      if (value === undefined) return;
      if (this.mode === 'postgres') {
        sets.push(`${column} = $${i++}`);
        params.push(value);
      } else {
        sets.push(`${column} = ?`);
        params.push(value);
      }
    };

    addField('role', fields.role);
    addField('password_hash', fields.passwordHash);
    addField('totp_secret', fields.totpSecret);
    addField('totp_enabled', fields.totpEnabled);
    addField('is_active', fields.isActive);

    if (sets.length === 0) return;

    if (this.mode === 'postgres') {
      sets.push(`updated_at = $${i++}`);
      params.push(now);
      params.push(id);
      await this.pool.query(
        `UPDATE admin_users SET ${sets.join(', ')} WHERE id = $${i}`,
        params
      );
    } else {
      sets.push('updated_at = ?');
      params.push(now);
      params.push(id);
      this.db.prepare(`UPDATE admin_users SET ${sets.join(', ')} WHERE id = ?`).run(...params);
    }
  }

  // ============================================================
  // AUDIT LOGGING
  // ============================================================

  async insertAuditLog(adminId, adminUsername, action, targetType, targetId, details, ipAddress) {
    const now = new Date().toISOString();
    if (this.mode === 'postgres') {
      await this.pool.query(
        `INSERT INTO admin_audit_logs (admin_id, admin_username, action, target_type, target_id, details, ip_address, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [adminId, adminUsername, action, targetType, targetId, details ? JSON.stringify(details) : null, ipAddress, now]
      );
    } else {
      this.db.prepare(
        `INSERT INTO admin_audit_logs (admin_id, admin_username, action, target_type, target_id, details, ip_address, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      ).run(adminId, adminUsername, action, targetType, targetId, details ? JSON.stringify(details) : null, ipAddress, now);
    }
  }

  async getAuditLogs({ adminId, action, limit = 100, offset = 0 } = {}) {
    let where = [];
    let params = [];
    let i = 1;

    if (adminId) {
      where.push(this.mode === 'postgres' ? `admin_id = $${i++}` : 'admin_id = ?');
      params.push(adminId);
    }
    if (action) {
      where.push(this.mode === 'postgres' ? `action = $${i++}` : 'action = ?');
      params.push(action);
    }

    const whereClause = where.length > 0 ? `WHERE ${where.join(' AND ')}` : '';

    if (this.mode === 'postgres') {
      params.push(limit, offset);
      return this._all(
        `SELECT * FROM admin_audit_logs ${whereClause} ORDER BY created_at DESC LIMIT $${i++} OFFSET $${i}`,
        params
      );
    }
    params.push(limit, offset);
    return this._all(
      `SELECT * FROM admin_audit_logs ${whereClause} ORDER BY created_at DESC LIMIT ? OFFSET ?`,
      params
    );
  }

  // ============================================================
  // LENDER MANAGEMENT (suspend/notes)
  // ============================================================

  async suspendUser(deviceId, reason) {
    const now = new Date().toISOString();
    if (this.mode === 'postgres') {
      await this.pool.query(
        `UPDATE users SET suspended = 1, suspended_reason = $1, last_seen_at = $2 WHERE device_id = $3`,
        [reason, now, deviceId]
      );
    } else {
      this.db.prepare(
        `UPDATE users SET suspended = 1, suspended_reason = ?, last_seen_at = ? WHERE device_id = ?`
      ).run(reason, now, deviceId);
    }
  }

  async unsuspendUser(deviceId) {
    const now = new Date().toISOString();
    if (this.mode === 'postgres') {
      await this.pool.query(
        `UPDATE users SET suspended = 0, suspended_reason = NULL, last_seen_at = $1 WHERE device_id = $2`,
        [now, deviceId]
      );
    } else {
      this.db.prepare(
        `UPDATE users SET suspended = 0, suspended_reason = NULL, last_seen_at = ? WHERE device_id = ?`
      ).run(now, deviceId);
    }
  }

  async updateUserAdminNotes(deviceId, notes) {
    const now = new Date().toISOString();
    if (this.mode === 'postgres') {
      await this.pool.query(
        `UPDATE users SET admin_notes = $1, last_seen_at = $2 WHERE device_id = $3`,
        [notes, now, deviceId]
      );
    } else {
      this.db.prepare(
        `UPDATE users SET admin_notes = ?, last_seen_at = ? WHERE device_id = ?`
      ).run(notes, now, deviceId);
    }
  }

  // ============================================================
  // EMAIL-LEVEL BLOCKING (cross-device enforcement)
  // ============================================================

  async suspendByEmail(email, reason, adminId, adminUsername) {
    await this.ready;
    const now = new Date().toISOString();

    // Insert or update email_blocks table
    if (this.mode === 'postgres') {
      await this.pool.query(
        `INSERT INTO email_blocks (email, reason, suspended_by, suspended_by_username, suspended_at)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (email) DO UPDATE SET
           reason = EXCLUDED.reason,
           suspended_by = EXCLUDED.suspended_by,
           suspended_by_username = EXCLUDED.suspended_by_username,
           suspended_at = EXCLUDED.suspended_at,
           unsuspended_at = NULL`,
        [email, reason, adminId, adminUsername, now]
      );

      // Suspend all users with this email
      await this.pool.query(
        `UPDATE users SET suspended = 1, suspended_reason = $1 WHERE email = $2`,
        [reason, email]
      );
    } else {
      this.db.prepare(
        `INSERT INTO email_blocks (email, reason, suspended_by, suspended_by_username, suspended_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT (email) DO UPDATE SET
           reason = excluded.reason,
           suspended_by = excluded.suspended_by,
           suspended_by_username = excluded.suspended_by_username,
           suspended_at = excluded.suspended_at,
           unsuspended_at = NULL`
      ).run(email, reason, adminId, adminUsername, now);

      // Suspend all users with this email
      this.db.prepare(
        `UPDATE users SET suspended = 1, suspended_reason = ? WHERE email = ?`
      ).run(reason, email);
    }
  }

  async unsuspendByEmail(email, adminId, adminUsername) {
    await this.ready;
    const now = new Date().toISOString();

    if (this.mode === 'postgres') {
      // Mark email block as unsuspended (keep record for audit)
      await this.pool.query(
        `UPDATE email_blocks SET unsuspended_at = $1 WHERE email = $2`,
        [now, email]
      );

      // Unsuspend all users with this email
      await this.pool.query(
        `UPDATE users SET suspended = 0, suspended_reason = NULL WHERE email = $1`,
        [email]
      );
    } else {
      // Mark email block as unsuspended (keep record for audit)
      this.db.prepare(
        `UPDATE email_blocks SET unsuspended_at = ? WHERE email = ?`
      ).run(now, email);

      // Unsuspend all users with this email
      this.db.prepare(
        `UPDATE users SET suspended = 0, suspended_reason = NULL WHERE email = ?`
      ).run(email);
    }
  }

  async isEmailBlocked(email) {
    await this.ready;
    if (!email) return { blocked: false, reason: null };

    const block = await this._get(
      this.mode === 'postgres'
        ? 'SELECT email, reason, suspended_at FROM email_blocks WHERE email = $1 AND unsuspended_at IS NULL'
        : 'SELECT email, reason, suspended_at FROM email_blocks WHERE email = ? AND unsuspended_at IS NULL',
      [email]
    );

    if (block) {
      return { blocked: true, reason: block.reason, suspendedAt: block.suspended_at };
    }
    return { blocked: false, reason: null };
  }

  async getEmailBlock(email) {
    await this.ready;
    return this._get(
      this.mode === 'postgres'
        ? 'SELECT * FROM email_blocks WHERE email = $1'
        : 'SELECT * FROM email_blocks WHERE email = ?',
      [email]
    );
  }

  async listEmailBlocks({ active = true, limit = 100, offset = 0 } = {}) {
    await this.ready;
    const whereClause = active ? 'WHERE unsuspended_at IS NULL' : '';
    
    if (this.mode === 'postgres') {
      return this._all(
        `SELECT * FROM email_blocks ${whereClause} ORDER BY suspended_at DESC LIMIT $1 OFFSET $2`,
        [limit, offset]
      );
    }
    return this._all(
      `SELECT * FROM email_blocks ${whereClause} ORDER BY suspended_at DESC LIMIT ? OFFSET ?`,
      [limit, offset]
    );
  }

  // ============================================================
  // BILLING: PLANS & SUBSCRIPTIONS
  // ============================================================

  async initializeDefaultPlans() {
    const existing = await this._all('SELECT id FROM plans LIMIT 1');
    if (existing.length > 0) return;

    const now = new Date().toISOString();
    const plans = [
      { id: 'free', name: 'Free', description: 'Basic plan with limited customers', customer_limit: 25, features: ['manual_backup'], price_monthly: 0, price_yearly: 0 },
      { id: 'pro', name: 'Pro', description: 'Unlimited customers with cloud sync', customer_limit: null, features: ['cloud_sync', 'priority_support', 'advanced_reports'], price_monthly: 29900, price_yearly: 299900 },
      { id: 'business', name: 'Business', description: 'Multi-device with premium features', customer_limit: null, features: ['cloud_sync', 'priority_support', 'advanced_reports', 'multi_device', 'api_access'], price_monthly: 49900, price_yearly: 499900 },
    ];

    for (const plan of plans) {
      if (this.mode === 'postgres') {
        await this.pool.query(
          `INSERT INTO plans (id, name, description, customer_limit, features, price_monthly, price_yearly, is_active, created_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, 1, $8)`,
          [plan.id, plan.name, plan.description, plan.customer_limit, JSON.stringify(plan.features), plan.price_monthly, plan.price_yearly, now]
        );
      } else {
        this.db.prepare(
          `INSERT INTO plans (id, name, description, customer_limit, features, price_monthly, price_yearly, is_active, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)`
        ).run(plan.id, plan.name, plan.description, plan.customer_limit, JSON.stringify(plan.features), plan.price_monthly, plan.price_yearly, now);
      }
    }
    console.log('Default plans initialized');
  }

  async listPlans() {
    return this._all(
      this.mode === 'postgres'
        ? 'SELECT * FROM plans WHERE is_active = 1 ORDER BY price_monthly ASC'
        : 'SELECT * FROM plans WHERE is_active = 1 ORDER BY price_monthly ASC'
    );
  }

  async getPlan(planId) {
    return this._get(
      this.mode === 'postgres'
        ? 'SELECT * FROM plans WHERE id = $1'
        : 'SELECT * FROM plans WHERE id = ?',
      [planId]
    );
  }

  async createSubscription(id, deviceId, email, planId, status = 'active') {
    const now = new Date().toISOString();
    if (this.mode === 'postgres') {
      await this.pool.query(
        `INSERT INTO subscriptions (id, device_id, email, plan_id, status, started_at, created_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [id, deviceId, email, planId, status, now, now, now]
      );
    } else {
      this.db.prepare(
        `INSERT INTO subscriptions (id, device_id, email, plan_id, status, started_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      ).run(id, deviceId, email, planId, status, now, now, now);
    }
  }

  async getSubscriptionByDevice(deviceId) {
    return this._get(
      this.mode === 'postgres'
        ? `SELECT s.*, p.name as plan_name, p.customer_limit, p.features
           FROM subscriptions s
           JOIN plans p ON s.plan_id = p.id
           WHERE s.device_id = $1
           ORDER BY s.created_at DESC
           LIMIT 1`
        : `SELECT s.*, p.name as plan_name, p.customer_limit, p.features
           FROM subscriptions s
           JOIN plans p ON s.plan_id = p.id
           WHERE s.device_id = ?
           ORDER BY s.created_at DESC
           LIMIT 1`,
      [deviceId]
    );
  }

  async getSubscriptionByEmail(email) {
    return this._get(
      this.mode === 'postgres'
        ? `SELECT s.*, p.name as plan_name, p.customer_limit, p.features
           FROM subscriptions s
           JOIN plans p ON s.plan_id = p.id
           WHERE s.email = $1 AND s.status = 'active'
           ORDER BY s.created_at DESC
           LIMIT 1`
        : `SELECT s.*, p.name as plan_name, p.customer_limit, p.features
           FROM subscriptions s
           JOIN plans p ON s.plan_id = p.id
           WHERE s.email = ? AND s.status = 'active'
           ORDER BY s.created_at DESC
           LIMIT 1`,
      [email]
    );
  }

  async updateSubscriptionStatus(subscriptionId, status, expiresAt = null) {
    const now = new Date().toISOString();
    if (this.mode === 'postgres') {
      await this.pool.query(
        `UPDATE subscriptions SET status = $1, expires_at = $2, updated_at = $3 WHERE id = $4`,
        [status, expiresAt, now, subscriptionId]
      );
    } else {
      this.db.prepare(
        `UPDATE subscriptions SET status = ?, expires_at = ?, updated_at = ? WHERE id = ?`
      ).run(status, expiresAt, now, subscriptionId);
    }
  }

  async assignPlanToDevice(deviceId, email, planId) {
    // Check if subscription exists
    const existing = await this.getSubscriptionByDevice(deviceId);
    const now = new Date().toISOString();
    
    if (existing) {
      // Update existing subscription
      if (this.mode === 'postgres') {
        await this.pool.query(
          `UPDATE subscriptions SET plan_id = $1, email = $2, status = 'active', updated_at = $3 WHERE device_id = $4`,
          [planId, email, now, deviceId]
        );
      } else {
        this.db.prepare(
          `UPDATE subscriptions SET plan_id = ?, email = ?, status = 'active', updated_at = ? WHERE device_id = ?`
        ).run(planId, email, now, deviceId);
      }
    } else {
      // Create new subscription
      const { v4: uuidv4 } = require('uuid');
      await this.createSubscription(uuidv4(), deviceId, email, planId, 'active');
    }
  }

  async listSubscriptions({ status, limit = 100, offset = 0 } = {}) {
    const whereClause = status ? (this.mode === 'postgres' ? 'WHERE s.status = $1' : 'WHERE s.status = ?') : '';
    const params = status ? [status] : [];

    if (this.mode === 'postgres') {
      const limitParam = status ? '$2' : '$1';
      const offsetParam = status ? '$3' : '$2';
      params.push(limit, offset);
      return this._all(
        `SELECT s.*, u.email as user_email, u.display_name, p.name as plan_name
         FROM subscriptions s
         LEFT JOIN users u ON s.device_id = u.device_id
         JOIN plans p ON s.plan_id = p.id
         ${whereClause}
         ORDER BY s.created_at DESC
         LIMIT ${limitParam} OFFSET ${offsetParam}`,
        params
      );
    }
    params.push(limit, offset);
    return this._all(
      `SELECT s.*, u.email as user_email, u.display_name, p.name as plan_name
       FROM subscriptions s
       LEFT JOIN users u ON s.device_id = u.device_id
       JOIN plans p ON s.plan_id = p.id
       ${whereClause}
       ORDER BY s.created_at DESC
       LIMIT ? OFFSET ?`,
      params
    );
  }

  async getSubscriptionStats() {
    const stats = await this._get(
      this.mode === 'postgres'
        ? `SELECT
            COUNT(*) FILTER (WHERE status = 'active')::int AS active_subscriptions,
            COUNT(*) FILTER (WHERE status = 'expired')::int AS expired_subscriptions,
            COUNT(*) FILTER (WHERE plan_id = 'free')::int AS free_plan_count,
            COUNT(*) FILTER (WHERE plan_id = 'pro')::int AS pro_plan_count,
            COUNT(*) FILTER (WHERE plan_id = 'business')::int AS business_plan_count
           FROM subscriptions`
        : `SELECT
            SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active_subscriptions,
            SUM(CASE WHEN status = 'expired' THEN 1 ELSE 0 END) AS expired_subscriptions,
            SUM(CASE WHEN plan_id = 'free' THEN 1 ELSE 0 END) AS free_plan_count,
            SUM(CASE WHEN plan_id = 'pro' THEN 1 ELSE 0 END) AS pro_plan_count,
            SUM(CASE WHEN plan_id = 'business' THEN 1 ELSE 0 END) AS business_plan_count
           FROM subscriptions`
    );
    return stats || { active_subscriptions: 0, expired_subscriptions: 0, free_plan_count: 0, pro_plan_count: 0, business_plan_count: 0 };
  }
}

module.exports = { AdminDatabase };
