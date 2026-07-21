# subscribe-ai-daily skill 设计文档

- **日期**：2026-07-21
- **状态**：已通过设计评审，待写实现计划
- **作者**：Vincent（chen）

## 1. 定位

开源、跨 Claude Code / Codex 的 skill。被唤起时从 10 家 AI 巨头的官方源抓取过去 24h 内的新文章，做跨公司归纳 + 按公司分节附上每篇文章实际链接，**直接输出到当前对话框**。

skill 本身不含调度、不含推送、不落地文件。定时由 harness（Claude Code / Codex）自带的 cron 机制唤起——定时仅在 harness 正在运行时生效，未设定时则由用户主动调用触发。

10 家公司：Anthropic、OpenAI、Google（含 DeepMind）、Meta、DeepSeek、Moonshot、智谱（Zhipu）、Kimi、阿里（Qwen）、字节（Seed）。

## 2. 目录结构（仓库）

```
subscribe-ai-daily/
├── SKILL.md                # 主指令（frontmatter + 工作流）
├── README.md               # 开源说明 + 一键安装
├── install.sh              # 一键安装（检测 Claude Code / Codex）
├── sources.json            # 10 家默认源（随仓库一起下，离线 fallback 用）
└── config.example.json     # 配置模板
```

运行期产物（用户机器）：
```
~/.claude/skills/subscribe-ai-daily/
├── SKILL.md
├── sources.json            # 安装时下的本地副本（离线 fallback）
├── sources.local.json      # 用户本地 override（可选）
└── config.json             # 问卷生成
```

Codex 的对应目录同构，`install.sh` 检测后同步安装。

## 3. `sources.json` 三层源机制

运行时按优先级合并（后者覆盖前者同名公司）：

1. **离线 fallback**：安装时随包下的 `sources.json` 副本（始终存在）
2. **远程默认源**：`curl` 仓库最新 `sources.json`（本地缓存 24h，cache busting 避免命中 CDN 旧版）
3. **本地 override**：`sources.local.json` 存在则覆盖同名公司（用户自定义公司 / 对某家的修补）

合并后取交集：只在 `config.json` 的 `companies` 列表里的公司才纳入抓取。

每家公司结构：
```json
{
  "anthropic": {
    "company": "Anthropic",
    "sources": [
      {
        "url": "https://claude.com/blog",
        "method": "rss|html|fetch",
        "category": "blog",
        "selector": "..."
      },
      {
        "url": "https://anthropic.com/research",
        "method": "...",
        "category": "research"
      }
    ]
  }
}
```

- `method=rss`：解析 RSS/Atom feed，结构稳定优先
- `method=html`：抓静态 HTML，按 CSS selector 解析
- `method=fetch`：JS 渲染的 SPA，交由 WebFetch 处理

实现阶段逐家摸清 10 家真实抓取方式，写进默认 `sources.json`。

## 4. `config.json`

安装问卷生成：
```json
{
  "language": "zh",
  "categories": ["blog", "research", "news"],
  "companies": [
    "anthropic", "openai", "google", "meta",
    "deepseek", "moonshot", "zhipu", "kimi",
    "alibaba", "bytedance"
  ],
  "summary_style": "paragraph",
  "window_hours": 24,
  "schedule": {
    "enabled": true,
    "cron": "0 9 * * *"
  }
}
```

字段说明：
- `language`：`zh` 或 `en`，控制总结输出语言
- `categories`：blog / research / news 多选，选中的类别才纳入
- `companies`：公司 ID 多选，默认 10 家全开
- `summary_style`：预留字段，v1 固定 `paragraph`
- `window_hours`：滚动时间窗，默认 24
- `schedule.enabled` / `schedule.cron`：定时配置，cron 格式 `M H * * *`

## 5. 安装问卷（4 题，交互式）

1. **开启定时？** 是 → 问时间（如 `09:00`）→ 生成 cron `0 9 * * *`，写到 harness cron 配置（Claude Code 的 `~/.claude/` 或 Codex 对应位置）
2. **输出语言**：中文 / 英文
3. **文章类别**：blog / research / news 多选（默认全选）
4. **公司筛选**：10 家列表多选保留项（默认全选）

问卷完写入 `config.json`。若开启定时，额外在 harness 配置里写一条唤起 `subscribe-ai-daily` 的 cron 条目。

## 6. SKILL.md 工作流（被唤起时执行）

1. 读 `config.json` → language / categories / companies / window_hours
2. 合并三层 sources（离线 fallback + 远程默认 + 本地 override）
3. 对每家启用公司，**并发**抓取各源列表页
4. 解析出 `(title, url, pubDate, category, excerpt)`
5. 时间过滤：`pubDate` 在 `now - window_hours` 内
6. **跨公司归纳**：读完所有文章标题/摘要后，找出今日主线与共同主题（如「3 家都在讲 agent 安全」），写 2-3 句开头综述
7. **按公司分节**：每家公司下列当日文章，每篇**三句话摘要** + 原文链接
8. 今日无更新的公司单列一节
9. 输出到当前对话框，不落地文件

### 输出形态示例

```
# AI 日报 · 2026-07-21

今日主线：[2-3 句跨公司综述，点出主线和共同主题]

## Anthropic
- **[文章标题]** (blog)
  [三句话摘要]
  https://claude.com/blog/xxx
- **[文章标题]** (research)
  [三句话摘要]
  https://anthropic.com/research/xxx

## OpenAI
...

## 今日无更新
DeepSeek、Moonshot 过去 24h 未发布新文章。

---
*数据源：subscribe-ai-daily skill | 窗口：过去 24h*
```

## 7. 一键安装 `install.sh`

- 检测 `~/.claude/` 存在 → 装 Claude Code 版
- 检测 Codex 配置目录存在 → 同步装一份
- 跑 4 题问卷 → 写 `config.json`
- 若开启定时 → 写 harness cron 条目唤起 `subscribe-ai-daily`
- README 给出一行安装命令：
  ```bash
  curl -fsSL https://raw.githubusercontent.com/<you>/subscribe-ai-daily/main/install.sh | bash
  ```

## 8. 错误处理

- **单家公司抓取失败**：跳过、末尾标注「Anthropic 抓取失败，下次重试」，不阻塞其他公司
- **全部失败**：输出「今日抓取异常」+ 各家错误摘要
- **远程 sources 拉取失败**：静默退回本地副本，正常出报告
- **某家过去 24h 无新文章**：列入「今日无更新」节

## 9. 测试

- 每家公司一个 smoke 测试：抓取 + 解析 + 时间过滤能跑通
- 手动跑一次完整 skill 验证输出格式
- 验证定时唤起：写完 cron 条目后人工触发一次

## 10. YAGNI 砍掉

- 不内置推送（飞书/邮件/Telegram）——只输出到对话框
- 不落地文件、不做缓存 DB
- 不读正文做深度分析——只到三句话摘要级
- 不做 Web UI
- v1 不做 doctor 子命令 / 源状态表（v2 再考虑）

## 11. 待实现阶段确认的细节

- 10 家公司各源的真实 `method`（rss / html / fetch），需逐家访问验证后写进默认 `sources.json`
- GitHub 仓库名与 `install.sh` 的 raw URL 占位符 `<you>` 待定
- Codex 的 skill 目录与 cron 配置路径待实现阶段确认（与 Claude Code 不同）
