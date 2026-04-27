// ── core.js — Config, Helpers, Shared State ────────────────────────
// No static imports — this is a near-leaf module. Uses dynamic import for closePanel.

// ── Config ──────────────────────────────────────────────────────────
export const REFRESH_MS = 1 * 60 * 1000;
export const EMAIL_PAGE_SIZE = 25;
export const CAL_PAGE_SIZE = 200;  // Calendar events are few (~50-200), load all at once for correct client-side sort
export const TASK_SECTIONS = ['In Progress', 'To Do', 'Backlog'];
export const DASHBOARD_URL = 'http://localhost:8080/dashboard';

// API base — empty = same origin (served by nginx at /dashboard)
export const BASE = '';

// ── Open in Browse Lite ──────────────────────────────────────────────
export function openDashboard() {
  window.open(DASHBOARD_URL, '_blank');
}

// ── Helpers ─────────────────────────────────────────────────────────
export function fmtDate(raw) {
  if (!raw) return '';
  try {
    const d = new Date(raw);
    const now = new Date();
    const diff = (now - d) / 86400000;
    if (diff < 1) return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    if (diff < 7) return d.toLocaleDateString([], { weekday: 'short', hour: '2-digit', minute: '2-digit' });
    return d.toLocaleDateString([], { day: '2-digit', month: 'short' });
  } catch { return raw.slice(0, 10); }
}

export function fmtDatetime(raw) {
  if (!raw) return '';
  try {
    const d = new Date(raw);
    return d.toLocaleDateString([], { weekday: 'short', day: '2-digit', month: 'short' })
      + ' · ' + d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  } catch { return raw; }
}

export function isUpcoming(raw) {
  if (!raw) return true;
  try { return new Date(raw) >= new Date(Date.now() - 86400000); }
  catch { return true; }
}

export function escHtml(s) {
  return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

/** Strip HTML tags and decode entities — returns clean plain text */
export function stripHtml(s) {
  if (!s) return '';
  var tmp = document.createElement('div');
  tmp.innerHTML = s;
  var text = tmp.textContent || tmp.innerText || '';
  // Collapse whitespace and trim
  return text.replace(/\s+/g, ' ').trim();
}

/** Clean snippet for list preview: strip HTML, remove long tracking URLs, truncate */
export function cleanSnippet(s, maxLen) {
  if (!s) return '';
  var text = stripHtml(s);
  // Remove long URL-encoded tracking params (LinkedIn, etc)
  text = text.replace(/https?:\/\/[^\s]{120,}/g, '[link]');
  // Remove remaining URLs longer than 80 chars
  text = text.replace(/https?:\/\/[^\s]{80,}/g, '[link]');
  // Collapse separators like --------
  text = text.replace(/-{5,}/g, '—');
  maxLen = maxLen || 150;
  if (text.length > maxLen) text = text.substring(0, maxLen) + '…';
  return text;
}

/** Check if a string looks like HTML content */
export function isHtml(s) {
  return s && (s.trimStart().startsWith('<!DOCTYPE') || s.trimStart().startsWith('<html') || /<[a-z][a-z0-9]*[\s>]/i.test(s));
}

/** Encode data as base64 for safe embedding in HTML attributes */
export function encKiloData(obj) {
  return btoa(unescape(encodeURIComponent(JSON.stringify(obj))));
}
export function decKiloData(b64) {
  return JSON.parse(decodeURIComponent(escape(atob(b64))));
}

export function tagClass(tag) {
  const t = tag.toLowerCase();
  if (t.includes('infra')) return 'infra';
  if (t.includes('bug')) return 'bug';
  if (t.includes('security')) return 'security';
  if (t.includes('research')) return 'research';
  if (t.includes('ux')) return 'ux';
  return '';
}

export function setCount(id, n) {
  document.getElementById(id).textContent = n;
  // Mirror into stats bar (but NOT mail — that uses real Gmail unread count)
  if (id === 'cal-count') document.getElementById('stat-cal').textContent = n;
  if (id === 'task-count') document.getElementById('stat-tasks').textContent = n;
}

/** FIX-3: Update calendar stat card to show today's events (stat) vs total upcoming (label) */
export function updateCalStat(todayCount, totalUpcoming) {
  const valEl = document.getElementById('stat-cal');
  const labelEl = document.getElementById('stat-cal-label');
  if (valEl) valEl.textContent = todayCount;
  if (labelEl) {
    const upcomingOther = totalUpcoming - todayCount;
    labelEl.textContent = upcomingOther > 0
      ? `Today's Events · ${upcomingOther} upcoming`
      : `Today's Events`;
  }
}

export function setBody(id, html) {
  document.getElementById(id).innerHTML = html;
}

/** Append HTML into a container (for infinite scroll) */
export function appendBody(id, html) {
  // Insert before the sentinel element if it exists
  const container = document.getElementById(id);
  const sentinel = container.querySelector('.scroll-sentinel');
  if (sentinel) {
    sentinel.insertAdjacentHTML('beforebegin', html);
  } else {
    container.insertAdjacentHTML('beforeend', html);
  }
}

// ── Scroll Sentinel (shared by mail + calendar infinite scroll) ────
export function updateSentinel(containerId, hasMore, loading) {
  const container = document.getElementById(containerId);
  let sentinel = container.querySelector('.scroll-sentinel');
  if (!sentinel) {
    sentinel = document.createElement('div');
    sentinel.className = 'scroll-sentinel';
    container.appendChild(sentinel);
  }
  if (!hasMore) {
    sentinel.innerHTML = '<span class="scroll-end">All loaded</span>';
    sentinel.classList.remove('loading');
  } else if (loading) {
    sentinel.innerHTML = '<div class="scroll-spinner"></div>';
    sentinel.classList.add('loading');
  } else {
    sentinel.innerHTML = '<div class="scroll-spinner"></div>';
    sentinel.classList.remove('loading');
  }
}

// ── Shared Tier State ──────────────────────────────────────────────
// Lives here (not app.js) to avoid circular imports from ideas.js
export let _isPro = false;
export function setIsPro(val) { _isPro = val; }

// ── Toast (used by mail, kilo, app — lives here to avoid circular deps)
export function showToast(msg) {
  const existing = document.querySelector('.kilo-toast');
  if (existing) existing.remove();
  const t = document.createElement('div');
  t.className = 'kilo-toast';
  t.textContent = msg;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 2500);
}

/** Event delegation for panel close buttons — survives Browse Lite focus theft */
document.getElementById('panel-container').addEventListener('click', async (e) => {
  const closeBtn = e.target.closest('.panel-close');
  if (closeBtn) {
    const panel = closeBtn.closest('.floating-panel');
    if (panel && panel.dataset.panelKey) {
      const { closePanel } = await import('./panels.js');
      closePanel(panel.dataset.panelKey);
    }
  }
});

/**
 * Open external URL via URL relay inside Docker.
 * Dashboard → nginx /api/open-url → vs-code:18099 (url-relay.py)
 *   → writes to shared file → host watcher → macOS `open` command.
 * Uses delegated event listener (CSP-safe, no inline onclick needed).
 */
document.getElementById('panel-container').addEventListener('click', function (e) {
  var el = e.target.closest('[data-ext-url]');
  if (!el) return;
  e.preventDefault();
  e.stopPropagation();
  var url = el.getAttribute('data-ext-url');
  fetch('/api/open-url?url=' + encodeURIComponent(url))
    .then(function (r) {
      if (r.ok) showToast('\u2713 Opened in browser');
      else window.open(url, '_blank');
    })
    .catch(function () { window.open(url, '_blank'); });
});

// Dismiss menu on click outside or Escape (dismissMenu lives in kilo.js)
document.addEventListener('click', async () => {
  const { dismissMenu } = await import('./kilo.js');
  dismissMenu();
});
document.addEventListener('keydown', async (e) => {
  if (e.key === 'Escape') {
    const { dismissMenu } = await import('./kilo.js');
    dismissMenu();
  }
});

// ── Window exports (HTML onclick handlers) ──
window.openDashboard = openDashboard;
window.showToast = showToast;
