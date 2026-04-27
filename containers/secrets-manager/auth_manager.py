# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station

import os
import json
import secrets
from datetime import datetime, timedelta
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request

# Scopes must match google_auth_flow.py and Google Cloud Console config
SCOPES = [
    'https://www.googleapis.com/auth/gmail.readonly',
    'https://www.googleapis.com/auth/gmail.modify',
    'https://www.googleapis.com/auth/gmail.send',
    'https://www.googleapis.com/auth/calendar.events',
    'https://www.googleapis.com/auth/calendar.calendars.readonly',
    'https://www.googleapis.com/auth/drive',
]


class AuthManager:
    def __init__(self, token_path='/app/secrets/token.json', credentials_path=None):
        self.token_path = token_path
        self.credentials_path = credentials_path or os.environ.get(
            'CREDENTIALS_PATH', '/app/secrets/credentials.json'
        )
        self._credentials = None
        self._oauth_state = None  # CSRF state for OAuth flow
        self._oauth_flow = None   # Persisted Flow object for PKCE

    def has_valid_token(self):
        """Check if token.json has valid or refreshable credentials."""
        try:
            self.get_valid_token()
            return True
        except Exception as e:
            print(f"Token validation failed: {e}")
            return False

    def get_connected_email(self):
        """Extract the email address from token info, if available."""
        self._load_credentials()
        if not self._credentials:
            return None
        try:
            # Try to get email from token info via Google API
            from google.oauth2 import id_token
            from google.auth.transport import requests as auth_requests
            # Use userinfo endpoint instead
            import urllib.request
            if not self._credentials.valid:
                if self._credentials.refresh_token:
                    self._credentials.refresh(Request())
                    self._save_credentials()
                else:
                    return None
            req = urllib.request.Request(
                'https://www.googleapis.com/oauth2/v2/userinfo',
                headers={'Authorization': f'Bearer {self._credentials.token}'}
            )
            response = urllib.request.urlopen(req, timeout=5)
            data = json.loads(response.read().decode())
            return data.get('email')
        except Exception as e:
            print(f"Could not fetch email: {e}")
            return None

    def start_oauth_flow(self):
        """
        Generate the Google OAuth authorization URL.
        Returns (auth_url, state) tuple.
        """
        from google_auth_oauthlib.flow import Flow

        if not os.path.exists(self.credentials_path):
            raise Exception(f"credentials.json not found at {self.credentials_path}")

        # Generate CSRF state token
        self._oauth_state = secrets.token_urlsafe(32)

        # redirect_uri: configurable via OAUTH_REDIRECT_URI env var.
        # In production: http://localhost:9002 (callback server in container, no /callback path for installed creds)
        # In dev via nginx: http://localhost:8090/api/auth/callback
        redirect_uri = os.environ.get('OAUTH_REDIRECT_URI', 'http://localhost:9002')

        self._oauth_flow = Flow.from_client_secrets_file(
            self.credentials_path,
            scopes=SCOPES,
            redirect_uri=redirect_uri
        )

        auth_url, _ = self._oauth_flow.authorization_url(
            access_type='offline',
            prompt='consent',
            state=self._oauth_state
        )

        return auth_url, self._oauth_state

    def complete_oauth_flow(self, code, state=None):
        """
        Exchange the authorization code for tokens and save to token.json.
        Validates the state parameter if provided.
        """
        if state and self._oauth_state and state != self._oauth_state:
            raise Exception("OAuth state mismatch — possible CSRF attack")

        if not self._oauth_flow:
            raise Exception("No active OAuth flow — call start_oauth_flow() first")

        self._oauth_flow.fetch_token(code=code)
        self._credentials = self._oauth_flow.credentials
        self._save_credentials()

        # Clear state and flow after successful exchange
        self._oauth_state = None
        self._oauth_flow = None

        return True

    def get_valid_token(self):
        """
        Returns a valid access token and its expiry time. 
        Refreshes the token if it is expired or within 5 minutes of expiration.
        """
        self._load_credentials()
        
        # Check if we have credentials
        if not self._credentials:
             raise Exception("No credentials found. Please seed /secrets/token.json")
             
        # Proactive refresh buffer (5 minutes)
        expiry_buffer = timedelta(minutes=5)
        is_near_expiry = self._credentials.expiry and (self._credentials.expiry - datetime.utcnow() < expiry_buffer)

        if not self._credentials.valid or is_near_expiry:
            if self._credentials.refresh_token:
                print(f"Token expired or near expiry (expiry: {self._credentials.expiry}). Refreshing...")
                self._credentials.refresh(Request())
                self._save_credentials()
            else:
                 # If we don't have a refresh token or credentials are totally invalid/missing, we can't do anything headlessly.
                 # In a real scenario, we might raise an error or log a warning.
                 # For now, we assume token.json is seeded with a valid refresh token.
                 raise Exception("No valid refresh token found. Please seed /secrets/token.json")
        
        return {
            'token': self._credentials.token,
            'expires_at': self._credentials.expiry.isoformat() + 'Z' if self._credentials.expiry else None
        }

    def _load_credentials(self):
        if os.path.exists(self.token_path):
            try:
                self._credentials = Credentials.from_authorized_user_file(self.token_path)
            except Exception as e:
                print(f"Error loading credentials: {e}")
                self._credentials = None
        else:
             print(f"Token file not found at {self.token_path}")

    def _save_credentials(self):
        if self._credentials:
            try:
                with open(self.token_path, 'w') as token_file:
                    token_file.write(self._credentials.to_json())
            except Exception as e:
                 print(f"Error saving refreshed credentials: {e}")
