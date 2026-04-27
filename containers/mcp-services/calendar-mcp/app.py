# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
import os
import re
import datetime
import logging
import json
import requests
from uuid import uuid4
from typing import Optional, List, Dict, Any
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from fastmcp import FastMCP

from qdrant_client import QdrantClient
import sys

# Add shared directory to path to import rate_limiter
sys.path.append(os.path.join(os.path.dirname(__file__), 'shared'))
try:
    from rate_limiter import rate_limit
except ImportError:
    logging.warning("Shared rate_limiter not found, using dummy decorator")
    def rate_limit(limit=100, period=60):
        def decorator(func):
            return func
        return decorator

# Initialize FastMCP
mcp = FastMCP("Calendar MCP")

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Configuration ---
SCOPES = ['https://www.googleapis.com/auth/calendar']
QDRANT_HOST = os.environ.get('QDRANT_HOST', 'qdrant')
QDRANT_PORT = int(os.environ.get('QDRANT_PORT', 6333))
COLLECTION_NAME = "calendar"
EMBEDDING_BASE_URL = os.getenv("EMBEDDING_BASE_URL", "http://embedding-server:7997")
EMBEDDING_MODEL_ID = os.getenv("EMBEDDING_MODEL_ID", "sentence-transformers/paraphrase-multilingual-mpnet-base-v2")


# Global Qdrant Client
q_client = None

def get_qdrant_client():
    global q_client
    if not q_client:
        try:
            q_client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)
        except Exception as e:
            logger.error(f"Failed to connect to Qdrant: {e}")
            return None
    return q_client

def get_embedding_via_http(text):
    """Get embedding vector via centralized embedding server."""
    try:
        response = requests.post(
            f"{EMBEDDING_BASE_URL}/v1/embeddings",
            json={"input": [text], "model": EMBEDDING_MODEL_ID},
            headers={"X-Priority": "search"},
            timeout=30
        )
        response.raise_for_status()
        return response.json()["data"][0]["embedding"]
    except Exception as e:
        logger.error(f"Embedding server call failed: {e}")
        return None


# ── WO-CSYNC-4: Direct Qdrant Write ──────────────────────────────────
import uuid
import threading as _csync_threading

def _upsert_event_to_qdrant(event: dict, account_email: str = "", google_calendar_id: str = "primary") -> None:
    """Immediately upsert a Google Calendar event into Qdrant.
    Replicates the exact payload format the ingestor uses (app.py:640-670)
    so the dashboard sees the event without waiting for a full re-index.

    Runs in a daemon thread to avoid blocking the API response.
    Falls back to a zero vector if embedding fails, so the event is always
    queryable by payload fields (start_epoch, summary, etc.).
    """
    def _do_upsert():
        import sys
        try:
            logger.info(f"CSYNC-4: Starting direct write for event '{event.get('summary', '?')[:30]}'")
            sys.stdout.flush()
            client = get_qdrant_client()
            if not client:
                logger.warning("CSYNC-4: Qdrant unavailable, skipping direct write")
                return

            evt_id = event.get('id', '')
            summary = event.get('summary', 'No Title')
            description = event.get('description', '')
            start = event.get('start', {}).get('dateTime', event.get('start', {}).get('date', ''))
            end = event.get('end', {}).get('dateTime', event.get('end', {}).get('date', ''))
            location = event.get('location', '')
            attendees_raw = event.get('attendees', [])
            attendees = [a.get('email', '') for a in attendees_raw]
            attendee_status = {a.get('email', ''): a.get('responseStatus', 'needsAction') for a in attendees_raw}
            hangout_link = event.get('hangoutLink', '')
            html_link = event.get('htmlLink', '')
            status = event.get('status', 'confirmed')
            organizer = event.get('organizer', {}).get('email', '')

            # Parse start_epoch (same logic as ingestor)
            start_epoch = 0
            try:
                if start:
                    if len(start) == 10:  # YYYY-MM-DD (all-day event)
                        start_epoch = int(datetime.datetime.strptime(start, '%Y-%m-%d').timestamp())
                    else:
                        start_epoch = int(datetime.datetime.fromisoformat(start).timestamp())
            except Exception:
                start_epoch = 0

            # Build embedding text (same format as ingestor)
            attendee_str = ', '.join(attendees) if attendees else ''
            full_text = f"Event: {summary}\nStart: {start}\nEnd: {end}"
            if location:
                full_text += f"\nLocation: {location}"
            if attendee_str:
                full_text += f"\nAttendees: {attendee_str}"
            if description:
                full_text += f"\nDescription: {description}"

            vector = get_embedding_via_http(full_text)
            if vector is None:
                # Fallback: use zero vector so event still appears in payload-based queries
                logger.warning(f"CSYNC-4: Embedding failed for '{summary[:30]}', using zero vector fallback")
                vector = [0.0] * 384  # VECTOR_SIZE

            # Same point ID as ingestor: uuid5(NAMESPACE_DNS, event_id)
            point_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, evt_id))

            from qdrant_client.http import models
            client.upsert(
                collection_name=COLLECTION_NAME,
                points=[
                    models.PointStruct(
                        id=point_id,
                        vector=vector,
                        payload={
                            "calendar_id": evt_id,
                            "calendar_name": event.get('_source_calendar', ''),
                            "google_calendar_id": google_calendar_id,
                            "recurring_event_id": event.get('recurringEventId', ''),
                            "summary": summary,
                            "start": start,
                            "start_epoch": start_epoch,
                            "end": end,
                            "description": description,
                            "location": location,
                            "attendees": attendees,
                            "attendee_status": attendee_status,
                            "hangout_link": hangout_link,
                            "html_link": html_link,
                            "status": status,
                            "organizer": organizer,
                            "account_email": account_email,
                            "type": "event",
                            "ingested_at": datetime.datetime.now().isoformat()
                        }
                    )
                ]
            )
            logger.info(f"CSYNC-4: Direct Qdrant write OK for event '{summary[:30]}'")
        except Exception as e:
            logger.error(f"CSYNC-4: Direct write FAILED: {e}", exc_info=True)

    _csync_threading.Thread(target=_do_upsert, daemon=True).start()


def _require_explicit_offset(time_str: str) -> None:
    """Validate that an ISO 8601 datetime string has an explicit timezone offset or 'Z'.
    
    Raises ValueError if the string is naive (no offset).
    """
    if time_str.endswith('Z'):
        return
    # Match +HH:MM or -HH:MM at end of string (after the time part)
    if re.search(r'[+\-]\d{2}:\d{2}$', time_str):
        return
    raise ValueError(
        f"Naive datetime '{time_str}' is not allowed. "
        f"Include an explicit timezone offset (e.g., '+01:00') or 'Z' for UTC."
    )


# Import TokenManager from shared package
try:
    from workstation_auth import TokenManager
except ImportError:
    # Fallback for when running without shared package in path (e.g. legacy local runs)
    logging.warning("Shared workstation_auth not found in path")
    TokenManager = None

def get_calendar_service():
    """Authenticates and returns a Calendar API service object using TokenManager."""
    if TokenManager:
        try:
            tm = TokenManager()
            creds = tm.get_credentials(SCOPES)
            return build('calendar', 'v3', credentials=creds)
        except Exception as e:
            logger.error(f"TokenManager failed: {e}")
            raise
    else:
        # Legacy fallback if shared package missing
        raise ImportError("workstation_auth package not found. Ensure shared/ directory is mounted.")


# Validated Logic Functions
def _list_events(max_results: int = 10, calendar_id: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Lists upcoming events. Fetches from ALL subscribed calendars by default.
    
    Args:
        max_results: The maximum number of events to return (default: 10)
        calendar_id: Google Calendar ID. If None, fetches all calendars.
    """
    try:
        service = get_calendar_service()
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()

        if calendar_id:
            # Single calendar query
            events_result = service.events().list(
                calendarId=calendar_id, timeMin=now,
                maxResults=max_results, singleEvents=True,
                orderBy='startTime').execute()
            return events_result.get('items', [])

        # Multi-calendar: fetch all subscribed calendars
        calendar_ids = []
        try:
            cal_list = service.calendarList().list().execute()
            for cal_entry in cal_list.get('items', []):
                cid = cal_entry.get('id', '')
                cname = cal_entry.get('summary', cal_entry.get('summaryOverride', ''))
                if cid:
                    calendar_ids.append((cid, cname))
        except Exception as e:
            logger.warning(f"calendarList.list() failed, falling back to primary: {e}")
            calendar_ids = [('primary', 'Primary')]

        all_events = []
        for cid, cname in calendar_ids:
            try:
                events_result = service.events().list(
                    calendarId=cid, timeMin=now,
                    maxResults=max_results, singleEvents=True,
                    orderBy='startTime').execute()
                for evt in events_result.get('items', []):
                    evt['_source_calendar'] = cname
                    evt['_google_calendar_id'] = cid
                all_events.extend(events_result.get('items', []))
            except Exception as e:
                logger.warning(f"Failed to list events from '{cname}' ({cid}): {e}")

        # Sort merged results by start time, then trim
        all_events.sort(key=lambda e: e.get('start', {}).get('dateTime', e.get('start', {}).get('date', '')))
        return all_events[:max_results]
    except Exception as e:
        logger.error(f"Error listing events: {e}")
        return [{"error": str(e)}]

def _create_event(summary: str, start_time: str, end_time: str, description: str = "", attendees: List[str] = [], time_zone: Optional[str] = None, add_meet: bool = False, calendar_id: str = "primary", recurrence: Optional[List[str]] = None) -> Dict[str, Any]:
    """
    Creates an event on the user's calendar.
    
    Args:
        summary: Event title
        start_time: Start time in ISO 8601 format (e.g. "2023-12-25T09:00:00+01:00")
        end_time: End time in ISO 8601 format
        description: Optional event description
        attendees: Optional list of email addresses
        time_zone: Optional IANA timezone name (e.g., "America/Los_Angeles"). If provided and
                   start/end times lack offset, this timezone will be applied.
        add_meet: If True, auto-generate a Google Meet link for the event
        calendar_id: Google Calendar ID (default: "primary")
        recurrence: Optional list of RRULE strings for recurring events
                    (e.g. ["RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=10"])
    """
    # Coerce recurrence from JSON string if LLM sends it as a string
    if isinstance(recurrence, str):
        try:
            recurrence = json.loads(recurrence)
        except (json.JSONDecodeError, TypeError):
            recurrence = [recurrence]  # treat bare string as single-item list
    try:
        _require_explicit_offset(start_time)
        _require_explicit_offset(end_time)
    except ValueError as e:
        return {"error": str(e)}
    try:
        service = get_calendar_service()
        
        start_event_data = {'dateTime': start_time}
        end_event_data = {'dateTime': end_time}
        
        # Check if timezone offset is already present in the time string
        # Simple heuristic: check for '+' or '-' after 'T'
        if time_zone and not ('T+' in start_time or 'T-' in start_time or start_time.endswith('Z')):
            start_event_data['timeZone'] = time_zone
        if time_zone and not ('T+' in end_time or 'T-' in end_time or end_time.endswith('Z')):
            end_event_data['timeZone'] = time_zone

        # WO-CAL-REC-2: timeZone is required for recurring events (Pattern #91)
        if recurrence and 'timeZone' not in start_event_data and time_zone:
            start_event_data['timeZone'] = time_zone
            end_event_data['timeZone'] = time_zone

        event = {
            'summary': summary,
            'description': description,
            'start': start_event_data,
            'end': end_event_data,
        }
        if attendees:
            event['attendees'] = [{'email': email} for email in attendees]
        
        # WO-CAL-REC-2: Add recurrence rules (e.g. RRULE:FREQ=WEEKLY;BYDAY=MO)
        if recurrence:
            event['recurrence'] = recurrence

        # Add Google Meet conference data if requested
        if add_meet:
            event['conferenceData'] = {
                'createRequest': {
                    'requestId': str(uuid4()),
                    'conferenceSolutionKey': {'type': 'hangoutsMeet'}
                }
            }

        created_event = service.events().insert(
            calendarId=calendar_id, body=event,
            conferenceDataVersion=1 if add_meet else 0
        ).execute()
        # WO-CSYNC-4: Direct Qdrant write — dashboard sees event immediately
        # Skip for recurring events — ingestor expands them into individual instances
        if not recurrence:
            _upsert_event_to_qdrant(created_event, google_calendar_id=calendar_id)
        trigger_ingestor_sync()
        notify_clients('calendar_updated')
        return created_event
    except Exception as e:
        logger.error(f"Error creating event: {e}")
        return {"error": str(e)}

def _update_event(event_id: str, summary: Optional[str] = None, start_time: Optional[str] = None, end_time: Optional[str] = None, description: Optional[str] = None, attendees: Optional[List[str]] = None, calendar_id: str = "primary") -> Dict[str, Any]:
    """
    Updates an existing event.
    """
    try:
        if start_time:
            _require_explicit_offset(start_time)
        if end_time:
            _require_explicit_offset(end_time)
    except ValueError as e:
        return {"error": str(e)}
    try:
        service = get_calendar_service()
        body = {}
        if summary: body['summary'] = summary
        if description: body['description'] = description
        if start_time: body['start'] = {'dateTime': start_time}
        if end_time: body['end'] = {'dateTime': end_time}
        if attendees is not None: 
            body['attendees'] = [{'email': email} for email in attendees]
            
        updated_event = service.events().patch(calendarId=calendar_id, eventId=event_id, body=body).execute()
        # WO-CSYNC-4: Direct Qdrant write — dashboard sees update immediately
        _upsert_event_to_qdrant(updated_event, google_calendar_id=calendar_id)
        trigger_ingestor_sync()
        notify_clients('calendar_updated')
        return updated_event
    except Exception as e:
        logger.error(f"Error updating event: {e}")
        return {"error": str(e)}

def _delete_event(event_id: str, calendar_id: str = "primary", scope: str = "this") -> Dict[str, Any]:
    """
    Deletes an event from Google Calendar and removes its Qdrant point(s).
    Treats 410 (Gone) as success — event was already deleted.

    Args:
        event_id: Google Calendar event ID
        calendar_id: Google Calendar ID (default: "primary")
        scope: "this" = delete single instance (default).
               "all"  = delete entire recurring series + all Qdrant instances.
    """
    qdrant_host = os.environ.get('QDRANT_HOST', 'qdrant')
    qdrant_port = os.environ.get('QDRANT_PORT', '6333')
    qdrant_url = f"http://{qdrant_host}:{qdrant_port}"

    def _cleanup_qdrant(evt_id):
        """Remove the Qdrant point so the dashboard reflects immediately."""
        try:
            requests.post(
                f"{qdrant_url}/collections/calendar/points/delete",
                json={"filter": {"must": [{"key": "calendar_id", "match": {"value": evt_id}}]}},
                timeout=5
            )
        except Exception as qe:
            logger.warning(f"Qdrant cleanup failed (non-fatal): {qe}")

    def _cleanup_qdrant_series(recurring_id):
        """Remove ALL Qdrant points for a recurring series by recurring_event_id."""
        try:
            resp = requests.post(
                f"{qdrant_url}/collections/calendar/points/delete",
                json={"filter": {"must": [{"key": "recurring_event_id", "match": {"value": recurring_id}}]}},
                timeout=10
            )
            logger.info(f"Qdrant series cleanup for recurring_event_id={recurring_id}: {resp.status_code}")
        except Exception as qe:
            logger.warning(f"Qdrant series cleanup failed (non-fatal): {qe}")

    # ── scope="all": delete entire recurring series ──────────────────────
    if scope == "all":
        try:
            service = get_calendar_service()
            # Fetch event to find the parent recurring event ID
            event = service.events().get(calendarId=calendar_id, eventId=event_id).execute()
            recurring_id = event.get('recurringEventId', event.get('id', event_id))
            # Delete the PARENT event (this cancels all instances on Google)
            service.events().delete(calendarId=calendar_id, eventId=recurring_id).execute()
            logger.info(f"Deleted recurring parent {recurring_id} from Google Calendar.")
        except Exception as e:
            e_str = str(e).lower()
            if '410' in e_str or '404' in e_str or 'not found' in e_str or 'deleted' in e_str:
                logger.info(f"Recurring parent already deleted (404/410).")
                recurring_id = event_id  # fallback for Qdrant cleanup
            else:
                logger.error(f"Error deleting recurring series: {e}")
                return {"error": str(e)}

        # Clean up ALL Qdrant instance points for this series
        _cleanup_qdrant_series(recurring_id)
        # Also clean the parent point itself (in case it exists)
        _cleanup_qdrant(recurring_id)
        notify_clients('calendar_updated')
        return {"status": "deleted", "eventId": recurring_id, "scope": "all"}

    # ── scope="this" (default): delete single instance ───────────────────
    try:
        service = get_calendar_service()
        service.events().delete(calendarId=calendar_id, eventId=event_id).execute()
    except Exception as e:
        # 410 Gone or 404 Not Found = already deleted — treat as success
        e_str = str(e).lower()
        if '410' in e_str or '404' in e_str or 'not found' in e_str or 'deleted' in e_str:
            logger.info(f"Event {event_id} already deleted (404/410), cleaning up Qdrant.")
        else:
            logger.error(f"Error deleting event: {e}")
            _cleanup_qdrant(event_id)  # still try Qdrant cleanup
            return {"error": str(e)}

    # Clean up Qdrant FIRST, before notifying dashboard
    _cleanup_qdrant(event_id)
    # Do NOT trigger ingestor sync — the event is gone from Google Calendar,
    # and a re-sync could re-index it from cached data before deletion propagates.
    notify_clients('calendar_updated')
    return {"status": "deleted", "eventId": event_id}

def _check_freebusy(time_min: str, time_max: str) -> Dict[str, Any]:
    """
    Checks free/busy status for the primary calendar.
    """
    try:
        _require_explicit_offset(time_min)
        _require_explicit_offset(time_max)
    except ValueError as e:
        return {"error": str(e)}
    try:
        service = get_calendar_service()
        body = {
            "timeMin": time_min,
            "timeMax": time_max,
            "items": [{"id": "primary"}]
        }
        return service.freebusy().query(body=body).execute()
    except Exception as e:
        logger.error(f"Error checking freebusy: {e}")
        return {"error": str(e)}

def _search_calendar_memory(query: str, limit: int = 5) -> str:
    """
    [DATABASE] Semantically search for PAST or FUTURE events stored in the local vector database.
    Use this for queries like "When was my last dentist appointment?" or "Project discussions last month".
    
    Args:
        query: Search text
        limit: Max results
    """
    try:
        client = get_qdrant_client()
        if not client:
            return "Error: Database connection unavailable."

        query_vector = get_embedding_via_http(query)
        if query_vector is None:
            return "Error: Failed to generate embedding for search query."

        search_result = client.query_points(
            collection_name=COLLECTION_NAME,
            query=query_vector,
            limit=limit
        )
        
        if not search_result.points:
            return "No matching events found in database."

        results = []
        for hit in search_result.points:
            p = hit.payload
            results.append(
                f"--- Event (Score: {hit.score:.2f}) ---\n"
                f"Summary: {p.get('summary')}\n"
                f"Start: {p.get('start')}\n"
                f"Snippet: {p.get('snippet')}\n"
            )
        
        return "\n".join(results)

    except Exception as e:
        logger.error(f"Search failed: {e}")
        return f"Error performing search: {str(e)}"

# MCP Tool Definitions
@mcp.tool()
@rate_limit(limit=100, period=60)
def list_events(max_results: int = 10, calendar_id: Optional[str] = None) -> List[Dict[str, Any]]:
    """Lists upcoming events. Fetches all calendars by default, or a specific one if calendar_id is provided."""
    return _list_events(max_results, calendar_id)

@mcp.tool()
@rate_limit(limit=5, period=60)
def debug_rate_limit() -> str:
    """Test tool for rate limit verification (Limit: 5/min)."""
    return "OK"

@mcp.tool()
@rate_limit(limit=100, period=60)
def create_event(summary: str, start_time: str, end_time: str, description: str = "", attendees: List[str] = [], time_zone: Optional[str] = None, calendar_id: str = "primary", recurrence: Optional[str] = None) -> Dict[str, Any]:
    """
    Creates an event. Defaults to primary calendar unless calendar_id is specified.
    
    Args:
        summary: Event title
        start_time: Start time in ISO 8601 format. MUST include an explicit timezone offset
                    (e.g., '+01:00') or 'Z' for UTC. Naive datetimes will be rejected.
        end_time: End time in ISO 8601 format. MUST include an explicit timezone offset.
        description: Optional event description
        attendees: Optional list of email addresses
        time_zone: Optional IANA timezone name (e.g., "America/Los_Angeles").
        calendar_id: Google Calendar ID (default: "primary"). Use the calendar's email
                     address for shared/family calendars.
        recurrence: Optional JSON list of RRULE strings for recurring events.
                    Example: '["RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=10"]'
    """
    return _create_event(summary, start_time, end_time, description, attendees, time_zone, calendar_id=calendar_id, recurrence=recurrence)

@mcp.tool()
def update_event(event_id: str, summary: str = None, start_time: str = None, end_time: str = None, description: str = None, attendees: List[str] = None, calendar_id: str = "primary") -> Dict[str, Any]:
    """
    Updates an existing event. Provide only the fields you want to update.
    start_time and end_time MUST include an explicit timezone offset (e.g., '+01:00') or 'Z' for UTC.
    calendar_id: Google Calendar ID (default: "primary").
    """
    return _update_event(event_id, summary, start_time, end_time, description, attendees, calendar_id=calendar_id)

@mcp.tool()
def delete_event(event_id: str, calendar_id: str = "primary", scope: str = "this") -> Dict[str, Any]:
    """
    Deletes an event by ID.

    Args:
        event_id: Google Calendar event ID
        calendar_id: Google Calendar ID (default: "primary").
        scope: "this" = delete single instance (default).
               "all"  = delete entire recurring series + all indexed instances.
    """
    return _delete_event(event_id, calendar_id=calendar_id, scope=scope)

@mcp.tool()
def check_freebusy(time_min: str, time_max: str) -> Dict[str, Any]:
    """Checks free/busy status for the primary calendar."""
    return _check_freebusy(time_min, time_max)

@mcp.tool()
def search_calendar_memory(query: str, limit: int = 5) -> str:
    """[DATABASE] Semantically search for PAST or FUTURE events."""
    return _search_calendar_memory(query, limit)

# ── Secondary Flask HTTP server for Dashboard ──────────────────────────
# Mirrors the gmail-mcp pattern: runs in a background thread alongside MCP.
import threading
import queue
from flask import Flask, jsonify, request as flask_request, Response

HTTP_PORT = int(os.getenv('HTTP_PORT', 8007))

# ── SSE Client Registry ────────────────────────────────────────────────
# Thread-safe list of per-client queues. Each connected dashboard tab gets
# its own Queue. notify_clients() fans out to all of them.
_sse_clients_lock = threading.Lock()
_sse_clients: list = []  # list[queue.Queue]

def notify_clients(event: str) -> None:
    """Broadcast an SSE event name to all connected dashboard clients."""
    with _sse_clients_lock:
        for q in list(_sse_clients):
            try:
                q.put_nowait(event)
            except queue.Full:
                pass  # Slow client — silently drop
http_app = Flask(__name__)

# ── Ingestor Sync Trigger ──────────────────────────────────────────────
def trigger_ingestor_sync():
    """Fire-and-forget POST to ingestor to re-index calendar events."""
    def _sync():
        try:
            resp = requests.post(
                "http://ingestor:8009/ingest",
                json={"target": "calendar"},
                timeout=10
            )
            if resp.status_code == 429:
                logger.warning("Ingestor rate-limited during calendar sync")
            elif resp.status_code != 200:
                logger.warning(f"Ingestor sync returned {resp.status_code}")
        except Exception as e:
            logger.warning(f"Ingestor sync failed (non-critical): {e}")
    threading.Thread(target=_sync, daemon=True).start()

def _ensure_offset(time_str: str) -> str:
    """Auto-append the container's local TZ offset if the datetime is naive.
    
    Dashboard date/time pickers produce naive strings like '2026-03-01T18:00:00'.
    This helper appends the local UTC offset (e.g., '+01:00') so they pass validation.
    MCP tools still require explicit offsets — this only applies to the HTTP API.
    """
    try:
        _require_explicit_offset(time_str)
        return time_str  # Already has offset
    except ValueError:
        # Naive — append local offset
        local_offset = datetime.datetime.now(datetime.timezone.utc).astimezone().strftime('%z')
        # Convert +0100 → +01:00
        if len(local_offset) == 5:
            local_offset = local_offset[:3] + ':' + local_offset[3:]
        return time_str + local_offset

@http_app.route('/events', methods=['POST'])
def http_create_event():
    """Create a calendar event (Dashboard Create Event panel)."""
    try:
        data = flask_request.get_json(force=True)
        summary = data.get('summary', '')
        start_time = data.get('start_time', '')
        end_time = data.get('end_time', '')
        description = data.get('description', '')
        attendees = data.get('attendees', [])
        time_zone = data.get('time_zone')
        add_meet = data.get('add_meet', False)
        calendar_id = data.get('calendar_id', 'primary')
        recurrence = data.get('recurrence')  # WO-CAL-REC-2: Optional RRULE list

        if not summary or not start_time or not end_time:
            return jsonify({'error': 'Missing required fields: summary, start_time, end_time'}), 400

        # Dashboard date pickers produce naive datetimes — auto-append local TZ offset
        start_time = _ensure_offset(start_time)
        end_time = _ensure_offset(end_time)

        result = _create_event(summary, start_time, end_time, description, attendees, time_zone, add_meet, calendar_id=calendar_id, recurrence=recurrence)

        if 'error' in result:
            return jsonify(result), 500

        meet_link = ''
        if add_meet and 'conferenceData' in result:
            entry_points = result['conferenceData'].get('entryPoints', [])
            for ep in entry_points:
                if ep.get('entryPointType') == 'video':
                    meet_link = ep.get('uri', '')
                    break

        return jsonify({
            'status': 'created',
            'event_id': result.get('id', ''),
            'html_link': result.get('htmlLink', ''),
            'meet_link': meet_link,
            'summary': result.get('summary', ''),
            'start': result.get('start', {}),
            'end': result.get('end', {}),
        }), 201
    except Exception as e:
        logger.error(f"Error creating event via HTTP: {e}")
        return jsonify({'error': str(e)}), 500

@http_app.route('/events/<event_id>', methods=['PATCH'])
def http_update_event(event_id):
    """Update an existing calendar event (Dashboard Edit) (WO-CAL-EDIT-1a)."""
    try:
        data = flask_request.get_json(force=True)
        summary = data.get('summary')
        start_time = data.get('start_time')
        end_time = data.get('end_time')
        description = data.get('description')
        attendees = data.get('attendees')
        calendar_id = data.get('calendar_id', 'primary')

        # At least one field must be provided
        if not any([summary, start_time, end_time, description is not None, attendees is not None]):
            return jsonify({'error': 'At least one field required: summary, start_time, end_time, description, attendees'}), 400

        # Auto-fix naive datetimes from dashboard pickers
        if start_time:
            start_time = _ensure_offset(start_time)
        if end_time:
            end_time = _ensure_offset(end_time)

        result = _update_event(event_id,
                               summary=summary,
                               start_time=start_time,
                               end_time=end_time,
                               description=description,
                               attendees=attendees,
                               calendar_id=calendar_id)

        if 'error' in result:
            return jsonify(result), 500

        return jsonify({
            'status': 'updated',
            'event_id': result.get('id', ''),
            'summary': result.get('summary', ''),
            'start': result.get('start', {}),
            'end': result.get('end', {}),
        }), 200
    except Exception as e:
        logger.error(f"Error updating event via HTTP: {e}")
        return jsonify({'error': str(e)}), 500

@http_app.route('/events', methods=['GET'])
def http_list_events():
    """List upcoming events from all calendars (or specific one via ?calendar_id=...)."""
    max_results = flask_request.args.get('limit', 10, type=int)
    calendar_id = flask_request.args.get('calendar_id')
    events = _list_events(max_results, calendar_id)
    return jsonify(events), 200

@http_app.route('/health', methods=['GET'])
def http_health():
    return jsonify({'status': 'ok', 'service': 'calendar-mcp-http'}), 200

@http_app.route('/events/stream')
def sse_stream():
    """SSE endpoint — streams calendar_updated events to the dashboard.

    Nginx proxies /api/calendar-events/stream → this endpoint (/events/stream).
    Connection stays open indefinitely; periodic ping keeps nginx from timing out.
    """
    client_queue: queue.Queue = queue.Queue(maxsize=10)
    with _sse_clients_lock:
        _sse_clients.append(client_queue)
    logger.info(f"Calendar SSE client connected ({len(_sse_clients)} total)")

    def generate():
        try:
            while True:
                try:
                    event = client_queue.get(timeout=30)
                    yield f"event: {event}\ndata: {event}\n\n"
                except queue.Empty:
                    yield ": ping\n\n"
                    continue  # CRITICAL: never break (spec §7 Issue 1)
        except GeneratorExit:
            pass
        finally:
            with _sse_clients_lock:
                try:
                    _sse_clients.remove(client_queue)
                except ValueError:
                    pass
            logger.info(f"Calendar SSE client disconnected ({len(_sse_clients)} remaining)")

    return http_app.response_class(
        generate(),
        mimetype='text/event-stream',
        headers={
            'X-Accel-Buffering': 'no',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
        }
    )

@http_app.route('/events/<event_id>', methods=['DELETE'])
def http_delete_event(event_id):
    """Delete a calendar event (Dashboard delete button / E2E cleanup)."""
    try:
        calendar_id = flask_request.args.get('calendar_id', 'primary')
        scope = flask_request.args.get('scope', 'this')
        result = _delete_event(event_id, calendar_id=calendar_id, scope=scope)
        if 'error' in result:
            return jsonify(result), 400
        return jsonify(result), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@http_app.route('/respond/<event_id>', methods=['POST'])
def http_respond_to_event(event_id):
    """RSVP to a calendar event (WO-CAL-RSVP-2).
    
    Body: {"response": "accepted"|"declined"|"tentative"}
    Uses events().patch() with only the current user's attendee entry
    to avoid overwriting other attendees' statuses.
    """
    VALID_RESPONSES = {'accepted', 'declined', 'tentative'}
    try:
        data = flask_request.get_json(silent=True) or {}
        response_status = data.get('response', '').strip().lower()
        calendar_id = data.get('calendar_id', 'primary')
        if response_status not in VALID_RESPONSES:
            return jsonify({
                'error': f'Invalid response. Must be one of: {", ".join(sorted(VALID_RESPONSES))}'
            }), 400

        service = get_calendar_service()
        if not service:
            return jsonify({'error': 'Calendar service unavailable'}), 503

        # Discover account email to identify our attendee entry
        account_email = service.calendars().get(calendarId='primary').execute().get('id', '')
        if not account_email:
            return jsonify({'error': 'Could not determine account email'}), 500

        # Fetch current event to get full attendees list
        event = service.events().get(calendarId=calendar_id, eventId=event_id).execute()
        attendees = event.get('attendees', [])

        # Update only our entry; preserve all others
        found = False
        for att in attendees:
            if att.get('email', '').lower() == account_email.lower():
                att['responseStatus'] = response_status
                found = True
                break

        if not found:
            # We're not in attendees — add ourselves
            attendees.append({'email': account_email, 'responseStatus': response_status})

        # Patch with full attendees list (required by Google API)
        service.events().patch(
            calendarId=calendar_id,
            eventId=event_id,
            body={'attendees': attendees},
            sendUpdates='all'
        ).execute()

        logger.info(f"RSVP {response_status} for event {event_id} by {account_email}")

        # Trigger Qdrant re-sync + notify dashboard
        trigger_ingestor_sync()
        notify_clients('calendar_updated')

        return jsonify({
            'success': True,
            'event_id': event_id,
            'status': response_status,
            'account_email': account_email
        }), 200

    except HttpError as e:
        logger.error(f"Google Calendar API error responding to {event_id}: {e}")
        return jsonify({'error': f'Google Calendar error: {e.reason}'}), e.resp.status
    except Exception as e:
        logger.error(f"Error responding to event {event_id}: {e}")
        return jsonify({'error': str(e)}), 500


def start_http_server():
    """Start Flask HTTP server in a background thread."""
    logger.info(f"Starting Calendar HTTP API on port {HTTP_PORT}")
    http_app.run(host='0.0.0.0', port=HTTP_PORT, threaded=True)


if __name__ == "__main__":
    # Determine transport based on environment, default to stdio
    transport = os.getenv("MCP_TRANSPORT", "stdio").lower()
    
    # Auto-detect Docker environment interaction
    if (os.path.exists("/.dockerenv") or os.getenv("DOCKER_CONTAINER")) and os.getenv("MCP_TRANSPORT") is None:
        transport = "stdio" 

    # Start HTTP server only in SSE mode (primary process).
    # In stdio mode (bridge-spawned), the primary SSE instance already owns the HTTP port.
    if transport == "sse":
        http_thread = threading.Thread(target=start_http_server, daemon=True)
        http_thread.start()
    
    if transport == "sse":
        mcp.run(transport="sse", host="0.0.0.0", port=8000)
    else:
        mcp.run(transport="stdio")
