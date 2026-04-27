
import os
import requests
import logging
from typing import Optional, List
from google.oauth2.credentials import Credentials

logger = logging.getLogger(__name__)

class TokenManager:
    def __init__(self, auth_manager_url: str = None):
        # Default to the internal docker network URL for secrets-manager
        self.auth_manager_url = auth_manager_url or os.environ.get(
            'AUTH_MANAGER_URL', 
            'http://secrets-manager:9001/auth/token'
        )

    def get_credentials(self, scopes: List[str] = None) -> Credentials:
        """
        Retrieves valid Google OAuth credentials from the best available source.
        Priority:
        1. Auth Manager Service (Secrets Manager)
        2. Local Token File (GOOGLE_TOKEN_FILE)
        3. Environment Variables
        
        Raises:
            ValueError: If no valid credentials can be found.
        """
        creds = self._try_auth_manager()
        
        if not creds:
            creds = self._try_token_file(scopes)
            
        if not creds:
            creds = self._try_env_vars(scopes)
            
        if not creds:
            raise ValueError("No valid credentials found (Auth Manager failed, and no local fallbacks available)")
            
        return creds

    def _try_auth_manager(self) -> Optional[Credentials]:
        """Attempt to get token from the central Auth Manager service.

        Bug note: the Auth Manager returns only the bare access_token, not a full
        credential. A Credentials(token=access_token) object is NOT refreshable —
        when it expires after ~1h, google-auth raises 'does not contain the necessary
        fields need to refresh the access token'. We therefore only use the auth manager
        response to verify connectivity; for the actual credential we always load the
        full token.json so the credential can self-refresh indefinitely.
        """
        try:
            response = requests.get(self.auth_manager_url, timeout=5)
            if response.status_code == 200:
                token_data = response.json()
                if not token_data:
                    logger.warning("Auth Manager returned empty response")
                    return None

                # If the auth manager returns full oauth fields, build a refreshable cred
                if all(k in token_data for k in ('refresh_token', 'token_uri', 'client_id', 'client_secret')):
                    logger.info("Successfully retrieved full credentials from Auth Manager")
                    return Credentials.from_authorized_user_info(token_data)

                # Auth Manager only returns bare access_token — this is NOT refreshable.
                # Log success (the service is reachable and auth is working) but return
                # None so get_credentials() falls through to the token.json fallback,
                # which provides a fully refreshable credential.
                if 'token' in token_data:
                    logger.info("Auth Manager reachable — falling through to token file for refreshable credential")
                else:
                    logger.warning(f"Auth Manager response missing token field: {list(token_data.keys())}")
            else:
                logger.warning(f"Auth Manager returned status {response.status_code}: {response.text}")
        except Exception as e:
            logger.warning(f"Failed to connect to Auth Manager at {self.auth_manager_url}: {e}")
        return None

    def _try_token_file(self, scopes: List[str]) -> Optional[Credentials]:
        """Attempt to load credentials from a local JSON file.

        Checks (in order):
        1. GOOGLE_TOKEN_FILE env var (explicit override)
        2. TOKEN_PATH env var (set in cloud-sync)
        3. /run/secrets/token-json  (Docker secrets mount — gmail-mcp, calendar-mcp)
        4. /run/secrets/token.json  (Docker secrets alternate name)
        5. /app/secrets/token.json  (direct bind-mount — cloud-sync)
        """
        candidates = []
        if os.environ.get('GOOGLE_TOKEN_FILE'):
            candidates.append(os.environ['GOOGLE_TOKEN_FILE'])
        if os.environ.get('TOKEN_PATH'):
            candidates.append(os.environ['TOKEN_PATH'])
        # Docker secrets standard paths
        candidates.append('/run/secrets/token-json')
        candidates.append('/run/secrets/token.json')
        # Direct bind-mount path (cloud-sync)
        candidates.append('/app/secrets/token.json')

        for token_file in candidates:
            if os.path.exists(token_file):
                logger.info(f"Loading credentials from file: {token_file}")
                try:
                    return Credentials.from_authorized_user_file(token_file, scopes)
                except Exception as e:
                    logger.error(f"Failed to load token file {token_file}: {e}")
        return None

    def _try_env_vars(self, scopes: List[str]) -> Optional[Credentials]:
        """Attempt to construct credentials from environment variables."""
        refresh_token = os.environ.get('GOOGLE_REFRESH_TOKEN')
        client_id = os.environ.get('GOOGLE_CLIENT_ID')
        client_secret = os.environ.get('GOOGLE_CLIENT_SECRET')
        
        if all([client_id, client_secret, refresh_token]):
            logger.info("Constructing credentials from environment variables")
            return Credentials(
                None,
                refresh_token=refresh_token,
                token_uri='https://oauth2.googleapis.com/token',
                client_id=client_id,
                client_secret=client_secret,
                scopes=scopes
            )
        return None
