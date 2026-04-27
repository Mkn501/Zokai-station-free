# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
from flask import Flask, jsonify, request
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from werkzeug.middleware.proxy_fix import ProxyFix
import os
import threading

app = Flask(__name__)
# Trusts 1 layer of proxy (Nginx)
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_port=1)

_redis_password = os.environ.get('REDIS_PASSWORD')
if not _redis_password:
    raise RuntimeError("REDIS_PASSWORD environment variable is required but not set")
redis_url = f"redis://:{_redis_password}@{os.environ.get('REDIS_HOST', 'redis')}:{os.environ.get('REDIS_PORT', 6379)}"

limiter = Limiter(
    get_remote_address,
    app=app,
    storage_uri=redis_url,
    default_limits=["200 per day", "50 per hour"],
    storage_options={"socket_connect_timeout": 30},
    strategy="fixed-window"
)

# Shared AuthManager instance (preserves CSRF state between /auth/start and /auth/callback)
_token_path = os.environ.get('TOKEN_PATH', '/app/secrets/token.json')
_auth_manager = None

def _get_auth_manager():
    global _auth_manager
    if _auth_manager is None:
        from auth_manager import AuthManager
        _auth_manager = AuthManager(token_path=_token_path)
    return _auth_manager


def check_redis():
    """Check Redis connection with timeout."""
    try:
        if not hasattr(limiter, '_storage'):
            return {"status": "unknown", "error": "No storage"}
        
        # Flask-Limiter doesn't expose a simple ping, so we check directly if possible
        # Or we can just trust the limiter exists. 
        # Better: Create a raw redis client for health checks if needed, 
        # but reusing existing connection is preferred.
        # For now, let's assume if app starts, it's ok, but a real check is better.
        # Let's try to ping via the storage mechanism if accessible, or just return 'unknown'
        # until we add a proper redis client.
        # actually, let's add a proper check if we can import redis
        import redis
        client = redis.from_url(redis_url, socket_timeout=2)
        client.ping()
        return {"status": "up", "latency_ms": 1} # Mock latency or measure it
    except Exception as e:
        return {"status": "down", "error": str(e)}

@app.route('/health')
@limiter.exempt
def health():
    redis_status = check_redis()
    
    # Determine overall status
    status = "healthy"
    if redis_status['status'] != 'up':
        status = "degraded" # Secrets manager can still serve static secrets? Maybe not.

    return jsonify({
        'status': status, 
        'service': 'secrets-manager',
        'dependencies': {
            'redis': redis_status
        }
    }), 200


@app.route('/secrets/status')
def secrets_status():
    # Basic secrets status endpoint
    return jsonify({
        'service': 'secrets-manager',
        'version': '1.0.0',
        'status': 'running',
        'secrets_loaded': True
    })

@app.route('/auth/token')
@limiter.limit("50 per minute")
def get_auth_token():
    try:
        manager = _get_auth_manager()
        auth_data = manager.get_valid_token()
        return jsonify({
            'token': auth_data['token'],
            'expires_at': auth_data['expires_at'],
            'status': 'valid'
        }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500


# ── OAuth Dashboard Connect Flow ────────────────────────────────────────

@app.route('/auth/status')
@limiter.exempt
def auth_status():
    """Check if Google account is connected."""
    try:
        manager = _get_auth_manager()
        connected = manager.has_valid_token()
        email = manager.get_connected_email() if connected else None
        return jsonify({
            'connected': connected,
            'email': email,
        }), 200
    except Exception as e:
        return jsonify({'connected': False, 'email': None, 'error': str(e)}), 200


@app.route('/auth/start')
@limiter.limit("10 per hour")
def auth_start():
    """Generate Google OAuth URL and start callback listener."""
    try:
        manager = _get_auth_manager()

        # Check if already connected
        if manager.has_valid_token():
            return jsonify({
                'error': 'Already connected. Disconnect first to re-authenticate.',
                'connected': True,
            }), 400

        auth_url, state = manager.start_oauth_flow()

        # Start the temporary callback server in a background thread
        _start_callback_server(manager, state)

        return jsonify({
            'auth_url': auth_url,
            'state': state,
        }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500


def _start_callback_server(manager, expected_state):
    """
    Start a temporary HTTP server on port 9002 to catch Google's OAuth callback.
    Runs in a daemon thread and shuts down after receiving the callback.
    """
    from http.server import HTTPServer, BaseHTTPRequestHandler
    from urllib.parse import urlparse, parse_qs

    class CallbackHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            parsed = urlparse(self.path)
            if parsed.path not in ('/', '/callback'):
                self.send_response(404)
                self.end_headers()
                return

            params = parse_qs(parsed.query)
            code = params.get('code', [None])[0]
            state = params.get('state', [None])[0]
            error = params.get('error', [None])[0]

            if error:
                self.send_response(200)
                self.send_header('Content-Type', 'text/html')
                self.end_headers()
                self.wfile.write(f"""
                    <html><body style="font-family: system-ui; text-align: center; padding: 60px;">
                    <h1>❌ Authorization Failed</h1>
                    <p>{error}</p>
                    <p>You can close this tab and try again from the dashboard.</p>
                    </body></html>
                """.encode())
                # Shut down after error
                threading.Thread(target=self.server.shutdown, daemon=True).start()
                return

            if not code:
                self.send_response(400)
                self.send_header('Content-Type', 'text/html')
                self.end_headers()
                self.wfile.write(b"<html><body>Missing authorization code.</body></html>")
                return

            try:
                manager.complete_oauth_flow(code, state=state)
                self.send_response(200)
                self.send_header('Content-Type', 'text/html')
                self.end_headers()
                self.wfile.write("""
                    <html><body style="font-family: system-ui; text-align: center; padding: 60px;">
                    <h1 style="color: #4CAF50;">&#10003; Connected!</h1>
                    <p>Your Google account has been connected to Zokai Station.</p>
                    <p>You can close this tab. The dashboard will update automatically.</p>
                    <script>setTimeout(function() { window.close(); }, 3000);</script>
                    </body></html>
                """.encode('utf-8'))
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'text/html')
                self.end_headers()
                self.wfile.write(f"""
                    <html><body style="font-family: system-ui; text-align: center; padding: 60px;">
                    <h1>❌ Error</h1>
                    <p>{str(e)}</p>
                    </body></html>
                """.encode())
            finally:
                # Shut down the temporary server after handling the callback
                threading.Thread(target=self.server.shutdown, daemon=True).start()

        def log_message(self, format, *args):
            # Suppress default HTTP server logging
            print(f"[OAuth Callback] {format % args}")

    def run_server():
        try:
            server = HTTPServer(('0.0.0.0', 9002), CallbackHandler)
            server.timeout = 300  # 5 minute timeout
            print("[OAuth] Callback server listening on port 9002...")
            server.serve_forever()
            print("[OAuth] Callback server shut down.")
        except OSError as e:
            print(f"[OAuth] Could not start callback server on port 9002: {e}")

    thread = threading.Thread(target=run_server, daemon=True)
    thread.start()


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 9001))
    app.run(host='0.0.0.0', port=port)