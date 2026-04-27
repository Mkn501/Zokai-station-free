# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
from flask import Flask, jsonify
import os
import json

app = Flask(__name__)

@app.route('/health')
def health():
    return {'status': 'ok', 'service': 'config-service'}, 200

@app.route('/config')
def config():
    try:
        with open('config.json', 'r') as f:
            data = json.load(f)
        return jsonify(data)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8006))
    app.run(host='0.0.0.0', port=port)