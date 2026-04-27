# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
"""
WO-GSYNC-6: Backfill Labels on Existing Emails
================================================
One-time script that scrolls all existing email points in Qdrant,
fetches their current labelIds from Gmail API, and updates the
Qdrant payload with the `labels` and `is_read` fields.

Usage (inside the ingestor container):
    python backfill_labels.py

Environment:
    Requires the same env vars as app.py (QDRANT_HOST, AUTH_MANAGER_URL, etc.)
"""
import os
import sys
import time
import logging
import requests
from datetime import datetime

from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build
from qdrant_client import QdrantClient

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

# Configuration (same as app.py)
AUTH_MANAGER_URL = os.getenv('AUTH_MANAGER_URL', 'http://secrets-manager:9001/auth/token')
QDRANT_HOST = os.getenv('QDRANT_HOST', 'qdrant')
QDRANT_PORT = int(os.getenv('QDRANT_PORT', 6333))
COLLECTION_NAME = "emails"
GMAIL_SCOPES = ['https://www.googleapis.com/auth/gmail.modify']


def get_gmail_service():
    """Authenticate with Gmail API via secrets-manager (same as app.py)."""
    try:
        response = requests.get(AUTH_MANAGER_URL, timeout=10)
        if response.status_code != 200:
            logger.error(f"Auth manager returned {response.status_code}")
            return None
        token_data = response.json()
        if 'token' not in token_data:
            logger.error(f"Auth manager missing 'token' in response: {list(token_data.keys())}")
            return None
        creds = Credentials(token=token_data['token'])
        return build('gmail', 'v1', credentials=creds)
    except Exception as e:
        logger.error(f"Failed to get Gmail service: {e}")
        return None


def backfill_labels(q_client, gmail_service, batch_size=50):
    """Scroll all email points, fetch labels from Gmail, update Qdrant payloads.
    
    Returns: count of emails updated.
    """
    updated = 0
    skipped = 0
    errors = 0
    offset = None

    while True:
        # Scroll through all email points
        results = q_client.scroll(
            collection_name=COLLECTION_NAME,
            scroll_filter=None,
            limit=batch_size,
            offset=offset,
            with_payload=["gmail_id", "labels", "type"],
            with_vectors=False,
        )

        points, next_offset = results
        if not points:
            break

        for point in points:
            payload = point.payload or {}

            # Skip non-email points (e.g., _sync_metadata sentinel)
            if payload.get('type') != 'email':
                continue

            # Skip if already has labels
            if payload.get('labels'):
                skipped += 1
                continue

            gmail_id = payload.get('gmail_id')
            if not gmail_id:
                continue

            # Fetch labels from Gmail API
            try:
                msg = gmail_service.users().messages().get(
                    userId='me', id=gmail_id, format='metadata',
                    metadataHeaders=['']  # We only need labelIds
                ).execute()
                label_ids = msg.get('labelIds', [])
                is_read = 'UNREAD' not in label_ids

                q_client.set_payload(
                    collection_name=COLLECTION_NAME,
                    payload={
                        "labels": label_ids,
                        "is_read": is_read
                    },
                    points=[point.id],
                )
                updated += 1

                if updated % 100 == 0:
                    logger.info(f"Progress: {updated} updated, {skipped} skipped, {errors} errors")

                # Rate limit: ~10 requests/sec
                time.sleep(0.1)

            except Exception as e:
                logger.warning(f"Failed to fetch labels for {gmail_id}: {e}")
                errors += 1
                time.sleep(0.5)  # Back off on errors

        offset = next_offset
        if offset is None:
            break

    logger.info(f"Backfill complete: {updated} updated, {skipped} already had labels, {errors} errors")
    return updated


def main():
    logger.info("Starting label backfill...")

    gmail_service = get_gmail_service()
    if not gmail_service:
        logger.error("Cannot connect to Gmail. Exiting.")
        return 1

    q_client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT)

    count = backfill_labels(q_client, gmail_service, batch_size=50)
    logger.info(f"Updated {count} emails with labels")
    return 0


if __name__ == '__main__':
    sys.exit(main())
