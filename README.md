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
终端安装命令：

```bash
curl -fsSL https://raw.githubusercontent.com/cops751/subscribe-ai-daily/main/install.sh | bash
```

或者直接把下面这句话发给你的 agent,让它审阅后安装:

```text
请检查并安装 subscribe-ai-daily skill:https://raw.githubusercontent.com/cops751/subscribe-ai-daily/main/install.sh
先读取 install.sh 和 SKILL.md,告诉我你准备写入的目录和文件;不要使用 sudo,不要覆盖其它 skill。安装完成后告诉我是否需要重启或开启新会话,并给出一个验证问题。
```

The installer is non-interactive: it copies the skill files and writes a default config (10 companies, zh, all categories, no schedule). It installs into `~/.claude/skills/subscribe-ai-daily/` (Claude Code) and, if `~/.codex/` exists, also into `~/.codex/skills/subscribe-ai-daily/` (Codex).

## First use (config wizard)

The first time you invoke the skill in your agent (ask "今天 AI 圈有什么" or "AI 日报"), it detects `configured: false` and walks you through 4 questions:

1. Output language (`zh` / `en`)
2. Article categories (subset of `blog, research, news`)
3. Companies (subset of the 10 ids, or all)
4. Schedule on/off + daily push time (e.g. `09:00`)

Answers are saved to `config.json` and `configured` flips to `true`. If you enable scheduling, the wizard also writes a macOS LaunchAgent at `~/Library/LaunchAgents/ai.subscribe-ai-daily.plist` that fires daily at your chosen time. The invocation differs by host:

- **Claude Code:** runs `claude -p "<prompt invoking subscribe-ai-daily>"` headlessly
- **Codex:** runs `/Applications/ChatGPT.app/Contents/Resources/codex exec --dangerously-bypass-approvals-and-sandbox` with the same prompt

In headless mode the report is written to `$OUTPUT_DIR/YYYY-MM-DD.md` (default `~/ai-daily/`) and a macOS notification fires via `osascript`.

## Updates

The installer does a `git clone --depth 1` into the skill directory, so updates are automatic: each time you invoke the skill, it runs `git pull --ff-only` (once per session) and fast-forwards to the latest `main`. Your `config.json` and `sources.local.json` are gitignored, so pulls never overwrite your config.

If you installed with an older curl-based installer (no `.git` in the skill dir), just re-run the install command once to migrate — your existing config is preserved automatically.

Re-running the install command on a git-cloned install also acts as an update (fast-forward).

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
| `configured` | boolean | `false` | `false` after install triggers the first-use wizard; `true` once the user has answered the 4 questions |

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
