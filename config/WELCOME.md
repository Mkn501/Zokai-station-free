# Welcome to Zokai Station 🌿

Your private AI workstation is up and running.

---

## Quick Start

Your station is ready. Kilo Code — your AI agent — is in the sidebar on the right. The **Dashboard** should already be open in your browser — your emails and calendar are syncing in the background.

Here's how to get started:

### 1. Ensure your Tavily key is set _(for web search)_

If you didn't configure this during installation, open `zokai-config.json` in your workspace and add your key:

```json
"TAVILY_API_KEY": "tvly-your-key-here"
```

Get a free key at [tavily.com](https://tavily.com) — 1,000 free searches/month. Web search won't work without it.

### 2. Start using Kilo Code

Click the **Kilo** icon in the left sidebar, or press `Ctrl+Shift+K`.

**Sample prompts to try:**
- *"What's on my calendar today?"*
- *"Search my inbox for the latest email with 'invoice' in the subject and show me the amounts"*
- *"Research the latest changes to [topic] and save a summary to my notes"*
- *"Read this PDF and check it against our standard payment terms"*
- *"Show my tasks"*

**See it in action — real workflow demos (no editing, no faking):** *(video walkthroughs coming soon)*

| Demo | What You See | Duration |
|------|-------------|----------|
| 📊 **One-Prompt Slide Deck** | One prompt → Calendar + tasks + code → HTML slide deck | 44s |
| 📰 **Newsletter Digest** | Agent reads Gmail Newsletter, synthesizes, fact-checks, drafts email, creates template | 2m |
| 🔍 **Invoice Controller** | Audits PDF → cross-checks Postgres → catches €16k in phantom contracts → drafts response | 2m |

> **Questions?** Switch Kilo to **Zokai Guide** mode (mode selector dropdown in the Kilo panel) — it reads the user manual and answers questions about what the station can do and how to use it. Or open `.zokai/zokai_station_manual.md` directly in Zokai Viewer.

### Read notes in Zokai Viewer

When Kilo creates or edits a `.md` file, right-click it in the file explorer and choose **"Open with Zokai Viewer"** (or click the 🌿 icon in the top-right of the editor tab).

Zokai Viewer gives you:
- **Clean rendered view** — no raw markdown syntax, just readable text
- **Git diff markers** — color-coded indicators on each line show what's new since the last commit:
  - 🟢 Green = added by the AI, not yet committed
  - 🟡 Yellow = modified, not yet committed
  - 🔴 Red = deleted, not yet committed

> This is your **track-changes for AI content** — glance at the markers to review exactly what the agent wrote before you commit it.

**To commit your changes:**
1. Click the **branch icon** in the left sidebar (Source Control panel)
2. Review staged files — each shows the diff of what changed
3. Type a commit message and click ✓ **Commit**
4. Optionally push to a remote: `git remote add origin <your-repo-url>` then **Sync**

> Kilo can also do this for you — *"Commit all my changes with the message 'Add invoice analysis'"*

---

## Need Help?

📖 **Full User Manual** → open `.zokai/zokai_station_manual.md` in Zokai Viewer for the complete guide (all chapters, troubleshooting, architecture diagram).

Or switch Kilo to **Zokai Guide** mode and ask it anything — it reads the manual and answers your questions directly.

Full guide and documentation → [zokai.ai](https://zokai.ai)

Your credentials and URL are saved in `access.txt` (in your install folder).
