---
title: AI + Code Daily Digest
description: Daily collection of GitHub AI+Code trending open source projects, with MiniMax AI analysis
hide:
  - navigation
  - toc
---

# AI + Code Daily Digest

Daily collection of GitHub AI+Code trending open source projects, analyzed and summarized by MiniMax LLM to generate structured knowledge pages.

## About This Project

| Item | Description |
|------|------|
| Data Source | GitHub Trending (gh search repos) |
| AI Analysis | MiniMax Coding Plan API |
| Site Framework | Material for MkDocs |
| Hosting | GitHub Pages |
| Update Frequency | Daily at 9:00 AM Beijing Time |

## Technical Architecture

```
Rule Configuration (rules/ai-daily.yml)
    ↓
GitHub Actions (Scheduled Trigger)
    ↓
├─ gh search repos → Data Collection
├─ MiniMax API → AI Analysis & Markdown Generation
├─ Write to docs/daily/YYYY-MM-DD.md
└─ mkdocs build → site/
    ↓
GitHub Pages Deployment
```

## Daily Summary

Automatically generated daily. Click a date to view detailed project list and AI analysis summary.

!!! info "Auto Update"
    Runs automatically daily at 9:00 AM Beijing Time. Data from GitHub Trending, AI analysis powered by MiniMax LLM.

Click "Daily" in the navigation bar to view historical content.
