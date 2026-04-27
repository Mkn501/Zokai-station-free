// ── kilo.js — Kilo AI Context Menu ─────────────────────────────────
import { BASE, escHtml, decKiloData, showToast } from './core.js';
import { createPanel, setKiloMenuActive } from './panels.js';

// ── Kilo AI Context Menu ──────────────────────────────────────────────
let activeMenu = null;

const KILO_ACTIONS = {
  mail: [
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path><path d="M18.5 2.5a2.121 2.121 0 1 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path></svg>', label: 'Draft Reply', action: 'draft' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>', label: 'Find Related', action: 'find' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path></svg>', label: 'Ask Kilo…', action: 'ask' }
  ],
  calendar: [
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"></path><rect x="8" y="2" width="8" height="4" rx="1" ry="1"></rect></svg>', label: 'Prepare for Meeting', action: 'prepare' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>', label: 'Find Related', action: 'find' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path></svg>', label: 'Ask Kilo…', action: 'ask' }
  ],
  task: [
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 14 1.45-2.9A2 2 0 0 1 9.24 10H22"></path><path d="M10 2 2.23 14.82A2 2 0 0 0 3.89 18H22"></path><path d="M20 22a2 2 0 1 1-4 0 2 2 0 0 1 4 0Z"></path></svg>', label: 'Break Down', action: 'breakdown' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"></circle><line x1="21" y1="21" x2="16.65" y2="16.65"></line></svg>', label: 'Find Related', action: 'find' },
    { icon: '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"></path></svg>', label: 'Ask Kilo…', action: 'ask' }
  ]
};

export function buildPrompt(action, data) {
  switch (data.type) {
    case 'mail':
      switch (action) {
        case 'draft':
          return `Draft a professional reply to this email from ${data.sender} about "${data.subject}".\n\nEmail content:\n${data.snippet}`;
        case 'find':
          return `Search my knowledge base and emails for documents related to "${data.subject}" from ${data.sender}.\n\nContext: ${data.snippet}`;
        case 'ask':
          return `Regarding this email from ${data.sender}: "${data.subject}"\n\n${data.snippet}\n\n`;
      }
      break;
    case 'calendar':
      const locStr = data.location ? ` at ${data.location}` : '';
      switch (action) {
        case 'prepare':
          return `Help me prepare for this meeting: "${data.title}" on ${data.date}${locStr}. Find relevant notes, emails, and documents in my knowledge base.`;
        case 'find':
          return `Search for documents and emails related to the meeting: "${data.title}"${locStr}`;
        case 'ask':
          return `Regarding this event: "${data.title}" on ${data.date}${locStr}\n\n`;
      }
      break;
    case 'task':
      switch (action) {
        case 'breakdown':
          return `Break down this task into actionable sub-steps with estimated effort:\n\n${data.text}`;
        case 'find':
          return `Search for relevant notes, specs, and resources related to this task:\n\n${data.text}`;
        case 'ask':
          return `Regarding this task: ${data.text}\n\n`;
      }
      break;
  }
  return data.text || data.subject || data.title || '';
}

export function showKiloMenu(x, y, data) {
  dismissMenu();
  const actions = KILO_ACTIONS[data.type] || KILO_ACTIONS.task;

  const menu = document.createElement('div');
  menu.className = 'kilo-menu';

  // Header
  const header = document.createElement('div');
  header.className = 'kilo-menu-header';
  header.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px;margin-right:4px"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>KILO AI';
  menu.appendChild(header);

  // Action items
  actions.forEach(a => {
    const item = document.createElement('div');
    item.className = 'kilo-menu-item';
    item.innerHTML = `<span class="kilo-menu-icon">${a.icon}</span><span class="kilo-menu-label">${a.label}</span>`;
    item.addEventListener('click', () => {
      sendToKilo(a.action, data);
      dismissMenu();
    });
    menu.appendChild(item);
  });

  // Position — ensure menu stays within viewport
  menu.style.left = Math.min(x, window.innerWidth - 270) + 'px';
  menu.style.top = Math.min(y, window.innerHeight - 160) + 'px';

  document.body.appendChild(menu);
  activeMenu = menu;
}

// Reset menu guard (imported from panels.js)

export function dismissMenu() {
  if (activeMenu) {
    activeMenu.remove();
    activeMenu = null;
  }
  // Clear the guard flag after a tick so the row's onclick doesn't fire
  setTimeout(() => { setKiloMenuActive(false); }, 200);
}

export function onKiloMenu(e, rowEl) {
  e.preventDefault();
  e.stopPropagation();
  setKiloMenuActive(true);
  try {
    // Decode base64-encoded JSON from data-kilo attribute
    const b64 = rowEl.dataset.kilo;
    if (!b64) { console.warn('No data-kilo attribute found'); return; }
    const data = decKiloData(b64);
    showKiloMenu(e.clientX, e.clientY, data);
  } catch (err) {
    console.error('Kilo menu data parse error:', err);
  }
}

let _kiloSendLast = 0;
export async function sendToKilo(action, data) {
  // Debounce: skip if called within 3s of last send
  const now = Date.now();
  if (now - _kiloSendLast < 3000) {
    console.log('sendToKilo debounced — too soon after last send');
    return;
  }
  _kiloSendLast = now;

  const prompt = buildPrompt(action, data);
  showToast('Sending to Kilo...');

  try {
    // 1. Try vs-code relay (writes directly to Kilo's workspace)
    const res = await fetch('/api/vs-code/relay/kilo-prompt', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: prompt })
    });

    if (res.ok) {
      showToast('Sent to Kilo');
      return;
    }
  } catch (err) {
    console.warn('Bridge failed, falling back to clipboard:', err);
  }

  // 2. Fallback: Clipboard
  try {
    await navigator.clipboard.writeText(prompt);
    showToast('📋 Prompt copied — paste in Kilo');
  } catch (err) {
    // Fallback for non-HTTPS contexts
    const ta = document.createElement('textarea');
    ta.value = prompt;
    ta.style.cssText = 'position:fixed;left:-9999px';
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
    showToast('📋 Prompt copied — paste in Kilo');
  }
}



// ── Window exports (HTML onclick handlers) ──
window.onKiloMenu = onKiloMenu;
