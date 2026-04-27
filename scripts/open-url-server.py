#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
"""
Zokai Station — Host URL Opener

Tiny HTTP server that runs on the macOS HOST (outside Docker).
When the dashboard calls GET /open?url=<encoded-url>, this script opens
the URL in the system's default browser via macOS `open` command.

Usage:
    python3 scripts/open-url-server.py &

The server listens on 0.0.0.0:18099 (IPv4+IPv6 dual-stack).
Docker containers reach it via host.docker.internal.
"""

import http.server
import socket
import socketserver
import subprocess
import sys
import urllib.parse
import os
import signal

PORT = int(os.environ.get("URL_OPENER_PORT", 18099))


class DualStackHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    """HTTP server that supports both IPv4 and IPv6 (dual-stack)."""
    address_family = socket.AF_INET6
    allow_reuse_address = True

    def server_bind(self):
        # Enable dual-stack: accept both IPv4 and IPv6 connections
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


class URLOpenerHandler(http.server.BaseHTTPRequestHandler):
    """Handles GET /open?url=<url> requests."""

    # Use HTTP/1.1 for keep-alive compatibility with nginx proxy
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)

        if parsed.path == "/open":
            params = urllib.parse.parse_qs(parsed.query)
            url = params.get("url", [""])[0]

            if not url:
                self._respond(400, "Missing 'url' parameter")
                return

            # Security: only allow HTTPS URLs
            if not url.startswith("https://"):
                self._respond(403, "Only HTTPS URLs are allowed")
                return

            try:
                subprocess.Popen(["open", url])
                self._respond(200, "OK")
                print(f"[url-opener] Opened: {url[:60]}")
            except Exception as e:
                self._respond(500, f"Failed: {e}")

        elif parsed.path == "/health":
            self._respond(200, "OK")

        else:
            self._respond(404, "Not found")

    def _respond(self, code, message):
        body = message.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Connection", "close")
        self.end_headers()

    def log_message(self, format, *args):
        """Suppress default request logging (we log manually)."""
        pass


def main():
    # Bind to [::] (IPv6 any) with dual-stack = accepts IPv4 too
    server = DualStackHTTPServer(("::", PORT), URLOpenerHandler)
    print(f"[url-opener] Listening on [::]:{PORT} (IPv4+IPv6 dual-stack)")

    # Graceful shutdown
    def shutdown(sig, frame):
        print("\n[url-opener] Shutting down...")
        server.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        shutdown(None, None)


if __name__ == "__main__":
    main()
