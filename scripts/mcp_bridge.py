# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
import sys
import json
import subprocess
import threading
import time
import os
import signal

# Container prefix auto-detection:
# 1. Check ZOKAI_INSTANCE env var first (explicit override)
# 2. Probe Docker to find our own container name via hostname → docker inspect
# 3. Scan docker ps for running containers matching *-vs-code pattern (host fallback)
# 4. Default to "zokai"
def _detect_prefix():
    env_val = os.environ.get("ZOKAI_INSTANCE")
    if env_val:
        return env_val
    # ZOKAI_TIER support (consistent with docker_helpers.py)
    tier = os.environ.get("ZOKAI_TIER")
    if tier:
        return f"zokai-{tier}"
    # Strategy 1: Inside a container — hostname is the short container ID
    try:
        import socket as _socket
        short_id = _socket.gethostname()  # Docker sets hostname = short container ID
        result = subprocess.run(
            ["docker", "inspect", "--format", "{{.Name}}", short_id],
            capture_output=True, text=True, timeout=2
        )
        name = result.stdout.strip().lstrip("/")  # e.g. "zokai-dev-vs-code" or "zokai-mkn-vs-code"
        if "-vs-code" in name:
            return name.split("-vs-code")[0]
    except Exception:
        pass
    # Strategy 2: On the host — scan running containers
    try:
        result = subprocess.run(
            ["docker", "ps", "--format", "{{.Names}}"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            for container_name in result.stdout.strip().splitlines():
                if "-vs-code" in container_name:
                    prefix = container_name.split("-vs-code")[0]
                    return prefix
    except Exception:
        pass
    return "zokai"

ZOKAI_PREFIX = _detect_prefix()

# Service Configurations — container names built dynamically from prefix
SERVICES = {
    "gptr-mcp": {
        "container": f"{ZOKAI_PREFIX}-gptr-mcp",
        "command": "python -u /app/server.py --stdio", # Default classic mode
        "env": {"MCP_TRANSPORT": "stdio"}
    },
    "youtube-mcp": {
        "container": f"{ZOKAI_PREFIX}-youtube-mcp",
        "command": "python simple_youtube_mcp.py",
        "env": {"MCP_TRANSPORT": "stdio"}
    },
    "gmail-mcp": {
        "container": f"{ZOKAI_PREFIX}-gmail-mcp",
        "command": "python -u /app/app.py",
        "env": {"MCP_TRANSPORT": "stdio"}
    },
    "calendar-mcp": {
        "container": f"{ZOKAI_PREFIX}-calendar-mcp",
        "command": "python -u /app/app.py",
        "env": {"MCP_TRANSPORT": "stdio"}
    },
    "github-mcp": {
        "container": f"{ZOKAI_PREFIX}-github-mcp",
        "command": "exec /server/github-mcp-server stdio",
        "shell_wrap": True, # Needs sh -c for secret injection
        "secret_env": "GITHUB_PERSONAL_ACCESS_TOKEN=$(cat /run/secrets/github-token)"
    },
    "postgres": {
        "container": f"{ZOKAI_PREFIX}-postgres-mcp",
        "command": "python /app/postgres_server.py",
        "env": {"MCP_TRANSPORT": "stdio"}
    },
    "markdownify-mcp": {
        "container": f"{ZOKAI_PREFIX}-markdownify-mcp",
        "command": "node dist/index.js",
        "env": {"MCP_TRANSPORT": "stdio"}
    },
    "mcp-tasks": {
        "container": f"{ZOKAI_PREFIX}-mcp-tasks",
        "command": "node /app/dist/index.js",
        "env": {"TRANSPORT": "stdio"},
        "needs_path_translation": True
    },
    "ideas-mcp": {
        "container": f"{ZOKAI_PREFIX}-ideas-mcp",
        "command": "node /app/dist/index.js",
        "env": {"TRANSPORT": "stdio"}
    },
    "raindrop-mcp": {
        "container": f"{ZOKAI_PREFIX}-raindrop-mcp",
        "command": "python -u /app/server.py",
        "env": {"MCP_TRANSPORT": "stdio"}
    },
    "kw-extractor-mcp": {
        "container": f"{ZOKAI_PREFIX}-kw-extractor-mcp",
        "command": "python -u /app/server.py",
        "env": {"MCP_TRANSPORT": "stdio"}
    },
    "tavily-mcp": {
        "container": f"{ZOKAI_PREFIX}-tavily-mcp",
        "command": "node /app/node_modules/@mcptools/mcp-tavily/dist/index.js",
        "env": {},
        # Read secret from host secrets/ dir and inject as env var (avoids broken
        # in-container bind-mount: ls shows file but cat fails ENOENT on Alpine)
        "host_secret_env": {"TAVILY_API_KEY": "secrets/tavily-api-key.txt"},
    },
    "memory-kg-mcp": {
        "host_command": [
            "node", "/host-tools/memory-kg-mcp/dist/index.js",
            "--memory-path", "/home/workspace-user/workspaces/notes/kw/memory/kg_memory.jsonl"
        ]
    }
}

class MCPBridge:
    def __init__(self, service_name):
        if service_name not in SERVICES:
            raise ValueError(f"Unknown service: {service_name}")
        
        self.service_name = service_name
        self.config = SERVICES[service_name]
        self.process = None
        self.debug = True
        self.log_file = '/tmp/bridge.log'

    def log(self, msg):
        if self.debug:
            timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
            try:
                with open(self.log_file, 'a') as f:
                    f.write(f'[{timestamp}] [{self.service_name}] {msg}\n')
            except:
                pass

    def start_process(self):
        # Host-local execution (no Docker container) — e.g., memory-kg-mcp
        if 'host_command' in self.config:
            cmd = self.config['host_command']
            env = os.environ.copy()
            if 'env' in self.config:
                env.update(self.config['env'])
            self.log(f"Starting host-local process: {cmd}")
            self.process = subprocess.Popen(
                cmd,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=0,
                env=env
            )
            return

        # Docker exec mode (existing behavior)
        container = self.config['container']
        cmd_str = self.config['command']
        
        # Special handling for gptr-mcp modes
        if self.service_name == 'gptr-mcp':
            mode = os.environ.get('GPTR_MODE', 'classic')
            self.log(f"GPTR Mode: {mode}")
            if mode == 'proxy':
                cmd_str = "python -u /app/proxy.py"
        
        docker_cmd = ['docker', 'exec', '-i']
        
        # Add static env vars
        if 'env' in self.config:
            for k, v in self.config['env'].items():
                docker_cmd.extend(['-e', f'{k}={v}'])
        
        # Add host-side secret env vars (read from host file, inject into docker exec)
        # This avoids the broken in-container bind-mount pattern on Alpine.
        if 'host_secret_env' in self.config:
            script_dir = os.path.dirname(os.path.abspath(__file__))
            # Build candidate paths — tried in order until one works.
            # Covers: host execution (bridge in core/scripts/) and
            # in-container execution (bridge in /home/workspace-user/scripts/)
            candidate_bases = [
                # 1. Host: core/scripts/../../  = zokai-station/
                os.path.normpath(os.path.join(script_dir, '..', '..')),
                # 2. Scripts volume dir itself (in-container: /home/workspace-user/scripts)
                #    Secrets written here as .<key-name> by installer/hot-fix.
                #    The host_secret_env path is e.g. "secrets/tavily-api-key.txt";
                #    we also try the script_dir directly with just the filename.
                script_dir,
                # 3. DATA_DIR env (set by installer e.g. ~/Documents/ZokaiData)
                os.path.join(os.environ.get('DATA_DIR', ''), ''),
                # 4. macOS default install path
                os.path.expanduser('~/Documents/ZokaiData'),
                # 5. Explicit secrets dir override
                os.environ.get('ZOKAI_SECRETS_DIR', ''),
            ]
            for env_key, secret_rel_path in self.config['host_secret_env'].items():
                injected = False

                # For TAVILY_API_KEY: check zokai-config.json FIRST (user-editable source of truth)
                if env_key == 'TAVILY_API_KEY':
                    for cfg_path in [
                        '/home/workspace-user/workspaces/.zokai/zokai-config.json',
                        os.path.join(os.environ.get('WORKSPACE_DIR', ''), '.zokai', 'zokai-config.json'),
                    ]:
                        try:
                            import json as _json
                            with open(cfg_path) as _f:
                                _cfg = _json.load(_f)
                            _val = _cfg.get('TAVILY_API_KEY', '')
                            if _val and _val.upper() != 'PLACEHOLDER':
                                docker_cmd.extend(['-e', f'{env_key}={_val}'])
                                self.log(f"Injected {env_key} from zokai-config: {cfg_path}")
                                injected = True
                                break
                        except Exception:
                            continue

                # Fall back to secret files (file-first for non-Tavily keys, fallback for Tavily)
                if not injected:
                    # Also try the filename directly (without subdirectory) in script_dir
                    filename = os.path.basename(secret_rel_path)
                    dot_filename = '.' + filename.replace('-api-key.txt', '-api-key')  # e.g. .tavily-api-key
                    extra_paths = [
                        os.path.join(script_dir, filename),
                        os.path.join(script_dir, dot_filename),
                    ]
                    for candidate in extra_paths + [os.path.normpath(os.path.join(b, secret_rel_path)) for b in candidate_bases if b]:
                        try:
                            with open(candidate, 'r') as f:
                                secret_value = f.read().strip()
                            if secret_value and secret_value.upper() != 'PLACEHOLDER':
                                docker_cmd.extend(['-e', f'{env_key}={secret_value}'])
                                self.log(f"Injected {env_key} from: {candidate}")
                                injected = True
                                break
                            elif secret_value.upper() == 'PLACEHOLDER':
                                self.log(f"Skipped PLACEHOLDER value in: {candidate}")
                                continue
                        except OSError:
                            continue
                if not injected:
                    self.log(f"Warning: could not find secret for {env_key} in any candidate path")

        docker_cmd.append(container)
        
        if self.config.get('shell_wrap'):
            # Complex case for GitHub: use sh -c to eval secrets
            secret = self.config.get('secret_env', '')
            full_cmd = f"{secret} {cmd_str}"
            docker_cmd.extend(['/bin/sh', '-c', full_cmd])
        else:
             # Basic case: split command string
             docker_cmd.extend(cmd_str.split())

        self.log(f"Starting process: {docker_cmd}")
        self.process = subprocess.Popen(
            docker_cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=0 # Critical: Unbuffered
        )
        
    def handshake(self):
        """Performs the initial handshake with the MCP server."""
        try:
            # 1. Send initialize
            info = {"name": f"{self.service_name}-bridge", "version": "1.0.0"}
            init_req = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": info
                }
            }
            self.log(f"Sending handshake init: {json.dumps(init_req)}")
            self.process.stdin.write(json.dumps(init_req) + "\n")
            self.process.stdin.flush()

            # 2. Wait for response
            self.log("Waiting for handshake response...")
            response = self.process.stdout.readline()
            self.log(f"Handshake response: {response.strip()}")

            # 3. Send initialized notification
            init_notif = {
                "jsonrpc": "2.0",
                "method": "notifications/initialized"
            }
            self.process.stdin.write(json.dumps(init_notif) + "\n")
            self.process.stdin.flush()
            self.log("Handshake complete.")

        except Exception as e:
            self.log(f"Handshake failed: {e}")
            if self.process:
                self.process.terminate()
            raise

    def handle_client_message(self, line):
        """Standardizes handling of messages from Kilo Code (stdin)."""
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            return  # Skip invalid JSON

        method = msg.get("method")

        # Intercept Initialize Request
        if method == "initialize":
            self.log("Intercepting Kilo initialize request")
            response = {
                "jsonrpc": "2.0",
                "id": msg.get("id"),
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {"listChanged": True}},
                    "serverInfo": {"name": self.service_name, "version": "1.0.0"}
                }
            }
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()
            return

        # Intercept Initialized Notification
        if method == "notifications/initialized":
            self.log("Intercepting Kilo initialized notification")
            return

        # Path Translation (mcp-tasks and other services needing path conversion)
        if self.config.get("needs_path_translation"):
             if "params" in msg and "arguments" in msg["params"]:
                args = msg["params"]["arguments"]
                # Iterate over common path arguments to translate
                PATH_KEYS = ["projectRoot", "input", "output", "file", "path", "directory", "cwd", "source_path"]
                for key in args:
                    if key in PATH_KEYS and isinstance(args[key], str):
                        old_path = args[key]
                        if old_path.startswith("/home/workspace-user/workspaces"):
                             new_path = old_path.replace("/home/workspace-user/workspaces", "/app/workspace", 1)
                             args[key] = new_path
                             self.log(f"Translated {key}: {old_path} -> {new_path}")
                        elif old_path.startswith("/home/workspace-user/tasks"):
                             new_path = old_path.replace("/home/workspace-user/tasks", "/app/tasks", 1)
                             args[key] = new_path
                             self.log(f"Translated {key}: {old_path} -> {new_path}")
                        elif old_path.startswith("/app"):
                             pass 
                
                line = json.dumps(msg) + "\n"

        # Forward to MCP Server
        self.process.stdin.write(line)
        self.process.stdin.flush()

    def run(self):
        """Main entry point: starts process, handshake, and proxy loops."""
        self.start_process()
        self.handshake()

        # Thread to read from MCP stdout -> Kilo stdout
        def pipe_stdout():
            try:
                for line in self.process.stdout:
                    # Filter out non-JSON lines (some servers print banners to stdout)
                    stripped = line.strip()
                    if stripped and not stripped.startswith('{'):
                        self.log(f"Filtered non-JSON stdout: {stripped}")
                        continue
                    sys.stdout.write(line)
                    sys.stdout.flush()
            except Exception as e:
                self.log(f"Error in pipe_stdout: {e}")

        t = threading.Thread(target=pipe_stdout, daemon=True)
        t.start()

        # Main thread: Read from Kilo stdin -> MCP stdin
        try:
            while True:
                line = sys.stdin.readline()
                if not line:
                    break
                self.handle_client_message(line)
        except KeyboardInterrupt:
            pass # Clean exit handled by finally
        except Exception as e:
            self.log(f"Error in main loop: {e}")
        finally:
            if self.process:
                self.process.terminate()

if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(1)
    bridge = MCPBridge(sys.argv[1])
    bridge.run()
