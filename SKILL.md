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

`merge_sources` (from `lib/merge_sources.sh`) takes no args, prints the merged JSON object to stdout. It already handles the three-layer merge: offline `sources.json` → remote default (24h cache at `/tmp/subscribe-ai-daily-sources.remote.json`) → local override `sources.local.json`. Remote fetch failures fall back to offline silently.

### Step 4 — Fetch each enabled company (concurrent)

For each company in the filtered set, for each of its sources, run `fetch_source` from `lib/fetch_articles.sh`. Dispatch companies concurrently (you may use parallel bash `&` + `wait`, or the host's parallel-agent capability).

`fetch_source` takes a single JSON-string argument (one source object `{url, method, category, selector}`) and emits NDJSON lines to stdout, one per article: `{"title","url","pubDate","category","excerpt"}`. Empty `pubDate` is normal for HTML listing pages without per-item dates.

```bash
source lib/fetch_articles.sh
# For each source object $src:
fetch_source "$src"
```

For `method=fetch` sources: `fetch_source` emits a single marker line `{"title":"","url":"<url>","pubDate":"","category":"<category>","method":"fetch"}`. When you see this marker, use your **WebFetch** tool on the url, then from the rendered page extract article entries `(title, url, pubDate, excerpt)` where pubDate is within the last `window_hours`. WebFetch prompt: "Extract every blog/research article on this page as JSON lines: {title, url, pubDate (ISO-8601 if present, else empty), excerpt (1 sentence)}. Only articles posted in the last 24 hours."

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
