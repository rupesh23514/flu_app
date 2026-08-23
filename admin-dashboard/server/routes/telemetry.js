const express = require('express');
const { requireTelemetryKey } = require('../middleware/auth');

function createTelemetryRouter(db) {
  const router = express.Router();

  router.use(requireTelemetryKey);

  // Helper function to check suspension status (email-level first, then device-level)
  async function checkSuspensionStatus(db, email, deviceId) {
    // First check email-level block (takes precedence)
    if (email) {
      const emailBlock = await db.isEmailBlocked(email);
      if (emailBlock.blocked) {
        return {
          suspended: true,
          suspendedReason: emailBlock.reason,
          scope: 'email',
        };
      }
    }

    // Then check device-level suspension
    if (deviceId) {
      const user = await db.getUser(deviceId);
      if (user?.suspended === 1) {
        return {
          suspended: true,
          suspendedReason: user.suspended_reason,
          scope: 'device',
        };
      }
    }

    return { suspended: false, suspendedReason: null, scope: null };
  }

  // Lightweight status check endpoint for app to verify suspension
  router.post('/status', async (req, res) => {
    try {
      const { deviceId, email } = req.body || {};

      if (!deviceId) {
        return res.status(400).json({ error: 'deviceId is required' });
      }

      const status = await checkSuspensionStatus(db, email, deviceId);
      
      res.json({
        ok: true,
        suspended: status.suspended,
        suspendedReason: status.suspendedReason,
      });
    } catch (err) {
      console.error('status check error:', err);
      res.status(500).json({ error: 'Failed to check status' });
    }
  });

  router.post('/heartbeat', async (req, res) => {
    try {
      const {
        deviceId,
        email,
        displayName,
        appVersion,
        platform,
        stats,
      } = req.body || {};

      if (!deviceId) {
        return res.status(400).json({ error: 'deviceId is required' });
      }

      const fields = {
        email,
        displayName,
        appVersion,
        platform: platform || 'android',
      };

      if (stats) {
        // Basic counts
        if (stats.customerCount !== undefined) fields.customerCount = stats.customerCount;
        if (stats.loanCount !== undefined) fields.loanCount = stats.loanCount;
        if (stats.activeLoanCount !== undefined) fields.activeLoanCount = stats.activeLoanCount;
        if (stats.overdueLoanCount !== undefined) fields.overdueLoanCount = stats.overdueLoanCount;
        if (stats.paymentCount !== undefined) fields.paymentCount = stats.paymentCount;
        
        // Financial aggregates
        if (stats.totalOutstanding !== undefined) fields.totalOutstanding = stats.totalOutstanding;
        if (stats.totalPrincipalOutstanding !== undefined) fields.totalPrincipalOutstanding = stats.totalPrincipalOutstanding;
        if (stats.totalInterestOutstanding !== undefined) fields.totalInterestOutstanding = stats.totalInterestOutstanding;
        if (stats.monthlyCollectionThisMonth !== undefined) fields.monthlyCollection = stats.monthlyCollectionThisMonth;
        
        // Loan type breakdown
        if (stats.loanTypeBreakdown !== undefined) fields.loanTypeBreakdown = stats.loanTypeBreakdown;
        
        // Backup info
        if (stats.backupCount !== undefined) fields.backupCount = stats.backupCount;
        if (stats.lastBackupAt !== undefined) fields.lastBackupAt = stats.lastBackupAt;
      }

      const existing = await db.getUser(deviceId);
      fields.sessionCount = (existing?.session_count ?? 0) + 1;

      await db.upsertUser(deviceId, fields);
      await db.insertEvent(deviceId, email, 'app_open', { appVersion, stats });

      // Check suspension status (email-level takes precedence)
      const status = await checkSuspensionStatus(db, email, deviceId);
      
      res.json({ 
        ok: true, 
        suspended: status.suspended,
        suspendedReason: status.suspendedReason,
      });
    } catch (err) {
      console.error('heartbeat error:', err);
      res.status(500).json({ error: 'Failed to record heartbeat' });
    }
  });

  router.post('/events', async (req, res) => {
    try {
      const { deviceId, email, displayName, appVersion, platform, events } = req.body || {};

      if (!deviceId || !Array.isArray(events) || events.length === 0) {
        return res.status(400).json({ error: 'deviceId and events[] are required' });
      }

      await db.upsertUser(deviceId, {
        email,
        displayName,
        appVersion,
        platform: platform || 'android',
      });

      for (const event of events.slice(0, 50)) {
        const type = event.type || event.eventType;
        if (!type) continue;

        const payload = event.payload || event.data || null;
        await db.insertEvent(deviceId, email, type, payload);

        switch (type) {
          case 'sign_in':
            await db.incrementUserCounter(deviceId, 'sign_in_count');
            await db.upsertUser(deviceId, {
              email,
              displayName,
              lastSignInAt: event.timestamp || new Date().toISOString(),
            });
            break;
          case 'sign_out':
            break;
          case 'backup_success':
            await db.incrementUserCounter(deviceId, 'backup_count');
            await db.upsertUser(deviceId, {
              lastBackupAt: event.timestamp || new Date().toISOString(),
            });
            break;
          case 'backup_failed':
            await db.incrementUserCounter(deviceId, 'backup_fail_count');
            break;
          case 'error':
            await db.incrementUserCounter(deviceId, 'error_count');
            break;
          case 'stats_sync':
            if (payload) {
              await db.upsertUser(deviceId, {
                // Basic counts
                customerCount: payload.customerCount,
                loanCount: payload.loanCount,
                activeLoanCount: payload.activeLoanCount,
                overdueLoanCount: payload.overdueLoanCount,
                paymentCount: payload.paymentCount,
                // Financial aggregates
                totalOutstanding: payload.totalOutstanding,
                totalPrincipalOutstanding: payload.totalPrincipalOutstanding,
                totalInterestOutstanding: payload.totalInterestOutstanding,
                monthlyCollection: payload.monthlyCollectionThisMonth,
                // Loan type breakdown
                loanTypeBreakdown: payload.loanTypeBreakdown,
                // Backup info
                backupCount: payload.backupCount,
                lastBackupAt: payload.lastBackupAt,
              });
            }
            break;
          default:
            break;
        }
      }

      // Check suspension status and include in response
      const status = await checkSuspensionStatus(db, email, deviceId);
      
      res.json({ 
        ok: true, 
        processed: events.length,
        suspended: status.suspended,
        suspendedReason: status.suspendedReason,
      });
    } catch (err) {
      console.error('events error:', err);
      res.status(500).json({ error: 'Failed to record events' });
    }
  });

  return router;
}

module.exports = { createTelemetryRouter };
