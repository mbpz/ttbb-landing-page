#!/usr/bin/env bash
# =============================================================================
# ai-daily-generate.sh — 搜集 GitHub 项目 + MiniMax AI 分析 + 生成 HTML
# =============================================================================
set -euo pipefail

TODAY=$(date +%Y-%m-%d)
WEEKDAY=$(date +%A)
READABLE_DATE=$(date +"%Y年%m月%d日 $WEEKDAY")
OUTPUT_FILE="docs/index.html"
DATA_DIR="docs/data/$TODAY"
TEMP=$(mktemp -d)
GH_TOKEN="${GH_TOKEN:-}"
MINIMAX_API_KEY="${MINIMAX_API_KEY:-}"
MINIMAX_BASE_URL="${MINIMAX_BASE_URL:-https://api.minimax.chat/v1}"
MODEL_NAME="${MINIMAX_MODEL_NAME:-MiniMax-Text-01}"

# GH_TOKEN 传给 gh
export GH_TOKEN

mkdir -p "$DATA_DIR" "$(dirname "$OUTPUT_FILE")"

echo "=== [1/5] 搜索 GitHub 项目 (5个维度) ==="

search() {
  local q="$1" label="$2"
  echo "  → $label"
  gh search repos "$q" --limit 15 --sort stars --order desc \
    --json name,description,url,stargazerCount,updatedAt,primaryLanguage \
    > "$TEMP/$label.json" 2>/dev/null || echo "[]" > "$TEMP/$label.json"
}

search "AI coding assistant" "coding"
search "LLM agent framework" "agent"
search "code review AI agent" "review"
search "MCP model context protocol" "mcp"
search "vibe coding OR AI software development" "vibe"

cp "$TEMP/"*.json "$DATA_DIR/"
echo "  完成，数据在 $DATA_DIR/"

# ------------------------------------------------------------------------------
echo "=== [2/5] 准备 AI 分析 ==="
build_prompt() {
cat << 'PROMPT'
你是 AI 技术观察员。请分析以下 GitHub trending 项目，用中文撰写一份结构化报告。

## 输出格式
1. **今日概览** — 总览整体趋势（2-3句话）
2. **重点推荐**（精选 4-5 个项目，每个简述：核心功能 + 技术亮点 + 适用场景）
3. **技术趋势** — 本周新方向或模式
4. **学习建议** — 新手/进阶/架构师分别看哪些

## 数据（JSON格式，5个维度）
PROMPT
for label in coding agent review mcp vibe; do
  echo ""
  echo "【$label】"
  cat "$TEMP/$label.json"
done
}

ANALYSIS=""
if [[ -n "$MINIMAX_API_KEY" && "$MINIMAX_API_KEY" != "dummy" ]]; then
  echo "  调用 MiniMax API..."
  PROMPT_CONTENT=$(build_prompt | jq -Rs .)
  ANALYSIS=$(curl -s --fail \
    -H "Authorization: Bearer $MINIMAX_API_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL_NAME\",\"messages\":[{\"role\":\"user\",\"content\":$PROMPT_CONTENT}],\"max_tokens\":4000}" \
    "$MINIMAX_BASE_URL/chat/completions" 2>/dev/null | \
    jq -r '.choices[0].message.content // empty' || echo "")
  echo "  AI 分析完成"
else
  echo "  跳过 AI 分析（MINIMAX_API_KEY 未设置）"
fi

# ------------------------------------------------------------------------------
echo "=== [3/5] 生成 MkDocs 风格 HTML ==="

render_cards() {
  local json="$1" section_id="$2" section_icon="$3" section_label="$4" tag_class="$5"
  if ! grep -q 'name' "$json" 2>/dev/null; then return; fi
  local count
  count=$(jq 'length' "$json" 2>/dev/null || echo 0)
  cat << CARDS
<section class="md-section" id="$section_id">
  <span class="md-section__icon">$section_icon</span>
  <span class="md-section__title">$section_label</span>
  <span class="md-section__count">$count 个项目</span>
</section>
CARDS
  jq -r '.[] | "<div class=\"md-card\"><div class=\"md-card__header\"><span class=\"md-card__title\"><a href=\"" + .url + "\">" + .name + "</a></span><span class=\"md-card__stars\">★ " + (.stargazerCount | tostring) + "</span></div><p class=\"md-card__desc\">" + (.description // "无描述") + "</p><div class=\"md-card__tags\"><span class=\"md-tag "'\''$tag_class'\''">" + (.primaryLanguage // "代码") + "</span></div></div>"' "$json" 2>/dev/null || true
}

cat > "$OUTPUT_FILE" << HTML_HEAD
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AI + Code 每日速递 — $TODAY</title>
  <meta name="description" content="每日搜集 GitHub AI+Code 热门开源项目，AI 分析技术趋势">
  <style>
:root{--bg-primary:#0a0a0f;--bg-secondary:#12121a;--bg-card:#1a1a24;--text-primary:#ffffff;--text-secondary:#a0a0b0;--accent:#6366f1;--accent-hover:#818cf8;--accent-cyan:#22d3ee;--success:#10b981;--border:#2a2a3a}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:var(--bg-primary);color:var(--text-primary);line-height:1.6}
.md-header{background:var(--bg-secondary);border-bottom:1px solid var(--border);padding:0.75rem 2rem;display:flex;align-items:center;gap:1rem}
.md-header__topic{color:var(--accent-cyan);font-size:0.75rem;text-transform:uppercase;letter-spacing:0.05em}
.md-header__title{font-weight:600;font-size:1rem}
.md-header__date{margin-left:auto;color:var(--text-secondary);font-size:0.85rem}
.ai-hero{background:linear-gradient(135deg,rgba(99,102,241,0.12) 0%,rgba(34,211,238,0.06) 100%);border-bottom:1px solid var(--border);padding:3rem 2rem;text-align:center}
.ai-hero h1{font-size:2.5rem;font-weight:800;background:linear-gradient(135deg,var(--text-primary),var(--accent-cyan));-webkit-background-clip:text;-webkit-text-fill-color:transparent;margin-bottom:0.5rem}
.ai-hero .subtitle{color:var(--text-secondary);font-size:1rem}
.md-container{max-width:1100px;margin:0 auto;padding:2rem}
.md-grid{display:grid;grid-template-columns:1fr 260px;gap:2rem;align-items:start}
@media(max-width:900px){.md-grid{grid-template-columns:1fr}}
.md-sidebar{position:sticky;top:1rem;background:var(--bg-secondary);border:1px solid var(--border);border-radius:0.5rem;padding:1rem}
.md-sidebar__title{font-size:0.7rem;text-transform:uppercase;letter-spacing:0.08em;color:var(--accent-cyan);margin-bottom:0.75rem;font-weight:600}
.md-sidebar__list{list-style:none}
.md-sidebar__list li{margin-bottom:0.4rem}
.md-sidebar__list a{color:var(--text-secondary);text-decoration:none;font-size:0.875rem;display:flex;align-items:center;gap:0.4rem;padding:0.2rem 0;border-radius:0.25rem;transition:color 0.15s}
.md-sidebar__list a:hover{color:var(--accent)}
.md-sidebar__list .num{color:var(--accent-cyan);font-size:0.75rem;min-width:1.2rem}
.md-inset{background:var(--bg-secondary);border-left:3px solid var(--accent);border-radius:0 0.5rem 0.5rem 0;padding:1.25rem 1.5rem;margin-bottom:2rem}
.md-inset h2{font-size:0.7rem;text-transform:uppercase;letter-spacing:0.08em;color:var(--accent);margin-bottom:1rem;font-weight:600}
.md-inset h3{color:var(--accent-cyan);font-size:0.95rem;margin:1rem 0 0.4rem}
.md-inset p{color:var(--text-secondary);font-size:0.9rem;margin-bottom:0.6rem}
.md-card{background:var(--bg-secondary);border:1px solid var(--border);border-radius:0.5rem;padding:1.25rem 1.5rem;margin-bottom:1rem;transition:border-color 0.2s}
.md-card:hover{border-color:var(--accent)}
.md-card__header{display:flex;align-items:flex-start;justify-content:space-between;gap:0.75rem;margin-bottom:0.5rem}
.md-card__title{font-size:1rem;font-weight:600}
.md-card__title a{color:inherit;text-decoration:none}
.md-card__title a:hover{color:var(--accent)}
.md-card__stars{font-size:0.8rem;color:var(--accent-cyan);white-space:nowrap;background:rgba(34,211,238,0.1);padding:0.15rem 0.5rem;border-radius:999px;border:1px solid rgba(34,211,238,0.2)}
.md-card__desc{color:var(--text-secondary);font-size:0.875rem;margin-bottom:0.75rem}
.md-card__tags{display:flex;flex-wrap:wrap;gap:0.4rem}
.md-tag{display:inline-block;font-size:0.7rem;padding:0.1rem 0.5rem;border-radius:0.25rem;font-weight:600}
.md-tag--framework{background:rgba(99,102,241,0.15);color:#a5b4fc;border:1px solid rgba(99,102,241,0.3)}
.md-tag--tool{background:rgba(34,211,238,0.12);color:#67e8f9;border:1px solid rgba(34,211,238,0.25)}
.md-tag--product{background:rgba(16,185,129,0.12);color:#6ee7b7;border:1px solid rgba(16,185,129,0.25)}
.md-tag--architecture{background:rgba(245,158,11,0.12);color:#fcd34d;border:1px solid rgba(245,158,11,0.25)}
.md-section{margin:2rem 0 1rem;padding-bottom:0.4rem;border-bottom:1px solid var(--border);display:flex;align-items:center;gap:0.75rem}
.md-section__icon{font-size:1.1rem}
.md-section__title{font-size:1.1rem;font-weight:600;color:var(--accent-cyan)}
.md-section__count{font-size:0.75rem;color:var(--text-secondary);margin-left:auto}
.md-footer{text-align:center;padding:2rem;color:var(--text-secondary);font-size:0.8rem;border-top:1px solid var(--border);margin-top:3rem}
.md-footer a{color:var(--accent);text-decoration:none}
.md-footer a:hover{text-decoration:underline}
.md-footer .separator{margin:0 0.5rem;color:var(--border)}
  </style>
</head>
<body>
<header class="md-header">
  <span class="md-header__topic">TTBB</span>
  <span class="md-header__title">AI + Code 每日速递</span>
  <span class="md-header__date">$READABLE_DATE</span>
</header>

<section class="ai-hero">
  <h1>AI + Code 每日速递</h1>
  <p class="subtitle">GitHub Trending · AI 分析 · 技术趋势</p>
</section>

<div class="md-container">
  <div class="md-grid">
    <div class="main">
HTML_HEAD

# AI 分析块
if [[ -n "$ANALYSIS" ]]; then
  echo '      <div class="md-inset">' >> "$OUTPUT_FILE"
  echo '        <h2>AI 观察员点评</h2>' >> "$OUTPUT_FILE"
  echo "$ANALYSIS" | sed 's/^## /<h3>/g' | sed 's/^### /<h4 style="color:var(--text-secondary);font-size:0.85rem;margin:0.6rem 0 0.3rem">/g' | sed 's/$/<\/h3>/g' | sed 's/<\/h3>\n<h3>/<\/h3><h3>/g' | sed 's/<\/h4>$/<\/h4>/g' >> "$OUTPUT_FILE"
  echo '      </div>' >> "$OUTPUT_FILE"
fi

# 项目卡片
render_cards "$TEMP/coding.json" "coding" "🤖" "AI 编程助手" "md-tag--tool" >> "$OUTPUT_FILE"
render_cards "$TEMP/agent.json" "agent" "🔗" "LLM Agent 框架" "md-tag--framework" >> "$OUTPUT_FILE"
render_cards "$TEMP/review.json" "review" "🔍" "AI 代码审查" "md-tag--tool" >> "$OUTPUT_FILE"
render_cards "$TEMP/mcp.json" "mcp" "⚡" "MCP 协议" "md-tag--architecture" >> "$OUTPUT_FILE"
render_cards "$TEMP/vibe.json" "vibe" "✨" "AI 软件开发" "md-tag--product" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'HTML_TAIL'
    </div>
    <aside class="md-sidebar">
      <p class="md-sidebar__title">导航</p>
      <ul class="md-sidebar__list">
        <li><a href="#coding"><span class="num">01</span> AI 编程助手</a></li>
        <li><a href="#agent"><span class="num">02</span> LLM Agent 框架</a></li>
        <li><a href="#review"><span class="num">03</span> AI 代码审查</a></li>
        <li><a href="#mcp"><span class="num">04</span> MCP 协议</a></li>
        <li><a href="#vibe"><span class="num">05</span> AI 软件开发</a></li>
      </ul>
    </aside>
  </div>
</div>

<footer class="md-footer">
  <span>AI + Code 每日速递</span>
  <span class="separator">·</span>
  <span>数据来源：GitHub Trending</span>
  <span class="separator">·</span>
  <span>AI 分析：MiniMax</span>
</footer>
</body>
</html>
HTML_TAIL

# ------------------------------------------------------------------------------
echo "=== [4/5] 更新时间戳 ==="
touch "$OUTPUT_FILE"

# ------------------------------------------------------------------------------
echo "=== [5/5] 清理 ==="
rm -rf "$TEMP"
echo ""
echo "=== 完成 ==="
echo "  输出: $OUTPUT_FILE"
echo "  数据: $DATA_DIR/"
