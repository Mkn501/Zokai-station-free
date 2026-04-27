// ── tasks.js — Tasks Column ────────────────────────────────────────
import { BASE, TASK_SECTIONS, escHtml, tagClass, setCount, setBody, encKiloData } from './core.js';
import { openDetail, _kiloMenuActive } from './panels.js';

let _taskPayloads = [];

function openTaskDetailByIdx(idx) {
  if (_kiloMenuActive) return;
  const t = _taskPayloads[idx];
  if (!t) return;
  openDetail(t.title, t.meta, t.body);
}

/** Update the sentinel element state */

// ── Tasks ────────────────────────────────────────────────────────────
export async function loadTasks() {
  try {
    const res = await fetch(`${BASE}/api/tasks`, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const md = await res.text();

    // Parse tasks into sections
    const sections = { 'In Progress': [], 'To Do': [], 'Backlog': [] };
    let currentSection = null;

    for (const line of md.split('\n')) {
      // Detect sections
      if (/^##\s+In Progress/i.test(line)) { currentSection = 'In Progress'; continue; }
      if (/^##\s+To\s+Do/i.test(line)) { currentSection = 'To Do'; continue; }
      if (/^##\s+Backlog/i.test(line)) { currentSection = 'Backlog'; continue; }
      if (/^##\s+/.test(line)) { currentSection = null; continue; }
      if (!currentSection || !sections[currentSection]) continue;

      // Match task lines (top-level only, not sub-items)
      const m = line.match(/^- \[[ x]\] (.+)/);
      if (!m) continue;

      // Skip meta/header lines
      const text = m[1].trim();
      if (text.startsWith('**Category**') || text.startsWith('**Topic**') ||
        text.startsWith('**Difficulty**') || text === '->' || text === '-') continue;

      // Extract [Tag]
      const tagMatch = text.match(/^\[([^\]]+)\]/);
      const tag = tagMatch ? tagMatch[1] : '';
      const body = tagMatch ? text.slice(tagMatch[0].length).trim() : text;
      const clean = body.split('\\n')[0].trim();

      sections[currentSection].push({ tag, text: clean, section: currentSection });
    }

    const totalTasks = sections['In Progress'].length + sections['To Do'].length + sections['Backlog'].length;

    if (!totalTasks) {
      setCount('task-count', '0');
      setBody('task-body', '<div class="empty-msg">No open tasks</div>');
      return;
    }

    setCount('task-count', totalTasks);
    _taskLastFetched = Date.now();

    // Build sectioned HTML
    const sectionConfig = [
      { key: 'In Progress', icon: '<circle cx="12" cy="12" r="10"></circle><polyline points="12 6 12 12 16 14"></polyline>', color: 'var(--vsc-green, #4caf50)', bulletClass: ' active' },
      { key: 'To Do', icon: '<circle cx="12" cy="12" r="10"></circle>', color: 'var(--vsc-accent, #007acc)', bulletClass: '' },
      { key: 'Backlog', icon: '<circle cx="12" cy="12" r="10"></circle>', color: 'var(--vsc-muted, #888)', bulletClass: '' }
    ];

    let html = '';
    for (const sec of sectionConfig) {
      const tasks = sections[sec.key];
      if (!tasks.length) continue;

      // Section header
      html += `<div style="padding:6px 12px 4px;font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:0.5px;color:${sec.color};border-bottom:1px solid var(--vsc-border);display:flex;align-items:center;gap:6px;position:sticky;top:0;background:var(--vsc-bg);z-index:1">
        <svg width="8" height="8" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">${sec.icon}</svg>
        ${escHtml(sec.key)} <span style="font-weight:400;opacity:0.7">${tasks.length}</span>
      </div>`;

      // Task rows
      for (const t of tasks) {
        const tc = tagClass(t.tag);
        const taskText = (t.tag ? '[' + t.tag + '] ' : '') + t.text;
        const metaLabel = t.section;
        const kiloB64 = encKiloData({ type: 'task', text: taskText, status: metaLabel });
        const _tIdx = _taskPayloads.length;
        _taskPayloads.push({ title: taskText, meta: metaLabel, body: t.fullText || t.text });
        const dimStyle = sec.key === 'Backlog' ? 'opacity:0.65;' : '';
        html += `<div class="task-row" onclick="openTaskDetailByIdx(${_tIdx})" data-kilo="${kiloB64}" oncontextmenu="onKiloMenu(event,this)" style="cursor:pointer;${dimStyle}" title="Click to open · Right-click for AI actions">
      <div class="task-bullet${sec.bulletClass}">
        <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">${sec.icon}</svg>
      </div>
      <div class="task-label">
        ${t.tag ? `<span class="tag ${tc}">[${escHtml(t.tag)}]</span> ` : ''}${escHtml(t.text)}
      </div>
      <button class="kilo-btn" onclick="event.stopPropagation();onKiloMenu(event,this.closest('.task-row'))" title="Kilo AI"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg></button>
    </div>`;
      }
    }

    setBody('task-body', html);

  } catch (e) {
    setBody('task-body', `<div class="error-msg"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line></svg> Could not load tasks<br><small>${escHtml(e.message)}</small></div>`);
  }
}


// ── State accessors ──
let _taskLastFetched = 0;
export function getTaskState() { return { lastFetched: _taskLastFetched }; }
export function resetTaskState() { _taskPayloads = []; _taskLastFetched = 0; }

// ── Window exports (HTML onclick handlers) ──
window.openTaskDetailByIdx = openTaskDetailByIdx;
