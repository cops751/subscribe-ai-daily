#!/usr/bin/env bash
# subscribe-ai-daily one-line installer.
# Detects Claude Code and/or Codex, copies skill files, runs a 4-question
# wizard, writes config.json, and optionally installs a macOS LaunchAgent
# that fires the skill on a daily schedule.
set -euo pipefail

SKILL_NAME="subscribe-ai-daily"
CLAUDE_DIR="$HOME/.claude/skills/$SKILL_NAME"
CODEX_DIR="${CODEX_SKILL_DIR:-$HOME/.codex/skills/$SKILL_NAME}"
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/cops751/subscribe-ai-daily/main}"
CODEX_BIN="/Applications/ChatGPT.app/Contents/Resources/codex"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

echo "=== subscribe-ai-daily installer ==="

# --- 1. Detect host(s) ---
INSTALL_CLAUDE=0
INSTALL_CODEX=0
if [[ -d "$HOME/.claude" ]]; then
  INSTALL_CLAUDE=1
fi
if [[ -d "$HOME/.codex/skills" ]]; then
  INSTALL_CODEX=1
elif [[ -d "$HOME/.codex" ]]; then
  echo "WARN: ~/.codex present but ~/.codex/skills missing — install Codex CLI v0.145+ or create ~/.codex/skills/ (skipping Codex)." >&2
fi

if [[ $INSTALL_CLAUDE -eq 0 && $INSTALL_CODEX -eq 0 ]]; then
  echo "ERROR: neither ~/.claude nor ~/.codex/skills found. Install Claude Code or Codex first." >&2
  exit 1
fi

# --- 2. Copy files (from local checkout if present, else curl from raw) ---
install_one() {
  local dest_root="$1"
  mkdir -p "$dest_root/lib"
  if [[ -f "SKILL.md" ]]; then
    cp SKILL.md sources.json config.example.json "$dest_root/"
    cp lib/*.sh "$dest_root/lib/" 2>/dev/null || true
    # VERSION: stamped at release so the skill can self-check for updates.
    if [[ -f "VERSION" ]]; then cp VERSION "$dest_root/"; else echo "dev" > "$dest_root/VERSION"; fi
  else
    local f
    for f in SKILL.md sources.json config.example.json lib/merge_sources.sh lib/fetch_articles.sh VERSION; do
      curl -fsSL -H "User-Agent: $UA" "$REPO_RAW_BASE/$f" -o "$dest_root/$f" 2>/dev/null || true
    done
    [[ -f "$dest_root/VERSION" ]] || echo "dev" > "$dest_root/VERSION"
  fi
  [[ -f "$dest_root/config.json" ]] || cp "$dest_root/config.example.json" "$dest_root/config.json"
  echo "installed -> $dest_root"
}

if [[ $INSTALL_CLAUDE -eq 1 ]]; then
  install_one "$CLAUDE_DIR"
fi
if [[ $INSTALL_CODEX -eq 1 ]]; then
  install_one "$CODEX_DIR"
fi

# --- 3. 4-question wizard ---
# Canonical config lives at the Claude path when both hosts are installed.
TARGET_CONFIG="$CLAUDE_DIR/config.json"
if [[ $INSTALL_CLAUDE -eq 0 ]]; then
  TARGET_CONFIG="$CODEX_DIR/config.json"
fi

ENABLE_SCHED=0
CRON="0 9 * * *"
HH=9
MM=0

read -r -p "开启定时推送? (y/N) " ANS_SCHEDULE || ANS_SCHEDULE=""
if [[ "${ANS_SCHEDULE:-N}" =~ ^[Yy] ]]; then
  ENABLE_SCHED=1
  read -r -p "每天推送时间 (HH:MM, 默认 09:00) " TM || TM=""
  TM="${TM:-09:00}"
  HH=$(echo "$TM" | cut -d: -f1 | sed 's/^0//')
  MM=$(echo "$TM" | cut -d: -f2 | sed 's/^0//')
  CRON="$MM $HH * * *"
fi

read -r -p "输出语言 (zh/en, 默认 zh) " LANG_OUT || LANG_OUT=""
LANG_OUT="${LANG_OUT:-zh}"

read -r -p "文章类别 (回车=blog,research,news 全选; 或用逗号筛选) " CATS || CATS=""
CATS="${CATS:-blog,research,news}"
CATS_JSON=$(echo "$CATS" | tr ',' '\n' | jq -R . | jq -s .)

read -r -p "公司筛选 (回车=10家全选; 或用逗号列出要保留的 id) " COMPS || COMPS=""
if [[ -z "$COMPS" ]]; then
  COMPS_JSON='["anthropic","openai","google","meta","deepseek","moonshot","zhipu","kimi","alibaba","bytedance"]'
else
  COMPS_JSON=$(echo "$COMPS" | tr ',' '\n' | jq -R . | jq -s .)
fi

mkdir -p "$HOME/ai-daily"
SCHED_JSON=$(printf '{"enabled":%s,"cron":"%s"}' "$ENABLE_SCHED" "$CRON")
jq -n \
  --arg lang "$LANG_OUT" \
  --argjson cats "$CATS_JSON" \
  --argjson comps "$COMPS_JSON" \
  --argjson sched "$SCHED_JSON" \
  '{language:$lang, categories:$cats, companies:$comps, summary_style:"paragraph", window_hours:24, output_dir:"~/ai-daily", schedule:$sched}' \
  > "$TARGET_CONFIG"
echo "config written -> $TARGET_CONFIG"

# When both hosts installed, mirror the same config into Codex.
if [[ $INSTALL_CLAUDE -eq 1 && $INSTALL_CODEX -eq 1 ]]; then
  cp "$TARGET_CONFIG" "$CODEX_DIR/config.json"
fi

# --- 4. LaunchAgent if scheduling enabled ---
if [[ $ENABLE_SCHED -eq 1 ]]; then
  PLIST="$HOME/Library/LaunchAgents/ai.subscribe-ai-daily.plist"
  mkdir -p "$HOME/Library/LaunchAgents"

  # Build ProgramArguments + invocation label per detected host.
  # Prefer Claude Code when both present (canonical path); fall back to Codex.
  PROG_ARGS=""
  HOST_LABEL=""
  if [[ $INSTALL_CLAUDE -eq 1 ]]; then
    HOST_LABEL="claude"
    # Use printf to embed the prompt string safely into the plist <string> entries.
    PROG_ARGS=$(printf '<string>claude</string><string>-p</string><string>invoke the subscribe-ai-daily skill and output the daily briefing</string>')
  else
    HOST_LABEL="codex"
    if [[ ! -x "$CODEX_BIN" ]]; then
      echo "WARN: codex binary not found at $CODEX_BIN — LaunchAgent will fail to run. Add it to PATH or install the ChatGPT.app." >&2
    fi
    PROG_ARGS=$(printf '<string>%s</string><string>exec</string><string>--dangerously-bypass-approvals-and-sandbox</string><string>invoke the subscribe-ai-daily skill and output the daily briefing</string>' "$CODEX_BIN")
  fi

  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>ai.subscribe-ai-daily</string>
  <key>ProgramArguments</key><array>
    $PROG_ARGS
  </array>
  <key>StartCalendarInterval</key><dict>
    <key>Hour</key><integer>$HH</integer>
    <key>Minute</key><integer>$MM</integer>
  </dict>
  <key>StandardOutPath</key><string>$HOME/ai-daily/launched.log</string>
  <key>StandardErrorPath</key><string>$HOME/ai-daily/launched.err</string>
</dict></plist>
EOF
  launchctl load "$PLIST" 2>/dev/null || true
  printf 'LaunchAgent installed -> %s (host=%s, fires daily at %02d:%02d)\n' "$PLIST" "$HOST_LABEL" "$HH" "$MM"
fi

echo "=== done. invoke with: /subscribe-ai-daily ==="
