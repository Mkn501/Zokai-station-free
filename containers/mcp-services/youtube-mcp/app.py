# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
from flask import Flask, jsonify
import os
import logging

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@app.route('/health')
def health():
    return {'status': 'ok', 'service': 'youtube-mcp'}, 200

@app.route('/info')
def info():
    return {'service': 'youtube-mcp', 'version': '1.0.0'}, 200

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8002))
    app.run(host='0.0.0.0', port=port)