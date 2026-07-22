# Platform support matrix

Confirmed paths and invocation patterns for the `subscribe-ai-daily` skill on its two target hosts. Used by `install.sh` (Task 7) to decide where to copy skill files and which headless command to wire into the macOS LaunchAgent.

| Host | Skill dir | Headless invocation | Scheduling | Headless output |
|---|---|---|---|---|
| Claude Code | `~/.claude/skills/<name>/` | `claude -p "<prompt>"` (built-in `--print` mode) | macOS LaunchAgent running `claude -p` on a `StartCalendarInterval` | write report to `~/ai-daily/YYYY-MM-DD.md` + `osascript -e 'display notification ...'` |
| Codex | `~/.codex/skills/<name>/` | `codex exec "<prompt>"` (non-interactive subcommand; binary at `/Applications/ChatGPT.app/Contents/Resources/codex`, `codex-cli 0.145.0-alpha.27`) | No Codex-native scheduler. Use macOS LaunchAgent running `codex exec` on a `StartCalendarInterval` (same plist pattern as Claude Code, swapping the `ProgramArguments` entry). | same as Claude Code |

## Verification notes

### Claude Code
- `~/.claude/` exists on this machine; `~/.claude/skills/<name>/` is the documented skill directory convention.
- `claude -p "<prompt>"` is the documented headless / `--print` invocation; stdout is the model's reply.
- macOS LaunchAgent plist at `~/Library/LaunchAgents/ai.subscribe-ai-daily.plist` with `ProgramArguments = [claude, -p, <prompt>]` and a `StartCalendarInterval` fires the skill on schedule. `launchctl load` registers it.

### Codex
- `~/.codex/` exists on this machine; `~/.codex/skills/` already contains 25+ installed skills (e.g. `nature-reader`, `baoyu-diagram`, `skill-creator`), confirming the `~/.codex/skills/<name>/` convention is real and in active use.
- `~/.codex/AGENTS.md` is Codex's equivalent of `~/.claude/CLAUDE.md` (global instructions auto-loaded into every session).
- The codex binary lives at `/Applications/ChatGPT.app/Contents/Resources/codex` (Codex is bundled inside the ChatGPT macOS app, not a standalone install). `codex --version` reports `codex-cli 0.145.0-alpha.27`. It is not on `PATH` by default.
- `codex exec --help` documents the non-interactive subcommand: it accepts a prompt argument, reads stdin if no prompt is given, and supports `-c key=value` config overrides, `-m model`, `-s sandbox`, and `--dangerously-bypass-approvals-and-sandbox` for fully unattended runs.
- **Scheduling verdict:** Codex has no built-in scheduler or cron/trigger mechanism for skills. The same macOS LaunchAgent pattern used for Claude Code applies, with two adjustments:
  1. `ProgramArguments` becomes `[/Applications/ChatGPT.app/Contents/Resources/codex, exec, "<prompt>"]` (use the absolute path since `codex` is not on `PATH`; alternatively add `/Applications/ChatGPT.app/Contents/Resources` to the LaunchAgent's `PATH`).
  2. Pass `--dangerously-bypass-approvals-and-sandbox` (or `-s danger-full-access`) so the headless run does not stall on an approval prompt that no human will answer.
- `install.sh` should detect Codex by checking `[[ -d "$HOME/.codex/skills" ]]` and install into `~/.codex/skills/subscribe-ai-daily/`. If `~/.codex` exists but `codex` is not on `PATH`, warn the user that scheduled runs require the absolute path to the codex binary (or adding it to `PATH`).

## install.sh decision table

| Detected state | Action |
|---|---|
| `~/.claude/` present | Install to `~/.claude/skills/subscribe-ai-daily/`. LaunchAgent uses `claude -p`. |
| `~/.codex/skills/` present | Install to `~/.codex/skills/subscribe-ai-daily/`. LaunchAgent uses `/Applications/ChatGPT.app/Contents/Resources/codex exec --dangerously-bypass-approvals-and-sandbox`. Warn if codex binary not at that path. |
| Both present | Install to both. Use the Claude Code path for the wizard's `config.json` (canonical); Codex install copies the same `config.json`. |
| Neither present | Refuse with: "Install Claude Code or Codex first." |
| `~/.codex/` present but no `skills/` subdir | Treat as Codex-not-detected; warn "Codex detected but skill directory missing — install Codex CLI v0.145+ or create `~/.codex/skills/`." |
