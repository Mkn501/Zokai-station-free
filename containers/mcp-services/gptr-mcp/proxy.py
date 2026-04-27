# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
import sys
import json
import logging
import threading
import requests
import sseclient

# Configure logging to stderr so it doesn't interfere with stdio JSON-RPC
logging.basicConfig(level=logging.INFO, stream=sys.stderr, format='[Proxy] %(message)s')
logger = logging.getLogger("proxy")

BASE_URL = "http://localhost:8000"
SSE_URL = f"{BASE_URL}/sse"
POST_URL = None # Will be set by 'endpoint' event

def sse_listener():
    global POST_URL
    try:
        logger.info(f"Connecting to SSE at {SSE_URL}")
        # Use requests with stream=True for manual SSE parsing
        with requests.get(SSE_URL, stream=True) as response:
            response.raise_for_status()
            logger.info("SSE connection established.")
            
            # Simple manual SSE parser
            current_event = None
            current_data = []

            for line in response.iter_lines():
                if line:
                    decoded_line = line.decode('utf-8')
                    # logger.debug(f"Raw SSE line: {decoded_line}") # Too verbose for INFO level
                    if decoded_line.startswith('event: '):
                        current_event = decoded_line[7:].strip()
                    elif decoded_line.startswith('data: '):
                        current_data.append(decoded_line[6:].strip())
                else:
                    # Empty line indicates end of message
                    if current_event and current_data:
                        data_str = '\n'.join(current_data)
                        
                        if current_event == 'endpoint':
                            if data_str.startswith("http"):
                                POST_URL = data_str
                            else:
                                POST_URL = f"{BASE_URL}{data_str}"
                            logger.info(f"Endpoint received: {POST_URL}")
                        
                        elif current_event == 'message':
                            print(data_str)
                            sys.stdout.flush()
                            
                    current_event = None
                    current_data = []
                    
    except Exception as e:
        logger.error(f"SSE Error: {e}")
        sys.exit(1)

def main():
    # Start SSE listener in a thread
    t = threading.Thread(target=sse_listener, daemon=True)
    t.start()

    # Read from stdin (JSON-RPC from Client)
    # Loop and POST to the endpoint
    while True:
        try:
            line = sys.stdin.readline()
            if not line:
                break
            
            # Wait for POST_URL to be established
            if not POST_URL:
                # Busy wait or use event (simplified here)
                import time
                timeout = 0
                while not POST_URL and timeout < 50:
                    time.sleep(0.1)
                    timeout += 1
                if not POST_URL:
                    logger.error("Timeout waiting for SSE endpoint")
                    continue

            # POST the message
            try:
                requests.post(POST_URL, data=line, headers={"Content-Type": "application/json"})
            except Exception as e:
                logger.error(f"POST Error: {e}")
        except KeyboardInterrupt:
            break

if __name__ == "__main__":
    main()
