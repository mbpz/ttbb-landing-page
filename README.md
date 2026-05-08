# AI + Code 每日速递

每日自动搜集 GitHub AI+Code 热门开源项目，调用 MiniMax AI 生成技术点评，部署至 GitHub Pages。

## 自动化流程

```
每天 UTC 1:00 (北京时间 9:00)
  └─ GitHub Actions (ai-daily.yml)
        ├─ gh search repos → 5个维度抓项目
        ├─ MiniMax API → AI 分析 + 点评
        ├─ 生成 docs/index.html
        └─ GitHub Pages 自动部署
```

## 目录结构

```
ttbb-landing-page/
├── .github/workflows/
│   └── ai-daily.yml      # 定时任务 + 部署
├── scripts/
│   └── ai-daily-generate.sh  # 核心脚本
└── docs/
    ├── index.html        # 每日生成的页面
    └── data/             # 原始 JSON 数据（按日期归档）
```

## 配置步骤

### 1. 创建 GitHub Repo

在 GitHub 创建空仓库，推送代码：
```bash
git remote add origin https://github.com/YOUR_NAME/ttbb-landing-page.git
git push -u origin main
```

### 2. 配置 GitHub Secrets

在 repo → Settings → Secrets 添加：

| Secret Name | Value |
|-------------|-------|
| `MINIMAX_API_KEY` | 你的 MiniMax API Key |
| `MINIMAX_BASE_URL` | `https://api.minimax.chat/v1`（可选，默认值已填） |
| `MINIMAX_MODEL_NAME` | `MiniMax-Text-01`（可选） |

### 3. 启用 GitHub Pages

- Repo → Settings → Pages
- Source: **Deploy from a branch**
- Branch: `main` / `(root)`
- 保存

### 4. 手动触发测试

在 GitHub Actions 页面点击 `AI Daily Update` → `Run workflow`，验证流程正常。

## 手动本地运行

```bash
export MINIMAX_API_KEY="your-key"
export GH_TOKEN="your-gh-token"   # 需要 repo scope
bash scripts/ai-daily-generate.sh
```

## 搜索维度

| 维度 | 关键词 |
|------|--------|
| AI 编程助手 | `AI coding assistant` |
| LLM Agent 框架 | `LLM agent framework` |
| AI 代码审查 | `code review AI agent` |
| MCP 协议 | `MCP model context protocol` |
| AI 软件开发 | `vibe coding OR AI software development` |
