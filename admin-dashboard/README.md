# Money Lender Admin Dashboard

Web admin console + telemetry API for monitoring Android app users, Google sign-ins, backups, loan stats, and errors.

## Features

- **Overview Dashboard**: total devices, signed-in users, active today, customers, loans, backups, errors, version distribution chart
- **Users Table**: email visibility, customer/loan counts, backup history, last sign-in, filtering & sorting
- **User Detail Modal**: full device profile, portfolio summary, loan type breakdown, recent events
- **User Management**: suspend/unsuspend users by email (blocks all devices), internal admin notes
- **Email-Level Blocking**: suspend blocks ALL devices using the same Gmail account, with mandatory reason
- **Activity Log**: sign-in, backup, app open, stats sync, errors
- **Error Reports**: dedicated error stream from the mobile app
- **Audit Logs**: track admin actions (login, suspend, notes changes) with IP logging
- **Admin RBAC**: role-based access control (super_admin, support, finance, read_only)
- **Billing Preparation**: plans, subscriptions, and status tracking (Razorpay-ready)

## Local Development

```bash
cd admin-dashboard
cp .env.example .env
# Edit .env — set TELEMETRY_API_KEY, ADMIN_PASSWORD, JWT_SECRET
npm install
npm run dev
```

Open `http://localhost:3000` and sign in with your admin credentials.

Without `DATABASE_URL`, data is stored in `admin-dashboard/data/admin.db` (SQLite).

## Railway Deployment

### 1. Create Railway project

1. Go to [railway.app](https://railway.app) and create a new project
2. Add **PostgreSQL** plugin (recommended for production persistence)
3. Add a **GitHub repo** service or deploy from this folder:

```bash
cd admin-dashboard
railway login
railway init
railway add --database postgres
railway up
```

### 2. Set environment variables

In Railway → your service → **Variables**:

| Variable | Description |
|----------|-------------|
| `TELEMETRY_API_KEY` | Long random string — must match Flutter build |
| `ADMIN_USERNAME` | Admin login username (default: `admin`) |
| `ADMIN_PASSWORD` | Strong admin password |
| `JWT_SECRET` | Random string, min 32 characters |
| `DATABASE_URL` | Auto-set if you added Postgres plugin |
| `NODE_ENV` | `production` |

Railway sets `PORT` automatically.

### 3. Get your public URL

Railway → Settings → Networking → **Generate Domain**

Example: `https://flu-admin-production.up.railway.app`

### 4. Configure Flutter app

Build the APK with dart-define flags:

```bash
flutter build apk --release \
  --dart-define=ADMIN_API_URL=https://YOUR-RAILWAY-URL.up.railway.app \
  --dart-define=TELEMETRY_API_KEY=your-telemetry-key
```

Telemetry is disabled if either value is empty.

## API Endpoints

### Telemetry (mobile app)

- `POST /api/v1/telemetry/heartbeat` — app open + stats snapshot; returns `{ suspended, suspendedReason }`
- `POST /api/v1/telemetry/events` — batched events; returns `{ suspended, suspendedReason }`
- `POST /api/v1/telemetry/status` — lightweight suspension check; returns `{ suspended, suspendedReason }`

Header: `X-Telemetry-Key: <TELEMETRY_API_KEY>`

Event types: `sign_in`, `sign_out`, `backup_success`, `backup_failed`, `app_open`, `stats_sync`, `error`

**Suspension Enforcement**: The app checks suspension status on heartbeat, events, and status endpoints. When suspended, the app displays a block screen and prevents access to all features.

### Admin (dashboard)

- `POST /api/admin/login` — returns JWT + role + permissions
- `GET /api/admin/overview` — stats + sign-in trend + version distribution
- `GET /api/admin/users` — user list (searchable, filterable)
- `GET /api/admin/users/:deviceId` — user detail + events
- `POST /api/admin/users/:deviceId/suspend` — suspend user by email (blocks ALL devices with same email); requires `reason` in body
- `POST /api/admin/users/:deviceId/unsuspend` — unsuspend user by email (unblocks ALL devices with same email)
- `PUT /api/admin/users/:deviceId/notes` — update internal admin notes
- `GET /api/admin/events` — activity log
- `GET /api/admin/errors` — error log
- `GET /api/admin/audit-logs` — admin audit trail
- `GET /api/admin/admins` — list admin users
- `GET /api/admin/roles` — available roles & permissions
- `GET /api/admin/plans` — billing plans
- `GET /api/admin/subscriptions` — user subscriptions
- `GET /api/admin/subscriptions/:deviceId` — subscription for device
- `POST /api/admin/subscriptions/:deviceId/assign` — assign plan to device

Header: `Authorization: Bearer <token>`

Role-based permissions: `view`, `export`, `suspend`, `manage_admins`, `audit`, `edit_notes`

## User Suspension & Enforcement

### How it works

1. **Admin suspends a user** via the dashboard (Users → View → Remove Access)
2. **Email-level block** is created in the `email_blocks` table
3. **All devices** with that Gmail are marked as suspended
4. **App checks status** via telemetry endpoints (heartbeat, events, status)
5. **App shows block screen** when suspended, preventing all access

### Telemetry requirement

**IMPORTANT**: Remote suspension enforcement only works when the APK is built with telemetry enabled:

```bash
flutter build apk --release \
  --dart-define=ADMIN_API_URL=https://YOUR-URL.up.railway.app \
  --dart-define=TELEMETRY_API_KEY=your-key
```

APKs built without these flags cannot be remotely blocked. The suspension only applies to telemetry-enabled builds.

### Offline behavior

- If a user is suspended while online, the status is cached locally
- If the app goes offline while suspended, it remains blocked
- If offline and never suspended, the app continues to work (graceful degradation)
- On next online check, the status is refreshed from the server

### Data preservation

Suspension does NOT delete any data:
- Local SQLite database on phone: unchanged
- Google Drive backups: unchanged (admin has no Drive access)
- Admin telemetry stats: preserved for reporting
- Audit logs: preserved for compliance

Unsuspending restores access and all data remains intact.

## Security Notes

- Change all default secrets before production
- Use HTTPS only (Railway provides this)
- Telemetry key is embedded in the APK — treat it as an app attestation key, not a secret from reverse engineering
- Admin dashboard uses JWT with 12h expiry
- Suspension reasons are sanitized before display to prevent XSS
- Block screen cannot be bypassed via deep links (route guards in place)

## Project Structure

```
admin-dashboard/
  server/
    index.js          # Express entry
    db.js             # SQLite / Postgres adapter
    routes/
      telemetry.js    # Mobile ingestion
      admin.js        # Dashboard API
    middleware/
      auth.js         # API key + JWT auth
  public/
    index.html        # Admin UI
    app.js
    styles.css
```
