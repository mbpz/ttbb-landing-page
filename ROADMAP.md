# TTBB Landing Page — Roadmap

> 基于 GitHub Actions + MiniMax Coding Plan 的 AI 每日知识聚合平台

---

## 项目愿景

通过可配置的规则引擎，驱动 GitHub 搜索 + MiniMax LLM 汇总分析，生成 Material MkDocs 风格的每日知识页面，托管在 GitHub Pages。

---

## 当前状态 (v0.1)

- ✅ GitHub Actions 定时任务（每天北京时间 9:00）
- ✅ gh search repos 5个维度数据搜集
- ✅ MiniMax API AI 分析生成 HTML
- ✅ GitHub Pages 部署（自包含 HTML）
- ⚠️ Jekyll 覆盖了自定义 HTML（Jekyll 处理 Source 目录）

---

## 里程碑路线图

### Phase 0 — 修复现状 (当前)
**目标**：让自定义 HTML 绕过 Jekyll 直接 served

- [ ] 创建 `.nojekyll` 文件（已创建但未生效）
- [ ] 确认 GitHub Pages source 路径
- [ ] 验证自定义 HTML 能正确展示

### Phase 1 — MkDocs 迁移
**目标**：从自包含 HTML 切换到 Material MkDocs build 流程

- [ ] 修改 `ai-daily-generate.sh`：输出 Markdown 而非 HTML
- [ ] 更新 `mkdocs.yml`：完善 navigation、plugins
- [ ] 新建 `docs/index.md`：侧边栏 + 最新日期引用
- [ ] 新建 `docs/daily/YYYY-MM-DD.md`：每日归档 Markdown
- [ ] 修改 `ai-daily.yml`：添加 `pip install mkdocs-material` + `mkdocs build` step
- [ ] 部署 `site/` 而非 `docs/`

**验收标准**：GitHub Pages 展示 Material MkDocs 主题的页面

---

### Phase 2 — 规则引擎基础
**目标**：搜索维度和输出格式可配置

- [ ] 新建 `rules/ai-daily.yml` 配置文件
  ```yaml
  search:
    dimensions:
      - name: "AI编程助手"
        query: "AI coding assistant"
        limit: 15
        tags: ["tool"]
      - name: "LLM Agent框架"
        query: "LLM agent framework"
        limit: 15
        tags: ["framework"]
      # ... 其他维度
  llm:
    model: "MiniMax-Text-01"
    system_prompt: "你是 AI 技术观察员，用中文撰写简洁报告"
    output_format: |
      ## 今日概览
      ...
  ```
- [ ] 重写 `ai-daily-generate.sh`：读取 `rules/ai-daily.yml` 动态生成搜索和 prompt
- [ ] 规则引擎支持多维度搜索配置（关键词、limit、排序方式）
- [ ] 规则引擎支持 LLM 输出格式模板配置

**验收标准**：修改 `rules/ai-daily.yml` 无需改脚本，新增/删除搜索维度生效

---

### Phase 3 — 规则引擎精细化
**目标**：Prompt 模板、标签映射、内容字段全部可配置

- [ ] 支持项目字段可配置（stars/description/language/updatedAt）
- [ ] 支持标签体系配置（framework/tool/product/architecture）
- [ ] 支持 AI 摘要段落结构模板（概览/重点推荐/趋势/学习建议）
- [ ] 支持每分类项目数量限制（`max_projects_per_category`）
- [ ] 支持自定义 admonition 类型（!!! info / !!! warning）
- [ ] 规则引擎支持环境变量覆盖（`MINIMAX_*` 优先级 > yml 配置）

**验收标准**：不修改代码，仅改 yml 即可改变搜索结果和生成内容

---

### Phase 4 — 用户体验增强
**目标**：让 landing page 更易用、更有价值

- [ ] 侧边栏按日期倒序显示，点击跳转历史
- [ ] 首页自动引用最新日期的每日页面
- [ ] 添加"今日概览"一级标题，快速跳转到 AI 摘要
- [ ] 搜索功能：MkDocs 内置搜索支持中文
- [ ] 暗色/亮色主题切换
- [ ] 添加页脚：数据来源、AI 模型、最后更新时间
- [ ] 每个项目卡片可点击跳转 GitHub 原始仓库

**验收标准**：用户访问 `*.github.io/*` 可快速找到感兴趣的内容

---

### Phase 5 — 自动化与监控
**目标**：确保定时任务稳定运行，结果可追溯

- [ ] GitHub Actions 日志输出关键信息（搜索数量、AI token 消耗）
- [ ] 任务失败时发送 GitHub Actions 通知
- [ ] 每日 commit message 包含日期和变更摘要
- [ ] `docs/data/YYYY-MM-DD/` 原始 JSON 数据归档（便于复盘）
- [ ] 可手动触发 workflow（Actions 页面 "Run workflow" 按钮）

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
│  [5] 更新 index.md 侧边栏           │
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
| 内容生成 | Bash Shell + jq + curl |
| 规则配置 | YAML (规则引擎) |
| 静态站点 | Material for MkDocs |
| 托管 | GitHub Pages |

---

## 文件结构 (目标状态)

```
ttbb-landing-page/
├── mkdocs.yml                 # MkDocs 站点配置
├── rules/
│   └── ai-daily.yml          # 规则引擎配置（可热更新）
├── docs/
│   ├── index.md              # 首页（侧边栏 + 最新日期）
│   └── daily/
│       ├── 2026-05-08.md     # 每日归档
│       ├── 2026-05-07.md
│       └── ...
├── scripts/
│   └── ai-daily-generate.sh   # 核心生成脚本（读取 rules/）
├── .github/
│   └── workflows/
│       └── ai-daily.yml      # CI/CD（搜索+生成+build+部署）
└── README.md
```

---

## 依赖关系

```
Phase 1 (MkDocs)      ← Phase 0 修复前提
Phase 2 (规则引擎基础) ← Phase 1 完成前提
Phase 3 (精细化)       ← Phase 2 完成前提
Phase 4 (UX增强)      ← Phase 1 完成前提
Phase 5 (监控)        ← Phase 2 完成前提
```

---

## 下一步行动

**推荐顺序**：Phase 0 → Phase 1 → Phase 2

1. 确认 `.nojekyll` 是否生效（当前页面实际展示的是 README 还是 index.html？）
2. 如果 Jekyll 始终覆盖，创建 `/docs/index.md` 作为 MkDocs 入口
3. 完成 Phase 1 后再逐步引入规则引擎