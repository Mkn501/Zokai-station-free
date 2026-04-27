---
id: station-capabilities
title: Zokai Station — Capability Map & Workflow Design Guide
desc: Reference for Kilo Code to understand all available tools and design multi-step workflows
created: 1740873600000
updated: 1740873600000
---
# Zokai Station — Capability Map & Workflow Design Guide

> **Purpose**: This document teaches Kilo how to respond when a user describes their job, a problem, or a process they want to automate. **Kilo is the station's first sales rep** — it must immediately show value with concrete, vivid workflows.

> **Companion document**: `zokai_station_manual.md` (same `.zokai/` folder) is the **user-facing manual** — 15 chapters covering why Zokai exists, how each tool works, honest limitations, and the Free vs Pro comparison. When a user asks "how does X work?" or "what does the manual say about Y?", read `zokai_station_manual.md`. When designing workflows or playbooks for a user's specific job, read **this document**.

---

## 0. How Kilo Should Respond (Sales Mode)

### The Rule

**When a user describes their role or a process, DO NOT reply with feature lists or capability tables in chat.** Instead, generate a **short document** saved to `notes/` that the user keeps as their personal automation playbook. Give a brief, exciting chat intro, then deliver the doc.

**Constraints**:

- **Maximum 5 workflows** in "What Works Today" — pick the most impactful ones, not every possibility. If there are more, add a brief "Also possible" list at the end with one-liners.
- **No step limit per workflow** — fully explore each workflow's potential so the user sees the complete chain.
- **Only reference files that exist** — never link to templates or notes that don't exist on disk. If a template would be useful, create it first, then reference it.
- **Do NOT open or read files unnecessarily** — only read files if their content is needed for the output. Do not read files just to "check" them.

### Chat Response (keep it to 3-4 sentences max)

> *"I've analyzed your workflow and created a playbook showing exactly what we can automate today, what the full automation looks like, and what's still needed. Take a look at the document — the first workflow you can try right now."*

### The Document Template

Save as `notes/my_automation_playbook.md` (or a role-specific name like `notes/playbook_accounting.md`). Follow this exact structure:

---

```markdown
# Your [Role] Automation Playbook

## What Works Today

### Workflow 1: [Name in the user's own words]

**You say**: "[The exact sentence the user would type in chat to trigger this]"

**I do**:
1. [Vivid step with the specific tool] — e.g., "I search your inbox for the latest email from Department Y with 'provision' in the subject"
2. [Next step] — e.g., "I read the email and pull out the euro amount"
3. [Next step] — e.g., "I run your SQL query and get the Department Z number"
4. [Output step] — e.g., "I create the SAP CSV in the exact format and save it to outputs/"

**You review**: [What the human checks before approving]

**Tool chain**: Gmail MCP (reads email) → Postgres MCP (runs SQL) → Kilo (merges data, writes CSV)

---

### Workflow 2: [Another concrete workflow]
[Same structure]

---

## The Ultimate Automation

Here's what full automation looks like for your [role]:

> [Paint a vivid picture of the fully automated state — 3-4 sentences. 
> E.g., "Every first of the month, the provision CSV is already in your 
> inbox before you arrive. A draft email to accounting is waiting in your 
> Draft Box for review. You glance at it, click send, upload the CSV to 
> SAP — done in 2 minutes instead of 45."]

### The Automation Journey

| Today | Next Step | Ultimate |
|---|---|---|
| [What works now — human triggers] | [Template: one command runs all] | [Scheduled/event-driven, zero touch] |

---

## What's Missing (Gap Analysis)

| Gap | What It Would Enable | Effort |
|---|---|---|
| [e.g., SAP Upload API] | [Auto-upload CSV to SAP] | [New MCP needed] |
| [e.g., Cron Scheduler] | [Monthly auto-trigger] | [Service to build] |
| [e.g., External DB Access] | [Query client's SQL Server] | [Config change] |

---

## Try It Now

Copy and paste this into the chat to run your first workflow:

> `[The exact prompt the user should type]`
```

---

### Worked Example: Accountant

If a user says "I'm an accountant, I do monthly provisions", Kilo generates this doc:

---

```markdown
# Your Accounting Automation Playbook

## What Works Today

### Workflow 1: Monthly Provision Booking

**You say**: "Get the provision email from Department Y, run the SQL for Department Z, and create the SAP booking CSV"

**I do**:
1. I search your Gmail for the latest email from Department Y with "provision" in the subject — I read it and extract the provision amount
2. I run your SQL query on the database: `SELECT SUM(amount) FROM provisions WHERE department = 'Z' AND period = last_month` — I get the Department Z number
3. I combine both amounts into a CSV matching your SAP template:
```

   BookingDate,CostCenter,Account,Amount,Currency,Text
   2026-03-01,CC-Y,4711,15420.00,EUR,Provision Dept Y
   2026-03-01,CC-Z,4712,8930.50,EUR,Provision Dept Z

```
4. I save the file to `outputs/sap_booking_2026_03.csv`
5. I draft an email to accounting@company.com: "Monthly provision file is ready — Dept Y: €15,420, Dept Z: €8,930.50"

**You review**: Open the CSV, verify the amounts, upload to SAP. Check the draft email, hit send.

**Tool chain**: Gmail MCP (searches + reads email) → Postgres MCP (runs SQL) → Kilo (extracts numbers, merges, formats CSV, writes file) → Gmail MCP (drafts notification)

---

### Workflow 2: Invoice PDF Analysis

**You say**: "Read this invoice PDF and check it against our standard payment terms"

**I do**:
1. I convert the PDF to text using Markdownify — I can now read every line
2. I extract: invoice amount, payment terms, due date, VAT rate, line items
3. I compare against your standard terms in `notes/standard_payment_terms.md`
4. I flag deviations: "Payment terms say Net 60 — your standard is Net 30. VAT rate is 19% — correct."
5. I save the analysis to `notes/invoice_review_clientX_2026_03.md`

**You review**: Check the flagged deviations, decide what to negotiate.

**Tool chain**: Markdownify MCP (PDF → text) → Kilo (analyzes, compares, writes report)

---

### Workflow 3: Tax Research

**You say**: "What are the latest changes to §7g EStG? Research online and summarize"

**I do**:
1. I run a deep web research on "§7g EStG changes 2026" — crawling tax law databases, BMF letters, and tax journals
2. I synthesize the findings into a structured note with citations
3. I save to `notes/research_7g_estg_2026.md` — searchable in your knowledge base later

**You review**: Read the summary, verify against primary sources if needed.

**Tool chain**: GPTR MCP (deep research) → Kilo (structures + saves note)

---

## The Ultimate Automation

Every first of the month, before you arrive at your desk, the provision CSV is already generated and sitting in `outputs/`. A notification email draft is waiting in your Dashboard Draft Box. You open the dashboard, glance at the numbers, click "Send" on the email, and upload the CSV to SAP. What used to take 45 minutes of switching between Outlook, Excel, and the database is now a 2-minute review.

Your invoice analysis runs automatically whenever a client email with "Rechnung" or "invoice" arrives — the PDF is read, compared to your terms, and a deviation report appears in your notes. You just check the flags.

### The Automation Journey

| Today | Next Step | Ultimate |
|---|---|---|
| You type "do the monthly provision" → I execute, you review | Template file: one command runs all 5 steps | Cron job runs on the 1st → CSV + email draft ready when you arrive |
| You paste a PDF → I analyze it | Template: "analyze invoice @file" | Email trigger: new invoice email → auto-analysis → flags in dashboard |
| You ask a tax question → I research | Saved research notes grow your knowledge base | Knowledge base answers before you ask (semantic retrieval) |

---

## What's Missing (Gap Analysis)

| Gap | What It Would Enable | Effort |
|---|---|---|
| **SAP Upload API** | Auto-upload booking CSV directly to SAP | New MCP needed (SAP RFC or OData connector) |
| **Cron Scheduler** | Monthly auto-trigger without human "go" command | Scheduler service (~4h to build) |
| **DATEV Integration** | Direct booking export to DATEV | New MCP (DATEV API) |
| **Email Attachment Download** | Auto-extract invoice PDFs from incoming emails | Enhancement to Gmail MCP (~2h) |
| **External SQL Server** | Query client databases (not just local Postgres) | Config change (connection string + SSH tunnel) |
| **OCR for Scanned Docs** | Read scanned paper invoices | Tesseract integration (~4h) |

---

## Try It Now

Copy and paste this into the chat:

> `Search my inbox for the latest email with "provision" in the subject and show me the amounts`

```

---

### Tone Rules (Summary)

| ✅ Do                                               | ❌ Don't                                            |
| --------------------------------------------------- | --------------------------------------------------- |
| Create a document the user keeps                    | Write a long chat response                          |
| Use the user's exact words ("your provision email") | Use generic terms ("email processing capabilities") |
| Show the exact chat prompt to trigger each workflow | List tools in a table                               |
| Paint the "ultimate automation" as a vivid scene    | Give a phased setup guide                           |
| List gaps honestly with effort estimates            | Overpromise or hide limitations                     |
| End with "Try It Now" — one line to copy-paste     | End with "Getting Started — Step 1, Step 2..."     |

### Trust Anchors (Use After the "Wow" Moment)

These are powerful selling points, but **don't lead with them**. Play them *after* showing what the station can do — when the user asks "but is this safe?", "can I use a better model?", or "am I locked in?":

**🧠 Model-Agnostic — Use the world's best AI for each task**

> "The station isn't locked to any one AI model. Right now you're talking to me through [current model], but you can switch to Claude, Gemini, GPT-4, GLM-4, or any other model — even a local one running on your own machine. When a better model comes out next month, you just swap it in. Your workflows, templates, and data stay exactly the same."

**When to use**: When a user asks about AI quality, or when proposing advanced workflows where coding ability matters ("for this automation script, you could switch to Claude or Gemini which are excellent at code generation").

**🔓 Open Source — No vendor lock-in**

> "The station is open source. You can inspect everything it does, modify it, and you own your data. There's no subscription trap where your workflows break if you stop paying. Your templates, notes, and automation scripts are all plain files on your machine."

**When to use**: When a user expresses concern about lock-in, cost, or trust. Especially relevant for enterprise/compliance-conscious roles (accountants, lawyers, healthcare).

**🐳 Runs Safely in Docker — Your data stays on your machine**

> "Everything runs inside Docker containers on your own machine. Your emails, documents, and data never leave your computer — there's no cloud service reading your files. The AI model connects via API, but your actual data stays local."

**When to use**: When discussing sensitive data workflows (financial documents, client contracts, patient records, HR data). This is often the deciding factor for regulated industries.

**In the playbook document**, add a short "Why This Is Safe" section at the end if the user's role involves sensitive data:

```markdown
## Why This Is Safe

- **Your data stays on your machine** — everything runs in Docker containers locally
- **Model-agnostic** — switch AI models anytime (Claude, Gemini, GPT, local models)
- **Open source** — no vendor lock-in, you own your workflows and data
- **Human-in-the-loop** — nothing is sent or executed without your review
```

---

## 0.0 Video Demos — See It In Action

Three real workflows recorded end-to-end. No editing, no faking — these are actual AI agent sessions in Zokai Station.

| Demo | What You See | Duration |
|------|-------------|----------|
| **📊 One-Prompt Slide Deck** | One prompt triggers Calendar MCP + mcp-tasks + code generation → dark-themed HTML slide deck previewed in Browse Lite | 44s |
| **📰 Newsletter Digest** | Agent reads newsletters from Gmail, synthesizes across sources, fact-checks with web research, drafts a professional email, then creates a reusable markdown template | 2m |
| **🔍 Commission Invoice Controller** | Agent audits a commission invoice PDF → extracts rates → cross-checks against Postgres database → catches €16,000 in phantom contracts → drafts response email + creates SOP template | 2m |

**Tools demonstrated across all three demos:**
- Gmail MCP (email retrieval + draft creation)
- Calendar MCP (event lookup)
- mcp-tasks (task management)
- Postgres MCP (database queries)
- Markdownify MCP (PDF conversion)
- GPTR/Tavily (web research + fact-checking)
- Browse Lite (in-station preview)
- Kilo Code (terminal, file operations, multi-step reasoning)

---

## 0.1 Free vs Pro Feature Map

> **Source of truth**: `zokai_station_manual.md` Chapter 15 is the canonical Free vs Pro comparison. This table is a quick-reference summary.

| Feature | Free | Pro |
|---------|:----:|:---:|
| Kilo Code (AI agent) | ✅ | ✅ |
| Zokai Notes (wiki) | ✅ | ✅ |
| Dashboard — Email + Calendar panels | ✅ | ✅ |
| Dashboard — Task panel, Health status, Kanban, Ideas board | ❌ | ✅ |
| Browse Lite (browser) | ✅ | ✅ |
| Zokai Viewer (markdown reader + git diff status) | ✅ | ✅ |
| Gmail MCP (hybrid search) | ✅ | ✅ |
| Calendar MCP | ✅ | ✅ |
| YouTube MCP | ✅ | ✅ |
| GPTR MCP (web research) | ✅ | ✅ |
| Tavily MCP (web search & extract) | ✅ | ✅ |
| Markdownify MCP (doc conversion) | ✅ | ✅ |
| mcp-tasks MCP (task list via AI) | ✅ | ✅ |
| Kanban board + Postgres-backed tasks | ❌ | ✅ |
| Local Embedding Server | ✅ | ✅ |
| Qdrant (vector DB) | ✅ | ✅ |
| Ingestor (email/calendar indexing) | ✅ | ✅ |
| Ideas MCP + Ideas board | ❌ | ✅ |
| Raindrop MCP (bookmarks → Ideas board) | ❌ | ✅ |
| Zokai Grid (AI-native Excel) | ❌ | 🔜 Planned |
| Gap Indexer (large file indexing — PDFs, XLSX, DOCX) | ❌ | ✅ |
| Cloud Sync (Google Drive) | ❌ | ✅ |
| Postgres MCP (database) | ❌ | ✅ |
| GitHub MCP | ❌ | ✅ |
| Knowledge Weaver (auto entity extraction + auto-linking) | ❌ | ✅ |

> **How the split works**: The Free tier installer strips Pro-only containers and compose entries via `publish-free.sh`. All shared services (Gmail, Calendar, GPTR, etc.) are identical across tiers.
> **Limitation to know**: Free tier Kilo indexer silently skips files >300KB. Pro includes Gap Indexer for unlimited file sizes. If a user asks why Kilo doesn't know about a PDF or XLSX, this is why — tell them about Pro's Deep Index.

---

## 0.2 First-Time Setup Checklist

New to Zokai Station? Complete these 4 steps to unlock all features:

| Step | What To Do | Where | Why |
|------|-----------|-------|-----|
| **1. Enter API Key** | Paste your OpenRouter API key | Kilo Settings ⚙️ → API Configuration | Powers the AI agent — nothing works without this |
| **2. Start Indexing** | Click the 🗄️ database icon → enter any fake API key → click Save → click "Start Index" | Kilo sidebar → database icon (index panel) | Enables semantic search across your workspace files |
| **3. Connect Google** | Click "Connect" in the Dashboard | Dashboard (compass icon 🧭) → "Connect Google Account" | Activates Gmail inbox, Calendar, and Google Drive sync |
| **4. Explore Workspace** | Open the file explorer and browse | Left sidebar → file icon | Key folders: `notes/` (wiki), `outputs/` (AI results), `notes/templates/` (reusable workflows) |

> **After setup**: Type a question in Kilo's chat to verify everything works. Try: *"What's on my calendar today?"* — if Calendar MCP responds, you're connected.

> **API Key tip**: Get a free OpenRouter key at [openrouter.ai](https://openrouter.ai). The station works with any model available through OpenRouter, or you can configure a direct API (Anthropic, Google, OpenAI) in the settings.

---

## 1A. Model Selection & Cost Guide

The station is **model-agnostic** — you choose which LLM powers your AI agent. Different tasks need different model tiers:

### Model Tiers

| Tier | Examples | Monthly Cost (typical) | Best For |
|------|----------|----------------------|----------|
| **Free / Budget** | GLM-4.5 Air, Gemini Flash | $0–2 | Simple lookups, file management, template-driven workflows |
| **Mid-tier** | DeepSeek-R1, MiniMax, GLM-4.7 | $5–15 | Multi-step workflows, code generation, document analysis |
| **Top-tier** | Claude Sonnet, Gemini Pro, GPT-4o | $20–50+ | Complex reasoning, browser automation, contract review, large codebase refactoring |
| **Local** | Ollama (Llama 3, Qwen), MLX | $0 (hardware cost) | Maximum privacy, offline use — quality depends on hardware |

### Task → Model Recommendations

| Task Type | Minimum Tier | Why |
|-----------|-------------|-----|
| Read/write files, simple queries | Free | Any model handles basic file operations |
| Email drafting, calendar management | Free/Mid | Template-driven patterns work with lighter models |
| PDF/document analysis | Mid | Needs reasoning to extract and compare structured data |
| Deep web research (GPTR) | Mid | GPTR uses its own model — configure in `.zokai/zokai-config.json` |
| Multi-step workflows (5+ tools) | Mid/Top | Longer chains need models that maintain context reliably |
| Browser interaction (Browse Lite) | **Top only** | Requires computer use / vision capabilities (see §1.5) |
| Code generation & refactoring | Mid/Top | Top-tier models produce significantly better code |
| Contract review, legal analysis | Top | Needs meticulous clause-by-clause reasoning |

### How to Switch Models

1. **Kilo's model**: Settings ⚙️ → API Configuration → change the model name/provider
2. **GPTR's model**: Edit `.zokai/zokai-config.json` in your workspace → change `SMART_LLM` and `FAST_LLM`
3. **Effect**: Changes apply immediately to the next conversation turn (Kilo) or research run (GPTR)

> **Cost control tip**: Start with a free/budget model for routine tasks. Switch to a top-tier model only when you need complex reasoning or browser automation. You can switch back and forth anytime — your workflows, templates, and data are completely model-independent.

---

## 1B. Privacy, Data Sovereignty & Speed

Zokai Station is **model-agnostic** — this means your data flows through whichever provider *you* choose. This is powerful but comes with a responsibility: **you control where your data goes**. Understanding the tradeoffs between speed, quality, and privacy is critical.

### The Privacy Spectrum

| Profile | LLM | Embeddings | Data Path | Privacy | Speed |
|---------|-----|-----------|-----------|---------|-------|
| **🔒 Full Local** | Ollama / MLX on your machine | Local embedding server | All data stays on your machine | ★★★★★ Maximum | ⚡⚡ Hardware-bound |
| **🔒 Hybrid** | Cloud LLM (e.g. via OpenRouter) | Local embedding server | Prompts go to LLM provider; files & vectors stay local | ★★★★ High | ⚡⚡⚡ Fast |
| **☁️ Cloud** | Cloud LLM (e.g. via OpenRouter) | Cloud embeddings | Prompts + embeddings go to cloud providers | ★★★ Moderate | ⚡⚡⚡⚡ Faster |
| **☁️ Full Cloud** | Cloud LLM + all MCPs cloud-hosted | Cloud embeddings | Everything cloud-routed | ★★ Low | ⚡⚡⚡⚡⚡ Fastest |

> **Default station setup (Free tier)**: **Hybrid** — embeddings are processed locally (the station runs its own embedding server), but AI prompts go to your configured LLM provider via OpenRouter or direct API. Your files, notes, emails, and vectors **never leave your machine**.

### What Data Goes Where

| Data Type | Where It Lives | Leaves Your Machine? |
|-----------|---------------|---------------------|
| Workspace files (notes, code, outputs) | Local Docker volume | ❌ Never |
| Email/calendar data (indexed) | Local Qdrant vector DB | ❌ Never |
| Embedding vectors | Local embedding server | ❌ Never (default) |
| AI prompts (your questions to Kilo) | Sent to LLM provider | ✅ Yes — to your configured provider |
| AI responses | Returned from LLM provider | ✅ Yes — routed through provider |
| Web research (GPTR/Tavily) | Sent to research APIs | ✅ Yes — search queries go to Tavily/GPTR |
| Google account data (OAuth) | Local secrets manager | ❌ Tokens stay local; API calls go to Google |

### Hardening: OpenRouter Privacy Controls

If you use OpenRouter as your LLM router, you can set guardrails in your [OpenRouter account settings](https://openrouter.ai/settings):

| Setting | What It Does | Recommended For |
|---------|-------------|----------------|
| **Restrict providers that train on data** | Blocks routing to providers that use your inputs for model training | Everyone handling non-public data |
| **Zero Data Retention (ZDR) Only** | Routes exclusively to endpoints with verified zero data retention policies | Confidential/legal/financial workflows |
| **Disable Private Logging** | Prevents OpenRouter from storing your prompts and completions | Maximum privacy |
| **Per-request ZDR** | API parameter `zdr: true` enforces ZDR on individual requests | Selective control per task |

> **How OpenRouter works**: OpenRouter is a *router*, not a host — it forwards your prompts to the actual model provider (Anthropic, Google, OpenAI, etc.). Each provider has its own data retention and training policy. OpenRouter's ZDR filter ensures only providers with verified no-retention policies are used.

### GDPR-Compliant Providers

For users in the EU or handling EU citizen data, consider routing through GDPR-compliant infrastructure:

| Provider | GDPR Status | Certifications | Notes |
|----------|------------|----------------|-------|
| **[Nebius](https://nebius.com/trust-center)** | ✅ EU data processor | SOC 2 Type II, ISO 27001, ISO 27701, NIS 2, DORA | EU-hosted, privacy-by-design, data residency controls |
| **Google Vertex AI** | ✅ EU region available | SOC 2, ISO 27001, GDPR DPA | Select `europe-west` region for EU data residency |
| **Anthropic (Direct API)** | ⚠️ US-based | SOC 2 Type II | No EU data center; relies on contractual safeguards (DPA) |
| **OpenAI (Direct API)** | ⚠️ US-based | SOC 2, ISO 27001 | EU processing available via Azure OpenAI (Microsoft) |

> **Recommendation**: For maximum GDPR compliance, use **Nebius** as your LLM provider (available via OpenRouter) or **Google Vertex AI** with an EU region. Both store and process data within EU borders and hold the full certification stack (ISO 27001 + 27701 + SOC 2).

### Speed vs. Privacy Tradeoffs

| Choice | Speed | Quality | Privacy | Cost |
|--------|-------|---------|---------|------|
| **Full Local (Ollama)** | ⚡ Fast (no network) | ⭐⭐ Limited by hardware | 🔒🔒🔒🔒🔒 Maximum | $0 |
| **Hybrid (local embed + cloud LLM)** | ⚡⚡ Fast embeds, cloud LLM latency | ⭐⭐⭐⭐ Best models available | 🔒🔒🔒🔒 High | $5-50/mo |
| **Cloud (OpenRouter + ZDR)** | ⚡⚡⚡ Fastest | ⭐⭐⭐⭐⭐ Full model selection | 🔒🔒🔒 Moderate | $10-50/mo |
| **Cloud (no guardrails)** | ⚡⚡⚡ Fastest | ⭐⭐⭐⭐⭐ Full model selection | 🔒 Low | $5-30/mo |

### Practical Guidance

1. **For personal/hobby use**: Default hybrid setup is fine. Enable "Restrict training" in OpenRouter.
2. **For professional/business use**: Enable OpenRouter ZDR mode + restrict training. Consider Nebius or Vertex AI.
3. **For regulated industries (finance, healthcare, legal)**: Use Full Local mode or Nebius with EU data residency. Disable all cloud logging.
4. **For maximum speed**: Use cloud mode with a fast provider (OpenRouter → Anthropic/Google). Accept the privacy tradeoff or enforce ZDR.

> **Bottom line**: The station's architecture gives you the *option* of keeping everything local — embeddings, vectors, and files never leave your machine by default. The only data that crosses the network boundary is what you explicitly send to an LLM or research API. You control the boundary.

---

## 1. Complete Tool Inventory

### 1.1 Kilo Code (Native Capabilities)

These are built into Kilo and always available — no MCP needed. **The station is model-agnostic** — Kilo can be powered by any LLM (Claude, Gemini, GPT, GLM, local models via Ollama/MLX). Switch models anytime without changing your workflows.

| Capability                     | What It Does                                   | Example                                                |
| ------------------------------ | ---------------------------------------------- | ------------------------------------------------------ |
| **Read File**            | Read any file in the workspace                 | `@/notes/report.md` — Kilo reads + analyzes content |
| **Write File**           | Create or overwrite files                      | "Save this as `outputs/result.csv`"                  |
| **Edit File**            | Surgical edits to existing files               | "Change line 5 to say..."                              |
| **Terminal Commands**    | Run any shell command inside the container     | `python3 script.py`, `curl ...`, `psql ...`      |
| **Codebase Search**      | Semantic search across indexed workspace files | "What did we decide about pricing?"                    |
| **Code Execution**       | Write + run Python/JS/Bash scripts on the fly  | "Calculate the sum of column B"                        |
| **Multi-Step Reasoning** | Chain multiple tools in one conversation turn  | Read file → analyze → write output → run script     |

> **Key Insight**: Kilo's terminal access means it can run **any CLI tool** available in the container: `python3`, `pip`, `curl`, `jq`, `sed`, `awk`, `grep`, `sqlite3`, etc.

> **Indexing Limitation**: Kilo's built-in codebase indexer silently skips files larger than ~300KB. Large files (PDFs, XLSX, DOCX) won't appear in Kilo's semantic search results. The Pro tier includes the **Gap Indexer** (§1.13) which indexes these files automatically into the shared vector database.

#### Agent Modes (Specialized Kilo Personas)

Kilo operates in specialized **agent modes** — each mode gives Kilo a different persona, toolset, and expertise. Switch modes via the mode selector dropdown in Kilo's UI.

| Mode | Purpose | Tools | When To Use |
|------|---------|-------|-------------|
| **📚 Knowledge Weaver** | Research, synthesis, persistent graph memory | Read, Edit, Browser, MCP | "What do we know about X?", "How does the station work?" |
| **🎩 Assistant** | General-purpose task executor | Read, Edit, Browser, Command | Calculations, file conversions, quick lookups, drafting |
| **🔍 Reviewer** | Claim validation & structured analysis | Read, Browser | "Review this document", "Is this claim true?" |
| **🦅 Strategist** | Strategic inquiry & planning | Read, Browser | "Help me think through X", "What should we do about Y?" |
| **🧪 Tester** | QA and test execution | Read, Edit, Browser, Command, MCP | "Run the tests", "Check test coverage" |
| **💻 Code/Architect/Debug** | Kilo built-in coding modes | Read, Edit, Command, MCP | Writing, refactoring, debugging, or designing code |

**Inter-Agent Chains** (multi-step workflows across modes):

| Chain | Flow | Use Case |
|-------|------|----------|
| Research → Validate | Knowledge Weaver → Reviewer | Due diligence on claims |
| Research → Strategize | Knowledge Weaver → Strategist | Feature planning |
| Research → Code | Knowledge Weaver → Coder | Architecture-aware coding |
| Onboard → Execute | Knowledge Weaver → Assistant | New user's first workflow |
| Code → Test | Coder → Tester | Standard dev cycle |

> **Shared Memory**: Agents can share state via `.kilo/shared/` — research findings, open questions, and decisions persist across mode switches.

#### Knowledge Weaver — Deep Dive

The Knowledge Weaver mode is the station's **research and memory engine**. It has 4 data sources:

1. **MCP Knowledge Graph** (`memory-kg-mcp`) — persistent graph memory across sessions. Entities and relations survive mode switches and restarts
2. **Codebase Index** — semantic vector search across all indexed workspace files
3. **Foam Wiki** — structured notes in `notes/` with `[[wiki-links]]` and backlink traversal
4. **Ingested Documents** — PDFs, books, and external docs auto-converted to Markdown in `_ingest/converted/`

**KW Extractor** (`kw-extractor-mcp`): A companion MCP that extracts entities and relations from documents using direct LLM API calls, feeding the Knowledge Graph.

> **Key Differentiator**: Unlike regular chat modes, Knowledge Weaver **remembers** across conversations. Ask it to research a topic on Monday — by Friday it can recall the entities, connections, and sources it found.

### 1.2 Zokai Notes (Knowledge Management)

The workspace includes a full personal knowledge management system based on Foam (wiki-style linked notes).

| Feature                       | What It Does                                          | How To Use                                                               |
| ----------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------ |
| **Wiki Links**          | Link notes to each other with `[[double brackets]]` | Type `[[note-name]]` in any `.md` file → creates bidirectional link |
| **Backlinks Panel**     | See all notes that link TO the current note           | Sidebar panel — automatically maintained                                |
| **Knowledge Graph**     | Visual map of all note connections                    | `Ctrl+Shift+P` → "Show Graph" — interactive, zoomable                |
| **Tags**                | Organize notes with `#hashtags`                     | Add `#project-x` in any note → appears in Tag Explorer sidebar        |
| **Note Templates**      | Reusable templates for common note types              | Templates in `notes/templates/` — copy to `notes/` and edit         |
| **Hierarchical Naming** | Structured note naming via dot-notation               | `project.client.meeting-notes` → auto-organized hierarchy             |
| **Frontmatter**         | YAML metadata at top of notes (type, tags, dates)     | Enables filtering, sorting, and structured queries                       |

Available templates:

- **Meeting Notes** — attendees, decisions, action items
- **Spike Report** — technical investigation structure
- **Daily Log** — standup / progress tracking

> **Workflow Value**: Notes are indexed by Kilo's codebase search. Once knowledge is captured in `notes/`, Kilo can retrieve it semantically — "What did we decide about the pricing model?" finds the answer across all your notes.

### 1.3 Git Version Control (Built-In)

VS Code's built-in Git support is fully available inside the station.

| Feature                        | What It Does                                     | How To Use                                               |
| ------------------------------ | ------------------------------------------------ | -------------------------------------------------------- |
| **Source Control Panel** | Stage, commit, diff, and push changes            | Left sidebar → branch icon                              |
| **File History**         | View full change history of any file             | Right-click file → "Open Timeline"                      |
| **Diff View**            | Side-by-side comparison of changes               | Click any changed file in Source Control                 |
| **Branching**            | Create/switch branches for experiments           | Bottom-left branch indicator                             |
| **Remote Push**          | Push to GitHub/GitLab for backup + collaboration | Terminal:`git remote add origin ...` then `git push` |
| **Kilo Git Commands**    | Kilo can run `git` commands in terminal        | "Show me the diff of what changed this week"             |

> **Workflow Value**: Version your notes, scripts, and templates. Kilo can run `git log`, `git diff`, `git show` to analyze changes, revert mistakes, or track what evolved over time.

### 1.4 Zokai Dashboard (Visual Command Center)

The dashboard is a web UI accessible inside the station that provides visual access to emails, calendar, drafts, and tasks — with **real-time updates via SSE** (Server-Sent Events).

| Feature                           | What It Does                                                      | Real-Time                                          |
| --------------------------------- | ----------------------------------------------------------------- | -------------------------------------------------- |
| **Email Inbox**             | Scrollable list of all ingested emails (infinite scroll, 25/page) | ✅ SSE — new emails appear automatically          |
| **Email Modal**             | Click any email → full-body modal with rich HTML rendering       | —                                                 |
| **Email Sorting**           | Emails sorted by date (newest first via Qdrant `order_by`)      | —                                                 |
| **Calendar View**           | Today's events + upcoming events with "happening now" indicator   | ✅ SSE — updates when events are created/modified |
| **Calendar Event Creation** | Create events directly from dashboard (with Google Meet option)   | —                                                 |
| **Draft Box**               | Review, approve, send, or discard email drafts created by Kilo    | ✅ SSE — drafts appear when Kilo creates them     |
| **Quick Stats Bar**         | KPI cards: Unread Mails, Today's Events, Active Tasks             | —                                                 |
| **Task Display**            | 3-section task view (In Progress / To Do / Done)                  | —                                                 |
| **Semantic Search**         | Search bar for finding emails/notes using AI embeddings           | —                                                 |
| **Ideas Board**             | Capture, label, pin, and manage ideas. Inline editing from dashboard | —                                                 |

> **Workflow Value**: The dashboard is the **human review surface**. Kilo creates drafts → they appear in the Draft Box → user reviews and approves. This is the core human-in-the-loop pattern for email workflows.

> **First-Time Setup**: Click "Connect" in the Dashboard to link your Google Account (Gmail, Calendar, Drive). Once authorized, all Google services activate automatically — no manual token management needed.

> **Coming Soon (Pro)**: **Kanban Board** — visual task board integrated with `mcp-tasks` for drag-and-drop task management.

### 1.5 Browse Lite (In-Station Browser)

A full Chromium browser running inside the station. Critical for two purposes:

| Use Case                                | How It Works                                                             |
| --------------------------------------- | ------------------------------------------------------------------------ |
| **User browses the web**          | Open any URL inside the station — no context switching                  |
| **Sharing web content with Kilo** | User opens a page → Kilo reads it via Tavily MCP `extract` (URL → clean Markdown) |
| **Viewing generated reports**     | Open HTML reports, dashboards, or local dev servers                      |
| **External links from dashboard** | Meet links, Calendar links open in system browser via file-based relay   |

> **Key Pattern — "Show Kilo a webpage"**: The user opens a URL in Browse Lite. Then tells Kilo: "Read this page and summarize it." Kilo calls Tavily `extract` → gets clean Markdown → analyzes it. This lets the user share **any web content** with the AI assistant.

**Example conversation**:

```
User: "I'm looking at https://competitor.com/pricing — can you analyze their pricing tiers?"
Kilo: Uses Tavily extract to fetch + convert the page → provides structured analysis
```

**Gap Analysis — Shared Context Limitation:**

The station's design philosophy is that **the AI should see what the user sees**. For the browser, this is mostly achievable — but depends on which LLM model you use:

| Capability | Status | How |
|-----------|--------|-----|
| **Read a webpage** | ✅ Working | Tavily MCP `extract` converts URL → clean Markdown for LLM consumption (preferred). Markdownify's `webpage-to-markdown` is **disabled by default** — it fetches the full raw HTML including navbars, ads, and footers, routinely producing 50–200K+ tokens that blow the LLM context window. |
| **Interact with a webpage** | ⚠️ Model-dependent | Kilo's built-in **browser tool** connects to Browse Lite via Chrome DevTools Protocol (`--remote-debugging-port=9222`). The AI can click, type, scroll, and navigate — but this requires **powerful models that support computer use** (e.g., Claude Sonnet, Gemini Pro). Lighter models cannot drive it reliably. |
| **See live page state** | ⚠️ Model-dependent | With the browser tool enabled, Kilo takes viewport screenshots and reads the DOM. Again, only reliable with top-tier models. |

> **The model tradeoff**: Kilo's browser tool bridges Browse Lite via Chrome DevTools Protocol, giving the AI full DOM access. However, driving a browser reliably requires models with **computer use / vision capabilities** — typically the most expensive tier (Claude Sonnet, Gemini Pro). With the free-tier baseline model (GLM-4.5 Air), browser interaction is not reliable. The fallback is Tavily `extract`: cheap, fast, works with any model — but read-only (no clicking or form filling).

> **Future — Google WebMCP**: Google is developing **WebMCP** (Web Model Context Protocol), an early-preview Chrome API (`navigator.modelContext`) that lets websites **explicitly expose structured tools** to AI agents (e.g., `buyTicket(destination, date)`). Instead of fragile DOM scraping, websites publish a machine-readable "tool contract" that agents can call directly. This is available as a preview in Chrome 146+ Canary and could become the standard way agents interact with the web — making Browse Lite a true shared-context surface in a future release.

### 1.6 Zokai Viewer (Markdown Reader + Git Diff)

A rendered markdown viewer similar to Obsidian — but integrated directly into the station with **git change tracking**. When the AI agent creates or modifies workspace files, Zokai Viewer shows:

| Feature | What It Does |
|---------|-------------|
| **Rendered markdown** | Clean, readable view of `.md` files — no raw syntax |
| **Git diff status lines** | Color-coded indicators on each line: new (green), modified (yellow), deleted (red) |
| **Change awareness** | Instantly see what the AI changed vs. what was already there |

> **Why this matters**: When Kilo writes a 200-line report, you don't want to read raw markdown in a code editor. Zokai Viewer gives you a **reader-grade view** with immediate visibility into which parts are new or changed — like a built-in track-changes for AI-generated content.

> **For HTML content** (slide decks, generated reports, dashboards): use **Browse Lite** (§1.5) — the station's built-in Chromium browser that renders HTML files and web pages directly inside the workstation.

### 1.7 Gmail MCP

| Tool                     | What It Does                                           | Inputs                                                          |
| ------------------------ | ------------------------------------------------------ | --------------------------------------------------------------- |
| `list_inbox_emails`    | List emails with optional Gmail search query           | `query` (Gmail syntax: `from:X subject:Y`), `max_results` |
| `read_inbox_email`     | Read full email body by message ID                     | `message_id`                                                  |
| `search_stored_emails` | Semantic search across ingested emails (AI embeddings) | `query`, `limit`                                            |
| `trigger_ingestion`    | Ingest recent emails into the vector database          | `count`                                                       |
| `get_database_stats`   | Show email database statistics                         | —                                                              |
| `create_draft`         | Create a new email draft                               | `to`, `subject`, `message_text`, `html_body`            |
| `create_reply_draft`   | Create a reply draft to an existing email              | `message_id`, `reply_text`, `html_body`                   |
| `list_drafts`          | List all email drafts                                  | `max_results`                                                 |
| `delete_draft`         | Delete a draft                                         | `draft_id`                                                    |
| `send_draft`           | Send a draft email                                     | `draft_id`                                                    |

> **Power Feature**: `list_inbox_emails` accepts **full Gmail search syntax** — e.g., `from:accounting@company.com subject:"provision" after:2026/02/01 has:attachment`.

### 1.8 Calendar MCP

| Tool                       | What It Does                                                 | Inputs                                                                                   |
| -------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| `list_events`            | List upcoming calendar events                                | `max_results`                                                                          |
| `create_event`           | Create a calendar event (with optional attendees, Meet link) | `summary`, `start_time`, `end_time`, `description`, `attendees`, `time_zone` |
| `update_event`           | Modify an existing event                                     | `event_id`, fields to change                                                           |
| `delete_event`           | Delete a calendar event                                      | `event_id`                                                                             |
| `check_freebusy`         | Check availability in a time range                           | `time_min`, `time_max`                                                               |
| `search_calendar_memory` | Semantic search over past/upcoming events                    | `query`, `limit`                                                                     |

### 1.9 YouTube MCP

| Tool               | What It Does                                      | Inputs                      |
| ------------------ | ------------------------------------------------- | --------------------------- |
| `get_transcript` | Extract full transcript from a YouTube video      | `video_url` (or video ID) |
| `get_video_info` | Get video metadata (title, description, duration) | `video_url`               |

> **Limitation**: Only works on videos with available captions/auto-generated subtitles.

### 1.10 GPTR MCP (Web Research)

| Tool              | What It Does                              | Speed       | Status |
| ----------------- | ----------------------------------------- | ----------- | ------ |
| `deep_research` | Multi-source deep research with citations | 3-8 minutes | ✅ Enabled |
| `quick_search`  | Fast web search + summarized answer       | ~10 seconds | ❌ **Disabled** |

> **Why `quick_search` is disabled**: Tavily MCP already provides fast web search with better result quality. Having both active confused the AI about which to use. GPTR is now dedicated to what it does best: **deep multi-source research**.

> **Output**: Deep research reports are saved to `outputs/gptr/`.

**Model Configuration:**
- GPTR uses the LLM configured in `.zokai/zokai-config.json` (visible in your workspace under `.zokai/`)
- Default: Routes through OpenRouter — model can be changed by editing the config file
- **Performance varies by model**: Larger models (GLM-4.7, Claude) produce deeper, more thorough analysis; lighter models (GLM-4.5 Air) are faster but less detailed
- **Embeddings are local**: GPTR's retrieval step routes to the station's own embedding server — your search queries are embedded locally, never sent to external APIs in vector form

### 1.10b Tavily MCP (Web Search & Extract)

| Tool       | What It Does                                     | Inputs              |
| ---------- | ------------------------------------------------ | ------------------- |
| `search` | Fast web search via Tavily API with AI summaries | `query`, `options` |
| `extract` | Extract clean content from a URL for LLM consumption | `url` |

> **Relationship to GPTR**: Tavily `search` handles quick factual lookups. Tavily `extract` replaces Markdownify's `webpage-to-markdown` for reading web pages — it returns clean, extracted text without navbars/ads/footers. Use GPTR `deep_research` for multi-source deep research with full reports.

### 1.11 Markdownify MCP (Document Conversion)

| Tool | What It Does | Status |
| ---- | ------------ | ------ |
| `pdf-to-markdown` | Convert PDF files to Markdown | ✅ Enabled |
| `docx-to-markdown` | Convert Word documents to Markdown | ✅ Enabled |
| `xlsx-to-markdown` | Convert Excel spreadsheets to Markdown tables | ✅ Enabled |
| `pptx-to-markdown` | Convert PowerPoint presentations to Markdown | ✅ Enabled |
| `image-to-markdown` | Extract metadata/description from images | ✅ Enabled |
| `audio-to-markdown` | Extract metadata/transcription from audio | ✅ Enabled |
| `webpage-to-markdown` | Convert a URL to Markdown | ❌ **Disabled** |
| `bing-search-to-markdown` | Convert Bing search results to Markdown | ❌ **Disabled** |

> **Why `webpage-to-markdown` is disabled**: It fetches the **entire raw HTML** of a page — including navigation bars, cookie banners, footers, ads, and script tags — routinely producing 50–200K+ tokens. This exceeds most LLM context windows and wastes API budget. Use **Tavily MCP** `extract` instead: it returns clean, extracted content that fits comfortably in context.

> **Key Use**: LLMs cannot natively read binary formats. Markdownify converts **local files** (PDF, DOCX, XLSX, PPTX) to Markdown tables/text that Kilo can analyze. For **web URLs**, use Tavily extract instead.

### 1.12 Postgres MCP (Database)

| Tool               | What It Does                               | Inputs         |
| ------------------ | ------------------------------------------ | -------------- |
| `query`          | Execute read-only SQL queries              | SQL statement  |
| `execute`        | Execute write SQL (INSERT, UPDATE, DELETE) | SQL statement  |
| `list_tables`    | List all tables in the database            | —             |
| `describe_table` | Show table schema                          | `table_name` |

> **Power Feature**: Kilo can write SQL on-the-fly based on natural language questions, run it, and analyze results.

### 1.13 mcp-tasks (Task Management)

| Tool              | What It Does                                      | Inputs                  |
| ----------------- | ------------------------------------------------- | ----------------------- |
| `tasks_setup`   | Initialize a task file                            | `source_path`         |
| `tasks_add`     | Add new tasks                                     | `texts`, `status`   |
| `tasks_update`  | Change task status (To Do → In Progress → Done) | `ids`, `status`     |
| `tasks_search`  | Search/filter tasks                               | `terms`, `statuses` |
| `tasks_summary` | Get task queue overview                           | —                      |

### 1.14 Ideas MCP (Idea Capture)

| Tool              | What It Does                              | Inputs                         |
| ----------------- | ----------------------------------------- | ------------------------------ |
| `ideas_add`     | Capture a new idea (title, body, labels)  | `title`, `body`, `labels`  |
| `ideas_list`    | List all ideas (filtered by label)        | `labels` (optional)          |
| `ideas_update`  | Edit an existing idea                     | `id`, fields to change       |
| `ideas_delete`  | Delete an idea                            | `id`                         |
| `ideas_promote` | Promote an idea to a task                 | `id`                         |

**Dashboard Integration**: Ideas appear in the **Ideas Board** tab with labels, colors, pinning, and inline editing. Kilo can also capture ideas via MCP during conversations.

> **Workflow**: Capture ideas anytime → label and organize in the Dashboard → promote the best ones to actionable tasks.

### 1.15 Gap Indexer (Background Service — Pro)

| Feature                      | What It Does                                                                      |
| ---------------------------- | --------------------------------------------------------------------------------- |
| **Auto-indexing**      | Watches workspace for new/changed files and indexes them into the semantic search |
| **Large File Support** | Indexes files >300KB that Kilo's native indexer skips (PDF, XLSX, DOCX)           |
| **Shared vector space** | Indexes into the same Qdrant collection Kilo uses — results appear in codebase search |

**Operational Details:**
- Runs automatically in the background (port 8013) — no user interaction needed
- Watches `workspaces/` directory with 30s debounce for new/changed files
- Chunks files into 1500-char segments with 100-char overlap for optimal retrieval
- Uses the station's local embedding server (768-dimensional vectors)

> **Tier**: Pro only. Defined in `docker-compose.pro.yml`. Free tier users see Kilo's built-in indexing only (files <300KB).

### 1.16 Cloud Sync (Google Drive — Pro)

| Feature                      | What It Does                                                                      |
| ---------------------------- | --------------------------------------------------------------------------------- |
| **Bidirectional sync** | Continuously syncs workspace files ↔ Google Drive "Zokai Notes" folder            |
| **Auto-start**         | Starts automatically with `docker compose up` — retries until OAuth is complete   |
| **Conflict handling**  | Detects simultaneous edits; saves local version as `.conflict` file               |
| **Change detection**   | Uses Google Drive Changes API + local file hashing for efficient delta sync       |

**Operational Details:**
- **Sync interval**: Every 60 seconds (configurable via `CLOUD_SYNC_INTERVAL` env var)
- **Drive folder**: Defaults to "Zokai Notes" in the user's Google Drive root (configurable via `DRIVE_FOLDER_NAME`)
- **Fresh install**: On first boot, the service retries connection every 30s until the user completes OAuth via the Dashboard. Once authenticated, syncing begins automatically — no manual intervention needed
- **Scope requirement**: Requires the `https://www.googleapis.com/auth/drive` OAuth scope (included in the standard auth flow)

> **Tier**: Pro only. Not available in Free tier (container and compose entry are stripped by `publish-free.sh`).

> [!WARNING]
> **Do NOT install the Zokai workspace directly inside a Google Drive folder** (e.g. `~/Google Drive/ZokaiData`). Google Drive's filesystem driver continuously syncs `.git` internals, which corrupts Git's index, lock files, and pack files — leading to broken commits, phantom changes, and data loss. This is why the Pro tier ships a dedicated **Cloud Sync** service instead: it selectively syncs workspace *content* to a Drive folder while keeping the local `.git` directory untouched.

### 1.17 GitHub MCP (Pro)

| Tool                    | What It Does                                  | Inputs                       |
| ----------------------- | --------------------------------------------- | ---------------------------- |
| `github_status`       | Check GitHub connection status                | —                           |

> Provides repository browsing, issue management, and PR workflows via the GitHub API. Requires a GitHub personal access token.

> **Tier**: Pro only.

### 1.18 Raindrop MCP (Bookmarks — Pro)

| Tool                      | What It Does                             | Inputs                    |
| ------------------------- | ---------------------------------------- | ------------------------- |
| `list_collections`      | List bookmark collections                | —                        |
| `search_bookmarks`     | Search saved bookmarks                   | `query`                 |
| `save_bookmark`         | Save a new bookmark                      | `url`, `title`, `tags` |

> **Tier**: Pro only. Requires a Raindrop API token.

### 1.19 Semantic Search Engine (How "Search by Meaning" Works)

The station runs a **fully local AI embedding pipeline** — no search queries or document content leaves the machine in vector form. This is a core privacy differentiator.

**Embedding Model**: `sentence-transformers/paraphrase-multilingual-mpnet-base-v2` (768-dimensional, multilingual, baked into the Docker image at build time)

| Service | Search Method | How It Works |
|---------|--------------|------|
| **Gmail MCP** | **BM25 + Dense Hybrid** (RRF fusion) | Combines keyword matching (BM25 sparse vectors) with semantic understanding (dense vectors). Results merged via Reciprocal Rank Fusion — best of both worlds |
| **Calendar MCP** | **Dense vector only** | Pure semantic search over embedded event descriptions |
| **Kilo Codebase** | **Built-in embedding index** | Kilo Code's own tree-sitter + embedding system, independent from Qdrant |
| **GPTR** | **Local embeddings** for retrieval | GPTR's internal retrieval step routes to the station's embedding server — queries stay local |
| **Dashboard** | **Dense vector search** | Search bar queries the same Qdrant collections as the MCPs |

> **Privacy Guarantee**: All embeddings are computed by the local FastEmbed server running inside the station container. External LLM APIs only receive natural language prompts — never raw vectors or indexed documents.

### 1.20 Ingestor (Background Indexing Pipeline)

| Feature                      | What It Does                                                                      |
| ---------------------------- | --------------------------------------------------------------------------------- |
| **Email ingestion**    | Pulls emails from Gmail API, embeds them (dense + BM25 sparse), stores in Qdrant |
| **Calendar ingestion** | Pulls calendar events, embeds descriptions, stores in Qdrant                      |
| **Deduplication**      | UUIDv5-based dedup prevents duplicate entries on re-ingestion                     |
| **Collection setup**   | Creates and migrates Qdrant collections with proper named vector schemas         |

> Not called directly — triggered by `gmail-mcp.trigger_ingestion` or runs on schedule. The ingestor is the pipeline that makes `search_stored_emails` and `search_calendar_memory` work.

### 1.21 Supporting Infrastructure

| Service                       | Role                                                                           |
| ----------------------------- | ------------------------------------------------------------------------------ |
| **Embedding Server**    | Local FastEmbed API (768d multilingual model) — all semantic search routes here |
| **Qdrant**              | Vector database storing emails, calendar events, and workspace documents       |
| **Redis**               | Rate limiting and caching                                                      |
| **NGINX Proxy**         | Routes dashboard traffic and proxies API calls                                 |
| **Secrets Manager**     | Manages OAuth tokens with proactive refresh — handles Google auth flow         |
| **Service Discovery**   | Auto-detects running MCP services for the dashboard                            |
| **Config Service**      | Central configuration management across services                               |
| **Workspace Manager**   | Provisions and manages workspace directories                                   |

---

## 2. Workflow Composition Patterns

The true power of Zokai Station is **combining tools across MCPs in sequence**. Below are proven patterns showing how tools chain together.

### Pattern A: Template-Driven Processing

**How it works**: A Markdown template file contains step-by-step instructions. The user gives Kilo the template + input, and Kilo follows the instructions automatically.

```
Input: @/notes/template.youtube.ai_news.md + YouTube URL
Chain: YouTube.get_transcript → Kilo.analyze → Kilo.write_file
Output: Formatted summary note in notes/
```

**Template file structure**:

```markdown
---
id: template.your_workflow
title: Descriptive Name
---
## Instructions for Kilo
1. First, do X with the input...
2. Then, transform the data...
3. Finally, save the result as `notes/output_name.md`
```

> **This is the core automation primitive.** Any repeatable process can become a template.

### Pattern B: Email → Extract → Process → Respond

```
Chain: Gmail.list_inbox_emails(query) → Gmail.read_inbox_email(id)
     → Kilo.extract_data → Kilo.process → Gmail.create_reply_draft
Human: Review draft → approve send
```

### Pattern C: Document → Convert → Analyze → Report

```
Chain: Markdownify.convert(xlsx/pdf) → Kilo.analyze_data
     → Kilo.write_report → Kilo.write_file
```

### Pattern D: Research → Synthesize → Schedule

```
Chain: GPTR.deep_research(topic) → Kilo.read_file(report)
     → Kilo.summarize → Calendar.create_event(review meeting)
     → Gmail.create_draft(send summary to team)
```

### Pattern E: Database → Transform → Export

```
Chain: Postgres.query(SQL) → Kilo.transform_to_csv
     → Kilo.write_file(output.csv)
```

### Pattern F: Multi-Source Data Merge

```
Chain: Gmail.read_email(data1) + Markdownify.convert(file.xlsx, data2)
     + Postgres.query(SQL, data3)
     → Kilo.merge_and_transform → Kilo.write_file(result.csv)
```

### Pattern G: Browse → Capture → Analyze (Web Sharing)

```
User: Opens URL in Browse Lite + asks Kilo to analyze it
Chain: Tavily.extract(URL) → Kilo.analyze
     → Kilo.write_file(notes/analysis.md)
```

> **Use case**: User sees an interesting article, competitor page, or regulatory document online. Asks Kilo: "Read this page and compare it to our approach." Kilo fetches the page via Tavily extract, gets clean text, and provides analysis.

### Pattern H: Dashboard Review Loop (Human-in-the-Loop)

```
Kilo: Gmail.create_draft(response) → Draft appears in Dashboard Draft Box (SSE)
Human: Reviews draft in Dashboard → clicks Approve → email sent
       OR clicks Discard → draft deleted
```

> **This is the primary human validation loop.** Kilo proposes actions (email drafts, reports, files) and the human reviews them before execution.

### Pattern I: Knowledge Capture → Retrieval

```
Chain: Kilo.write_file(notes/meeting_2026_03_01.md)
     → Gap Indexer auto-indexes → Qdrant vector stored
Later: User asks "What did we decide about pricing?"
     → Kilo.codebase_search → finds meeting note → answers
```

> **The notes folder is a living knowledge base.** Every note Kilo creates is automatically indexed and searchable by meaning. The knowledge graph (Foam) visualizes how notes connect.

### Pattern J: Git History Analysis

```
Chain: Kilo.terminal(git log --since='1 week ago' --oneline)
     → Kilo.terminal(git diff HEAD~5) → Kilo.analyze_changes
     → Kilo.write_file(notes/weekly_changelog.md)
```

---

## 3. Worked Examples (Recorded Demos)

These are **real workflows** recorded end-to-end in Zokai Station. Each demo has a YouTube video so you can see exactly what happens.

---

### Example 1: One-Prompt Slide Deck 📊

> 📺 Video walkthrough coming soon (44s)

**Scenario**: It's 10 AM, there's a meeting in 15 minutes, and you need slides.

**What the agent does (one prompt):**
1. **Calendar MCP** → reads today's agenda to get the meeting topic
2. **mcp-tasks** → pulls recent task status for context
3. **Code generation** → creates a dark-themed HTML slide deck using a style file
4. **Browse Lite** → previews the rendered slides inside the station

**Tool chain:**
```
Calendar.get_events → mcp-tasks.tasks_search → Kilo.write_file(slides.html)
→ Browse Lite preview
```

**Captions from the demo:**

| Timestamp | Step | What Happens |
|-----------|------|-------------|
| 0:00 | Dashboard | Zokai Station: centralized AI workstation with integrated assistant |
| 0:09 | Tool Integration | Agent uses MCP to access calendar and task servers in real time |
| 0:21 | Slide Generation | Agent reads style file, converts content to HTML, applies dark theme |
| 0:34 | Preview | Task marked Done. Dark-themed deck previewed inside the workstation |

---

### Example 2: Newsletter Digest 📰

> 📺 Video walkthrough coming soon (2 min)

**Scenario**: You subscribe to AI research newsletters. Nobody reads them. Let the AI do it.

**What the agent does:**
1. **Gmail MCP** → pulls latest newsletters from inbox
2. **Kilo analysis** → reads, categorizes, and synthesizes across multiple sources
3. **GPTR/Browse Lite** → cross-references claims against academic papers and web sources
4. **Gmail MCP** → drafts a professional email summary for the team
5. **Kilo file write** → creates a **reusable markdown template** for next month

**Tool chain:**
```
Gmail.list_inbox_emails(query:"newsletter") → Gmail.read_inbox_email(id)
→ Kilo.analyze + GPTR.deep_research(fact-check)
→ Gmail.create_draft(summary email) → Kilo.write_file(template.md)
Human: Review draft → approve send
```

**Captions from the demo:**

| Timestamp | Step | What Happens |
|-----------|------|-------------|
| 0:00 | Information Retrieval | AI agent pulls latest AI research newsletters from Gmail |
| 0:08 | Intelligent Summarization | Multiple sources synthesized into a structured overview |
| 0:25 | Deep Dive & Validation | Detailed breakdown with cross-referenced academic papers |
| 0:58 | Seamless Communication | Research transformed into a professional email draft |
| 1:38 | Workflow Automation | A reusable markdown template for future research workflows |

---

### Example 3: Commission Invoice Controller 🔍

> 📺 Video walkthrough coming soon (2 min)

**Scenario**: A bank receives a commission invoice. The math looks correct. The rates look correct. But do the underlying contracts actually exist?

**What the agent does:**
1. **Markdownify MCP** → converts the PDF invoice to readable text
2. **Kilo extraction** → pulls location, partner ID, and claimed rates from the invoice
3. **Postgres MCP** → cross-checks each commission line against the contract database
4. **Kilo analysis** → catches **€16,000 in phantom contracts** (2 loans that don't exist in the database)
5. **Gmail MCP** → drafts a response email flagging the discrepancies
6. **Kilo file write** → creates a reusable SOP template for future audits

**Tool chain:**
```
Markdownify.convert(invoice.pdf) → Kilo.extract_data
→ Postgres.query(SELECT * FROM contracts WHERE partner_id = ?)
→ Kilo.cross_check(invoice vs database) → detects phantom contracts
→ Gmail.create_draft(response) → Kilo.write_file(sop_template.md)
Human: Review draft + SOP → approve send
```

**Captions from the demo:**

| Timestamp | Step | What Happens |
|-----------|------|-------------|
| 0:00 | Task Initiation | Agent receives the invoice and the context |
| 0:06 | Agentic Self-Correction | A standard tool fails to read the PDF — agent switches to Markdownify |
| 0:14 | Data & Rule Extraction | Location extracted, mapped to Non-Bavaria rate, validated against rules |
| 0:25 | Database Cross-Check | Postgres query reveals 2 phantom contracts — €16k overbill |
| 0:50 | Response Drafting | Professional response email flagging the discrepancies |
| 1:20 | SOP Creation | Reusable template for future commission audits |

> **Key takeaway**: The invoice math was correct. The rates were correct. Only the database cross-check revealed the fraud. This is what human+AI shared context enables — the human supplies the business context, the AI does the exhaustive reconciliation.

---

### Additional Workflow Templates

The following are template-based workflows you can set up in your station. They use the same tool patterns shown in the demos above.

#### Template A: YouTube Research Pipeline

**User says**: "I watch AI news videos weekly. I want structured summaries I can search later."

**Template** (`notes/template.youtube.ai_news.md`):

```markdown
---
id: template.youtube.ai_news
title: AI News Video Summary Template
---
## Instructions
1. Use YouTube MCP to get the transcript of the given video URL
2. Analyze the transcript and extract:
   - Key announcements (with timestamps)
   - Companies/products mentioned
   - Implications for developers
3. Save as `notes/ai.news.YYYYMMDD.md` with frontmatter:
   - tags: [ai-news, youtube]
   - source: [video URL]
4. Add a one-paragraph executive summary at the top
```

**Usage**: `Summarize https://youtube.com/watch?v=xxx using @/notes/template.youtube.ai_news.md`

**Gap Analysis:**
- ✅ Transcript extraction — working (YouTube MCP)
- ✅ AI summarization — working (Kilo analysis)
- ✅ File creation — working (Kilo write_file)
- ⚠️ **Missing**: Auto-discovery of new videos from subscribed channels (would need YouTube RSS/subscription MCP)
- ⚠️ **Missing**: Scheduled execution (would need a cron/scheduler service)

---

#### Template B: Monthly Accounting Provision Workflow

**User says**: "Each month I get an email from Department Y with provision amounts. I also need to run an SQL query for Department Z provisions. I combine both into a CSV for SAP upload."

**Template** (`notes/template.monthly_provision.md`):

```markdown
---
id: template.monthly-provision
title: Monthly Provision Booking Workflow
---
## Instructions
1. **Email Extraction**: Use Gmail MCP to search for the latest email:
   - Query: `from:department-y@company.com subject:"provision" newer_than:30d`
   - Read the email body and extract the provision amount (look for a currency figure)
   - Store as `provision_dept_y`

2. **SQL Query**: Use Postgres MCP to run:
   ```sql
   SELECT SUM(amount) as provision
   FROM provisions
   WHERE department = 'Z'
     AND period = DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')
```

- Store result as `provision_dept_z`

3. **Combine & Format**: Create a CSV file matching SAP template:

   ```csv
   BookingDate,CostCenter,Account,Amount,Currency,Text
   2026-03-01,CC-Y,4711,{provision_dept_y},EUR,Provision Dept Y
   2026-03-01,CC-Z,4712,{provision_dept_z},EUR,Provision Dept Z
   ```
4. **Save**: Write to `outputs/sap_booking_YYYY_MM.csv`
5. **Notify**: Create a draft email to accounting@company.com
```

**Gap Analysis:**

| Step | Status | Gap |
|------|--------|-----|
| Email search + extraction | ✅ Working | Gmail MCP `list_inbox_emails` with query syntax |
| SQL query execution | ✅ Working | Postgres MCP `query` |
| CSV generation | ✅ Working | Kilo writes CSV via file creation |
| SAP upload | ❌ Missing | **Need**: SAP MCP or SAP API integration to upload CSV programmatically |
| Scheduled execution | ❌ Missing | **Need**: Cron/scheduler service to trigger workflow monthly |
| Email attachment extraction | ⚠️ Partial | Gmail MCP can read emails but attachment download needs the email to be ingested first |
| Notification email | ✅ Working | Gmail MCP `create_draft` + human sends |

---

#### Template C: Competitive Intelligence Report

**Template** (`notes/template.competitive_intel.md`):

Uses GPTR deep research + Postgres sales data + Calendar event scheduling. See Section 2 patterns for the tool chain.

**Gap Analysis:**
- ✅ Web research — GPTR deep_research
- ✅ SQL queries — Postgres MCP
- ✅ Report generation — Kilo writes markdown
- ✅ Calendar scheduling — Calendar MCP
- ⚠️ **Missing**: CRM integration (Salesforce/HubSpot MCP for live pipeline data)
- ⚠️ **Missing**: Slack/Teams MCP to distribute the report to the team channel

---

#### Template D: Contract Deviation Analysis

**Template** (`notes/template.contract_review.md`):

Uses Markdownify for PDF conversion + Kilo clause-by-clause comparison against standard terms. Outputs a color-coded deviation report (🟢🟡🔴).

**Gap Analysis:**
- ✅ PDF conversion — Markdownify MCP
- ✅ Text comparison — Kilo AI analysis
- ✅ Report generation — file write
- ✅ Email draft — Gmail MCP
- ⚠️ **Missing**: OCR for scanned PDFs (Markdownify handles digital PDFs, not scanned images)
- ⚠️ **Missing**: Document signing integration (DocuSign/HelloSign MCP)
- ⚠️ **Missing**: Legal clause database for more precise matching

---


## 4. Workflow Design Methodology

When a user describes a process, Kilo should follow this methodology:

### Step 1: Decompose Into Atomic Steps

Break the user's process into individual actions:

- **Input**: Where does data come from? (Email, file, database, web, calendar)
- **Transform**: What processing is needed? (Extract, calculate, compare, merge, format)
- **Output**: Where does the result go? (File, email draft, calendar event, database)
- **Validate**: What needs human review? (Accuracy checks, approval gates)

### Step 2: Map Steps to Station Tools

For each atomic step, identify:

1. **Which MCP or Kilo capability handles it?** → Reference Section 1
2. **Is it fully supported, partially supported, or missing?**
3. **What's the input/output format?**

### Step 3: Propose Phase 1 — Human-in-the-Loop Workflow

Create a **template markdown file** the user can invoke with `@/notes/template.xxx.md`:

- Clear numbered steps Kilo will follow
- Explicit human checkpoints ("Review this before proceeding")
- Output file locations specified
- Error handling ("If email not found, notify user")

### Step 4: Propose Phase 2 — Automation Scripts

Identify which steps can be scripted:

- Python/Bash scripts for data transformation
- Scheduled execution (cron patterns)
- File watchers for trigger-on-arrival patterns
- Chained MCP calls in a single script

### Step 5: Analyze Phase 3 — Full Automation Gaps

For each gap, specify:

1. **What's missing** — the capability that doesn't exist yet
2. **What would solve it** — new MCP, API integration, or external tool
3. **Effort estimate** — how hard it would be to build
4. **Workaround** — can the human fill this gap manually in the meantime?

---

## 5. Common Gap Categories

These are the most frequently missing capabilities when designing workflows:

| Gap Category                   | Description                                                         | Examples of What Would Solve It                 |
| ------------------------------ | ------------------------------------------------------------------- | ----------------------------------------------- |
| **Scheduled Execution**  | No built-in cron/scheduler for recurring workflows                  | Cron MCP, or host-level `launchd`/`crontab` |
| **ERP/Business Systems** | No direct integration with SAP, Oracle, Dynamics                    | SAP RFC MCP, OData connector                    |
| **CRM**                  | No Salesforce, HubSpot, or Pipedrive access                         | CRM MCP with OAuth                              |
| **Team Communication**   | No Slack, Teams, or Discord integration                             | Slack MCP, Teams Webhook MCP                    |
| **Cloud Storage**        | ✅ Google Drive sync via Cloud Sync service (Pro). No OneDrive/Dropbox. | OneDrive MCP, Dropbox MCP                       |
| **Document Signing**     | No DocuSign, HelloSign integration                                  | E-Signature MCP                                 |
| **OCR**                  | Scanned document text extraction                                    | Tesseract integration or OCR MCP                |
| **Webhook Triggers**     | No inbound webhook listener for external event triggers             | Webhook receiver service                        |
| **SFTP/FTP**             | No remote file transfer capability                                  | SFTP MCP                                        |
| **Excel Writing**        | Can read XLSX (via Markdownify) but cannot write native .xlsx files | `openpyxl` script or Excel MCP                |
| **External Database**    | Postgres is local only — no connection to external SQL servers     | Connection string configuration, SSH tunnel     |

---

## 6. Building New MCPs — The Plugin Architecture

Zokai Station supports **drop-in MCP plugins**. When gap analysis reveals a missing tool, a new MCP can be built:

**What an MCP needs:**

1. A Docker container with the service
2. Tools registered via `@mcp.tool()` decorators (Python FastMCP) or equivalent
3. Entry in `mcp-config.json` for Kilo to discover it
4. Bridge script compatibility (`mcp-bridge.sh`)

**Typical effort**: A simple MCP (e.g., SFTP file transfer) takes 4-8 hours to build and integrate.

> See `docs/specs/station_plugin_architecture_spec.md` for the full plugin specification.

---

## 7. Quick Reference: "Can the Station Do X?"

### Communication & Productivity

| User Need                    | Answer              | How                                                                             |
| ---------------------------- | ------------------- | ------------------------------------------------------------------------------- |
| Read my emails               | ✅ Yes              | Gmail MCP `list_inbox_emails` + `read_inbox_email`                          |
| Search emails by meaning     | ✅ Yes              | Gmail MCP `search_stored_emails` (semantic/AI search)                         |
| Send emails                  | ✅ Yes (draft+send) | Gmail MCP `create_draft` → human reviews in Dashboard → `send_draft`      |
| Review email drafts visually | ✅ Yes              | Dashboard Draft Box — real-time SSE updates                                    |
| Read calendar                | ✅ Yes              | Calendar MCP `list_events` + Dashboard calendar view                          |
| Create meetings              | ✅ Yes              | Calendar MCP `create_event` (with Meet links + attendees) or Dashboard button |
| Check availability           | ✅ Yes              | Calendar MCP `check_freebusy`                                                 |

### Research & Analysis

| User Need                  | Answer | How                                                                       |
| -------------------------- | ------ | ------------------------------------------------------------------------- |
| Summarize YouTube          | ✅ Yes | YouTube MCP `get_transcript` → Kilo summarizes                         |
| Convert PDF/XLSX/DOCX      | ✅ Yes | Markdownify MCP (`pdf-to-markdown`, `docx-to-markdown`, `xlsx-to-markdown`, `pptx-to-markdown`) |
| Analyze spreadsheets       | ✅ Yes | Markdownify → Kilo reads markdown table → analyzes                      |
| Read a webpage             | ✅ Yes | Tavily MCP `extract` — converts URL to clean Markdown for LLM consumption (Markdownify `webpage-to-markdown` is disabled — blows context window) |
| Web research               | ✅ Yes | Tavily `search` (fast lookups) or GPTR `deep_research` (multi-source reports). GPTR `quick_search` is disabled — Tavily covers it. |
| Browse the web             | ✅ Yes | Browse Lite (built-in Chromium)                                           |
| Share a web page with Kilo | ✅ Yes | User opens URL in Browse Lite, Kilo reads via Tavily `extract` or copies URL to chat |

### Knowledge & Notes

| User Need                 | Answer | How                                                                        |
| ------------------------- | ------ | -------------------------------------------------------------------------- |
| Take structured notes     | ✅ Yes | Zokai Notes — wiki-linked markdown files                                  |
| Link notes together       | ✅ Yes | `[[wiki links]]` — creates bidirectional connections                    |
| Visualize knowledge graph | ✅ Yes | Foam Graph View (`Ctrl+Shift+P` → "Show Graph")                         |
| Search my notes (AI)      | ✅ Yes | Kilo Codebase Search (semantic embedding search)                           |
| Use note templates        | ✅ Yes | Copy from `notes/templates/` — meeting notes, spike reports, daily logs |
| Tag and organize notes    | ✅ Yes | `#hashtags` + dot-notation hierarchy (`project.client.notes`)          |

### Data & Development

| User Need                  | Answer       | How                                                              |
| -------------------------- | ------------ | ---------------------------------------------------------------- |
| Run SQL queries            | ✅ Yes       | Postgres MCP `query` or `execute`                            |
| Manage tasks               | ✅ Yes       | mcp-tasks `tasks_add`, `tasks_update`, etc.                  |
| Write/edit any file        | ✅ Yes       | Kilo native file operations                                      |
| Run scripts                | ✅ Yes       | Kilo terminal (`python3`, `bash`, `node`, etc.)            |
| Version control            | ✅ Yes       | Git built-in — commit, diff, branch, push, history              |
| Track file changes         | ✅ Yes       | Git timeline +`git log` + `git diff`                         |
| Revert to previous version | ✅ Yes       | `git checkout`, `git revert`, or VS Code timeline            |
| Write Excel (.xlsx)        | ⚠️ Partial | Can write CSV; for .xlsx, Kilo can run `openpyxl` via terminal |
| Connect to external DBs    | ⚠️ Partial | Postgres MCP is local-only — needs config for external          |

| Sync files to Google Drive | ✅ Yes (Pro) | Cloud Sync service — bidirectional sync to "Zokai Notes" Drive folder |
| Manage GitHub repos        | ✅ Yes (Pro) | GitHub MCP — issues, PRs, repo browsing                               |
| Save/search bookmarks      | ✅ Yes (Pro) | Raindrop MCP — bookmark management with search                        |

### Gaps (Not Yet Available)

| User Need                | Answer       | What Would Solve It                                |
| ------------------------ | ------------ | -------------------------------------------------- |
| Read Slack/Teams         | ❌ No        | Slack/Teams MCP                                    |
| Upload to SAP/ERP        | ❌ No        | SAP RFC MCP or OData connector                     |
| Send WhatsApp            | ❌ No        | WhatsApp MCP                                       |
| Schedule recurring tasks | ⚠️ Partial | Can create scripts, but no built-in cron scheduler |
| SFTP/FTP file transfer   | ❌ No        | SFTP MCP                                           |
| OCR scanned documents    | ❌ No        | Tesseract integration                              |

---

## Related Notes

- [[1.Welcome]] — Overview of the workspace structure
- [[finance-controller-automation]] — Financial automation workflows and procedures

---

*This document is maintained as part of the Zokai Station workspace. Update it when new MCPs or capabilities are added.*
