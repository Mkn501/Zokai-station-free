# Zokai Station — User Manual

> **Version**: 1.1 | **Last updated**: 2026-04-19 | **Tier**: Free + Pro

---

## Prologue: Welcome to Zokai Station

**Your AI workstation builds context over time. The more you use it, the more useful it becomes.**

Most AI tools start fresh on every session. You paste in context, the AI responds, and everything is gone when you close the tab. Zokai is different.

Every email you sync, every note you write, every project you work on adds to a searchable, persistent knowledge base — and Kilo, your AI agent, can reach across all of it at once. Ask about a contract mentioned in an email three months ago. Cross-reference it with your notes. Draft a reply. All in one prompt.

With **Pro**, this goes further. **Knowledge Weaver** actively reads your workspace, extracts entities — people, projects, decisions, concepts — maps the relationships between them, and auto-links your notes. Passive accumulation becomes an active, growing knowledge graph. The more you work, the smarter it gets. → [See Chapter 11](#chapter-11-growth-through-accumulation)

And all of it runs on your own machine — no vendor routes your data, no subscription controls your access, no platform update breaks your workflow overnight.

**What you're looking at right now** — a professional AI development environment, fully assembled and ready:

| What you see | What it actually is |
|---|---|
| **Dashboard** (`localhost:8080`) | Your command centre — live inbox and calendar at a glance. **Pro** adds a full task panel, system health indicators, a Kanban board, and an Ideas board. |
| **Kilo** (the sidebar icon on the left) | Your AI agent — it reads your emails, searches your notes, writes code, runs research, and drafts replies — all without leaving this window |
| **File Explorer** (left panel) | Your workspace — notes, reports, code, and downloads that Kilo can read, create, and edit |
| **Terminal** (bottom) | A full shell running inside the station — Kilo can use it too |

**First thing to try**: Click the Kilo icon → type *"What's on my calendar today?"*

Watch it go directly to your Google Calendar, read the actual events, and give you a real answer — not a demo, not a simulated response. Your data. Your calendar. Right now.

**Where to find this manual again**: Switch Kilo to **Zokai Guide** mode (the dropdown at the top of the Kilo panel) and ask it anything. Kilo Guide reads this entire manual and answers questions about what the station can do and how to use it — no searching required.

> **First launch?** The first start takes 3–5 minutes while Docker builds the containers. If your email or calendar panel is empty, connect your Google account first: **Dashboard → Connect Google Account**. Once connected, up to 5,000 emails are indexed automatically in the background — your inbox becomes searchable within minutes.

> 🎬 *[See it in action: one prompt → a complete slide deck](https://youtu.be/bqTI-GP8rkk)* — Calendar, tasks, and code pulled together without copy-pasting anything.

---

## Act I: Why Zokai Exists

---

## Chapter 1: You Don't Need AGI

The promise of fully autonomous AI agents is everywhere. The reality is more measured:

- **Carnegie Mellon (2025)**: ~70% failure rate on real office tasks
- **APEX Benchmark (2026)**: 76–82% failure on multi-step workflows
- **MCP-Universe (2025)**: 43.7% success rate for GPT-5 without human oversight
- **Gartner (2026)**: 40%+ of agentic projects will be cancelled by 2027

The academic consensus is consistent: full autonomy does not yet work reliably. And in regulated industries — finance, insurance, healthcare, legal — a human must always be accountable for decisions. No AI signature holds up in court. No AI can be held responsible.

> *You don't need an AI that replaces you. You need one that works with you.*

That is the design philosophy behind Zokai Station. Not a chatbot. Not an autonomous agent. A **workstation** — where you stay in control and the AI does the heavy lifting.

---

## Chapter 2: AI Proposes. You Decide.

Five concrete scenarios showing what **Human-in-the-Loop** means in practice:

| Scenario | AI does | You do |
|---|---|---|
| Email drafts | Writes the reply | Read it, edit it, decide whether to send |
| Code & documents | Suggests edits with diffs | See every change, approve or reject line by line |
| Research | Gathers sources and synthesises | Decide what to trust and what to discard |
| Scheduling | Proposes events and deadlines | Approve before anything lands on your calendar |
| Workflows | Runs multi-step tasks end-to-end | Review the result before it is final |

**How you see what the AI changed** — the Zokai Viewer:

Right-click any `.md` file in the file explorer → **"Open with Zokai Viewer"** (or click the 🌿 icon in the editor tab).

- 🟢 **Green** = lines added by the AI, not yet committed
- 🟡 **Yellow** = lines modified by the AI, not yet committed
- 🔴 **Red** = lines deleted by the AI, not yet committed

One glance shows exactly what the agent wrote before you decide to keep it.

**The review → commit workflow** (Git is built into Zokai — your workspace is a repository):

1. **Kilo writes or edits a file** — the change is saved but *uncommitted* (like a tracked draft)
2. **Review in Zokai Viewer** — right-click the file → "Open with Zokai Viewer". Green/yellow/red markers show every change.
3. **Review in Source Control** — click the branch icon in the left sidebar. Every modified file shows a full line-by-line diff.
4. **Commit** — two options:

| Method | How | When to use |
|---|---|---|
| **Manual** (VS Code) | Source Control panel → click + to stage → type a commit message → click ✓ Commit | When you want full control |
| **Via Kilo** | *"Commit all my changes with the message 'Add invoice analysis'"* | When you trust the changes and want speed |

5. **Optionally push to a remote** — for backup or team collaboration:
   - First time: `git remote add origin <your-repo-url>` (or ask Kilo to do it)
   - Then: click **Sync** in Source Control, or: *"Push my changes to GitHub"*

> **Why this matters**: Every commit is a permanent, auditable record of what the AI did and when. You can always revert: *"Undo the last commit"* or `git revert HEAD`. This is your safety net — experiment freely, roll back if needed.

> *This isn't a limitation — it's what makes Zokai different. Full automation sounds impressive until it sends the wrong email.*

---

## Act II: What the Station Does

---

## Chapter 3: The Station — Six Tools, One Workspace

The core thesis: **Human-in-the-Loop only works if your AI sees the full picture.** Every tool in Zokai feeds into one shared workspace, so Kilo always has context across all of them.

| Capability | Interface | What it does |
|---|---|---|
| Research | Browser + Reports | Deep web research with synthesised reports |
| Email & Calendar | Dashboard | Inbox and schedule, indexed and searchable |
| Zokai Notes | Editor + Graph | Wiki-style knowledge base with `[[links]]` |
| Code & Automation | Editor + Terminal | AI coding agent with full workspace context |
| AI Agents | Kilo sidebar | Connect any AI — local or cloud |
| Dashboard | Browser panel | Live overview: emails and calendar. **Pro** adds tasks, Kanban, Ideas board. |

> *No copy-paste. No app switch. One workspace.*

**Why shared context matters**: When Kilo drafts an email reply, it can reference your calendar (to propose a meeting time), your notes (to cite a previous decision), and your codebase (to attach the right file). This only works because everything is in one workspace.

**Built-in content conversion** — the AI can also pull in external content:

| Tool | What it does | Example prompt |
|---|---|---|
| **Tavily Extract** | Fetches and extracts clean text from any URL | *"Read this article and summarise the key points: https://..."* |
| **Markdownify** | Converts web pages, PDFs, Excel, Word docs into readable markdown | *"Convert this PDF to markdown so we can work with it"* |

This means Kilo is not limited to files already in your workspace. It can fetch a web page or convert a document, and use that content alongside your emails, notes, and code — all within the same shared context.

---

## Chapter 4: Research

Most AI tools can answer a question from their training data. Kilo can go further: it actively browses the web, gathers sources, cross-references them, and synthesises a structured report — saved as a markdown file in your workspace so you can build on it later. Not a chatbot answer. A document.

**What you can do:**
- *"Research the latest GDPR changes affecting AI companies"* → multi-page report with sources
- *"Summarise this YouTube video and save the key points to my notes"*
- *"Find academic papers about prompt injection defence"*
- *"Compare these two vendors and give me a recommendation"*

**How it works**: Kilo calls GPTR (GPT Researcher) → Tavily web search → source gathering → AI synthesis → saved to your workspace as a markdown report.

**Setup**: Tavily API key in `zokai-config.json`. Free tier: 1,000 searches/month at [tavily.com](https://tavily.com). If you don't have a key, Kilo will tell you — and you can request one for free in 30 seconds.

**What to expect**:
- A full report: 1–3 pages, sourced, structured, saved to your workspace
- Processing time: 30s–2min depending on topic complexity and the number of sources
- Quality depends on web content availability — paywalled or JavaScript-heavy sites may not extract cleanly

**Tip**: Research reports are saved as markdown files in your workspace. You can continue any research session by pointing Kilo at a previous report:

> *"Read my report on GDPR changes and dig deeper into the AI Act implications."*

The workspace is your persistence layer — every report builds on the last.

---

## Chapter 5: Email & Calendar Intelligence

Your inbox and calendar are indexed directly into Zokai's search layer. This means Kilo can answer questions like *"what did Legal say about the contract last March?"* the same way it answers questions about your code — by meaning, not by keyword. No forwarding emails. No copy-pasting threads. The context is already there.

**What you can do:**
- Search your inbox semantically: *"find the email where Maria mentioned the budget revision"*
- Use operators: `from:john`, `to:team@company.com`, `subject:invoice`, `after:2026-03-01`, `before:2026-04-01`, `has:attachment`
- Ask Kilo to draft replies: *"draft a professional response declining the meeting"*
- Calendar: create, edit, delete, RSVP to invitations, recurring events, multi-calendar

**How search works**: A dual approach — **BM25 keyword matching** (exact words) + **dense vector similarity** (semantic meaning). Results ranked by Reciprocal Rank Fusion. This means the query *"budget revision"* will find emails that say "budget changes" or "financial adjustments" — not just literal matches.

**Setup**: Dashboard → **Connect Google Account** → OAuth flow opens in your default browser → grant access → sync starts automatically.

**What to expect**:
- Email sync runs every 5 minutes via a background daemon
- Initial deep sync: indexes up to 5,000 emails on first connect (100 pages × 50 per batch)
- Search results return in 1–3 seconds
- Draft appears in Dashboard → you review and edit before sending (nothing is sent automatically)
- Calendar events are visible immediately after creation — no sync delay

**During heavy indexing** (e.g., when Kilo is indexing your codebase for the first time):
- **Calendar events**: Always immediate. Creating, editing, or deleting events works instantly.
- **Email search**: Always fast (~1–3s). Search requests get priority over bulk indexing — you will never notice a slowdown.
- **Newly sent emails**: Appear in your inbox list immediately (live Gmail API). They won't be *semantically searchable* until the background sync picks them up — which may take a few extra minutes if heavy indexing is running. This resolves automatically.

**Inherited limitations**:
- Sync is periodic (5 min), not real-time — new emails won't appear instantly
- Gmail labels/categories are basic (inbox, sent, draft) — no custom label filtering yet
- Maximum 50 emails per sync batch (Google API rate limit per page)
- Calendar free/busy view not available
- Google Workspace admins may block OAuth consent for organisational accounts

---

## Chapter 6: Zokai Notes & the Knowledge Graph

Zokai Notes is your workspace's long-term memory. While Kilo reads and writes files in real-time, your notes accumulate across sessions — linked to each other, searchable by meaning, and visible as a graph you can navigate. Every document Kilo produces, every research summary, every meeting write-up becomes part of a growing knowledge base you own.

**What you can do:**
- Write markdown notes with wiki-links: `[[project-name]]` auto-links to other notes in the workspace
- Visualise connections: see a graph of all your linked notes (`Ctrl+Shift+P` → *"Foam: Show Graph"*)
- Use templates: journal entries, research notes, meeting notes — pre-configured in `.foam/templates/`
- Ask Kilo to create notes: *"Write up a summary of our discussion and save it as a note called 'project-alpha-kickoff'"*

**Zokai Viewer** — your track-changes for AI content:
- Right-click any `.md` file → **"Open with Zokai Viewer"** (or click the 🌿 icon in the editor tab)
- 🟢 Green = added by AI, not yet committed
- 🟡 Yellow = modified by AI, not yet committed
- 🔴 Red = deleted by AI, not yet committed

One glance to see exactly what the agent changed before you decide whether to commit.

**Inherited limitations**:
- Foam builds the graph from wiki-links — it does not understand content semantics
- Large non-markdown files in the workspace (XLSX, JSON, CSV) can cause the graph extension to spike CPU. This is mitigated via built-in file exclusion filters, but worth knowing if you drop large non-markdown files into the workspace root.
- Graph view is read-only — you cannot drag and drop to reorganise

**Why notes live locally first, then sync to Google Drive — not the other way around**:

You might wonder: *why not just point the workspace at the Google Drive folder directly, so notes are always "in" Google Drive?*

The short answer: Google Drive on Mac is not a real folder — and Docker can't tell the difference.

Google Drive for Desktop uses a virtual filesystem layer (FUSE) that *looks* like a local folder but uploads files to the cloud as you write them. Docker runs your workspace in its own filesystem layer stacked on top. Git needs to place exclusive "DO NOT TOUCH" locks on files while it works. Virtual folders don't support those locks. The result is a kernel-level deadlock error (`EDEADLK`) that crashes git and can corrupt your entire workspace history.

*An analogy: it's like trying to put a padlock on a hologram. The lock is real; the surface isn't.*

**The solution Zokai uses**: your workspace lives on the local filesystem (real disk, no virtual layer). A dedicated `cloud-sync` service syncs files to Google Drive in the background via the Google Drive API — bypassing the virtual filesystem entirely. Git works perfectly. Your notes still land in Google Drive within 60 seconds.

> **Important**: Do not manually move your workspace folder into Google Drive, iCloud Drive, OneDrive, or Dropbox. These all use FUSE-based virtual filesystems. If you do, git inside the container will fail silently. The installer places the workspace on a local path automatically — leave it there.

**What Pro changes — Knowledge Weaver**:
- AI scans your notes, extracts entities (people, projects, concepts, decisions), creates semantic relationships, and auto-links notes
- `/scan` to build the knowledge graph from your entire workspace
- `/explore` to quickly extract from a focused set of files
- Entities and relationships stored in Postgres for unlimited scale
- **Still Human-in-the-Loop**: KW proposes entities and relationships — you review what it found, correct misidentifications, and confirm before links are injected. No silent changes to your knowledge base.

---

### Knowledge Weaver Pro — Full Workflow

Knowledge Weaver builds your graph in **3 stages**. Run them in order.

#### Stage 1: Build the Graph — `/scan` (repeat until queue is empty)

This is the core indexing loop. Run `/scan` repeatedly until the queue reaches 0.

```
/scan
```

What happens each time you run it:
1. KW picks the next 5 unindexed notes from the queue
2. Reads each file (full read for small files; headings + frontmatter only for large files)
4. You review the extracted entities and relations — correct anything wrong
5. Approved results are written to Postgres (entities, observations, relations)
6. Files are marked `indexed` with a SHA-256 content hash (used by `/refresh-all` to detect future changes)

**What you see in the report:**
- Files processed this batch
- New entities, observations, relations added
- Files remaining in queue

> **Run `/scan` repeatedly** until "Remaining: 0". Default batch size is 5 notes per run.

**Choosing your batch size** — `/scan batch=N`

```
/scan batch=10     ← recommended for large workspaces (100+ notes)
/scan batch=5      ← default, safest extraction quality
/scan batch=3      ← use for very large individual files (>500 lines each)
```

Batch size trades off **speed vs. extraction quality** — it is not simply "bigger = faster":

| Batch | Speed | Quality | Notes |
|-------|-------|---------|-------|
| 3–5 | Slowest | Best | LLM context is light, all entities captured cleanly. Default. |
| 8–12 | **Fastest** | Good | Sweet spot. API overhead amortised, context still manageable. |
| 15–20 | Slower | Degrades | LLM context fills up → slower token generation, entities dropped at end of batch, more corrections needed. Net slower. |
| >20 | Slowest | Poor | Context overflows. Do not use. |

**Why batch=20 is slower than batch=10**: the LLM extracts entities from all files at once. A batch of 20 files can push 15,000+ tokens into a single call. The model generates tokens more slowly under full context pressure, and cheaper/free models may truncate output — meaning some files need re-scanning. The time saved on API round trips is lost to slower generation and corrections.

**Measured benchmark** (minimax-m2.5:free on a 150-note workspace):

| Batch size | Duration | Per file | Total for 150 notes |
|------------|----------|----------|---------------------|
| 5 (default) | ~7 min / run | ~1.4 min | ~3.5 hours |
| 10 | ~4 min / run | ~0.4 min | ~55 min |
| 20 (estimated) | ~5–6 min / run | ~0.3 min | ~1.2 hours + correction overhead |

> **Recommendation**: Use `/scan batch=10` once you have reviewed your first `/scan batch=5` batch and are confident in extraction quality. Do not exceed batch=12 on free-tier models.

**Recommended workflow: Two-Pass Review**

The most cost-efficient way to build a high-quality graph:

```
  → Fast, cheap, extracts ~80% of entities and relations correctly
  → Run until Remaining: 0

Pass 2 — Review with a strong model (switch Kilo to GLM 5 / Claude / GPT-4o)
  → Ask: "Review the extracted relations in kw_relations and flag any that look wrong"
  → Correct using /correct [entity] — [fix] for each identified error
  → Strong model reviews, it does not re-extract — costs only a fraction of full re-scan
```

**Why not use the strong model for extraction?**
The strong model is 5–10× slower and more expensive per API call. For the extraction step, the free model gets the majority of entities and relations right. The strong model pays off in the review step, where reasoning about relationship quality and directionality is genuinely better — not in raw extraction throughput.

**Real-world accuracy** (personal notes content):
- Most relations and entities will be correct without review
- A small fraction — typically relations with ambiguous directionality or overly generic types — benefit from strong-model or human correction
- Personal notes extract more cleanly than academic papers — everyday language has clearer subject-verb-object structure than dense domain jargon

> **Note on the benchmark in §6**: The 48%/47% F1 figures are measured on the SciER academic dataset (scientific papers). On personal notes, meeting summaries, and project documentation — the typical Zokai workspace — expect meaningfully higher first-pass accuracy before review.




#### Stage 2: Visualise — `/link` (run once after queue is empty)

Once the full graph exists in Postgres, inject wiki-links into your source notes for visual display in Foam:

```
/link
```

What happens:
1. Reads all relations from Postgres (`kw_relations`)
2. For each relation `A → USES → B`, opens `notes/A.md` and appends `- [[B]] — uses` to the `## Related` section
3. If `[[B]]` already exists → skips (idempotent, safe to run multiple times)
4. Foam's graph view (`Ctrl+Shift+P` → *"Foam: Show Graph"*) now shows the visual connections

> **Run `/link` after every major scan session** — not after every batch. Links are only as complete as the graph you have built so far.

#### Stage 3: Maintenance (on demand)

| Command | When to run | What it does |
|---------|-------------|--------------|
| `/status` | Any time | Shows entity/observation/relation counts, files indexed vs remaining, model in use |
| `/refresh-all` | After editing or deleting notes | Re-hashes all indexed files, detects changes and deletions, re-queues changed files |
| `/correct [entity] — [fix]` | When you spot a wrong observation | Updates the observation, marks it `is_human_corrected=TRUE` so it survives future refreshes |
| `/merge [A] [B]` | When two entities are duplicates | Merges B into A, transfers all observations and relations |
| `/prune` | After `/refresh-all` detects deletions | Removes entities whose source files were deleted and have no other observations |

#### What `/refresh-all` does in detail

After you delete or edit notes, KW needs to be told:

```
/refresh-all
```

1. Reads all rows from `kw_notes_index WHERE status='indexed'`
2. For each file: computes current SHA-256 hash and compares to stored `content_hash`
3. **File unchanged** → no action
4. **File changed** → marks `status='changed'` → re-queued for next `/scan`
5. **File deleted** → marks `status='deleted'`
6. Triggers `/prune` → entities whose observations are all from deleted files are removed from Postgres

> **Important**: Deleting a note does not remove its entities immediately. You must run `/refresh-all` + `/prune`. Entities shared with other notes (e.g. "Docker" mentioned in 5 files) survive even if one source is deleted.

#### The complete first-time setup sequence

```
1. /status          → confirm Postgres connected, 0 entities, model shown
2. /scan            → process first 5 files, review extraction, approve
3. /scan            → next 5 files
4. /scan            → (repeat until Remaining: 0)
5. /link            → inject wiki-links into all notes
6. Ctrl+Shift+P → "Foam: Show Graph"  → view your knowledge graph
```

**How well does extraction work?** We benchmark against the [SciER 2024 academic dataset](https://github.com/edzq/SciER) (Zhang et al., ACL 2024) — 50 scientific papers, 650 gold entities, 483 gold relations:

| Metric | Raw (AI only) | After human review (estimated) |
|---|---|---|
| Entity F1 | 48% | 70–80% |
| Relation F1 | 47% | 65–75% |

This is **77% of supervised SOTA** — with zero training data, pure zero-shot extraction. Human review is what closes the gap. The full benchmark — data, scripts, prompts, and results — will be published at [github.com/zokai-ai/zokai-kw-benchmark](https://github.com/zokai-ai/zokai-kw-benchmark) for full transparency and reproducibility. *(Coming soon.)*

---

## Chapter 7: Code & Automation

Kilo is a full AI coding agent. It can read your entire codebase semantically, write and edit files, run terminal commands, and fix test failures — all from the same chat interface where it drafts emails and schedules meetings. The workspace is the context. The terminal is the tool. Everything is connected.

**What you can do:**
- Semantic code search: *"find the authentication logic"* → results ranked by meaning, not just filename
- Code generation: *"add input validation to the signup form"*
- Refactoring: *"rename all instances of `userService` to `accountService`"*
- Run commands in the terminal: *"run the tests and fix any failures"*
- File operations: create, edit, delete, move files — you see every diff in Source Control before committing

**How codebase indexing works**:
1. Kilo uses Tree-sitter to parse your code into semantic blocks (functions, classes, methods)
2. Each block is embedded into a vector via the local embedding server (running inside Docker)
3. Vectors are stored in **Qdrant** for semantic similarity search, keyed by a `segmentHash` derived from the file path + chunk text
4. When you search, your query is embedded and matched against code blocks by meaning

> 📌 **This is Kilo's built-in file-search index (Qdrant + Tree-sitter)** — it indexes ALL workspace files including markdown notes, and is available in Free + Pro. This is **completely separate** from Knowledge Weaver (Pro), which extracts entities and relations into a Postgres graph. They run in parallel and serve different purposes:
> - **Kilo's file-search** → answers *"find the authentication logic"* by semantic similarity in Qdrant
> - **Knowledge Weaver** → answers *"what do we know about Docker?"* from the entity graph in Postgres

**What to expect**:
- Initial indexing: 2–5 minutes depending on codebase size
- Searches return in 1–3 seconds
- Code generation quality depends on the AI model — Claude/GPT-4+ recommended for complex tasks; the default free model (GLM-4.5 Air) handles simple tasks well
- **During initial indexing**: Email search and calendar always work normally — search requests get priority. You will not notice any slowdown in dashboard responsiveness.

**Re-indexing after a workspace restore (e.g. after cloud-sync recovers your notes)**:
If cloud-sync re-pulls your notes from Google Drive, Kilo detects those files as new or changed and starts a re-index pass in **Qdrant** (file-search index — not Knowledge Weaver). This is safe and expected:
- **No duplicates are created.** Each chunk is identified by its `segmentHash` (a content hash). If the file content is identical, the same hash re-upserts the existing vector — nothing is added. If content changed, the old vector is replaced.
- **Qdrant stays clean.** A full workspace re-index produces the same number of vectors, not more.
- **You will see** the Kilo indexing panel show `Indexing — X / N blocks found` again. This is cosmetic progress, not data loss or corruption.
- **What actually happened** in context: `cloud-sync token expired → notes disappeared from disk → cloud-sync restarted → notes re-pulled from Drive → Kilo detected new files → re-index triggered`. All of these are recoverable steps. Nothing is permanently lost.
- **Knowledge Weaver is not affected** by this re-index — the KW Postgres graph is independent of Qdrant. Your extracted entities and relations remain intact. Run `/refresh-all` separately if you need KW to detect file changes.


**Inherited limitations**:
- **Files >300KB are silently skipped** by Kilo's built-in indexer. Large PDFs, XLSX, DOCX are not searchable via semantic code search. This is the #1 user-reported limitation.
- Context window limits depend on the AI model (8K–128K tokens) — very large files may not fit in a single prompt
- One file edited at a time per tool call — multi-file refactoring takes multiple sequential steps
- Tool call reliability varies by model: Claude and GPT-4+ are consistent; smaller free models may occasionally skip tool calls or hallucinate file paths

**What Pro changes — Deep Index (gap-indexer)**:
- Indexes ALL files regardless of size: PDFs, Excel, Word, images with text, any binary that can be extracted
- Automatic: drop a file into your workspace → searchable within ~2 minutes
- 423-page PDF: ~3 minutes to index, fully chunked and semantically searchable

---

## Chapter 8: AI Agents — Your Keys, Your Choice

Zokai does not bundle an AI model. It connects to any model you choose, on any provider, with your own keys — and it runs that model against your private workspace data locally. This means you are never locked into one vendor, never subject to a price increase you did not agree to, and never forced to send your data to a provider you do not trust.

**What you can do:**
- Connect any AI model: **local** (Ollama, MLX, LM Studio) or **cloud** (OpenRouter, OpenAI, Anthropic, Gemini)
- Switch models at any time — different tasks can use different models
- Use agent modes: Code, Plan, Debug, **Zokai Guide** (each optimised for a different work style)
- Default free model (GLM-4.5 Air via Nebius) requires no key and works out of the box

**How to configure your AI model**:

Open `zokai-config.json` in your workspace:

```json
{
  "OPENAI_BASE_URL": "https://openrouter.ai/api/v1",
  "OPENAI_API_KEY": "sk-or-your-key-here"
}
```

- **Default (Free)**: GLM-4.5 Air via Nebius — connected automatically, no key needed
- **Recommended**: [OpenRouter](https://openrouter.ai) key ($5 credit to start) → access to Claude, GPT-4o, Gemini, 500+ models
- **Local**: Point `OPENAI_BASE_URL` to `http://host.docker.internal:11434/v1` for Ollama

**The three deployment modes** (same workspace, different AI):

| Mode | Where AI runs | What leaves your machine | Best for |
|---|---|---|---|
| **Cloud** | OpenRouter, OpenAI, Anthropic, etc. | Your prompts + context sent to provider | Power, speed, model variety |
| **Local** | Ollama or MLX on your hardware | Nothing | Maximum privacy, air-gapped environments |
| **Hybrid** | Mix of both | Only what you route to cloud | Balance of capability and privacy |

**Switching models does not require reindexing** — your Qdrant vector database is separate from the chat model. Search quality depends on the *embedding model* (separate from the chat model; configured via `EMBEDDING_BASE_URL` — see Appendix A for how to change it).

**Inherited limitations**:
- Local models require significant hardware: 8GB+ RAM for small models, 32GB+ for capable coding models
- The default free model (GLM-4.5 Air) is capable for straightforward tasks but may struggle with complex multi-step agentic workflows
- Tool call reliability varies by provider and model — if a tool call fails, try rephrasing or switching to a more capable model

---

## Chapter 9: The Dashboard

The Dashboard is the control surface for your station — a single browser tab that shows what your AI is doing, what is in your inbox, and what is on your calendar, all at once. It is designed to be glanceable: you should be able to open it and understand the state of your day in under ten seconds.

**What you see (Free)**:
- **Email panel** — latest emails, search bar, attachments, download to workspace
- **Calendar panel** — today's events, upcoming week, create/edit/RSVP in place

**How to open**:
- It opens automatically on launch in your default browser
- Direct URL: `http://localhost:8080` (or the port shown in your `access.txt`)
- From VS Code: `Ctrl+Alt+D` inside the editor

**What to expect**: The dashboard refreshes via SSE (Server-Sent Events) — email and calendar updates stream in near-real-time after each sync cycle, without a page reload.

> 🎬 *[See it in action: AI curates a news digest](https://youtu.be/klV9WiVHHso)* — your inbox summarised and organised by AI.

**What Pro adds to the Dashboard**:
- **Task panel** — open tasks from mcp-tasks, shown as a list sorted by priority
- **Health status** — service health indicators (green = up, grey = not connected)
- **Kanban board** — drag-and-drop task management (To Do → In Progress → Done), synced with the MCP task system
- **Ideas board** — capture, organise, and label ideas with a masonry card layout and inline editing. Kilo can also create idea cards proactively during conversations.
- **Raindrop bookmark integration** — your Raindrop bookmarks sync into the Ideas board as link cards (cover image, domain, tags). Kilo can search and reference your saved bookmarks. **Setup**: add your Raindrop API key to `zokai-config.json` as `RAINDROP_API_KEY` — same pattern as Tavily, no restart needed.
- **Direct MCP actions** — search, compose email, RSVP, create tasks — all without switching to Kilo's chat panel

---

## Act III: The Flow

---

## Chapter 10: Research → Ingest → Connect → Draft → Edit → Act → Deepen

The end-to-end workflow that most AI tools cannot do:

```
Research    → AI gathers information (web, docs, YouTube)
  ↓
Ingest      → Email, calendar, files indexed into your workspace
  ↓
Connect     → Knowledge graph links related information (Pro: auto-linked by KW)
  ↓
Draft       → AI proposes content (email reply, report, code change)
  ↓
Edit        → You review every change (Zokai Viewer diffs, Source Control)
  ↓
Act         → Send the email, commit the code, schedule the meeting — your call
  ↓
Deepen      → What you approved becomes context for the next cycle
  ↑___________↓
```

**Worked example: The Invoice Controller** (from demo video)

1. **Ingest**: Drop a PDF invoice into your workspace → gap-indexer extracts text, chunks, and embeds it (Pro; Free: use Markdownify to convert first)
2. **Connect**: Kilo cross-references the invoice against your Postgres database (commission rates, contract records, partner history)
3. **Draft**: Kilo writes an audit report flagging €16,000 in phantom contracts — with evidence cited
4. **Edit**: You review the report in Zokai Viewer — green lines show AI findings, nothing committed yet
5. **Act**: You approve the report, then ask Kilo to draft an email to the vendor with the discrepancy analysis attached
6. **Deepen**: Kilo generates a reusable workflow template (`commission-invoice-check.md`) in your notes:

> *"Follow the instructions in @workflow/commission-invoice-check.md to process the invoice @mail-attachments/invoice_finanzhaus_mueller.pdf"*

Different partner, different invoice — same rigour. One prompt. The workflow template is your compounding asset.

> 🎬 *[Watch this workflow](https://youtu.be/tirmY4EfeqA)* — AI audits a commission invoice, queries the database, catches €16,000 in phantom contracts.

**Worked example: The Newsletter Digest** (from demo video)

1. **Ingest**: Newsletter arrives in Gmail → auto-indexed at the next sync cycle
2. **Research**: Kilo reads the newsletter, identifies key claims and sources
3. **Connect**: Cross-references with your notes and previous newsletters
4. **Draft**: Synthesised digest with fact-check annotations and highlighted key points
5. **Edit**: You approve the summary, adjust highlights, add your own commentary
6. **Act**: Forward to your team with one email draft command
7. **Deepen**: Kilo saves the digest workflow as a template:

> *"Process the email 'AI Research Monthly: The February 2026 Reality Check' according to @workflow/ai_newsletter_workflow.md"*

One prompt. Same quality every month. The template does the work.

> 🎬 *[Watch this workflow](https://youtu.be/klV9WiVHHso)* — AI curates a news digest from Gmail.

---

## Act IV: The Knowledge Tree

---

## Chapter 11: Growth Through Accumulation

> *Most tools are the same on day one and day one thousand. Zokai gets more useful as you put more into it.*

Every email you index, every note you write, every project you work on expands the searchable context available to Kilo. The more your workspace contains, the more precisely Kilo can answer questions and cross-reference information. This compounds over time — not by magic, but by accumulation. Your workspace is the memory.

**How your station gets smarter over time**:

| Week 1 | Month 1 | Month 6 |
|---|---|---|
| 50 emails indexed | 500 emails indexed | 3,000+ emails indexed |
| 10 notes, search works | 50 notes, searchable | 200+ notes, searchable corpus |
| Basic code context | Full codebase indexed | Multiple projects indexed |
| Kilo can find files and emails | Kilo can cross-reference projects | Kilo has years of your work to draw from |

**Version control as audit trail**:
- Every change tracked by Git — built into VS Code's Source Control panel
- Zokai Viewer shows exactly what the AI wrote before you commit
- Full history: `git log` shows when the AI created or modified every file
- Branches for experiments — try an approach without affecting your main workspace

**Inherited limitation**: Knowledge compounds only within this installation. Multiple Zokai installations on different machines do not share context automatically (yet). If you reinstall, your emails and calendar data are re-synced from Google; your notes and workspace files come from your Git repository.

**What Pro changes — Knowledge Weaver**:
- Turns accumulation from **passive** (you manually link notes) to **active** (AI links notes for you)
- Postgres-backed entity database — fast queries like *"show me everything related to Project Phoenix"*
- Batch workspace scanning — AI processes your entire vault, not one file at a time
- Human-confirmed corrections feed back into the graph — it gets more accurate as you use it

---

## Act V: Trust & Transparency

---

## Chapter 12: Privacy — You Decide What Stays Local

Every AI tool you use is a decision about where your data goes. Most tools — even ones marketed as "private" — route your queries through a vendor's infrastructure, where they can be logged, analysed, or used for model training. Zokai's architecture starts from the opposite assumption: nothing leaves your machine unless you explicitly choose it.

- **Local-First**: Everything runs on your machine via Docker. Emails, calendar, notes, AI conversations — all stored on your hardware, not in anyone else's cloud.
- **You Own Your Keys**: OAuth tokens for Google and API keys for AI providers are stored in local Docker secrets. We never see them — they never leave your machine.
- **What Goes Online**: Only what you choose. Gmail and Calendar API calls go to Google (with your OAuth consent). Optionally, prompts go to an LLM provider. Everything else — embedding, search, storage, agents — is local.
- **No Telemetry**: Zero usage data, crash reports, or analytics are collected. There is no phone-home.
- **GDPR Aligned**: Built in Germany. European data protection principles by design. No tracking, no advertising, no data monetisation.

**The privacy spectrum for embeddings** (how your files are made searchable):

| Mode | Speed | Privacy | Cost | How to configure |
|---|---|---|---|---|
| Local Docker (default) | ~1s/chunk | Maximum — nothing leaves Docker | Free | No change needed |
| Cloud + ZDR (Zero Data Retention) | ~50ms/chunk | Data processed, not stored by provider | Per token | Set `EMBEDDING_BASE_URL` to an OpenRouter endpoint with ZDR enabled |
| Cloud standard | ~50ms/chunk | Provider may retain data for up to 30 days | Per token | Set `EMBEDDING_BASE_URL` to any compatible provider |

**Full privacy policy**: [zokai.ai/privacy](https://zokai.ai/privacy)

---

## Chapter 13: Deploy Anywhere

> *Nothing is locked in.*

Run on your laptop, a dedicated server, or in the cloud. Switch providers, switch modes, switch hardware — your workspace files and notes travel with you via Git. The Docker containers rebuild from the same configuration on any machine.

| Platform | How to run |
|---|---|
| **macOS** | DMG installer → double-click → Zokai opens as a standalone browser window |
| **Windows** | ZIP + PowerShell installer → Desktop shortcut → one-click launch |
| **Cloud / Server** | `docker compose up -d` on any Docker-capable Linux server |
| **Demo** | [demo.zokai.ai](https://demo.zokai.ai) — try it without installing anything |

**To move your workspace to a new machine**:
1. Push your workspace to a Git remote (GitHub, GitLab, or self-hosted)
2. Install Zokai on the new machine
3. Clone your workspace repository into the workspace folder
4. Re-run OAuth — your Google tokens reconnect automatically

---

## Chapter 14: What We Know Doesn't Work (Yet)

> **Design intent**: Honesty builds trust. You should read this chapter and think *"they told me upfront"* rather than discovering these through frustration.

**Kilo Code (AI Agent)**:
- **File size indexing cap (~300KB)** in Free tier — this is the #1 inherited limitation. Large PDFs, XLSX, DOCX are silently skipped by Kilo's built-in indexer. Pro's Deep Index removes this entirely.
- Context window limits depend on the AI model (8K–128K tokens) — very large files may not fit in a single prompt even if indexed
- Tool call reliability: Claude/GPT-4+ are consistent; smaller free models may occasionally skip tool calls or produce wrong file paths
- No multi-file editing in a single tool call — large refactoring tasks require multiple sequential steps
- Kilo cannot interact with GUIs or click through visual browser interfaces

**Knowledge Weaver (Pro)**:
- Raw extraction accuracy: 48% entity F1, 47% relation F1 — **not perfect, not magic**. Human review is expected and built into the workflow.
- Coverage depends on the LLM's iteration discipline — some model/prompt combinations process 48–100% of files per scan
- Relation type vocabulary is broader than academic benchmarks — false matches are possible, especially for abstract concepts
- Full benchmark data will be published at [zokai-kw-benchmark](https://github.com/zokai-ai/zokai-kw-benchmark) — *(coming soon)*

**VS Code (code-server, browser-based)**:
- Some desktop VS Code extensions don't work (notably GitHub Copilot, some language debuggers)
- Extension marketplace is Open VSX, not Microsoft's — some extensions are missing or on older versions
- Terminal keybindings may differ from your desktop environment (Ctrl+C/V behaviour in particular)

**Docker**:
- Requires Docker Desktop on Mac/Windows — approximately 2GB of disk overhead for the runtime alone
- First start: 3–5 minutes to pull images and start all containers (subsequent starts: <60 seconds)
- File I/O through Docker volumes can be slower than native filesystem, especially on macOS with large workspaces
- Docker Desktop must be running for Zokai to work — there is no standalone binary yet

**Gmail & Calendar (Google APIs)**:
- OAuth token refresh: occasional re-authentication may be needed if you are inactive for extended periods
- Maximum 50 emails per sync batch due to Google API rate limits — deep sync processes pages sequentially
- Gmail labels beyond inbox/sent/draft are not fully exposed in the dashboard
- Calendar free/busy view is not available
- Google Workspace administrators may restrict OAuth consent for organisational accounts

**Notes sync (Cloud Sync)** *(Free + Pro)*:
- The cloud-sync service keeps your Zokai Notes folder in sync with Google Drive (bidirectionally, every 60 seconds). It is included in both tiers but only activates after you connect your Google account (**Dashboard → Connect Google Account**). Without authentication, the service stays idle.
- If the OAuth token expires while the container is running, sync fails silently — notes in Google Drive will not appear in the workspace until the container is restarted
- **How to know if sync has stopped**: A file called `SYNC_UNHEALTHY` will appear in `.zokai/` inside your workspace (visible in VS Code's Explorer panel as a red untracked file) after 3 consecutive failed sync cycles (~3 minutes). Open the file for the exact error and fix instructions.
- **Fix**: `docker compose restart cloud-sync` — this forces a fresh token refresh and restarts the sync daemon. If that does not work, re-authenticate via **Dashboard → Reconnect Google Account**.

**Search (Qdrant)**:
- Cold start after container restart: first search takes ~2–3 seconds (model loading)
- No fuzzy/typo tolerance — vector search matches by meaning, not exact characters
- Semantic quality depends on the embedding model — niche domain jargon may not match intuitively

**Web Research (GPTR + Tavily)**:
- Tavily free tier: 1,000 searches/month
- Paywalled or JavaScript-heavy sites may not extract cleanly
- Research continuity depends on explicitly referencing previous reports — Kilo does not auto-link research sessions across prompts

---

## Chapter 15: Free vs. Pro — What Changes

> *Free is not a demo. It is the full vision. Pro removes the walls.*

**What both tiers share** — everything that matters for daily AI-assisted work:

| Capability | Free | Pro |
|---|---|---|
| **AI Agent (Kilo)** | ✅ Full | ✅ Same |
| **LLM Models** | ✅ GLM-4.5 Air + bring your own key | ✅ Same |
| **Email & Calendar** | ✅ Search + draft + RSVP + attachments + deep sync (5k) | ✅ Same |
| **Web Research** | ✅ Full (Tavily key required) | ✅ Same |
| **Notes + Zokai Viewer** | ✅ Full | ✅ Same |
| **Google Drive Notes Sync** | ✅ Bidirectional sync with "Zokai Notes" Drive folder (requires Google account) | ✅ Same |
| **Version Control (Git)** | ✅ Full | ✅ Same |
| **Dashboard** | ✅ Email + Calendar | ✅ Same + Tasks, Health, Kanban, Ideas |
| **License** | AGPL-3.0 (open source) | Commercial |

**What Pro adds** — capabilities that do not exist in Free:

| Capability | Free | Pro |
|---|---|---|
| **Deep Index** | − Files >300KB silently skipped | + All files indexed — PDFs, Excel, Word, any size |
| **Knowledge Weaver** | − Manual note linking only | + AI entity extraction, auto-linking, `/scan`, `/explore` |
| **GRID** | − | + AI-native spreadsheet — query, analyse, and visualise data like Excel, powered by AI |
| **Dashboard boards** | − Email + Calendar panels only | + Task panel, Health status, Kanban, Ideas board |
| **Raindrop bookmarks** | − | + Raindrop MCP — bookmarks sync into Ideas board, Kilo can search them (`RAINDROP_API_KEY` in `zokai-config.json`) |
| **Database Access** | − | + Postgres MCP — Kilo queries SQL databases directly |
| **Task Management** | − Markdown lists only | + mcp-tasks + Postgres-backed tasks + Kanban drag-and-drop |

---

## Appendices

---

## Appendix A: Changing Your Embedding Provider (Destructive Operation)

> ⚠️ Different embedding models produce different-sized vectors. Switching providers requires dropping all search indexes and reindexing everything from scratch.

**When you would do this**:
- Switching from local (slow) to cloud embedding (fast) for large workspaces
- Changing models — e.g., from `jina-v2-base-de` (768d) to `text-embedding-3-small` (1536d)
- Corporate migration to a centralised internal embedding server

**Step-by-step**:

1. Stop all containers:
   ```bash
   docker compose down
   ```

2. Update `zokai-config.json` (or `.env`):
   ```json
   "EMBEDDING_BASE_URL": "https://openrouter.ai/api/v1",
   "EMBEDDING_API_KEY": "your-key",
   "EMBEDDING_MODEL_ID": "openai/text-embedding-3-small",
   "VECTOR_SIZE": "1536"
   ```

3. Update Kilo settings JSON — set the `embedder` provider, base URL, and model to match

4. Delete all Qdrant collections:
   ```bash
   curl -X DELETE http://localhost:6333/collections/ws-your-workspace
   curl -X DELETE http://localhost:6333/collections/emails
   curl -X DELETE http://localhost:6333/collections/calendar_events
   curl -X DELETE http://localhost:6333/collections/workspace_docs
   ```

5. Restart:
   ```bash
   docker compose up -d
   ```

6. Wait for all services to reindex:
   - Codebase: 2–5 minutes for a medium project
   - Emails: depends on inbox size (5,000 emails ≈ 5–10 minutes)
   - Documents: depends on workspace size

**Estimated reindex time**: 200-page PDF ≈ 2 min | 500 emails ≈ 5 min | medium codebase ≈ 3 min

> **Note**: Your email and calendar data in Google is not affected — only the local Qdrant search index is rebuilt. All data re-syncs from Google automatically.

---

## Appendix B: Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Dashboard blank / won't load | Nginx container not running | `docker compose restart nginx` |
| Email not syncing | OAuth token expired | Dashboard → **Reconnect Google Account** |
| Search returns nothing | Embedding server still warming up, or model mismatch | `docker compose logs embedding-server` — look for model loaded message |
| Kilo unresponsive | Extension host crashed | `docker compose restart vs-code` |
| "Connection refused" errors | Docker Desktop not running | Start Docker Desktop, then relaunch Zokai |
| Slow performance on first start | Images being pulled, containers starting | Wait 3–5 min. Check progress with `docker compose logs -f` |
| Browse Lite error after restart | Stale browser lock file | Restart the vs-code container: `docker compose restart vs-code` |
| Zokai Viewer shows **401 Unauthorized** | Browse Lite's embedded browser holds a stale session cookie after code-server restarts or the session expires | Hard-refresh the browser tab (**Ctrl+Shift+R** / **Cmd+Shift+R**), then re-open the file in the viewer. The embedded browser re-acquires a valid session cookie automatically. |
| Calendar events showing in UTC | Timezone not configured | Check that your system clock matches your timezone; container inherits host TZ |
| Kilo says it can't find a large file | File >300KB skipped by indexer | Use Markdownify to convert: *"Convert this PDF to markdown"* (Free); Pro: Deep Index handles this automatically |
| Embedding server 503 errors during sync | Too many concurrent indexing requests | Wait — backpressure is automatic. Search requests are always prioritised. |
| "Docker daemon not running" | Docker Desktop closed or crashed | Reopen Docker Desktop. On Windows: check the system tray. On macOS: check the menu bar. |
| **Notes not appearing / workspace out of date** | Cloud-sync stopped — OAuth token expired while container was running | Look for a red `SYNC_UNHEALTHY` file in `.zokai/` in your workspace. If present: `docker compose restart cloud-sync`. If not: check `docker compose logs cloud-sync \| tail -20` for errors. |
| **`SYNC_UNHEALTHY` file appeared in workspace** | Cloud-sync has failed 3+ consecutive cycles | Open the file — it contains the exact error. Fix: `docker compose restart cloud-sync`. The file disappears automatically once sync recovers. |
| **After `docker compose restart cloud-sync`, all notes show as uncommitted** | Sync-state was reset — full re-pull from Drive detected all files as "new" | This is cosmetic. The files are correct. In Source Control: stage all → commit with message *"sync state reset after cloud-sync restart"*. Or run `git add -A && git commit -m "sync reset"` in the terminal. |
| **KW: deleted notes still show entities** | Files deleted but `/refresh-all` not run yet | Run `/refresh-all` then `/prune` in Kilo (Knowledge Weaver mode). This detects deleted files and removes orphaned entities. |
| **KW: `/refresh-all` treats all files as changed** | `content_hash` was NULL (indexed before fix) | Run a one-time backfill — ask Kilo: *"Run kw_status to check how many files have null content_hash"* — or contact support. |

---

## Appendix C: MCP Tool Reference

Kilo has access to the following tools via the Model Context Protocol. These are the actions Kilo can take on your behalf:

| MCP | Tool | What it does |
|---|---|---|
| **Gmail** | `search_email_memory` | Semantic search across indexed emails (BM25 + dense) |
| **Gmail** | `get_recent_emails` | Retrieve latest emails from Gmail |
| **Gmail** | `create_draft` | Create a draft email |
| **Gmail** | `create_reply_draft` | Create a reply to an existing email |
| **Gmail** | `send_email` | Send a draft (requires your confirmation) |
| **Calendar** | `list_events` | List upcoming calendar events |
| **Calendar** | `create_event` | Create a new calendar event |
| **Calendar** | `update_event` | Edit an existing event |
| **Calendar** | `delete_event` | Delete an event (with optional series scope) |
| **Calendar** | `respond_to_event` | RSVP (accept / decline / tentative) |
| **GPTR** | `deep_research` | Run a multi-source web research report |
| **YouTube** | `get_transcript` | Fetch and process a YouTube video transcript |
| **GitHub** | `search_repositories`, `create_issue`, `list_pull_requests` | GitHub repository actions |
| **Postgres** | `query`, `execute` | Query or write to a connected Postgres database (Pro) |
| **Markdownify** | `convert_url`, `convert_file` | Convert URLs or files (PDF/XLSX/DOCX) into markdown |
| **mcp-tasks** | `list_tasks`, `add_task`, `update_task` | Read and write tasks in the task manager |
| **Qdrant Memory** | `remember`, `recall` | Store and retrieve memories across sessions |
| **KW Extractor** *(Pro)* | `kw_extract` | Send a file batch to the extraction LLM → returns entities + relations JSON |
| **KW Extractor** *(Pro)* | `kw_save` | Write approved entities/relations to Postgres in one transaction |
| **KW Extractor** *(Pro)* | `kw_status` | Return entity/observation/relation counts + model name from Postgres |
| **KW Extractor** *(Pro)* | `kw_search` | Fuzzy-match entity names in the knowledge graph |

> *The full tool registry with parameter schemas is auto-generated from the running MCP servers. Ask Kilo: "List all the tools you have available."*

---

## Appendix D: Architecture Map

Zokai Station runs as a set of Docker containers organised into four isolated networks:

```
┌─────────────────────────────────────────────────────────────────┐
│  FRONTEND NETWORK (172.21.0.0/16)                              │
│  VS Code (code-server) + Kilo Code + Browse Lite               │
│  Nginx Reverse Proxy                                            │
│  Port: 8080 (Free) │ 8082 (Pro) │ 8080 (MKN)                  │
└────────────────────┬────────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────────┐
│  BACKEND NETWORK (172.22.0.0/16) — has internet access          │
│  Gmail MCP (8007) │ Calendar MCP (8008) │ GPTR MCP (8000)      │
│  YouTube MCP      │ GitHub MCP          │ Markdownify MCP       │
│  Postgres MCP (Pro) │ mcp-tasks (8006)  │ Gap Indexer (Pro)     │
└────────────────────┬────────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────────┐
│  DATA NETWORK (172.23.0.0/16) — internal only, NO internet      │
│  Qdrant (6333)      — vector database (emails, calendar, code)  │
│  Embedding Server (7997) — FastEmbed, local jina-v2-base-de     │
│  Redis (6379)       — rate limiting, caching                    │
│  Postgres (Pro)     — task DB, KW entity graph                  │
└─────────────────────────────────────────────────────────────────┘
```

**Data flows**:
- Your prompts travel: Browser → Nginx → VS Code → Kilo → MCP bridge → MCP container → action
- Email search: Dashboard → Nginx → Gmail MCP → Qdrant (local) → Embedding Server (local)
- No data leaves the DATA network — Qdrant and the Embedding Server have no internet access by design

**Key ports** (from your host machine):
| Service | Port |
|---|---|
| Dashboard / VS Code | 8080 (8081 Free, 8082 Pro) |
| Qdrant UI | 6333 |
| OAuth callback | 9002 |

**All source code** (except Pro-tier proprietary containers) is published under AGPL-3.0 at [github.com/Mkn501/zokai-station](https://github.com/Mkn501/zokai-station).

---

*Zokai Station User Manual — v1.1 — 2026-04-19*
*Built in Germany. Sovereign by design.*
