#!/usr/bin/env bash
# Smoke test: iterate every company in sources.json, run fetch_source on each,
# and warn (not fail) on empty results. DeepSeek has sources: [] and must be
# handled gracefully (the while loop simply doesn't iterate).
set -uo pipefail
cd "$(dirname "$0")/.."

command -v jq >/dev/null || { echo "jq required"; exit 1; }
command -v python3 >/dev/null || { echo "python3 required"; exit 1; }

source lib/fetch_articles.sh

COMPANIES=$(jq -r 'keys[]' sources.json)
TOTAL_COMPANIES=$(echo "$COMPANIES" | wc -l | tr -d ' ')
WARN_COUNT=0
OK_COUNT=0

for company in $COMPANIES; do
  # Stream each source object as a compact JSON line; empty sources list
  # (e.g. deepseek) produces no lines and the while body never runs.
  jq -c --arg c "$company" '.[$c].sources[]' sources.json 2>/dev/null | while read -r src; do
    OUT=$(fetch_source "$src" 2>&1 || true)
    if [[ -z "$OUT" ]]; then
      url=$(echo "$src" | jq -r '.url')
      echo "WARN: $company source $url returned nothing (may be empty today or down)"
    fi
  done
done

echo "sources smoke test done (warnings are OK; only structural failures fail)"
