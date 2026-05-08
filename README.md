# AI + Code 每日速递

每日自动搜集 GitHub AI+Code 热门开源项目，调用 MiniMax AI 生成技术点评，部署至 GitHub Pages。

## 功能特性

- **定时自动更新**：每天北京时间 9:00 自动运行
- **规则引擎**：通过 `rules/ai-daily.yml` 配置搜索维度和 AI prompt
- **多语言支持**：中英文双语页面，支持语言切换
- **暗色/亮色主题**：自动跟随系统主题
- **数据归档**：原始 JSON 数据按日期归档到 `docs/data/`
- **手动触发**：支持 GitHub Actions 手动运行

## 自动化流程

```
每天北京时间 9:00 (UTC 1:00) 或手动触发
  └─ GitHub Actions (ai-daily.yml)
        ├─ 读取 rules/ai-daily.yml 配置
        ├─ gh search repos → 多维度抓项目
        ├─ MiniMax API → AI 分析 + 点评
        ├─ 生成 docs/daily/YYYY-MM-DD.md
        ├─ MkDocs build → site/
        ├─ 归档 JSON 到 docs/data/
        └─ GitHub Pages 自动部署
```

## 目录结构

```
ttbb-landing-page/
├── .nojekyll                    # 防止 Jekyll 处理
├── mkdocs.yml                   # MkDocs 站点配置
├── rules/
│   └── ai-daily.yml            # 规则引擎配置（可热更新）
├── docs/
│   ├── index.md                # 首页
│   ├── index.en.md             # 英文首页
│   ├── daily/                  # 每日归档 Markdown
│   │   └── YYYY-MM-DD.md
│   ├── data/                    # 原始 JSON 归档
│   │   └── YYYY-MM-DD/
│   │       └── *.json
│   └── stylesheets/
│       └── extra.css           # 自定义样式
├── scripts/
│   └── ai-daily-generate.sh   # 核心生成脚本
└── .github/workflows/
    └── ai-daily.yml           # CI/CD（搜索+生成+build+部署）
```

## 配置步骤

### 1. 配置 GitHub Secrets

在 repo → Settings → Secrets → Actions 添加：

| Secret Name | Value |
|-------------|-------|
| `MINIMAX_API_KEY` | 你的 MiniMax API Key |
| `MINIMAX_BASE_URL` | `https://api.minimax.chat/v1`（可选） |
| `MINIMAX_MODEL_NAME` | `MiniMax-Text-01`（可选） |

### 2. 启用 GitHub Pages

- Repo → Settings → Pages
- Source: **GitHub Actions**
- 保存

### 3. 手动触发测试

在 GitHub Actions 页面点击 `AI Daily Update` → `Run workflow`，验证流程正常。

### 4. 修改搜索维度

编辑 `rules/ai-daily.yml` 中的 `search.dimensions`：

```yaml
search:
  dimensions:
    - name: "AI编程助手"
      query: "AI coding assistant"
      limit: 15
      sort: stars
      order: desc
```

## 本地运行

```bash
export MINIMAX_API_KEY="your-key"
export MINIMAX_BASE_URL="https://api.minimax.chat/v1"
export MINIMAX_MODEL_NAME="MiniMax-Text-01"
export GH_TOKEN="your-gh-token"  # 需要 repo scope
bash scripts/ai-daily-generate.sh
```

## 自定义配置

### 修改 AI Prompt

编辑 `rules/ai-daily.yml` 中的 `llm.system_prompt`。

### 添加新搜索维度

在 `rules/ai-daily.yml` 的 `search.dimensions` 中添加新项。

### 修改输出格式

编辑 `rules/ai-daily.yml` 中的 `output` 配置段。

## 技术栈

| 组件 | 技术 |
|------|------|
| 定时任务 | GitHub Actions (schedule: cron) |
| 数据搜集 | gh search repos |
| AI 分析 | MiniMax API |
| 内容生成 | Bash + jq + curl + yq |
| 静态站点 | Material for MkDocs + i18n |
| 托管 | GitHub Pages |
