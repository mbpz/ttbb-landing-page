#!/usr/bin/env bash
# =============================================================================
# ai-daily-generate.sh — 搜集 GitHub 项目 + MiniMax AI 分析 + 生成 Markdown
# =============================================================================
set -euo pipefail

TODAY=$(date +%Y-%m-%d)
WEEKDAY=$(date +%A)
READABLE_DATE=$(date +"%Y年%m月%d日 $WEEKDAY")
TEMP=$(mktemp -d)
GH_TOKEN="${GH_TOKEN:-}"
MINIMAX_API_KEY="${MINIMAX_API_KEY:-}"
MINIMAX_BASE_URL="${MINIMAX_BASE_URL:-https://api.minimax.chat/v1}"
MODEL_NAME="${MINIMAX_MODEL_NAME:-MiniMax-Text-01}"

# 默认规则文件
RULES_FILE="${RULES_FILE:-rules/ai-daily.yml}"
DAILY_DIR="docs/daily"
mkdir -p "$DAILY_DIR"

export GH_TOKEN

echo "=== [1/6] 读取规则配置 ==="
if [[ -f "$RULES_FILE" ]]; then
  echo "  使用规则: $RULES_FILE"
  # 解析规则中的搜索维度（如果 yq 可用）
  if command -v yq &>/dev/null; then
    DIMENSIONS=$(yq '.search.dimensions' "$RULES_FILE" 2>/dev/null || echo "")
    echo "  发现维度配置"
  else
    echo "  yq 未安装，使用默认搜索维度"
    DIMENSIONS=""
  fi
else
  echo "  规则文件 $RULES_FILE 不存在，使用默认配置"
  DIMENSIONS=""
fi

# ------------------------------------------------------------------------------
echo "=== [2/6] 搜索 GitHub 项目 ==="

search() {
  local q="$1" label="$2"
  echo "  → $label"
  gh search repos "$q" --limit 15 --sort stars --order desc \
    --json name,description,url,stargazerCount,updatedAt,primaryLanguage \
    > "$TEMP/$label.json" 2>/dev/null || echo "[]" > "$TEMP/$label.json"
}

# 默认 5 个搜索维度
search "AI coding assistant" "coding"
search "LLM agent framework" "agent"
search "code review AI agent" "review"
search "MCP model context protocol" "mcp"
search "vibe coding OR AI software development" "vibe"

echo "  完成，JSON 数据在 $TEMP/"

# ------------------------------------------------------------------------------
echo "=== [3/6] 调用 MiniMax API 生成 AI 摘要 ==="

build_summary_prompt() {
cat << 'PROMPT'
你是 AI 技术观察员。请分析以下 GitHub trending 项目，用中文撰写一份结构化报告。

## 输出格式（严格遵循）
### 今日概览
[2-3句话总览整体趋势]

### 重点推荐
- [项目名] — [一句话核心定位]

### 技术趋势
- [趋势1]
- [趋势2]

### 学习建议
- 新手：[建议]
- 进阶：[建议]
- 架构师：[建议]

## 项目数据（JSON格式）
PROMPT
for label in coding agent review mcp vibe; do
  echo ""
  echo "【$label】"
  cat "$TEMP/$label.json"
done
}

SUMMARY=""
if [[ -n "$MINIMAX_API_KEY" && "$MINIMAX_API_KEY" != "dummy" && "$MINIMAX_API_KEY" != "sk-" ]]; then
  echo "  调用 MiniMax API..."
  PROMPT_CONTENT=$(build_summary_prompt | jq -Rs .)
  SUMMARY=$(curl -s --fail \
    -H "Authorization: Bearer $MINIMAX_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL_NAME\",\"messages\":[{\"role\":\"user\",\"content\":$PROMPT_CONTENT}],\"max_tokens\":4000}" \
    "$MINIMAX_BASE_URL/chat/completions" 2>/dev/null | \
    jq -r '.choices[0].message.content // empty' || echo "")
  echo "  AI 摘要生成完成"
else
  echo "  跳过 AI 摘要（MINIMAX_API_KEY 未设置或为 placeholder）"
fi

# ------------------------------------------------------------------------------
echo "=== [4/6] 生成每日 Markdown 页面 ==="

render_md_cards() {
  local json="$1" section_icon="$2" section_name="$3" tag_class="$4"
  local count
  count=$(jq 'length' "$json" 2>/dev/null || echo 0)
  echo ""
  echo "### $section_icon $section_name"
  echo ""
  jq -r '.[] | "**[" + .name + "](" + .url + ")** ★ " + (.stargazerCount | tostring) + " | `" + (.primaryLanguage // "代码") + "`\n\n" + (.description // "") + "\n"' "$json" 2>/dev/null || true
}

cat > "$DAILY_DIR/$TODAY.md" << MD_HEADER
---
title: AI + Code 每日速递 $TODAY
description: 每日搜集 GitHub AI+Code 热门开源项目，MiniMax AI 分析技术趋势
hide:
  - navigation
  - toc
date: $TODAY
---

# AI + Code 每日速递

<span class="md-date">$READABLE_DATE</span>

MD_HEADER

# AI 摘要
if [[ -n "$SUMMARY" ]]; then
  echo '!!! info "🤖 AI 观察员点评"' >> "$DAILY_DIR/$TODAY.md"
  echo '    ' >> "$DAILY_DIR/$TODAY.md"
  echo "$SUMMARY" | sed 's/^/    /' >> "$DAILY_DIR/$TODAY.md"
  echo "" >> "$DAILY_DIR/$TODAY.md"
fi

# 项目卡片
echo '## 📊 项目速览' >> "$DAILY_DIR/$TODAY.md"
render_md_cards "$TEMP/coding.json" "🤖" "AI 编程助手" "tool" >> "$DAILY_DIR/$TODAY.md"
render_md_cards "$TEMP/agent.json" "🔗" "LLM Agent 框架" "framework" >> "$DAILY_DIR/$TODAY.md"
render_md_cards "$TEMP/review.json" "🔍" "AI 代码审查" "tool" >> "$DAILY_DIR/$TODAY.md"
render_md_cards "$TEMP/mcp.json" "⚡" "MCP 协议" "architecture" >> "$DAILY_DIR/$TODAY.md"
render_md_cards "$TEMP/vibe.json" "✨" "AI 软件开发" "product" >> "$DAILY_DIR/$TODAY.md"

echo "" >> "$DAILY_DIR/$TODAY.md"
echo '=== "数据来源"' >> "$DAILY_DIR/$TODAY.md"
echo "GitHub Trending · AI 分析：MiniMax $MODEL_NAME · 最后更新：$READABLE_DATE" >> "$DAILY_DIR/$TODAY.md"

# ------------------------------------------------------------------------------
echo "=== [5/6] 更新 index.md 首页 ==="

# 获取所有日期目录（时间倒序）
DAILY_FILES=$(ls -1 "$DAILY_DIR"/20*.md 2>/dev/null | sort -r || echo "")

cat > "docs/index.md" << INDEX_HEADER
---
title: AI + Code 每日速递
description: 每日搜集 GitHub AI+Code 热门开源项目，MiniMax AI 分析技术趋势
hide:
  - navigation
  - toc
nav:
  - 首页: index.md
INDEX_HEADER

# 动态添加每日导航
for f in $DAILY_FILES; do
  date_str=$(basename "$f" .md)
  readable=$(date -j -f "%Y-%m-%d" "$date_str" "+%m月%d日" 2>/dev/null || echo "$date_str")
  echo "  - $readable: \"daily/$date_str.md\"" >> "docs/index.md"
done

cat >> "docs/index.md" << INDEX_FOOTER

## 最新内容

!!! info "📅 今日概览"
    每日北京时间 9:00 自动更新。数据来源：GitHub Trending，AI 分析：MiniMax。

点击上方导航日期可查看历史每日汇总。
INDEX_FOOTER

# ------------------------------------------------------------------------------
echo "=== [6/6] 清理 ==="
rm -rf "$TEMP"
echo ""
echo "=== 完成 ==="
echo "  每日页面: $DAILY_DIR/$TODAY.md"
echo "  首页: docs/index.md"