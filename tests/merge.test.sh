#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Minimal jq check
command -v jq >/dev/null || { echo "jq required"; exit 1; }

# Source the helper
source lib/merge_sources.sh

# Case 1: offline fallback only (no remote cache, no local override)
rm -f /tmp/subscribe-ai-daily-sources.remote.json /tmp/subscribe-ai-daily-sources.remote.ts
rm -f sources.local.json
MERGED=$(merge_sources)
# Anthropic must survive
echo "$MERGED" | jq -e '.anthropic.company == "Anthropic"' >/dev/null
echo "case1 ok: offline fallback works"

# Case 2: local override replaces a company's sources
cat > sources.local.json <<'EOF'
{"anthropic": {"company": "Anthropic", "sources": [{"url": "https://example.com/x", "method": "rss", "category": "blog"}]}}
EOF
MERGED=$(merge_sources)
# Override wins: only 1 source, with the example URL
test "$(echo "$MERGED" | jq '.anthropic.sources | length')" = "1"
echo "$MERGED" | jq -e '.anthropic.sources[0].url == "https://example.com/x"' >/dev/null
echo "case2 ok: local override wins"

# Case 3: remote cache present and fresh (<24h) takes precedence over offline
mkdir -p /tmp
cat > /tmp/subscribe-ai-daily-sources.remote.json <<'EOF'
{"openai": {"company": "OpenAI-REMOTE", "sources": []}}
EOF
date +%s > /tmp/subscribe-ai-daily-sources.remote.ts
MERGED=$(merge_sources)
echo "$MERGED" | jq -e '.openai.company == "OpenAI-REMOTE"' >/dev/null
echo "case3 ok: fresh remote wins over offline"

# Case 4: remote cache stale (>24h) -> fall back to offline, but local override still wins
STALE=$(($(date +%s) - 100000))
echo "$STALE" > /tmp/subscribe-ai-daily-sources.remote.ts
# remove local override to test remote-vs-offline only
rm -f sources.local.json
MERGED=$(merge_sources)
echo "$MERGED" | jq -e '.openai.company == "OpenAI"' >/dev/null
echo "case4 ok: stale remote falls back to offline"

# Cleanup test artifacts (keep sources.json)
rm -f sources.local.json /tmp/subscribe-ai-daily-sources.remote.json /tmp/subscribe-ai-daily-sources.remote.ts
echo "ALL MERGE TESTS PASS"
