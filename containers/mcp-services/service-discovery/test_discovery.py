# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station

import unittest
from unittest.mock import patch, MagicMock
import json
import sys
import os

# Add app directory to path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from app import app, fetch_tools_from_service

class TestServiceDiscovery(unittest.TestCase):
    def setUp(self):
        self.app = app.test_client()
        self.app.testing = True

    @patch('app.requests.get')
    def test_fetch_tools_success(self, mock_get):
        # Mock successful response from an MCP service
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "tools": [
                {
                    "name": "test_tool",
                    "description": "A test tool",
                    "inputSchema": {"type": "object"}
                }
            ]
        }
        mock_get.return_value = mock_response

        tools = fetch_tools_from_service("http://test-service:8000")
        self.assertEqual(len(tools), 1)
        self.assertEqual(tools[0]['name'], "test_tool")

    @patch('app.requests.get')
    def test_fetch_tools_failure(self, mock_get):
        # Mock failed response
        mock_get.side_effect = Exception("Connection refused")
        
        tools = fetch_tools_from_service("http://test-service:8000")
        self.assertEqual(tools, [])

    @patch('app.fetch_tools_from_service')
    def test_mcp_config_endpoint(self, mock_fetch):
        # Mock the fetch function to return a consolidated list
        mock_fetch.side_effect = [
            [{"name": "tool1"}], # service 1
            [{"name": "tool2"}]  # service 2
        ]
        
        # We need to mock the SERVICES list in app.py, but it's hardcoded or env var.
        # For this test, we assume app.py will be modified to use a list we can control or mock.
        # Instead of full integration, let's just test that the endpoint returns JSON.
        
        with patch('app.MCP_SERVICES', [{"name": "s1", "url": "http://s1"}, {"name": "s2", "url": "http://s2"}]):
            response = self.app.get('/mcp-config')
            self.assertEqual(response.status_code, 200)
            data = json.loads(response.data)
            self.assertIn("mcpServers", data)

if __name__ == '__main__':
    unittest.main()
