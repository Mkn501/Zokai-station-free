# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
import os
import threading
import time as _time
import queue
import base64
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
from typing import Optional, List, Dict, Any
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from fastmcp import FastMCP
from qdrant_client import QdrantClient
from qdrant_client.http import models
from fastembed import SparseTextEmbedding
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
mcp = FastMCP("Gmail MCP")

# --- Configuration (RAG) ---
QDRANT_HOST = os.environ.get('QDRANT_HOST', 'qdrant')
QDRANT_PORT = int(os.environ.get('QDRANT_PORT', 6333))
COLLECTION_NAME = "emails"

# Configure logging
# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("gmail-mcp")

# --- Configuration ---
VECTOR_SIZE = int(os.environ.get('VECTOR_SIZE', 768))

# --- Configuration ---
SCOPES = ['https://www.googleapis.com/auth/gmail.readonly', 'https://www.googleapis.com/auth/gmail.compose']
API_SERVICE_NAME = 'gmail'
API_VERSION = 'v1'

import requests
from qdrant_client import QdrantClient

# Configuration for centralized embedding server
EMBEDDING_BASE_URL = os.getenv("EMBEDDING_BASE_URL", "http://embedding-server:7997")
EMBEDDING_MODEL_ID = os.getenv("EMBEDDING_MODEL_ID", "sentence-transformers/paraphrase-multilingual-mpnet-base-v2")

# Global Qdrant Client
q_client = None

# BM25 sparse embedding model (tokenizer-only, ~1MB, no GPU needed)
try:
    bm25_model = SparseTextEmbedding(model_name="Qdrant/bm25")
    logging.info("BM25 sparse embedding model loaded")
except Exception as e:
    logging.warning(f"BM25 model failed to load: {e} — sparse search disabled")
    bm25_model = None

def _get_bm25_sparse_vector(text: str):
    """Generate BM25 sparse vector for a query string."""
    if bm25_model is None:
        return None
    try:
        results = list(bm25_model.query_embed(text))
        if results:
            sr = results[0]
            return models.SparseVector(
                indices=sr.indices.tolist(),
                values=sr.values.tolist(),
            )
    except Exception as e:
        logging.warning(f"BM25 query embedding failed: {e}")
    return None

def get_qdrant_client():
    global q_client
    if not q_client:
        host = os.environ.get('QDRANT_HOST', 'qdrant')
        port = int(os.environ.get('QDRANT_PORT', 6333))
        try:
            q_client = QdrantClient(host=host, port=port)
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


# Import TokenManager from shared package
try:
    from workstation_auth import TokenManager
except ImportError:
    # Fallback for when running without shared package in path (e.g. legacy local runs)
    logging.warning("Shared workstation_auth not found in path")
    TokenManager = None

def get_gmail_service():
    """Authenticates and returns a Gmail API service object using TokenManager."""
    if TokenManager:
        try:
            tm = TokenManager()
            creds = tm.get_credentials(SCOPES)
            return build(API_SERVICE_NAME, API_VERSION, credentials=creds)
        except Exception as e:
            logger.error(f"TokenManager failed: {e}")
            raise
    else:
        # Legacy fallback if shared package missing
        raise ImportError("workstation_auth package not found. Ensure shared/ directory is mounted.")

@mcp.tool()
@rate_limit(limit=50, period=60)
def list_inbox_emails(query: str = "", max_results: int = 10) -> List[Dict[str, Any]]:
    """
    [LIVE API] Lists emails directly from the user's Gmail Inbox.
    Use this to see what is currently in the mailbox (unread, recent, etc).
    Does NOT search the vector database.
    
    Args:
        query: The search query (e.g., "from:user@example.com", "is:unread")
        max_results: The maximum number of results to return (default: 10)
    """
    try:
        service = get_gmail_service()
        results = service.users().messages().list(userId='me', q=query, maxResults=max_results).execute()
        messages = results.get('messages', [])
        
        detailed_messages = []
        for msg in messages:
            try:
                # Fetch details for each message to get snippet and headers
                msg_detail = service.users().messages().get(
                    userId='me', 
                    id=msg['id'], 
                    format='full' # Get full format to extract snippet and headers safely
                ).execute()
                
                payload = msg_detail.get('payload', {})
                headers_list = payload.get('headers', [])
                headers = {h['name']: h['value'] for h in headers_list}
                
                detailed_messages.append({
                    'id': msg['id'],
                    'threadId': msg['threadId'],
                    'snippet': msg_detail.get('snippet', ''),
                    'subject': headers.get('Subject', '(No Subject)'),
                    'from': headers.get('From', '(Unknown Sender)'),
                    'date': headers.get('Date', '')
                })
            except Exception as e:
                logger.error(f"Error fetching details for message {msg['id']}: {e}")
                detailed_messages.append(msg)
                
        return detailed_messages
    except Exception as error:
        logger.error(f"Gmail API error: {error}")
        return [{"error": str(error)}]
    except Exception as e:
        logger.error(f"Error listing emails: {e}")
        return [{"error": str(e)}]

@mcp.tool()
@rate_limit(limit=5, period=60)
def trigger_ingestion(count: int = 50) -> str:
    """
    [ADMIN] Triggers an immediate ingestion of emails into the database.
    Use this when the user asks to "update", "sync", or "ingest" more emails manually.
    
    Args:
        count: The number of recent emails to ingest (default: 50). Increase this to ingest older history.
    """
    try:
        # The ingestor service is reachable by its container name "ingestor" (or "workstation-ingestor" depending on network alias, 
        # but docker-compose service name is 'ingestor' and they share a network)
        # Note: In docker-compose.yml service name is 'ingestor'.
        url = "http://ingestor:8009/ingest"
        
        logger.info(f"Triggering ingestion via {url} with batch_size={count}")
        # Pass deep_sync=True to enable full mailbox pagination (up to 100 pages/50k emails)
        response = requests.post(url, json={"batch_size": count, "deep_sync": True}, timeout=300) # Increased timeout for deep sync
        
        if response.status_code == 200:
            data = response.json()
            return f"Ingestion triggered successfully. Processed {data.get('processed_count', 'unknown')} emails."
        else:
            return f"Ingestion failed with status {response.status_code}: {response.text}"
            
    except Exception as e:
        logger.error(f"Error triggering ingestion: {e}")
        return f"Error triggering ingestion: {str(e)}"

@mcp.tool()
def get_database_stats() -> str:
    """
    [DATABASE] Returns detailed statistics about the ingested emails in the vector database.
    Includes total count and the date range (earliest and latest email).
    Use this to answer "What period does the database cover?" or "How many emails do I have?".
    """
    try:
        client = get_qdrant_client()
        if not client:
            return "Error: Database connection unavailable."
            
        count_result = client.count(collection_name="emails")
        total_count = count_result.count
        
        if total_count == 0:
             return "Database is empty. No emails ingested yet."

        # Estimate date range by sampling. 
        # (For a true full scan we'd need a Scroll loop, but for responsiveness we sample recent additions or just a batch)
        # Note: Without a 'payload index' on 'date', we can't efficiently sort on DB side easily in Qdrant v1.x without config.
        # We will fetch a batch of points and find min/max. For small DBs (this workstation), fetching all headers is fine.
        # Limit to 500 for performance safety.
        
        # Fetch up to 100 recent items to get a meaningful sample
        # Note: Qdrant scroll is not ordered by default. We must sort manually in client.
        scroll_result, _ = client.scroll(
            collection_name="emails",
            limit=100,
            with_payload=True,
            with_vectors=False
        )
        
        # Helper to parse dates loosely
        from email.utils import parsedate_to_datetime
        from datetime import datetime
        
        def parse_date(pt):
            date_str = pt.payload.get('date')
            try:
                return parsedate_to_datetime(date_str) if date_str else datetime.min
            except (ValueError, TypeError):
                return datetime.min

        # Sort descending (newest first)
        sorted_points = sorted(scroll_result, key=parse_date, reverse=True)
        
        dates = [p.payload.get('date') for p in sorted_points if p.payload.get('date')]
        
        # Simple string-based info for now, the Agent can parse "Wed, 24 Dec 2025" etc.
        
        stats = {
            "total_emails": total_count,
            "sample_size": len(dates),
            "date_examples": dates[:3] # Show top 3 newest
        }
        
        return f"Database Stats:\nTotal Emails: {stats['total_emails']}\nLatest Dates: {stats['date_examples']}"

    except Exception as e:
        logger.error(f"Error getting stats: {e}")
        return f"Error getting database stats: {str(e)}"

import re as _re
from email.utils import parsedate_to_datetime as _parsedate

def _parse_search_query(raw_query: str):
    """Parse Gmail-style prefixes: from:, subject:, to:, after:, before:, has:attachment.
    Returns (filters_dict, remaining_text).
    filters_dict keys: 'sender', 'subject', 'to' (text match),
                       'after', 'before' (epoch int), 'has_attachments' (bool).
    """
    filters = {}
    remaining = raw_query

    # Text-match operators: from:, subject:, to:
    for prefix, field in [('from', 'sender'), ('subject', 'subject'), ('to', 'to')]:
        pattern = _re.compile(rf'{prefix}:"([^"]+)"|{prefix}:(\S+)', _re.IGNORECASE)
        match = pattern.search(remaining)
        if match:
            value = match.group(1) or match.group(2)
            filters[field] = value.strip()
            remaining = remaining[:match.start()] + remaining[match.end():]

    # Date operators: after:YYYY-MM-DD, before:YYYY-MM-DD
    for prefix in ('after', 'before'):
        pattern = _re.compile(rf'{prefix}:(\S+)', _re.IGNORECASE)
        match = pattern.search(remaining)
        if match:
            date_str = match.group(1)
            try:
                from datetime import datetime as _dt
                dt = _dt.strptime(date_str, '%Y-%m-%d')
                filters[prefix] = int(dt.timestamp())
            except ValueError:
                logger.warning(f"Could not parse date '{date_str}' for {prefix}: operator")
            remaining = remaining[:match.start()] + remaining[match.end():]

    # Boolean operator: has:attachment
    has_pattern = _re.compile(r'has:attachment', _re.IGNORECASE)
    match = has_pattern.search(remaining)
    if match:
        filters['has_attachments'] = True
        remaining = remaining[:match.start()] + remaining[match.end():]

    return filters, remaining.strip()


def _targeted_payload_search(client, filters: dict, limit: int):
    """Payload-only search using parsed prefix filters (AND logic).
    Supports text match (sender, subject, to), date ranges (after, before),
    and boolean filters (has_attachments).
    """
    try:
        conditions = []
        for field, value in filters.items():
            if field in ('sender', 'subject', 'to'):
                conditions.append(
                    models.FieldCondition(key=field, match=models.MatchText(text=value))
                )
            elif field == 'after':
                conditions.append(
                    models.FieldCondition(key='date_epoch', range=models.Range(gte=value))
                )
            elif field == 'before':
                conditions.append(
                    models.FieldCondition(key='date_epoch', range=models.Range(lte=value))
                )
            elif field == 'has_attachments':
                conditions.append(
                    models.FieldCondition(key='has_attachments', match=models.MatchValue(value=True))
                )
        results, _ = client.scroll(
            collection_name=COLLECTION_NAME,
            scroll_filter=models.Filter(must=conditions),
            limit=limit,
            with_payload=True,
            with_vectors=False,
        )
        # Sort by recency
        results = sorted(results, key=lambda pt: pt.payload.get('date_epoch', 0), reverse=True)
        return list(results)
    except Exception as e:
        logger.warning(f"Targeted payload search failed: {e}")
        return []


def _payload_search(client, query: str, limit: int):
    """Broad payload fallback — match sender OR subject by text (no prefix)."""
    try:
        results, _ = client.scroll(
            collection_name=COLLECTION_NAME,
            scroll_filter=models.Filter(should=[
                models.FieldCondition(key="sender", match=models.MatchText(text=query)),
                models.FieldCondition(key="subject", match=models.MatchText(text=query)),
                models.FieldCondition(key="snippet", match=models.MatchText(text=query)),
                models.FieldCondition(key="body", match=models.MatchText(text=query)),
            ]),
            limit=limit,
            with_payload=True,
            with_vectors=False,
        )
        return results
    except Exception as e:
        logger.warning(f"Payload search fallback failed: {e}")
        return []


@mcp.tool()
@rate_limit(limit=100, period=60)
def search_stored_emails(query: str, limit: int = 5) -> str:
    """
    [DATABASE] Semantically search for emails stored in the local vector database.
    Use this for context-aware questions like "Find invoices", "What did X say about Y?".
    Does NOT search the live Gmail inbox, only what has been ingested.
    
    Args:
        query: The search question or topic (e.g., "invoices from last week", "project updates")
        limit: Number of results to return (default: 5)
    
    Returns:
        A formatted string containing the most relevant email snippets.
    """
    try:
        client = get_qdrant_client()
        if not client:
            return "Error: Database connection unavailable."

        # Parse query for from:/subject: prefixes
        filters, remaining_text = _parse_search_query(query)

        if filters:
            # Prefix search: use ONLY payload filters (skip vector search)
            hits = _targeted_payload_search(client, filters, limit)
        else:
            # No prefix: hybrid vector + payload merge
            query_vector = get_embedding_via_http(query)
            if query_vector is None:
                return "Error: Failed to generate embedding for search query."

            prefetch_list = [
                models.Prefetch(
                    query=query_vector,
                    using="dense",
                    limit=limit * 3,
                ),
            ]
            sparse_vec = _get_bm25_sparse_vector(query)
            if sparse_vec is not None:
                prefetch_list.append(
                    models.Prefetch(
                        query=sparse_vec,
                        using="bm25",
                        limit=limit * 3,
                    )
                )
            search_result = client.query_points(
                collection_name="emails",
                prefetch=prefetch_list,
                query=models.FusionQuery(fusion=models.Fusion.RRF),
                limit=limit,
            )
            hits = search_result.points

            # Merge payload fallback for plain text queries
            payload_hits = _payload_search(client, query, limit)
            # Sort payload hits by recency (newest first)
            payload_hits.sort(key=lambda pt: pt.payload.get('date_epoch', 0), reverse=True)
            seen_ids = set()
            merged = []
            for pt in payload_hits:
                if pt.id not in seen_ids:
                    seen_ids.add(pt.id)
                    merged.append(pt)
            for hit in hits:
                if hit.id not in seen_ids:
                    seen_ids.add(hit.id)
                    merged.append(hit)
            hits = merged[:limit]

        if not hits:
            return "No relevant emails found in database."

        # Format results
        results = []
        for hit in hits:
            p = hit.payload
            snippet = p.get('snippet', '')
            subject = p.get('subject', '(No Subject)')
            sender = p.get('sender', 'Unknown')
            date = p.get('date', 'Unknown')
            
            # Using MD format for readability by LLM
            entry = (
                f"--- Email (Score: {hit.score:.2f}) ---\n"
                f"Subject: {subject}\n"
                f"From: {sender}\n"
                f"Date: {date}\n"
                f"Snippet: {snippet}\n"
            )
            results.append(entry)

        return "\n".join(results)

    except Exception as e:
        logger.error(f"Search failed: {e}")
        return f"Error performing search: {str(e)}"

@mcp.tool()
def create_draft(to: str, subject: str, message_text: str, html_body: str = "") -> Dict[str, Any]:
    """
    Creates a draft email. Supports both plain text and HTML.
    
    Args:
        to: Recipient's email address
        subject: Email subject
        message_text: The plain text of the email body
        html_body: Optional HTML version of the email body for rich formatting
    """
    try:
        service = get_gmail_service()
        
        if html_body:
            # MIMEMultipart('alternative') sends both plain + HTML; client picks best
            message = MIMEMultipart('alternative')
            message.attach(MIMEText(message_text, 'plain'))
            message.attach(MIMEText(html_body, 'html'))
        else:
            message = MIMEText(message_text)
        
        message['to'] = to
        message['subject'] = subject
        encoded_message = base64.urlsafe_b64encode(message.as_bytes()).decode()
        
        create_message = {'message': {'raw': encoded_message}}
        
        draft = service.users().drafts().create(userId='me', body=create_message).execute()
        notify_clients('drafts_updated')
        return draft
    except Exception as error:
        logger.error(f"Gmail API error: {error}")
        return {"error": str(error)}
    except Exception as e:
        logger.error(f"Error creating draft: {e}")
        return {"error": str(e)}

@mcp.tool()
def update_draft(draft_id: str, to: str = "", subject: str = "", message_text: str = "", html_body: str = "") -> Dict[str, Any]:
    """
    Updates an existing Gmail draft with new To, Subject, and/or Body content.
    All fields are optional — only provided fields will be updated.
    
    Args:
        draft_id: The Gmail draft ID to update
        to: New recipient email address (optional)
        subject: New email subject (optional)
        message_text: New plain text body (optional)
        html_body: Optional HTML version of the body
    """
    try:
        service = get_gmail_service()
        
        # Fetch existing draft to preserve unchanged fields
        existing = service.users().drafts().get(userId='me', id=draft_id, format='full').execute()
        existing_headers = {h['name'].lower(): h['value'] for h in existing.get('message', {}).get('payload', {}).get('headers', [])}
        existing_body = existing.get('message', {}).get('snippet', '')
        
        final_to = to or existing_headers.get('to', '')
        final_subject = subject or existing_headers.get('subject', '(No Subject)')
        final_body = message_text or existing_body
        
        if html_body:
            message = MIMEMultipart('alternative')
            message.attach(MIMEText(final_body, 'plain'))
            message.attach(MIMEText(html_body, 'html'))
        else:
            message = MIMEText(final_body)
        
        message['to'] = final_to
        message['subject'] = final_subject
        encoded_message = base64.urlsafe_b64encode(message.as_bytes()).decode()
        
        updated = service.users().drafts().update(
            userId='me', id=draft_id,
            body={'message': {'raw': encoded_message}}
        ).execute()
        notify_clients('drafts_updated')
        return updated
    except Exception as e:
        logger.error(f"Error updating draft {draft_id}: {e}")
        return {"error": str(e)}

@mcp.tool()
def create_reply_draft(message_id: str, reply_text: str, html_body: str = "") -> Dict[str, Any]:
    """
    Creates a reply draft to an existing email with proper threading headers.
    The draft appears in the same thread as the original email.
    
    Args:
        message_id: The Gmail message ID to reply to
        reply_text: The plain text reply body
        html_body: Optional HTML version of the reply body
    """
    try:
        service = get_gmail_service()
        
        # 1. Fetch original message metadata for threading
        original = service.users().messages().get(
            userId='me', id=message_id, format='metadata',
            metadataHeaders=['Subject', 'From', 'To', 'Message-ID']
        ).execute()
        
        headers = {h['name']: h['value'] for h in original.get('payload', {}).get('headers', [])}
        thread_id = original.get('threadId', '')
        orig_subject = headers.get('Subject', '')
        orig_from = headers.get('From', '')
        orig_message_id = headers.get('Message-ID', '')
        
        # 2. Build reply subject (prepend "Re:" if missing)
        reply_subject = orig_subject if orig_subject.lower().startswith('re:') else f'Re: {orig_subject}'
        
        # 3. Build MIME message with threading headers
        if html_body:
            message = MIMEMultipart('alternative')
            message.attach(MIMEText(reply_text, 'plain'))
            message.attach(MIMEText(html_body, 'html'))
        else:
            message = MIMEText(reply_text)
        
        message['to'] = orig_from  # Reply to the sender
        message['subject'] = reply_subject
        if orig_message_id:
            message['In-Reply-To'] = orig_message_id
            message['References'] = orig_message_id
        
        encoded_message = base64.urlsafe_b64encode(message.as_bytes()).decode()
        
        # 4. Create draft in the same thread
        create_body = {
            'message': {
                'raw': encoded_message,
                'threadId': thread_id
            }
        }
        
        draft = service.users().drafts().create(userId='me', body=create_body).execute()
        notify_clients('drafts_updated')
        return {
            'draft_id': draft.get('id', ''),
            'thread_id': thread_id,
            'reply_to': orig_from,
            'subject': reply_subject
        }
    except Exception as error:
        logger.error(f"Gmail API error creating reply draft: {error}")
        return {"error": str(error)}
    except Exception as e:
        logger.error(f"Error creating reply draft: {e}")
        return {"error": str(e)}

@mcp.tool()
def list_drafts(max_results: int = 20) -> List[Dict[str, Any]]:
    """
    [LIVE API] Lists all drafts in the user's Gmail account.
    Used by the Dashboard Draft Box to show pending drafts for review.
    
    Args:
        max_results: Maximum number of drafts to return (default: 20)
    """
    try:
        service = get_gmail_service()
        results = service.users().drafts().list(userId='me', maxResults=max_results).execute()
        drafts = results.get('drafts', [])
        
        detailed_drafts = []
        for d in drafts:
            try:
                draft_detail = service.users().drafts().get(userId='me', id=d['id'], format='metadata').execute()
                msg = draft_detail.get('message', {})
                headers = {h['name'].lower(): h['value'] for h in msg.get('payload', {}).get('headers', [])}
                detailed_drafts.append({
                    'id': d['id'],
                    'message_id': msg.get('id', ''),
                    'thread_id': msg.get('threadId', ''),
                    'subject': headers.get('subject', '(No Subject)'),
                    'to': headers.get('to', ''),
                    'date': headers.get('date', ''),
                    'snippet': msg.get('snippet', '')
                })
            except Exception as e:
                logger.error(f"Error fetching draft {d['id']}: {e}")
                detailed_drafts.append({'id': d['id'], 'error': str(e)})
        
        return detailed_drafts
    except Exception as error:
        logger.error(f"Gmail API error listing drafts: {error}")
        return [{"error": str(error)}]
    except Exception as e:
        logger.error(f"Error listing drafts: {e}")
        return [{"error": str(e)}]

@mcp.tool()
def get_draft(draft_id: str) -> Dict[str, Any]:
    """
    [LIVE API] Gets the full content of a specific draft.
    Used by the Dashboard review modal to display draft body before approve/discard.
    
    Args:
        draft_id: The Gmail draft ID
    """
    try:
        service = get_gmail_service()
        draft = service.users().drafts().get(userId='me', id=draft_id, format='full').execute()
        msg = draft.get('message', {})
        headers = {h['name'].lower(): h['value'] for h in msg.get('payload', {}).get('headers', [])}
        
        # Extract body
        payload = msg.get('payload', {})
        parts = payload.get('parts', [])
        body = ''
        
        def _extract_text(parts_list):
            for part in parts_list:
                if part.get('mimeType') == 'text/plain':
                    data = part.get('body', {}).get('data')
                    if data:
                        return base64.urlsafe_b64decode(data).decode()
                if 'parts' in part:
                    found = _extract_text(part['parts'])
                    if found:
                        return found
            return None
        
        if not parts:
            data = payload.get('body', {}).get('data')
            if data:
                body = base64.urlsafe_b64decode(data).decode()
        else:
            body = _extract_text(parts) or ''
        
        return {
            'id': draft_id,
            'subject': headers.get('subject', '(No Subject)'),
            'to': headers.get('to', ''),
            'from': headers.get('from', ''),
            'date': headers.get('date', ''),
            'body': body or msg.get('snippet', '(No content)'),
            'thread_id': msg.get('threadId', '')
        }
    except Exception as error:
        logger.error(f"Gmail API error getting draft: {error}")
        return {"error": str(error)}
    except Exception as e:
        logger.error(f"Error getting draft: {e}")
        return {"error": str(e)}

@mcp.tool()
def delete_draft(draft_id: str) -> str:
    """
    Deletes a draft from Gmail.
    Used by the Dashboard "Discard" button.
    
    Args:
        draft_id: The Gmail draft ID to delete
    """
    try:
        service = get_gmail_service()
        service.users().drafts().delete(userId='me', id=draft_id).execute()
        notify_clients('drafts_updated')
        return f"Draft {draft_id} deleted successfully."
    except Exception as error:
        logger.error(f"Gmail API error deleting draft: {error}")
        return f"Error deleting draft: {str(error)}"
    except Exception as e:
        logger.error(f"Error deleting draft: {e}")
        return f"Error deleting draft: {str(e)}"

@mcp.tool()
def send_draft(draft_id: str) -> Dict[str, Any]:
    """
    Sends an existing draft via Gmail.
    Used by the Dashboard "Approve & Send" button. The user must explicitly approve.
    
    Args:
        draft_id: The Gmail draft ID to send
    """
    try:
        service = get_gmail_service()
        result = service.users().drafts().send(userId='me', body={'id': draft_id}).execute()
        notify_clients('drafts_updated')
        # WO-GSYNC-12: Sent email changes inbox state — notify dashboard + trigger re-index
        notify_clients('mail_updated')
        trigger_ingestor_sync()
        return {
            'status': 'sent',
            'message_id': result.get('id', ''),
            'thread_id': result.get('threadId', ''),
            'label_ids': result.get('labelIds', [])
        }
    except Exception as error:
        logger.error(f"Gmail API error sending draft: {error}")
        return {"error": str(error)}
    except Exception as e:
        logger.error(f"Error sending draft: {e}")
        return {"error": str(e)}

@mcp.tool()
def read_inbox_email(message_id: str) -> str:
    """
    [LIVE API] Reads the full content of an email directly from Gmail.
    Use this when you have a message_id (from list_inbox_emails) and need to read the full body.
    
    Args:
        message_id: The ID of the email to read.
    """
    try:
        service = get_gmail_service()
        message = service.users().messages().get(userId='me', id=message_id, format='full').execute()
        
        payload = message.get('payload', {})
        parts = payload.get('parts', [])
        body = ""

        def extract_body(parts, prefer_html=True):
            """Walk MIME parts, prefer text/html for dashboard rendering, fallback to text/plain."""
            html_body = None
            text_body = None
            for part in parts:
                mime = part.get('mimeType', '')
                if mime == 'text/html' and not html_body:
                    data = part.get('body', {}).get('data')
                    if data:
                        html_body = base64.urlsafe_b64decode(data).decode()
                elif mime == 'text/plain' and not text_body:
                    data = part.get('body', {}).get('data')
                    if data:
                        text_body = base64.urlsafe_b64decode(data).decode()
                if 'parts' in part:
                    found = extract_body(part['parts'], prefer_html)
                    if found: 
                        if found.strip().startswith('<!') or found.strip().startswith('<html'):
                            html_body = html_body or found
                        else:
                            text_body = text_body or found
            # Prefer HTML for rich dashboard display
            if prefer_html and html_body:
                return html_body
            return text_body or html_body

        if not parts:
            # Non-multipart — check mimeType to determine if it's HTML
            mime = payload.get('mimeType', '')
            data = payload.get('body', {}).get('data')
            if data:
                body = base64.urlsafe_b64decode(data).decode()
        else:
            body = extract_body(parts)
            
        if not body:
            body = message.get('snippet', '(No content found)')
            
        return body
    except Exception as e:
        logger.error(f"Error reading email {message_id}: {e}")
        return f"Error reading email: {str(e)}"

# ── HTTP Server for Dashboard (WO-MAIL-5) ─────────────────────────────────
# ── Attachment helper ──────────────────────────────────────────────────
import mimetypes as _mimetypes

WORKSPACE_ROOT = '/workspaces'
MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024  # 25 MB Gmail limit

def _build_message_with_attachments(to, subject, body_text, files=None, attachment_paths=None):
    """Build a MIME message with optional file attachments.
    
    Args:
        to: Recipient email
        subject: Email subject
        body_text: Plain text body
        files: List of Flask FileStorage objects (from multipart/form-data)
        attachment_paths: List of absolute container paths (from workspace browser)
    Returns:
        MIMEMessage ready for base64 encoding
    """
    has_attachments = (files and len(files) > 0) or (attachment_paths and len(attachment_paths) > 0)
    
    if has_attachments:
        # Use 'mixed' for text + attachments
        message = MIMEMultipart('mixed')
        message.attach(MIMEText(body_text, 'plain'))
        total_size = 0
        
        # Path 1: Flask FileStorage (existing — multipart/form-data uploads)
        if files:
            for f in files:
                data = f.read()
                total_size += len(data)
                if total_size > MAX_ATTACHMENT_BYTES:
                    raise ValueError(f"Total attachments exceed 25 MB Gmail limit")
                part = MIMEBase('application', 'octet-stream')
                part.set_payload(data)
                encoders.encode_base64(part)
                part.add_header('Content-Disposition', f'attachment; filename="{f.filename}"')
                message.attach(part)
        
        # Path 2: Container paths (WO-MAIL-ATT-1c — workspace file browser)
        if attachment_paths:
            for p in attachment_paths:
                resolved = os.path.realpath(p)
                if not resolved.startswith(WORKSPACE_ROOT):
                    raise ValueError(f"Path outside workspace: {p}")
                if not os.path.isfile(resolved):
                    raise FileNotFoundError(f"File not found: {p}")
                
                file_size = os.path.getsize(resolved)
                total_size += file_size
                if total_size > MAX_ATTACHMENT_BYTES:
                    raise ValueError(f"Total attachments exceed 25 MB Gmail limit")
                
                mime, _ = _mimetypes.guess_type(os.path.basename(resolved))
                maintype, subtype = (mime or 'application/octet-stream').split('/', 1)
                part = MIMEBase(maintype, subtype)
                with open(resolved, 'rb') as fh:
                    part.set_payload(fh.read())
                encoders.encode_base64(part)
                part.add_header('Content-Disposition',
                    f'attachment; filename="{os.path.basename(resolved)}"')
                message.attach(part)
    else:
        message = MIMEText(body_text)
    
    message['to'] = to
    message['subject'] = subject
    return message


# Secondary Flask thread on port 8007 — serves REST endpoints for the
# dashboard's Draft Box and email body modal. Follows the ingestor pattern.
import threading
from flask import Flask, jsonify, request as flask_request

http_app = Flask(__name__)
HTTP_PORT = int(os.getenv('HTTP_PORT', 8007))

# ── Ingestor Sync Trigger (WO-GSYNC-12) ───────────────────────────────
def trigger_ingestor_sync():
    """Fire-and-forget POST to ingestor to re-index emails.
    Mirrors calendar-mcp's trigger_ingestor_sync() pattern."""
    def _sync():
        try:
            resp = requests.post(
                "http://ingestor:8009/ingest",
                json={"target": "email"},
                timeout=10
            )
            if resp.status_code == 429:
                logger.warning("Ingestor rate-limited during email sync")
            elif resp.status_code != 200:
                logger.warning(f"Ingestor sync returned {resp.status_code}")
        except Exception as e:
            logger.warning(f"Ingestor sync failed (non-critical): {e}")
    threading.Thread(target=_sync, daemon=True).start()

# ── SSE Client Management (Spec 3: Gmail Draft Sync) ────────────────
sse_clients: list = []  # List of queue.Queue objects

def notify_clients(event_type: str):
    """Push an SSE event to all connected dashboard clients."""
    dead = []
    for q in sse_clients:
        try:
            q.put_nowait(event_type)
        except queue.Full:
            dead.append(q)
    for q in dead:
        try:
            sse_clients.remove(q)
        except ValueError:
            pass

@http_app.route('/drafts/stream')
def sse_draft_stream():
    """SSE endpoint for real-time draft update notifications."""
    from flask import Response
    
    def generate():
        q = queue.Queue(maxsize=50)
        sse_clients.append(q)
        try:
            while True:
                try:
                    event = q.get(timeout=30)
                    yield f"data: {event}\n\n"
                except queue.Empty:
                    yield ": ping\n\n"  # keepalive
        except GeneratorExit:
            pass
        finally:
            try:
                sse_clients.remove(q)
            except ValueError:
                pass
    
    return Response(
        generate(),
        mimetype='text/event-stream',
        headers={
            'Cache-Control': 'no-cache',
            'X-Accel-Buffering': 'no',
            'Connection': 'keep-alive'
        }
    )

# ── WO-MAIL-ATT-1b: Workspace file browser ────────────────────────────
BROWSE_SKIP = {'.git', 'node_modules', '__pycache__', '.venv', 'venv', '.DS_Store'}

@http_app.route('/browse', methods=['GET'])
def http_browse():
    """Browse workspace files for email attachments.
    Returns directory listing for the given path (must be under /workspaces).
    """
    try:
        path = flask_request.args.get('path', WORKSPACE_ROOT)
        # Security: resolve symlinks and verify inside workspace root
        resolved = os.path.realpath(path)
        if not resolved.startswith(WORKSPACE_ROOT):
            return jsonify({'error': 'Path outside workspace'}), 403
        if not os.path.isdir(resolved):
            return jsonify({'error': 'Not a directory'}), 400

        entries = []
        try:
            items = sorted(os.listdir(resolved))
        except PermissionError:
            return jsonify({'error': 'Permission denied'}), 403

        for name in items:
            # Skip hidden files and noise directories
            if name.startswith('.') or name in BROWSE_SKIP:
                continue
            full = os.path.join(resolved, name)
            try:
                st = os.stat(full)
            except (OSError, PermissionError):
                continue
            if os.path.isdir(full):
                entries.append({'name': name, 'type': 'dir', 'size': 0})
            elif os.path.isfile(full):
                entries.append({'name': name, 'type': 'file', 'size': st.st_size})

        return jsonify({'path': resolved, 'entries': entries}), 200
    except Exception as e:
        logger.error(f"Error browsing workspace: {e}")
        return jsonify({'error': str(e)}), 500
@http_app.route('/read/<message_id>', methods=['GET'])
def http_read_email(message_id):
    """Full email body + attachment list for dashboard modal."""
    try:
        service = get_gmail_service()
        message = service.users().messages().get(
            userId='me', id=message_id, format='full'
        ).execute()

        body = read_inbox_email(message_id)

        # Extract attachment metadata from MIME parts
        attachments = []
        def _collect_attachments(parts):
            for part in parts:
                fname = part.get('filename', '')
                if fname:
                    size = int(part.get('body', {}).get('size', 0))
                    att_id = part.get('body', {}).get('attachmentId', '')
                    attachments.append({'name': fname, 'size': size, 'attachment_id': att_id})
                if 'parts' in part:
                    _collect_attachments(part['parts'])

        payload = message.get('payload', {})
        if 'parts' in payload:
            _collect_attachments(payload['parts'])

        return jsonify({'body': body, 'attachments': attachments}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@http_app.route('/attachment/<message_id>/save', methods=['POST'])
def http_save_attachment(message_id):
    """Download a Gmail attachment and save it to the workspace."""
    try:
        data = flask_request.get_json(force=True) or {}
        attachment_id = data.get('attachment_id', '')
        filename = data.get('filename', '')
        dest_dir = data.get('dest_dir', '/workspaces/mail-attachments')

        if not attachment_id or not filename:
            return jsonify({'error': 'attachment_id and filename are required'}), 400

        # Security: sanitize filename
        filename = os.path.basename(filename).replace('\x00', '')
        if not filename or filename.startswith('.'):
            return jsonify({'error': 'Invalid filename'}), 400

        # Security: dest_dir must be within /workspaces/mail-attachments
        ALLOWED_ROOT = '/workspaces/mail-attachments'
        resolved_dir = os.path.realpath(dest_dir)
        if not resolved_dir.startswith(ALLOWED_ROOT):
            return jsonify({'error': 'Destination outside allowed path'}), 400

        # Ensure destination directory exists
        os.makedirs(resolved_dir, exist_ok=True)

        # Fetch attachment binary from Gmail API
        service = get_gmail_service()
        att = service.users().messages().attachments().get(
            userId='me', messageId=message_id, id=attachment_id
        ).execute()

        file_data = base64.urlsafe_b64decode(att['data'])

        # 25 MB guard
        if len(file_data) > 25 * 1024 * 1024:
            return jsonify({'error': 'Attachment exceeds 25 MB limit'}), 400

        # Handle file collision — append _1, _2, etc.
        base, ext = os.path.splitext(filename)
        target = os.path.join(resolved_dir, filename)
        counter = 1
        while os.path.exists(target):
            target = os.path.join(resolved_dir, f"{base}_{counter}{ext}")
            counter += 1

        with open(target, 'wb') as fh:
            fh.write(file_data)

        return jsonify({
            'saved_path': target,
            'size': len(file_data),
            'filename': os.path.basename(target)
        }), 200
    except Exception as e:
        logging.error(f"Attachment save error: {e}", exc_info=True)
        return jsonify({'error': str(e)}), 500
@http_app.route('/unread-count', methods=['GET'])
def http_unread_count():
    """Get real Gmail INBOX unread count for the dashboard stat card."""
    try:
        service = get_gmail_service()
        label = service.users().labels().get(userId='me', id='INBOX').execute()
        return jsonify({
            'unread': label.get('messagesUnread', 0),
            'total': label.get('messagesTotal', 0)
        }), 200
    except Exception as e:
        logger.error(f"Error fetching unread count: {e}")
        return jsonify({'error': str(e)}), 500


# ── WO-MAIL-SYNC-2/5/6/7: Qdrant-based unread count + reconciliation ─────
def _reconcile_read_status():
    """WO-MAIL-SYNC-5: Diff Gmail unread IDs vs Qdrant is_read=false, batch-fix.

    1. Ask Gmail for current UNREAD message IDs (up to 500)
    2. Ask Qdrant for all emails with is_read=false
    3. Emails in Qdrant as unread but NOT in Gmail unread → set is_read=true
    4. Emails in Gmail unread but Qdrant has is_read=true → set is_read=false
    Returns dict with counts of fixes applied.
    """
    try:
        service = get_gmail_service()
        client = get_qdrant_client()
        if not client:
            return {"error": "qdrant_unavailable", "fixed": 0}

        # Step 1: Get Gmail unread IDs
        gmail_unread_ids = set()
        page_token = None
        for _ in range(10):  # max 10 pages = ~5000 messages
            result = service.users().messages().list(
                userId='me', labelIds=['UNREAD'], maxResults=500,
                pageToken=page_token
            ).execute()
            for msg in result.get('messages', []):
                gmail_unread_ids.add(msg['id'])
            page_token = result.get('nextPageToken')
            if not page_token:
                break

        # Step 2: Get Qdrant emails with is_read=false
        qdrant_unread = {}  # gmail_id -> point_id
        offset = None
        for _ in range(20):  # max 20 pages
            hits, offset = client.scroll(
                collection_name="emails",
                scroll_filter=models.Filter(
                    must=[models.FieldCondition(
                        key="is_read",
                        match=models.MatchValue(value=False)
                    )]
                ),
                limit=100,
                offset=offset,
                with_payload=["gmail_id"],
                with_vectors=False
            )
            for hit in hits:
                gid = hit.payload.get("gmail_id")
                if gid:
                    qdrant_unread[gid] = hit.id
            if offset is None:
                break

        # Step 3: Fix stale unread in Qdrant (marked unread but Gmail says read)
        stale_unread = set(qdrant_unread.keys()) - gmail_unread_ids
        fixed_read = 0
        if stale_unread:
            point_ids = [qdrant_unread[gid] for gid in stale_unread]
            # Batch in groups of 100
            for i in range(0, len(point_ids), 100):
                batch = point_ids[i:i+100]
                client.set_payload(
                    collection_name="emails",
                    payload={"is_read": True},
                    points=batch
                )
                fixed_read += len(batch)

        # Step 4: Fix missing unread (Gmail says unread but Qdrant says read)
        # Scroll Qdrant for emails matching gmail_unread_ids that have is_read=true
        fixed_unread = 0
        gmail_unread_list = list(gmail_unread_ids - set(qdrant_unread.keys()))
        # Check in batches of 50
        for i in range(0, len(gmail_unread_list), 50):
            batch_ids = gmail_unread_list[i:i+50]
            for gid in batch_ids:
                hits, _ = client.scroll(
                    collection_name="emails",
                    scroll_filter=models.Filter(
                        must=[
                            models.FieldCondition(
                                key="gmail_id",
                                match=models.MatchValue(value=gid)
                            ),
                            models.FieldCondition(
                                key="is_read",
                                match=models.MatchValue(value=True)
                            )
                        ]
                    ),
                    limit=1,
                    with_payload=False,
                    with_vectors=False
                )
                if hits:
                    client.set_payload(
                        collection_name="emails",
                        payload={"is_read": False},
                        points=[hits[0].id]
                    )
                    fixed_unread += 1

        total_fixed = fixed_read + fixed_unread
        if total_fixed > 0:
            logger.info(f"Reconciled read status: {fixed_read} marked read, {fixed_unread} marked unread")
        return {"fixed_read": fixed_read, "fixed_unread": fixed_unread, "gmail_unread_total": len(gmail_unread_ids)}

    except Exception as e:
        logger.error(f"Read status reconciliation failed: {e}")
        return {"error": str(e), "fixed": 0}





# ── WO-MAIL-SYNC-7: Background reconciliation daemon ──────────────────
_reconcile_thread_started = False

def _start_reconciliation_daemon():
    """Runs _reconcile_read_status() every 5 minutes in background."""
    global _reconcile_thread_started
    if _reconcile_thread_started:
        return
    _reconcile_thread_started = True

    def _daemon():
        import time as _time
        _time.sleep(60)  # Wait 1 min after startup before first reconciliation
        while True:
            try:
                _reconcile_read_status()
            except Exception as e:
                logger.error(f"Background reconciliation error: {e}")
            _time.sleep(300)  # Every 5 minutes

    t = threading.Thread(target=_daemon, daemon=True, name="read-status-reconciler")
    t.start()
    logger.info("Background read-status reconciliation daemon started (every 5 min)")

@http_app.route('/read/<message_id>/mark-read', methods=['POST'])
def http_mark_read(message_id):
    """Mark an email as read in Gmail (remove UNREAD label) AND sync to Qdrant."""
    try:
        service = get_gmail_service()
        service.users().messages().modify(
            userId='me',
            id=message_id,
            body={'removeLabelIds': ['UNREAD']}
        ).execute()

        # Sync Qdrant: find point by gmail_id, set is_read=true (fire-and-forget)
        try:
            client = get_qdrant_client()
            if client:
                hits, _offset = client.scroll(
                    collection_name="emails",
                    scroll_filter=models.Filter(
                        must=[models.FieldCondition(
                            key="gmail_id",
                            match=models.MatchValue(value=message_id)
                        )]
                    ),
                    limit=1,
                    with_payload=False,
                    with_vectors=False
                )
                if hits:
                    client.set_payload(
                        collection_name="emails",
                        payload={"is_read": True},
                        points=[hits[0].id]
                    )
        except Exception as qe:
            logger.warning(f"Qdrant is_read sync failed for {message_id}: {qe}")

        return jsonify({'status': 'ok'}), 200
    except Exception as e:
        logger.error(f"Error marking email {message_id} as read: {e}")
        return jsonify({'error': str(e)}), 500


# ── WO-GSYNC-8/9/10: Helper to sync Gmail labels → Qdrant ──────────────────
def _sync_labels_to_qdrant(message_id):
    """Fetch current labels from Gmail and update Qdrant payload."""
    try:
        client = get_qdrant_client()
        if not client:
            return
        service = get_gmail_service()
        msg = service.users().messages().get(
            userId='me', id=message_id, format='metadata',
            metadataHeaders=['']
        ).execute()
        label_ids = msg.get('labelIds', [])
        is_read = 'UNREAD' not in label_ids

        hits, _ = client.scroll(
            collection_name="emails",
            scroll_filter=models.Filter(
                must=[models.FieldCondition(
                    key="gmail_id",
                    match=models.MatchValue(value=message_id)
                )]
            ),
            limit=1, with_payload=False, with_vectors=False
        )
        if hits:
            client.set_payload(
                collection_name="emails",
                payload={"labels": label_ids, "is_read": is_read},
                points=[hits[0].id]
            )
    except Exception as e:
        logger.warning(f"Qdrant label sync failed for {message_id}: {e}")


# WO-GSYNC-8: Archive endpoint
@http_app.route('/archive/<message_id>', methods=['POST'])
def http_archive(message_id):
    """Archive email: remove INBOX label in Gmail + sync labels to Qdrant."""
    try:
        service = get_gmail_service()
        service.users().messages().modify(
            userId='me', id=message_id,
            body={'removeLabelIds': ['INBOX']}
        ).execute()
        _sync_labels_to_qdrant(message_id)
        notify_clients('mail_updated')
        return jsonify({'status': 'archived'}), 200
    except Exception as e:
        logger.error(f"Error archiving {message_id}: {e}")
        return jsonify({'error': str(e)}), 500


# WO-GSYNC-9: Star / Unstar endpoints
@http_app.route('/star/<message_id>', methods=['POST'])
def http_star(message_id):
    """Add STARRED label in Gmail + sync to Qdrant."""
    try:
        service = get_gmail_service()
        service.users().messages().modify(
            userId='me', id=message_id,
            body={'addLabelIds': ['STARRED']}
        ).execute()
        _sync_labels_to_qdrant(message_id)
        notify_clients('mail_updated')
        return jsonify({'status': 'starred'}), 200
    except Exception as e:
        logger.error(f"Error starring {message_id}: {e}")
        return jsonify({'error': str(e)}), 500


@http_app.route('/unstar/<message_id>', methods=['POST'])
def http_unstar(message_id):
    """Remove STARRED label in Gmail + sync to Qdrant."""
    try:
        service = get_gmail_service()
        service.users().messages().modify(
            userId='me', id=message_id,
            body={'removeLabelIds': ['STARRED']}
        ).execute()
        _sync_labels_to_qdrant(message_id)
        notify_clients('mail_updated')
        return jsonify({'status': 'unstarred'}), 200
    except Exception as e:
        logger.error(f"Error unstarring {message_id}: {e}")
        return jsonify({'error': str(e)}), 500


# WO-GSYNC-10: Trash endpoint
@http_app.route('/trash/<message_id>', methods=['POST'])
def http_trash(message_id):
    """Move email to trash in Gmail + sync labels to Qdrant."""
    try:
        service = get_gmail_service()
        service.users().messages().trash(userId='me', id=message_id).execute()
        _sync_labels_to_qdrant(message_id)
        notify_clients('mail_updated')
        return jsonify({'status': 'trashed'}), 200
    except Exception as e:
        logger.error(f"Error trashing {message_id}: {e}")
        return jsonify({'error': str(e)}), 500

# ── Gmail ↔ Qdrant read-status reconciliation ──────────────────────────
def _reconcile_read_status():
    """Sync Gmail read state → Qdrant is_read for all indexed emails.
    Scrolls ALL Qdrant emails once to build full map, then diffs with Gmail."""
    try:
        service = get_gmail_service()
        client = get_qdrant_client()
        if not service or not client:
            return

        # 1. Fetch ALL unread message IDs from Gmail INBOX
        gmail_unread_ids = set()
        page_token = None
        while True:
            resp = service.users().messages().list(
                userId='me', q='is:unread in:inbox',
                fields='messages/id,nextPageToken',
                pageToken=page_token, maxResults=500
            ).execute()
            for m in resp.get('messages', []):
                gmail_unread_ids.add(m['id'])
            page_token = resp.get('nextPageToken')
            if not page_token:
                break

        # 2. Scroll ALL Qdrant emails once → build full gmail_id → (point_id, is_read) map
        qdrant_map = {}  # gmail_id → (point_id, is_read)
        offset = None
        while True:
            hits, offset = client.scroll(
                collection_name="emails",
                limit=500, offset=offset,
                with_payload=["gmail_id", "is_read"], with_vectors=False
            )
            for h in hits:
                gid = h.payload.get("gmail_id")
                if gid:
                    qdrant_map[gid] = (h.id, h.payload.get("is_read", True))
            if not offset:
                break

        # 3. Diff both directions in a single pass
        to_mark_read = []   # Qdrant says unread, Gmail says read
        to_mark_unread = [] # Gmail says unread, Qdrant says read

        for gid, (pid, q_is_read) in qdrant_map.items():
            gmail_says_unread = gid in gmail_unread_ids
            if not q_is_read and not gmail_says_unread:
                # Qdrant: unread, Gmail: read → mark read
                to_mark_read.append(pid)
            elif q_is_read and gmail_says_unread:
                # Qdrant: read, Gmail: unread → mark unread
                to_mark_unread.append(pid)

        # 4. Batch update
        if to_mark_read:
            client.set_payload("emails", {"is_read": True}, to_mark_read)
        if to_mark_unread:
            client.set_payload("emails", {"is_read": False}, to_mark_unread)

        total = len(to_mark_read) + len(to_mark_unread)
        if total > 0:
            logger.info(f"[sync] Reconciled {total} emails "
                        f"({len(to_mark_read)} → read, "
                        f"{len(to_mark_unread)} → unread)")
    except Exception as e:
        logger.warning(f"[sync] Reconciliation failed: {e}")


def _sync_loop():
    """Background thread: reconcile Gmail ↔ Qdrant every 5 min."""
    _time.sleep(60)  # Initial delay: let services warm up
    while True:
        try:
            _reconcile_read_status()
        except Exception as e:
            logger.warning(f"[sync] Background cycle failed: {e}")
        _time.sleep(300)


@http_app.route('/unread-indexed-count', methods=['GET'])
def http_unread_indexed_count():
    """Return Gmail's official INBOX unread count (matches Gmail sidebar).
    Also triggers async Qdrant reconciliation to keep per-email state in sync."""
    # Fire async reconciliation (non-blocking) to sync per-email read state
    if flask_request.args.get('sync') == 'true':
        threading.Thread(target=_reconcile_read_status, daemon=True).start()
    try:
        # Use Gmail's own INBOX label unread count — matches Gmail sidebar exactly
        service = get_gmail_service()
        if not service:
            return jsonify({'error': 'Gmail unavailable'}), 503
        result = service.users().labels().get(userId='me', id='INBOX').execute()
        unread = result.get('messagesUnread', 0)
        return jsonify({'unread': unread}), 200
    except Exception as e:
        logger.error(f"Error fetching unread count from Gmail: {e}", exc_info=True)
        # Fallback to Qdrant count if Gmail API fails
        try:
            client = get_qdrant_client()
            if client:
                result = client.count(
                    collection_name="emails",
                    count_filter=models.Filter(
                        must=[models.FieldCondition(
                            key="is_read",
                            match=models.MatchValue(value=False)
                        )]
                    ),
                    exact=True
                )
                return jsonify({'unread': result.count}), 200
        except Exception:
            pass
        return jsonify({'error': str(e)}), 500

@http_app.route('/drafts', methods=['POST'])
def http_create_draft():
    """Create a new draft in Gmail (Dashboard Self Draft / Save to Drafts).
    Accepts JSON or multipart/form-data (with file attachments)."""
    try:
        if flask_request.content_type and 'multipart/form-data' in flask_request.content_type:
            to = flask_request.form.get('to', '')
            subject = flask_request.form.get('subject', '')
            body = flask_request.form.get('body', '')
            message_id = flask_request.form.get('message_id', '')
            files = flask_request.files.getlist('attachments')
        else:
            data = flask_request.get_json(force=True)
            to = data.get('to', '')
            subject = data.get('subject', '')
            body = data.get('body', '')
            message_id = data.get('message_id', '')
            files = []

        # WO-MAIL-ATT-1c: Workspace file paths (from file browser)
        attachment_paths = []
        if flask_request.content_type and 'multipart/form-data' in flask_request.content_type:
            raw = flask_request.form.get('attachment_paths', '')
        else:
            raw = data.get('attachment_paths', []) if 'data' in dir() else []
        if isinstance(raw, str) and raw:
            import json as _json
            attachment_paths = _json.loads(raw)
        elif isinstance(raw, list):
            attachment_paths = raw

        if not to or not body:
            return jsonify({'error': 'Missing required fields: to, body'}), 400

        if message_id:
            result = create_reply_draft(message_id=message_id, reply_text=body)
        else:
            message = _build_message_with_attachments(to, subject, body, files, attachment_paths)
            encoded_message = base64.urlsafe_b64encode(message.as_bytes()).decode()
            service = get_gmail_service()
            result = service.users().drafts().create(
                userId='me', body={'message': {'raw': encoded_message}}
            ).execute()
            notify_clients('drafts_updated')

        if 'error' in result:
            return jsonify(result), 400
        return jsonify(result), 201
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@http_app.route('/send', methods=['POST'])
def http_send_email():
    """Send an email directly (Dashboard Send Now button).
    Accepts JSON or multipart/form-data (with file attachments)."""
    try:
        if flask_request.content_type and 'multipart/form-data' in flask_request.content_type:
            to = flask_request.form.get('to', '')
            subject = flask_request.form.get('subject', '')
            body_text = flask_request.form.get('body', '')
            files = flask_request.files.getlist('attachments')
        else:
            data = flask_request.get_json(force=True)
            to = data.get('to', '')
            subject = data.get('subject', '')
            body_text = data.get('body', '')
            files = []

        # WO-MAIL-ATT-1c: Workspace file paths
        attachment_paths = []
        if flask_request.content_type and 'multipart/form-data' in flask_request.content_type:
            raw = flask_request.form.get('attachment_paths', '')
        else:
            raw = data.get('attachment_paths', []) if 'data' in dir() else []
        if isinstance(raw, str) and raw:
            import json as _json
            attachment_paths = _json.loads(raw)
        elif isinstance(raw, list):
            attachment_paths = raw

        if not to or not body_text:
            return jsonify({'error': 'Missing required fields: to, body'}), 400

        service = get_gmail_service()
        message = _build_message_with_attachments(to, subject, body_text, files, attachment_paths)
        encoded = base64.urlsafe_b64encode(message.as_bytes()).decode()

        result = service.users().messages().send(
            userId='me', body={'raw': encoded}
        ).execute()

        return jsonify({
            'status': 'sent',
            'message_id': result.get('id', ''),
            'thread_id': result.get('threadId', '')
        }), 200
    except Exception as e:
        logger.error(f"Error sending email: {e}")
        return jsonify({'error': str(e)}), 500

@http_app.route('/drafts', methods=['GET'])
def http_list_drafts():
    """List all drafts for Dashboard Draft Box."""
    try:
        drafts = list_drafts(max_results=20)
        return jsonify({'drafts': drafts}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@http_app.route('/drafts/<draft_id>', methods=['GET'])
def http_get_draft(draft_id):
    """Full draft content for review modal."""
    try:
        draft = get_draft(draft_id)
        return jsonify(draft), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@http_app.route('/drafts/<draft_id>/send', methods=['POST'])
def http_send_draft(draft_id):
    """Approve & Send a draft (Dashboard button)."""
    try:
        result = send_draft(draft_id)
        if 'error' in result:
            return jsonify(result), 400
        return jsonify(result), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@http_app.route('/drafts/<draft_id>', methods=['DELETE'])
def http_delete_draft(draft_id):
    """Discard a draft (Dashboard button)."""
    try:
        result = delete_draft(draft_id)
        return jsonify({'message': result}), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@http_app.route('/drafts/<draft_id>', methods=['PUT'])
def http_update_draft(draft_id):
    """Update a draft's To/Subject/Body (Dashboard inline edit)."""
    try:
        data = flask_request.get_json(force=True)
        to = data.get('to', '')
        subject = data.get('subject', '')
        body = data.get('body', '')
        
        if not to and not subject and not body:
            return jsonify({'error': 'At least one of to, subject, or body is required'}), 400
        
        result = update_draft(draft_id=draft_id, to=to, subject=subject, message_text=body)
        if 'error' in result:
            return jsonify(result), 400
        return jsonify(result), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@http_app.route('/auth/status', methods=['GET'])
def http_auth_status():
    """Auth state check for dashboard. Returns connected or unauthenticated + auth URL."""
    token_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'secrets', 'token.json')
    if not os.path.exists(token_path):
        token_path = '/app/secrets/token.json'

    try:
        if os.path.exists(token_path) and os.path.getsize(token_path) > 0:
            import json as _json
            with open(token_path) as f:
                token_data = _json.load(f)
            if token_data.get('token') or token_data.get('access_token'):
                # Try a quick credential validation
                try:
                    creds = Credentials.from_authorized_user_info(token_data)
                    if creds and (creds.valid or creds.refresh_token):
                        return jsonify({'status': 'connected'}), 200
                except Exception:
                    pass
        # Not authenticated — return auth URL via the workstation_auth relay if available
        auth_url = None
        try:
            from workstation_auth import TokenManager
            tm = TokenManager()
            auth_url = tm.get_auth_url()
        except Exception:
            pass
        return jsonify({'status': 'unauthenticated', 'auth_url': auth_url}), 200
    except Exception as e:
        logger.error(f"Auth status check failed: {e}")
        return jsonify({'status': 'error', 'error': str(e)}), 500

@http_app.route('/health', methods=['GET'])
def http_health():
    return jsonify({'status': 'healthy', 'service': 'gmail-mcp-http'}), 200

@http_app.route('/search', methods=['GET'])
def http_search_emails():
    """Semantic email search for dashboard search bar (WO-EMAIL-1)."""
    query = flask_request.args.get('q', '').strip()
    if not query:
        return jsonify({'error': "query parameter 'q' is required"}), 400

    limit = min(flask_request.args.get('limit', 10, type=int), 50)
    offset = flask_request.args.get('offset', 0, type=int)

    try:
        client = get_qdrant_client()
        if not client:
            return jsonify({'error': 'search unavailable: database connection failed'}), 500

        # Parse query for from:/subject: prefixes
        filters, remaining_text = _parse_search_query(query)

        if filters:
            # Prefix search: use ONLY payload filters (skip vector search)
            all_hits = _targeted_payload_search(client, filters, limit + offset)
            hits = all_hits[offset:offset + limit]
        else:
            # No prefix: hybrid vector + payload merge
            query_vector = get_embedding_via_http(query)
            if query_vector is None:
                return jsonify({'error': 'search unavailable: embedding generation failed'}), 500

            prefetch_list = [
                models.Prefetch(
                    query=query_vector,
                    using="dense",
                    limit=(limit + offset) * 3,
                ),
            ]
            sparse_vec = _get_bm25_sparse_vector(query)
            if sparse_vec is not None:
                prefetch_list.append(
                    models.Prefetch(
                        query=sparse_vec,
                        using="bm25",
                        limit=(limit + offset) * 3,
                    )
                )
            search_result = client.query_points(
                collection_name="emails",
                prefetch=prefetch_list,
                query=models.FusionQuery(fusion=models.Fusion.RRF),
                limit=limit + offset,
            )
            hits = search_result.points[offset:]

            # Merge payload fallback for plain text queries
            payload_hits = _payload_search(client, query, limit + offset)
            # Sort payload hits by recency (newest first)
            payload_hits.sort(key=lambda pt: pt.payload.get('date_epoch', 0), reverse=True)
            seen_ids = set()
            merged = []
            for pt in payload_hits:
                if pt.id not in seen_ids:
                    seen_ids.add(pt.id)
                    merged.append(pt)
            for hit in hits:
                if hit.id not in seen_ids:
                    seen_ids.add(hit.id)
                    merged.append(hit)
            hits = merged[:limit]

        results = []
        for hit in hits:
            p = hit.payload
            results.append({
                'id': p.get('gmail_id', p.get('message_id', str(hit.id))),
                'subject': p.get('subject', '(No Subject)'),
                'from': p.get('sender', 'Unknown'),
                'date': p.get('date', ''),
                'snippet': (p.get('snippet', p.get('body', '')) or '')[:200],
                'score': round(getattr(hit, 'score', 1.0), 4)
            })

        return jsonify({
            'results': results,
            'total': len(results),
            'limit': limit,
            'offset': offset
        })

    except Exception as e:
        logger.error(f"Search endpoint failed: {e}")
        return jsonify({'error': f'search unavailable: {str(e)}'}), 500

def start_http_server():
    """Start Flask HTTP server in a background thread."""
    logger.info(f"Starting Gmail HTTP API on port {HTTP_PORT}")
    http_app.run(host='0.0.0.0', port=HTTP_PORT, threaded=True)


if __name__ == "__main__":
    # Determine transport based on environment, default to stdio for Kilo Code compatibility
    transport = os.getenv("MCP_TRANSPORT", "stdio").lower()
    
    # Auto-detect Docker environment interaction
    if (os.path.exists("/.dockerenv") or os.getenv("DOCKER_CONTAINER")) and os.getenv("MCP_TRANSPORT") is None:
        transport = "stdio" 

    # Start HTTP server only in SSE mode (primary process).
    # In stdio mode (bridge-spawned), the primary SSE instance already owns port 8007.
    if transport == "sse":
        http_thread = threading.Thread(target=start_http_server, daemon=True)
        http_thread.start()
        # Start Gmail ↔ Qdrant read-status sync background thread
        sync_thread = threading.Thread(target=_sync_loop, daemon=True, name="gmail-qdrant-sync")
        sync_thread.start()
        # WO-MAIL-SYNC-7: Start background read-status reconciliation (every 5 min)
        _start_reconciliation_daemon()

    # Embedding model now served by centralized embedding-server (HTTP)
    # No local model to preload
    logger.info("Gmail MCP starting (embedding via centralized server)")

    if transport == "sse":
        mcp.run(transport="sse", host="0.0.0.0", port=8000)
    else:
        mcp.run(transport="stdio")
