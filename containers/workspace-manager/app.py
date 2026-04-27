# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return {'status': 'ok', 'service': 'workspace-manager'}, 200

@app.route('/workspaces')
def workspaces():
    # Basic workspaces endpoint
    return jsonify({
        'service': 'workspace-manager',
        'version': '1.0.0',
        'status': 'running',
        'workspaces': []
    })

@app.route('/bridge/kilo-prompt', methods=['POST', 'OPTIONS'])
def kilo_prompt():
    from flask import request
    if request.method == 'OPTIONS':
        return '', 204
    
    data = request.get_json()
    if not data or 'prompt' not in data:
        return jsonify({'error': 'Missing prompt'}), 400
    
    # Target path in the shared volume
    gemini_dir = '/workspaces/.gemini'
    os.makedirs(gemini_dir, exist_ok=True)
    
    import json
    import time

    target = os.path.join(gemini_dir, 'kilo-prompt.json')
    
    with open(target, 'w') as f:
        json.dump({
            'prompt': data['prompt'],
            'timestamp': time.time()
        }, f)
    
    return jsonify({'status': 'ok', 'message': 'Prompt dropped'}), 200


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 9000))
    app.run(host='0.0.0.0', port=port)