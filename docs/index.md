---
title: AI + Code 每日速递
description: 每日搜集 GitHub AI+Code 热门开源项目，MiniMax AI 分析技术趋势
hide:
  - navigation
  - toc
---

# AI + Code 每日速递

每日搜集 GitHub AI+Code 热门开源项目，调用 MiniMax 大模型进行分析汇总，生成结构化知识页面。

## 📡 关于本项目

| 项目 | 说明 |
|------|------|
| 数据来源 | GitHub Trending (gh search repos) |
| AI 分析 | MiniMax Coding Plan API |
| 站点框架 | Material for MkDocs |
| 托管平台 | GitHub Pages |
| 更新频率 | 每天北京时间 9:00 |

## 🚀 技术架构

```
规则配置 (rules/ai-daily.yml)
    ↓
GitHub Actions (定时触发)
    ↓
├─ gh search repos → 数据搜集
├─ MiniMax API → AI 分析生成 Markdown
├─ 写入 docs/daily/YYYY-MM-DD.md
└─ mkdocs build → site/
    ↓
GitHub Pages 部署
```

## 📅 每日汇总

每日自动生成，点击日期查看详细项目列表和 AI 分析摘要。

!!! info "⏰ 自动更新"
    每日北京时间 9:00 自动运行。数据来源 GitHub Trending，AI 分析由 MiniMax 大模型完成。

点击上方导航栏的「每日汇总」查看历史内容。