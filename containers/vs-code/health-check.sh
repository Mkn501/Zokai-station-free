#!/bin/bash
# Health check for VS Code Server
if curl -f http://localhost:8080 > /dev/null 2>&1; then
    exit 0
else
    exit 1
fi