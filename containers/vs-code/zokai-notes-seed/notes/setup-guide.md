---
id: setup-guide
title: Setup Guide
desc: >-
  Step-by-step setup to get Zokai Station fully operational.
  API key, codebase indexing, and Google account connection.
updated: '2026-04-04T00:00:00.000Z'
created: '2026-04-04T00:00:00.000Z'
tags:
  - setup
  - getting-started
  - onboarding
---

# Setup Guide

Get your Zokai Station fully operational in 3 steps.

> **Tip**: Switch to **Zokai Guide** mode in Kilo (the AI panel on the right) for interactive help at any time.

---

## Step 1: Enter Your API Key

Kilo Code needs an AI provider key to work. We recommend **OpenRouter** (free models available).

1. Get a free key at [openrouter.ai/keys](https://openrouter.ai/keys)
2. In VS Code, click the **gear icon** (⚙️) at the bottom of the Kilo panel
3. Paste your OpenRouter API key in the **API Key** field
4. Click **Save**

> **Note**: The free GLM-4.5 Air model is pre-configured. No credit card needed.

---

## Step 2: Start Codebase Indexing

This enables semantic search across your workspace files (notes, docs, code).

1. In the Kilo panel settings, find **Codebase Indexing**
2. Click **"Start Indexing"**
3. Indexing starts immediately. A medium workspace takes 2–5 minutes.
4. You'll see a progress indicator in the status bar

> **Important**: Indexing is required for Kilo to understand your workspace. Without it, Kilo can only see files you explicitly open.

> **Limitation (Free tier)**: Files larger than ~300KB are skipped. This covers most notes and code, but large PDFs or Excel files won't be searchable. Zokai Pro includes Deep Index for unlimited file sizes.

---

## Step 3: Connect Google Account (Optional)

Connect Gmail and Calendar to see your inbox and events in the Dashboard.

1. Click the **compass icon** (🧭) in the Activity Bar → **Dashboard**
2. Look for the **"Connect Google Account"** button
3. Follow the OAuth consent flow in your browser
4. Once connected, emails start indexing automatically (10-15 min for first sync)

> **Note**: Your data stays on your machine. Emails are indexed locally into Qdrant for semantic search.

---

## What's Next?

- **Explore notes**: Your knowledge base lives in `notes/`. Type `[[` to create wiki-links between notes.
- **Ask Kilo anything**: Switch to **Zokai Guide** mode and ask "what can I do?" for a personalized overview.
- **Use templates**: `Ctrl+Shift+P` → "Zokai: Create New Note from Template"
- **View your graph**: `Ctrl+Alt+G` to see connections between notes.

→ Back to [[1.Welcome]] | Learn more about [[getting-started|Zokai Notes]]

#setup #onboarding
