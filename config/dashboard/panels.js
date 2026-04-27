// ── panels.js — Multi-panel Window Manager ─────────────────────────
import { escHtml } from './core.js';

// Kilo menu guard — set by kilo.js via setKiloMenuActive()
export let _kiloMenuActive = false;
export function setKiloMenuActive(val) { _kiloMenuActive = val; }

// ── Multi-panel window manager ──────────────────────────────────────
export const panels = {};       // panelKey → DOM element
let panelZIndex = 200;   // stacking counter
let panelCascade = 0;    // cascade offset for new panels

export function createPanel(key, title, meta, bodyHtml, footerHtml) {
  // If panel already exists, focus it
  if (panels[key]) { focusPanel(panels[key]); return panels[key]; }

  const el = document.createElement('div');
  el.className = 'panel focused';
  el.dataset.panelKey = key;
  el.style.zIndex = ++panelZIndex;

  // Cascade position: start top-right, offset each new panel
  const baseTop = 80 + (panelCascade % 8) * 32;
  const baseRight = 40 + (panelCascade % 8) * 32;
  el.style.top = baseTop + 'px';
  el.style.right = baseRight + 'px';
  panelCascade++;

  el.innerHTML = `
    <div class="panel-header">
      <div style="overflow:hidden">
        <div class="panel-title">${escHtml(title)}</div>
        ${meta ? `<div class="panel-meta">${escHtml(meta)}</div>` : ''}
      </div>
      <button class="panel-close" onclick="closePanel('${key}')">×</button>
    </div>
    <div class="panel-body">${bodyHtml || '(No content)'}</div>
    ${footerHtml ? `<div class="panel-footer">${footerHtml}</div>` : ''}
  `;

  // Focus on click
  el.addEventListener('mousedown', () => focusPanel(el));

  // Drag via header
  const header = el.querySelector('.panel-header');
  let dragging = false, dragX, dragY;
  header.addEventListener('mousedown', (e) => {
    if (e.target.tagName === 'BUTTON') return;
    dragging = true;
    dragX = e.clientX - el.offsetLeft;
    dragY = e.clientY - el.offsetTop;
    el.style.transition = 'none';
    focusPanel(el);
  });
  document.addEventListener('mousemove', (e) => {
    if (!dragging) return;
    // Bulletproof fix for stolen focus (e.g. Browse Lite opening external link):
    // If no mouse buttons are physically pressed but we think we're dragging, we missed a mouseup.
    if (e.buttons === 0) {
      dragging = false;
      el.style.transition = '';
      return;
    }
    el.style.left = Math.max(0, e.clientX - dragX) + 'px';
    el.style.top = Math.max(0, e.clientY - dragY) + 'px';
    el.style.right = 'auto';
  });
  document.addEventListener('mouseup', () => {
    if (dragging) { dragging = false; el.style.transition = ''; }
  });

  // Unfocus all others
  Object.values(panels).forEach(p => p.classList.remove('focused'));

  document.getElementById('panel-container').appendChild(el);
  panels[key] = el;
  return el;
}

export function focusPanel(el) {
  Object.values(panels).forEach(p => p.classList.remove('focused'));
  el.classList.add('focused');
  el.style.zIndex = ++panelZIndex;
}

export function closePanel(key) {
  if (panels[key]) { panels[key].remove(); delete panels[key]; }
}

// Escape closes the focused (top) panel
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    const focused = Object.values(panels).find(p => p.classList.contains('focused'));
    if (focused) closePanel(focused.dataset.panelKey);
  }
});

// Backward-compatible openDetail for tasks/calendar (creates a panel)
export function openDetail(title, meta, body) {
  if (_kiloMenuActive) return; // guard: skip if Kilo context menu is active
  const key = 'detail-' + title.slice(0, 30).replace(/\W/g, '_');
  const p = createPanel(key, title, meta, `<span>${escHtml(body || '')}</span>`);
  return p;
}

/** Rich HTML panel for calendar events (WO-CAL-2) */
export function openDetailHtml(title, meta, htmlBody) {
  const key = 'detail-' + title.slice(0, 30).replace(/\W/g, '_');
  const p = createPanel(key, title, meta, htmlBody || '(No content available)');
  // panel-body uses pre-wrap by default; for HTML content, override
  const body = p.querySelector('.panel-body');
  if (body) body.style.whiteSpace = 'normal';
  return p;
}

// ── Window exports (HTML onclick handlers) ──
window.closePanel = closePanel;
