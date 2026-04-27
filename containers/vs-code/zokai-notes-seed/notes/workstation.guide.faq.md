---
id: workstation.faq
title: Zokai Station FAQ
desc: >-
  Frequently asked questions about Zokai Station. Covers first boot,
  performance, troubleshooting, and common setup concerns.
updated: '2026-03-02T19:00:00.000Z'
created: '2026-03-02T19:00:00.000Z'
tags:
  - workstation
  - faq
  - troubleshooting
  - help
---

# Zokai Station FAQ

## First Boot & Performance

### Q: Why does the dashboard show "No emails indexed" after a fresh install?
**A:** On first boot, three things compete for the embedding server:

1. **Kilo Code** indexes your workspace files (~5-10 min)
2. **Email ingestor** processes your Gmail inbox
3. **The embedding model** loads into memory (~500MB, takes 1-2 min)

All three share the same CPU. Kilo Code finishes first, then emails start flowing. Give it 10-15 minutes and refresh the dashboard.

### Q: Why is everything slow in the first 15 minutes?
**A:** The embedding model needs to warm up by loading neural network weights into RAM. After this first cold start, subsequent restarts are much faster because the OS caches the model files. Don't restart the embedding server during initial indexing.

### Q: The email count stays at 0. Is something broken?
**A:** Check in this order:

1. Is the embedding server healthy? Look for the green status dot in the dashboard bottom bar.
2. Is your Google account connected? The Gmail card should show your unread count. If it shows a dash, your OAuth token may be missing.
3. On machines with fewer than 8 cores, initial indexing can take 20-30 minutes. High CPU usage is normal during first boot.

### Q: How do I connect my Google account (Gmail / Calendar)?
**A:** Coming soon as a Connect button in the dashboard. Currently your Google OAuth token is in `~/Applications/ZokaiStation/secrets/token.json`.

### Q: Can I use Zokai Station while emails are still indexing?
**A:** Yes. The AI assistant (Kilo Code), notes, and all other features work immediately. Only the Gmail inbox view and email search are empty until indexing completes. Calendar events sync independently and are usually ready within 2-3 minutes.

## General

### Q: How much RAM does Zokai Station need?
**A:** Minimum 8 GB, recommended 16 GB. The embedding model alone uses ~2.5 GB. With all services running, expect ~6-8 GB total Docker memory usage.

### Q: Can I run Zokai Station alongside other Docker containers?
**A:** Yes, but be aware of resource competition. Zokai Station uses ~6-8 GB RAM and up to 4 CPU cores during peak indexing. Plan your host capacity accordingly.
