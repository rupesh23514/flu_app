// Safe JSON parse with fallback
function safeJsonParse(str, fallback) {
  try {
    return JSON.parse(str);
  } catch {
    return fallback;
  }
}

const state = {
  token: localStorage.getItem('adminToken'),
  username: localStorage.getItem('adminUsername'),
  role: localStorage.getItem('adminRole') || 'read_only',
  permissions: safeJsonParse(localStorage.getItem('adminPermissions'), ['view']),
  currentView: 'overview',
  usersData: [], // Cache for filtering/sorting
  lastRefreshedAt: null,   // Timestamp of last successful refresh
  autoRefreshTimer: null,  // setInterval handle
  tickTimer: null,         // setInterval for "X sec ago" counter
};

const els = {
  loginScreen: document.getElementById('loginScreen'),
  dashboard: document.getElementById('dashboard'),
  loginForm: document.getElementById('loginForm'),
  loginError: document.getElementById('loginError'),
  logoutBtn: document.getElementById('logoutBtn'),
  refreshBtn: document.getElementById('refreshBtn'),
  adminName: document.getElementById('adminName'),
  pageTitle: document.getElementById('pageTitle'),
  statsGrid: document.getElementById('statsGrid'),
  signInChart: document.getElementById('signInChart'),
  versionChart: document.getElementById('versionChart'),
  recentActivityTable: document.getElementById('recentActivityTable'),
  usersTable: document.getElementById('usersTable'),
  userSearch: document.getElementById('userSearch'),
  userFilter: document.getElementById('userFilter'),
  userSort: document.getElementById('userSort'),
  exportUsersBtn: document.getElementById('exportUsersBtn'),
  eventsTable: document.getElementById('eventsTable'),
  eventTypeFilter: document.getElementById('eventTypeFilter'),
  errorsTable: document.getElementById('errorsTable'),
  userModal: document.getElementById('userModal'),
  closeModalBtn: document.getElementById('closeModalBtn'),
  userProfileGrid: document.getElementById('userProfileGrid'),
  portfolioCards: document.getElementById('portfolioCards'),
  loanTypeChart: document.getElementById('loanTypeChart'),
  loanStatsGrid: document.getElementById('loanStatsGrid'),
  activityGrid: document.getElementById('activityGrid'),
  userEventsTable: document.getElementById('userEventsTable'),
  modalTitle: document.getElementById('modalTitle'),
  modalSubtitle: document.getElementById('modalSubtitle'),
  suspendedBadge: document.getElementById('suspendedBadge'),
  auditNavBtn: document.getElementById('auditNavBtn'),
  auditTable: document.getElementById('auditTable'),
  auditActionFilter: document.getElementById('auditActionFilter'),
  exportAuditBtn: document.getElementById('exportAuditBtn'),
  adminActionsSection: document.getElementById('adminActionsSection'),
  suspendBtn: document.getElementById('suspendBtn'),
  unsuspendBtn: document.getElementById('unsuspendBtn'),
  adminNotesInput: document.getElementById('adminNotesInput'),
  saveNotesBtn: document.getElementById('saveNotesBtn'),
  billingNavBtn: document.getElementById('billingNavBtn'),
  billingStatsGrid: document.getElementById('billingStatsGrid'),
  plansGrid: document.getElementById('plansGrid'),
  subscriptionsTable: document.getElementById('subscriptionsTable'),
  subscriptionStatusFilter: document.getElementById('subscriptionStatusFilter'),
  // Suspend modal elements
  suspendModal: document.getElementById('suspendModal'),
  closeSuspendModalBtn: document.getElementById('closeSuspendModalBtn'),
  suspendEmailDisplay: document.getElementById('suspendEmailDisplay'),
  suspendReasonInput: document.getElementById('suspendReasonInput'),
  cancelSuspendBtn: document.getElementById('cancelSuspendBtn'),
  confirmSuspendBtn: document.getElementById('confirmSuspendBtn'),
  noEmailWarning: document.getElementById('noEmailWarning'),
};

// Current user in modal (for actions)
let currentModalDeviceId = null;
let currentModalUserEmail = null;

function fmtDate(value) {
  if (!value) return '—';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value;
  return d.toLocaleString();
}

function fmtRelativeDate(value) {
  if (!value) return '—';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return value;
  const now = new Date();
  const diffMs = now - d;
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
  if (diffDays === 0) return 'Today';
  if (diffDays === 1) return 'Yesterday';
  if (diffDays < 7) return `${diffDays} days ago`;
  if (diffDays < 30) return `${Math.floor(diffDays / 7)} weeks ago`;
  return d.toLocaleDateString();
}

function fmtNum(value) {
  return Number(value || 0).toLocaleString();
}

function fmtMoney(value) {
  const num = Number(value || 0);
  if (num >= 10000000) return `₹${(num / 10000000).toFixed(2)} Cr`;
  if (num >= 100000) return `₹${(num / 100000).toFixed(2)} L`;
  if (num >= 1000) return `₹${(num / 1000).toFixed(1)} K`;
  return `₹${num.toLocaleString()}`;
}

async function api(path, options = {}) {
  const headers = {
    'Content-Type': 'application/json',
    ...(options.headers || {}),
  };
  if (state.token) headers.Authorization = `Bearer ${state.token}`;

  const res = await fetch(path, { ...options, headers });
  if (res.status === 401) {
    logout();
    throw new Error('Session expired');
  }
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || 'Request failed');
  return data;
}

function showDashboard() {
  els.loginScreen.classList.add('hidden');
  els.dashboard.classList.remove('hidden');
  els.adminName.textContent = state.username || 'Admin';
}

function logout() {
  stopAutoRefresh();
  state.token = null;
  state.username = null;
  state.role = 'read_only';
  state.permissions = ['view'];
  localStorage.removeItem('adminToken');
  localStorage.removeItem('adminUsername');
  localStorage.removeItem('adminRole');
  localStorage.removeItem('adminPermissions');
  els.dashboard.classList.add('hidden');
  els.loginScreen.classList.remove('hidden');
}

function startAutoRefresh() {
  stopAutoRefresh();
  // Auto-refresh data every 60 seconds
  state.autoRefreshTimer = setInterval(async () => {
    try {
      await refreshCurrentView();
    } catch (e) {
      // Silent fail — network may be temporarily unavailable
    }
  }, 60_000);
  // Tick the "X sec ago" label every second
  state.tickTimer = setInterval(updateLastRefreshedLabel, 1000);
}

function stopAutoRefresh() {
  if (state.autoRefreshTimer) { clearInterval(state.autoRefreshTimer); state.autoRefreshTimer = null; }
  if (state.tickTimer) { clearInterval(state.tickTimer); state.tickTimer = null; }
}

function markRefreshed() {
  state.lastRefreshedAt = Date.now();
  updateLastRefreshedLabel();
}

function updateLastRefreshedLabel() {
  if (!state.lastRefreshedAt) return;
  const sec = Math.round((Date.now() - state.lastRefreshedAt) / 1000);
  const label = sec < 5 ? 'just now' : sec < 60 ? `${sec}s ago` : `${Math.floor(sec / 60)}m ago`;
  if (els.refreshBtn) els.refreshBtn.title = `Last updated: ${label} — auto-refreshes every 60s`;
  // Update inline label if present
  const lbl = document.getElementById('lastUpdatedLabel');
  if (lbl) lbl.textContent = `Updated ${label}`;
}

function setView(view) {
  state.currentView = view;
  document.querySelectorAll('.nav-btn').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.view === view);
  });
  ['overview', 'users', 'events', 'errors', 'billing', 'audit'].forEach((name) => {
    const el = document.getElementById(`${name}View`);
    if (el) el.classList.toggle('hidden', name !== view);
  });
  const titles = {
    overview: 'Overview',
    users: 'Lenders',
    events: 'Activity Log',
    errors: 'Error Reports',
    billing: 'Billing & Plans',
    audit: 'Audit Logs',
  };
  els.pageTitle.textContent = titles[view];
}

function hasPermission(permission) {
  return state.permissions.includes(permission);
}

function updateUIForPermissions() {
  // Hide audit nav if no audit permission
  if (els.auditNavBtn) {
    els.auditNavBtn.classList.toggle('hidden', !hasPermission('audit'));
  }
  // Show role badge
  els.adminName.innerHTML = `${escapeHtml(state.username)} <span class="badge info">${state.role.replace('_', ' ')}</span>`;
}

function renderStats(overview) {
  const totalOutstanding = overview.total_principal_outstanding || 0;
  const monthlyCollection = overview.total_monthly_collection || 0;
  const backupHealth = overview.backup_health_percent || 0;
  
  const cards = [
    { label: 'Total Lenders', value: fmtNum(overview.total_users), variant: '' },
    { label: 'Signed-in', value: fmtNum(overview.signed_in_users), subtitle: `${overview.suspended_users || 0} suspended`, variant: '' },
    { label: 'Active Today', value: fmtNum(overview.active_today), subtitle: `WAU: ${fmtNum(overview.active_this_week)}, MAU: ${fmtNum(overview.active_this_month)}`, variant: '' },
    { label: 'Total Outstanding', value: fmtMoney(totalOutstanding), variant: 'highlight' },
    { label: 'Monthly Collection', value: fmtMoney(monthlyCollection), variant: '' },
    { label: 'Total Loans', value: fmtNum(overview.total_loans), subtitle: `${fmtNum(overview.active_loans)} active`, variant: '' },
    { label: 'Overdue Loans', value: fmtNum(overview.overdue_loans || 0), variant: overview.overdue_loans > 0 ? 'warning' : '' },
    { label: 'Backup Health', value: `${backupHealth}%`, subtitle: `${fmtNum(overview.backup_healthy_count)} healthy`, variant: backupHealth < 50 ? 'error' : backupHealth < 80 ? 'warning' : '' },
    { label: 'Total Customers', value: fmtNum(overview.total_customers), variant: '' },
    { label: 'Total Backups', value: fmtNum(overview.total_backups), subtitle: `${fmtNum(overview.total_backup_failures)} failed`, variant: '' },
    { label: 'Errors', value: fmtNum(overview.total_errors), variant: overview.total_errors > 0 ? 'error' : '' },
  ];

  els.statsGrid.innerHTML = cards.map(({ label, value, subtitle, variant }) => `
    <div class="stat-card ${variant}">
      <div class="label">${label}</div>
      <div class="value">${value}</div>
      ${subtitle ? `<div class="subtitle">${subtitle}</div>` : ''}
    </div>
  `).join('');
}

function renderVersionChart(versionData) {
  if (!versionData || !versionData.length) {
    els.versionChart.innerHTML = '<p style="color:#8fa0bf">No version data yet</p>';
    return;
  }
  
  const colors = ['#4caf50', '#64b5f6', '#ffb74d', '#ef5350', '#ab47bc', '#26a69a'];
  const total = versionData.reduce((sum, v) => sum + v.count, 0);
  
  els.versionChart.innerHTML = `
    <div class="pie-legend">
      ${versionData.map((v, i) => `
        <div class="pie-legend-item">
          <div class="pie-legend-color" style="background:${colors[i % colors.length]}"></div>
          <span>${escapeHtml(v.app_version || 'Unknown')}: ${v.count} (${Math.round(v.count / total * 100)}%)</span>
        </div>
      `).join('')}
    </div>
  `;
}

function renderSignInChart(trend) {
  if (!trend.length) {
    els.signInChart.innerHTML = '<p style="color:#8fa0bf">No sign-in data yet</p>';
    return;
  }
  const max = Math.max(...trend.map((t) => t.count), 1);
  els.signInChart.innerHTML = trend.map((item) => {
    const height = Math.max(8, Math.round((item.count / max) * 180));
    const day = String(item.day).slice(5);
    return `
      <div class="bar-col" title="${item.day}: ${item.count}">
        <div class="bar" style="height:${height}px"></div>
        <div class="bar-label">${day}</div>
      </div>
    `;
  }).join('');
}

function eventBadge(type) {
  const map = {
    sign_in: 'info',
    sign_out: 'warning',
    backup_success: 'success',
    backup_failed: 'error',
    app_open: 'info',
    stats_sync: 'info',
    error: 'error',
  };
  return `<span class="badge ${map[type] || 'info'}">${type}</span>`;
}

function renderEventsTable(container, events, showEmail = true) {
  if (!events.length) {
    container.innerHTML = '<p style="padding:16px;color:#8fa0bf">No events yet</p>';
    return;
  }

  container.innerHTML = `
    <table>
      <thead>
        <tr>
          <th>Time</th>
          ${showEmail ? '<th>Email</th>' : ''}
          <th>Type</th>
          <th>Details</th>
        </tr>
      </thead>
      <tbody>
        ${events.map((e) => `
          <tr>
            <td>${fmtDate(e.created_at)}</td>
            ${showEmail ? `<td>${e.email ? `<span class="email-chip">${escapeHtml(e.email)}</span>` : '—'}</td>` : ''}
            <td>${eventBadge(e.event_type)}</td>
            <td><code>${escapeHtml(formatPayload(e.payload))}</code></td>
          </tr>
        `).join('')}
      </tbody>
    </table>
  `;
}

function formatPayload(payload) {
  if (!payload) return '—';
  if (typeof payload === 'object') return JSON.stringify(payload);
  try {
    return JSON.stringify(JSON.parse(payload));
  } catch {
    return String(payload);
  }
}

function escapeHtml(text) {
  return String(text)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function filterAndSortUsers(users, filter, sort) {
  let filtered = [...users];
  
  // Apply filter
  switch (filter) {
    case 'signed_in':
      filtered = filtered.filter(u => u.email);
      break;
    case 'not_signed_in':
      filtered = filtered.filter(u => !u.email);
      break;
    case 'has_overdue':
      filtered = filtered.filter(u => (u.overdue_loan_count || 0) > 0);
      break;
    case 'backup_failing':
      filtered = filtered.filter(u => (u.backup_fail_count || 0) > 0);
      break;
    case 'inactive_7d':
      const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
      filtered = filtered.filter(u => !u.last_seen_at || new Date(u.last_seen_at) < sevenDaysAgo);
      break;
    case 'has_errors':
      filtered = filtered.filter(u => (u.error_count || 0) > 0);
      break;
  }
  
  // Apply sort
  switch (sort) {
    case 'outstanding':
      filtered.sort((a, b) => (b.total_principal_outstanding || 0) - (a.total_principal_outstanding || 0));
      break;
    case 'loan_count':
      filtered.sort((a, b) => (b.loan_count || 0) - (a.loan_count || 0));
      break;
    case 'customer_count':
      filtered.sort((a, b) => (b.customer_count || 0) - (a.customer_count || 0));
      break;
    case 'first_seen':
      filtered.sort((a, b) => new Date(a.first_seen_at || 0) - new Date(b.first_seen_at || 0));
      break;
    case 'last_seen':
    default:
      filtered.sort((a, b) => new Date(b.last_seen_at || 0) - new Date(a.last_seen_at || 0));
  }
  
  return filtered;
}

function renderUsersTable(users) {
  if (!users.length) {
    els.usersTable.innerHTML = '<p style="padding:16px;color:#8fa0bf">No lenders match the current filters</p>';
    return;
  }

  els.usersTable.innerHTML = `
    <table class="users-table">
      <thead>
        <tr>
          <th>Email</th>
          <th>Name</th>
          <th>Portfolio</th>
          <th>Loans</th>
          <th>Backups</th>
          <th>Last Active</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        ${users.map((u) => {
          const isSuspended = u.suspended === 1;
          const hasOverdue = (u.overdue_loan_count || 0) > 0;
          const backupFailing = (u.backup_fail_count || 0) > 0;
          
          return `
          <tr class="${isSuspended ? 'suspended' : ''}">
            <td>
              ${u.email ? `<span class="email-chip">${escapeHtml(u.email)}</span>` : '<span class="badge warning">Not signed in</span>'}
              ${isSuspended ? '<span class="badge error" style="margin-left:4px">Suspended</span>' : ''}
            </td>
            <td>${escapeHtml(u.display_name || '—')}</td>
            <td>
              <div>${fmtMoney(u.total_principal_outstanding || 0)}</div>
              <div class="subtitle">${fmtNum(u.customer_count)} customers</div>
            </td>
            <td>
              <div>${fmtNum(u.active_loan_count || 0)} active</div>
              ${hasOverdue ? `<div class="overdue-indicator">${fmtNum(u.overdue_loan_count)} overdue</div>` : '<div class="healthy-indicator">0 overdue</div>'}
            </td>
            <td>
              <div>${fmtNum(u.backup_count)} total</div>
              <div class="${backupFailing ? 'overdue-indicator' : 'healthy-indicator'}">${fmtNum(u.backup_fail_count)} failed</div>
            </td>
            <td>
              <div>${fmtRelativeDate(u.last_seen_at)}</div>
              <div class="subtitle">v${u.app_version || '?'}</div>
            </td>
            <td><button class="link-btn" data-device="${escapeHtml(u.device_id)}">View</button></td>
          </tr>
        `;}).join('')}
      </tbody>
    </table>
  `;

  els.usersTable.querySelectorAll('[data-device]').forEach((btn) => {
    btn.addEventListener('click', () => openUserModal(btn.dataset.device));
  });
}

function exportUsersCSV() {
  if (!state.usersData.length) return;
  
  const headers = ['Email', 'Display Name', 'Device ID', 'Customers', 'Loans', 'Active Loans', 'Overdue Loans', 'Outstanding', 'Backups', 'Backup Failures', 'Errors', 'First Seen', 'Last Seen', 'Last Backup', 'App Version'];
  
  const rows = state.usersData.map(u => [
    u.email || '',
    u.display_name || '',
    u.device_id,
    u.customer_count || 0,
    u.loan_count || 0,
    u.active_loan_count || 0,
    u.overdue_loan_count || 0,
    u.total_principal_outstanding || 0,
    u.backup_count || 0,
    u.backup_fail_count || 0,
    u.error_count || 0,
    u.first_seen_at || '',
    u.last_seen_at || '',
    u.last_backup_at || '',
    u.app_version || '',
  ]);
  
  const csvContent = [headers, ...rows]
    .map(row => row.map(cell => `"${String(cell).replace(/"/g, '""')}"`).join(','))
    .join('\n');
  
  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = `lenders_export_${new Date().toISOString().slice(0,10)}.csv`;
  link.click();
}

async function loadOverview() {
  const data = await api('/api/admin/overview');
  renderStats(data.overview);
  renderSignInChart(data.signInTrend || []);
  renderVersionChart(data.overview.version_distribution || []);
  const events = await api('/api/admin/events?limit=20');
  renderEventsTable(els.recentActivityTable, events.events);
}

async function loadUsers(search = '') {
  const data = await api(`/api/admin/users?search=${encodeURIComponent(search)}&limit=500`);
  state.usersData = data.users;
  applyUsersFilters();
}

function applyUsersFilters() {
  const search = els.userSearch.value.trim().toLowerCase();
  const filter = els.userFilter.value;
  const sort = els.userSort.value;
  
  let filtered = state.usersData;
  
  // Apply search
  if (search) {
    filtered = filtered.filter(u => 
      (u.email || '').toLowerCase().includes(search) ||
      (u.display_name || '').toLowerCase().includes(search) ||
      (u.device_id || '').toLowerCase().includes(search)
    );
  }
  
  // Apply filter and sort
  filtered = filterAndSortUsers(filtered, filter, sort);
  
  renderUsersTable(filtered);
}

async function loadEvents(type = '') {
  const query = type ? `?type=${encodeURIComponent(type)}&limit=200` : '?limit=200';
  const data = await api(`/api/admin/events${query}`);
  renderEventsTable(els.eventsTable, data.events);
}

async function loadErrors() {
  const data = await api('/api/admin/errors');
  renderEventsTable(els.errorsTable, data.events);
}

async function loadAuditLogs(action = '') {
  if (!hasPermission('audit')) {
    els.auditTable.innerHTML = '<p style="padding:16px;color:#8fa0bf">You do not have permission to view audit logs</p>';
    return;
  }
  const query = action ? `?action=${encodeURIComponent(action)}&limit=200` : '?limit=200';
  const data = await api(`/api/admin/audit-logs${query}`);
  renderAuditTable(data.logs);
}

function renderAuditTable(logs) {
  if (!logs.length) {
    els.auditTable.innerHTML = '<p style="padding:16px;color:#8fa0bf">No audit logs yet</p>';
    return;
  }

  els.auditTable.innerHTML = `
    <table>
      <thead>
        <tr>
          <th>Time</th>
          <th>Admin</th>
          <th>Action</th>
          <th>Target</th>
          <th>Details</th>
          <th>IP</th>
        </tr>
      </thead>
      <tbody>
        ${logs.map((log) => `
          <tr>
            <td>${fmtDate(log.created_at)}</td>
            <td>${escapeHtml(log.admin_username || log.admin_id)}</td>
            <td>${auditActionBadge(log.action)}</td>
            <td>${log.target_type ? `${escapeHtml(log.target_type)}:${escapeHtml(log.target_id || '')}` : '—'}</td>
            <td><code>${escapeHtml(formatPayload(log.details))}</code></td>
            <td>${escapeHtml(log.ip_address || '—')}</td>
          </tr>
        `).join('')}
      </tbody>
    </table>
  `;
}

function auditActionBadge(action) {
  const map = {
    login_success: 'success',
    login_failed: 'error',
    suspend_user: 'warning',
    unsuspend_user: 'info',
    update_notes: 'info',
    assign_plan: 'success',
  };
  return `<span class="badge ${map[action] || 'info'}">${escapeHtml(action)}</span>`;
}

// ============================================================
// BILLING
// ============================================================

async function loadBilling(statusFilter = '') {
  const [plansData, subsData] = await Promise.all([
    api('/api/admin/plans'),
    api(`/api/admin/subscriptions${statusFilter ? `?status=${statusFilter}` : ''}`),
  ]);

  renderPlans(plansData.plans);
  renderSubscriptions(subsData.subscriptions);
  renderBillingStats(subsData.stats);
}

function renderBillingStats(stats) {
  if (!els.billingStatsGrid) return;
  
  const cards = [
    { label: 'Active Subscriptions', value: fmtNum(stats.active_subscriptions || 0), variant: '' },
    { label: 'Free Plan', value: fmtNum(stats.free_plan_count || 0), variant: '' },
    { label: 'Pro Plan', value: fmtNum(stats.pro_plan_count || 0), variant: 'highlight' },
    { label: 'Business Plan', value: fmtNum(stats.business_plan_count || 0), variant: 'highlight' },
    { label: 'Expired', value: fmtNum(stats.expired_subscriptions || 0), variant: stats.expired_subscriptions > 0 ? 'warning' : '' },
  ];

  els.billingStatsGrid.innerHTML = cards.map(({ label, value, variant }) => `
    <div class="stat-card ${variant}">
      <div class="label">${label}</div>
      <div class="value">${value}</div>
    </div>
  `).join('');
}

function renderPlans(plans) {
  if (!els.plansGrid) return;
  if (!plans.length) {
    els.plansGrid.innerHTML = '<p style="padding:16px;color:#8fa0bf">No plans configured</p>';
    return;
  }

  els.plansGrid.innerHTML = plans.map((plan) => {
    const features = typeof plan.features === 'string' ? safeJsonParse(plan.features, []) : (plan.features || []);
    const priceMonthly = plan.price_monthly / 100;
    const isPopular = plan.id === 'pro';
    
    return `
      <div class="plan-card ${isPopular ? 'popular' : ''}">
        <div class="plan-name">${escapeHtml(plan.name)}</div>
        <div class="plan-price">${priceMonthly === 0 ? 'Free' : `₹${priceMonthly}`}</div>
        <div class="plan-price-period">${priceMonthly > 0 ? '/month' : 'forever'}</div>
        <div class="plan-description">${escapeHtml(plan.description || '')}</div>
        <div class="plan-features">
          ${features.map(f => `<div class="plan-feature">${escapeHtml(formatFeature(f))}</div>`).join('')}
        </div>
        <div class="plan-limit">
          ${plan.customer_limit ? `Up to ${fmtNum(plan.customer_limit)} customers` : 'Unlimited customers'}
        </div>
      </div>
    `;
  }).join('');
}

function formatFeature(feature) {
  const map = {
    manual_backup: 'Manual Google Drive backup',
    cloud_sync: 'Cloud sync',
    priority_support: 'Priority support',
    advanced_reports: 'Advanced reports',
    multi_device: 'Multi-device access',
    api_access: 'API access',
  };
  return map[feature] || feature.replace(/_/g, ' ');
}

function renderSubscriptions(subscriptions) {
  if (!els.subscriptionsTable) return;
  if (!subscriptions.length) {
    els.subscriptionsTable.innerHTML = '<p style="padding:16px;color:#8fa0bf">No subscriptions yet</p>';
    return;
  }

  els.subscriptionsTable.innerHTML = `
    <table>
      <thead>
        <tr>
          <th>Email</th>
          <th>Plan</th>
          <th>Status</th>
          <th>Started</th>
          <th>Expires</th>
        </tr>
      </thead>
      <tbody>
        ${subscriptions.map((s) => `
          <tr>
            <td>${s.email || s.user_email ? `<span class="email-chip">${escapeHtml(s.email || s.user_email)}</span>` : '—'}</td>
            <td><span class="badge info">${escapeHtml(s.plan_name || s.plan_id)}</span></td>
            <td>${subscriptionStatusBadge(s.status)}</td>
            <td>${fmtDate(s.started_at)}</td>
            <td>${s.expires_at ? fmtDate(s.expires_at) : '—'}</td>
          </tr>
        `).join('')}
      </tbody>
    </table>
  `;
}

function subscriptionStatusBadge(status) {
  const map = {
    active: 'success',
    expired: 'error',
    cancelled: 'warning',
    pending: 'info',
  };
  return `<span class="badge ${map[status] || 'info'}">${escapeHtml(status)}</span>`;
}

async function openUserModal(deviceId) {
  const data = await api(`/api/admin/users/${encodeURIComponent(deviceId)}`);
  const u = data.user;
  
  // Header
  els.modalTitle.textContent = u.display_name || u.email || 'Anonymous Lender';
  els.modalSubtitle.textContent = u.email || u.device_id;
  els.suspendedBadge.classList.toggle('hidden', u.suspended !== 1);
  
  // Profile section
  els.userProfileGrid.innerHTML = [
    ['Email', u.email || 'Not signed in'],
    ['Device ID', u.device_id],
    ['App Version', u.app_version || '—'],
    ['Platform', u.platform || 'android'],
    ['First Seen', fmtDate(u.first_seen_at)],
    ['Sessions', fmtNum(u.session_count)],
  ].map(([k, v]) => `
    <div class="detail-item"><div class="k">${k}</div><div class="v">${escapeHtml(String(v))}</div></div>
  `).join('');
  
  // Portfolio cards
  const principalOutstanding = u.total_principal_outstanding || 0;
  const interestOutstanding = u.total_interest_outstanding || 0;
  const monthlyCollection = u.monthly_collection || 0;
  
  els.portfolioCards.innerHTML = `
    <div class="portfolio-card">
      <div class="label">Total Outstanding</div>
      <div class="value money">${fmtMoney(principalOutstanding)}</div>
    </div>
    <div class="portfolio-card">
      <div class="label">Interest Outstanding</div>
      <div class="value">${fmtMoney(interestOutstanding)}</div>
    </div>
    <div class="portfolio-card">
      <div class="label">Monthly Collection</div>
      <div class="value">${fmtMoney(monthlyCollection)}</div>
    </div>
    <div class="portfolio-card">
      <div class="label">Customers</div>
      <div class="value">${fmtNum(u.customer_count)}</div>
    </div>
  `;
  
  // Loan breakdown
  let loanBreakdown = u.loan_type_breakdown;
  if (typeof loanBreakdown === 'string') {
    try { loanBreakdown = JSON.parse(loanBreakdown); } catch { loanBreakdown = null; }
  }
  
  const activeLoanCount = u.active_loan_count || 0;
  const overdueLoanCount = u.overdue_loan_count || 0;
  
  if (loanBreakdown && typeof loanBreakdown === 'object') {
    const regular = loanBreakdown.regular || 0;
    const monthly = loanBreakdown.monthly_interest || 0;
    const reducing = loanBreakdown.reducing || 0;
    const total = regular + monthly + reducing;
    
    els.loanTypeChart.innerHTML = total > 0 ? `
      <svg width="140" height="140" viewBox="0 0 140 140">
        ${createDonutChart([
          { value: regular, color: '#4caf50' },
          { value: monthly, color: '#64b5f6' },
          { value: reducing, color: '#ffb74d' },
        ], 70, 50, 20)}
      </svg>
      <div class="donut-chart-center">
        <div class="total">${total}</div>
        <div class="label">Active</div>
      </div>
    ` : '<div style="color:#8fa0bf">No active loans</div>';
    
    els.loanStatsGrid.innerHTML = `
      <div class="detail-item"><div class="k">Regular</div><div class="v" style="color:#4caf50">${fmtNum(regular)}</div></div>
      <div class="detail-item"><div class="k">Monthly Interest</div><div class="v" style="color:#64b5f6">${fmtNum(monthly)}</div></div>
      <div class="detail-item"><div class="k">Reducing</div><div class="v" style="color:#ffb74d">${fmtNum(reducing)}</div></div>
      <div class="detail-item"><div class="k">Overdue</div><div class="v ${overdueLoanCount > 0 ? 'overdue-indicator' : ''}">${fmtNum(overdueLoanCount)}</div></div>
    `;
  } else {
    els.loanTypeChart.innerHTML = `
      <div style="text-align:center;color:#8fa0bf">
        <div style="font-size:2rem;font-weight:700">${fmtNum(activeLoanCount)}</div>
        <div>Active loans</div>
      </div>
    `;
    els.loanStatsGrid.innerHTML = `
      <div class="detail-item"><div class="k">Total Loans</div><div class="v">${fmtNum(u.loan_count)}</div></div>
      <div class="detail-item"><div class="k">Active</div><div class="v">${fmtNum(activeLoanCount)}</div></div>
      <div class="detail-item"><div class="k">Overdue</div><div class="v ${overdueLoanCount > 0 ? 'overdue-indicator' : ''}">${fmtNum(overdueLoanCount)}</div></div>
      <div class="detail-item"><div class="k">Payments</div><div class="v">${fmtNum(u.payment_count)}</div></div>
    `;
  }
  
  // Activity section
  const backupHealthy = u.last_backup_at && (Date.now() - new Date(u.last_backup_at).getTime()) < 7 * 24 * 60 * 60 * 1000;
  
  els.activityGrid.innerHTML = `
    <div class="detail-item"><div class="k">Last Seen</div><div class="v">${fmtDate(u.last_seen_at)}</div></div>
    <div class="detail-item"><div class="k">Last Sign-in</div><div class="v">${fmtDate(u.last_sign_in_at)}</div></div>
    <div class="detail-item"><div class="k">Sign-in Count</div><div class="v">${fmtNum(u.sign_in_count)}</div></div>
    <div class="detail-item">
      <div class="k">Last Backup</div>
      <div class="v ${backupHealthy ? 'healthy-indicator' : 'overdue-indicator'}">${fmtDate(u.last_backup_at)}</div>
    </div>
    <div class="detail-item"><div class="k">Backup Success</div><div class="v">${fmtNum(u.backup_count)}</div></div>
    <div class="detail-item"><div class="k">Backup Failed</div><div class="v ${u.backup_fail_count > 0 ? 'overdue-indicator' : ''}">${fmtNum(u.backup_fail_count)}</div></div>
    <div class="detail-item"><div class="k">Errors</div><div class="v ${u.error_count > 0 ? 'overdue-indicator' : ''}">${fmtNum(u.error_count)}</div></div>
  `;

  // Admin actions section
  currentModalDeviceId = deviceId;
  currentModalUserEmail = u.email || null;
  
  // Show/hide admin actions based on permissions
  if (els.adminActionsSection) {
    const canSuspend = hasPermission('suspend');
    const canEditNotes = hasPermission('edit_notes');
    els.adminActionsSection.classList.toggle('hidden', !canSuspend && !canEditNotes);
    
    const hasEmail = !!u.email;
    const isSuspended = u.suspended === 1;
    
    if (els.suspendBtn) {
      // Show suspend button only if not suspended and has suspend permission
      els.suspendBtn.classList.toggle('hidden', isSuspended || !canSuspend);
      // Disable suspend button if user has no email
      els.suspendBtn.disabled = !hasEmail;
    }
    if (els.unsuspendBtn) {
      els.unsuspendBtn.classList.toggle('hidden', !isSuspended || !canSuspend);
    }
    // Show warning if user has no email (can't be suspended)
    if (els.noEmailWarning) {
      els.noEmailWarning.classList.toggle('hidden', hasEmail || isSuspended);
    }
    if (els.adminNotesInput) {
      els.adminNotesInput.value = u.admin_notes || '';
      els.adminNotesInput.disabled = !canEditNotes;
    }
    if (els.saveNotesBtn) {
      els.saveNotesBtn.classList.toggle('hidden', !canEditNotes);
    }
  }

  renderEventsTable(els.userEventsTable, data.events, false);
  els.userModal.classList.remove('hidden');
}

function createDonutChart(segments, cx, cy, radius) {
  const total = segments.reduce((sum, s) => sum + s.value, 0);
  if (total === 0) return '';
  
  let cumulativePercent = 0;
  const innerRadius = radius * 0.6;
  
  return segments.filter(s => s.value > 0).map(segment => {
    const percent = segment.value / total;
    const startAngle = cumulativePercent * 2 * Math.PI - Math.PI / 2;
    const endAngle = (cumulativePercent + percent) * 2 * Math.PI - Math.PI / 2;
    cumulativePercent += percent;
    
    const x1 = cx + radius * Math.cos(startAngle);
    const y1 = cy + radius * Math.sin(startAngle);
    const x2 = cx + radius * Math.cos(endAngle);
    const y2 = cy + radius * Math.sin(endAngle);
    const x3 = cx + innerRadius * Math.cos(endAngle);
    const y3 = cy + innerRadius * Math.sin(endAngle);
    const x4 = cx + innerRadius * Math.cos(startAngle);
    const y4 = cy + innerRadius * Math.sin(startAngle);
    
    const largeArc = percent > 0.5 ? 1 : 0;
    
    return `<path d="M ${x1} ${y1} A ${radius} ${radius} 0 ${largeArc} 1 ${x2} ${y2} L ${x3} ${y3} A ${innerRadius} ${innerRadius} 0 ${largeArc} 0 ${x4} ${y4} Z" fill="${segment.color}" />`;
  }).join('');
}

async function refreshCurrentView() {
  if (state.currentView === 'overview') await loadOverview();
  if (state.currentView === 'users') await loadUsers(els.userSearch.value.trim());
  if (state.currentView === 'events') await loadEvents(els.eventTypeFilter.value);
  if (state.currentView === 'errors') await loadErrors();
  if (state.currentView === 'billing') await loadBilling(els.subscriptionStatusFilter?.value || '');
  if (state.currentView === 'audit') await loadAuditLogs(els.auditActionFilter?.value || '');
  markRefreshed();
}

els.loginForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  els.loginError.textContent = '';
  try {
    const form = new FormData(els.loginForm);
    const result = await api('/api/admin/login', {
      method: 'POST',
      body: JSON.stringify({
        username: form.get('username'),
        password: form.get('password'),
      }),
    });
    state.token = result.token;
    state.username = result.username;
    state.role = result.role || 'read_only';
    state.permissions = result.permissions || ['view'];
    localStorage.setItem('adminToken', state.token);
    localStorage.setItem('adminUsername', state.username);
    localStorage.setItem('adminRole', state.role);
    localStorage.setItem('adminPermissions', JSON.stringify(state.permissions));
    showDashboard();
    updateUIForPermissions();
    setView('overview');
    await refreshCurrentView();
    startAutoRefresh();
  } catch (err) {
    els.loginError.textContent = err.message;
  }
});

document.querySelectorAll('.nav-btn').forEach((btn) => {
  btn.addEventListener('click', async () => {
    setView(btn.dataset.view);
    await refreshCurrentView();
  });
});

els.logoutBtn.addEventListener('click', logout);
els.refreshBtn.addEventListener('click', refreshCurrentView);
els.userSearch.addEventListener('input', debounce(() => applyUsersFilters(), 300));
els.userFilter.addEventListener('change', () => applyUsersFilters());
els.userSort.addEventListener('change', () => applyUsersFilters());
els.exportUsersBtn.addEventListener('click', exportUsersCSV);
els.eventTypeFilter.addEventListener('change', () => loadEvents(els.eventTypeFilter.value));
els.auditActionFilter?.addEventListener('change', () => loadAuditLogs(els.auditActionFilter.value));
els.subscriptionStatusFilter?.addEventListener('change', () => loadBilling(els.subscriptionStatusFilter.value));
els.closeModalBtn.addEventListener('click', () => els.userModal.classList.add('hidden'));
els.userModal.addEventListener('click', (e) => {
  if (e.target === els.userModal) els.userModal.classList.add('hidden');
});

// Suspend/Unsuspend handlers

// Open suspend modal when suspend button is clicked
els.suspendBtn?.addEventListener('click', () => {
  if (!currentModalDeviceId || !currentModalUserEmail) return;
  
  // Clear previous reason and show modal
  if (els.suspendReasonInput) {
    els.suspendReasonInput.value = '';
  }
  if (els.suspendEmailDisplay) {
    els.suspendEmailDisplay.textContent = currentModalUserEmail;
  }
  if (els.suspendModal) {
    els.suspendModal.classList.remove('hidden');
  }
});

// Close suspend modal handlers
els.closeSuspendModalBtn?.addEventListener('click', () => {
  els.suspendModal?.classList.add('hidden');
});

els.cancelSuspendBtn?.addEventListener('click', () => {
  els.suspendModal?.classList.add('hidden');
});

els.suspendModal?.addEventListener('click', (e) => {
  if (e.target === els.suspendModal) {
    els.suspendModal.classList.add('hidden');
  }
});

// Confirm suspend handler
els.confirmSuspendBtn?.addEventListener('click', async () => {
  if (!currentModalDeviceId || !currentModalUserEmail) return;
  
  const reason = els.suspendReasonInput?.value.trim();
  if (!reason) {
    alert('Please enter a reason for removal.');
    els.suspendReasonInput?.focus();
    return;
  }
  
  // Disable button to prevent double-click
  if (els.confirmSuspendBtn) {
    els.confirmSuspendBtn.disabled = true;
    els.confirmSuspendBtn.textContent = 'Removing...';
  }
  
  try {
    const result = await api(`/api/admin/users/${encodeURIComponent(currentModalDeviceId)}/suspend`, {
      method: 'POST',
      body: JSON.stringify({ reason }),
    });
    
    // Close both modals
    els.suspendModal?.classList.add('hidden');
    els.userModal?.classList.add('hidden');
    
    // Show success message
    alert(result.message || `Access removed for ${currentModalUserEmail}`);
    
    // Refresh users list
    await loadUsers();
  } catch (err) {
    alert('Failed to remove access: ' + err.message);
  } finally {
    // Re-enable button
    if (els.confirmSuspendBtn) {
      els.confirmSuspendBtn.disabled = false;
      els.confirmSuspendBtn.textContent = 'Remove Access';
    }
  }
});

els.unsuspendBtn?.addEventListener('click', async () => {
  if (!currentModalDeviceId) return;
  
  const email = currentModalUserEmail;
  const confirmMessage = email 
    ? `This will restore access for ALL devices using ${email}. Continue?`
    : 'Are you sure you want to restore access for this user?';
  
  if (!confirm(confirmMessage)) return;
  
  try {
    const result = await api(`/api/admin/users/${encodeURIComponent(currentModalDeviceId)}/unsuspend`, {
      method: 'POST',
    });
    alert(result.message || 'Access restored successfully');
    els.userModal.classList.add('hidden');
    await loadUsers();
  } catch (err) {
    alert('Failed to restore access: ' + err.message);
  }
});

els.saveNotesBtn?.addEventListener('click', async () => {
  if (!currentModalDeviceId) return;
  const notes = els.adminNotesInput.value.trim();
  
  try {
    await api(`/api/admin/users/${encodeURIComponent(currentModalDeviceId)}/notes`, {
      method: 'PUT',
      body: JSON.stringify({ notes }),
    });
    alert('Notes saved successfully');
  } catch (err) {
    alert('Failed to save notes: ' + err.message);
  }
});

function debounce(fn, ms) {
  let t;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}

if (state.token) {
  showDashboard();
  updateUIForPermissions();
  refreshCurrentView().catch(logout).then(() => startAutoRefresh());
}
