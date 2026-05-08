#!/usr/bin/env bash
# =============================================================================
# ai-daily-generate.sh — 搜集 GitHub 项目 + LLM AI 分析 + 生成 Markdown
# 支持 MiniMax / DeepSeek 多厂商切换
# =============================================================================
set -euo pipefail

TODAY=$(date +%Y-%m-%d)
WEEKDAY=$(date +%A)
READABLE_DATE=$(date +"%Y年%m月%d日 $WEEKDAY")
# 支持 TARGET_DATE 环境变量指定日期（用于手动测试 CI）
TARGET_DATE="${TARGET_DATE:-}"
if [[ -n "$TARGET_DATE" ]]; then
  TODAY="$TARGET_DATE"
  WEEKDAY=$(date -d "$TARGET_DATE" +%A 2>/dev/null || date -j -f "%Y-%m-%d" "$TARGET_DATE" +%A 2>/dev/null || echo "Unknown")
  READABLE_DATE=$(date -d "$TARGET_DATE" +"%Y年%m月%d日 $WEEKDAY" 2>/dev/null || date -j -f "%Y-%m-%d" "$TARGET_DATE" +"%Y年%m月%d日 $WEEKDAY" 2>/dev/null || echo "$TARGET_DATE")
fi
TEMP=$(mktemp -d)
GH_TOKEN="${GH_TOKEN:-}"
# 向后兼容：保留旧变量名
MINIMAX_API_KEY="${MINIMAX_API_KEY:-}"
MINIMAX_BASE_URL="${MINIMAX_BASE_URL:-}"
MINIMAX_MODEL_NAME="${MINIMAX_MODEL_NAME:-}"

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
ENV_PRIORITY=$(get_config_raw ".env_override.priority" "LLM_PROVIDER,LLM_API_KEY,LLM_BASE_URL,LLM_MODEL_NAME,MINIMAX_API_KEY,MINIMAX_MODEL_NAME,MINIMAX_BASE_URL")

# 读取 search.project_fields（用于 gh --json）
PROJECT_FIELDS=$(get_config_raw ".search.project_fields" "name,description,url,stargazersCount,updatedAt,language")

# 读取 tags 配置
TAG_MAPPING=$(get_config ".tags.mapping" "{}")
TAG_COLORS=$(get_config ".tags.colors" "{}")

# ==============================================================================
# LLM 提供商解析（支持 MiniMax / DeepSeek 多厂商切换）
# 优先级: 环境变量 > yml providers 预设 > 旧 MINIMAX_* 变量（向后兼容）
# ==============================================================================

# 1. 确定提供商
LLM_PROVIDER="${LLM_PROVIDER:-}"
if [[ -z "$LLM_PROVIDER" ]]; then
  LLM_PROVIDER=$(get_config_raw ".llm.provider" "minimax")
fi

# 2. 读取提供商预设（base_url、model、name）
PROVIDER_NAME=$(get_config_raw ".llm.providers.${LLM_PROVIDER}.name" "$LLM_PROVIDER")
PROVIDER_BASE_URL=$(get_config_raw ".llm.providers.${LLM_PROVIDER}.base_url" "")
PROVIDER_MODEL=$(get_config_raw ".llm.providers.${LLM_PROVIDER}.model" "")
PROVIDER_API_KEY_ENV=$(get_config_raw ".llm.providers.${LLM_PROVIDER}.api_key_env" "")

# 3. API Key: LLM_API_KEY > 提供商预设的 api_key_env > MINIMAX_API_KEY(向后兼容)
LLM_API_KEY="${LLM_API_KEY:-}"
if [[ -z "$LLM_API_KEY" && -n "$PROVIDER_API_KEY_ENV" ]]; then
  LLM_API_KEY="${!PROVIDER_API_KEY_ENV:-}"
fi
if [[ -z "$LLM_API_KEY" ]]; then
  LLM_API_KEY="${MINIMAX_API_KEY:-}"
fi

# 4. Base URL: LLM_BASE_URL > 提供商 base_url > MINIMAX_BASE_URL(向后兼容)
LLM_BASE_URL="${LLM_BASE_URL:-}"
if [[ -z "$LLM_BASE_URL" ]]; then
  LLM_BASE_URL="$PROVIDER_BASE_URL"
fi
if [[ -z "$LLM_BASE_URL" ]]; then
  LLM_BASE_URL="${MINIMAX_BASE_URL:-}"
fi

# 5. Model: LLM_MODEL_NAME > 提供商 model > MINIMAX_MODEL_NAME(向后兼容)
LLM_MODEL_NAME="${LLM_MODEL_NAME:-}"
if [[ -z "$LLM_MODEL_NAME" ]]; then
  LLM_MODEL_NAME="$PROVIDER_MODEL"
fi
if [[ -z "$LLM_MODEL_NAME" ]]; then
  LLM_MODEL_NAME="${MINIMAX_MODEL_NAME:-}"
fi

# 通用配置
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
echo "=== [1/7] 读取规则配置 ==="
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
echo "=== [2/7] 搜索 GitHub 项目 ==="

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

    echo "    执行: gh search repos \"$QUERY\" --limit $LIMIT --sort $SORT --order $ORDER"
    SEARCH_OUTPUT=$(gh search repos "$QUERY" --limit "$LIMIT" --sort "$SORT" --order "$ORDER" \
      --json "$PROJECT_FIELDS" 2>&1) || true
    SEARCH_EXIT=$?
    # 检查是否是有效 JSON 数组
    if [[ $SEARCH_EXIT -eq 0 ]] && echo "$SEARCH_OUTPUT" | jq -e 'type == "array"' &>/dev/null; then
      echo "$SEARCH_OUTPUT" > "$TEMP/$LABEL.json"
      ARRAY_LEN=$(echo "$SEARCH_OUTPUT" | jq 'length')
      echo "    成功: 获取 $ARRAY_LEN 个项目"
    else
      echo "    错误: gh search 失败 (exit $SEARCH_EXIT)"
      echo "    原始输出: $SEARCH_OUTPUT" | head -5 | sed 's/^/      /'
      echo "[]" > "$TEMP/$LABEL.json"
    fi

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
    echo "    执行: gh search repos \"$q\" --limit 15 --sort stars --order desc"
    SEARCH_OUTPUT=$(gh search repos "$q" --limit 15 --sort stars --order desc \
      --json "$PROJECT_FIELDS" 2>&1) || true
    SEARCH_EXIT=$?
    if [[ $SEARCH_EXIT -eq 0 ]] && echo "$SEARCH_OUTPUT" | jq -e 'type == "array"' &>/dev/null; then
      echo "$SEARCH_OUTPUT" > "$TEMP/$label.json"
      ARRAY_LEN=$(echo "$SEARCH_OUTPUT" | jq 'length')
      echo "    成功: 获取 $ARRAY_LEN 个项目"
    else
      echo "    错误: gh search 失败 (exit $SEARCH_EXIT)"
      echo "    原始输出: $SEARCH_OUTPUT" | head -5 | sed 's/^/      /'
      echo "[]" > "$TEMP/$label.json"
    fi

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
echo "=== [3/7] 调用 $PROVIDER_NAME API 生成 AI 摘要 ==="

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
if [[ -n "$LLM_API_KEY" && "$LLM_API_KEY" != "dummy" && "$LLM_API_KEY" != "sk-" ]]; then
  echo "  调用 $PROVIDER_NAME API..."
  echo "  模型: $LLM_MODEL_NAME, Base URL: $LLM_BASE_URL, Max Tokens: $MAX_TOKENS"
  PROMPT_CONTENT=$(build_summary_prompt | jq -Rs .)
  HTTP_RESPONSE=$(curl -s -w "%{http_code}" -o "$API_RESPONSE_FILE" \
    -H "Authorization: Bearer $LLM_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$LLM_MODEL_NAME\",\"messages\":[{\"role\":\"user\",\"content\":$PROMPT_CONTENT}],\"max_tokens\":$MAX_TOKENS}" \
    "$LLM_BASE_URL/chat/completions" 2>&1)
  API_RESPONSE=$(cat "$API_RESPONSE_FILE")
  echo "  HTTP 状态码: $HTTP_RESPONSE"
  if [[ "$HTTP_RESPONSE" -ge 400 ]]; then
    echo "  错误: API 请求失败，响应内容:"
    cat "$API_RESPONSE_FILE"
    SUMMARY=""
  fi

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
echo "=== [4/7] 生成每日 Markdown 页面 ==="

render_md_cards() {
  local json="$1" section_name="$2"
  local count
  count=$(jq 'length' "$json" 2>/dev/null || echo 0)
  echo ""
  echo "### $section_name"
  echo ""
  if [[ "$count" -eq 0 ]]; then
    echo "暂无项目数据"
  else
    # 应用 max_projects_per_category 限制
    # 使用 for loop + jq 分别处理每个元素，避免 shell 变量解析问题
    local max_items
    max_items=$(echo "$count" | awk "{if($count<$MAX_PROJECTS_PER_CATEGORY) print $count; else print $MAX_PROJECTS_PER_CATEGORY}")
    for i in $(seq 0 $((max_items - 1))); do
      jq -r --argjson idx "$i" '
        if .[$idx] != null then
          "**[" + .[$idx].name + "](" + .[$idx].url + ")** ★ " + (.[$idx].stargazersCount | tostring) + " | `" + (.[$idx].language // "代码") + "`\n\n" + (.[$idx].description // "") + "\n"
        else
          empty
        end
      ' "$json" 2>/dev/null || true
    done
  fi
}

cat > "$DAILY_DIR/$TODAY.md" << MD_HEADER
---
title: AI + Code 每日速递 $TODAY
description: 每日搜集 GitHub AI+Code 热门开源项目，$PROVIDER_NAME AI 分析技术趋势
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
echo "GitHub Trending · AI 分析：$PROVIDER_NAME $LLM_MODEL_NAME · 最后更新：$READABLE_DATE" >> "$DAILY_DIR/$TODAY.md"

# ------------------------------------------------------------------------------
echo "=== [5/7] 确认 MkDocs 导航 ==="
# MkDocs 通过 mkdocs.yml 中的 nav 配置自动读取 docs/daily/*.md
# 确保当日文件存在即可
if [[ -f "$DAILY_DIR/$TODAY.md" ]]; then
  echo "  当日页面已生成: $DAILY_DIR/$TODAY.md"
else
  echo "  警告: 当日页面未生成"
fi

# ------------------------------------------------------------------------------
echo "=== [6/7] 归档原始 JSON 数据 ==="
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
