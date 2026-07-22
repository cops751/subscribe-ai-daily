#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v jq >/dev/null || { echo "jq required"; exit 1; }
source lib/fetch_articles.sh

# Case 1: RSS source parses and yields valid NDJSON
OUT=$(fetch_source '{"url":"https://research.google/blog/rss/","method":"rss","category":"research"}')
# At least one line, each valid JSON with title+url
COUNT=$(echo "$OUT" | grep -c . || true)
test "$COUNT" -ge 1
echo "$OUT" | head -1 | jq -e '.title and .url and .category=="research"' >/dev/null
echo "case1 ok: rss parses"

# Case 2: HTML source (claude.com/blog) yields NDJSON with url starting /blog/
OUT=$(fetch_source '{"url":"https://claude.com/blog","method":"html","category":"blog","selector":"a[href^=\"/blog/\"]:not([href*=\"blog-category\"])"}')
test "$(echo "$OUT" | grep -c . || true)" -ge 1
echo "$OUT" | head -1 | jq -e '.url | startswith("/blog/") or startswith("http")' >/dev/null
echo "case2 ok: html parses"

# Case 3: fetch method emits a marker line for the host to use WebFetch
OUT=$(fetch_source '{"url":"https://openai.com/research/","method":"fetch","category":"research"}')
echo "$OUT" | grep -q '"method":"fetch"'
echo "case3 ok: fetch marker emitted"

echo "ALL FETCH TESTS PASS"
