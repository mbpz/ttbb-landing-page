# TTBB Landing Page — Roadmap

> 基于 GitHub Actions + MiniMax Coding Plan 的 AI 每日知识聚合平台

---

## 项目愿景

通过可配置的规则引擎，驱动 GitHub 搜索 + MiniMax LLM 汇总分析，生成 Material MkDocs 风格的每日知识页面，托管在 GitHub Pages。

---

## 当前状态 (v0.2)

- ✅ GitHub Actions 定时任务（每天北京时间 9:00）
- ✅ gh search repos 5个维度数据搜集
- ✅ MiniMax API AI 分析生成 Markdown
- ✅ Material MkDocs + GitHub Pages 部署
- ✅ `.nojekyll` 防止 Jekyll 处理
- ✅ 规则引擎配置文件 `rules/ai-daily.yml`
- ✅ i18n 多语言支持（中英文）
- ✅ 暗色/亮色主题切换
- ✅ JSON 数据归档到 `docs/data/`
- ✅ GitHub Actions 日志增强 + 失败通知
- ✅ workflow_dispatch 手动触发

---

## 里程碑路线图

### Phase 0 — 修复现状 ✅
**目标**：让自定义 HTML 绕过 Jekyll 直接 served

- [x] 创建 `.nojekyll` 文件
- [x] 确认 GitHub Pages source 路径（使用 Actions artifact 部署）
- [x] 验证自定义 HTML 能正确展示

---

### Phase 1 — MkDocs 迁移 ✅
**目标**：从自包含 HTML 切换到 Material MkDocs build 流程

- [x] 修改 `ai-daily-generate.sh`：输出 Markdown 而非 HTML
- [x] 更新 `mkdocs.yml`：完善 navigation、plugins、i18n
- [x] 新建 `docs/index.md`：首页
- [x] 新建 `docs/index.en.md`：英文版首页
- [x] workflow 添加 MkDocs build step
- [x] 部署 `site/` 而非 `docs/`

**验收标准**：GitHub Pages 展示 Material MkDocs 主题的页面

---

### Phase 2 — 规则引擎基础 ✅
**目标**：搜索维度和输出格式可配置

- [x] 新建 `rules/ai-daily.yml` 配置文件
- [x] 重写 `ai-daily-generate.sh`：读取 `rules/ai-daily.yml` 动态生成搜索和 prompt
- [x] 规则引擎支持多维度搜索配置（关键词、limit、排序方式）
- [x] 规则引擎支持 LLM 输出格式模板配置

**验收标准**：修改 `rules/ai-daily.yml` 无需改脚本，新增/删除搜索维度生效

---

### Phase 3 — 规则引擎精细化 ✅
**目标**：Prompt 模板、标签映射、内容字段全部可配置

- [x] 支持项目字段可配置（stars/description/language/updatedAt）
- [x] 支持标签体系配置（framework/tool/product/architecture）
- [x] 支持 AI 摘要段落结构模板（概览/重点推荐/趋势/学习建议）
- [x] 支持每分类项目数量限制（`max_projects_per_category`）
- [x] 支持自定义 admonition 类型（!!! info / !!! warning）
- [x] 规则引擎支持环境变量覆盖（`MINIMAX_*` 优先级 > yml 配置）

**验收标准**：不修改代码，仅改 yml 即可改变搜索结果和生成内容

---

### Phase 4 — 用户体验增强 ✅
**目标**：让 landing page 更易用、更有价值

- [x] 侧边栏按日期倒序显示（MkDocs 自动目录读取）
- [x] 首页自动引用最新日期的每日页面
- [x] 添加"今日概览"一级标题，快速跳转到 AI 摘要
- [x] 搜索功能：MkDocs 内置搜索支持中文
- [x] 暗色/亮色主题切换
- [x] 添加页脚：数据来源、AI 模型、最后更新时间
- [x] 每个项目卡片可点击跳转 GitHub 原始仓库
- [x] **多语言 i18n 支持**：支持中英文切换

**验收标准**：用户访问 `*.github.io/*` 可快速找到感兴趣的内容

---

### Phase 5 — 自动化与监控 ✅
**目标**：确保定时任务稳定运行，结果可追溯

- [x] GitHub Actions 日志输出关键信息（搜索数量、AI token 消耗）
- [x] 任务失败时发送 GitHub Actions 通知
- [x] 每日 commit message 包含日期和变更摘要
- [x] `docs/data/YYYY-MM-DD/` 原始 JSON 数据归档（便于复盘）
- [x] 可手动触发 workflow（Actions 页面 "Run workflow" 按钮）

**验收标准**：每次运行都有完整日志，出现问题可追溯

---

## 架构图

```
规则配置层 (rules/ai-daily.yml)
    │
    │ 读取
    ▼
┌─────────────────────────────────────┐
│    ai-daily-generate.sh (核心脚本)   │
│                                     │
│  [1] 解析规则 → 执行 gh search      │
│  [2] 解析规则 → 构建 LLM Prompt     │
│  [3] 调用 MiniMax API               │
│  [4] 解析输出 → 写入 Markdown       │
│  [5] MkDocs 自动读取 daily/ 目录     │
│  [6] 归档 JSON 到 docs/data/        │
└─────────────────────────────────────┘
         │
         │ 生成 Markdown 源文件
         ▼
┌─────────────────────────────────────┐
│        GitHub Actions CI             │
│                                     │
│  pip install mkdocs-material         │
│  mkdocs build                        │
│  → 生成 site/ 静态文件               │
└─────────────────────────────────────┘
         │
         │ 部署
         ▼
   GitHub Pages
         │
         ▼
   用户访问 landing page
```

---

## 技术栈

| 组件 | 技术 |
|------|------|
| 定时任务 | GitHub Actions (`schedule: cron`) |
| 数据搜集 | `gh search repos` (GitHub CLI) |
| AI 分析 | MiniMax API (Coding Plan Key) |
| 内容生成 | Bash Shell + jq + curl + yq |
| 规则配置 | YAML (规则引擎) |
| 静态站点 | Material for MkDocs + i18n |
| 托管 | GitHub Pages |

---

## 文件结构

```
ttbb-landing-page/
├── .nojekyll                    # 防止 Jekyll 处理
├── mkdocs.yml                   # MkDocs 站点配置 + i18n
├── rules/
│   └── ai-daily.yml            # 规则引擎配置（可热更新）
├── docs/
│   ├── index.md                # 首页（中文）
│   ├── index.en.md             # 首页（英文）
│   ├── stylesheets/
│   │   └── extra.css           # 自定义样式
│   ├── daily/                   # 每日归档 Markdown
│   │   └── YYYY-MM-DD.md
│   └── data/                    # 原始 JSON 归档
│       └── YYYY-MM-DD/
│           └── *.json
├── scripts/
│   └── ai-daily-generate.sh    # 核心生成脚本（读取 rules/）
├── .github/
│   └── workflows/
│       └── ai-daily.yml        # CI/CD（搜索+生成+build+部署）
└── README.md
```

---

## 下一步行动

**所有 Phase 已完成。v0.2 版本功能完备。**

可选优化方向：
1. 添加更多搜索维度（如：AI 安全、AI 数据处理等）
2. 支持更多输出语言（日语、韩语等）
3. 添加评论区或 GitHub Discussions 集成
4. 性能优化：缓存搜索结果避免频繁 API 调用
5. 统计分析：趋势图表展示项目 star 变化
