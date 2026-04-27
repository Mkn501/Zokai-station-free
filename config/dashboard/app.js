// ── app.js — Boot Orchestrator ─────────────────────────────────────
// Initializes the application, handles global layout, and bootstrap connections.

import { BASE, REFRESH_MS, escHtml, setBody, setIsPro, _isPro, showToast } from './core.js?v=3';
import { createPanel } from './panels.js?v=3';
import { loadMail, loadUnreadCount, loadDrafts, fetchMailEpochIndex,
         resetMailState, getMailState } from './mail.js?v=4';
import { loadCalendar, forceReloadCalendar, getCalState, resetCalState } from './calendar.js?v=4';
import { loadTasks, getTaskState, resetTaskState } from './tasks.js?v=3';
import { loadIdeas, getIdeasState, isEditing } from './ideas.js?v=3';
// kilo.js is loaded via side-effect (registers event handlers)
import './kilo.js?v=3';

let _sseConnections = [];

export function registerSSEConnection(es) {
    if (es && es.readyState !== EventSource.CLOSED) {
        _sseConnections.push(es);
    }
}

export function closeAllSSE() {
    _sseConnections.forEach(es => {
        if (es && es.readyState !== EventSource.CLOSED) {
            console.log('[SSE] Forcing connection close to free connections');
            es.close();
        }
    });
    _sseConnections = [];
}

window.addEventListener('pagehide', () => {
    closeAllSSE();
});

/** Connect to SSE streams for real-time updates (ideas, calendar, mail) */
function connectSSE() {
    // Ideas stream — debounce to avoid jittery re-renders
    let _ideasDebounce = null;
    const ideasES = new EventSource(`${BASE}/api/ideas/stream`);
    ideasES.onmessage = () => {
        if (isEditing()) return;
        if (_ideasDebounce) clearTimeout(_ideasDebounce);
        _ideasDebounce = setTimeout(() => {
            loadIdeas();
            _ideasDebounce = null;
        }, 1500);
    };
    registerSSEConnection(ideasES);

    // Calendar stream
    const calES = new EventSource(`${BASE}/api/calendar-events/stream`);
    calES.onmessage = () => { forceReloadCalendar(); };
    registerSSEConnection(calES);

    // Mail drafts stream
    const mailES = new EventSource(`${BASE}/api/mail/drafts/stream`);
    mailES.onmessage = () => { loadMail(true); };
    registerSSEConnection(mailES);

    console.log('[SSE] Connected to ideas, calendar, mail streams');
}

export function toggleSidebar() {
    document.querySelector('.sidebar').classList.toggle('collapsed');
}

export function switchTab(tabId) {
    document.querySelectorAll('.tab-panel').forEach(c => c.classList.remove('active'));
    document.querySelectorAll('.tab-btn').forEach(t => t.classList.remove('active'));
    
    document.getElementById(`tab-${tabId}`)?.classList.add('active');
    document.querySelector(`.tab-btn[data-tab="${tabId}"]`)?.classList.add('active');
}

export function loadStationHealth() {
    const healthNum = document.getElementById('health-num');
    const healthFill = document.getElementById('health-fill');
    
    // Simulate some logic checking services
    const mailOk = getMailState().lastFetched > 0;
    const calOk = getCalState().lastFetched > 0;
    const taskOk = getTaskState().lastFetched > 0;
    const ideasOk = getIdeasState().lastFetched > 0;
    
    let score = 60; // Base score
    if(mailOk) score += 10;
    if(calOk) score += 10;
    if(taskOk) score += 10;
    if(ideasOk) score += 10;
    
    if(healthNum) healthNum.textContent = `${score}/100`;
    if(healthFill) {
        healthFill.style.width = `${score}%`;
        if(score >= 90) healthFill.style.background = 'var(--accent-green)';
        else if (score >= 70) healthFill.style.background = 'var(--text-secondary)';
        else healthFill.style.background = 'var(--accent-red)';
    }
}

export async function init() {
    console.log("[App] Booting Modular Dashboard...");
    
    // Check Pro status by probing gap-indexer through reverse proxy
    let gapHealth = null;
    try {
        const resp = await fetch(`${BASE}/api/gap-indexer/health`);
        setIsPro(resp.ok);
        if (resp.ok) gapHealth = await resp.json();
    } catch {
        setIsPro(false);
    }

    // Update Deep Index stat card based on Pro probe result
    const diValue  = document.getElementById('stat-deep-index-value');
    const diStatus = document.getElementById('stat-deep-index-status');
    const diIcon   = document.getElementById('stat-deep-index-icon');
    if (_isPro && diValue && diStatus) {
        document.body.classList.add('is-pro');
        diValue.textContent = 'On';
        diValue.style.opacity = '1';
        diValue.style.color = 'var(--accent-green, #22c55e)';
        if (diIcon) { diIcon.classList.remove('di-free'); diIcon.classList.add('di-pro'); }
        // Show last scan info if available
        const lastScan = gapHealth?.last_scan;
        if (lastScan) {
            const d = new Date(lastScan.timestamp * 1000);
            const timeStr = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            diStatus.innerHTML = `<span style="font-size:11px;color:var(--text-secondary)">Last scan ${timeStr} &middot; ${lastScan.files} file(s)</span>`;
        } else {
            diStatus.innerHTML = `<span style="font-size:11px;color:var(--text-secondary)">Active &mdash; watching workspace</span>`;
        }
    }
    
    console.log("[App] Initializing Modules...");
    
    // Phase 1: Load body content (mail, calendar, ideas) — must complete before stats
    // because E2E waitForDataLoad resolves on stat change and then checks body content
    await Promise.allSettled([
        loadDrafts(),
        fetchMailEpochIndex(),
        loadMail(),
        loadCalendar(),
        loadIdeas()
    ]);
    // Phase 2: Stats (triggers waitForDataLoad in E2E tests — body must be ready by now)
    await Promise.allSettled([
        loadTasks(),
        loadUnreadCount()
    ]);
    
    loadStationHealth();

    // Update footer after first boot
    const ts = document.getElementById('ts');
    const st = document.getElementById('footer-status');
    if (ts) ts.textContent = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    if (st) st.textContent = `Last updated ${new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
    
    // 3. Setup global refresh loop (every 1 min)
    setInterval(async () => {
        closeAllSSE(); // avoid connection leak before refresh
        console.log("[App] Global Refresh Cycle");
        await Promise.all([
            loadUnreadCount(),
            loadDrafts(),
            fetchMailEpochIndex(),
            loadTasks()
        ]);
        await Promise.all([
            loadMail(true),
            loadCalendar()
            // Ideas handled by SSE — no polling needed
        ]);
        loadStationHealth();
    }, REFRESH_MS);

    // Connect SSE for real-time updates
    connectSSE();
}

// ── loadAll — called by Refresh button (onclick="loadAll()") ──
export async function loadAll() {
    const ts = document.getElementById('ts');
    const st = document.getElementById('footer-status');
    if (ts) ts.textContent = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    if (st) st.textContent = 'Refreshing…';

    closeAllSSE();
    resetTaskState();

    await Promise.allSettled([
        loadUnreadCount(),
        loadDrafts(),
        fetchMailEpochIndex(),
        loadTasks(),
        loadMail(),
        loadCalendar(),
        loadIdeas()
    ]);

    loadStationHealth();
    if (st) st.textContent = `Last updated ${new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`;
}

// Global expose for inline HTML handlers
window.switchTab = switchTab;
window.toggleSidebar = toggleSidebar;
window.createPanel = createPanel;
window.loadAll = loadAll;

// Boot
window.onload = init;
