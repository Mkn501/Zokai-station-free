# Contributing to Zokai Station

Thank you for your interest in contributing to Zokai Station! This document outlines the process and requirements for contributing.

## Current Status

Zokai Station is in **pre-launch / invite-only** stage. External contributions are not yet accepted. This document is provided for transparency and will be activated when the project opens to community contributions.

## Contributor License Agreement (CLA)

**A CLA is required before any external pull request can be merged.**

By signing the CLA, you agree that:
1. You grant the project maintainer (Minh Khoa Nguyen) a perpetual, worldwide, non-exclusive, royalty-free license to use, modify, and sublicense your contributions
2. You retain copyright over your own contributions
3. The maintainer retains the right to dual-license the project (e.g., AGPL-3.0 for open source + commercial license for enterprise)

> **Why a CLA?** Without a CLA, contributor code remains under its original license and cannot be relicensed. This would block future commercial licensing options. This is the same approach used by MongoDB, Elastic, and HashiCorp.

## How to Contribute

### Reporting Issues

1. Check existing issues to avoid duplicates
2. Use the issue template (when available)
3. Include: OS, Docker version, steps to reproduce, expected vs. actual behavior
4. Attach relevant logs: `docker compose logs <service-name> | tail -50`

### Submitting Code

1. **Fork** the repository
2. **Branch** from `main`: `git checkout -b feat/your-feature`
3. **Follow coding standards** (see below)
4. **Test** your changes locally
5. **Submit PR** with a clear description of what and why

### Commit Style

Use conventional commit prefixes:
- `feat:` — New feature
- `fix:` — Bug fix
- `chore:` — Maintenance, dependencies
- `docs:` — Documentation only
- `test:` — Adding or updating tests

### Coding Standards

#### Python
- Python 3.11+, PEP 8 compliant
- Type hints required on all function signatures
- `logging.getLogger(__name__)` — never `print()` for operational output
- Absolute imports only
- Every file must include the SPDX header:
  ```python
  # SPDX-License-Identifier: AGPL-3.0-or-later
  # Copyright (c) 2026 Minh Khoa Nguyen — Zokai™ Station
  ```

#### Shell Scripts
- `set -eo pipefail` at the top
- POSIX-compatible where possible

#### Docker
- Multi-stage builds where applicable
- Non-root users for all services
- Resource limits enforced

### What NOT to Modify

Unless explicitly discussed in the issue:
- `docker-compose.yml` / `docker-compose.cloud.yml`
- `memory-bank/` — human/AI context files
- `scripts/mcp_bridge.py` — core infrastructure
- `secrets/` — OAuth tokens and credentials

## AI-Assisted Contributions

We welcome AI-assisted contributions. If you used AI tools to generate your code:
- This does not affect acceptance — AI-generated code is evaluated on the same quality standard as human-written code
- You must still review and understand the code you submit
- See `AI_CONTRIBUTIONS.md` for how the project itself uses AI

## License

By contributing, you agree that your contributions will be licensed under the **AGPL-3.0** license that covers the project, subject to the CLA terms above.
