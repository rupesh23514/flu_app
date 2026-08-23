require('dotenv').config();

const path = require('path');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { AdminDatabase } = require('./db');
const { createTelemetryRouter } = require('./routes/telemetry');
const { createAdminRouter } = require('./routes/admin');
const { setDatabase } = require('./middleware/auth');

const PORT = process.env.PORT || 3000;
const IS_VERCEL = !!process.env.VERCEL;

if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 16) {
  if (process.env.NODE_ENV === 'production') {
    console.error('FATAL: JWT_SECRET is missing or too short (min 16 chars). Refusing to start in production.');
    process.exit(1);
  }
  console.warn('WARNING: JWT_SECRET is missing or too short. Set it in .env before production.');
}

const app = express();
const db = new AdminDatabase();

// Initialize auth module with database for RBAC
setDatabase(db);

app.use(helmet({
  contentSecurityPolicy: false,
}));
app.use(cors());
app.use(express.json({ limit: '1mb' }));

// Ensure DB is ready before handling any request (important for Vercel cold starts)
app.use(async (_req, _res, next) => {
  try {
    await db.ready;
    next();
  } catch (err) {
    next(err);
  }
});

// Rate limiter for telemetry (higher limit for app traffic)
const telemetryLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false,
});

// Rate limiter for admin login (stricter for security)
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10, // 10 login attempts per 15 minutes
  message: { error: 'Too many login attempts. Please try again later.' },
  standardHeaders: true,
  legacyHeaders: false,
});

app.use('/api/v1/telemetry', telemetryLimiter, createTelemetryRouter(db));
app.use('/api/admin/login', loginLimiter);
app.use('/api/admin', createAdminRouter(db));

app.use(express.static(path.join(__dirname, '..', 'public')));

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString(), vercel: IS_VERCEL });
});

app.get('*', (_req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'index.html'));
});

// Export for Vercel serverless — Vercel calls the handler directly, not listen()
module.exports = app;

// Local dev: only call listen() when NOT on Vercel
if (!IS_VERCEL) {
  app.listen(PORT, async () => {
    console.log(`Admin dashboard running on port ${PORT}`);
    console.log(`Database mode: ${process.env.DATABASE_URL ? 'postgres' : 'sqlite'}`);

    // Initialize default billing plans
    try {
      await db.ready;
      await db.initializeDefaultPlans();
    } catch (err) {
      console.error('Failed to initialize plans:', err);
    }
  });
}
