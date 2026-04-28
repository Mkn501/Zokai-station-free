# Zokai™ Station

> **A self-hosted, containerized AI workstation with integrated IDE, semantic search, and MCP-powered productivity tools.**
>
> *Zokai™ (増加 + AI) — "growth through AI"*

[![Version](https://img.shields.io/badge/version-0.9.1-blue)]() [![License](https://img.shields.io/badge/license-AGPL--3.0-green)](LICENSE) [![Docker](https://img.shields.io/badge/docker-24.x+-blue)]()

---

## What is Zokai Station?

Zokai Station is a **portable AI workstation** that runs entirely on your machine via Docker. It gives you a web-based VS Code IDE, a built-in AI coding agent (Kilo Code), email and calendar intelligence, vector-powered semantic search, and deep web research — all in a single setup.

No cloud account required. Your data stays on your machine — only LLM prompts are sent to the API provider you choose (or stay fully local with Ollama or LM Studio).

### Included Tools

| Tool | What it does |
|---|---|
| 🖥️ **VS Code (web)** | Full browser-based IDE — access from any device on your network |
| 🤖 **Kilo Code** | AI coding agent wired to your codebase and every tool below |
| 📊 **Zokai Dashboard** | Integrated dashboard for Gmail and Calendar |
| 👁️ **Zokai Viewer** | WYSIWYG markdown editor with diff coloring — write and review docs without touching raw code, synced with Git |
| 📧 **Gmail + Calendar** | Semantic email search, draft replies, accept or decline calendar invites |
| 🔍 **Semantic Search** | Qdrant vector DB — indexes your emails, calendar entries, and markdown notes for AI-powered search |
| 📝 **Zokai Notes** | Wiki-style knowledge base with `[[links]]` and graph view |
| 🌐 **Deep Research** | Web research via GPTR — powered by Tavily (free key required) |
| 📄 **Document Reader** | Convert PDF, DOCX, XLSX → Markdown for AI context |
| 🎬 **YouTube** | Extract transcripts and metadata from YouTube videos for AI context |
| 🔀 **Git** | Built-in version control — track changes, branch, and commit from the IDE |
| 🔒 **Privacy-First** | Your data stays on your machine — no telemetry, no vendor lock-in. LLM calls go to whichever provider you choose (or stay fully local with Ollama or LM Studio). |

### AI Models

Zokai Station is **LLM-agnostic** — it works with any OpenAI-compatible provider:

| Setup | How it works |
|---|---|
| ☁️ **API (default)** | Connect to OpenRouter, OpenAI, Anthropic, or Google — your key, your cost. The free default uses **GLM-4.5 Air via OpenRouter** (free tier). |
| 🏠 **Local LLM** | If you have a local model server (Ollama, LM Studio, etc.), point Zokai at it for 100% offline operation — no API key needed. |

### See it in Action *(video walkthroughs coming soon)*

- **AI generates a slide deck** from a single prompt (44s)
- **AI curates a news digest** from your inbox (2m)
- **AI builds a commission controller** — audits invoices, catches phantom contracts (2m)

### Free vs Pro

This is the **Free tier** — fully functional, no time limit, no feature crippling. The Pro tier adds power tools for professionals:

| Capability | Free | Pro |
|---|:---:|:---:|
| AI agent + IDE + all MCP tools | ✅ | ✅ |
| Gmail, Calendar, YouTube, Web Research | ✅ | ✅ |
| Semantic search (emails, notes) | ✅ | ✅ |
| **Database tools** (Postgres MCP) | — | ✅ |
| **Deep Index** (PDF, XLSX, DOCX search) | — | ✅ |
| **Knowledge Weaver** (auto entity extraction) | — | ✅ |
| **Google Drive sync** | — | ✅ |
| **GitHub MCP** | — | ✅ |
| **[Raindrop](https://raindrop.io) bookmark MCP** | — | ✅ |
| **Kanban board + Ideas board** | — | ✅ |

> **Upgrade anytime** — Pro uses a separate data directory so both tiers can run side-by-side. More at [zokai.ai](https://zokai.ai).
---

## System Requirements

| | Minimum | Recommended | Optimal |
|---|---|---|---|
| **RAM** | 16 GB ⚠️ | 24 GB | 32+ GB ✅ |
| **Disk** | 10 GB free | 20 GB free | SSD recommended |
| **CPU** | 4 cores | 6+ cores | Apple M-series / modern x86 |
| **OS** | macOS 13+, Windows 10+ | macOS 14+, Windows 11 | macOS (Apple Silicon) |
| **Docker Desktop** | 24.x+ | Latest | Latest |
| **Browser** | Chrome or Chromium | Chrome | Chrome |

> ⚠️ **Docker Desktop RAM**: Make sure Docker Desktop is allocated at least **8 GB RAM** in **Settings → Resources → Memory**. The macOS default (4 GB) is not enough — the containers alone need ~6.5 GB.

### The Cost of Sovereignty

Zokai Station runs **~20 Docker containers locally** — a full AI workstation including IDE, vector database, embedding engine, MCP services, and productivity tools. This is what keeps your data on your machine instead of someone else's server.

Here's what that costs in RAM:

| Service Group | What it does | Idle RAM |
|---|---|---|
| **VS Code + AI agent** | Browser-based IDE + Kilo Code | ~1,600 MB |
| **Embedding server** | Local text→vector conversion (FastEmbed) | ~800 MB |
| **Deep Research (GPTR)** | Web research agent | ~800 MB |
| **Qdrant + Redis** | Vector search + caching | ~230 MB |
| **Gmail + Calendar + Ingestor** | Email/calendar intelligence | ~450 MB |
| **MCP services** (7×) | YouTube, Tavily, GitHub, Tasks, etc. | ~370 MB |
| **Nginx + system services** | Proxy, secrets, config | ~210 MB |
| **Docker VM overhead** | Kernel, filesystem cache, page tables | ~1,500 MB |
| **Total** | | **~6,000 MB containers + ~1,500 MB VM** |

**On a 16 GB machine**: macOS/Windows uses ~10 GB at idle. Docker adds ~7.5 GB. That leaves ~0 GB for your browser and other apps — which means swap thrashing and visible slowness.

**On a 24 GB machine**: Comfortable. ~6 GB headroom for browsing, documents, and development tools.

**On a 32+ GB machine**: Optimal. Full headroom for everything, including heavy AI workloads and local LLM inference.

### Which mode is right for you?

| Your hardware | Recommended setup | Experience |
|---|---|---|
| **Apple Silicon Mac (24-64 GB)** | Full Local | ⭐ Best — all services, fast embedding |
| **Modern PC (24+ GB, SSD)** | Full Local | Great — all services run comfortably |
| **Older laptop (16 GB)** | Full Local (tight) | Functional — expect some swap pressure |
| **Thin client / Chromebook** | Cloud deploy | Browser only — run Zokai on a server, access remotely |

> **Why not just make it lighter?** We could — by sending your emails, calendar, and documents to a cloud API for processing. But that would defeat the purpose. The resource footprint is the price of keeping everything local. We believe it's worth paying.
>
> We're actively working on **Resource-Lite configurations** that reduce RAM usage for smaller machines — including optional cloud embedding for users who are comfortable with that trade-off. Follow our [roadmap](https://zokai.ai) for updates.

---

## Installation

### Step 1 — Install Docker Desktop (required)

Zokai Station runs inside Docker containers. You need Docker Desktop installed and running **before** you start the installer.

| Platform | Download |
|---|---|
| 🍎 **macOS** | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) — choose **Apple Silicon** or **Intel** |
| 🪟 **Windows** | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) — requires WSL2 (the installer enables it) |

> 💡 Docker Desktop is free for personal use. After installing, **open it once** and let it finish its initial setup before running the Zokai installer.

### Step 2 — Get your API keys (5 min, while Docker installs)

Zokai Station needs two API keys for the best experience. Both have free tiers, no credit card required:

| Key | What it does | Get it |
| :--- | :--- | :--- |
| **OpenRouter** | Routes your prompts to LLMs (GLM-4.5 Air is free) | [openrouter.ai/keys](https://openrouter.ai/keys) |
| **Tavily** | Powers web research — 1,000 free searches/month | [tavily.com](https://tavily.com) |

> 💡 Without an OpenRouter key, Kilo Code won't be able to call any AI model. Without a Tavily key, the direct web search tool won't be available, and deep research will fall back to DuckDuckGo (less accurate).

---

### macOS — DMG installer (easiest)

⬇️ **[Download ZokaiStation-free-v0.9.1.dmg](https://github.com/Mkn501/Zokai-station-free/releases/download/v0.9.1/ZokaiStation-free-v0.9.1.dmg)**

1. Double-click the downloaded DMG
2. Double-click **Zokai Station Installer**
3. Follow the on-screen prompts — takes 10–20 min on first run

> ⚠️ **macOS security warning**: Zokai Station is not yet signed with an Apple Developer certificate, so macOS Gatekeeper will block it on first launch. This is expected for open-source, independently distributed apps — it does **not** mean the software is unsafe.
>
> **To allow the app:**
> 1. Double-click the installer — macOS will show *"Zokai Station Installer can't be opened because it is from an unidentified developer"*
> 2. Open **System Settings → Privacy & Security**
> 3. Scroll down to the **Security** section — you'll see the blocked app listed
> 4. Click **Open Anyway** and enter your Mac password
> 5. A final confirmation dialog appears — click **Open**
>
> The app is now saved as an exception and will open normally from now on.
>
> **Alternative**: Right-click (or Control-click) the installer and select **Open** — this bypasses the block directly.

> 💡 The installer will ask for your OpenRouter and Tavily keys during setup, then download and start everything automatically.

> ⚡ **Keep your machine plugged in and awake** during the entire installation. If your laptop sleeps or hibernates mid-install, Docker loses its connection and the installer may freeze. On Windows: go to **Settings → Power → Screen and sleep** and set sleep to **Never** until installation completes.

**What happens during install:** The installer downloads Docker images (~2 GB), builds 16 service containers, configures your workspace, and starts all services. Progress is shown in the installer dialog. This takes 10–20 minutes on a fresh install; subsequent starts are near-instant.

That's it! Your workstation opens automatically at **http://localhost:8081** when ready. The page may be blank for a moment while services start — the Zokai splash screen will appear shortly, followed by the login page.

▶ **[Watch the install walkthrough (YouTube)](https://youtu.be/3Wy6CjDr0rs)**

---

### Windows — install-free.bat

⬇️ **[Download ZokaiStation-free-v0.9.1-windows.zip](https://github.com/Mkn501/Zokai-station-free/releases/download/v0.9.1/ZokaiStation-free-v0.9.1-windows.zip)**

**Steps:**
1. Extract the ZIP to a **short path** (e.g. `C:\zokai`)
   > Windows has a 260-character path limit. Deep paths like `C:\Users\Name\Downloads\...\` may fail.
2. Double-click **`install-free.bat`**
3. A folder picker dialog will appear — choose where to store your workspace
4. Enter your OpenRouter and Tavily API keys when prompted
5. Wait 10–20 minutes for the initial container build

The launcher automatically checks Docker Desktop, starts it if needed, and opens your workstation in the browser when ready.

> **WSL2 troubleshooting**: If Docker fails to start or shows "WSL" errors, open **Command Prompt as Administrator** and run:
> ```cmd
> wsl --update
> wsl --shutdown
> ```
> Then restart Docker Desktop.

> **SmartScreen**: Windows may show a "Windows protected your PC" warning when running the `.bat` file. Click **"More info" → "Run anyway"**. This is normal for unsigned scripts.

> **Windows builds take longer** (~15–25 min vs ~10 min on macOS). When the browser opens, you'll see a splash page saying "Zokai Station is starting…". On Windows, this may take several minutes. If the page doesn't transition automatically, **refresh the page** — once you see the login screen, your workstation is ready.

---

## First Steps

> 📂 **Your install folder**: During installation you chose a location (default: `~/Documents/`). The installer created a `Zokai Station Free/` folder there — all paths below refer to this folder.

### 1. Open your workstation

After installation completes, open your browser:

```
http://localhost:8081
```

> 🔑 **Password**: Your password is shown at the end of installation and saved to `access.txt` in your Zokai Station Free folder (e.g., `~/Documents/Zokai Station Free/access.txt`). You'll need it every time you open the workstation.

### 2. Connect Gmail & Calendar

Click **Connect Gmail** in the Zokai dashboard sidebar. You'll be redirected to a standard Google sign-in — no Google Cloud account or API setup needed.

> **Beta note**: During early access, Google may show an "app not verified" warning. Click **"Advanced" → "Go to Zokai (unsafe)"** to proceed. This is expected and will be resolved once Google completes our app verification.

▶ **[Watch the Gmail setup walkthrough (YouTube)](https://youtu.be/Vq2HCMKpopY)**

### 3. Enable web search

Zokai's web search is powered by **[Tavily](https://tavily.com)** — 1,000 free searches/month, no credit card required. Add your key through the installer or by placing it in your secrets folder.

> 💡 Without a Tavily key, the direct search tool won't be available. The deep research tool (GPTR) will still run but falls back to DuckDuckGo, which gives less accurate results.

If you skipped this during installation, open `zokai-config.json` in the VS Code file explorer (path: **workspaces → .zokai → zokai-config.json**) and set:

```json
"RETRIEVER": "tavily",
"TAVILY_API_KEY": "tvly-..."
```

Changes take effect immediately — no restart needed.

### 4. Activate local codebase indexing

Once you have files in your workspace, Kilo Code can semantically search your entire codebase — so you can ask questions like *"where is the authentication logic?"* and get accurate, context-aware answers.

1. Click the **⚙ Settings gear** at the bottom of the Kilo sidebar
2. The indexing panel opens — all backend fields (Embedder URL, Model, Vector Store) are **already pre-configured**
3. Enter a placeholder value (e.g., `local`) in the API key field — the field is required by the interface but local indexing does not use a real key — and click **Save**
4. Click **Start Indexing** — the status switches to "Indexing" and the file scanner starts immediately
5. Click the **← back arrow** to return to the chat — indexing continues in the background

> 💡 The backend is fully pre-configured. You just need any value in the API key field to activate the Start button.

▶ **[Watch the codebase indexing walkthrough (YouTube)](https://youtu.be/-8YJalp103c)**

---

## Stopping & Restarting

Zokai Station starts automatically on login. To restart or stop:

| Action | macOS | Windows |
|---|---|---|
| **Restart** | Double-click **Zokai Station Free.app** in your install folder | Double-click **install-free.bat** (detects existing install — no reinstallation) |
| **Stop** | Quit **Docker Desktop** — all containers stop automatically | Quit **Docker Desktop** — all containers stop automatically |

> 💡 Your data is never lost — volumes persist across stops and restarts.
>
> For advanced users: `docker compose --env-file .env.free -f docker-compose-free.yml down` stops Zokai containers without quitting Docker.

---

## Upgrading

Download the latest installer and run it in the same location. It detects your existing installation, preserves all data (notes, emails, calendar, secrets), and only updates the application files.

> **Free → Pro**: Pro uses a separate data directory so both tiers can run side-by-side. The Pro installer will offer to migrate your notes and secrets.

---

## Architecture

```
  Browser
    │
    ▼
┌──────────────────── FRONTEND ──────────────────────┐
│   Nginx Proxy  →  VS Code (code-server)             │
└──────────────────────┬─────────────────────────────┘
                       │
┌──────────────────── BACKEND ───────────────────────┐
│   MCP Services (AI-callable tools):                 │
│   Gmail · Calendar · YouTube · GPTR                 │
│   Markdownify · Tavily · mcp-tasks · Ingestor       │
└──────────────────────┬─────────────────────────────┘
                       │
┌──────────────────── DATA ──────────────────────────┐
│   Qdrant (vectors)  ·  Redis (cache)                │
│   Embedding Server (FastEmbed, local)               │
└──────────────────────┬─────────────────────────────┘
                       │
┌──────────────────── MANAGEMENT ────────────────────┐
│   Secrets Manager  ·  Workspace Manager             │
└────────────────────────────────────────────────────┘
```

All services run in isolated Docker networks.

---

## Uninstalling

**macOS:** Double-click **Uninstall Zokai Station.sh** in your install folder, or run:

```bash
bash "<install-folder>/Uninstall Zokai Station.sh"
```

**Windows:** Double-click **uninstall-free.bat**, or run:

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

This stops all containers, removes Docker volumes, and cleans up internal data. Your workspace (notes, outputs) is preserved.

---

<details>
<summary><strong>🔧 Developer Reference</strong></summary>

### Install from source

```bash
git clone https://github.com/Mkn501/Zokai-station-free.git
cd Zokai-station-free
bash installer-free.sh
```

### Troubleshooting

**VS Code won't open:**
```bash
docker compose -f docker-compose-free.yml ps
docker compose -f docker-compose-free.yml logs vs-code
```

**Port already in use:**
```bash
# macOS/Linux
lsof -i :8081

# Windows (PowerShell)
Get-NetTCPConnection -LocalPort 8081 -ErrorAction SilentlyContinue
```

**Docker not starting (macOS):**
```bash
open -a "Docker"   # start Docker Desktop manually
# wait 30 seconds, then re-run the installer
```

**Docker not starting (Windows):**
```cmd
:: Open Command Prompt as Administrator
wsl --shutdown
:: Wait 10 seconds, then restart Docker Desktop
```

**Reset everything:**
```bash
docker compose -f docker-compose-free.yml down -v
rm -rf "<install-folder>"
bash installer-free.sh
```

### Directory Structure

```
Zokai-station-free/
├── install-free.bat            # Windows: double-click to install
├── uninstall-free.bat          # Windows: double-click to uninstall
├── installer-free.sh           # macOS: installer script
├── uninstall-free.sh           # macOS: uninstall script
├── docker-compose-free.yml     # Free-tier service definitions
├── docker-compose.yml          # Base compose (used by installer)
├── .env.example                # Environment variable template
├── LICENSE                     # AGPL-3.0
├── NOTICE                      # Third-party attributions
├── config/                     # Kilo Code settings, MCP config
├── containers/                 # Dockerfiles for each service
├── launcher/                   # macOS .app bundle assets
└── scripts/
    ├── configure-kilo-code.sh  # Kilo Code profile setup
    ├── mcp_bridge.py           # MCP stdio↔container bridge
    └── ...                     # Utility scripts
```

</details>

---

## Acknowledgments

Zokai Station builds on these outstanding open-source projects:

| Project | Role in Zokai | License |
|---|---|---|
| [code-server](https://github.com/coder/code-server) | Browser-based VS Code | MIT |
| [Kilo Code](https://github.com/kilocode/kilo-code) | AI coding agent | Apache-2.0 |
| [Foam](https://github.com/foambubble/foam) | Wiki-style notes (Zokai Notes) | MIT |
| [GPT Researcher](https://github.com/assafelovic/gpt-researcher) | Deep web research engine | Apache-2.0 |
| [Qdrant](https://github.com/qdrant/qdrant) | Vector database | Apache-2.0 |
| [FastEmbed](https://github.com/qdrant/fastembed) | Local embedding model server | Apache-2.0 |
| [Redis](https://github.com/redis/redis) | In-memory cache | BSD-3 |
| [Nginx](https://nginx.org) | Reverse proxy | BSD-2 |
| [Markdownify MCP](https://github.com/zcaceres/markdownify-mcp) | Document → Markdown conversion | MIT |
| [Browse Lite](https://github.com/nicepkg/browse-lite) | Embedded browser (dashboard) | MIT |
| [Tavily MCP](https://github.com/modelcontextprotocol/servers) | Web search integration | MIT |

Thank you to all contributors and maintainers. 🙏

---

## Contributing

We welcome contributions! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR.

> By submitting a pull request, you agree to the Contributor License Agreement in [CONTRIBUTING.md](CONTRIBUTING.md). This allows Zokai to offer dual-licensed (AGPL-3.0 + commercial) distributions.

---

## License

Zokai™ Station is licensed under the [GNU Affero General Public License v3.0](LICENSE).

**Commercial / dual licensing** available for organizations that cannot comply with AGPL-3.0. Contact [zokai.check@gmail.com](mailto:zokai.check@gmail.com).

---

## Links

- 🌐 **Website**: [zokai.ai](https://zokai.ai)
- 🔑 **OpenRouter** (free LLM key): [openrouter.ai/keys](https://openrouter.ai/keys)
- 🔍 **Tavily** (web search): [tavily.com](https://tavily.com)
- 🐛 **Issues**: [github.com/Mkn501/Zokai-station-free/issues](https://github.com/Mkn501/Zokai-station-free/issues)

---

*Built with ❤️ by [Zokai](https://zokai.ai)*