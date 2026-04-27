# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
import os
import time
import schedule
import logging
import json
import base64
import requests
from datetime import datetime, timedelta
from email.utils import parsedate_to_datetime
from bs4 import BeautifulSoup
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from qdrant_client import QdrantClient
from qdrant_client.http import models
from fastembed import SparseTextEmbedding

import uuid

# BM25 sparse embedding model (tokenizer-only, ~1MB, no GPU needed)
try:
    bm25_model = SparseTextEmbedding(model_name="Qdrant/bm25")
    logging.info("BM25 sparse embedding model loaded")
except Exception as e:
    logging.warning(f"BM25 model failed to load: {e} — sparse search disabled")
    bm25_model = None

# Configuration
AUTH_MANAGER_URL = os.getenv('AUTH_MANAGER_URL', 'http://secrets-manager:9001/auth/token')
POLL_INTERVAL = int(os.getenv('POLL_INTERVAL', 30))  # WO-GSYNC-4: 30s with History API (was 300)
QDRANT_HOST = os.getenv('QDRANT_HOST', 'qdrant')
QDRANT_PORT = int(os.getenv('QDRANT_PORT', 6333))
COLLECTION_NAME = "emails"
EMBEDDING_BASE_URL = os.getenv("EMBEDDING_BASE_URL", "http://embedding-server:7997")
EMBEDDING_MODEL_ID = os.getenv("EMBEDDING_MODEL_ID", "sentence-transformers/paraphrase-multilingual-mpnet-base-v2")
VECTOR_SIZE = int(os.getenv('VECTOR_SIZE', 768))
ATTACHMENTS_DIR = os.getenv('ATTACHMENTS_DIR', '/data/attachments')
MAX_ATTACHMENT_SIZE_MB = int(os.getenv('MAX_ATTACHMENT_SIZE_MB', 25))
MAX_DEEP_SYNC_PAGES = int(os.getenv('MAX_DEEP_SYNC_PAGES', 100))  # 100 pages × 50 = 5,000 emails max
QDRANT_MIGRATE_SCHEMA = os.getenv('QDRANT_MIGRATE_SCHEMA', 'false').lower() == 'true'

# Setup Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('ingestor')



def get_gmail_service():
    """Authenticates and returns the Gmail API service using Auth Manager."""
    creds = None
    try:
        response = requests.get(AUTH_MANAGER_URL, timeout=10)
        if response.status_code == 200:
            token_data = response.json()
            if 'token' in token_data:
                creds = Credentials(token=token_data['token'])
            else:
                logger.error(f"Auth Manager missing token in response: {token_data}")
        else:
            logger.error(f"Auth Manager failed: {response.status_code} - {response.text}")
    except Exception as e:
        logger.error(f"Error contacting Auth Manager: {e}")

    if not creds:
        return None

    return build('gmail', 'v1', credentials=creds)

def _needs_hybrid_migration(client):
    """Check if existing 'emails' collection uses old anonymous vector schema."""
    try:
        info = client.get_collection(COLLECTION_NAME)
        config = info.config.params.vectors
        # Old schema: anonymous VectorParams (not a dict of named vectors)
        # New schema: dict with 'dense' key
        if isinstance(config, models.VectorParams):
            return True  # Anonymous single vector → needs migration
        if isinstance(config, dict) and 'dense' in config:
            return False  # Already migrated
        logger.warning(f"Collection '{COLLECTION_NAME}' has unexpected vector config type: {type(config)}. Skipping migration.")
        return False  # Unknown schema → safe default, do NOT delete
    except Exception:
        return False

def init_qdrant():
    """Initialize Qdrant collections with named vectors (dense + BM25 sparse)."""
    try:
        client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)
        
        # --- emails collection (hybrid: dense + BM25 sparse) ---
        if client.collection_exists(COLLECTION_NAME):
            if _needs_hybrid_migration(client):
                if QDRANT_MIGRATE_SCHEMA:
                    logger.warning(
                        f"QDRANT_MIGRATE_SCHEMA=true: Deleting collection '{COLLECTION_NAME}' "
                        f"to recreate with named vectors (dense + bm25). "
                        f"Data will be re-ingested from Gmail API."
                    )
                    client.delete_collection(COLLECTION_NAME)
                else:
                    logger.error(
                        f"Collection '{COLLECTION_NAME}' uses old anonymous vector schema "
                        f"and needs migration to named vectors (dense + bm25). "
                        f"BM25 keyword search will be UNAVAILABLE until migrated. "
                        f"To migrate, set QDRANT_MIGRATE_SCHEMA=true and restart the ingestor. "
                        f"WARNING: This will delete the collection and re-ingest from Gmail API."
                    )
        
        if not client.collection_exists(COLLECTION_NAME):
            logger.info(f"Creating collection '{COLLECTION_NAME}' with hybrid vectors (dense + bm25)...")
            client.create_collection(
                collection_name=COLLECTION_NAME,
                vectors_config={
                    "dense": models.VectorParams(size=VECTOR_SIZE, distance=models.Distance.COSINE),
                },
                sparse_vectors_config={
                    "bm25": models.SparseVectorParams(modifier=models.Modifier.IDF),
                },
            )

        # Ensure payload index on date_epoch for order_by sorting
        try:
            collection_info = client.get_collection(COLLECTION_NAME)
            indexed_fields = set(collection_info.payload_schema.keys()) if collection_info.payload_schema else set()
            if 'date_epoch' not in indexed_fields:
                logger.info("Creating payload index on 'date_epoch' for date-sorted scroll...")
                client.create_payload_index(
                    collection_name=COLLECTION_NAME,
                    field_name='date_epoch',
                    field_schema=models.PayloadSchemaType.INTEGER,
                )
        except Exception as e:
            logger.warning(f"Could not create date_epoch index (non-fatal): {e}")

        # WO-SEARCH-1: Text indexes on sender + subject + to (prefix tokenizer for type-ahead)
        try:
            schema = collection_info.payload_schema or {}
            for field in ('sender', 'subject', 'to'):
                # Recreate with prefix tokenizer if existing index uses word tokenizer
                if field in schema:
                    existing = schema[field]
                    params = getattr(existing, 'params', None)
                    tokenizer = getattr(params, 'tokenizer', None) if params else None
                    if tokenizer and str(tokenizer) != str(models.TokenizerType.PREFIX):
                        logger.info(f"Upgrading '{field}' index to prefix tokenizer...")
                        client.delete_payload_index(COLLECTION_NAME, field)
                        del schema[field]
                        indexed_fields.discard(field)
                if field not in schema:
                    logger.info(f"Creating prefix text index on '{field}'...")
                    client.create_payload_index(
                        collection_name=COLLECTION_NAME,
                        field_name=field,
                        field_schema=models.TextIndexParams(
                            type="text",
                            tokenizer=models.TokenizerType.PREFIX,
                            min_token_len=2,
                            max_token_len=20,
                            lowercase=True,
                        ),
                    )
        except Exception as e:
            logger.warning(f"Could not create text indexes (non-fatal): {e}")

        # WO-GSYNC-5: Keyword index on 'labels' for label-based filtering
        try:
            if 'labels' not in indexed_fields:
                logger.info("Creating keyword index on 'labels' for label filtering...")
                client.create_payload_index(
                    collection_name=COLLECTION_NAME,
                    field_name='labels',
                    field_schema=models.PayloadSchemaType.KEYWORD,
                )
        except Exception as e:
            logger.warning(f"Could not create labels index (non-fatal): {e}")
            
        # --- calendar collection (dense only, no BM25 needed) ---
        if not client.collection_exists("calendar"):
            logger.info(f"Creating collection 'calendar'...")
            client.create_collection(
                collection_name="calendar",
                vectors_config=models.VectorParams(size=VECTOR_SIZE, distance=models.Distance.COSINE),
            )
            
        # Ensure payload index on start_epoch for calendar order_by sorting
        try:
            cal_info = client.get_collection("calendar")
            cal_fields = set(cal_info.payload_schema.keys()) if cal_info.payload_schema else set()
            if 'start_epoch' not in cal_fields:
                logger.info("Creating payload index on 'start_epoch' for calendar...")
                client.create_payload_index(
                    collection_name="calendar",
                    field_name='start_epoch',
                    field_schema=models.PayloadSchemaType.INTEGER,
                )
        except Exception as e:
            logger.warning(f"Could not create start_epoch index (non-fatal): {e}")

        return client
    except Exception as e:
        logger.error(f"Failed to connect to Qdrant: {e}")
        return None

def get_embedding(text):
    """Generate embedding via centralized embedding server (HTTP)."""
    try:
        response = requests.post(
            f"{EMBEDDING_BASE_URL}/v1/embeddings",
            json={"input": [text], "model": EMBEDDING_MODEL_ID},
            timeout=300
        )
        response.raise_for_status()
        return response.json()["data"][0]["embedding"]
    except Exception as e:
        logger.error(f"Embedding server call failed: {e}")
        return None

def parse_email_body(payload):
    """Extract plain text from email payload."""
    body = ""
    if 'parts' in payload:
        for part in payload['parts']:
            if part['mimeType'] == 'text/plain':
                data = part['body'].get('data')
                if data:
                    body += base64.urlsafe_b64decode(data).decode()
    elif payload.get('body', {}).get('data'):
         body = base64.urlsafe_b64decode(payload['body']['data']).decode()
    
    # Clean HTML if present (simple fallback)
    if body:
        soup = BeautifulSoup(body, 'html.parser')
        return soup.get_text()
    return ""

def extract_attachments(service, msg_id, payload, output_dir):
    """
    Recursively walk MIME parts, download attachments via Gmail API,
    save to output_dir/{YYYY}/{MM}/{email_id}/.

    Returns list of attachment metadata dicts.
    Standalone function — no global state, no embedding model, no Qdrant client.
    """
    attachments_meta = []
    max_size_bytes = MAX_ATTACHMENT_SIZE_MB * 1024 * 1024

    def _walk_parts(parts):
        for part in parts:
            # Recurse into nested multipart
            if 'parts' in part:
                _walk_parts(part['parts'])
                continue

            filename = part.get('filename')
            if not filename:
                continue

            mime_type = part.get('mimeType', 'application/octet-stream')
            body = part.get('body', {})
            att_id = body.get('attachmentId')
            size = body.get('size', 0)

            # Skip oversized attachments
            if size > max_size_bytes:
                logger.warning(
                    f"Skipping oversized attachment '{filename}' "
                    f"({size / 1024 / 1024:.1f}MB > {MAX_ATTACHMENT_SIZE_MB}MB) "
                    f"in email {msg_id}"
                )
                continue

            if not att_id:
                continue

            try:
                att = service.users().messages().attachments().get(
                    userId='me', messageId=msg_id, id=att_id
                ).execute()
                file_data = base64.urlsafe_b64decode(att['data'])
            except Exception as e:
                logger.error(f"Failed to download attachment '{filename}' from {msg_id}: {e}")
                continue

            # Build date-organized path: {output_dir}/{YYYY}/{MM}/{msg_id}/{filename}
            now = datetime.now()
            save_dir = os.path.join(
                output_dir,
                now.strftime('%Y'),
                now.strftime('%m'),
                msg_id
            )
            os.makedirs(save_dir, exist_ok=True)
            file_path = os.path.join(save_dir, filename)

            try:
                with open(file_path, 'wb') as f:
                    f.write(file_data)
            except Exception as e:
                logger.error(f"Failed to save attachment '{filename}' to {file_path}: {e}")
                continue

            attachments_meta.append({
                'filename': filename,
                'content_type': mime_type,
                'size_bytes': len(file_data),
                'path': file_path
            })
            logger.info(f"Saved attachment: {filename} ({len(file_data)} bytes)")

    parts = payload.get('parts', [])
    if parts:
        _walk_parts(parts)

    return attachments_meta

# ── WO-GSYNC-2: historyId Storage (Qdrant sentinel point) ────────────
HISTORY_SENTINEL_ID = "00000000-0000-0000-0000-000000000001"

def _get_stored_history_id(q_client):
    """Read the last stored historyId from Qdrant sentinel point."""
    try:
        points = q_client.retrieve(
            collection_name=COLLECTION_NAME,
            ids=[HISTORY_SENTINEL_ID],
            with_payload=True,
            with_vectors=False
        )
        if points and points[0].payload:
            return points[0].payload.get('history_id')
    except Exception as e:
        logger.warning(f"Failed to read stored historyId: {e}")
    return None

def _store_history_id(q_client, history_id: str):
    """Persist the latest historyId into a Qdrant sentinel point."""
    try:
        q_client.upsert(
            collection_name=COLLECTION_NAME,
            points=[
                models.PointStruct(
                    id=HISTORY_SENTINEL_ID,
                    vector={"dense": [0.0] * VECTOR_SIZE},  # dummy vector
                    payload={
                        "type": "_sync_metadata",
                        "history_id": history_id,
                        "updated_at": datetime.now().isoformat()
                    }
                )
            ]
        )
        logger.info(f"Stored historyId: {history_id}")
    except Exception as e:
        logger.error(f"Failed to store historyId: {e}")


def _ingest_single_message(service, q_client, msg_id, label_ids=None):
    """Fetch, embed, and upsert a single email message into Qdrant.
    Shared by both full-sync and history-sync paths.
    Returns True if successfully ingested, False otherwise."""
    try:
        details = service.users().messages().get(userId='me', id=msg_id).execute()
    except Exception as e:
        logger.error(f"Failed to fetch message {msg_id}: {e}")
        return False

    snippet = details.get('snippet', '')
    if label_ids is None:
        label_ids = details.get('labelIds', [])
    is_read = 'UNREAD' not in label_ids
    payload_data = details.get('payload', {})
    headers = payload_data.get('headers', [])

    subject = next((h['value'] for h in headers if h['name'] == 'Subject'), '(No Subject)')
    sender = next((h['value'] for h in headers if h['name'] == 'From'), 'Unknown')
    to_addr = next((h['value'] for h in headers if h['name'] == 'To'), '')
    date = next((h['value'] for h in headers if h['name'] == 'Date'), '')

    date_epoch = 0
    try:
        if date:
            date_epoch = int(parsedate_to_datetime(date).timestamp())
    except Exception:
        date_epoch = 0

    body_text = parse_email_body(payload_data)
    attachments_meta = extract_attachments(service, msg_id, payload_data, ATTACHMENTS_DIR)
    full_text = f"Subject: {subject}\nFrom: {sender}\nDate: {date}\n\n{body_text}"

    dense_vector = get_embedding(full_text)
    if dense_vector is None:
        return False

    sparse_vector = None
    if bm25_model is not None:
        try:
            sparse_results = list(bm25_model.embed([full_text]))
            if sparse_results:
                sr = sparse_results[0]
                sparse_vector = models.SparseVector(
                    indices=sr.indices.tolist(),
                    values=sr.values.tolist(),
                )
        except Exception as e:
            logger.warning(f"BM25 embedding failed for {msg_id}: {e}")

    point_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, msg_id))
    vectors_dict = {"dense": dense_vector}
    if sparse_vector is not None:
        vectors_dict["bm25"] = sparse_vector

    q_client.upsert(
        collection_name=COLLECTION_NAME,
        points=[
            models.PointStruct(
                id=point_id,
                vector=vectors_dict,
                payload={
                    "gmail_id": msg_id,
                    "subject": subject,
                    "sender": sender,
                    "to": to_addr,
                    "date": date,
                    "date_epoch": date_epoch,
                    "snippet": snippet,
                    "body": body_text[:5000] if body_text else "",
                    "type": "email",
                    "attachments": attachments_meta,
                    "has_attachments": len(attachments_meta) > 0,
                    "is_read": is_read,
                    "labels": label_ids,
                    "ingested_at": datetime.now().isoformat()
                }
            )
        ]
    )
    logger.info(f"Indexed email: {subject[:30]}...")
    return True


def _update_label_payload(q_client, msg_id, label_ids):
    """Update only the labels/is_read fields on an existing Qdrant point."""
    point_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, msg_id))
    try:
        q_client.set_payload(
            collection_name=COLLECTION_NAME,
            payload={
                "is_read": 'UNREAD' not in label_ids,
                "labels": label_ids
            },
            points=[point_id]
        )
    except Exception as e:
        logger.warning(f"Failed to update labels for {msg_id}: {e}")


def sync_via_history(service, q_client, last_history_id):
    """WO-GSYNC-2: Delta sync using Gmail History API.
    Returns (emails_processed, new_history_id).
    Raises googleapiclient.errors.HttpError with 404 if historyId expired."""
    from googleapiclient.errors import HttpError

    emails_processed = 0
    labels_updated = 0
    page_token = None

    while True:
        kwargs = {
            'userId': 'me',
            'startHistoryId': last_history_id,
            'historyTypes': ['messageAdded', 'labelAdded', 'labelRemoved']
        }
        if page_token:
            kwargs['pageToken'] = page_token

        response = service.users().history().list(**kwargs).execute()
        new_history_id = response.get('historyId', last_history_id)
        records = response.get('history', [])

        for record in records:
            # New messages
            for added in record.get('messagesAdded', []):
                msg = added.get('message', {})
                msg_id = msg.get('id')
                if not msg_id:
                    continue
                # Check if already indexed
                point_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, msg_id))
                existing = q_client.retrieve(
                    collection_name=COLLECTION_NAME,
                    ids=[point_id],
                    with_payload=False,
                    with_vectors=False
                )
                if existing:
                    continue  # Already indexed
                if _ingest_single_message(service, q_client, msg_id):
                    emails_processed += 1
                    time.sleep(0.5)

            # Label changes (read/unread, archive, star, etc.)
            for label_event in record.get('labelsAdded', []) + record.get('labelsRemoved', []):
                msg = label_event.get('message', {})
                msg_id = msg.get('id')
                label_ids = msg.get('labelIds', [])
                if msg_id and label_ids:
                    _update_label_payload(q_client, msg_id, label_ids)
                    labels_updated += 1

        page_token = response.get('nextPageToken')
        if not page_token:
            break

    logger.info(f"Δ sync: {emails_processed} new emails, {labels_updated} label changes")
    return emails_processed, new_history_id


def process_new_emails(custom_batch_size=None, deep_sync=False):
    """
    Main logic to fetch and process new emails.
    
    Args:
        custom_batch_size (int): Override BATCH_SIZE env var.
        deep_sync (bool): If True, paginate through history until 100 pages or early stop.
                          If False, fetch only the first page (scheduled poll).
    """
    logger.info(f"Starting ingestion cycle (deep_sync={deep_sync})...")
    
    # connect services
    service = get_gmail_service()
    q_client = init_qdrant()
    
    if not service or not q_client:
        logger.error("Service connection failed. Skipping cycle.")
        return 0

    # ── WO-GSYNC-2: Try History API delta sync first ──
    stored_history_id = _get_stored_history_id(q_client)
    if stored_history_id and not deep_sync:
        try:
            from googleapiclient.errors import HttpError
            count, new_hid = sync_via_history(service, q_client, stored_history_id)
            _store_history_id(q_client, new_hid)
            return count
        except Exception as e:
            if '404' in str(e) or 'notFound' in str(e):
                logger.warning(f"historyId {stored_history_id} expired (404). Falling back to full sync.")
                # Fall through to full sync below
            else:
                logger.error(f"History sync failed: {e}. Falling back to full sync.")
    # ── End WO-GSYNC-2 fast path ──

    total_ingested = 0
    page_token = None
    page_count = 0
    max_pages = MAX_DEEP_SYNC_PAGES if deep_sync else 1

    try:
        while page_count < max_pages:
            page_count += 1
            
            # 1. List messages
            if custom_batch_size is not None:
                 batch_size = int(custom_batch_size)
            else:
                 batch_size = int(os.getenv('BATCH_SIZE', 50))
                 
            list_args = {'userId': 'me', 'maxResults': batch_size}
            if page_token:
                list_args['pageToken'] = page_token

            results = service.users().messages().list(**list_args).execute()
            messages = results.get('messages', [])
            next_page_token = results.get('nextPageToken')
            
            logger.info(f"Page {page_count}: Found {len(messages)} messages to process.")
            
            if not messages:
                break

            # Deduplication Step
            skipped_count = 0
            messages_to_process = []
            
            try:
                # 1. Compute Point IDs for all messages
                # Map msg_id -> point_id
                id_map = {m['id']: str(uuid.uuid5(uuid.NAMESPACE_DNS, m['id'])) for m in messages}
                point_ids = list(id_map.values())
                
                # 2. Batch Retrieve from Qdrant (Existence Check)
                # We don't need payload or vectors, just ID confirmation
                existing_points = q_client.retrieve(
                    collection_name=COLLECTION_NAME,
                    ids=point_ids,
                    with_payload=False,
                    with_vectors=False
                )
                
                existing_point_ids = {point.id for point in existing_points}
                
                # 3. Filter Messages
                for msg in messages:
                    p_id = id_map[msg['id']]
                    if p_id in existing_point_ids:
                        skipped_count += 1
                        # logger.debug(f"Skipping duplicate email: {msg['id']}")
                    else:
                        messages_to_process.append(msg)
                
                if skipped_count > 0:
                    logger.info(f"Deduplication: Found {len(messages)} total. Skipping {skipped_count} existing. Processing {len(messages_to_process)} new.")
                
                messages = messages_to_process
                
            except Exception as e:
                logger.error(f"Deduplication check failed: {e}. Proceeding with all messages.")
                # Fallback: process all if check fails
            
            # EARLY STOP CHECK
            # If we fetched a full batch and ALL were duplicates:
            # - Normal poll (deep_sync=False): stop immediately — we're caught up
            # - Deep sync (deep_sync=True): keep going — older pages may have unindexed emails
            if skipped_count > 0 and len(messages) == 0:
                if not deep_sync:
                    logger.info("All messages in this page are duplicates. Stopping pagination (Caught Up).")
                    break
                else:
                    logger.info(f"Page {page_count}: all duplicates, continuing deep sync to find older emails...")
            
            for msg in messages:
                msg_id = msg['id']
                
                # Fetch full message
                try:
                    details = service.users().messages().get(userId='me', id=msg_id).execute()
                except Exception as e:
                    logger.error(f"Failed to fetch message {msg_id}: {e}")
                    continue

                snippet = details.get('snippet', '')
                label_ids = details.get('labelIds', [])
                is_read = 'UNREAD' not in label_ids
                # WO-GSYNC-2: Capture historyId from latest message for delta sync
                msg_history_id = details.get('historyId')
                payload = details.get('payload', {})
                headers = payload.get('headers', [])
                
                subject = next((h['value'] for h in headers if h['name'] == 'Subject'), '(No Subject)')
                sender = next((h['value'] for h in headers if h['name'] == 'From'), 'Unknown')
                to_addr = next((h['value'] for h in headers if h['name'] == 'To'), '')
                date = next((h['value'] for h in headers if h['name'] == 'Date'), '')

                # Parse RFC 2822 date to epoch for Qdrant order_by sorting
                date_epoch = 0
                try:
                    if date:
                        date_epoch = int(parsedate_to_datetime(date).timestamp())
                except Exception:
                    date_epoch = 0
                
                body_text = parse_email_body(payload)
                # Extract attachments
                attachments_meta = extract_attachments(service, msg_id, payload, ATTACHMENTS_DIR)
                # Embedding Content: Include headers for context
                full_text = f"Subject: {subject}\nFrom: {sender}\nDate: {date}\n\n{body_text}"
                
                # 2a. Dense embedding (semantic)
                dense_vector = get_embedding(full_text)
                if dense_vector is None:
                    continue

                # 2b. BM25 sparse embedding (keyword)
                sparse_vector = None
                if bm25_model is not None:
                    try:
                        sparse_results = list(bm25_model.embed([full_text]))
                        if sparse_results:
                            sr = sparse_results[0]
                            sparse_vector = models.SparseVector(
                                indices=sr.indices.tolist(),
                                values=sr.values.tolist(),
                            )
                    except Exception as e:
                        logger.warning(f"BM25 embedding failed for {msg_id}: {e}")

                # 3. Store in Qdrant (named vectors: dense + bm25)
                point_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, msg_id))

                vectors_dict = {"dense": dense_vector}
                if sparse_vector is not None:
                    vectors_dict["bm25"] = sparse_vector

                q_client.upsert(
                    collection_name=COLLECTION_NAME,
                    points=[
                        models.PointStruct(
                            id=point_id,
                            vector=vectors_dict,
                            payload={
                                "gmail_id": msg_id,
                                "subject": subject,
                                "sender": sender,
                                "to": to_addr,
                                "date": date,
                                "date_epoch": date_epoch,
                                "snippet": snippet,
                                "body": body_text[:5000] if body_text else "",
                                "type": "email",
                                "attachments": attachments_meta,
                                "has_attachments": len(attachments_meta) > 0,
                                "is_read": is_read,
                                "labels": label_ids,
                                "ingested_at": datetime.now().isoformat()
                            }
                        )
                    ]
                )
                logger.info(f"Indexed email: {subject[:30]}...")
                total_ingested += 1
                
                # Rate limiting not strictly needed for local FastEmbed, 
                # but good api citizenship for Gmail
                time.sleep(0.5)  # WO-MAIL-UX-4: was 0.1 — increased to reduce search timeout during heavy ingestion

            # Prepare for next page
            if deep_sync and next_page_token:
                page_token = next_page_token
            else:
                break

        # WO-GSYNC-2: After full sync, store latest historyId for future delta syncs
        try:
            profile = service.users().getProfile(userId='me').execute()
            latest_hid = profile.get('historyId')
            if latest_hid:
                _store_history_id(q_client, latest_hid)
        except Exception as e:
            logger.warning(f"Failed to store historyId after full sync: {e}")

        return total_ingested

    except Exception as e:
        logger.error(f"Error processing emails: {e}")
        return total_ingested


def get_calendar_service():
    """Authenticates and returns the Calendar API service using Auth Manager."""
    creds = None
    try:
        response = requests.get(AUTH_MANAGER_URL, timeout=10)
        if response.status_code == 200:
            token_data = response.json()
            if 'token' in token_data:
                creds = Credentials(token=token_data['token'])
            else:
                logger.error(f"Auth Manager missing token in response: {token_data}")
        else:
            logger.error(f"Auth Manager failed: {response.status_code} - {response.text}")
    except Exception as e:
        logger.error(f"Error contacting Auth Manager: {e}")

    if not creds:
        return None

    return build('calendar', 'v3', credentials=creds)

# ── WO-CSYNC-1: syncToken Storage (Qdrant sentinel points per calendar) ─────
CAL_SYNC_SENTINEL_PREFIX = "cal-sync-"

def _get_cal_sync_token(q_client, cal_id):
    """Read stored syncToken for a specific calendar."""
    sentinel_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, CAL_SYNC_SENTINEL_PREFIX + cal_id))
    try:
        points = q_client.retrieve(
            collection_name="calendar",
            ids=[sentinel_id],
            with_payload=True,
            with_vectors=False
        )
        if points and points[0].payload:
            return points[0].payload.get('sync_token')
    except Exception as e:
        logger.warning(f"Failed to read syncToken for calendar '{cal_id}': {e}")
    return None

def _store_cal_sync_token(q_client, cal_id, sync_token):
    """Persist syncToken for a specific calendar."""
    sentinel_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, CAL_SYNC_SENTINEL_PREFIX + cal_id))
    try:
        q_client.upsert(
            collection_name="calendar",
            points=[
                models.PointStruct(
                    id=sentinel_id,
                    vector=[0.0] * VECTOR_SIZE,  # dummy vector
                    payload={
                        "type": "_sync_metadata",
                        "calendar_id": cal_id,
                        "sync_token": sync_token,
                        "updated_at": datetime.now().isoformat()
                    }
                )
            ]
        )
        logger.info(f"Stored syncToken for calendar '{cal_id}'")
    except Exception as e:
        logger.error(f"Failed to store syncToken for '{cal_id}': {e}")


def sync_calendar_incremental(service, q_client, cal_id, cal_name, sync_token, account_email=''):
    """WO-CSYNC-1/2: Incremental calendar sync using syncToken.
    Returns (events_processed, new_sync_token).
    Raises HttpError with 410 if syncToken expired."""
    events_processed = 0
    events_deleted = 0
    page_token = None
    new_sync_token = sync_token

    while True:
        kwargs = {'calendarId': cal_id, 'syncToken': sync_token}
        if page_token:
            kwargs['pageToken'] = page_token
            del kwargs['syncToken']  # Can't use both

        response = service.events().list(**kwargs).execute()
        items = response.get('items', [])

        for event in items:
            evt_id = event.get('id', '')
            evt_status = event.get('status', 'confirmed')

            # WO-CSYNC-2: Handle cancelled events — delete from Qdrant
            if evt_status == 'cancelled':
                point_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, evt_id))
                try:
                    q_client.delete(
                        collection_name="calendar",
                        points_selector=models.PointIdsList(points=[point_id])
                    )
                    events_deleted += 1
                    logger.info(f"Deleted cancelled event: {evt_id}")
                except Exception as e:
                    logger.warning(f"Failed to delete cancelled event {evt_id}: {e}")
                continue

            # Upsert updated/new event
            summary = event.get('summary', 'No Title')
            description = event.get('description', '')
            start = event.get('start', {}).get('dateTime', event.get('start', {}).get('date', ''))
            end = event.get('end', {}).get('dateTime', event.get('end', {}).get('date', ''))

            start_epoch = 0
            try:
                if start:
                    if len(start) == 10:
                        start_epoch = int(datetime.strptime(start, '%Y-%m-%d').timestamp())
                    else:
                        # Python <3.11 fromisoformat() doesn't handle 'Z' suffix
                        start_iso = start.replace('Z', '+00:00') if start.endswith('Z') else start
                        start_epoch = int(datetime.fromisoformat(start_iso).timestamp())
            except Exception:
                start_epoch = 0

            location = event.get('location', '')
            attendees_raw = event.get('attendees', [])
            attendees = [a.get('email', '') for a in attendees_raw]
            attendee_status = {a.get('email', ''): a.get('responseStatus', 'needsAction') for a in attendees_raw}
            hangout_link = event.get('hangoutLink', '')
            html_link = event.get('htmlLink', '')
            status = event.get('status', 'confirmed')
            organizer = event.get('organizer', {}).get('email', '')

            attendee_str = ', '.join(attendees) if attendees else ''
            full_text = f"Event: {summary}\nStart: {start}\nEnd: {end}"
            if location:
                full_text += f"\nLocation: {location}"
            if attendee_str:
                full_text += f"\nAttendees: {attendee_str}"
            if description:
                full_text += f"\nDescription: {description}"

            vector = get_embedding(full_text)
            if vector is None:
                continue

            point_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, evt_id))
            q_client.upsert(
                collection_name="calendar",
                points=[
                    models.PointStruct(
                        id=point_id,
                        vector=vector,
                        payload={
                            "calendar_id": evt_id,
                            "calendar_name": cal_name,
                            "google_calendar_id": cal_id,
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
                            "ingested_at": datetime.now().isoformat()
                        }
                    )
                ]
            )
            events_processed += 1

        page_token = response.get('nextPageToken')
        if not page_token:
            new_sync_token = response.get('nextSyncToken', sync_token)
            break

    logger.info(f"Δ cal sync '{cal_name}': {events_processed} updated, {events_deleted} cancelled")
    return events_processed, new_sync_token


def process_new_events():
    """Main logic to fetch and process new calendar events."""
    logger.info("Starting calendar ingestion cycle...")
    
    # connect services
    service = get_calendar_service()
    q_client = init_qdrant()
    
    if not service or not q_client:
        logger.error("Service connection failed. Skipping calendar cycle.")
        return 0

    try:
        # Resolve account email once for RSVP identification (WO-CAL-RSVP-1)
        try:
            account_email = service.calendars().get(calendarId='primary').execute().get('id', '')
        except Exception:
            account_email = ''

        # FIX-4: Fetch ALL subscribed calendars (family, work, shared, etc.)
        calendar_ids = []
        try:
            cal_list = service.calendarList().list().execute()
            for cal_entry in cal_list.get('items', []):
                cal_id = cal_entry.get('id', '')
                cal_summary = cal_entry.get('summary', cal_entry.get('summaryOverride', ''))
                if cal_id:
                    calendar_ids.append((cal_id, cal_summary))
            logger.info(f"Found {len(calendar_ids)} calendars: {[c[1] for c in calendar_ids]}")
        except Exception as e:
            logger.warning(f"calendarList.list() failed, falling back to primary: {e}")
            calendar_ids = [('primary', 'Primary')]

        # ── WO-CSYNC-1: Try syncToken incremental sync per calendar ──
        total_incremental = 0
        all_have_tokens = True
        for cal_id, cal_name in calendar_ids:
            stored_token = _get_cal_sync_token(q_client, cal_id)
            if not stored_token:
                all_have_tokens = False
                break  # Need full sync to seed tokens

        if all_have_tokens:
            try:
                for cal_id, cal_name in calendar_ids:
                    stored_token = _get_cal_sync_token(q_client, cal_id)
                    count, new_token = sync_calendar_incremental(
                        service, q_client, cal_id, cal_name, stored_token, account_email
                    )
                    _store_cal_sync_token(q_client, cal_id, new_token)
                    total_incremental += count
                logger.info(f"Δ cal sync total: {total_incremental} events across {len(calendar_ids)} calendars")
                return total_incremental
            except Exception as e:
                if '410' in str(e) or 'fullSyncRequired' in str(e).lower():
                    logger.warning(f"syncToken expired (410). Falling back to full sync.")
                else:
                    logger.error(f"Incremental cal sync failed: {e}. Falling back to full sync.")
        # ── End WO-CSYNC-1 fast path ──

        # Full sync: List events from each calendar (Past 1 year to Future 1 year)
        now = datetime.utcnow()
        time_min = (now - timedelta(days=365)).isoformat() + 'Z'
        time_max = (now + timedelta(days=365)).isoformat() + 'Z'
        
        events = []
        for cal_id, cal_name in calendar_ids:
            try:
                cal_events = []
                page_token = None
                # WO-CSYNC-1: Request syncToken from full sync for future incremental use
                full_sync_token = None
                while True:
                    events_result = service.events().list(
                        calendarId=cal_id, 
                        timeMin=time_min, 
                        timeMax=time_max, 
                        singleEvents=True,
                        orderBy='startTime',
                        pageToken=page_token
                    ).execute()
                    
                    cal_events.extend(events_result.get('items', []))
                    page_token = events_result.get('nextPageToken')
                    if not page_token:
                        full_sync_token = events_result.get('nextSyncToken')
                        break
                # Store syncToken for future incremental syncs
                if full_sync_token:
                    _store_cal_sync_token(q_client, cal_id, full_sync_token)
                # Tag each event with its calendar name
                for evt in cal_events:
                    evt['_calendar_name'] = cal_name
                    evt['_calendar_id'] = cal_id
                events.extend(cal_events)
                logger.info(f"Calendar '{cal_name}': {len(cal_events)} events")
            except Exception as e:
                logger.warning(f"Failed to fetch events from calendar '{cal_name}' ({cal_id}): {e}")
        
        logger.info(f"Found {len(events)} total events across {len(calendar_ids)} calendars.")

        for event in events:
            evt_id = event['id']
            summary = event.get('summary', 'No Title')
            description = event.get('description', '')
            
            start = event.get('start', {}).get('dateTime', event.get('start', {}).get('date'))
            end = event.get('end', {}).get('dateTime', event.get('end', {}).get('date', ''))
            
            # Parse start date to epoch for Qdrant order_by sorting
            start_epoch = 0
            try:
                if start:
                    if len(start) == 10:  # YYYY-MM-DD
                        start_epoch = int(datetime.strptime(start, '%Y-%m-%d').timestamp())
                    else:
                        # Python <3.11 fromisoformat() doesn't handle 'Z' suffix
                        start_iso = start.replace('Z', '+00:00') if start.endswith('Z') else start
                        start_epoch = int(datetime.fromisoformat(start_iso).timestamp())
            except Exception:
                start_epoch = 0
                
            location = event.get('location', '')
            attendees_raw = event.get('attendees', [])
            attendees = [a.get('email', '') for a in attendees_raw]
            attendee_status = {a.get('email', ''): a.get('responseStatus', 'needsAction') for a in attendees_raw}
            hangout_link = event.get('hangoutLink', '')
            html_link = event.get('htmlLink', '')
            status = event.get('status', 'confirmed')
            organizer = event.get('organizer', {}).get('email', '')
            
            # Embedding Content — include location + attendees for semantic search
            attendee_str = ', '.join(attendees) if attendees else ''
            full_text = f"Event: {summary}\nStart: {start}\nEnd: {end}"
            if location:
                full_text += f"\nLocation: {location}"
            if attendee_str:
                full_text += f"\nAttendees: {attendee_str}"
            if description:
                full_text += f"\nDescription: {description}"
            
            # 2. Embed
            vector = get_embedding(full_text)
            if vector is None:
                continue

            # 3. Store in Qdrant
            point_id = str(uuid.uuid5(uuid.NAMESPACE_DNS, evt_id))

            q_client.upsert(
                collection_name="calendar",
                points=[
                    models.PointStruct(
                        id=point_id,
                        vector=vector,
                        payload={
                            "calendar_id": evt_id,
                            "calendar_name": event.get('_calendar_name', ''),
                            "google_calendar_id": event.get('_calendar_id', 'primary'),
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
                            "ingested_at": datetime.now().isoformat()
                        }
                    )
                ]
            )
            logger.info(f"Indexed event: {summary[:30]}...")
            
        return len(events)

    except Exception as e:
        logger.error(f"Error processing events: {e}")
        return 0

import threading
from flask import Flask, request, jsonify
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from werkzeug.middleware.proxy_fix import ProxyFix

app = Flask(__name__)
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_port=1)

_redis_password = os.environ.get('REDIS_PASSWORD')
if not _redis_password:
    raise RuntimeError("REDIS_PASSWORD environment variable is required but not set")
redis_url = f"redis://:{_redis_password}@{os.environ.get('REDIS_HOST', 'redis')}:{os.environ.get('REDIS_PORT', 6379)}"

limiter = Limiter(
    get_remote_address,
    app=app,
    storage_uri=redis_url,
    default_limits=["1000 per day"],
    storage_options={"socket_connect_timeout": 30}
)


def check_qdrant():
    """Check Qdrant connection with timeout."""
    try:
        # Use a short timeout for the check
        client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT, timeout=2)
        # Ping isn't standard, but get_collections is lightweight
        client.get_collections()
        return {"status": "up", "latency_ms": 1}
    except Exception as e:
        return {"status": "down", "error": str(e)}

def check_auth():
    """Check Auth Manager connection with timeout."""
    try:
        response = requests.get(AUTH_MANAGER_URL, timeout=2)
        if response.status_code == 200:
             return {"status": "up", "latency_ms": response.elapsed.microseconds // 1000}
        return {"status": "down", "error": f"Status {response.status_code}"}
    except Exception as e:
        return {"status": "down", "error": str(e)}

@app.route('/health', methods=['GET'])
def health():
    qdrant_status = check_qdrant()
    auth_status = check_auth()
    
    status = "healthy"
    if qdrant_status['status'] != 'up':
        status = "unhealthy" # Critical
    elif auth_status['status'] != 'up':
        status = "degraded" # Can still serve cached data? No, ingestor needs auth. Unhealthy? 
        # Actually Ingestor runs in background. If auth is down, it just fails to ingest. 
        # "degraded" is appropriate as it's not a hard crash.

    return jsonify({
        "status": status,
        "service": "ingestor",
        "dependencies": {
            "qdrant": qdrant_status,
            "auth_manager": auth_status
        }
    }), 200

@app.route('/ingest', methods=['POST'])
@limiter.limit("5 per minute")
def trigger_ingest():
    """Trigger an immediate ingestion cycle."""
    try:
        data = request.get_json() or {}
        custom_batch_size = data.get('batch_size')
        # Default to True for manual triggers via API
        deep_sync = data.get('deep_sync', True)
        # Optional target: 'calendar', 'email', or None (both)
        target = data.get('target')
        
        logger.info(f"Received manual ingestion trigger (deep_sync={deep_sync}, target={target}).")
        
        email_count = 0
        event_count = 0
        
        if target is None or target == 'email':
            email_count = process_new_emails(custom_batch_size=custom_batch_size, deep_sync=deep_sync)
        if target is None or target == 'calendar':
            event_count = process_new_events()
        
        return jsonify({
            "status": "success", 
            "processed": {
                "emails": email_count,
                "events": event_count
            }
        }), 200
    except Exception as e:
        logger.error(f"Manual ingestion failed: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

def run_scheduler():
    """Starts the scheduling loop."""
    logger.info(f"Starting Ingestor Scheduler (Poll Interval: {POLL_INTERVAL}s)")
    
    # Run deep sync on first boot to backfill email history (up to 5,000 emails)
    # Subsequent polls only check the latest page for new arrivals
    try:
        logger.info("First boot: running deep sync to backfill email history...")
        process_new_emails(deep_sync=True)
        process_new_events()
    except Exception as e:
        logger.error(f"First boot deep sync failed (non-fatal, scheduler continues): {e}")
    
    schedule.every(POLL_INTERVAL).seconds.do(process_new_emails)
    schedule.every(POLL_INTERVAL).seconds.do(process_new_events)
    
    while True:
        try:
            schedule.run_pending()
        except Exception as e:
            logger.error(f"Scheduler cycle error (retrying next cycle): {e}")
        time.sleep(1)

def start_server():
    """Starts the Flask server."""
    port = int(os.getenv('PORT', 8009))
    logger.info(f"Starting Ingestor API on port {port}")
    app.run(host='0.0.0.0', port=port)

if __name__ == "__main__":
    # Start Scheduler in a separate thread
    scheduler_thread = threading.Thread(target=run_scheduler, daemon=True)
    scheduler_thread.start()
    
    # Run Flask server in main thread
    start_server()
