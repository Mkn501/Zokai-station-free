# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
from fastmcp import FastMCP
import inspect

print(inspect.signature(FastMCP.run))
print(inspect.getdoc(FastMCP.run))
