// ── ideas.js — Ideas Board, Labels, Modal, Inline Edit ─────────────
import { BASE, escHtml, _isPro, showToast } from './core.js';

// ── Ideas Board ────────────────────────────────────────────────────
let _ideasData = [];   // From ideas-mcp REST API
let _editingId = null; // Guard: skip re-renders while user is editing a card

export async function loadIdeas() {
  // Edit guard: skip refresh while user is mid-edit (defer to next cycle)
  if (_editingId) return;
  try {
    const res = await fetch(`${BASE}/api/ideas/ideas`, { signal: AbortSignal.timeout(5000) });
    if (res.ok) {
      const data = await res.json();
      _ideasData = data.ideas || [];
    } else {
      _ideasData = [];
    }
  } catch (e) {
    // ideas-mcp not available — show empty state
    _ideasData = [];
  }
  renderIdeas();
}

/** Returns true if the user is currently editing an idea card */
export function isEditing() { return _editingId !== null; }

// ── Label Filter State ──
let _activeFilters = new Set();
let _filterNone = false; // When true, show only unlabeled cards
let _activeSource = 'all'; // UI-4: Source filter (all|human|kilo|raindrop)

export function renderLabelFilter() {
  const bar = document.getElementById('ideas-filter-bar');
  if (!bar) return;
  const allLabels = new Set();
  _ideasData.forEach(i => (i.labels || []).forEach(l => allLabels.add(l)));
  if (allLabels.size === 0) { bar.innerHTML = ''; return; }
  // Meta-buttons: All / None
  const metaHtml = `<button class="ideas-filter-chip ideas-filter-meta" onclick="selectAllLabels()">All</button>` +
    `<button class="ideas-filter-chip ideas-filter-meta" onclick="clearAllLabels()">None</button>`;
  const chipsHtml = Array.from(allLabels).sort().map(l =>
    `<button class="ideas-filter-chip${_activeFilters.has(l) ? ' active' : ''}" onclick="toggleLabelFilter('${escHtml(l).replace(/'/g, "\\'")}')">` +
    escHtml(l) + '</button>'
  ).join('');
  bar.innerHTML = metaHtml + chipsHtml;
}

export function selectAllLabels() {
  _activeFilters.clear(); // Clear all filters → show every card
  _filterNone = false;
  renderLabelFilter();
  renderIdeas();
}

export function clearAllLabels() {
  _activeFilters.clear();
  _filterNone = true; // Show only unlabeled cards
  renderLabelFilter();
  renderIdeas();
}

function toggleLabelFilter(label) {
  _filterNone = false; // Reset special state when toggling individual labels
  if (_activeFilters.has(label)) _activeFilters.delete(label);
  else _activeFilters.add(label);
  renderLabelFilter();
  renderIdeas();
}

/**
 * Convert markdown lists to HTML (XSS-safe: text segments go through escHtml).
 * Supports: - item, * item, 1. item, - [ ] unchecked, - [x] checked
 */
function renderMarkdownBody(text) {
  const lines = text.split('\n');
  let html = '';
  let inUl = false, inOl = false, inChecklist = false;

  for (const line of lines) {
    const trimmed = line.trim();
    // Checkbox: - [ ] or - [x]
    const cbMatch = trimmed.match(/^[-*]\s\[([ xX])\]\s(.*)$/);
    if (cbMatch) {
      if (inUl) { html += '</ul>'; inUl = false; }
      if (inOl) { html += '</ol>'; inOl = false; }
      if (!inChecklist) { html += '<ul class="checklist">'; inChecklist = true; }
      const isChecked = cbMatch[1].toLowerCase() === 'x';
      const checkbox = `<input type="checkbox" disabled ${isChecked ? 'checked' : ''} style="margin-right:6px;pointer-events:none;vertical-align:middle">`;
      html += `<li>${checkbox}${escHtml(cbMatch[2])}</li>`;
      continue;
    }
    // Unordered: - item or * item
    const ulMatch = trimmed.match(/^[-*]\s(.+)$/);
    if (ulMatch) {
      if (inChecklist) { html += '</ul>'; inChecklist = false; }
      if (inOl) { html += '</ol>'; inOl = false; }
      if (!inUl) { html += '<ul>'; inUl = true; }
      html += `<li>${escHtml(ulMatch[1])}</li>`;
      continue;
    }
    // Ordered: 1. item
    const olMatch = trimmed.match(/^\d+\.\s(.+)$/);
    if (olMatch) {
      if (inChecklist) { html += '</ul>'; inChecklist = false; }
      if (inUl) { html += '</ul>'; inUl = false; }
      if (!inOl) { html += '<ol>'; inOl = true; }
      html += `<li>${escHtml(olMatch[1])}</li>`;
      continue;
    }
    // Close any open lists
    if (inUl) { html += '</ul>'; inUl = false; }
    if (inOl) { html += '</ol>'; inOl = false; }
    if (inChecklist) { html += '</ul>'; inChecklist = false; }
    // Plain text — render wiki-links [[file.md]] as clickable
    if (trimmed) {
      const rendered = escHtml(trimmed).replace(
        /\[\[([^\]]+)\]\]/g,
        (_, file) => `<a class="idea-wiki-link" onclick="event.stopPropagation();openLinkedFile('${file.replace(/'/g, "\\'")}')"
          title="Open ${file}"><svg class="wiki-link-icon" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15.172 7l-6.586 6.586a2 2 0 1 0 2.828 2.828l6.414-6.586a4 4 0 0 0-5.656-5.656l-6.415 6.585a6 6 0 1 0 8.486 8.486L20.5 13"/></svg> ${file}</a>`
      );
      html += `<p>${rendered}</p>`;
    }
  }
  // Close dangling lists
  if (inUl) html += '</ul>';
  if (inOl) html += '</ol>';
  if (inChecklist) html += '</ul>';
  return html;
}

export function renderIdeas() {
  const container = document.getElementById('ideas-masonry');
  const emptyEl = document.getElementById('ideas-empty');
  const countEl = document.getElementById('ideas-count');

  // Remove old cards (keep empty state)
  container.querySelectorAll('.idea-card').forEach(c => c.remove());

  // UI-4: Apply source filter first
  let filtered = _ideasData;
  if (_activeSource !== 'all') {
    filtered = filtered.filter(i => i.source === _activeSource);
  }
  // Apply label filter
  if (_filterNone) {
    // "None" = show only unlabeled cards
    filtered = filtered.filter(i => !i.labels || i.labels.length === 0);
  } else if (_activeFilters.size > 0) {
    filtered = filtered.filter(i =>
      (i.labels || []).some(l => _activeFilters.has(l))
    );
  }

  countEl.textContent = filtered.length + ' idea' + (filtered.length !== 1 ? 's' : '') +
    (_activeFilters.size > 0 ? ' (filtered)' : '');

  // Also update filter bar
  renderLabelFilter();

  if (filtered.length === 0) {
    emptyEl.style.display = 'flex';
    return;
  }
  emptyEl.style.display = 'none';

  filtered.forEach(idea => {
    const card = document.createElement('div');
    let cls = 'idea-card';
    if (idea.color) cls += ' color-' + idea.color;
    if (idea.source === 'kilo') cls += ' ai-suggestion';
    if (idea.pinned) cls += ' pinned';
    card.className = cls;
    card.id = 'idea-' + idea.id;

    // Badge (text only — no emojis for Browse Lite compat)
    const badgeMap = {
      kilo: { label: 'AI', cls: 'kilo' },
      raindrop: { label: 'Raindrop', cls: 'raindrop' },
      human: { label: 'You', cls: 'human' },
    };
    const badge = badgeMap[idea.source] || badgeMap.human;

    // Confidence dot (AI only)
    let confDot = '';
    if (idea.ai_context && idea.ai_context.confidence != null) {
      const c = idea.ai_context.confidence;
      const level = c >= 0.7 ? 'high' : c >= 0.4 ? 'medium' : 'low';
      confDot = `<span class="idea-card-confidence ${level}" title="Confidence: ${(c * 100).toFixed(0)}%"></span>`;
    }

    // Pin icon (SVG pushpin — no emoji)
    const pinHtml = idea.pinned ? `<span class="idea-card-pin"><svg viewBox="0 0 24 24"><path d="M16 12V4h1V2H7v2h1v8l-2 2v2h5.2v6h1.6v-6H18v-2l-2-2z"/></svg></span>` : '';

    // Body — render markdown lists
    let bodyHtml = '';
    if (idea.body) bodyHtml = renderMarkdownBody(idea.body);

    // Labels + inline add button
    let labelsHtml = '<div class="idea-card-tags">';
    if (idea.labels && idea.labels.length > 0) {
      labelsHtml += idea.labels.map(l => {
        const safe = escHtml(l);
        return `<span class="idea-card-tag">${safe}<span class="tag-x" onclick="event.stopPropagation();removeLabelFromIdea('${idea.id}','${safe}')">&times;</span></span>`;
      }).join('');
    }
    labelsHtml += `<span class="idea-card-add-label" onclick="showInlineLabelInput(event,'${idea.id}')">+</span>`;
    labelsHtml += '</div>';

    // AI context reasoning (Stitch: bordered container)
    let aiHtml = '';
    if (idea.ai_context && idea.ai_context.reasoning) {
      const r = idea.ai_context.reasoning;
      aiHtml = `<div class="idea-card-reasoning">${escHtml(r.length > 140 ? r.slice(0, 140) + '…' : r)}</div>`;
    }

    // Color picker dots (shown on hover)
    const colors = ['yellow','green','blue','pink','purple','orange','none'];
    const colorDots = colors.map(c =>
      `<span class="idea-color-dot c-${c}" onclick="setIdeaColor('${idea.id}','${c === 'none' ? '' : c}')"></span>`
    ).join('');

    card.innerHTML = `
      ${pinHtml}
      <span class="idea-card-badge ${badge.cls}">${badge.label}${confDot}</span>
      <div class="idea-card-title">${escHtml(idea.title)}</div>
      ${idea.linked_file ? (() => {
        const lf = idea.linked_file.replace(/^\[\[|\]\]$/g, '');
        return `<a class="idea-card-link" onclick="event.stopPropagation();openLinkedFile('${escHtml(lf).replace(/'/g, "\\'")}')"
          title="Open ${escHtml(lf)}"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15.172 7l-6.586 6.586a2 2 0 1 0 2.828 2.828l6.414-6.586a4 4 0 0 0-5.656-5.656l-6.415 6.585a6 6 0 1 0 8.486 8.486L20.5 13"/></svg></a>`;
      })() : ''}
      ${bodyHtml ? `<div class="idea-card-body">${bodyHtml}</div>` : ''}
      ${aiHtml}
      ${labelsHtml}
      <div class="idea-card-actions">
        <button class="idea-action" style="border-color:#7c9bf5;color:#7c9bf5" onclick="editIdeaCard('${idea.id}')">Edit</button>
        <button class="idea-action promote" onclick="promoteIdea('${idea.id}')">Promote</button>
        <button class="idea-action dismiss" onclick="dismissIdea('${idea.id}')">Dismiss</button>
        <button class="idea-action" style="border-color:var(--vsc-muted);color:var(--vsc-muted)" onclick="toggleIdeaPin('${idea.id}',${!idea.pinned})">${idea.pinned ? 'Unpin' : 'Pin'}</button>
      </div>
      <div class="idea-card-colors">${colorDots}</div>
    `;
    // UI-6: Single-click on body/title opens edit (Browse Lite swallows dblclick)
    card.addEventListener('click', (e) => {
      // Skip if clicking action buttons, color dots, labels, or add-label
      if (e.target.closest('.idea-card-actions') || e.target.closest('.idea-card-colors') ||
          e.target.closest('.idea-card-add-label') || e.target.closest('.idea-card-inline-label') ||
          e.target.closest('.idea-card-tags') || e.target.closest('.idea-card-badge') ||
          e.target.closest('.idea-show-more')) return;
      // Only trigger on body or title clicks
      if (e.target.closest('.idea-card-body') || e.target.closest('.idea-card-title')) {
        editIdeaCard(idea.id);
      }
    });
    // Keep dblclick as fallback for standalone browser (anywhere on card)
    card.addEventListener('dblclick', (e) => {
      if (e.target.closest('.idea-card-actions') || e.target.closest('.idea-card-colors') ||
          e.target.closest('.idea-card-add-label') || e.target.closest('.idea-card-inline-label')) return;
      editIdeaCard(idea.id);
    });
    card.style.cursor = 'default';
    container.appendChild(card);
  });

  // Post-render: detect truncated bodies and add "more" toggle
  const chevronDown = '<svg width="10" height="10" viewBox="0 0 10 10" style="vertical-align:-1px;margin-right:3px"><path d="M2 3.5L5 6.5L8 3.5" stroke="currentColor" stroke-width="1.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  const chevronUp = '<svg width="10" height="10" viewBox="0 0 10 10" style="vertical-align:-1px;margin-right:3px"><path d="M2 6.5L5 3.5L8 6.5" stroke="currentColor" stroke-width="1.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  requestAnimationFrame(() => {
    container.querySelectorAll('.idea-card-body').forEach(body => {
      if (body.scrollHeight > body.clientHeight + 2) {
        const toggle = document.createElement('a');
        toggle.className = 'idea-show-more';
        toggle.innerHTML = chevronDown + 'more';
        toggle.addEventListener('click', (e) => {
          e.stopPropagation();
          const expanded = body.style.webkitLineClamp === 'unset';
          body.style.webkitLineClamp = expanded ? '' : 'unset';
          body.style.lineClamp = expanded ? '' : 'unset';
          const card = body.closest('.idea-card');
          if (!expanded) card.style.minHeight = '';
          toggle.innerHTML = expanded ? chevronDown + 'more' : chevronUp + 'less';
        });
        body.parentElement.insertBefore(toggle, body.nextSibling);
      }
    });
  });
}

// escHtml imported from core.js

export async function promoteIdea(id) {
  const cardEl = document.getElementById('idea-' + id);
  if (cardEl) cardEl.style.opacity = '0.3';
  try {
    await fetch(`${BASE}/api/ideas/ideas/${id}/promote`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({})
    });
  } catch (e) { /* fallback */ }
  _ideasData = _ideasData.filter(i => i.id !== id);
  setTimeout(renderIdeas, 300);
}

export async function dismissIdea(id) {
  const cardEl = document.getElementById('idea-' + id);
  if (cardEl) cardEl.style.opacity = '0.3';
  try {
    await fetch(`${BASE}/api/ideas/ideas/${id}`, { method: 'DELETE' });
  } catch (e) { /* fallback */ }
  _ideasData = _ideasData.filter(i => i.id !== id);
  setTimeout(renderIdeas, 300);
}

export async function toggleIdeaPin(id, pinned) {
  // Optimistic UI
  const idea = _ideasData.find(i => i.id === id);
  if (idea) idea.pinned = pinned;
  renderIdeas();
  try {
    await fetch(`${BASE}/api/ideas/ideas/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pinned })
    });
  } catch (e) { /* revert on fail — just reload */ loadIdeas(); }
}

export async function setIdeaColor(id, color) {
  const idea = _ideasData.find(i => i.id === id);
  if (idea) idea.color = color || null;
  renderIdeas();
  try {
    await fetch(`${BASE}/api/ideas/ideas/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ color: color || null })
    });
  } catch (e) { loadIdeas(); }
}

// ── New Idea Modal ──
let _modalLabels = [];

export function promptNewIdea() {
  _modalLabels = [];
  document.getElementById('idea-modal-title').value = '';
  document.getElementById('idea-modal-body').value = '';
  document.getElementById('idea-modal-label-input').value = '';
  renderModalLabelChips();
  document.getElementById('idea-modal-overlay').style.display = 'flex';
  setTimeout(() => document.getElementById('idea-modal-title').focus(), 50);
}

export function closeIdeaModal() {
  document.getElementById('idea-modal-overlay').style.display = 'none';
}

function renderModalLabelChips() {
  const c = document.getElementById('idea-modal-labels-chips');
  c.innerHTML = _modalLabels.map((l, i) =>
    `<span class="idea-modal-label-chip">${escHtml(l)}<span class="chip-x" onclick="removeModalLabel(${i})">&times;</span></span>`
  ).join('');
}

function removeModalLabel(idx) {
  _modalLabels.splice(idx, 1);
  renderModalLabelChips();
}

// Label input: Enter adds chip
document.addEventListener('DOMContentLoaded', () => {
  const labelInput = document.getElementById('idea-modal-label-input');
  if (labelInput) {
    labelInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        const val = labelInput.value.trim().toUpperCase();
        if (val && !_modalLabels.includes(val)) {
          _modalLabels.push(val);
          renderModalLabelChips();
        }
        labelInput.value = '';
      }
    });
  }
  // Escape closes modal
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeIdeaModal();
  });
});

export function submitIdeaModal() {
  const title = document.getElementById('idea-modal-title').value.trim();
  const body = document.getElementById('idea-modal-body').value.trim();
  if (!title) {
    document.getElementById('idea-modal-title').style.borderColor = '#ef4444';
    setTimeout(() => document.getElementById('idea-modal-title').style.borderColor = '', 1500);
    return;
  }
  closeIdeaModal();
  const tempId = 'temp-' + Date.now();
  _ideasData.unshift({
    id: tempId, title, body,
    labels: [..._modalLabels],
    color: null, pinned: false, source: 'human',
    ai_context: null,
    created: new Date().toISOString(),
    updated: new Date().toISOString(),
    promoted: false,
  });
  renderIdeas();
  fetch(`${BASE}/api/ideas/ideas`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, body, labels: [..._modalLabels], source: 'human' })
  }).then(res => {
    if (res.ok) return res.json();
  }).then(created => {
    if (created) {
      const idx = _ideasData.findIndex(i => i.id === tempId);
      if (idx !== -1) _ideasData[idx] = created;
      renderIdeas();
    }
  }).catch(() => {});
}

// ── Inline Label Editor ──
export function showInlineLabelInput(event, ideaId) {
  event.stopPropagation();
  const btn = event.target;
  if (btn.parentElement.querySelector('.idea-card-inline-label')) return;

  // Collect all unique labels from existing ideas (excluding this card's)
  const idea = _ideasData.find(i => i.id === ideaId);
  const currentLabels = new Set((idea && idea.labels) || []);
  const allLabels = [...new Set(
    _ideasData.flatMap(i => i.labels || []).filter(l => !currentLabels.has(l))
  )].sort();

  // Create wrapper for input + dropdown
  const wrapper = document.createElement('span');
  wrapper.className = 'idea-label-autocomplete';
  wrapper.style.position = 'relative';
  wrapper.style.display = 'inline-block';

  const input = document.createElement('input');
  input.type = 'text';
  input.className = 'idea-card-inline-label';
  input.placeholder = 'Label';
  wrapper.appendChild(input);

  // Dropdown with suggestions
  const dropdown = document.createElement('div');
  dropdown.className = 'idea-label-dropdown';
  allLabels.forEach(label => {
    const opt = document.createElement('div');
    opt.className = 'idea-label-option';
    opt.textContent = label;
    opt.addEventListener('mousedown', (e) => {
      e.preventDefault(); // prevent blur
      addLabelToIdea(ideaId, label);
      wrapper.remove();
    });
    dropdown.appendChild(opt);
  });
  wrapper.appendChild(dropdown);

  btn.parentElement.insertBefore(wrapper, btn);
  // Raise card z-index so dropdown floats above other cards
  const parentCard = btn.closest('.idea-card');
  if (parentCard) parentCard.style.zIndex = '50';
  input.focus();

  // Filter dropdown as user types
  input.addEventListener('input', () => {
    const q = input.value.trim().toUpperCase();
    dropdown.querySelectorAll('.idea-label-option').forEach(opt => {
      opt.style.display = opt.textContent.includes(q) ? '' : 'none';
    });
  });

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      const val = input.value.trim().toUpperCase();
      if (val) addLabelToIdea(ideaId, val);
      if (parentCard) parentCard.style.zIndex = '';
      wrapper.remove();
    } else if (e.key === 'Escape') {
      if (parentCard) parentCard.style.zIndex = '';
      wrapper.remove();
    }
  });
  input.addEventListener('blur', () => {
    setTimeout(() => {
      const val = input.value.trim().toUpperCase();
      if (val) addLabelToIdea(ideaId, val);
      if (parentCard) parentCard.style.zIndex = '';
      wrapper.remove();
    }, 150);
  });
}

export async function addLabelToIdea(ideaId, label) {
  const idea = _ideasData.find(i => i.id === ideaId);
  if (!idea) return;
  if (!idea.labels) idea.labels = [];
  if (idea.labels.includes(label)) return;
  idea.labels.push(label);
  renderIdeas();
  try {
    await fetch(`${BASE}/api/ideas/ideas/${ideaId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ labels: idea.labels })
    });
  } catch (e) { loadIdeas(); }
}

export async function removeLabelFromIdea(ideaId, label) {
  const idea = _ideasData.find(i => i.id === ideaId);
  if (!idea || !idea.labels) return;
  idea.labels = idea.labels.filter(l => l !== label);
  renderIdeas();
  try {
    await fetch(`${BASE}/api/ideas/ideas/${ideaId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ labels: idea.labels })
    });
  } catch (e) { loadIdeas(); }
}

// ── Double-Click Card Editing ──
export function editIdeaCard(ideaId) {
  const idea = _ideasData.find(i => i.id === ideaId);
  if (!idea) return;
  const card = document.getElementById('idea-' + ideaId);
  if (!card || card.dataset.editing === 'true') return;
  card.dataset.editing = 'true';
  // Freeze card height to prevent masonry jitter
  card.style.minHeight = card.offsetHeight + 'px';
  _editingId = ideaId; // Guard: prevent sync from destroying this edit

  const titleVal = idea.title || '';
  const bodyVal = idea.body || '';
  const labelsVal = (idea.labels || []).join(', ');

  const linkedVal = idea.linked_file || '';
  card.innerHTML = `
    <input type="text" class="idea-edit-title" value="${escHtml(titleVal)}" placeholder="Title" />
    <textarea class="idea-edit-body" placeholder="Details (optional)" rows="3">${escHtml(bodyVal)}</textarea>
    <input type="text" class="idea-edit-labels" value="${escHtml(labelsVal)}" placeholder="Labels (comma-separated)" />
    <input type="text" class="idea-edit-linked" value="${escHtml(linkedVal)}" placeholder="Link to file (optional, e.g. notes/idea.md)" />
    <div class="idea-modal-actions" style="margin-top:8px">
      <button onclick="cancelEditIdea('${ideaId}')">Cancel</button>
      <button class="btn-create" onclick="saveEditIdea('${ideaId}')">Save</button>
    </div>
  `;
  const titleInput = card.querySelector('.idea-edit-title');
  if (titleInput) titleInput.focus();

  // Escape to cancel
  card.addEventListener('keydown', function handler(e) {
    if (e.key === 'Escape') { cancelEditIdea(ideaId); card.removeEventListener('keydown', handler); }
  });
}

export function cancelEditIdea(ideaId) {
  _editingId = null; // Clear guard
  renderIdeas();
}

export async function saveEditIdea(ideaId) {
  const card = document.getElementById('idea-' + ideaId);
  if (!card) return;
  const idea = _ideasData.find(i => i.id === ideaId);
  if (!idea) return;

  const titleInput = card.querySelector('.idea-edit-title');
  const bodyInput = card.querySelector('.idea-edit-body');
  const labelsInput = card.querySelector('.idea-edit-labels');

  // Strip wiki-link brackets from linked_file
  const linkedInput = card.querySelector('.idea-edit-linked');
  let linkedRaw = linkedInput ? linkedInput.value.trim() : '';
  // Support [[filename]] wiki-link syntax
  const wikiMatch = linkedRaw.match(/^\[\[(.+)\]\]$/);
  if (wikiMatch) linkedRaw = wikiMatch[1];
  const newLinked = linkedRaw || null;

  const newTitle = titleInput ? titleInput.value.trim() : idea.title;
  const newBody = bodyInput ? bodyInput.value.trim() : idea.body;
  const newLabels = labelsInput ? labelsInput.value.split(',').map(l => l.trim().toUpperCase()).filter(Boolean) : idea.labels;

  if (!newTitle) {
    if (titleInput) { titleInput.style.borderColor = '#ef4444'; }
    return;
  }

  // Optimistic update
  idea.title = newTitle;
  idea.body = newBody;
  idea.labels = newLabels;
  idea.linked_file = newLinked;
  _editingId = null; // Clear guard
  // Release frozen height
  card.style.minHeight = '';
  renderIdeas();

  try {
    await fetch(`${BASE}/api/ideas/ideas/${ideaId}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: newTitle, body: newBody, labels: newLabels, linked_file: newLinked })
    });
  } catch (e) { loadIdeas(); }
}

// ── Tab Switching ─────────────────────────────────────────────────────
let _ideasLoaded = false;
let _healthLoaded = false;
export function switchTab(tabName) {
  // Update tab buttons
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tab === tabName);
  });
  // Update tab panels
  document.querySelectorAll('.tab-panel').forEach(panel => {
    panel.classList.toggle('active', panel.id === 'tab-' + tabName);
  });
  // Lazy-load Ideas Board on first visit (Pro only)
  if (tabName === 'ideas' && !_ideasLoaded && _isPro) {
    _ideasLoaded = true;
    loadIdeas();
  }
  // Lazy-load Station Health on first visit (Pro only)
  if (tabName === 'health' && !_healthLoaded && _isPro) {
    _healthLoaded = true;
    import('./app.js').then(m => m.loadStationHealth());
  }
}


// ── Sync Button (WO-IDEAS-2) ──
export async function refreshIdeasBoard() {
  showToast('Syncing ideas…');
  _editingId = null; // Force clear any stale edit guard
  await loadIdeas();
  showToast('Ideas synced ✓');
}

// ── State accessors ──
export function getIdeasState() { return { ideasLoaded: _ideasLoaded }; }

// ── Window exports (HTML onclick handlers) ──
window.promptNewIdea = promptNewIdea;
window.closeIdeaModal = closeIdeaModal;
window.submitIdeaModal = submitIdeaModal;
window.showInlineLabelInput = showInlineLabelInput;
window.toggleLabelFilter = toggleLabelFilter;
window.addLabelToIdea = addLabelToIdea;
window.removeLabelFromIdea = removeLabelFromIdea;
window.editIdeaCard = editIdeaCard;
window.cancelEditIdea = cancelEditIdea;
window.saveEditIdea = saveEditIdea;
window.setIdeaColor = setIdeaColor;
window.toggleIdeaPin = toggleIdeaPin;
window.promoteIdea = promoteIdea;
window.dismissIdea = dismissIdea;
window.switchTab = switchTab;
window.isEditing = isEditing;
window.selectAllLabels = selectAllLabels;
window.clearAllLabels = clearAllLabels;
window.refreshIdeasBoard = refreshIdeasBoard;

// UI-4: Source filter
export function setSourceFilter(source) {
  _activeSource = source;
  // Update tab active state
  document.querySelectorAll('.source-tab').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.source === source);
  });
  renderIdeas();
}
window.setSourceFilter = setSourceFilter;

// UI-5: Open linked file in VS Code editor via relay → remote CLI
export function openLinkedFile(filePath) {
  // Strip wiki-link brackets if present
  const clean = filePath.replace(/^\[\[|\]\]$/g, '');
  fetch('/api/vs-code/relay/open-file', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: clean })
  }).then(r => {
    if (r.ok) showToast('\u2713 Opened: ' + clean);
    else showToast('File not found: ' + clean);
  }).catch(() => {
    showToast('Relay unavailable — ' + clean);
  });
}
window.openLinkedFile = openLinkedFile;
