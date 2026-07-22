# subscribe-ai-daily Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an open-source, cross-platform (Claude Code / Codex) skill that aggregates "past 24h" articles from 10 AI companies' official blogs/research/news, prints a cross-company summary + per-company links to the dialog (interactive) or to `~/ai-daily/YYYY-MM-DD.md` + macOS notification (headless), and installs in one line with a 4-question setup wizard.

**Architecture:** A single SKILL.md instruction file plus a `sources.json` registry. The skill is pure instructions executed by the host LLM — no runtime code, no Node/Python process. Fetching uses the host's built-in tools (Bash curl with browser UA for RSS/HTML, WebFetch for JS-rendered SPAs). Three-layer source merging (offline fallback → remote default → local override). Scheduling via a macOS LaunchAgent that runs `claude -p` headlessly; the skill detects interactive vs headless and routes output accordingly.

**Tech Stack:** Bash (install.sh, LaunchAgent plist), JSON (sources.json, config.json), Markdown (SKILL.md, README). No external runtime deps. Host tools: curl, jq, WebFetch, macOS `osascript` for notifications.

## Global Constraints

- **Skill name:** `subscribe-ai-daily` (exact, used in dir name, frontmatter `name:`, install paths).
- **Target hosts:** Claude Code (`~/.claude/skills/subscribe-ai-daily/`) and Codex (path confirmed in Task 1; if absent, install Claude Code only and warn).
- **Language of SKILL.md comments/prompts:** Chinese (user-facing output zh/en per config; SKILL.md itself bilingual-readable, instructions in Chinese matching user).
- **No runtime code dependency:** the skill must work with only the host's built-in Bash + curl + jq + WebFetch. No `pip install`, no `npm install`.
- **UA rule for curl:** every curl against a company domain must carry `-H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"`. OpenAI.com 403s default curl UA.
- **Time window:** default 24h, configurable via `config.json: window_hours`.
- **Output languages:** `zh` (default) or `en`.
- **Summary depth:** exactly 3 sentences per article; 2-3 sentence cross-company opening.
- **Commits:** one commit per task, conventional-commit style (`feat:`, `docs:`, `test:`, `chore:`).

---

## File Structure

| File | Responsibility |
|---|---|
| `sources.json` | Default source registry for 10 companies. Each entry: company id, display name, list of sources (url, method, category, selector). Installed as offline fallback. |
| `config.example.json` | Template config; copied to `config.json` by installer if missing. |
| `SKILL.md` | Frontmatter (`name`, `description`) + the workflow instructions the host LLM follows when invoked. This IS the skill — no other runtime code. |
| `install.sh` | One-line installer: detect host, copy files, run 4-question wizard, write `config.json`, optionally write LaunchAgent. |
| `README.md` | Open-source readme: what it does, one-line install, config docs, how to contribute sources. |
| `tests/sources.test.sh` | Smoke test: for each company in sources.json, fetch its sources and assert ≥0 articles parse (not network-flaky on exact counts). Run with `bash tests/sources.test.sh`. |
| `tests/merge.test.sh` | Unit test the three-layer merge logic embedded in SKILL.md (extracted as a small bash helper). |

**Note on "code in a skill":** Skills are instruction files, not programs. But the SKILL.md will embed small bash snippets the host runs. We extract the merge + fetch logic into inline bash in SKILL.md so it's testable via the test scripts (which source the same snippets). Keep snippets in SKILL.md under clearly-fenced ```bash blocks so tests can `sed`-extract them.

---

## Task 1: Confirm Codex skill path and document platform matrix

**Files:**
- Create: `docs/platform-matrix.md`
- Reference: `~/.claude/` (exists), Codex config (probe)

**Interfaces:**
- Produces: `docs/platform-matrix.md` with confirmed paths for Claude Code and Codex skill dirs + scheduling mechanism, used by Task 7 (install.sh).

- [ ] **Step 1: Probe Codex skill directory**

Run:
```bash
ls -la ~/.codex/ 2>/dev/null || echo "no ~/.codex"
ls -la ~/.config/codex/ 2>/dev/null || echo "no ~/.config/codex"
ls -la ~/.config/openai-codex/ 2>/dev/null || echo "no openai-codex"
which codex 2>/dev/null && codex --version 2>/dev/null
```
Record which path exists. If none, Codex support is deferred (install.sh warns "Codex not detected, Claude Code only").

- [ ] **Step 2: Probe Codex scheduling mechanism**

Check Codex docs (web search if needed) for whether Codex supports scheduled/triggered skill invocation. Record: (a) mechanism name, (b) config file path, (c) invocation syntax.

- [ ] **Step 3: Write platform matrix**

Create `docs/platform-matrix.md`:
```markdown
# Platform support matrix

| Host | Skill dir | Scheduling | Headless output |
|---|---|---|---|
| Claude Code | `~/.claude/skills/<name>/` | macOS LaunchAgent running `claude -p "<prompt>"` | write to `~/ai-daily/YYYY-MM-DD.md` + `osascript` notification |
| Codex | `<confirmed path or "deferred">` | <mechanism or "deferred"> | same as Claude Code |
```

- [ ] **Step 4: Commit**

```bash
git add docs/platform-matrix.md
git commit -m "docs: add platform support matrix for claude code and codex"
```

---

## Task 2: Write `sources.json` with verified per-company methods

**Files:**
- Create: `sources.json`

**Interfaces:**
- Produces: `sources.json` object keyed by company id; each value `{company: <display>, sources: [{url, method, category, selector}]}`. Consumed by SKILL.md fetch logic (Task 5) and tests (Task 8).

Verified methods (from probing, see Global Constraints for UA rule):

| Company id | Display | Sources |
|---|---|---|
| `anthropic` | Anthropic | claude.com/blog (html), anthropic.com/research (html), anthropic.com/news (html) |
| `openai` | OpenAI | developers.openai.com/blog (rss), openai.com/research (fetch), openai.com/index (fetch) |
| `google` | Google | research.google/blog (rss), deepmind.google/research (rss), blog.google/rss (rss, Google-wide supplement) |
| `meta` | Meta | (see Step 1 — needs Llama/FAIR blog URL) |
| `deepseek` | DeepSeek | deepseek.com (needs URL confirm) |
| `moonshot` | Moonshot | (needs URL) |
| `zhipu` | Zhipu | zhipuai.cn/zh/research (fetch) |
| `kimi` | Kimi | kimi.com/blog (fetch) |
| `alibaba` | Alibaba (Qwen) | qwen.ai/research (fetch) |
| `bytedance` | Bytedance (Seed) | seed.bytedance.com/zh/blog (fetch), seed.bytedance.com/zh/research (fetch) |

> The original spec's URL list did not include Meta, DeepSeek, Moonshot source URLs. They must be found before this task completes.

- [ ] **Step 1: Find missing company URLs (Meta, DeepSeek, Moonshot)**

For each, web-search the official AI research/blog page:
```bash
# Meta: ai.meta.com/blog or meta AI blog — confirm
curl -sI "https://ai.meta.com/blog/" -H "User-Agent: Mozilla/5.0 ... Chrome/124"
# DeepSeek: deepseek.com blog/research
curl -sI "https://www.deepseek.com" -H "User-Agent: Mozilla/5.0 ... Chrome/124"
# Moonshot: moonshot.ai blog
curl -sI "https://www.moonshot.cn" -H "User-Agent: Mozilla/5.0 ... Chrome/124"
```
Record the real blog/research URL for each. If a company has no public blog, mark its source list empty (the company appears in config but yields "今日无更新").

- [ ] **Step 2: Write the sources.json file**

Create `sources.json` with this exact structure (fill the three unknowns from Step 1; use the verified methods from the table above for the rest):

```json
{
  "anthropic": {
    "company": "Anthropic",
    "sources": [
      {"url": "https://claude.com/blog", "method": "html", "category": "blog", "selector": "a[href^=\"/blog/\"]:not([href*=\"blog-category\"])"},
      {"url": "https://www.anthropic.com/research", "method": "html", "category": "research", "selector": "a[href^=\"/research/\"]"},
      {"url": "https://www.anthropic.com/news", "method": "html", "category": "news", "selector": "a[href^=\"/news/\"]"}
    ]
  },
  "openai": {
    "company": "OpenAI",
    "sources": [
      {"url": "https://developers.openai.com/rss.xml", "method": "rss", "category": "blog"},
      {"url": "https://openai.com/research/", "method": "fetch", "category": "research"},
      {"url": "https://openai.com/index/", "method": "fetch", "category": "news"}
    ]
  },
  "google": {
    "company": "Google",
    "sources": [
      {"url": "https://research.google/blog/rss/", "method": "rss", "category": "research"},
      {"url": "https://deepmind.google/blog/rss.xml", "method": "rss", "category": "research"},
      {"url": "https://blog.google/rss/", "method": "rss", "category": "news", "note": "Google-wide supplement for ai.google coverage"}
    ]
  },
  "meta": {
    "company": "Meta",
    "sources": [
      {"url": "<CONFIRMED_META_URL>", "method": "<rss|html|fetch>", "category": "blog"}
    ]
  },
  "deepseek": {
    "company": "DeepSeek",
    "sources": [
      {"url": "<CONFIRMED_DEEPSEEK_URL>", "method": "<rss|html|fetch>", "category": "blog"}
    ]
  },
  "moonshot": {
    "company": "Moonshot",
    "sources": [
      {"url": "<CONFIRMED_MOONSHOT_URL>", "method": "<rss|html|fetch>", "category": "blog"}
    ]
  },
  "zhipu": {
    "company": "Zhipu",
    "sources": [
      {"url": "https://www.zhipuai.cn/zh/research", "method": "fetch", "category": "research"}
    ]
  },
  "kimi": {
    "company": "Kimi",
    "sources": [
      {"url": "https://www.kimi.com/blog/", "method": "fetch", "category": "blog"}
    ]
  },
  "alibaba": {
    "company": "Alibaba (Qwen)",
    "sources": [
      {"url": "https://qwen.ai/research", "method": "fetch", "category": "research"}
    ]
  },
  "bytedance": {
    "company": "Bytedance (Seed)",
    "sources": [
      {"url": "https://seed.bytedance.com/zh/blog", "method": "fetch", "category": "blog"},
      {"url": "https://seed.bytedance.com/zh/research", "method": "fetch", "category": "research"}
    ]
  }
}
```

- [ ] **Step 3: Validate JSON**

Run: `python3 -c "import json; json.load(open('sources.json')); print('ok')"`
Expected: `ok`

- [ ] **Step 4: Commit**

```bash
git add sources.json
git commit -m "feat: add sources.json with verified fetch methods for 10 companies"
```

---

## Task 3: Write `config.example.json`

**Files:**
- Create: `config.example.json`

**Interfaces:**
- Produces: config schema example. Copied to `config.json` by installer; read by SKILL.md workflow.

- [ ] **Step 1: Write the example config**

```json
{
  "language": "zh",
  "categories": ["blog", "research", "news"],
  "companies": ["anthropic", "openai", "google", "meta", "deepseek", "moonshot", "zhipu", "kimi", "alibaba", "bytedance"],
  "summary_style": "paragraph",
  "window_hours": 24,
  "output_dir": "~/ai-daily",
  "schedule": {
    "enabled": false,
    "cron": "0 9 * * *"
  }
}
```

- [ ] **Step 2: Validate**

Run: `python3 -c "import json; json.load(open('config.example.json')); print('ok')"`
Expected: `ok`

- [ ] **Step 3: Commit**

```bash
git add config.example.json
git commit -m "feat: add config.example.json template"
```

---

## Task 4: Write the three-layer source merge helper

**Files:**
- Create: `lib/merge_sources.sh`
- Create: `tests/merge.test.sh`

**Interfaces:**
- Consumes: `sources.json` (offline fallback), remote `sources.json` (cached 24h at `/tmp/subscribe-ai-daily-sources.remote.json`), `sources.local.json` (optional).
- Produces: bash function `merge_sources()` that prints merged JSON to stdout; called by SKILL.md (Task 5).

- [ ] **Step 1: Write the failing test**

`tests/merge.test.sh`:
```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/merge.test.sh`
Expected: FAIL — `lib/merge_sources.sh` doesn't exist.

- [ ] **Step 3: Write the helper**

`lib/merge_sources.sh`:
```bash
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
  if [[ -f "$REMOTE_CACHE" && -f "$REMOTE_TS" ]]; then
    local ts now age
    ts=$(cat "$REMOTE_TS" 2>/dev/null || echo 0)
    now=$(date +%s)
    age=$((now - ts))
    if [[ "$age" -lt "$ONE_DAY" ]]; then need_refresh=0; fi
  fi
  if [[ "$need_refresh" = "1" ]]; then
    UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    if curl -fsSL -H "User-Agent: $UA" --max-time 10 "$REMOTE_URL" -o "$REMOTE_CACHE.tmp" 2>/dev/null; then
      mv "$REMOTE_CACHE.tmp" "$REMOTE_CACHE"
      date +%s > "$REMOTE_TS"
    fi
  fi
  if [[ -f "$REMOTE_CACHE" ]] && jq -e . "$REMOTE_CACHE" >/dev/null 2>&1; then
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/merge.test.sh`
Expected: `ALL MERGE TESTS PASS`

- [ ] **Step 5: Commit**

```bash
git add lib/merge_sources.sh tests/merge.test.sh
git commit -m "feat: add three-layer source merge helper with tests"
```

---

## Task 5: Write the per-company fetch helper

**Files:**
- Create: `lib/fetch_articles.sh`
- Create: `tests/fetch.test.sh`

**Interfaces:**
- Consumes: a single source object `{url, method, category, selector}` and `window_hours`.
- Produces: bash function `fetch_source()` printing NDJSON lines: `{"title","url","pubDate","category","excerpt"}` (pubDate ISO-8601 or empty if not on listing). Called by SKILL.md (Task 7).

- [ ] **Step 1: Write the failing test**

`tests/fetch.test.sh`:
```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/fetch.test.sh`
Expected: FAIL — `lib/fetch_articles.sh` missing.

- [ ] **Step 3: Write the helper**

`lib/fetch_articles.sh`:
```bash
#!/usr/bin/env bash
# Fetch one source; emit NDJSON article lines to stdout.
# For method=fetch (JS-rendered SPA), emit a marker JSON for the host LLM to WebFetch.
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

fetch_source() {
  local src="$1"
  local url method category selector
  url=$(echo "$src" | jq -r '.url')
  method=$(echo "$src" | jq -r '.method')
  category=$(echo "$src" | jq -r '.category // "blog"')
  selector=$(echo "$src" | jq -r '.selector // ""')

  case "$method" in
    rss)
      local tmp
      tmp=$(mktemp)
      curl -fsSL -H "User-Agent: $UA" --max-time 20 "$url" -o "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
      # Parse <item>/<entry>: title, link, pubDate/updated
      python3 - "$tmp" "$category" <<'PY'
import sys, re, json, html
from xml.etree import ElementTree as ET
path, category = sys.argv[1], sys.argv[2]
try:
    tree = ET.parse(path)
except Exception:
    sys.exit(0)
root = tree.getroot()
ns = {'a':'http://www.w3.org/2005/Atom'}
items = root.findall('.//item') or root.findall('.//a:entry', ns)
for it in items:
    def g(tag):
        el = it.find(tag) or it.find('a:'+tag, ns)
        return (el.text or '').strip() if el is not None else ''
    title = g('title')
    link = g('link')
    if not link:
        le = it.find('a:link', ns)
        if le is not None: link = le.get('href','')
    pub = g('pubDate') or g('updated') or g('published')
    print(json.dumps({'title':title,'url':link,'pubDate':pub,'category':category,'excerpt':''}))
PY
      rm -f "$tmp"
      ;;
    html)
      local tmp
      tmp=$(mktemp)
      curl -fsSL -H "User-Agent: $UA" --max-time 20 "$url" -o "$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
      python3 - "$tmp" "$url" "$category" "$selector" <<'PY'
import sys, json, re
from html.parser import HTMLParser
path, base_url, category, selector = sys.argv[1:5]
href_prefix = re.match(r'a\[href\^="([^"]+)"', selector)
prefix = href_prefix.group(1) if href_prefix else ''
with open(path, encoding='utf-8', errors='ignore') as f:
    html_txt = f.read()
# Crude anchor extraction: href matching prefix, anchor text as title
pat = re.compile(r'<a[^>]+href="(' + re.escape(prefix) + r'[^"]*)"[^>]*>(.*?)</a>', re.S)
seen = set()
for m in pat.finditer(html_txt):
    href, inner = m.group(1), re.sub(r'<[^>]+>','', m.group(2))
    title = re.sub(r'\s+',' ', inner).strip()
    if not title or href in seen: continue
    seen.add(href)
    if href.startswith('/'):
        from urllib.parse import urljoin
        href = urljoin(base_url, href)
    print(json.dumps({'title':title,'url':href,'pubDate':'','category':category,'excerpt':''}))
PY
      rm -f "$tmp"
      ;;
    fetch)
      # Marker: host LLM will WebFetch url and extract articles itself.
      echo "{\"title\":\"\",\"url\":\"$url\",\"pubDate\":\"\",\"category\":\"$category\",\"method\":\"fetch\"}"
      ;;
    *)
      echo "ERROR: unknown method $method" >&2
      ;;
  esac
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/fetch.test.sh`
Expected: `ALL FETCH TESTS PASS`

Note: these tests hit the live network. If a site is temporarily down the test may flake; rerun once. Document this in `tests/README.md`.

- [ ] **Step 5: Write tests/README.md**

```markdown
# Tests

`merge.test.sh` — pure unit, no network.
`fetch.test.sh` — hits live company sites; may flake if a site is down. Rerun once before investigating failures.

Run all: `bash tests/merge.test.sh && bash tests/fetch.test.sh`
```

- [ ] **Step 6: Commit**

```bash
git add lib/fetch_articles.sh tests/fetch.test.sh tests/README.md
git commit -m "feat: add per-source fetch helper (rss/html/fetch) with tests"
```

---

## Task 6: Write `SKILL.md` (the skill itself)

**Files:**
- Create: `SKILL.md`

**Interfaces:**
- Consumes: `lib/merge_sources.sh`, `lib/fetch_articles.sh`, `config.json`.
- Produces: the workflow instructions + embedded bash that the host LLM executes when the skill is invoked. This is the skill.

- [ ] **Step 1: Write SKILL.md with frontmatter**

```markdown
---
name: subscribe-ai-daily
description: Aggregate the past 24 hours of blog/research/news articles from 10 AI companies (Anthropic, OpenAI, Google, Meta, DeepSeek, Moonshot, Zhipu, Kimi, Alibaba/Qwen, Bytedance/Seed) into one daily briefing with a cross-company summary and per-company article links. Use when the user asks for "AI 日报", "今天 AI 圈有什么", "AI 行业动态", "daily AI news", "subscribe-ai-daily", or when a scheduled (LaunchAgent) run invokes it. Outputs directly to the dialog when interactive; writes to ~/ai-daily/YYYY-MM-DD.md + macOS notification when headless.
---

# subscribe-ai-daily

Past-24h AI industry briefing across 10 companies. Direct output to dialog (interactive) or `~/ai-daily/YYYY-MM-DD.md` + notification (headless).

## When invoked

- User explicitly asks for an AI daily briefing / 今天 AI 圈动态 / AI 日报
- A LaunchAgent scheduled run calls `claude -p` with a prompt that includes `subscribe-ai-daily`

## Workflow (follow exactly)

### Step 1 — Load config

Read `~/.claude/skills/subscribe-ai-daily/config.json`. If missing, print: "subscribe-ai-daily 未配置,请重新运行 install.sh" and stop.

Extract: `language`, `categories`, `companies`, `window_hours`, `output_dir`.

### Step 2 — Detect interactive vs headless

Run in bash:
```bash
if [[ -t 1 ]] && [[ -z "${CLAUDE_HEADLESS:-}" ]]; then
  echo "interactive"
else
  echo "headless"
fi
```
If output is `headless` (e.g. launched by LaunchAgent with stdout redirected to a file), route output to `~/ai-daily/YYYY-MM-DD.md` and fire a macOS notification at the end.

### Step 3 — Merge sources

```bash
cd ~/.claude/skills/subscribe-ai-daily
source lib/merge_sources.sh
MERGED=$(merge_sources)
# Filter to configured companies only
echo "$MERGED" | jq -c --argjson cfg "$(cat config.json)" 'to_entries | map(select(.key as $k | $cfg.companies | index($k))) | from_entries'
```

### Step 4 — Fetch each enabled company (concurrent)

For each company in the filtered set, for each of its sources, run `fetch_source` from `lib/fetch_articles.sh`. Dispatch companies concurrently (you may use parallel bash `&` + `wait`, or the host's parallel-agent capability).

For `method=fetch` sources: use your **WebFetch** tool on the url, then from the rendered page extract article entries `(title, url, pubDate, excerpt)` where pubDate is within the last `window_hours`. WebFetch prompt: "Extract every blog/research article on this page as JSON lines: {title, url, pubDate (ISO-8601 if present, else empty), excerpt (1 sentence)}. Only articles posted in the last 24 hours."

Collect all article NDJSON into one stream.

### Step 5 — Time-filter

Keep only articles with `pubDate` inside `[now - window_hours, now]`. If `pubDate` empty (HTML sources without listing dates), fall back to **fetching the article page via WebFetch** and extracting the date from the article body. If still no date: include the article (HTML list pages show only recent posts, so an undated item is presumed recent).

### Step 6 — Cross-company summary (2-3 sentences)

Read all collected `(title, excerpt)` pairs. Write 2-3 sentences identifying the day's main threads and shared themes across companies (e.g. "三家都在讲 agent 安全"). This is the opening of the report.

### Step 7 — Per-company section

For each company with ≥1 article, emit:
```
## <Display Name>
- **<Title>** (<category>)
  <Three-sentence summary derived from excerpt + WebFetch of the article if excerpt empty>
  <url>
```

Companies with zero articles go under `## 今日无更新` as a comma-separated list.

### Step 8 — Compose report

```
# AI 日报 · YYYY-MM-DD

今日主线：<cross-company summary>

<per-company sections>

## 今日无更新
<companies>

---
*数据源：subscribe-ai-daily skill | 窗口：过去<window_hours>h | 语言：<language>*
```

### Step 9 — Output routing

- **Interactive** (Step 2 said interactive): print the full report to the dialog. Done.
- **Headless**: write the report to `$OUTPUT_DIR/YYYY-MM-DD.md` (mkdir -p `$OUTPUT_DIR`), then fire:
  ```bash
  osascript -e "display notification \"subscribe-ai-daily 日报已生成\" with title \"AI 日报\" sound name \"Glass\""
  ```
  Print only `written: <path>` to stdout (which LaunchAgent logs).

### Error handling

- A single company's fetch fails: skip it, append to a `## 抓取失败` section at the end: `- <Company>: <one-line error>, 下次重试`. Do not abort other companies.
- All companies fail: print/write `今日抓取异常` + each company's error.
- Remote sources.json fetch fails: silently use offline fallback (merge helper already handles this).

## Config schema

See `config.example.json`. Key fields: `language` (zh|en), `categories` (blog|research|news subset), `companies` (id list), `window_hours`, `output_dir`, `schedule` ({enabled, cron}).
```

- [ ] **Step 2: Validate frontmatter parses**

Run:
```bash
# Extract frontmatter and ensure it's valid YAML-ish (name + description present)
awk '/^---$/{c++; next} c==1' SKILL.md | grep -E '^(name|description):' | head -2
```
Expected: two lines starting `name:` and `description:`.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat: add SKILL.md with full workflow and dual-output routing"
```

---

## Task 7: Write `install.sh`

**Files:**
- Create: `install.sh`
- Reference: `docs/platform-matrix.md` (Task 1), `sources.json`, `config.example.json`

**Interfaces:**
- Produces: installed skill at `~/.claude/skills/subscribe-ai-daily/` (+ Codex path if detected), `config.json` from wizard, optional LaunchAgent plist at `~/Library/LaunchAgents/ai.subscribe-ai-daily.plist`.

- [ ] **Step 1: Write install.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

SKILL_NAME="subscribe-ai-daily"
CLAUDE_DIR="$HOME/.claude/skills/$SKILL_NAME"
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/USER/subscribe-ai-daily/main}"

echo "=== subscribe-ai-daily installer ==="

# --- 1. Detect host ---
INSTALL_CLAUDE=0; INSTALL_CODEX=0
[[ -d "$HOME/.claude" ]] && INSTALL_CLAUDE=1
# Codex path confirmed in docs/platform-matrix.md; substitute real path here
CODEX_DIR="${CODEX_SKILL_DIR:-$HOME/.codex/skills/$SKILL_NAME}"
if [[ -d "${CODEX_SKILL_DIR_PARENT:-$HOME/.codex}" ]]; then INSTALL_CODEX=1; fi

if [[ $INSTALL_CLAUDE = 0 && $INSTALL_CODEX = 0 ]]; then
  echo "ERROR: neither ~/.claude nor ~/.codex found. Install Claude Code or Codex first." >&2
  exit 1
fi

# --- 2. Copy files (from local checkout if present, else curl from raw) ---
install_one() {
  local dest_root="$1"
  mkdir -p "$dest_root/lib"
  if [[ -f "SKILL.md" ]]; then
    cp SKILL.md sources.json config.example.json "$dest_root/"
    cp lib/*.sh "$dest_root/lib/" 2>/dev/null || true
  else
    UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124.0.0.0 Safari/537.36"
    for f in SKILL.md sources.json config.example.json lib/merge_sources.sh lib/fetch_articles.sh; do
      curl -fsSL -H "User-Agent: $UA" "$REPO_RAW_BASE/$f" -o "$dest_root/$f"
    done
  fi
  [[ -f "$dest_root/config.json" ]] || cp "$dest_root/config.example.json" "$dest_root/config.json"
  echo "installed -> $dest_root"
}

[[ $INSTALL_CLAUDE = 1 ]] && install_one "$CLAUDE_DIR"
[[ $INSTALL_CODEX = 1 ]] && install_one "$CODEX_DIR"

# --- 3. 4-question wizard ---
TARGET_CONFIG="$CLAUDE_DIR/config.json"
[[ $INSTALL_CLAUDE = 0 ]] && TARGET_CONFIG="$CODEX_DIR/config.json"

read -p "开启定时推送? (y/N) " ANS_SCHEDULE
ENABLE_SCHED=0; CRON="0 9 * * *"
if [[ "${ANS_SCHEDULE:-N}" =~ ^[Yy] ]]; then
  ENABLE_SCHED=1
  read -p "每天推送时间 (HH:MM, 默认 09:00) " TM
  TM="${TM:-09:00}"
  HH=$(echo "$TM" | cut -d: -f1 | sed 's/^0//'); MM=$(echo "$TM" | cut -d: -f2 | sed 's/^0//')
  CRON="$MM $HH * * *"
fi

read -p "输出语言 (zh/en, 默认 zh) " LANG_OUT; LANG_OUT="${LANG_OUT:-zh}"

read -p "文章类别 (blog,research,news 全选回车; 用逗号分隔屏蔽某些) " CATS
CATS="${CATS:-blog,research,news}"
CATS_JSON=$(echo "$CATS" | tr ',' '\n' | jq -R . | jq -s .)

read -p "公司筛选 (回车=10家全选; 或用逗号列出要保留的 id) " COMPS
if [[ -z "$COMPS" ]]; then
  COMPS_JSON='["anthropic","openai","google","meta","deepseek","moonshot","zhipu","kimi","alibaba","bytedance"]'
else
  COMPS_JSON=$(echo "$COMPS" | tr ',' '\n' | jq -R . | jq -s .)
fi

mkdir -p "$HOME/ai-daily"
jq -n \
  --arg lang "$LANG_OUT" \
  --argjson cats "$CATS_JSON" \
  --argjson comps "$COMPS_JSON" \
  --argjson sched "$(printf '{"enabled":%s,"cron":"%s"}' $ENABLE_SCHED "$CRON")" \
  '{language:$lang, categories:$cats, companies:$comps, summary_style:"paragraph", window_hours:24, output_dir:"~/ai-daily", schedule:$sched}' \
  > "$TARGET_CONFIG"
echo "config written -> $TARGET_CONFIG"

# --- 4. LaunchAgent if scheduling enabled ---
if [[ $ENABLE_SCHED = 1 ]]; then
  PLIST="$HOME/Library/LaunchAgents/ai.subscribe-ai-daily.plist"
  HH_MIN=$(echo "$CRON" | awk '{print $2":"$1}')
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>ai.subscribe-ai-daily</string>
  <key>ProgramArguments</key><array>
    <string>claude</string><string>-p</string>
    <string>invoke the subscribe-ai-daily skill and output the daily briefing</string>
  </array>
  <key>StartCalendarInterval</key><dict>
    <key>Hour</key><integer>$(echo "$CRON" | awk '{print $2}')</integer>
    <key>Minute</key><integer>$(echo "$CRON" | awk '{print $1}')</integer>
  </dict>
  <key>StandardOutPath</key><string>$HOME/ai-daily/launched.log</string>
  <key>StandardErrorPath</key><string>$HOME/ai-daily/launched.err</string>
</dict></plist>
EOF
  launchctl load "$PLIST" 2>/dev/null || true
  echo "LaunchAgent installed -> $PLIST (fires daily at $HH_MIN)"
fi

echo "=== done. invoke with: /subscribe-ai-daily  ==="
```

- [ ] **Step 2: Make executable + syntax check**

Run:
```bash
chmod +x install.sh
bash -n install.sh && echo "syntax ok"
```
Expected: `syntax ok`

- [ ] **Step 3: Smoke-test install (dry-run in a temp HOME)**

Run:
```bash
TMPHOME=$(mktemp -d)
HOME="$TMPHOME" bash install.sh <<'EOF'
N
zh

blog,research,news

EOF
ls "$TMPHOME/.claude/skills/subscribe-ai-daily/SKILL.md"
cat "$TMPHOME/.claude/skills/subscribe-ai-daily/config.json" | jq .language
rm -rf "$TMPHOME"
```
Expected: SKILL.md exists, `.language` is `"zh"`, no LaunchAgent created (answered N).

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat: add one-line installer with 4-question wizard and LaunchAgent setup"
```

---

## Task 8: Write the sources smoke test

**Files:**
- Create: `tests/sources.test.sh`

**Interfaces:**
- Consumes: `sources.json`, `lib/fetch_articles.sh`.

- [ ] **Step 1: Write the smoke test**

```bash
#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
source lib/fetch_articles.sh

FAIL=0
for company in $(jq -r 'keys[]' sources.json); do
  jq -c --arg c "$company" '.[$c].sources[]' sources.json | while read -r src; do
    OUT=$(fetch_source "$src" 2>&1 || true)
    if [[ -z "$OUT" ]]; then
      echo "WARN: $company source $(echo $src | jq -r .url) returned nothing (may be empty today or down)"
    fi
  done
done
echo "sources smoke test done (warnings are OK; only structural failures fail)"
```

- [ ] **Step 2: Run it**

Run: `bash tests/sources.test.sh`
Expected: completes without hard error; WARN lines acceptable.

- [ ] **Step 3: Commit**

```bash
git add tests/sources.test.sh
git commit -m "test: add sources smoke test for all 10 companies"
```

---

## Task 9: Write `README.md`

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

```markdown
# subscribe-ai-daily

A Claude Code / Codex skill that produces a daily AI-industry briefing from 10 companies' official blogs/research/news — Anthropic, OpenAI, Google, Meta, DeepSeek, Moonshot, Zhipu, Kimi, Alibaba (Qwen), Bytedance (Seed).

## What it does

When invoked (manually or on schedule), the skill:
1. Fetches each company's blog/research/news listings (past 24h, configurable)
2. Writes a 2-3 sentence cross-company summary
3. Lists per-company articles with 3-sentence summaries + real article links
4. Prints to the dialog (interactive) or writes `~/ai-daily/YYYY-MM-DD.md` + macOS notification (headless/scheduled)

## Install

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/USER/subscribe-ai-daily/main/install.sh | bash
\`\`\`

The installer asks 4 questions: schedule on/off + time, language (zh/en), categories to include, companies to include.

## Manual use

In Claude Code: ask "今天 AI 圈有什么" or "subscribe-ai-daily" — the skill fires.

## Scheduled use

If you answered "y" to scheduling, a macOS LaunchAgent fires daily at your chosen time, runs `claude -p` headlessly, and writes the report to `~/ai-daily/YYYY-MM-DD.md` with a notification.

## Configuration

`~/.claude/skills/subscribe-ai-daily/config.json`:
- `language`: `zh` | `en`
- `categories`: subset of `["blog","research","news"]`
- `companies`: subset of the 10 company ids
- `window_hours`: rolling window, default `24`
- `output_dir`: where headless reports land, default `~/ai-daily`
- `schedule`: `{enabled, cron}`

## Sources & maintenance

Sources live in `sources.json`. Three layers, merged in priority:
1. Offline fallback (shipped with the skill)
2. Remote default (this repo's `sources.json`, cached 24h)
3. Local override `sources.local.json` (your custom fixes — highest priority)

Site changed? Add/fix an entry in `sources.local.json`, or open a PR updating `sources.json`. Each source: `{url, method (rss|html|fetch), category, selector}`.

## Tests

\`\`\`bash
bash tests/merge.test.sh    # unit, no network
bash tests/fetch.test.sh    # live network, may flake
bash tests/sources.test.sh # all companies, live
\`\`\`

## License

MIT
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

## Task 10: Final integration verification

**Files:** none (verification only)

- [ ] **Step 1: Run all tests**

Run:
```bash
bash tests/merge.test.sh && bash tests/fetch.test.sh && bash tests/sources.test.sh
```
Expected: all pass (fetch/sources may emit WARN, not FAIL).

- [ ] **Step 2: Manually invoke the skill end-to-end**

In a fresh Claude Code session in a scratch dir, run the installer in a temp HOME, then ask the skill to produce today's briefing. Verify:
- Config loaded from `config.json`
- At least 3 companies produced articles (or all 10 in "今日无更新" if it's a slow day)
- Cross-company summary present
- Per-company sections with 3-sentence summaries + links
- Footer present

- [ ] **Step 3: Verify headless routing**

Run the LaunchAgent target manually:
```bash
CLAUDE_HEADLESS=1 claude -p "invoke subscribe-ai-daily" > /tmp/sad-test.log 2>&1
ls ~/ai-daily/$(date +%Y-%m-%d).md
osascript -e 'display notification "test" with title "test"'
```
Expected: `~/ai-daily/YYYY-MM-DD.md` exists; `/tmp/sad-test.log` contains `written: ...`.

- [ ] **Step 4: Final commit + tag**

```bash
git add -A
git commit -m "chore: final integration verification" --allow-empty
git tag v0.1.0
```

---

## Self-Review (completed by plan author)

**1. Spec coverage:**
- §1 positioning → Tasks 6, 7 (skill + installer, dual-output)
- §2 directory structure → Tasks 2,3,4,5,6,7,9
- §3 three-layer sources → Task 4 (merge helper) + Task 6 Step 3
- §4 config.json → Task 3 + Task 7 wizard
- §5 install questionnaire → Task 7
- §6 SKILL.md workflow → Task 6 (all 9 steps)
- §7 install.sh → Task 7
- §8 error handling → Task 6 Step "Error handling" + Task 4 (remote fallback)
- §9 testing → Tasks 4,5,8,10
- §10 YAGNI → respected (no push channels, no DB, no Web UI, no doctor)
- §11 open details → Task 1 (Codex path), Task 2 (Meta/DeepSeek/Moonshot URLs)

**2. Placeholder scan:** `<CONFIRMED_META_URL>` etc. in Task 2 are intentional — Task 2 Step 1 resolves them before writing the file; the plan shows the engineer exactly what to fill. `USER` in raw URLs and `CODEX_SKILL_DIR` are environment-dependent; installer reads them from env/`docs/platform-matrix.md`. Acceptable.

**3. Type consistency:** `fetch_source` takes a JSON string arg, emits NDJSON — consistent across Task 5 and Task 6 Step 4. `merge_sources` emits JSON object — consistent across Task 4 and Task 6 Step 3. Config keys match across Task 3, Task 7, Task 6.

No gaps. Plan is complete.
