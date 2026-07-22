# subscribe-ai-daily

A Claude Code / Codex skill that produces a daily AI-industry briefing from 10 companies' official blogs/research/news — Anthropic, OpenAI, Google, Meta, DeepSeek, Moonshot, Zhipu, Kimi, Alibaba (Qwen), Bytedance (Seed).

> Note: DeepSeek currently has no public blog/research listing page — it will appear in "今日无更新". Moonshot's blog is hosted on kimi.com, so its entries overlap with the Kimi company.

## What it does

When invoked (manually or on schedule), the skill:
1. Fetches each company's blog/research/news listings over the past `window_hours` (default 24h, configurable)
2. Writes a 2-3 sentence cross-company summary identifying the day's main threads
3. Lists per-company articles with 3-sentence summaries + real article links
4. Routes output to the dialog (interactive) or to `~/ai-daily/YYYY-MM-DD.md` + a macOS notification (headless/scheduled)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/USER/subscribe-ai-daily/main/install.sh | bash
```

Replace `USER` with the repo owner (e.g. your GitHub username or the org that owns the fork).

The installer asks 4 questions:
1. Schedule on/off + daily push time (e.g. `09:00`)
2. Output language (`zh` / `en`)
3. Article categories to include (subset of `blog,research,news`)
4. Companies to include (subset of the 10 ids, or enter for all)

It installs the skill into `~/.claude/skills/subscribe-ai-daily/` (Claude Code) and, if `~/.codex/` exists, also into `~/.codex/skills/subscribe-ai-daily/` (Codex).

## Manual use

In Claude Code or Codex, ask "今天 AI 圈有什么", "AI 日报", "subscribe-ai-daily", or any equivalent phrasing — the skill fires.

## Scheduled use

If you answered `y` to scheduling, the installer writes a macOS LaunchAgent at `~/Library/LaunchAgents/ai.subscribe-ai-daily.plist` that fires daily at your chosen time. The invocation differs by host:

- **Claude Code:** runs `claude -p "<prompt invoking subscribe-ai-daily>"` headlessly
- **Codex:** runs `/Applications/ChatGPT.app/Contents/Resources/codex exec --dangerously-bypass-approvals-and-sandbox` with the same prompt

In headless mode the report is written to `$OUTPUT_DIR/YYYY-MM-DD.md` (default `~/ai-daily/`) and a macOS notification fires via `osascript`.

## Configuration

`~/.claude/skills/subscribe-ai-daily/config.json` (or the Codex equivalent):

| Field | Type | Default | Description |
|---|---|---|---|
| `language` | `"zh"` \| `"en"` | `"zh"` | Output language for the briefing |
| `categories` | array | `["blog","research","news"]` | Which categories to include |
| `companies` | array | all 10 ids | Which companies to include (`anthropic`, `openai`, `google`, `meta`, `deepseek`, `moonshot`, `zhipu`, `kimi`, `alibaba`, `bytedance`) |
| `summary_style` | string | `"paragraph"` | Summary format |
| `window_hours` | number | `24` | Rolling time window for article inclusion |
| `output_dir` | path | `"~/ai-daily"` | Where headless reports are written |
| `schedule` | object | `{"enabled": false, "cron": "0 9 * * *"}` | Cron-style schedule; `enabled: false` disables the LaunchAgent |

## Sources & maintenance

Sources live in `sources.json` and are merged in three layers, highest priority last:

1. **Offline fallback** — the `sources.json` shipped with the skill
2. **Remote default** — this repo's `sources.json`, cached for 24h at `/tmp/subscribe-ai-daily-sources.remote.json`
3. **Local override** — `sources.local.json` in the skill dir (your custom fixes — highest priority)

Each source entry has the shape `{url, method, category, selector}` where:
- `method` is `rss` (RSS/Atom feed), `html` (server-rendered listing, parsed via `selector`), or `fetch` (JS-rendered SPA — the host LLM uses WebFetch on the URL)
- `category` is `blog`, `research`, or `news`
- `selector` (html only) is an anchor selector like `a[href^="/blog/"]:not([href*="blog-category"])`

A site changed? Add or fix an entry in `sources.local.json` for an immediate local fix, or open a PR updating `sources.json` for everyone.

## Tests

```bash
bash tests/merge.test.sh     # unit, no network
bash tests/fetch.test.sh     # live network, may flake
bash tests/sources.test.sh   # all 10 companies, live
```

## License

MIT
