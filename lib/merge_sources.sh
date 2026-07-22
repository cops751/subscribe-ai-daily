#!/usr/bin/env bash
# Three-layer source merge: offline fallback -> remote default (24h cache) -> local override.
# Prints merged JSON object to stdout. Caller filters by config.companies.

REMOTE_CACHE="/tmp/subscribe-ai-daily-sources.remote.json"
REMOTE_TS="/tmp/subscribe-ai-daily-sources.remote.ts"
REMOTE_URL="${SOURCES_REMOTE_URL:-https://raw.githubusercontent.com/USER/subscribe-ai-daily/main/sources.json}"
ONE_DAY=86400

merge_sources() {
  local base="{}"
  # Layer 1: offline fallback (the sources.json shipped beside this file)
  if [[ -f "sources.json" ]]; then
    base=$(jq -S . sources.json)
  fi

  # Layer 2: remote default (refresh if missing or stale >24h)
  local need_refresh=1
  local remote_usable=0
  if [[ -f "$REMOTE_CACHE" && -f "$REMOTE_TS" ]]; then
    local ts now age
    ts=$(cat "$REMOTE_TS" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$((now - ts))
    if [[ "$age" -lt "$ONE_DAY" ]]; then need_refresh=0; remote_usable=1; fi
  fi
  if [[ "$need_refresh" = "1" ]]; then
    UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    if curl -fsSL -H "User-Agent: $UA" --max-time 10 "$REMOTE_URL" -o "$REMOTE_CACHE.tmp" 2>/dev/null; then
      mv "$REMOTE_CACHE.tmp" "$REMOTE_CACHE"
      date +%s > "$REMOTE_TS"
      remote_usable=1
    fi
  fi
  if [[ "$remote_usable" = "1" ]] && [[ -f "$REMOTE_CACHE" ]] && jq -e . "$REMOTE_CACHE" >/dev/null 2>&1; then
    # remote overrides matching companies in base
    base=$(jq -S --argjson base "$base" --argjson remote "$(cat "$REMOTE_CACHE")" \
      '$base * $remote' <<<"{}")
  fi

  # Layer 3: local override (highest priority)
  if [[ -f "sources.local.json" ]] && jq -e . sources.local.json >/dev/null 2>&1; then
    base=$(jq -S --argjson base "$base" --argjson local "$(cat sources.local.json)" \
      '$base * $local' <<<"{}")
  fi

  echo "$base"
}
