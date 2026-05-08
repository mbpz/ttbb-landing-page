#!/usr/bin/env bash
# =============================================================================
# ai-daily-generate.sh — 搜集 GitHub 项目 + MiniMax AI 分析 + 生成 Markdown
# Phase 2: 重写规则引擎，读取 rules/ai-daily.yml 配置
# =============================================================================
set -euo pipefail

TODAY=$(date +%Y-%m-%d)
WEEKDAY=$(date +%A)
READABLE_DATE=$(date +"%Y年%m月%d日 $WEEKDAY")
TEMP=$(mktemp -d)
GH_TOKEN="${GH_TOKEN:-}"
MINIMAX_API_KEY="${MINIMAX_API_KEY:-}"

# 默认规则文件
RULES_FILE="${RULES_FILE:-rules/ai-daily.yml}"
DAILY_DIR="docs/daily"
mkdir -p "$DAILY_DIR"

export GH_TOKEN

# ------------------------------------------------------------------------------
# 辅助函数: 回退默认值
# ------------------------------------------------------------------------------
get_config() {
  local key="$1"
  local default="$2"
  if [[ -f "$RULES_FILE" ]] && command -v yq &>/dev/null; then
    yq "$key" "$RULES_FILE" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}

get_config_raw() {
  local key="$1"
  local default="$2"
  if [[ -f "$RULES_FILE" ]] && command -v yq &>/dev/null; then
    yq -r "$key" "$RULES_FILE" 2>/dev/null || echo "$default"
  else
    echo "$default"
  fi
}

# 读取环境变量覆盖配置
ENV_PRIORITY=$(get_config_raw ".env_override.priority" "MINIMAX_API_KEY,MINIMAX_MODEL_NAME,MINIMAX_BASE_URL")

# 读取 search.project_fields（用于 gh --json）
PROJECT_FIELDS=$(get_config_raw ".search.project_fields" "name,description,url,stargazerCount,updatedAt,primaryLanguage")

# 读取 tags 配置
TAG_MAPPING=$(get_config ".tags.mapping" "{}")
TAG_COLORS=$(get_config ".tags.colors" "{}")

# 读取 LLM 配置（带环境变量覆盖）
# env_override 优先级: 环境变量 > yml 配置
if [[ -n "${MINIMAX_MODEL_NAME:-}" ]]; then
  MODEL_NAME="$MINIMAX_MODEL_NAME"
else
  MODEL_NAME=$(get_config ".llm.model // \"MiniMax-Text-01\"" "MiniMax-Text-01")
fi

if [[ -n "${MINIMAX_BASE_URL:-}" ]]; then
  MINIMAX_BASE_URL="$MINIMAX_BASE_URL"
else
  MINIMAX_BASE_URL=$(get_config ".llm.base_url // \"https://api.minimax.chat/v1\"" "https://api.minimax.chat/v1")
fi

MAX_TOKENS=$(get_config ".llm.max_tokens // 4000" "4000")
SYSTEM_PROMPT=$(get_config_raw ".llm.system_prompt" "")

# 读取 LLM 摘要段落结构模板
SUMMARY_OVERVIEW=$(get_config_raw ".llm.summary_structure.overview" "今日概览")
SUMMARY_HIGHLIGHTS=$(get_config_raw ".llm.summary_structure.highlights" "重点推荐")
SUMMARY_TRENDS=$(get_config_raw ".llm.summary_structure.trends" "技术趋势")
SUMMARY_SUGGESTIONS=$(get_config_raw ".llm.summary_structure.suggestions" "学习建议")

# 读取 output 配置
OUTPUT_FORMAT=$(get_config ".output.format // \"markdown\"" "markdown")
OUTPUT_DAILY_DIR=$(get_config ".output.daily_dir // \"docs/daily\"" "docs/daily")
DATE_FORMAT=$(get_config ".output.date_format // \"%Y年%m月%d日 %A\"" "%Y年%m月%d日 %A")
MAX_PROJECTS_PER_CATEGORY=$(get_config ".output.max_projects_per_category // 15" "15")

# 读取 admonition 配置
ADMONITION_INFO=$(get_config ".output.admonition.info // \"info\"" "info")
ADMONITION_WARNING=$(get_config ".output.admonition.warning // \"warning\"" "warning")

# ------------------------------------------------------------------------------
echo "=== [1/6] 读取规则配置 ==="
if [[ -f "$RULES_FILE" ]]; then
  echo "  使用规则: $RULES_FILE"
  if command -v yq &>/dev/null; then
    DIMENSION_COUNT=$(yq '.search.dimensions | length' "$RULES_FILE" 2>/dev/null || echo "0")
    echo "  发现 $DIMENSION_COUNT 个搜索维度"
  else
    echo "  yq 未安装，使用默认搜索维度"
    DIMENSION_COUNT="0"
  fi
else
  echo "  规则文件 $RULES_FILE 不存在，使用默认配置"
  DIMENSION_COUNT="0"
fi

# ------------------------------------------------------------------------------
echo "=== [2/6] 搜索 GitHub 项目 ==="

# 用于统计总数
TOTAL_PROJECTS=0
DIMENSION_RESULTS=()

# 从配置读取维度数量
if [[ -f "$RULES_FILE" ]] && command -v yq &>/dev/null && [[ "$DIMENSION_COUNT" != "0" ]]; then
  # 动态读取配置中的搜索维度
  for i in $(seq 0 $((DIMENSION_COUNT - 1))); do
    NAME=$(yq -r ".search.dimensions[$i].name" "$RULES_FILE" 2>/dev/null)
    QUERY=$(yq -r ".search.dimensions[$i].query" "$RULES_FILE" 2>/dev/null)
    LIMIT=$(yq -r ".search.dimensions[$i].limit // 15" "$RULES_FILE" 2>/dev/null)
    SORT=$(yq -r ".search.dimensions[$i].sort // \"stars\"" "$RULES_FILE" 2>/dev/null)
    ORDER=$(yq -r ".search.dimensions[$i].order // \"desc\"" "$RULES_FILE" 2>/dev/null)
    # 生成 safe label（去掉空格和特殊字符）
    LABEL=$(echo "$NAME" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]' | cut -c1-20)

    echo "  → [$i] $NAME (query: $QUERY, limit: $LIMIT)"

    gh search repos "$QUERY" --limit "$LIMIT" --sort "$SORT" --order "$ORDER" \
      --json "$PROJECT_FIELDS" \
      > "$TEMP/$LABEL.json" 2>/dev/null || echo "[]" > "$TEMP/$LABEL.json"

    # 统计该项目数量
    DIM_PROJECTS=$(jq 'length' "$TEMP/$LABEL.json" 2>/dev/null || echo 0)
    TOTAL_PROJECTS=$((TOTAL_PROJECTS + DIM_PROJECTS))
    DIMENSION_RESULTS+=("$NAME: $DIM_PROJECTS")
  done
else
  # 回退到硬编码默认 5 个搜索维度
  search() {
    local q="$1" label="$2"
    echo "  → $label"
    gh search repos "$q" --limit 15 --sort stars --order desc \
      --json "$PROJECT_FIELDS" \
      > "$TEMP/$label.json" 2>/dev/null || echo "[]" > "$TEMP/$label.json"

    # 统计该项目数量
    DIM_PROJECTS=$(jq 'length' "$TEMP/$label.json" 2>/dev/null || echo 0)
    TOTAL_PROJECTS=$((TOTAL_PROJECTS + DIM_PROJECTS))
    DIMENSION_RESULTS+=("$label: $DIM_PROJECTS")
  }
  search "AI coding assistant" "coding"
  search "LLM agent framework" "agent"
  search "code review AI agent" "review"
  search "MCP model context protocol" "mcp"
  search "vibe coding OR AI software development" "vibe"
fi

echo ""
echo "  === 搜索统计 ==="
echo "  搜索到的项目总数: $TOTAL_PROJECTS"
for result in "${DIMENSION_RESULTS[@]}"; do
  echo "    - $result"
done
echo "  JSON 数据保存在: $TEMP/"

# ------------------------------------------------------------------------------
echo "=== [3/6] 调用 MiniMax API 生成 AI 摘要 ==="

build_summary_prompt() {
  # 使用配置中的 system_prompt 或默认模板
  if [[ -n "$SYSTEM_PROMPT" ]]; then
    echo "$SYSTEM_PROMPT"
  else
    cat << 'DEFAULT_PROMPT'
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
DEFAULT_PROMPT
  fi

  # 拼接所有 JSON 数据（根据实际生成的标签）
  for json_file in "$TEMP"/*.json; do
    if [[ -f "$json_file" ]]; then
      LABEL=$(basename "$json_file" .json)
      echo ""
      echo "【$LABEL】"
      cat "$json_file"
    fi
  done
}

SUMMARY=""
API_RESPONSE_FILE="$TEMP/api_response.json"
if [[ -n "$MINIMAX_API_KEY" && "$MINIMAX_API_KEY" != "dummy" && "$MINIMAX_API_KEY" != "sk-" ]]; then
  echo "  调用 MiniMax API..."
  echo "  模型: $MODEL_NAME, Base URL: $MINIMAX_BASE_URL, Max Tokens: $MAX_TOKENS"
  PROMPT_CONTENT=$(build_summary_prompt | jq -Rs .)
  API_RESPONSE=$(curl -s --fail \
    -H "Authorization: Bearer $MINIMAX_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL_NAME\",\"messages\":[{\"role\":\"user\",\"content\":$PROMPT_CONTENT}],\"max_tokens\":$MAX_TOKENS}" \
    "$MINIMAX_BASE_URL/chat/completions" 2>/dev/null)
  echo "$API_RESPONSE" > "$API_RESPONSE_FILE"

  # 提取摘要内容
  SUMMARY=$(echo "$API_RESPONSE" | jq -r '.choices[0].message.content // empty' || echo "")

  # 提取 token 消耗信息
  if echo "$API_RESPONSE" | jq -e '.usage' &>/dev/null; then
    PROMPT_TOKENS=$(echo "$API_RESPONSE" | jq -r '.usage.prompt_tokens // "N/A"')
    COMPLETION_TOKENS=$(echo "$API_RESPONSE" | jq -r '.usage.completion_tokens // "N/A"')
    TOTAL_TOKENS=$(echo "$API_RESPONSE" | jq -r '.usage.total_tokens // "N/A"')
    echo "  AI API 调用状态: 成功"
    echo "  Token 消耗 - Prompt: $PROMPT_TOKENS, Completion: $COMPLETION_TOKENS, Total: $TOTAL_TOKENS"
  else
    echo "  AI API 调用状态: 响应无 usage 字段"
  fi
  echo "  AI 摘要生成完成"
else
  echo "  跳过 AI 摘要（MINIMAX_API_KEY 未设置或为 placeholder）"
fi

# ------------------------------------------------------------------------------
echo "=== [4/6] 生成每日 Markdown 页面 ==="

render_md_cards() {
  local json="$1" section_name="$2"
  local count
  count=$(jq 'length' "$json" 2>/dev/null || echo 0)
  echo ""
  echo "### $section_name"
  echo ""
  # 应用 max_projects_per_category 限制
  jq -r ".[:$MAX_PROJECTS_PER_CATEGORY] | .[] | \"**[\" + .name + \"](\" + .url + \")** ★ \" + (.stargazerCount | tostring) + \" | \\`\" + (.primaryLanguage // "代码") + \"\\`\n\n\" + (.description // \"\") + \"\n\"" "$json" 2>/dev/null || true
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
  echo "!!! $ADMONITION_INFO \"🤖 AI 观察员点评\"" >> "$DAILY_DIR/$TODAY.md"
  echo '    ' >> "$DAILY_DIR/$TODAY.md"
  echo "$SUMMARY" | sed 's/^/    /' >> "$DAILY_DIR/$TODAY.md"
  echo "" >> "$DAILY_DIR/$TODAY.md"
fi

# 项目卡片（根据实际生成的 JSON 文件）
echo '## 📊 项目速览' >> "$DAILY_DIR/$TODAY.md"

if [[ -f "$RULES_FILE" ]] && command -v yq &>/dev/null && [[ "$DIMENSION_COUNT" != "0" ]]; then
  # 动态渲染配置中的维度
  for i in $(seq 0 $((DIMENSION_COUNT - 1))); do
    NAME=$(yq -r ".search.dimensions[$i].name" "$RULES_FILE" 2>/dev/null)
    LABEL=$(echo "$NAME" | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]' | cut -c1-20)
    if [[ -f "$TEMP/$LABEL.json" ]]; then
      render_md_cards "$TEMP/$LABEL.json" "$NAME" >> "$DAILY_DIR/$TODAY.md"
    fi
  done
else
  # 回退到硬编码的 5 个维度
  render_md_cards "$TEMP/coding.json" "AI 编程助手" >> "$DAILY_DIR/$TODAY.md"
  render_md_cards "$TEMP/agent.json" "LLM Agent 框架" >> "$DAILY_DIR/$TODAY.md"
  render_md_cards "$TEMP/review.json" "AI 代码审查" >> "$DAILY_DIR/$TODAY.md"
  render_md_cards "$TEMP/mcp.json" "MCP 协议" >> "$DAILY_DIR/$TODAY.md"
  render_md_cards "$TEMP/vibe.json" "AI 软件开发" >> "$DAILY_DIR/$TODAY.md"
fi

echo "" >> "$DAILY_DIR/$TODAY.md"
echo '=== "数据来源"' >> "$DAILY_DIR/$TODAY.md"
echo "GitHub Trending · AI 分析：MiniMax $MODEL_NAME · 最后更新：$READABLE_DATE" >> "$DAILY_DIR/$TODAY.md"

# ------------------------------------------------------------------------------
echo "=== [5/6] 确认 MkDocs 导航 ==="
# MkDocs 通过 mkdocs.yml 中的 nav 配置自动读取 docs/daily/*.md
# 确保当日文件存在即可
if [[ -f "$DAILY_DIR/$TODAY.md" ]]; then
  echo "  当日页面已生成: $DAILY_DIR/$TODAY.md"
else
  echo "  警告: 当日页面未生成"
fi

# ------------------------------------------------------------------------------
echo "=== [6/6] 归档原始 JSON 数据 ==="
ARCHIVE_DIR="docs/data/$TODAY"
mkdir -p "$ARCHIVE_DIR"
if [[ -d "$TEMP" ]]; then
  cp "$TEMP"/*.json "$ARCHIVE_DIR/" 2>/dev/null || true
  echo "  原始 JSON 数据已归档到: $ARCHIVE_DIR/"
  ARCHIVED_COUNT=$(ls -1 "$ARCHIVE_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')
  echo "  归档文件数: $ARCHIVED_COUNT"
fi

# ------------------------------------------------------------------------------
echo "=== [7/7] 清理 ==="
rm -rf "$TEMP"
echo ""
echo "=== 完成 ==="
echo "  每日页面: $DAILY_DIR/$TODAY.md"
