// ── calendar.js — Calendar Column, RSVP, Edit ──────────────────────
import { BASE, CAL_PAGE_SIZE, escHtml, fmtDate, fmtDatetime, isUpcoming,
         encKiloData, decKiloData, setCount, updateCalStat, setBody, appendBody, showToast, updateSentinel } from './core.js';
import { createPanel, closePanel, openDetail, openDetailHtml, _kiloMenuActive } from './panels.js';

// ── Calendar Scroll State ──
let _calOffset = null;
let _calHasMore = true;
let _calLoading = false;
let _calTotalLoaded = 0;
let _calTodayCount = 0;
let _calObserver = null;
let _calTotal = null;
let _calPayloads = [];

export function openCreateEventPanel() {
  const key = 'create-event-' + Date.now();
  const p = createPanel(key, 'New Event', 'Calendar', '');
  const body = p.querySelector('.panel-body');
  body.style.whiteSpace = 'normal';
  // Default date = today, default times = next hour rounded
  const now = new Date();
  const todayStr = now.toISOString().slice(0, 10);
  const startHour = String(now.getHours() + 1).padStart(2, '0');
  const endHour = String(now.getHours() + 2).padStart(2, '0');
  body.innerHTML = `
    <div style="display:flex;flex-direction:column;gap:8px;padding:4px">
      <label style="font-size:11px;color:var(--vsc-muted)">Title:</label>
      <input type="text" class="evt-summary" placeholder="Meeting title" style="width:100%;padding:6px 8px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
      <div style="display:flex;gap:8px">
        <div style="flex:1">
          <label style="font-size:11px;color:var(--vsc-muted)">Date:</label>
          <input type="date" class="evt-date" value="${todayStr}" style="width:100%;padding:5px 6px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
        </div>
        <div style="flex:1">
          <label style="font-size:11px;color:var(--vsc-muted)">Start:</label>
          <input type="time" class="evt-start" value="${startHour}:00" style="width:100%;padding:5px 6px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
        </div>
        <div style="flex:1">
          <label style="font-size:11px;color:var(--vsc-muted)">End:</label>
          <input type="time" class="evt-end" value="${endHour}:00" style="width:100%;padding:5px 6px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
        </div>
      </div>
      <label style="font-size:11px;color:var(--vsc-muted)">Description:</label>
      <textarea class="evt-desc" placeholder="Optional description…" style="width:100%;min-height:60px;max-height:150px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;padding:8px;font-size:12px;font-family:inherit;resize:vertical"></textarea>
      <label style="font-size:11px;color:var(--vsc-muted)">Attendees (comma-separated emails):</label>
      <input type="text" class="evt-attendees" placeholder="a@example.com, b@example.com" style="width:100%;padding:6px 8px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
      <label style="display:flex;align-items:center;gap:6px;font-size:11px;color:var(--vsc-muted);cursor:pointer;margin-top:2px">
        <input type="checkbox" class="evt-meet"> Add Google Meet link
      </label>
      <div style="display:flex;gap:8px;margin-top:4px">
        <button class="evt-create-btn" style="font-size:11px;padding:5px 14px;border-radius:4px;border:1px solid var(--vsc-accent,#007acc);background:var(--vsc-accent,#007acc);color:#fff;cursor:pointer"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><rect width="18" height="18" x="3" y="4" rx="2" ry="2"></rect><line x1="16" y1="2" x2="16" y2="6"></line><line x1="8" y1="2" x2="8" y2="6"></line><line x1="3" y1="10" x2="21" y2="10"></line></svg> Create Event</button>
        <button onclick="closePanel('${key}')" style="font-size:11px;padding:5px 14px;border-radius:4px;border:1px solid var(--vsc-border);background:var(--vsc-bg);color:var(--vsc-text);cursor:pointer">Cancel</button>
      </div>
    </div>
  `;

  body.querySelector('.evt-create-btn').addEventListener('click', async function () {
    const summary = body.querySelector('.evt-summary').value.trim();
    const date = body.querySelector('.evt-date').value;
    const startTime = body.querySelector('.evt-start').value;
    const endTime = body.querySelector('.evt-end').value;
    const desc = body.querySelector('.evt-desc').value.trim();
    const attendeesRaw = body.querySelector('.evt-attendees').value.trim();
    const addMeet = body.querySelector('.evt-meet').checked;

    if (!summary) { showToast('Title is required'); body.querySelector('.evt-summary').focus(); return; }
    if (!date || !startTime || !endTime) { showToast('Date and times are required'); return; }
    if (endTime <= startTime) { showToast('End time must be after start time'); return; }

    // Append browser's local timezone offset (e.g., "+01:00") to datetime strings
    const tzOffsetMin = new Date().getTimezoneOffset(); // e.g., -60 for CET
    const sign = tzOffsetMin <= 0 ? '+' : '-';
    const absMin = Math.abs(tzOffsetMin);
    const tzStr = sign + String(Math.floor(absMin / 60)).padStart(2, '0') + ':' + String(absMin % 60).padStart(2, '0');

    const attendees = attendeesRaw ? attendeesRaw.split(',').map(s => s.trim()).filter(Boolean) : [];

    try {
      this.disabled = true;
      this.textContent = '⏳ Creating…';
      const res = await fetch(`${BASE}/api/calendar-events/events`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          summary,
          start_time: `${date}T${startTime}:00${tzStr}`,
          end_time: `${date}T${endTime}:00${tzStr}`,
          description: desc,
          attendees,
          add_meet: addMeet
        }),
        signal: AbortSignal.timeout(15000)
      });
      if (!res.ok) { const d = await res.json().catch(() => ({})); throw new Error(d.error || `HTTP ${res.status}`); }
      const result = await res.json();
      let msg = 'Event created: ' + summary;
      if (result.meet_link) msg += '\n' + result.meet_link;
      showToast(msg);
      closePanel(key);
      // Force refresh after 1s to ensure Qdrant has the new event
      setTimeout(() => forceReloadCalendar(), 1000);
    } catch (e) {
      showToast('Failed to create event: ' + e.message);
      this.disabled = false;
      this.innerHTML = '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><rect width="18" height="18" x="3" y="4" rx="2" ry="2"></rect><line x1="16" y1="2" x2="16" y2="6"></line><line x1="8" y1="2" x2="8" y2="6"></line><line x1="3" y1="10" x2="21" y2="10"></line></svg> Create Event';
    }
  });

  body.querySelector('.evt-summary').focus();
}


// ── Calendar ─────────────────────────────────────────────────────────

/** Build rich HTML modal content for a calendar event (WO-CAL-2) */
function buildEventModalHtml(pl) {
  const parts = [];
  const startDt = pl.start ? new Date(pl.start) : null;
  const endDt = pl.end ? new Date(pl.end) : null;

  // Duration
  if (startDt && endDt) {
    const mins = Math.round((endDt - startDt) / 60000);
    const durStr = mins >= 60 ? `${Math.floor(mins / 60)}h ${mins % 60 ? mins % 60 + 'min' : ''}` : `${mins} min`;
    parts.push(`<div style="font-size:12px;color:var(--vsc-muted);margin-bottom:8px">⏱ ${escHtml(fmtDatetime(pl.start))} — ${escHtml(fmtDatetime(pl.end))} (${durStr.trim()})</div>`);
  }

  // Location + Meet
  if (pl.location) parts.push(`<div style="margin-bottom:6px"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path><circle cx="12" cy="10" r="3"></circle></svg> ${escHtml(pl.location)}</div>`);
  if (pl.hangout_link) parts.push(`<div style="margin-bottom:10px"><span class="modal-meet-link" data-ext-url="${escHtml(pl.hangout_link)}"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="m22 8-6 4 6 4V8Z"></path><rect width="14" height="12" x="2" y="6" rx="2" ry="2"></rect></svg> Join Google Meet</span></div>`);

  // Attendees
  const attendees = pl.attendees || [];
  const statuses = pl.attendee_status || {};
  if (attendees.length > 0) {
    const statusIcons = { accepted: '✅', declined: '❌', tentative: '❓', needsAction: '⏳' };
    const orgEmail = pl.organizer || '';
    parts.push(`<div class="modal-section"><div class="modal-section-title">👥 Attendees (${attendees.length})</div><ul class="modal-attendees">`);
    attendees.forEach(email => {
      const icon = statusIcons[statuses[email]] || '⏳';
      const orgTag = email === orgEmail ? ' <span style="color:var(--vsc-accent);font-size:10px">(organizer)</span>' : '';
      parts.push(`<li>${icon} ${escHtml(email)}${orgTag}</li>`);
    });
    parts.push('</ul></div>');
  }

  // RSVP buttons (WO-CAL-RSVP-4)
  const myEmail = (pl.account_email || '').toLowerCase();
  const myStatus = myEmail ? (statuses[myEmail] || statuses[pl.account_email] || '') : '';
  if (myEmail && (myStatus === 'needsAction' || myStatus === 'tentative')) {
    const calId = (pl.calendar_id || '').replace(/'/g, "\\'");
    parts.push(`<div class="rsvp-bar" id="rsvp-bar-${escHtml(calId)}">
      <button class="rsvp-btn rsvp-btn--accept" onclick="rsvpRespond('${calId}','accepted',this)">✅ Accept</button>
      <button class="rsvp-btn rsvp-btn--decline" onclick="rsvpRespond('${calId}','declined',this)">❌ Decline</button>
      <button class="rsvp-btn rsvp-btn--maybe" onclick="rsvpRespond('${calId}','tentative',this)">🤔 Maybe</button>
    </div>`);
  } else if (myEmail && myStatus) {
    const label = { accepted: '✅ Accepted', declined: '❌ Declined', tentative: '🤔 Tentative' }[myStatus] || myStatus;
    parts.push(`<div class="rsvp-status">${label}</div>`);
  }

  // Description
  if (pl.description) parts.push(`<div class="modal-section"><div class="modal-section-title"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg> Description</div><div style="white-space:pre-wrap">${escHtml(pl.description)}</div></div>`);

  // Open in Calendar link
  if (pl.html_link) parts.push(`<div style="margin-top:14px"><span class="modal-gcal-link" data-ext-url="${escHtml(pl.html_link)}"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"></path><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"></path></svg> Open in Google Calendar</span></div>`);

  // Edit + Delete buttons
  const calId = pl.calendar_id || '';
  if (calId) {
    const idEsc = escHtml(calId).replace(/'/g, "\\'");
    const payloadIdx = _calPayloads.indexOf(pl);
    parts.push(`<div style="margin-top:14px;padding-top:10px;border-top:1px solid var(--vsc-border);display:flex;gap:6px">
      <button onclick="editCalendarEvent(${payloadIdx}, this)" class="rsvp-btn rsvp-btn--accept" style="background:var(--vsc-accent,#007acc)">
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path></svg>
        Edit
      </button>
      ${pl.recurring_event_id ? `
      <button onclick="confirmDeleteCalEvent(this,'${idEsc}','this')" class="evt-delete-btn" style="background:var(--vsc-red,#e74c3c);color:#fff;border:none;padding:5px 14px;border-radius:4px;cursor:pointer;font-size:11px;display:inline-flex;align-items:center;gap:4px">
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg>
        Delete This
      </button>
      <button onclick="confirmDeleteCalEvent(this,'${idEsc}','all')" class="evt-delete-btn" style="background:#e67e22;color:#fff;border:none;padding:5px 14px;border-radius:4px;cursor:pointer;font-size:11px;display:inline-flex;align-items:center;gap:4px">
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg>
        🔁 Delete Series
      </button>
      ` : `
      <button onclick="confirmDeleteCalEvent(this,'${idEsc}','this')" class="evt-delete-btn" style="background:var(--vsc-red,#e74c3c);color:#fff;border:none;padding:5px 14px;border-radius:4px;cursor:pointer;font-size:11px;display:inline-flex;align-items:center;gap:4px">
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg>
        Delete Event
      </button>
      `}
    </div>`);
  }

  return parts.join('') || '(No details available)';
}

/** Send RSVP response to Google Calendar (WO-CAL-RSVP-4) */
export async function rsvpRespond(eventId, response, btn) {
  const bar = btn.closest('.rsvp-bar');
  const btns = bar ? bar.querySelectorAll('.rsvp-btn') : [];
  btns.forEach(b => { b.disabled = true; });
  btn.textContent = '…';

  try {
    const res = await fetch(`${BASE}/api/calendar-events/respond/${encodeURIComponent(eventId)}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ response }),
      signal: AbortSignal.timeout(15000)
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);

    // Optimistic: replace buttons with status label
    const label = { accepted: '✅ Accepted', declined: '❌ Declined', tentative: '🤔 Tentative' }[response] || response;
    if (bar) bar.innerHTML = `<div class="rsvp-status">${label}</div>`;
    showToast(`RSVP: ${label}`);

    // Refresh calendar after ingestor re-syncs (~10s)
    setTimeout(() => loadCalendar(false), 12000);
  } catch (e) {
    showToast(`RSVP failed: ${e.message}`);
    btns.forEach(b => { b.disabled = false; });
    btn.textContent = { accepted: '✅ Accept', declined: '❌ Decline', tentative: '🤔 Maybe' }[response] || response;
  }
}

/** Check if an event is happening right now (WO-CAL-3) */
function isHappeningNow(startStr, endStr) {
  if (!startStr || !endStr) return false;
  const now = Date.now();
  return new Date(startStr).getTime() <= now && now <= new Date(endStr).getTime();
}

/** Replace modal content with inline edit form (WO-CAL-EDIT-1b) */
export function editCalendarEvent(payloadIdx, btn) {
  const pl = _calPayloads[payloadIdx];
  if (!pl) return;
  const calId = pl.calendar_id || '';
  if (!calId) { showToast('Cannot edit: no event ID'); return; }

  // Parse existing start/end into date + time parts
  const startDt = pl.start ? new Date(pl.start) : new Date();
  const endDt = pl.end ? new Date(pl.end) : new Date();
  const dateStr = startDt.toISOString().slice(0, 10);
  const startTimeStr = String(startDt.getHours()).padStart(2, '0') + ':' + String(startDt.getMinutes()).padStart(2, '0');
  const endTimeStr = String(endDt.getHours()).padStart(2, '0') + ':' + String(endDt.getMinutes()).padStart(2, '0');
  const attendeeStr = (pl.attendees || []).join(', ');

  // Find the panel body via DOM traversal from the clicked button
  const modalBody = btn.closest('.panel').querySelector('.panel-body');
  if (!modalBody) return;
  const origHtml = modalBody.innerHTML;

  modalBody.innerHTML = `
    <div style="display:flex;flex-direction:column;gap:8px;padding:4px">
      <label style="font-size:11px;color:var(--vsc-muted)">Title:</label>
      <input type="text" class="evt-edit-summary" value="${escHtml(pl.summary || '')}" style="width:100%;padding:6px 8px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
      <div style="display:flex;gap:8px">
        <div style="flex:1">
          <label style="font-size:11px;color:var(--vsc-muted)">Date:</label>
          <input type="date" class="evt-edit-date" value="${dateStr}" style="width:100%;padding:5px 6px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
        </div>
        <div style="flex:1">
          <label style="font-size:11px;color:var(--vsc-muted)">Start:</label>
          <input type="time" class="evt-edit-start" value="${startTimeStr}" style="width:100%;padding:5px 6px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
        </div>
        <div style="flex:1">
          <label style="font-size:11px;color:var(--vsc-muted)">End:</label>
          <input type="time" class="evt-edit-end" value="${endTimeStr}" style="width:100%;padding:5px 6px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
        </div>
      </div>
      <label style="font-size:11px;color:var(--vsc-muted)">Description:</label>
      <textarea class="evt-edit-desc" style="width:100%;min-height:60px;max-height:150px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;padding:8px;font-size:12px;font-family:inherit;resize:vertical">${escHtml(pl.description || '')}</textarea>
      <label style="font-size:11px;color:var(--vsc-muted)">Attendees (comma-separated emails):</label>
      <input type="text" class="evt-edit-attendees" value="${escHtml(attendeeStr)}" style="width:100%;padding:6px 8px;background:var(--vsc-bg);color:var(--vsc-text);border:1px solid var(--vsc-border);border-radius:4px;font-size:12px;font-family:inherit">
      <div style="display:flex;gap:8px;margin-top:4px">
        <button class="evt-edit-save rsvp-btn rsvp-btn--accept" style="background:var(--vsc-accent,#007acc)">✔ Save</button>
        <button class="evt-edit-cancel rsvp-btn" style="background:var(--vsc-muted,#888)">✖ Cancel</button>
      </div>
    </div>`;

  // Save handler
  modalBody.querySelector('.evt-edit-save').addEventListener('click', () => saveCalendarEdit(calId, modalBody, origHtml));
  // Cancel handler — restore original content
  modalBody.querySelector('.evt-edit-cancel').addEventListener('click', () => { modalBody.innerHTML = origHtml; });
  // Focus summary
  modalBody.querySelector('.evt-edit-summary').focus();
}

/** Send PATCH to update calendar event (WO-CAL-EDIT-1b) */
async function saveCalendarEdit(eventId, modalBody, origHtml) {
  const summary = modalBody.querySelector('.evt-edit-summary').value.trim();
  const date = modalBody.querySelector('.evt-edit-date').value;
  const startTime = modalBody.querySelector('.evt-edit-start').value;
  const endTime = modalBody.querySelector('.evt-edit-end').value;
  const desc = modalBody.querySelector('.evt-edit-desc').value.trim();
  const attendeesRaw = modalBody.querySelector('.evt-edit-attendees').value.trim();

  if (!summary) { showToast('Title is required'); modalBody.querySelector('.evt-edit-summary').focus(); return; }
  if (!date || !startTime || !endTime) { showToast('Date and times are required'); return; }

  const tzOffsetMin = new Date().getTimezoneOffset();
  const sign = tzOffsetMin <= 0 ? '+' : '-';
  const absMin = Math.abs(tzOffsetMin);
  const tzStr = sign + String(Math.floor(absMin / 60)).padStart(2, '0') + ':' + String(absMin % 60).padStart(2, '0');

  const attendees = attendeesRaw ? attendeesRaw.split(',').map(s => s.trim()).filter(Boolean) : [];

  const saveBtn = modalBody.querySelector('.evt-edit-save');
  saveBtn.disabled = true;
  saveBtn.textContent = '⏳ Saving…';

  try {
    const res = await fetch(`${BASE}/api/calendar-events/events/${encodeURIComponent(eventId)}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        summary,
        start_time: `${date}T${startTime}:00${tzStr}`,
        end_time: `${date}T${endTime}:00${tzStr}`,
        description: desc,
        attendees
      }),
      signal: AbortSignal.timeout(15000)
    });
    if (!res.ok) { const d = await res.json().catch(() => ({})); throw new Error(d.error || `HTTP ${res.status}`); }
    showToast('✅ Event updated: ' + summary);
    modalBody.innerHTML = `<div class="rsvp-status">✅ Updated — refreshing in 10s…</div>`;
    setTimeout(() => {
      _calOffset = null; _calHasMore = true; _calTotalLoaded = 0;
      loadCalendar();
      // Close the modal if still open
      const panel = document.querySelector('.detail-panel');
      if (panel) panel.style.display = 'none';
      showToast('Calendar updated');
    }, 10000);
  } catch (e) {
    showToast('Failed to update: ' + e.message);
    saveBtn.disabled = false;
    saveBtn.textContent = '✔ Save';
  }
}

/** Build a single calendar row HTML */
function buildCalRow(p, insertedSeparatorRef, tomorrow) {
  const pl = p.payload || {};
  const name = pl.summary || pl.Summary || pl.title || '(no title)';
  const start = pl.start || pl.Start || '';
  const end = pl.end || '';
  const loc = pl.location || '';
  const happeningNow = isHappeningNow(start, end);
  const nowClass = happeningNow ? ' event-now' : '';
  const nowBadge = happeningNow ? '<div class="event-now-badge">● Now</div>' : '';

  // Pending RSVP badge (WO-CAL-RSVP-4)
  const myCalEmail = (pl.account_email || '').toLowerCase();
  const myCalStatus = myCalEmail ? ((pl.attendee_status || {})[myCalEmail] || (pl.attendee_status || {})[pl.account_email] || '') : '';
  const pendingBadge = (myCalEmail && myCalStatus === 'needsAction') ? '<div class="rsvp-pending-badge">⚑ Pending</div>' : '';

  let separator = '';
  if (!insertedSeparatorRef.done && start) {
    const evtDate = new Date(start);
    if (evtDate >= tomorrow) {
      separator = '<div class="today-separator">── Upcoming ──</div>';
      insertedSeparatorRef.done = true;
    }
  }

  const kiloB64 = encKiloData({ type: 'calendar', title: name, date: fmtDatetime(start), location: loc, attendees: pl.attendees || [] });
  const payloadIdx = _calPayloads.length;
  _calPayloads.push(pl);

  return separator + `<div class="row${nowClass}" onclick="openCalendarDetail(${payloadIdx})" data-kilo="${kiloB64}" oncontextmenu="onKiloMenu(event,this)" style="cursor:pointer" title="Click to open · Right-click for AI actions">
    <span class="row-icon"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><polyline points="12 6 12 12 16 14"></polyline></svg></span>
    <div class="row-body">
      <div class="cal-name">${escHtml(name)}</div>
      <div class="cal-time">${escHtml(fmtDatetime(start))}</div>
      ${loc ? `<div class="cal-loc"><svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path><circle cx="12" cy="10" r="3"></circle></svg> ${escHtml(loc)}</div>` : ''}
      ${nowBadge}
      ${pendingBadge}
    </div>
    <button class="kilo-btn" onclick="event.stopPropagation();onKiloMenu(event,this.closest('.row'))" title="Kilo AI"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg></button>
  </div>`;
}

// Separator state persists across calendar pages
let _calSeparatorRef = { done: false };
let _calTomorrow = null;

/** Force-reload calendar — resets ALL state so no guard can block it */
export function forceReloadCalendar() {
  _calOffset = null;
  _calHasMore = true;
  _calTotalLoaded = 0;
  _calTodayCount = 0;
  _calLoading = false;
  _calForceAbort = true; // Signal eagerly-loading loop to stop
  loadCalendar(false);
}

let _calForceAbort = false;

export async function loadCalendar(append = false) {
  if (_calLoading) return;
  if (append && !_calHasMore) return;
  _calLoading = true;
  _calForceAbort = false;

  try {
    const body = {
      limit: CAL_PAGE_SIZE,
      with_payload: true
    };
    // FIX: Use start_epoch index to properly fetch upcoming events in chronological order,
    // avoiding fetching a random chuck of 50 and then filtering locally which misses items.
    const nowEpoch = Math.floor(Date.now() / 1000);
    body.filter = {
      must: [
        { key: "start_epoch", range: { gte: nowEpoch } }
      ]
    };
    body.order_by = { key: "start_epoch", direction: "asc" };
    
    if (append && _calOffset) {
      body.offset = _calOffset;
    }

    if (append) updateSentinel('cal-body', true, true);

    const res = await fetch(`${BASE}/api/calendar`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10000)
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    const points = (data.result?.points || []);

    // Filter upcoming, sort asc
    const upcoming = points
      .filter(p => isUpcoming(p.payload?.start || p.payload?.Start))
      .sort((a, b) => {
        const da = new Date(a.payload?.start || a.payload?.Start || 0);
        const db = new Date(b.payload?.start || b.payload?.Start || 0);
        return da - db;
      });

    // Update cursor
    _calOffset = data.result?.next_page_offset || null;
    _calHasMore = !!_calOffset;

    if (!append) {
      // First load: reset state
      _calTotalLoaded = 0;
      _calTodayCount = 0;
      _calPayloads = [];
      _calSeparatorRef = { done: false };
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      _calTomorrow = new Date(today);
      _calTomorrow.setDate(_calTomorrow.getDate() + 1);

      if (!upcoming.length && !_calHasMore) {
        setCount('cal-count', '0');
        updateCalStat(0, 0);
        setBody('cal-body', '<div class="empty-msg">No upcoming events</div>');
        _calLoading = false;
        return;
      }
      setBody('cal-body', upcoming.map(p => buildCalRow(p, _calSeparatorRef, _calTomorrow)).join(''));
    } else {
      appendBody('cal-body', upcoming.map(p => buildCalRow(p, _calSeparatorRef, _calTomorrow)).join(''));
    }

    // FIX-3: Count today's events separately from total upcoming
    const todayStart = new Date(); todayStart.setHours(0,0,0,0);
    const todayEnd = new Date(); todayEnd.setHours(23,59,59,999);
    const todayEvents = upcoming.filter(p => {
      const d = new Date(p.payload?.start || p.payload?.Start || 0);
      return d >= todayStart && d <= todayEnd;
    });
    _calTodayCount += todayEvents.length;
    _calTotalLoaded += upcoming.length;
    // When all upcoming events are loaded, set _calTotal to the real count
    if (!_calHasMore) _calTotal = _calTotalLoaded;
    const calTotalStr = _calTotal !== null ? ` (${_calTotal})` : '';
    setCount('cal-count', `1\u2013${_calTotalLoaded}${calTotalStr}`);
    updateCalStat(_calTodayCount, _calTotalLoaded);
    updateSentinel('cal-body', _calHasMore, false);

    if (!_calObserver) {
      setupCalObserver();
    }

    // Eagerly load all remaining calendar pages in background
    // so _calTotal is known quickly and scrollbar thumb is proportional
    if (!append && _calHasMore) {
      setTimeout(async function loadAllCalPages() {
        while (_calHasMore && !_calForceAbort) {
          await loadCalendar(true);
        }
      }, 100);
    }

  } catch (e) {
    if (!append) {
      setBody('cal-body', `<div class="error-msg"><svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z"></path><line x1="12" y1="9" x2="12" y2="13"></line><line x1="12" y1="17" x2="12.01" y2="17"></line></svg> Could not load calendar<br><small>${escHtml(e.message)}</small></div>`);
    }
  } finally {
    _calLoading = false;
  }
}

export function setupCalObserver() {
  const scrollContainer = document.getElementById('cal-body').closest('.col-body') || document.getElementById('cal-body');
  _calObserver = new IntersectionObserver((entries) => {
    if (entries[0]?.isIntersecting && _calHasMore && !_calLoading) {
      loadCalendar(true);
    }
  }, { root: scrollContainer, rootMargin: '100px' });
  const sentinel = document.getElementById('cal-body').querySelector('.scroll-sentinel');
  if (sentinel) _calObserver.observe(sentinel);
}

// Calendar payload store for rich modal access (declared at top of module)
export function openCalendarDetail(idx) {
  if (_kiloMenuActive) return; // guard: skip if Kilo context menu is active
  const pl = _calPayloads[idx];
  if (!pl) return;
  const name = pl.summary || '(no title)';
  const meta = fmtDatetime(pl.start || '') + (pl.location ? '  ·  ' + pl.location : '');
  openDetailHtml(name, meta, buildEventModalHtml(pl));
}

export function confirmDeleteCalEvent(btn, eventId, scope = 'this') {
  if (btn.dataset.armed) {
    // Second click — actually delete
    deleteCalendarEvent(eventId, scope);
    return;
  }
  // First click — arm the button
  btn.dataset.armed = '1';
  const origBg = btn.style.background;
  const origLabel = scope === 'all' ? '🔁 Delete Series' : (btn.textContent.includes('This') ? 'Delete This' : 'Delete Event');
  btn.innerHTML = scope === 'all' ? '⚠️ Delete ALL instances?' : '🗑 Confirm Delete?';
  btn.style.background = '#c0392b';
  btn.style.fontWeight = '700';
  // Auto-reset after 3s
  setTimeout(() => {
    if (!btn.isConnected) return;
    delete btn.dataset.armed;
    btn.innerHTML = `<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-1px"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg> ${origLabel}`;
    btn.style.background = origBg;
    btn.style.fontWeight = '';
  }, 3000);
}

async function deleteCalendarEvent(eventId, scope = 'this') {
  try {
    const scopeParam = scope === 'all' ? '?scope=all' : '';
    const res = await fetch(`${BASE}/api/calendar-events/events/${eventId}${scopeParam}`, {
      method: 'DELETE',
      signal: AbortSignal.timeout(10000)
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.error || `HTTP ${res.status}`);
    }
    showToast('Event deleted');
    // Close the detail panel
    document.querySelectorAll('.panel').forEach(p => p.remove());
    // Refresh calendar immediately (backend already cleaned up Qdrant)
    _calOffset = null;
    _calHasMore = true;
    _calTotalLoaded = 0;
    loadCalendar();
  } catch (e) {
    showToast('Failed to delete: ' + e.message);
  }
}


// ── State accessors (used by app.js orchestrator) ──
export function getCalState() { return { calTotal: _calTotal }; }
export function resetCalState() {
  _calOffset = null; _calHasMore = true; _calTotalLoaded = 0; _calTodayCount = 0;
  if (_calObserver) { _calObserver.disconnect(); _calObserver = null; }
}

// ── Window exports (HTML onclick handlers) ──
window.openCalendarDetail = openCalendarDetail;
window.rsvpRespond = rsvpRespond;
window.editCalendarEvent = editCalendarEvent;
window.confirmDeleteCalEvent = confirmDeleteCalEvent;
window.openCreateEventPanel = openCreateEventPanel;
