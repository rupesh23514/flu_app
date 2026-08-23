const express = require('express');
const { requireAdminAuth, requirePermission, handleAdminLogin, getClientIp, ROLE_PERMISSIONS } = require('../middleware/auth');

function createAdminRouter(db) {
  const router = express.Router();

  router.post('/login', handleAdminLogin);

  // All routes below require authentication
  router.use(requireAdminAuth);

  // ============================================================
  // OVERVIEW & ANALYTICS (view permission)
  // ============================================================

  router.get('/overview', requirePermission('view'), async (_req, res) => {
    try {
      const overview = await db.getOverview();
      const signInTrend = await db.getSignInTrend(14);
      res.json({ overview, signInTrend });
    } catch (err) {
      console.error('overview error:', err);
      res.status(500).json({ error: 'Failed to load overview' });
    }
  });

  // ============================================================
  // USER/LENDER MANAGEMENT
  // ============================================================

  router.get('/users', requirePermission('view'), async (req, res) => {
    try {
      const search = (req.query.search || '').trim();
      const limit = Math.min(parseInt(req.query.limit, 10) || 100, 500);
      const offset = Math.max(0, parseInt(req.query.offset, 10) || 0);
      const users = await db.listUsers({ search, limit, offset });
      res.json({ users, limit, offset });
    } catch (err) {
      console.error('users error:', err);
      res.status(500).json({ error: 'Failed to load users' });
    }
  });

  router.get('/users/:deviceId', requirePermission('view'), async (req, res) => {
    try {
      const user = await db.getUser(req.params.deviceId);
      if (!user) {
        return res.status(404).json({ error: 'User not found' });
      }
      const events = await db.getUserEvents(req.params.deviceId, 100);
      res.json({ user, events });
    } catch (err) {
      console.error('user detail error:', err);
      res.status(500).json({ error: 'Failed to load user' });
    }
  });

  router.post('/users/:deviceId/suspend', requirePermission('suspend'), async (req, res) => {
    try {
      const { reason } = req.body || {};
      const deviceId = req.params.deviceId;
      
      // Validate reason is provided and non-empty
      if (!reason || typeof reason !== 'string' || reason.trim().length === 0) {
        return res.status(400).json({ error: 'Reason is required for suspension' });
      }
      
      // Limit reason length
      const sanitizedReason = reason.trim().slice(0, 500);
      
      const user = await db.getUser(deviceId);
      if (!user) {
        return res.status(404).json({ error: 'User not found' });
      }

      // Require email for email-level blocking
      if (!user.email) {
        return res.status(400).json({ 
          error: 'Cannot suspend user without email. User must sign in with Google first.' 
        });
      }

      // Use email-level blocking to block all devices with this email
      await db.suspendByEmail(user.email, sanitizedReason, req.admin.id, req.admin.username);
      
      await db.insertAuditLog(
        req.admin.id, 
        req.admin.username, 
        'suspend_user', 
        'user', 
        deviceId, 
        { reason: sanitizedReason, email: user.email, scope: 'email_block' }, 
        getClientIp(req)
      );

      res.json({ 
        ok: true, 
        message: `Access removed for all devices using ${user.email}`,
        email: user.email
      });
    } catch (err) {
      console.error('suspend error:', err);
      res.status(500).json({ error: 'Failed to suspend user' });
    }
  });

  router.post('/users/:deviceId/unsuspend', requirePermission('suspend'), async (req, res) => {
    try {
      const deviceId = req.params.deviceId;
      
      const user = await db.getUser(deviceId);
      if (!user) {
        return res.status(404).json({ error: 'User not found' });
      }

      if (!user.email) {
        // Fallback to device-level unsuspend if no email
        await db.unsuspendUser(deviceId);
        await db.insertAuditLog(
          req.admin.id, 
          req.admin.username, 
          'unsuspend_user', 
          'user', 
          deviceId, 
          { scope: 'device_only' }, 
          getClientIp(req)
        );
        return res.json({ ok: true, message: 'User unsuspended (device only)' });
      }

      // Use email-level unblocking to restore access for all devices
      await db.unsuspendByEmail(user.email, req.admin.id, req.admin.username);
      
      await db.insertAuditLog(
        req.admin.id, 
        req.admin.username, 
        'unsuspend_user', 
        'user', 
        deviceId, 
        { email: user.email, scope: 'email_unblock' }, 
        getClientIp(req)
      );

      res.json({ 
        ok: true, 
        message: `Access restored for all devices using ${user.email}`,
        email: user.email
      });
    } catch (err) {
      console.error('unsuspend error:', err);
      res.status(500).json({ error: 'Failed to unsuspend user' });
    }
  });

  router.put('/users/:deviceId/notes', requirePermission('edit_notes'), async (req, res) => {
    try {
      const { notes } = req.body || {};
      const deviceId = req.params.deviceId;
      
      const user = await db.getUser(deviceId);
      if (!user) {
        return res.status(404).json({ error: 'User not found' });
      }

      await db.updateUserAdminNotes(deviceId, notes);
      await db.insertAuditLog(
        req.admin.id, 
        req.admin.username, 
        'update_notes', 
        'user', 
        deviceId, 
        { hasNotes: !!notes }, 
        getClientIp(req)
      );

      res.json({ ok: true, message: 'Notes updated' });
    } catch (err) {
      console.error('notes error:', err);
      res.status(500).json({ error: 'Failed to update notes' });
    }
  });

  // ============================================================
  // EVENTS & ERRORS
  // ============================================================

  router.get('/events', requirePermission('view'), async (req, res) => {
    try {
      const type = req.query.type || null;
      const limit = Math.min(parseInt(req.query.limit, 10) || 100, 500);
      const events = await db.getRecentEvents({ type, limit });
      res.json({ events });
    } catch (err) {
      console.error('events list error:', err);
      res.status(500).json({ error: 'Failed to load events' });
    }
  });

  router.get('/errors', requirePermission('view'), async (_req, res) => {
    try {
      const events = await db.getRecentEvents({ type: 'error', limit: 200 });
      res.json({ events });
    } catch (err) {
      console.error('errors error:', err);
      res.status(500).json({ error: 'Failed to load errors' });
    }
  });

  // ============================================================
  // AUDIT LOGS
  // ============================================================

  router.get('/audit-logs', requirePermission('audit'), async (req, res) => {
    try {
      const adminId = req.query.adminId || null;
      const action = req.query.action || null;
      const limit = Math.min(parseInt(req.query.limit, 10) || 100, 500);
      const offset = Math.max(0, parseInt(req.query.offset, 10) || 0);
      
      const logs = await db.getAuditLogs({ adminId, action, limit, offset });
      res.json({ logs, limit, offset });
    } catch (err) {
      console.error('audit logs error:', err);
      res.status(500).json({ error: 'Failed to load audit logs' });
    }
  });

  // ============================================================
  // ADMIN USER MANAGEMENT
  // ============================================================

  router.get('/admins', requirePermission('manage_admins'), async (_req, res) => {
    try {
      const admins = await db.listAdminUsers();
      res.json({ admins });
    } catch (err) {
      console.error('list admins error:', err);
      res.status(500).json({ error: 'Failed to load admins' });
    }
  });

  router.get('/roles', requirePermission('view'), (_req, res) => {
    res.json({ 
      roles: Object.keys(ROLE_PERMISSIONS),
      permissions: ROLE_PERMISSIONS,
    });
  });

  // ============================================================
  // BILLING: PLANS & SUBSCRIPTIONS
  // ============================================================

  router.get('/plans', requirePermission('view'), async (_req, res) => {
    try {
      const plans = await db.listPlans();
      res.json({ plans });
    } catch (err) {
      console.error('list plans error:', err);
      res.status(500).json({ error: 'Failed to load plans' });
    }
  });

  router.get('/subscriptions', requirePermission('view'), async (req, res) => {
    try {
      const status = req.query.status || null;
      const limit = Math.min(parseInt(req.query.limit, 10) || 100, 500);
      const offset = Math.max(0, parseInt(req.query.offset, 10) || 0);
      
      const subscriptions = await db.listSubscriptions({ status, limit, offset });
      const stats = await db.getSubscriptionStats();
      
      res.json({ subscriptions, stats, limit, offset });
    } catch (err) {
      console.error('list subscriptions error:', err);
      res.status(500).json({ error: 'Failed to load subscriptions' });
    }
  });

  router.get('/subscriptions/:deviceId', requirePermission('view'), async (req, res) => {
    try {
      const subscription = await db.getSubscriptionByDevice(req.params.deviceId);
      res.json({ subscription });
    } catch (err) {
      console.error('get subscription error:', err);
      res.status(500).json({ error: 'Failed to load subscription' });
    }
  });

  router.post('/subscriptions/:deviceId/assign', requirePermission('manage_admins'), async (req, res) => {
    try {
      const { planId } = req.body || {};
      const deviceId = req.params.deviceId;
      
      if (!planId) {
        return res.status(400).json({ error: 'planId is required' });
      }

      const plan = await db.getPlan(planId);
      if (!plan) {
        return res.status(404).json({ error: 'Plan not found' });
      }

      const user = await db.getUser(deviceId);
      if (!user) {
        return res.status(404).json({ error: 'User not found' });
      }

      await db.assignPlanToDevice(deviceId, user.email, planId);
      await db.insertAuditLog(
        req.admin.id, 
        req.admin.username, 
        'assign_plan', 
        'subscription', 
        deviceId, 
        { planId, email: user.email }, 
        getClientIp(req)
      );

      res.json({ ok: true, message: `Plan ${plan.name} assigned to user` });
    } catch (err) {
      console.error('assign plan error:', err);
      res.status(500).json({ error: 'Failed to assign plan' });
    }
  });

  return router;
}

module.exports = { createAdminRouter };
