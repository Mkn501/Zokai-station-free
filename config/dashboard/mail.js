// ── mail.js — Mail Column, Search, Drafts ──────────────────────────
import { BASE, EMAIL_PAGE_SIZE, escHtml, fmtDate, fmtDatetime, stripHtml, cleanSnippet,
         isHtml, encKiloData, decKiloData, setCount, setBody, appendBody, showToast, updateSentinel } from './core.js';
import { panels, createPanel, focusPanel, closePanel, openDetail, openDetailHtml, _kiloMenuActive } from './panels.js';

// ── Mail ────────────────────────────────────────────────────────────

/** WO-MAIL-6: Async email body fetch on click — opens in panel */
export async function openMailDetail(messageId, subject, sender, date, snippet) {
  if (_kiloMenuActive) return; // guard: skip if Kilo context menu is active
  const key = 'mail-' + messageId;
  if (panels[key]) { focusPanel(panels[key]); return; }

  const meta = sender + (date ? '  ·  ' + fmtDate(date) : '');
  const p = createPanel(key, subject, meta, '<span style="color:var(--vsc-muted)">Loading…</span>');
  // Store email metadata for right-click actions
  p.dataset.emailSubject = subject;
  p.dataset.emailSender = sender;
  p.dataset.emailSnippet = snippet || '';
  p.dataset.emailId = messageId;

  // Right-click on panel body → show Self Draft / Send to Kilo menu
  p.querySelector('.panel-body').addEventListener('contextmenu', (e) => {
    e.preventDefault();
    e.stopPropagation();
    showPanelContextMenu(e.clientX, e.clientY, p);
  });

  const body = p.querySelector('.panel-body');

  // Mark as read in Gmail (fire & forget) + live-remove unread indicator + decrement stat bar
  fetch(`${BASE}/api/mail/read/${messageId}/mark-read`, { method: 'POST', signal: AbortSignal.timeout(5000) })
    .then(r => {
      if (r.ok) {
        const el = document.getElementById('stat-mail');
        const cur = parseInt(el?.textContent, 10);
        if (!isNaN(cur) && cur > 0) el.textContent = cur - 1;
      }
    })
    .catch(() => { /* ignore */ });
  // Live DOM update: remove unread styling from the clicked row immediately
  // (regardless of network result — UX intent is fulfilled on click)
  const clickedRow = document.querySelector(`[data-msg-id="${messageId}"]`);
  if (clickedRow && clickedRow.classList.contains('row-unread')) {
    clickedRow.classList.remove('row-unread');
    const icon = clickedRow.querySelector('.row-icon');
    if (icon && icon.querySelector('.unread-dot')) {
      icon.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="20" height="16" x="2" y="4" rx="2"></rect><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"></path></svg>';
    }
  }

  try {
    const res = await fetch(`${BASE}/api/mail/read/${messageId}`, { signal: AbortSignal.timeout(10000) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    const text = data.body || '';
    if (!text || text.startsWith('Error reading email:')) {
      showSnippetInPanel(body, snippet);
    } else if (isHtml(text)) {
      // HTML email — sanitize with DOMParser, render with innerHTML, intercept links
      var parser = new DOMParser();
      var emailDoc = parser.parseFromString(text, 'text/html');
      // Remove non-visible / dangerous elements
      emailDoc.querySelectorAll('script, style, head, meta, link, title, iframe, object, embed, form, input, button, textarea').forEach(function (el) { el.remove(); });
      // Get sanitized body HTML (preserves links, images, formatting)
      var safeHtml = emailDoc.body ? emailDoc.body.innerHTML : '';
      if (!safeHtml.trim()) {
        body.textContent = '(Empty email)';
      } else {
        // Wrap in a styled container
        body.innerHTML = '<div class="email-rendered">' + safeHtml + '</div>';
        body.style.whiteSpace = 'normal';
        // Make images responsive
        body.querySelectorAll('img').forEach(function (img) {
          img.style.maxWidth = '100%';
          img.style.height = 'auto';
          img.style.display = 'block';
        });
        // Intercept link clicks — Google/meeting links open externally, rest open in new Browse Lite tab
        body.addEventListener('click', function (e) {
          var a = e.target.closest('a[href]');
          if (!a) return;
          var url = a.href;
          if (!url || !url.startsWith('http')) { e.preventDefault(); return; }
          // Always prevent default to avoid replacing the dashboard (causes freeze)
          e.preventDefault();
          e.stopPropagation();
          // Route Google and meeting/video links through the external URL relay → host browser
          var externalDomains = ['meet.google.com', 'zoom.us', 'teams.microsoft.com', 'webex.com',
            'calendar.google.com', 'accounts.google.com', 'docs.google.com',
            'drive.google.com', 'mail.google.com'];
          var hostname = '';
          try { hostname = new URL(url).hostname; } catch (err) { return; }
          var isExternal = externalDomains.some(function (d) { return hostname.endsWith(d); });
          if (isExternal) {
            fetch(window.location.origin + '/api/open-url?url=' + encodeURIComponent(url))
              .catch(function () { });
          } else {
            // Navigate current Browse Lite tab (no split — user clicks Dashboard to return)
            window.location.href = url;
          }
        });
      }
      // Store plain text for Kilo
      p.dataset.emailBody = stripHtml(text);
    } else {
      // Plain text email — clean up long URLs for display
      var cleaned = text.replace(/https?:\/\/[^\s]{120,}/g, function (url) {
        try { return new URL(url).hostname + '/…'; } catch (e) { return '[link]'; }
      });
      body.textContent = cleaned;
      body.style.whiteSpace = 'pre-wrap';
      // Store original for Kilo
      p.dataset.emailBody = text;
    }

    // Show attachment list if any
    const atts = data.attachments || [];
    if (atts.length > 0) {
      const attDiv = document.createElement('div');
      attDiv.style.cssText = 'border-top:1px solid var(--vsc-border);padding:8px 4px 4px;margin-top:8px;display:flex;flex-wrap:wrap;gap:4px;align-items:center';
      attDiv.innerHTML = _svgIcon('attachment', 12) + ' <span style="font-size:10px;color:var(--vsc-muted);margin-right:4px">' + atts.length + ' attachment' + (atts.length > 1 ? 's' : '') + '</span>';
      for (const att of atts) {
        const ext = (att.name.split('.').pop() || '').toLowerCase();
        const sizeStr = att.size < 1024 ? att.size + ' B'
          : att.size < 1024 * 1024 ? (att.size / 1024).toFixed(1) + ' KB'
          : (att.size / (1024 * 1024)).toFixed(1) + ' MB';
        const chip = document.createElement('span');
        chip.style.cssText = 'display:inline-flex;align-items:center;gap:3px;padding:2px 6px;background:var(--vsc-bg);border:1px solid var(--vsc-border);border-radius:3px;font-size:10px;color:var(--vsc-text);cursor:pointer';
        chip.title = 'Click to save to workspace';
        chip.innerHTML = _svgIcon(_extToType(ext), 11) + ' ' + escHtml(att.name) + ' <span style="color:var(--vsc-muted)">(' + sizeStr + ')</span>';
        chip.addEventListener('click', function (ev) {
          ev.stopPropagation();
          _showAttachmentDownloadDialog(messageId, att, chip);
        });
        attDiv.appendChild(chip);
      }
      body.appendChild(attDiv);
    }
  } catch (e) {
    console.error("Mail load error:", e);
    showSnippetInPanel(body, snippet + '\n\n[DEBUG ERROR: ' + e.message + ']');
  }
}

/** Panel right-click context menu — Self Draft or Send to Kilo */
function showPanelContextMenu(x, y, panel) {
  dismissMenu();
  const menu = document.createElement('div');
  menu.className = 'kilo-menu';

  // Header
  const header = document.createElement('div');
  header.className = 'kilo-menu-header';
  header.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px;margin-right:4px"><rect width="20" height="16" x="2" y="4" rx="2"></rect><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"></path></svg>REPLY OPTIONS';
  menu.appendChild(header);

  // Self Draft — opens inline reply textarea
  const selfDraft = document.createElement('div');
  selfDraft.className = 'kilo-menu-item';
  selfDraft.innerHTML = '<span class="kilo-menu-icon"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path><path d="M18.5 2.5a2.121 2.121 0 1 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path></svg></span><span class="kilo-menu-label">Self Draft Reply</span>';
  selfDraft.addEventListener('click', () => { openReplyTextarea(panel); dismissMenu(); });
  menu.appendChild(selfDraft);

  // Send to Kilo — AI drafts reply
  const kiloItem = document.createElement('div');
  kiloItem.className = 'kilo-menu-item';
  kiloItem.innerHTML = '<span class="kilo-menu-icon"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg></span><span class="kilo-menu-label">Send to Kilo (AI Draft)</span>';
  kiloItem.addEventListener('click', () => {
    const data = {
      type: 'mail',
      subject: panel.dataset.emailSubject,
      sender: panel.dataset.emailSender,
      snippet: panel.dataset.emailBody || panel.dataset.emailSnippet
    };
    sendToKilo('draft', data);
    dismissMenu();
  });
  menu.appendChild(kiloItem);

  menu.style.left = Math.min(x, window.innerWidth - 270) + 'px';
  menu.style.top = Math.min(y, window.innerHeight - 160) + 'px';
  document.body.appendChild(menu);
  activeMenu = menu;
}

/** Opens an inline reply textarea at the bottom of the email panel */
function openReplyTextarea(panel) {
  const key = panel.dataset.panelKey;
  // Prevent duplicate reply areas
  if (panel.querySelector('.reply-area')) {
    panel.querySelector('.reply-area textarea').focus();
    return;
  }

  const replyDiv = document.createElement('div');
  replyDiv.className = 'reply-area';
  replyDiv.style.cssText = 'border-top:1px solid var(--vsc-border);padding:10px 14px;flex-shrink:0';

  const ta = document.createElement('textarea');
  ta.style.cssText = 'width:100%;min-height:80px;max-height:200px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;padding:8px;font-size:12px;font-family:inherit;resize:vertical';
  ta.placeholder = 'Write your reply…';
  replyDiv.appendChild(ta);

  const btnRow = document.createElement('div');
  btnRow.style.cssText = 'display:flex;gap:8px;margin-top:8px';

  const sendBtn = document.createElement('button');
  sendBtn.className = 'btn-primary';
  sendBtn.style.cssText = 'font-size:11px;padding:4px 12px;border-radius:4px;border:1px solid var(--vsc-accent,#007acc);background:var(--vsc-accent,#007acc);color:#fff;cursor:pointer';
  sendBtn.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><rect width="20" height="16" x="2" y="4" rx="2"></rect><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"></path></svg> Send Now';
  sendBtn.addEventListener('click', async () => {
    const text = ta.value.trim();
    if (!text) { showToast('Reply is empty'); return; }
    try {
      sendBtn.disabled = true;
      sendBtn.textContent = '⏳ Sending…';
      const res = await fetch(`${BASE}/api/mail/send`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          to: panel.dataset.emailSender,
          subject: 'Re: ' + panel.dataset.emailSubject,
          body: text
        }),
        signal: AbortSignal.timeout(15000)
      });
      if (!res.ok) { const d = await res.json().catch(() => ({})); throw new Error(d.error || `HTTP ${res.status}`); }
      showToast('Email sent!');
      replyDiv.remove();
    } catch (e) {
      showToast(`Failed to send: ${e.message}`);
      sendBtn.disabled = false;
      sendBtn.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><rect width="20" height="16" x="2" y="4" rx="2"></rect><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"></path></svg> Send Now';
    }
  });

  const draftBtn = document.createElement('button');
  draftBtn.style.cssText = 'font-size:11px;padding:4px 12px;border-radius:4px;border:1px solid var(--vsc-border);background:var(--vsc-bg);color:var(--vsc-text);cursor:pointer';
  draftBtn.innerHTML = '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg> Save to Drafts';
  draftBtn.addEventListener('click', async () => {
    const text = ta.value.trim();
    if (!text) { showToast('Reply is empty'); return; }
    try {
      draftBtn.disabled = true;
      draftBtn.textContent = '⏳ Saving…';
      const res = await fetch(`${BASE}/api/mail/drafts`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          to: panel.dataset.emailSender,
          subject: 'Re: ' + panel.dataset.emailSubject,
          body: text,
          message_id: panel.dataset.emailId || ''
        }),
        signal: AbortSignal.timeout(10000)
      });
      if (!res.ok) { const d = await res.json().catch(() => ({})); throw new Error(d.error || `HTTP ${res.status}`); }
      showToast('Saved to Draft Box');
      replyDiv.remove();
      if (_draftBoxOpen) loadDrafts();
    } catch (e) {
      showToast(`Failed to save draft: ${e.message}`);
      draftBtn.disabled = false;
      draftBtn.innerHTML = '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg> Save to Drafts';
    }
  });

  const cancelBtn = document.createElement('button');
  cancelBtn.style.cssText = 'font-size:11px;padding:4px 12px;border-radius:4px;border:1px solid var(--vsc-border);background:var(--vsc-bg);color:var(--vsc-muted);cursor:pointer;margin-left:auto';
  cancelBtn.textContent = '✕ Cancel';
  cancelBtn.addEventListener('click', () => replyDiv.remove());

  btnRow.appendChild(sendBtn);
  btnRow.appendChild(draftBtn);
  btnRow.appendChild(cancelBtn);
  replyDiv.appendChild(btnRow);

  // Insert before footer or append to panel
  const footer = panel.querySelector('.panel-footer');
  if (footer) panel.insertBefore(replyDiv, footer);
  else panel.appendChild(replyDiv);

  ta.focus();
}

function showSnippetInPanel(bodyEl, snippet) {
  if (snippet) {
    bodyEl.innerHTML =
      `<div style="color:var(--text-secondary);margin-bottom:12px;font-size:0.85em"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line></svg> Full email not available from Gmail (may have been deleted or archived)</div>` +
      `<div style="white-space:pre-wrap">${escHtml(snippet)}</div>`;
  } else {
    bodyEl.textContent = '(No content available)';
  }
}

/** WO-MAIL-UX-1: Open draft in an EDITABLE panel — inline edit To/Subject/Body + Save/Send/Discard */
export async function openDraftPanel(draftId, subject, to, snippet) {
  const key = 'draft-' + draftId;
  if (panels[key]) { focusPanel(panels[key]); return; }

  const displaySubject = (!subject || subject === '(no subject)' || subject === '(No Subject)')
    ? 'New Draft' : subject;
  const p = createPanel(key, '✎ ' + displaySubject, 'Loading draft…', '<span style="color:var(--vsc-muted)">Loading draft…</span>');
  const body = p.querySelector('.panel-body');
  body.style.whiteSpace = 'normal';

  try {
    const res = await fetch(`${BASE}/api/mail/drafts/${draftId}`, { signal: AbortSignal.timeout(10000) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    const fetchedTo = data.to || data.from || to || '';
    const fetchedSubject = data.subject || subject || '';
    const fetchedBody = data.body || data.snippet || snippet || '';

    // Update panel meta
    const metaEl = p.querySelector('.panel-meta');
    if (metaEl) metaEl.textContent = 'Editing draft';

    // Render editable form (reuses openComposePanel styling)
    body.innerHTML = `
      <div style="display:flex;flex-direction:column;gap:8px;padding:4px;flex:1">
        <label style="font-size:11px;color:var(--vsc-muted)">To:</label>
        <input type="text" class="draft-edit-to" value="${escHtml(fetchedTo)}" placeholder="recipient@example.com" style="width:100%;padding:6px 8px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
        <label style="font-size:11px;color:var(--vsc-muted)">Subject:</label>
        <input type="text" class="draft-edit-subject" value="${escHtml(fetchedSubject)}" placeholder="Subject" style="width:100%;padding:6px 8px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
        <label style="font-size:11px;color:var(--vsc-muted)">Body:</label>
        <textarea class="draft-edit-body" placeholder="Write your email…" style="width:100%;min-height:120px;flex:1;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;padding:8px;font-size:12px;font-family:inherit;resize:vertical">${escHtml(fetchedBody)}</textarea>
        <div style="display:flex;gap:8px;margin-top:4px;flex-wrap:wrap">
          <button class="draft-save-btn" style="font-size:11px;padding:5px 14px;border-radius:4px;border:1px solid var(--vsc-accent,#007acc);background:var(--vsc-accent,#007acc);color:#fff;cursor:pointer">💾 Save Changes</button>
          <button class="draft-send-btn" style="font-size:11px;padding:5px 14px;border-radius:4px;border:1px solid #28a745;background:#28a745;color:#fff;cursor:pointer">✓ Send</button>
          <button class="draft-discard-btn" style="font-size:11px;padding:5px 14px;border-radius:4px;border:1px solid var(--vsc-border);background:var(--vsc-bg);color:var(--vsc-text);cursor:pointer;margin-left:auto">✕ Discard</button>
        </div>
      </div>
    `;

    const toInput = body.querySelector('.draft-edit-to');
    const subjInput = body.querySelector('.draft-edit-subject');
    const bodyTa = body.querySelector('.draft-edit-body');

    // Save Changes → PUT /drafts/<id>
    body.querySelector('.draft-save-btn').addEventListener('click', async function () {
      const newTo = toInput.value.trim();
      const newSubj = subjInput.value.trim();
      const newBody = bodyTa.value.trim();
      if (!newTo && !newSubj && !newBody) { showToast('Nothing to save'); return; }
      try {
        this.disabled = true;
        this.textContent = '⏳ Saving…';
        const r = await fetch(`${BASE}/api/mail/drafts/${draftId}`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ to: newTo, subject: newSubj, body: newBody }),
          signal: AbortSignal.timeout(10000)
        });
        if (!r.ok) { const d = await r.json().catch(() => ({})); throw new Error(d.error || `HTTP ${r.status}`); }
        showToast('Draft saved ✓');
        this.disabled = false;
        this.textContent = '💾 Save Changes';
        // Update panel title
        const titleEl = p.querySelector('.panel-title');
        if (titleEl && newSubj) titleEl.textContent = '✎ ' + newSubj;
        if (_draftBoxOpen) loadDrafts();
      } catch (e) {
        showToast('Failed to save: ' + e.message);
        this.disabled = false;
        this.textContent = '💾 Save Changes';
      }
    });

    // Send → confirm then send
    body.querySelector('.draft-send-btn').addEventListener('click', function () {
      const subjEsc = escHtml(subjInput.value || subject).replace(/'/g, "\\'");
      const idEsc = escHtml(draftId).replace(/'/g, "\\'");
      confirmAction(this, () => { draftSend(idEsc, subjEsc); closePanel(key); });
    });

    // Discard → confirm then delete
    body.querySelector('.draft-discard-btn').addEventListener('click', function () {
      const subjEsc = escHtml(subjInput.value || subject).replace(/'/g, "\\'");
      const idEsc = escHtml(draftId).replace(/'/g, "\\'");
      confirmAction(this, () => { draftDiscard(idEsc, subjEsc); closePanel(key); });
    });

  } catch (e) {
    body.textContent = snippet || '(Could not load draft content)';
  }
}

// ── SVG icon helpers for file browser (emoji not supported in code-server) ──
function _svgIcon(type, size = 12) {
  const s = size;
  const icons = {
    folder: `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="#e8a838" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path></svg>`,
    file: `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"></path><polyline points="14 2 14 8 20 8"></polyline></svg>`,
    pdf: `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="#e74c3c" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="9" y1="15" x2="15" y2="15"></line></svg>`,
    image: `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="#3498db" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect><circle cx="8.5" cy="8.5" r="1.5"></circle><polyline points="21 15 16 10 5 21"></polyline></svg>`,
    spreadsheet: `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="#27ae60" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="8" y1="13" x2="16" y2="13"></line><line x1="8" y1="17" x2="16" y2="17"></line><line x1="12" y1="9" x2="12" y2="21"></line></svg>`,
    document: `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="#3498db" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line></svg>`,
    archive: `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="#9b59b6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 8v13H3V8"></path><path d="M23 3H1v5h22V3z"></path><line x1="10" y1="12" x2="14" y2="12"></line></svg>`,
    attachment: `<svg width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48"></path></svg>`,
  };
  return icons[type] || icons.file;
}

function _extToType(ext) {
  if (ext === 'pdf') return 'pdf';
  if (['png', 'jpg', 'jpeg', 'gif', 'svg', 'webp', 'bmp', 'ico'].includes(ext)) return 'image';
  if (['xls', 'xlsx', 'csv', 'tsv', 'ods'].includes(ext)) return 'spreadsheet';
  if (['doc', 'docx', 'txt', 'md', 'rtf', 'odt'].includes(ext)) return 'document';
  if (['zip', 'tar', 'gz', '7z', 'rar', 'bz2', 'xz'].includes(ext)) return 'archive';
  return 'file';
}

/** Shows inline download dialog when user double-clicks an attachment chip */
function _showAttachmentDownloadDialog(messageId, att, chipEl) {
  // Remove any existing dialog
  const old = document.getElementById('att-dl-dialog');
  if (old) old.remove();

  const ext = (att.name.split('.').pop() || '').toLowerCase();
  const sizeStr = att.size < 1024 ? att.size + ' B'
    : att.size < 1024 * 1024 ? (att.size / 1024).toFixed(1) + ' KB'
    : (att.size / (1024 * 1024)).toFixed(1) + ' MB';

  const dialog = document.createElement('div');
  dialog.id = 'att-dl-dialog';
  dialog.style.cssText = 'position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);z-index:10000;background:var(--vsc-panel);border:1px solid var(--vsc-border);border-radius:6px;padding:16px;min-width:320px;box-shadow:0 8px 24px rgba(0,0,0,0.4);font-size:12px;color:var(--vsc-text)';

  // Backdrop
  const backdrop = document.createElement('div');
  backdrop.style.cssText = 'position:fixed;top:0;left:0;width:100%;height:100%;z-index:9999;background:rgba(0,0,0,0.3)';
  backdrop.addEventListener('click', function () { backdrop.remove(); dialog.remove(); });

  // Header
  const header = document.createElement('div');
  header.style.cssText = 'display:flex;align-items:center;gap:6px;margin-bottom:12px;font-size:13px;font-weight:600';
  header.innerHTML = _svgIcon('attachment', 16) + ' Save Attachment';
  dialog.appendChild(header);

  // File info
  const info = document.createElement('div');
  info.style.cssText = 'display:flex;align-items:center;gap:6px;padding:8px;background:var(--vsc-bg);border-radius:4px;margin-bottom:12px';
  info.innerHTML = _svgIcon(_extToType(ext), 14) + ' <span>' + escHtml(att.name) + '</span> <span style="color:var(--vsc-muted)">(' + sizeStr + ')</span>';
  dialog.appendChild(info);

  // Destination input
  const destLabel = document.createElement('div');
  destLabel.style.cssText = 'font-size:11px;color:var(--vsc-muted);margin-bottom:4px';
  destLabel.textContent = 'Save to:';
  dialog.appendChild(destLabel);

  const destInput = document.createElement('input');
  destInput.type = 'text';
  destInput.value = '/workspaces/mail-attachments';
  destInput.style.cssText = 'width:100%;box-sizing:border-box;padding:6px 8px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:3px;font-size:11px;font-family:monospace;margin-bottom:12px';
  dialog.appendChild(destInput);

  // Buttons
  const btnRow = document.createElement('div');
  btnRow.style.cssText = 'display:flex;gap:8px;justify-content:flex-end';

  const cancelBtn = document.createElement('button');
  cancelBtn.textContent = 'Cancel';
  cancelBtn.style.cssText = 'padding:4px 12px;background:transparent;color:var(--vsc-muted);border:1px solid var(--vsc-border);border-radius:3px;cursor:pointer;font-size:11px';
  cancelBtn.addEventListener('click', function () { backdrop.remove(); dialog.remove(); });

  const saveBtn = document.createElement('button');
  saveBtn.innerHTML = _svgIcon('file', 11) + ' Save to Workspace';
  saveBtn.style.cssText = 'padding:4px 12px;background:var(--vsc-accent, #0078d4);color:#fff;border:none;border-radius:3px;cursor:pointer;font-size:11px;display:flex;align-items:center;gap:4px';

  saveBtn.addEventListener('click', async function () {
    saveBtn.disabled = true;
    saveBtn.textContent = 'Saving…';
    try {
      const res = await fetch(BASE + '/api/mail/attachment/' + messageId + '/save', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          attachment_id: att.attachment_id,
          filename: att.name,
          dest_dir: destInput.value.trim()
        }),
        signal: AbortSignal.timeout(30000)
      });
      const result = await res.json();
      if (!res.ok) throw new Error(result.error || 'Save failed');

      // Success: turn chip green
      chipEl.style.borderColor = '#27ae60';
      chipEl.style.background = 'rgba(39,174,96,0.1)';
      const checkSvg = '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#27ae60" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg>';
      chipEl.innerHTML = checkSvg + ' ' + escHtml(result.filename || att.name) + ' <span style="color:#27ae60">(saved)</span>';
      chipEl.title = 'Saved to ' + result.saved_path;

      backdrop.remove();
      dialog.remove();
    } catch (e) {
      saveBtn.disabled = false;
      saveBtn.innerHTML = _svgIcon('file', 11) + ' Save to Workspace';
      const err = document.createElement('div');
      err.style.cssText = 'color:#e74c3c;font-size:10px;margin-top:6px';
      err.textContent = 'Error: ' + e.message;
      // Remove old error if any
      const oldErr = dialog.querySelector('.dl-error');
      if (oldErr) oldErr.remove();
      err.className = 'dl-error';
      dialog.appendChild(err);
    }
  });

  btnRow.appendChild(cancelBtn);
  btnRow.appendChild(saveBtn);
  dialog.appendChild(btnRow);

  document.body.appendChild(backdrop);
  document.body.appendChild(dialog);
}

/** Opens a Compose New Email panel with To/Subject/Body fields + workspace file browser */
export function openComposePanel() {
  const key = 'compose-' + Date.now();
  const p = createPanel(key, 'New Email', 'Compose', '');
  const body = p.querySelector('.panel-body');
  body.style.whiteSpace = 'normal';

  // Track selected workspace files
  const selectedFiles = []; // { path, name, size }
  const MAX_BYTES = 25 * 1024 * 1024;

  body.innerHTML = `
    <div style="display:flex;flex-direction:column;gap:8px;padding:4px;flex:1">
      <label style="font-size:11px;color:var(--vsc-muted)">To:</label>
      <input type="text" class="compose-to" placeholder="recipient@example.com" style="width:100%;padding:6px 8px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
      <label style="font-size:11px;color:var(--vsc-muted)">Subject:</label>
      <input type="text" class="compose-subject" placeholder="Subject" style="width:100%;padding:6px 8px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
      <label style="font-size:11px;color:var(--vsc-muted)">Message:</label>
      <textarea class="compose-body" placeholder="Write your email…" style="width:100%;min-height:120px;flex:1;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;padding:8px;font-size:12px;font-family:inherit;resize:vertical"></textarea>
      <label style="font-size:11px;color:var(--vsc-muted)">Attachments:</label>
      <div class="compose-attach-row" style="display:flex;align-items:center;gap:6px;flex-wrap:wrap">
        <button class="compose-browse-btn" style="font-size:11px;padding:4px 10px;border-radius:4px;border:1px solid var(--vsc-border);background:var(--vsc-bg);color:var(--vsc-text);cursor:pointer;white-space:nowrap;display:inline-flex;align-items:center;gap:4px"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path></svg> Browse Workspace</button>
        <span class="compose-attach-total" style="font-size:10px;color:var(--vsc-muted)"></span>
      </div>
      <div class="compose-attach-chips" style="display:flex;flex-wrap:wrap;gap:4px"></div>
      <div style="display:flex;gap:8px;margin-top:4px">
        <button class="compose-send-btn" style="font-size:11px;padding:5px 14px;border-radius:4px;border:1px solid var(--vsc-accent,#007acc);background:var(--vsc-accent,#007acc);color:#fff;cursor:pointer"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><rect width="20" height="16" x="2" y="4" rx="2"></rect><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"></path></svg> Send Now</button>
        <button class="compose-draft-btn" style="font-size:11px;padding:5px 14px;border-radius:4px;border:1px solid var(--vsc-border);background:var(--vsc-bg);color:var(--vsc-text);cursor:pointer"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg> Save as Draft</button>
      </div>
    </div>
  `;

  const toInput = body.querySelector('.compose-to');
  const subjInput = body.querySelector('.compose-subject');
  const bodyTa = body.querySelector('.compose-body');
  const chipsEl = body.querySelector('.compose-attach-chips');
  const totalEl = body.querySelector('.compose-attach-total');

  function fmtSize(b) {
    if (b < 1024) return b + ' B';
    if (b < 1024 * 1024) return (b / 1024).toFixed(1) + ' KB';
    return (b / (1024 * 1024)).toFixed(1) + ' MB';
  }

  function updateChips() {
    chipsEl.innerHTML = '';
    let total = 0;
    selectedFiles.forEach((f, i) => {
      total += f.size;
      const chip = document.createElement('span');
      chip.style.cssText = 'display:inline-flex;align-items:center;gap:3px;padding:2px 6px;background:var(--vsc-bg);border:1px solid var(--vsc-border);border-radius:3px;font-size:10px;color:var(--vsc-text)';
      chip.innerHTML = `${_fileIcon(f.name)} ${escHtml(f.name)} <span style="color:var(--vsc-muted)">(${fmtSize(f.size)})</span>`;
      const rm = document.createElement('span');
      rm.textContent = '✕';
      rm.style.cssText = 'cursor:pointer;color:var(--vsc-muted);margin-left:2px';
      rm.addEventListener('click', () => { selectedFiles.splice(i, 1); updateChips(); });
      chip.appendChild(rm);
      chipsEl.appendChild(chip);
    });
    if (selectedFiles.length > 0) {
      const overLimit = total > MAX_BYTES;
      totalEl.textContent = fmtSize(total) + ' / 25 MB';
      totalEl.style.color = overLimit ? '#e74c3c' : 'var(--vsc-muted)';
    } else {
      totalEl.textContent = '';
    }
  }

  function _fileIcon(name) {
    return _svgIcon(_extToType((name.split('.').pop() || '').toLowerCase()));
  }

  // Browse Workspace button → opens modal
  body.querySelector('.compose-browse-btn').addEventListener('click', () => {
    openFileBrowserModal('/workspaces', (path, name, size) => {
      // Prevent duplicates
      if (selectedFiles.some(f => f.path === path)) { showToast(name + ' already added'); return; }
      const newTotal = selectedFiles.reduce((s, f) => s + f.size, 0) + size;
      if (newTotal > MAX_BYTES) { showToast('Total attachments would exceed 25 MB'); return; }
      selectedFiles.push({ path, name, size });
      updateChips();
    });
  });

  // Send Now
  body.querySelector('.compose-send-btn').addEventListener('click', async function () {
    const to = toInput.value.trim();
    const subj = subjInput.value.trim();
    const msg = bodyTa.value.trim();
    if (!to) { showToast('Recipient is required'); toInput.focus(); return; }
    if (!msg) { showToast('Message is empty'); bodyTa.focus(); return; }
    const totalSize = selectedFiles.reduce((s, f) => s + f.size, 0);
    if (totalSize > MAX_BYTES) { showToast('Total attachments exceed 25 MB'); return; }
    try {
      this.disabled = true;
      this.textContent = '⏳ Sending…';
      const payload = { to, subject: subj || '(No Subject)', body: msg };
      if (selectedFiles.length > 0) payload.attachment_paths = selectedFiles.map(f => f.path);
      const res = await fetch(`${BASE}/api/mail/send`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(30000)
      });
      if (!res.ok) { const d = await res.json().catch(() => ({})); throw new Error(d.error || `HTTP ${res.status}`); }
      showToast('Email sent to ' + to);
      closePanel(key);
    } catch (e) {
      showToast('Failed to send: ' + e.message);
      this.disabled = false;
      this.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><rect width="20" height="16" x="2" y="4" rx="2"></rect><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"></path></svg> Send Now';
    }
  });

  // Save as Draft
  body.querySelector('.compose-draft-btn').addEventListener('click', async function () {
    const to = toInput.value.trim();
    const subj = subjInput.value.trim();
    const msg = bodyTa.value.trim();
    if (!to) { showToast('Recipient is required'); toInput.focus(); return; }
    if (!msg) { showToast('Message is empty'); bodyTa.focus(); return; }
    const totalSize = selectedFiles.reduce((s, f) => s + f.size, 0);
    if (totalSize > MAX_BYTES) { showToast('Total attachments exceed 25 MB'); return; }
    try {
      this.disabled = true;
      this.textContent = '⏳ Saving…';
      const payload = { to, subject: subj || '(No Subject)', body: msg };
      if (selectedFiles.length > 0) payload.attachment_paths = selectedFiles.map(f => f.path);
      const res = await fetch(`${BASE}/api/mail/drafts`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(15000)
      });
      if (!res.ok) { const d = await res.json().catch(() => ({})); throw new Error(d.error || `HTTP ${res.status}`); }
      showToast('Saved as draft');
      closePanel(key);
      if (_draftBoxOpen) loadDrafts();
    } catch (e) {
      showToast('Failed to save draft: ' + e.message);
      this.disabled = false;
      this.innerHTML = '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg> Save as Draft';
    }
  });

  toInput.focus();
}

/** WO-MAIL-ATT-1d: File browser modal for workspace file attachments */
function openFileBrowserModal(startPath, onSelect) {
  // Dismiss any existing modal
  const existing = document.querySelector('.file-browser-overlay');
  if (existing) existing.remove();

  const overlay = document.createElement('div');
  overlay.className = 'file-browser-overlay';
  overlay.style.cssText = 'position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.5);z-index:10000;display:flex;align-items:center;justify-content:center';

  const modal = document.createElement('div');
  modal.style.cssText = 'width:420px;max-height:70vh;background:var(--vsc-bg,#1e1e1e);border:1px solid var(--vsc-border,#333);border-radius:8px;display:flex;flex-direction:column;overflow:hidden;box-shadow:0 8px 32px rgba(0,0,0,0.4)';

  const header = document.createElement('div');
  header.style.cssText = 'padding:10px 14px;border-bottom:1px solid var(--vsc-border);display:flex;align-items:center;gap:8px;flex-shrink:0';
  header.innerHTML = '<span style="font-size:13px;font-weight:600;color:var(--vsc-text);display:inline-flex;align-items:center;gap:6px">' + _svgIcon('folder', 14) + ' Browse Workspace</span>';
  const closeBtn = document.createElement('span');
  closeBtn.textContent = '✕';
  closeBtn.style.cssText = 'margin-left:auto;cursor:pointer;color:var(--vsc-muted);font-size:14px;padding:2px 4px';
  closeBtn.addEventListener('click', () => overlay.remove());
  header.appendChild(closeBtn);

  const breadcrumb = document.createElement('div');
  breadcrumb.style.cssText = 'padding:6px 14px;font-size:10px;color:var(--vsc-muted);border-bottom:1px solid var(--vsc-border);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex-shrink:0';

  const listEl = document.createElement('div');
  listEl.style.cssText = 'overflow-y:auto;flex:1;padding:4px 0';

  modal.appendChild(header);
  modal.appendChild(breadcrumb);
  modal.appendChild(listEl);
  overlay.appendChild(modal);
  document.body.appendChild(overlay);

  // Close on overlay click
  overlay.addEventListener('click', (e) => { if (e.target === overlay) overlay.remove(); });

  let currentPath = startPath;

  async function loadDir(dirPath) {
    currentPath = dirPath;
    breadcrumb.textContent = dirPath;
    listEl.innerHTML = '<div style="padding:16px;text-align:center;color:var(--vsc-muted);font-size:11px">Loading…</div>';
    try {
      const res = await fetch(`${BASE}/api/mail/browse?path=${encodeURIComponent(dirPath)}`, { signal: AbortSignal.timeout(5000) });
      if (!res.ok) { const d = await res.json().catch(() => ({})); throw new Error(d.error || 'Failed'); }
      const data = await res.json();
      listEl.innerHTML = '';

      // Back button (if not at root)
      if (dirPath !== '/workspaces') {
        const backRow = document.createElement('div');
        backRow.style.cssText = 'padding:6px 14px;cursor:pointer;display:flex;align-items:center;gap:6px;font-size:12px;color:var(--vsc-text)';
        backRow.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"></polyline></svg> <span style="color:var(--vsc-muted)">..</span>';
        backRow.addEventListener('click', () => loadDir(dirPath.replace(/\/[^/]+$/, '') || '/workspaces'));
        backRow.addEventListener('mouseenter', () => { backRow.style.background = 'var(--vsc-hover,rgba(255,255,255,0.05))'; });
        backRow.addEventListener('mouseleave', () => { backRow.style.background = ''; });
        listEl.appendChild(backRow);
      }

      // Sort: dirs first, then files
      const sorted = (data.entries || []).sort((a, b) => {
        if (a.type !== b.type) return a.type === 'dir' ? -1 : 1;
        return a.name.localeCompare(b.name);
      });

      if (sorted.length === 0) {
        listEl.innerHTML += '<div style="padding:16px;text-align:center;color:var(--vsc-muted);font-size:11px">(empty)</div>';
        return;
      }

      for (const entry of sorted) {
        const row = document.createElement('div');
        row.style.cssText = 'padding:5px 14px;cursor:pointer;display:flex;align-items:center;gap:6px;font-size:12px;color:var(--vsc-text)';
        row.addEventListener('mouseenter', () => { row.style.background = 'var(--vsc-hover,rgba(255,255,255,0.05))'; });
        row.addEventListener('mouseleave', () => { row.style.background = ''; });

        const fullPath = data.path + '/' + entry.name;

        if (entry.type === 'dir') {
          row.innerHTML = `${_svgIcon('folder', 14)} <span>${escHtml(entry.name)}</span>`;
          row.addEventListener('click', () => loadDir(fullPath));
        } else {
          const ext = (entry.name.split('.').pop() || '').toLowerCase();
          const icon = _svgIcon(_extToType(ext), 14);

          const sizeStr = entry.size < 1024 ? entry.size + ' B'
            : entry.size < 1024 * 1024 ? (entry.size / 1024).toFixed(1) + ' KB'
            : (entry.size / (1024 * 1024)).toFixed(1) + ' MB';

          row.innerHTML = `${icon} <span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${escHtml(entry.name)}</span> <span style="color:var(--vsc-muted);font-size:10px;flex-shrink:0">${sizeStr}</span>`;

          const addBtn = document.createElement('span');
          addBtn.textContent = '+';
          addBtn.style.cssText = 'width:18px;height:18px;display:flex;align-items:center;justify-content:center;border-radius:3px;background:var(--vsc-accent,#007acc);color:#fff;font-size:12px;font-weight:bold;cursor:pointer;flex-shrink:0';
          addBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            onSelect(fullPath, entry.name, entry.size);
            addBtn.textContent = '✓';
            addBtn.style.background = '#28a745';
            setTimeout(() => { addBtn.textContent = '+'; addBtn.style.background = 'var(--vsc-accent,#007acc)'; }, 800);
          });
          row.appendChild(addBtn);
        }
        listEl.appendChild(row);
      }
    } catch (e) {
      listEl.innerHTML = `<div style="padding:16px;text-align:center;color:#e74c3c;font-size:11px">Error: ${escHtml(e.message)}</div>`;
    }
  }

  loadDir(startPath);
}

/** Opens a Create Calendar Event panel with form fields + Google Meet option */

// ── Gmail auth state + unread count ──
// ── Gmail auth state + unread count ───────────────────────────────────
export async function loadUnreadCount() {
  const statEl = document.getElementById('stat-mail');
  try {
    // Step 1: probe auth status
    const authRes = await fetch(`${BASE}/api/auth/status`, { signal: AbortSignal.timeout(4000) });
    // Guard: reject HTML responses (nginx 502/504 during container startup)
    const authCt = (authRes.headers.get('content-type') || '');
    if (!authRes.ok || !authCt.includes('json')) {
      if (statEl) statEl.textContent = '—';
      return;
    }
    const auth = await authRes.json();
    if (!auth.connected) {
      // Show clickable Connect Google button with proper SVG icon
      if (statEl) {
        statEl.innerHTML = `<button id="btn-connect-google" title="Connect your Google account" style="background:none;border:1px solid var(--vsc-accent,#007acc);color:var(--vsc-accent,#007acc);border-radius:4px;padding:2px 7px;font-size:0.68em;cursor:pointer;white-space:nowrap;display:inline-flex;align-items:center;gap:3px;"><svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z"/><path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/><path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/><path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/></svg> Connect Google</button>`;
        document.getElementById('btn-connect-google')?.addEventListener('click', async (e) => {
          e.stopPropagation();
          const btn = e.currentTarget;
          btn.innerHTML = '<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" style="animation:spin 0.7s linear infinite"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg> Opening…';
          btn.disabled = true;
          try {
            const r = await fetch(`${BASE}/api/auth/start`, { signal: AbortSignal.timeout(8000) });
            if (r.status === 429) throw new Error('Rate limited – wait a few min');
            const ct = (r.headers.get('content-type') || '');
            if (!ct.includes('json')) throw new Error('Service not ready – retry');
            const d = await r.json();
            if (!r.ok || !d.auth_url) throw new Error(d.error || 'No auth URL returned');
            // Relay URL to host browser via nginx /api/open-url proxy (Pattern #13)
            const relayRes = await fetch(`${BASE}/api/open-url?url=${encodeURIComponent(d.auth_url)}`, { signal: AbortSignal.timeout(4000) });
            if (!relayRes.ok) throw new Error('relay_failed');
            btn.innerHTML = '<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"></polyline></svg> Check browser';
            setTimeout(() => loadUnreadCount(), 5000); // Re-poll after a few seconds
          } catch (err) {
            btn.innerHTML = '<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line></svg> ' + (err.message || 'Error');
            btn.disabled = false;
          }
        });
      }
      return;
    }
    // Step 2: connected — fetch unread count from Qdrant (reconciled with Gmail)
    // WO-MAIL-SYNC-3/8: Use /unread-indexed-count?sync=true (Qdrant + reconciliation)
    const res = await fetch(`${BASE}/api/mail/unread-indexed-count?sync=true`, { signal: AbortSignal.timeout(15000) });
    if (!res.ok) return;
    const resCt = (res.headers.get('content-type') || '');
    if (!resCt.includes('json')) return; // Guard against HTML from nginx
    const data = await res.json();
    if (statEl) statEl.textContent = data.unread ?? 0;
  } catch (e) { /* keep whatever was shown */ }
}


// ── Infinite Scroll State ──
// ── Infinite Scroll State ─────────────────────────────────────────────
let _mailOffset = null;   // Qdrant next_page_offset (point ID cursor)
let _mailHasMore = true;
let _mailLoading = false;
let _mailTotalLoaded = 0;
let _mailObserver = null;
// Cursor state for order_by pagination (Qdrant disables next_page_offset with order_by)
let _mailLastEpoch = null;   // last date_epoch value seen
let _mailSeenIds = [];       // IDs already loaded (for must_not dedup)
let _mailTotal = null;       // total emails in Qdrant (fetched once)
let _mailEpochIndex = null;  // cached [{ id, epoch }] for click-to-jump (fetched once in background)
let _mailJumped = false;     // true after a click-to-jump (prevents auto-refresh reset)
let _mailFirstLoaded = 0;    // index of first loaded item (for upward scroll)
let _mailLoadingUp = false;  // guard for upward loading
let _mailLabelFilter = '';   // WO-GSYNC-7: active label filter ('' = all)

/** Fetch all mail epoch values in background for click-to-jump scrollbar */
export async function fetchMailEpochIndex() {
  try {
    const res = await fetch(`${BASE}/api/emails`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        limit: 10000,
        with_payload: ['date_epoch'],
        with_vectors: false,
        order_by: { key: 'date_epoch', direction: 'desc' }
      }),
      signal: AbortSignal.timeout(15000)
    });
    if (!res.ok) return;
    const data = await res.json();
    const pts = data.result?.points || [];
    _mailEpochIndex = pts.map(p => ({ id: p.id, epoch: p.payload?.date_epoch ?? 0 }));
    console.log(`[scrollbar] Epoch index loaded: ${_mailEpochIndex.length} items`);
  } catch (e) {
    console.warn('[scrollbar] Failed to load epoch index:', e.message);
  }
}

/** Jump mail list to a specific position (0-based item index) */
export async function jumpToMailOffset(targetItem) {
  if (!_mailEpochIndex || _mailEpochIndex.length === 0) return;
  if (_mailLoading) return;

  // Clamp to valid range
  const idx = Math.max(0, Math.min(targetItem, _mailEpochIndex.length - 1));

  // Get the epoch + IDs around the target position
  const targetEpoch = _mailEpochIndex[idx].epoch;

  // Collect IDs BEFORE the target position with the same epoch (for dedup)
  const sameEpochIds = [];
  for (let i = 0; i < idx; i++) {
    if (_mailEpochIndex[i].epoch === targetEpoch) sameEpochIds.push(_mailEpochIndex[i].id);
  }

  // Reset mail state
  _mailLastEpoch = targetEpoch;
  _mailSeenIds = sameEpochIds;
  _mailTotalLoaded = idx;
  _mailFirstLoaded = idx;
  _mailHasMore = true;
  _mailPayloads = [];
  _mailLoading = false;
  _mailJumped = true;  // prevent auto-refresh from resetting position

  // Show loading state
  setBody('mail-body', '<div class="empty-msg" style="opacity:0.5">Loading...</div>');

  // Disconnect existing observer so it gets re-created after jump
  if (_mailObserver) { _mailObserver.disconnect(); _mailObserver = null; }

  // Load from the target position
  await loadMail(false, idx);

  // Scroll the body to top after jump
  document.getElementById('mail-body').scrollTop = 0;
}

/** Load earlier emails when user scrolls to top (upward infinite scroll) */
export async function loadMailUpward() {
  if (_mailLoadingUp || !_mailEpochIndex || _mailFirstLoaded <= 0) return;
  _mailLoadingUp = true;

  try {
    // Calculate how many items to load above
    const loadCount = Math.min(EMAIL_PAGE_SIZE, _mailFirstLoaded);
    const startIdx = _mailFirstLoaded - loadCount;

    // Get epoch + dedup IDs for the upward batch
    const upEpoch = _mailEpochIndex[startIdx].epoch;
    const upSeenIds = [];
    for (let i = 0; i < startIdx; i++) {
      if (_mailEpochIndex[i].epoch === upEpoch) upSeenIds.push(_mailEpochIndex[i].id);
    }

    const body = {
      limit: loadCount,
      with_payload: true,
      with_vectors: false,
      order_by: { key: 'date_epoch', direction: 'desc', start_from: upEpoch }
    };
    if (upSeenIds.length > 0) {
      body.filter = { must_not: [{ has_id: upSeenIds }] };
    }

    const res = await fetch(`${BASE}/api/emails`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10000)
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    const points = data.result?.points || [];
    if (points.length === 0) { _mailLoadingUp = false; return; }

    // Prepend rows and preserve scroll position
    const mailBody = document.getElementById('mail-body');
    const oldScrollH = mailBody.scrollHeight;
    const html = points.map(buildMailRow).join('');
    mailBody.insertAdjacentHTML('afterbegin', html);
    // Restore scroll so content doesn't jump
    mailBody.scrollTop = mailBody.scrollHeight - oldScrollH;

    // Update state
    _mailFirstLoaded = startIdx;
    _mailTotalLoaded += points.length;
    // Add to payloads and seen IDs
    for (const p of points) {
      _mailPayloads.unshift(p.payload || {});
      _mailSeenIds.push(p.id);
    }

    // Update badge
    const totalStr = _mailTotal !== null ? ` (${_mailTotal})` : '';
    setCount('mail-count', `${_mailFirstLoaded + 1}–${_mailFirstLoaded + _mailTotalLoaded}${totalStr}`);
  } catch (e) {
    console.warn('[mail] Upward load failed:', e.message);
  } finally {
    _mailLoadingUp = false;
  }
}


// Mail payload store for detail modal (mirrors calendar pattern)
let _mailPayloads = [];

/** Build a single email row HTML */

// ── buildMailRow + openMailDetailByIdx ──
function buildMailRow(p) {
  const pl = p.payload || {};
  const subj = pl.subject || pl.Subject || '(no subject)';
  const from = pl.sender || pl.from || pl.From || '';
  const date = pl.date || pl.Date || '';
  const rawSnippet = pl.snippet || pl.body || '';
  const snippet = cleanSnippet(rawSnippet, 150);
  const msgId = pl.gmail_id || pl.message_id || p.id || '';
  const kiloB64 = encKiloData({ type: 'mail', subject: subj, sender: from, date: date, snippet: snippet });
  // Absent is_read (historical emails) defaults to true (read) — no dot shown
  const isUnread = pl.is_read === false;

  _mailPayloads.push({ id: msgId, subject: subj, from: from, date: date, snippet: snippet, is_read: !isUnread });

  const unreadClass = isUnread ? ' row-unread' : '';
  const iconHtml = isUnread
    ? '<span class="unread-dot"></span>'
    : '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="20" height="16" x="2" y="4" rx="2"></rect><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"></path></svg>';

  return `<div class="row${unreadClass}" onclick="openMailDetailByIdx('${msgId}')" data-kilo="${kiloB64}" data-msg-id="${msgId}" oncontextmenu="onMailContextMenu(event,this)" style="cursor:pointer" title="Click to read · Right-click for actions">
    <span class="row-icon">${iconHtml}</span>
    <div class="row-body">
      <div class="row-title">${escHtml(subj)}</div>
      <div class="row-sub">
        <span class="row-sender">${escHtml(from)}</span>
        <span class="row-date">${escHtml(fmtDate(date))}</span>
        ${pl.has_attachments ? '<span style="color:var(--vsc-muted);margin-left:2px" title="Has attachments"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48"></path></svg></span>' : ''}
      </div>
      ${snippet ? '<div class="row-snippet">' + escHtml(snippet) + '</div>' : ''}
    </div>
    <button class="kilo-btn" onclick="event.stopPropagation();onMailContextMenu(event,this.closest('.row'))" title="Actions"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg></button>
  </div>`;
}

export function openMailDetailByIdx(msgId) {
  if (_kiloMenuActive) return;
  const m = _mailPayloads.find(p => p.id === msgId);
  if (!m) return;
  openMailDetail(m.id, m.subject, m.from, m.date, m.snippet);
}


// ── Email Search ──
// ── Email Search (WO-EMAIL-5) ──────────────────────────────────────
let _searchDebounce = null;
let _inSearchMode = false;

export async function searchEmails(query) {
  if (!query.trim()) { exitSearchMode(); return; }
  enterSearchMode();
  try {
    const res = await fetch(`${BASE}/api/mail/search?q=${encodeURIComponent(query)}&limit=20`,
      { signal: AbortSignal.timeout(10000) });
    if (!res.ok) { renderSearchResults([]); return; }
    const data = await res.json();
    renderSearchResults(data.results || []);
  } catch (e) {
    renderSearchResults([]);
  }
}

export function enterSearchMode() {
  _inSearchMode = true;
  document.getElementById('mail-body').style.display = 'none';
  document.getElementById('mail-search-results').style.display = 'block';
  document.getElementById('mail-search-clear').style.display = 'block';
  // Hide custom scrollbar — search results use native scroll
  const col = document.getElementById('mail-body')?.closest('.col');
  if (col) col.querySelectorAll('.custom-scrollbar-track').forEach(t => t.style.display = 'none');
}

export function exitSearchMode() {
  _inSearchMode = false;
  document.getElementById('mail-search-results').style.display = 'none';
  document.getElementById('mail-body').style.display = 'block';
  document.getElementById('mail-search-clear').style.display = 'none';
  document.getElementById('mail-search-input').value = '';
  // Restore custom scrollbar for main inbox
  const col = document.getElementById('mail-body')?.closest('.col');
  if (col) col.querySelectorAll('.custom-scrollbar-track').forEach(t => t.style.display = '');
}

function renderSearchResults(results) {
  const container = document.getElementById('mail-search-results');
  if (!results.length) {
    container.innerHTML = '<div class="empty-msg">No results found</div>';
    return;
  }
  container.innerHTML = results.map(r => {
    const snippet = cleanSnippet(r.snippet, 150);
    const scorePct = Math.round((r.score || 0) * 100);
    const kiloB64 = encKiloData({ type: 'mail', subject: r.subject, sender: r.from, date: r.date, snippet: snippet });
    return `<div class="row" onclick="openMailDetail('${escHtml(r.id)}','${escHtml(r.subject).replace(/'/g, '\\&#39;')}','${escHtml(r.from).replace(/'/g, '\\&#39;')}','${escHtml(r.date)}','${escHtml(snippet).replace(/'/g, '\\&#39;')}')" data-kilo="${kiloB64}" data-msg-id="${escHtml(r.id)}" oncontextmenu="onMailContextMenu(event,this)" style="cursor:pointer" title="Click to read · Right-click for actions">
      <span class="row-icon"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="20" height="16" x="2" y="4" rx="2"></rect><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"></path></svg></span>
      <div class="row-body">
        <div class="row-title">${escHtml(r.subject)}</div>
        <div class="row-sub">
          <span class="row-sender">${escHtml(r.from)}</span>
          <span class="row-date">${escHtml(fmtDate(r.date))}</span>
          ${r.has_attachments ? '<span style="color:var(--vsc-muted);margin-left:2px" title="Has attachments"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21.44 11.05-9.19 9.19a6 6 0 0 1-8.49-8.49l8.57-8.57A4 4 0 1 1 18 8.84l-8.59 8.57a2 2 0 0 1-2.83-2.83l8.49-8.48"></path></svg></span>' : ''}
          <span class="search-result-score">${scorePct}%</span>
        </div>
        ${snippet ? '<div class="row-snippet">' + escHtml(snippet) + '</div>' : ''}
      </div>
      <button class="kilo-btn" onclick="event.stopPropagation();onMailContextMenu(event,this.closest('.row'))" title="Actions"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg></button>
    </div>`;
  }).join('');
  // Force scrollbar thumb recalculation for search results container
  requestAnimationFrame(() => {
    container.dispatchEvent(new Event('scroll'));
  });
}

// Wire search events (WO-EMAIL-5)
document.addEventListener('DOMContentLoaded', () => {
  // -- FIX-1: Custom scrollbar for each .col-body --
  document.querySelectorAll('.col-body').forEach(body => {
    const col = body.closest('.col');
    if (!col) return;
    // Create track
    const track = document.createElement('div');
    track.className = 'custom-scrollbar-track';
    const thumb = document.createElement('div');
    thumb.className = 'custom-scrollbar-thumb';
    track.appendChild(thumb);
    col.appendChild(track);

    function updateThumb() {
      // Skip scrollbar update for mail column during search mode
      if (_inSearchMode && (body.id === 'mail-body' || body.id === 'mail-search-results')) {
        track.style.display = 'none';
        return;
      }
      const { scrollTop, scrollHeight, clientHeight } = body;
      if (scrollHeight <= clientHeight) {
        track.style.display = 'none';
        return;
      }
      track.style.display = '';
      const trackH = track.clientHeight;

      // For infinite-scroll lists, use total item count for proportional thumb + position
      let ratio = clientHeight / scrollHeight;
      let posRatio = scrollTop / (scrollHeight - clientHeight);
      const countBadge = col.querySelector('.col-count');
      if (countBadge) {
        // Badge format: "26–50 (5279)" or "1–25 (5279)"
        const m = countBadge.textContent.match(/(\d+)\s*[–-]\s*(\d+)\s*\((\d+)\)/);
        if (m) {
          const rangeStart = parseInt(m[1], 10);
          const rangeEnd = parseInt(m[2], 10);
          const totalItems = parseInt(m[3], 10);
          if (totalItems > 0) {
            const loadedItems = body.querySelectorAll('.row').length;
            const itemH = loadedItems > 0 ? scrollHeight / loadedItems : 80;
            const visibleItems = Math.ceil(clientHeight / itemH);
            ratio = Math.min(1, visibleItems / totalItems);

            // Position: blend scroll position within loaded content + global position
            const localFrac = scrollTop / Math.max(1, scrollHeight - clientHeight);
            const currentItem = rangeStart + localFrac * (rangeEnd - rangeStart);
            posRatio = Math.min(1, currentItem / totalItems);
          }
        }
      }

      const thumbH = Math.max(20, trackH * ratio);
      const thumbTop = posRatio * (trackH - thumbH);
      thumb.style.height = thumbH + 'px';
      thumb.style.top = thumbTop + 'px';
    }
    body.addEventListener('scroll', updateThumb);
    // Upward infinite scroll: load earlier items when at top
    if (body.id === 'mail-body') {
      body.addEventListener('scroll', () => {
        if (body.scrollTop < 5 && _mailJumped && _mailFirstLoaded > 0) {
          loadMailUpward();
        }
      });
    }
    new MutationObserver(updateThumb).observe(body, { childList: true, subtree: true });
    // Also watch the count badge for text updates (total count arrives async)
    const badge = col.querySelector('.col-count');
    if (badge) new MutationObserver(updateThumb).observe(badge, { childList: true, characterData: true, subtree: true });
    updateThumb();
    // Fallback: re-run after data loads
    setTimeout(updateThumb, 3000);

    // Drag support
    let dragging = false, startY = 0, startScroll = 0;
    thumb.addEventListener('mousedown', e => {
      e.preventDefault();
      dragging = true;
      startY = e.clientY;
      startScroll = body.scrollTop;
      thumb.classList.add('dragging');
      document.body.style.userSelect = 'none';
    });
    document.addEventListener('mousemove', e => {
      if (!dragging) return;
      const { scrollHeight, clientHeight } = body;
      const trackH = track.clientHeight;
      const ratio = clientHeight / scrollHeight;
      const thumbH = Math.max(30, trackH * ratio);
      const dy = e.clientY - startY;
      const scrollRange = scrollHeight - clientHeight;
      const trackRange = trackH - thumbH;
      body.scrollTop = startScroll + (dy / trackRange) * scrollRange;
    });
    document.addEventListener('mouseup', () => {
      if (dragging) {
        dragging = false;
        thumb.classList.remove('dragging');
        document.body.style.userSelect = '';
      }
    });

    // Click on track to jump
    track.addEventListener('click', e => {
      if (e.target === thumb) return;
      const rect = track.getBoundingClientRect();
      const clickY = e.clientY - rect.top;
      const ratio = clickY / track.clientHeight;

      // For mail column: use epoch index for global jump
      if (body.id === 'mail-body' && _mailEpochIndex && _mailTotal) {
        const targetItem = Math.round(ratio * _mailTotal);
        jumpToMailOffset(targetItem);
        return;
      }

      // For other columns: jump within loaded content
      body.scrollTop = ratio * (body.scrollHeight - body.clientHeight);
    });
  });

  const searchInput = document.getElementById('mail-search-input');
  searchInput.addEventListener('input', () => {
    clearTimeout(_searchDebounce);
    _searchDebounce = setTimeout(() => searchEmails(searchInput.value), 400);
  });
  searchInput.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && _inSearchMode) { exitSearchMode(); e.stopPropagation(); }
    // Enter key triggers search immediately (Browse Lite fallback)
    if (e.key === 'Enter') { clearTimeout(_searchDebounce); searchEmails(searchInput.value); }
  });
  // Search button click (Browse Lite compatibility — input events may not fire)
  const searchGoBtn = document.getElementById('mail-search-go');
  if (searchGoBtn) searchGoBtn.addEventListener('click', () => searchEmails(searchInput.value));
  document.getElementById('mail-search-clear').addEventListener('click', exitSearchMode);

  // Browse Lite fallback: poll input value every 500ms to detect changes
  // (Browse Lite's embedded Chromium may swallow keyboard 'input' events)
  let _lastSearchVal = '';
  setInterval(() => {
    const v = searchInput.value;
    if (v !== _lastSearchVal) {
      _lastSearchVal = v;
      clearTimeout(_searchDebounce);
      if (v.trim()) _searchDebounce = setTimeout(() => searchEmails(v), 400);
      else if (_inSearchMode) exitSearchMode();
    }
  }, 500);

  // WO-GSYNC-7: Label filter — custom dropdown (Browse Lite compatible)
  const labelTrigger = document.getElementById('mail-label-trigger');
  const labelOptions = document.getElementById('mail-label-options');
  if (labelTrigger && labelOptions) {
    // Toggle dropdown on click
    labelTrigger.addEventListener('click', (e) => {
      e.stopPropagation();
      const isOpen = labelOptions.style.display !== 'none';
      labelOptions.style.display = isOpen ? 'none' : 'block';
    });
    // Option click → update filter and reload
    labelOptions.querySelectorAll('.custom-select-option').forEach(opt => {
      opt.addEventListener('mouseenter', () => { opt.style.background = 'var(--vsc-hover)'; });
      opt.addEventListener('mouseleave', () => { opt.style.background = ''; });
      opt.addEventListener('click', (e) => {
        e.stopPropagation();
        const val = opt.dataset.value;
        // Update trigger text (keep the chevron SVG)
        const svg = labelTrigger.querySelector('svg');
        labelTrigger.textContent = opt.textContent;
        if (svg) labelTrigger.appendChild(svg);
        labelOptions.style.display = 'none';
        _mailLabelFilter = val;
        // Reset pagination state
        _mailLastEpoch = null;
        _mailSeenIds = [];
        _mailTotalLoaded = 0;
        _mailFirstLoaded = 0;
        _mailHasMore = true;
        _mailTotal = null;
        _mailLoading = false;
        _mailJumped = false;
        if (_mailObserver) { _mailObserver.disconnect(); _mailObserver = null; }
        // Reload
        loadMail(false);
      });
    });
    // Close dropdown when clicking outside
    document.addEventListener('click', () => { labelOptions.style.display = 'none'; });
  }
});


// updateSentinel imported from core.js

export async function loadMail(append = false, jumpOffset = 0) {
  if (_mailLoading) return;
  if (append && !_mailHasMore) return;
  _mailLoading = true;

  try {
    const body = {
      limit: EMAIL_PAGE_SIZE,
      with_payload: true,
      with_vectors: false,
      order_by: { key: 'date_epoch', direction: 'desc' }
    };

    // Fetch total count from Qdrant on first load (non-blocking)
    if (!append && _mailTotal === null) {
      fetch(`${BASE}/api/emails-count`, { signal: AbortSignal.timeout(5000) })
        .then(r => r.ok ? r.json() : null)
        .then(d => {
          if (d?.result?.points_count != null) {
            _mailTotal = d.result.points_count;
            // Update counter with total
            const el = document.getElementById('mail-count');
            if (el && _mailTotalLoaded > 0) {
              el.textContent = `1\u2013${_mailTotalLoaded} (${_mailTotal})`;
            }
          }
        })
        .catch(() => { });
    }

    // Cursor-based pagination for order_by (Qdrant disables next_page_offset)
    // Apply cursor when appending OR when jumping to a specific offset
    if ((append || jumpOffset > 0) && _mailLastEpoch !== null) {
      body.order_by.start_from = _mailLastEpoch;
      if (_mailSeenIds.length > 0) {
        if (!body.filter) body.filter = {};
        if (!body.filter.must_not) body.filter.must_not = [];
        body.filter.must_not.push({ has_id: _mailSeenIds });
      }
    }

    // WO-GSYNC-7: Label filter
    if (_mailLabelFilter) {
      if (!body.filter) body.filter = {};
      if (!body.filter.must) body.filter.must = [];
      body.filter.must.push({
        key: 'labels',
        match: { value: _mailLabelFilter }
      });
    }

    if (append) updateSentinel('mail-body', true, true);

    const res = await fetch(`${BASE}/api/emails`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10000)
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    const points = (data.result?.points || []);

    // Update cursor for next page
    if (points.length > 0) {
      const lastPoint = points[points.length - 1];
      _mailLastEpoch = lastPoint.payload?.date_epoch ?? 0;
      // Track IDs to exclude on next page (avoid duplicates with same epoch)
      for (const p of points) _mailSeenIds.push(p.id);
    }
    _mailHasMore = points.length >= EMAIL_PAGE_SIZE;

    if (!append) {
      // First load: reset state (but preserve offset if jumping)
      if (jumpOffset > 0) {
        // Jump mode: keep _mailTotalLoaded as set by jumpToMailOffset
      } else {
        _mailTotalLoaded = 0;
      }
      _mailPayloads = [];
      if (!points.length) {
        setCount('mail-count', '0 (0)');
        setBody('mail-body', '<div class="empty-msg">No emails indexed yet</div>');
        _mailLoading = false;
        return;
      }
      setBody('mail-body', points.map(buildMailRow).join(''));
    } else {
      // Append mode: add rows before sentinel
      appendBody('mail-body', points.map(buildMailRow).join(''));
    }

    _mailTotalLoaded += points.length;
    const rangeStart = _mailTotalLoaded - points.length + 1;
    const totalStr = _mailTotal !== null ? ` (${_mailTotal})` : '';
    setCount('mail-count', `${rangeStart}–${_mailTotalLoaded}${totalStr}`);
    updateSentinel('mail-body', _mailHasMore, false);

    // Set up observer if not yet done
    if (!_mailObserver) {
      setupMailObserver();
    }

  } catch (e) {
    if (!append) {
      setBody('mail-body', `<div class="error-msg"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line></svg> Could not load emails<br><small>${escHtml(e.message)}</small></div>`);
    }
  } finally {
    _mailLoading = false;
  }
}

export function setupMailObserver() {
  const scrollContainer = document.getElementById('mail-body').closest('.col-body') || document.getElementById('mail-body');
  _mailObserver = new IntersectionObserver((entries) => {
    if (entries[0]?.isIntersecting && _mailHasMore && !_mailLoading) {
      loadMail(true);
    }
  }, { root: scrollContainer, rootMargin: '100px' });
  const sentinel = document.getElementById('mail-body').querySelector('.scroll-sentinel');
  if (sentinel) _mailObserver.observe(sentinel);
}


// ── Draft Box ──
// ── Draft Box (WO-MAIL-7) ────────────────────────────────────────────
let _draftBoxOpen = false;

export function toggleDraftBox() {
  _draftBoxOpen = !_draftBoxOpen;
  const box = document.getElementById('draft-body');
  box.style.display = _draftBoxOpen ? '' : 'none';
  if (_draftBoxOpen) loadDrafts();
}

export async function loadDrafts() {
  try {
    const res = await fetch(`${BASE}/api/mail/drafts`, { signal: AbortSignal.timeout(10000) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    const drafts = data.drafts || [];

    document.getElementById('draft-count').textContent = drafts.length;

    if (!drafts.length) {
      setBody('draft-body', '<div class="empty-msg">No drafts</div>');
      return;
    }

    setBody('draft-body', drafts.map(d => {
      const subj = d.subject || '(no subject)';
      const to = d.to || '';
      const snippet = d.snippet || '';
      const draftId = d.id || '';
      const idEsc = escHtml(draftId).replace(/'/g, "\\'");
      const subjEsc = escHtml(subj).replace(/'/g, "\\'");
      const toEsc = escHtml(to).replace(/'/g, "\\'");
      const snippetEsc = escHtml(snippet).replace(/'/g, "\\'");

      // Show snippet as title if subject is missing
      const displayTitle = (!subj || subj === '(no subject)' || subj === '(No Subject)')
        ? (snippet ? snippet.substring(0, 60) + (snippet.length > 60 ? '…' : '') : '(No Subject)')
        : subj;
      const displayTo = to || '(no recipient set)';

      return `<div class="draft-row" style="cursor:default" title="Click Review to preview before sending">
    <span class="row-icon" style="color: var(--vsc-amber)"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path><path d="M18.5 2.5a2.121 2.121 0 1 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path></svg></span>
    <div class="row-body">
      <div class="row-title">${escHtml(displayTitle)}</div>
      <div class="row-sub">
        <span class="row-sender" style="${to ? '' : 'color:var(--vsc-muted);font-style:italic'}">To: ${escHtml(displayTo)}</span>
      </div>
      <div class="draft-actions">
        <button class="draft-btn" onclick="event.stopPropagation(); openDraftPanel('${idEsc}','${subjEsc}','${toEsc}','${snippetEsc}')" title="Review draft content before sending" style="background:var(--vsc-accent,#007acc);color:#fff;border-color:var(--vsc-accent,#007acc)">⊕ Review</button>
        <button class="draft-btn send" onclick="event.stopPropagation(); confirmAction(this, () => draftSend('${idEsc}','${subjEsc}'))" title="Send this draft">✓ Send</button>
        <button class="draft-btn discard" onclick="event.stopPropagation(); confirmAction(this, () => draftDiscard('${idEsc}','${subjEsc}'))" title="Delete this draft">✕ Discard</button>
      </div>
    </div>
  </div>`;
    }).join(''));

  } catch (e) {
    setBody('draft-body', `<div class="error-msg"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line></svg> Could not load drafts<br><small>${escHtml(e.message)}</small></div>`);
  }
}

export async function draftSend(draftId, subject) {
  try {
    const res = await fetch(`${BASE}/api/mail/drafts/${draftId}/send`, { method: 'POST', signal: AbortSignal.timeout(15000) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    showToast(`Sent: ${subject}`);
    loadDrafts();
  } catch (e) {
    showToast(`Failed to send: ${e.message}`);
  }
}

export async function draftDiscard(draftId, subject) {
  try {
    const res = await fetch(`${BASE}/api/mail/drafts/${draftId}`, { method: 'DELETE', signal: AbortSignal.timeout(10000) });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    showToast(`Discarded: ${subject}`);
    loadDrafts();
  } catch (e) {
    showToast(`Failed to discard: ${e.message}`);
  }
}

/** Inline confirmation: first click → "Sure?", second click within 3s → executes */
export function confirmAction(btn, action) {
  if (btn.dataset.armed === 'true') {
    action();
    return;
  }
  const origText = btn.textContent;
  const origClass = btn.className;
  btn.textContent = 'Sure?';
  btn.classList.add('armed');
  btn.dataset.armed = 'true';
  const timer = setTimeout(() => {
    btn.textContent = origText;
    btn.classList.remove('armed');
    btn.dataset.armed = '';
  }, 3000);
  btn.addEventListener('click', function once() {
    clearTimeout(timer);
    btn.removeEventListener('click', once);
  }, { once: true });
}


// ── State accessors (used by app.js orchestrator) ──
export function getMailState() {
  return { mailJumped: _mailJumped, mailEpochIndex: _mailEpochIndex, draftBoxOpen: _draftBoxOpen };
}
export function resetMailState() {
  _mailLoading = false; // Critical: reset loading guard to prevent stuck state
  _mailOffset = null; _mailHasMore = true; _mailTotalLoaded = 0; _mailPayloads = [];
  _mailLastEpoch = null; _mailSeenIds = []; _mailTotal = null;
  if (_mailObserver) { _mailObserver.disconnect(); _mailObserver = null; }
}

// ── Window exports (HTML onclick handlers) ──
window.openMailDetail = openMailDetail;
window.openMailDetailByIdx = openMailDetailByIdx;
window.openDraftPanel = openDraftPanel;
window.openComposePanel = openComposePanel;
window.toggleDraftBox = toggleDraftBox;
window.draftSend = draftSend;
window.draftDiscard = draftDiscard;
window.confirmAction = confirmAction;
window.jumpToMailOffset = jumpToMailOffset;
window.loadMailUpward = loadMailUpward;// ── WO-GSYNC-11: Email Context Menu (Archive / Star / Trash + Kilo AI) ──────
let _mailMenu = null;

function dismissMailMenu() {
  if (_mailMenu) { _mailMenu.remove(); _mailMenu = null; }
}

async function _doMailAction(action, msgId, rowEl) {
  const mailBase = `${BASE}/api/mail`;
  try {
    let res;
    switch (action) {
      case 'archive':
        res = await fetch(`${mailBase}/archive/${msgId}`, { method: 'POST' });
        if (res.ok && rowEl) { rowEl.style.transition = 'opacity 0.3s,max-height 0.3s'; rowEl.style.opacity = '0'; rowEl.style.maxHeight = '0'; setTimeout(() => rowEl.remove(), 350); }
        showToast('Archived');
        break;
      case 'star':
        res = await fetch(`${mailBase}/star/${msgId}`, { method: 'POST' });
        showToast('⭐ Starred');
        break;
      case 'unstar':
        res = await fetch(`${mailBase}/unstar/${msgId}`, { method: 'POST' });
        showToast('Unstarred');
        break;
      case 'trash':
        res = await fetch(`${mailBase}/trash/${msgId}`, { method: 'POST' });
        if (res.ok && rowEl) { rowEl.style.transition = 'opacity 0.3s,max-height 0.3s'; rowEl.style.opacity = '0'; rowEl.style.maxHeight = '0'; setTimeout(() => rowEl.remove(), 350); }
        showToast('🗑 Moved to trash');
        break;
    }
  } catch (e) {
    showToast('Action failed: ' + e.message);
  }
}

function onMailContextMenu(e, rowEl) {
  e.preventDefault();
  e.stopPropagation();
  dismissMailMenu();

  const msgId = rowEl.dataset.msgId;
  if (!msgId) return;

  const menu = document.createElement('div');
  menu.className = 'kilo-menu';  // reuse existing Kilo menu styles

  // ── Email Actions Header ──
  const hdr = document.createElement('div');
  hdr.className = 'kilo-menu-header';
  hdr.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px;margin-right:4px"><rect width="20" height="16" x="2" y="4" rx="2"></rect><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"></path></svg>ACTIONS';
  menu.appendChild(hdr);

  // Check if already starred (try reading the labels from payload cache)
  const cached = _mailPayloads.find(p => p.id === msgId);
  const labels = cached?.labels || [];
  const isStarred = labels.includes('STARRED');

  const svgArchive = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="21 8 21 21 3 21 3 8"/><rect width="23" height="4" x=".5" y="4" rx="1"/><line x1="10" x2="14" y1="12" y2="12"/></svg>';
  const svgStar = '<svg width="14" height="14" viewBox="0 0 24 24" fill="' + (isStarred ? 'currentColor' : 'none') + '" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>';
  const svgTrash = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>';
  const actions = [
    { icon: svgArchive, label: 'Archive', action: 'archive' },
    { icon: svgStar, label: isStarred ? 'Unstar' : 'Star', action: isStarred ? 'unstar' : 'star' },
    { icon: svgTrash, label: 'Move to Trash', action: 'trash' }
  ];

  actions.forEach(a => {
    const item = document.createElement('div');
    item.className = 'kilo-menu-item';
    item.innerHTML = `<span class="kilo-menu-icon" style="min-width:20px;text-align:center">${a.icon}</span><span class="kilo-menu-label">${a.label}</span>`;
    item.addEventListener('click', () => { dismissMailMenu(); _doMailAction(a.action, msgId, rowEl); });
    menu.appendChild(item);
  });

  // ── Separator + Kilo AI section ──
  const sep = document.createElement('div');
  sep.style.cssText = 'height:1px;background:var(--vsc-border);margin:4px 0';
  menu.appendChild(sep);

  // Fall through to Kilo menu items
  const kiloHdr = document.createElement('div');
  kiloHdr.className = 'kilo-menu-header';
  kiloHdr.style.paddingTop = '2px';
  kiloHdr.innerHTML = '<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px;margin-right:4px"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>KILO AI';
  menu.appendChild(kiloHdr);

  // Kilo actions (reimplemented to avoid cross-module import issues)
  const svgDraft = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>';
  const svgFind = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/></svg>';
  const svgAsk = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>';
  const kiloActions = [
    { icon: svgDraft, label: 'Draft Reply', kiloAction: 'draft' },
    { icon: svgFind, label: 'Find Related', kiloAction: 'find' },
    { icon: svgAsk, label: 'Ask Kilo…', kiloAction: 'ask' }
  ];
  kiloActions.forEach(a => {
    const item = document.createElement('div');
    item.className = 'kilo-menu-item';
    item.innerHTML = `<span class="kilo-menu-icon" style="min-width:20px;text-align:center">${a.icon}</span><span class="kilo-menu-label">${a.label}</span>`;
    item.addEventListener('click', () => {
      dismissMailMenu();
      // Delegate to the existing Kilo menu handler
      try {
        const b64 = rowEl.dataset.kilo;
        if (b64) {
          const { decKiloData: dkd } = window;
          // Use the global onKiloMenu for AI actions via data attribute
          const data = decKiloData(b64);
          import('./kilo.js').then(m => m.sendToKilo(a.kiloAction, data)).catch(() => {});
        }
      } catch (err) { console.warn('Kilo action failed:', err); }
    });
    menu.appendChild(item);
  });

  // Position
  menu.style.left = Math.min(e.clientX, window.innerWidth - 270) + 'px';
  menu.style.top = Math.min(e.clientY, window.innerHeight - 280) + 'px';

  document.body.appendChild(menu);
  _mailMenu = menu;

  // Auto-dismiss on click elsewhere
  const dismiss = (ev) => { if (!menu.contains(ev.target)) { dismissMailMenu(); document.removeEventListener('click', dismiss); } };
  setTimeout(() => document.addEventListener('click', dismiss), 0);
}

window.onMailContextMenu = onMailContextMenu;
