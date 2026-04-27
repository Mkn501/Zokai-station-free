# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
import sys
import os

sys.path.append(os.path.join(os.path.dirname(__file__), 'shared'))
from workstation_auth import TokenManager
from googleapiclient.discovery import build

tm = TokenManager()
creds = tm.get_credentials(['https://www.googleapis.com/auth/calendar'])
service = build('calendar', 'v3', credentials=creds)

event_id = "6pgjio9j6pgjab9i6sq3ib9kcgq34b9o6opjab9m64qm8eb660qjge9lcg_20260322T110000Z"
try:
    print("Attempting to delete...")
    service.events().delete(calendarId='primary', eventId=event_id).execute()
    print("Delete succeeded.")
except Exception as e:
    print(f"Delete failed: {e}")
    try:
        print("Attempting to patch status to cancelled...")
        service.events().patch(calendarId='primary', eventId=event_id, body={'status': 'cancelled'}).execute()
        print("Patch succeeded.")
    except Exception as patch_e:
        print(f"Patch failed: {patch_e}")
