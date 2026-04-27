#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
import os
import sys
import json
from pathlib import Path

TOKEN_PATH = os.getenv("GOOGLE_TOKEN_FILE", "/run/secrets/token-json")

def validate_token():
    print(f"Validating token at: {TOKEN_PATH}")
    
    path = Path(TOKEN_PATH)
    
    if not path.exists():
        print(f"ERROR: Token file not found at {TOKEN_PATH}")
        sys.exit(1)
        
    try:
        content = path.read_text()
        token_data = json.loads(content)
        
        # Basic schema check
        required_keys = ["token", "refresh_token", "client_id", "client_secret"]
        missing = [k for k in required_keys if k not in token_data]
        
        if missing:
            print(f"ERROR: Token is missing required fields: {missing}")
            sys.exit(1)
            
        print("SUCCESS: Token file exists and has valid schema.")
        sys.exit(0)
        
    except json.JSONDecodeError:
        print("ERROR: Token file is not valid JSON")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Unexpected error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    validate_token()
