#!/usr/bin/env bash
# subscribe-ai-daily one-line installer.
# Non-interactive: detects Claude Code and/or Codex, copies skill files,
# writes a default config.json (configured=false). First use in the agent
# guides config; if the user enables scheduling there, the skill writes the
# LaunchAgent.
set -euo pipefail

SKILL_NAME="subscribe-ai-daily"
CLAUDE_DIR="$HOME/.claude/skills/$SKILL_NAME"
CODEX_DIR="${CODEX_SKILL_DIR:-$HOME/.codex/skills/$SKILL_NAME}"
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/cops751/subscribe-ai-daily/main}"
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

# --- 3. Write default config (non-interactive) ---
# No wizard in the terminal. The skill guides first-time config on first use.
# Canonical config lives at the Claude path when both hosts are installed.
TARGET_CONFIG="$CLAUDE_DIR/config.json"
if [[ $INSTALL_CLAUDE -eq 0 ]]; then
  TARGET_CONFIG="$CODEX_DIR/config.json"
fi

mkdir -p "$HOME/ai-daily"
# marked configured=false so the skill knows to run the first-use wizard.
jq -n '{language:"zh", categories:["blog","research","news"],
  companies:["anthropic","openai","google","meta","deepseek","moonshot","zhipu","kimi","alibaba","bytedance"],
  summary_style:"paragraph", window_hours:24, output_dir:"~/ai-daily",
  schedule:{enabled:false, cron:"0 9 * * *"}, configured:false}' \
  > "$TARGET_CONFIG"
echo "config written -> $TARGET_CONFIG"

# When both hosts installed, mirror the same config into Codex.
if [[ $INSTALL_CLAUDE -eq 1 && $INSTALL_CODEX -eq 1 ]]; then
  cp "$TARGET_CONFIG" "$CODEX_DIR/config.json"
fi

# --- 4. LaunchAgent only if the user later sets schedule.enabled=true in config ---
# (handled by the skill's first-use wizard, not by this installer.)

echo "=== 安装成功，在你的Claude code或Codex输入/subscribe-ai-daily即可使用 ==="

