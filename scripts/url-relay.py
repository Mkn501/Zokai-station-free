#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
"""
Zokai Station — URL Relay (runs inside vs-code container)

Receives POST /open requests with a URL and writes it to a shared file.
The host-side watcher (open-url-watcher.sh) picks up the URL and opens it.

Usage (inside container):
    python3 /home/workspace-user/scripts/url-relay.py &
"""

import http.server
import os
import urllib.parse
import sys
import signal

PORT = 18099
# Write to the scripts/ directory — bind-mounted from the host in both dev and prod
# (docker-compose.yml: ./scripts → /home/workspace-user/scripts)
# The host-side open-url-watcher.sh reads from the same scripts/ directory.
RELAY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)))
RELAY_FILE = os.path.join(RELAY_DIR, ".open-url-queue")
os.makedirs(RELAY_DIR, exist_ok=True)


class RelayHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/open":
            params = urllib.parse.parse_qs(parsed.query)
            url = params.get("url", [""])[0]
            if not url or not url.startswith("https://"):
                self._respond(400, "Invalid URL")
                return
            # Write URL to relay file for host watcher to pick up
            try:
                with open(RELAY_FILE, "w") as f:
                    f.write(url)
                self._respond(200, "OK")
                print(f"[url-relay] Relayed: {url[:60]}")
            except Exception as e:
                self._respond(500, f"Failed: {e}")
        elif parsed.path == "/health":
            self._respond(200, "OK")
        else:
            self._respond(404, "Not found")

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/kilo-prompt":
            try:
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length).decode("utf-8")
                import json
                data = json.loads(body)
                prompt = data.get("prompt", "")
                if not prompt:
                    self._respond(400, "Missing prompt")
                    return
                # Write to the workspaces .gemini dir where the Kilo watcher polls
                ws_dir = "/home/workspace-user/workspaces"
                gemini_dir = os.path.join(ws_dir, ".gemini")
                os.makedirs(gemini_dir, exist_ok=True)
                import time
                target = os.path.join(gemini_dir, "kilo-prompt.json")
                with open(target, "w") as f:
                    json.dump({"prompt": prompt, "timestamp": time.time()}, f)
                self._respond(200, "OK")
                print(f"[url-relay] Kilo prompt dropped ({len(prompt)} chars)")
            except Exception as e:
                self._respond(500, f"Failed: {e}")
        elif parsed.path == "/open-file":
            try:
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length).decode("utf-8")
                import json
                data = json.loads(body)
                file_path = data.get("path", "").strip()
                if not file_path:
                    self._respond(400, "Missing path")
                    return
                # Resolve relative paths against workspaces root
                ws_root = "/home/workspace-user/workspaces"
                if not os.path.isabs(file_path):
                    file_path = os.path.join(ws_root, file_path)
                # Security: ensure path stays within workspaces
                real = os.path.realpath(file_path)
                if not real.startswith(ws_root):
                    self._respond(403, "Path outside workspace")
                    return
                # Find the active VS Code IPC socket (only one will be LISTENING)
                import glob
                import socket as sock_mod
                import subprocess
                ipc_sock = None
                for s in sorted(glob.glob("/tmp/vscode-ipc-*.sock"), key=os.path.getmtime, reverse=True):
                    try:
                        test = sock_mod.socket(sock_mod.AF_UNIX, sock_mod.SOCK_STREAM)
                        test.settimeout(0.3)
                        test.connect(s)
                        test.close()
                        ipc_sock = s
                        break
                    except Exception:
                        continue
                if not ipc_sock:
                    self._respond(500, "No active VS Code IPC socket")
                    return
                env = os.environ.copy()
                env["VSCODE_IPC_HOOK_CLI"] = ipc_sock
                subprocess.Popen(
                    ["/usr/lib/code-server/lib/vscode/bin/remote-cli/code-server",
                     "--goto", real + ":1"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    env=env,
                )
                self._respond(200, "OK")
                print(f"[url-relay] Opening file: {real}")
            except Exception as e:
                self._respond(500, f"Failed: {e}")
        else:
            self._respond(404, "Not found")

    def do_OPTIONS(self):
        """Handle CORS preflight for POST requests."""
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _respond(self, code, msg):
        body = msg.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


def main():
    from http.server import ThreadingHTTPServer
    server = ThreadingHTTPServer(("0.0.0.0", PORT), RelayHandler)
    print(f"[url-relay] Listening on 0.0.0.0:{PORT}")
    signal.signal(signal.SIGTERM, lambda s, f: (server.shutdown(), sys.exit(0)))
    signal.signal(signal.SIGINT, lambda s, f: (server.shutdown(), sys.exit(0)))
    server.serve_forever()


if __name__ == "__main__":
    main()
