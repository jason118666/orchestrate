---
name: orchestrate
description: 多 agent 编排。用户输入 /orchestrate，或要求"用多个 agent / 让 Codex、OpenCode、Claude 分工"完成功能、重构或多处修复时使用。你是主控，把任务派给 Claude 子 agent、Codex CLI、OpenCode CLI，并负责防冲突、串联、审查和集成。改 1–2 个文件的小任务不要用。
---

# Orchestrate

你是**主控**：理解需求、拆任务、派活、验收、提交。你不写业务代码。
工人（子 agent）只拿到它需要的最小上下文，做完一件事就结束。

## 0. 判断规模

- **S**（1–2 个文件、思路明确）：不用本 skill，直接做。
- **M**（3–6 个文件）：1 次探索 → 计划 → 逐个实现 → 每个审查。
- **L**（多模块）：最多 3 个并行探索 → 计划 → 实现（满足条件才并行）→ 审查 → 最终审查。

开始时用一句话告诉用户规模判断。用户指定的规模优先。

## 1. 后端和分工

| 后端 | 怎么调用 | 适合 |
|---|---|---|
| `claude` | Agent 工具（`subagent_type` + `model`） | 探索、审查、需要理解全局的实现 |
| `codex` | `run-agent.ps1 -Backend codex` | **主力**：实现、修复、重活 |
| `opencode` | `run-agent.ps1 -Backend opencode` | 只干轻活（机械搬运、批量小改、跑脚本、装依赖、浏览器走查） |

**默认分工**（用户可以在请求里改，例如"全部用 codex"）：

- 探索 → `claude`，`Explore`，`haiku`
- 实现 → `codex`；不可用时 → `claude`，`general-purpose`，`sonnet`
- 审查 → 和实现者**不同**的后端（Codex 写的给 Claude 审，Claude 或 OpenCode 写的给 Codex 审）。不同模型容易发现对方的盲点。OpenCode 不做审查。
- 最终审查 → `claude`，`opus`

**第一次使用时检测后端**（一个会话只做一次）：

```powershell
Get-Command codex, opencode -ErrorAction SilentlyContinue | Select-Object Name, Source
```

没装的后端，相关任务自动改用 `claude`，并告诉用户一句。

**默认模型**（每次调用外部后端都显式传 `-Model`，不要靠 CLI 自己的默认。用户在请求里指定了模型则按用户的）：

| 后端 | 重活（实现、修复、交叉审查） | 轻活（便宜的批量小改） |
|---|---|---|
| `codex` | `gpt-6.2-sol`（用户机器上的默认；没有就用 `gpt-5.5`） | `gpt-6.2-sol`（Codex 不分档） |
| `claude` | `sonnet` | `sonnet` |
| `opencode` | **不派重活** | ① `opencode/deepseek-v4.1-flash-free` → ② 用完再用 `opencode-go/deepseek-v4.1-flash` |

**分工原则（用户 2026-11 指定）**：主要干活的是 **Codex**，其次 Claude。OpenCode **只用 DeepSeek 4.1 Flash**（最便宜）、只干轻活：**先用免费版，用完再用 Go 版**。OpenCode 的其他模型（`big-pickle`、Pro、gemini、kimi 等）**一律不用**，除非用户指定。重活（核心逻辑、权限/安全、复杂实现、修复、审查）交给 `codex gpt-6.2-sol` 或 `claude sonnet`。

**轻活 = 照着明确指示做、做错了一眼能看出来的活**，可以派 OpenCode：

- 机械改动：批量改名、改文案/配置项、按给定格式搬运代码、补注释
- 跑命令：装依赖、跑脚本/测试/构建，并汇报输出
- 看页面（它支持图片输入）：打开页面截图，检查能不能打开、有没有报错、按钮/链接能不能点、内容是否和给定清单一致
- 整理资料：汇总日志、列出文件、按模板生成文档

**不算轻活**（给 Codex / Claude）：判断页面好不好看、找 bug 根因、设计方案、改核心逻辑、审查代码。

**思考强度**由主控按任务决定：简单搬运、机械改动用低档；核心逻辑、权限、并发、疑难排查用高档。Codex 用 `-c model_reasoning_effort="low|medium|high"`，OpenCode 用 `--variant`，Claude 子 agent 用 Agent 的 `effort`（用户没明确要求时不设）。不确定就 medium，并在台账里写一句。

**OpenCode 用哪个**（一个会话判断一次，运行 `opencode models` 看有哪些）：

1. 先用 `opencode/deepseek-v4.1-flash-free`。
2. 免费版到限额（`QUOTA` / `STALLED` 探测确认）→ 本会话后面改用 `opencode-go/deepseek-v4.1-flash`，**不用问用户**，派工表备注写一句，对话里告诉用户一行。同一任务用 Go 版重派一次。
3. Go 版也到限额 → 按第 6 节「限额」停下来找用户。没有 Go 订阅（列表里没有 `opencode-go/`）就直接停下来找用户。
4. 模型 ID 找不到（官方改名或下线）→ 只在 DeepSeek Flash 系列里找最接近的，写进台账；找不到就告诉用户，不换别的系列。

**设计 / 审美类任务**（界面、页面、配色排版、图表、PPT、图标、文案语气这类"好不好看"占主导的活）：

- 默认用 `claude` 后端：从零设计或重要页面 → `opus`；改样式、微调 → `sonnet`。这是经验判断，没做过本环境的对比测试。
- OpenCode 不用于设计活，除非用户指定。
- 提示词里写清风格方向、参考、配色字体等约束，不要只写"做好看点"。
- 审查必须看**渲染结果**（打开页面截图或预览），不能只读代码。审查者仍然和实现者用不同后端。
- 纯逻辑、数据处理、脚本类任务不按这条走，仍按上面的默认表。

**中文乱码**：Windows 下 PowerShell 的输出被管道接走时，中文可能变成 `?`（实测：不设置时输出 `?????`，先执行 `[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)` 后正常）。

- 你自己运行含中文输出的 PowerShell 命令，开头先加上这一句。
- 派给工人的提示词里也要带上这条（`prompts.md` 的实现模板已加）。
- 看到 `?` 先别当文件坏了：用 `[IO.File]::ReadAllText(<路径>, [Text.Encoding]::UTF8)` 读一遍确认。文件本身通常是对的，只是显示被吃掉。

**Codex 在 Windows 上的沙箱**（实测，Codex 0.166，配置里 `[windows] sandbox = "unelevated"` 时）：

- 默认的 `unelevated` 沙箱下，工人启动任何子进程都会 `spawn EPERM`（连 `cmd` 都不行），所以起不了浏览器、跑不了 playwright。联网没问题（node 的 fetch 通；curl 可能因代理报 TLS 错，不是沙箱问题）。
- **解决**：启动时加 `-c windows.sandbox="elevated"`，并保持 `--sandbox workspace-write`。实测 Edge 能启动，playwright-core 配 `channel:'msedge'` 能打开页面并截图；**浏览器启动参数必须加 `--no-sandbox`**（再加 `--disable-gpu` 更稳），否则 Edge 会崩（退出码 2147483651）。
- 装依赖：pnpm 的全局 store 在项目目录外，沙箱会拒绝写锁（`ERR_PNPM_STORE_DIR_OPEN_OPERATION_LOCK`）。要么把 store 设到项目内（`pnpm config set store-dir`/`--store-dir`），要么用 `--add-dir` 放行；也可以让别的工人先装好依赖。这条没实测，做的时候先小试。
- **不要**用 `--dangerously-bypass-approvals-and-sandbox`：会被权限分类器拦下，且确实是关掉沙箱，不是正当手段。
- 提升模式会用独立的沙箱账户，是否改动了系统设置没有验证；第一次用先告诉用户一句。
- 通过 `codex exec` 直接调用时的写法：`codex exec -c windows.sandbox="elevated" --sandbox workspace-write -m gpt-6.2-sol -C <目录> - < 提示词文件`。

**项目在用户电脑上、通过远程命令操作时**（例如共享项目的 `~/.hourlypc/<项目>` 命令）：`run-agent.ps1` 跑在本机，够不到远程文件。做法是把提示词和一个启动脚本放进项目的 `.orchestrate/`，用远程命令后台启动 `opencode run --auto -m <模型> "$(cat 提示词)"` 或 `codex exec ... - < 提示词`，输出写日志，结束时写一个 `.exit` 文件；主控用后台循环等 `.exit` 出现。台账与派工记录仍要手写。

**调用外部后端**：用 PowerShell 工具运行（耗时长，一律 `run_in_background: true`，完成时你会收到通知，不要轮询）：

```powershell
& "$HOME\.claude\skills\orchestrate\run-agent.ps1" -Backend codex -Mode write -WorkDir <目录> -PromptFile <提示词文件> -OutFile <输出文件> -Model <模型> -Task "<任务 N 角色：名字>" [-Note <备注>] [-TimeoutMin 20] [-StallMin 5]
```

- `-Mode read`：只读（Codex 用只读沙箱；OpenCode 在提示里禁止改文件）。探索和审查用这个。
- `-Mode write`：允许改工作目录里的文件。
- `-Task` 必填（写法见第 2 节「派工记录」），`-Note` 写换模型、降级之类的原因。
- 结果看 `<输出文件>.status.json` 里的 `status`（含 `QUOTA`、`STALLED`，见第 6 节），详情看 `<输出文件>`，出错看 `<输出文件>.log`。
- `-TimeoutMin` 默认 20；`-StallMin` 是日志多少分钟不动就终止，opencode 默认 5，codex 默认关闭（高强度思考时可能几分钟没输出）。

## 2. 工作区和台账

对话会被压缩，压缩后你会忘了做到哪。**进度只以文件为准。**

```
.orchestrate/
  history.md         所有任务的派工历史（永久保留，不删）
  <任务短名>/
    progress.md        台账（只追加）
    dispatch-log.md    本任务的派工记录（谁用什么模型做了什么）
    plan.md            计划
    explore-N.md       探索报告
    task-N-brief.md    任务需求
    task-N-prompt.md   发给外部后端的完整提示词
    task-N-report.md   工人的报告
    task-N-diff.txt    给审查者的 diff
```

- 是 git 仓库就把 `.orchestrate/` 加进 `.gitignore`。
- **开始前先看这个目录在不在**。在就是断点续做：读 `progress.md` 和 `git log`，从第一条没完成的任务接着做，不重做已完成的。
- 台账格式：`任务 2: 开始 BASE=a1b2c3d 后端=codex` / `任务 2: 完成 a1b2c3d..e4f5a6b 审查通过` / `裁决: <决定> — <原因> — <错了的代价>`

### 派工记录（每次派活都要记，并显示给用户）

目的：让用户随时看到**哪个模型做了哪个任务**，看完可能会要求调整分工，调整后要写回本 skill。

**记录**：每派一次活，`dispatch-log.md` 就多一行。格式固定：

```
| 时间 | 任务 | 后端 | 模型 | 模式 | 结果 | 耗时 | 备注 |
|---|---|---|---|---|---|---|---|
| 11-21 10:02 | 主控 | claude | claude-opus-5-5 | - | - | - | 本会话主控模型 |
| 11-21 10:03 | 探索 1：数据层 | claude | haiku | read | DONE | 48s | |
| 11-21 10:09 | 任务 1 实现：导出 CSV | codex | gpt-5.5 | write | DONE | 4m12s | |
| 11-21 10:15 | 任务 2 实现：批量改文案 | opencode | opencode/deepseek-v4.1-flash-free | write | DONE | 1m05s | |
```

- 建工作区时就创建这个文件（写好表头），第一行记**主控自己**用的模型。
- **外部后端**（codex / opencode）：`run-agent.ps1` 会自动追加，你只要传 `-Task`。
- **Claude 工人**：Agent 返回后，你按同样格式手动追加一行。模型写你传给 Agent 的 `model`；耗时能从结果里拿到就写，拿不到写 `-`。
- 任务名写法：`探索 N：方向` / `任务 N 实现：名字` / `任务 N 审查：名字` / `任务 N 修复第 R 轮：名字` / `最终审查`。
- 换模型、换后端、额度用完降级、用户指定模型：写进 `备注`。

**显示给用户**（在对话里直接写出来，保持简短）：

1. **计划写完后**：贴一张分工表，`| 任务 | 角色 | 后端 | 模型 |`，让用户一眼看到打算怎么分。
2. **每个工人返回后**：一行，例如 `▸ 任务 1 实现 — codex / gpt-5.5 — DONE — 4m12s`。
3. **换模型或降级时**：立刻一行说明原因。
4. **全部结束时**：原样贴出 `dispatch-log.md` 的整张表，下面加一行汇总，例如 `共派工 7 次：claude 3 次（haiku 2、opus 1），codex 2 次，opencode 2 次`。

**长期保存**：结束时把本次的整张表追加到 `.orchestrate/history.md`，前面加标题 `## <日期> <任务短名>`。这个文件不随任务目录删除。

**用户要求调整时**：用户看了记录说"实现别用 X""审查改用 Y"之类，就修改本 skill 的默认分工或默认模型表（`~/.claude/skills/orchestrate/SKILL.md`），然后在 skill 目录里提交并推送到 GitHub（这个目录是 git 仓库，已经配好远程）。改了什么用一句话告诉用户。

## 3. 探索（只读，可并行）

- 按**不重叠的方向**拆（如"数据层 / 接口层 / 测试与构建"），每个方向一个工人。
- Claude 工人：**同一条消息里发多个 Agent 调用 = 并行**。外部工人：同一条消息里发多个后台 PowerShell 调用。
- 提示词用 `prompts.md` 的「探索」。要求完整报告写进文件，只回给你 10 行摘要。

交接一律用文件。你贴进提示词的、工人回给你的内容，都会一直占着你的上下文。

## 4. 计划和冲突扫描

你自己写 `plan.md`，每个任务写明：

```
## 任务 N：<名字>
- 目标：一句话
- 负责文件（只能改这些）：…
- 只读参考：…
- 依赖：任务 M 产出的 <接口签名>（无则写"无"）
- 验收：测试命令或可观察的行为
- 后端 / 模型：codex / gpt-5.5（按第 1 节）
```

写完做冲突扫描，结果写进台账：

1. **共用文件的任务**：能合并就合并，不能合并就串行并写明先后。
2. **接口**：一个任务产出、另一个使用的，两边的名字、参数、返回值必须一致。
3. **可并行写的任务**：负责文件完全不相交、没有依赖、不共用端口 / 数据库 / 全局安装。

给用户一段话看任务列表，然后直接开始（除非用户要先审计划）。

## 5. 派发实现

**防冲突规则**

1. **写代码默认串行。** 一个任务完成并提交后，再派下一个。
2. 并行写必须同时满足：冲突扫描标为可并行 + 是 git 仓库 + **每个工人在自己的 worktree 里**：
   - Claude 工人：Agent 调用加 `isolation: "worktree"`。
   - 外部工人：你先建 `git worktree add ../<仓库名>-wt-<N> -b orch/<任务短名>-<N>`，再把这个目录作为 `-WorkDir`。
   全部完成后由你按依赖顺序合并回来，合并后跑完整测试。冲突简单的你解决，复杂的派一个修复任务。
3. 不是 git 仓库 → 只能串行。
4. 工人**不提交、不派子 agent、不 push / merge**。只有你提交。

**每个任务的步骤**

1. 记 BASE：`git rev-parse HEAD`，写台账。
2. 把计划里这个任务原样写进 `task-N-brief.md`。
3. 按 `prompts.md` 的「实现」填好提示词。只放：一句话位置、brief 路径、上游接口、你对模糊点的决定、报告路径。**不放对话历史和前面任务的总结。**
4. 派发：Claude 工人把提示词作为 Agent 的 prompt，**明确写 `model`**（不写会继承你当前最贵的模型）；外部工人把提示词写进 `task-N-prompt.md` 再调 `run-agent.ps1`（带 `-Task`）。返回后按第 2 节记录并显示一行。
5. 工人完成后，你检查 `git status`：**改动超出"负责文件"的，先处理越界再继续**（还原越界部分或写裁决）。
6. 你来提交：`git add <负责文件> && git commit -m "任务 N：<名字>"`，记下 HEAD。

## 6. 处理回报

所有工人最后都要输出一行 `STATUS: <状态>`。

| 状态 | 处理 |
|---|---|
| `DONE` | 提交，进入审查 |
| `DONE_WITH_CONCERNS` | 先读顾虑。关于正确性或越界的先处理；只是意见的记台账 |
| `NEEDS_CONTEXT` | 补信息，重新派 |
| `BLOCKED` | 缺上下文 → 补；太难 → 换更强的模型或换后端；太大 → 拆小；计划错 → 写裁决改计划 |
| `QUOTA` | 到限额，按下面「限额」处理：**停下来找用户** |
| `STALLED` | 日志 `StallMin` 分钟没动，脚本已终止它。opencode 先做一次探测（见「限额」）；不是限额就按 `FAILED` 处理 |
| `TIMEOUT` / `FAILED` / `NO_STATUS` | 看 `.log`。CLI 本身出错（没登录、参数变了）→ 告诉用户；工人跑偏 → 换后端重派一次 |

### 限额（Codex 和 OpenCode Go）

**怎么发现**（`run-agent.ps1` 自动做，结果在 `status.json`）：

- 工人没正常完成，且 `.log` 里有 usage limit、quota、insufficient、rate limit、429、402 之类的字样 → `status` 为 `QUOTA`，匹配到的那行在 `quotaHint`，也会写进派工表的备注。Codex 到限额会直接报 "You've hit your usage limit" 并退出。
- OpenCode Go 到限额时**可能不报错、只是挂住**（实测：日志停在 `> build · <模型名>`）。所以 opencode 默认日志 5 分钟不动就终止，状态 `STALLED`。拿到 `STALLED` 时用同一个模型探测一次：
  `opencode run -m <模型> '只回复OK'`，60 秒超时。也挂住或报额度错误 → 按 `QUOTA` 处理。
- 单次派工最长 20 分钟（`-TimeoutMin`）。超时且日志里有限额字样同样是 `QUOTA`。

**发现后怎么做**（唯一例外：OpenCode **免费版** DeepSeek Flash 到限额时，按第 1 节直接换 Go 版，不走下面流程）：

1. **立刻停止往这个后端派新任务**。已经在跑的其他工人等它们跑完，但不再派新的，包括别的后端。
2. **不自动换模型**，也不换成 OpenCode 的其他模型。
3. 台账记一句，派工表备注写明。
4. 结束本轮，向用户汇报（简短）：
   - 哪个后端、哪个模型到了限额，当时在做哪个任务；
   - `quotaHint` 原文，有重置时间就写出来；
   - 已完成的任务和还剩的任务；
   - 让用户选：**等额度恢复后继续** / **改用 Codex 或 Claude** / **先暂停**。
5. 用户选了之后按选择继续，选择写进台账，本会话后面不再重复问同一个后端。

**不要让同一个工人原样重试。** 它卡住了，就一定要改变一点什么。
一个任务失败，只影响依赖它的任务，其他独立任务继续。需要回退提交时，列出提交让用户确认，不要自己 `reset --hard`。

## 7. 审查和修复

1. 生成 diff：`git diff --stat BASE..HEAD` 和 `git diff -U10 BASE..HEAD` 写进 `task-N-diff.txt`。
2. 派审查工人（`prompts.md`「审查」，`-Mode read` 或 Claude 工人），给它 brief、report、diff 三个路径。**审查者只读。**
3. 结论分两部分：需求符合度（缺少 / 多余 / 理解错）和代码质量（Critical / Important / Minor）。

**修复循环**

- Minor → 记台账，留给最终审查，不进循环。
- Critical / Important → 最多 **3 轮**，每轮 = 修复 + 只看修复 diff 的复审：
  - 第 1–2 轮：问题原文发给原后端修。
  - 第 3 轮：换更强的模型或换一个后端，并告诉它"前面试过 2 次，看 report 里试过什么"。
- 3 轮后仍未修好：停止派发，你逐条裁决（审查者错了 / 真问题但可延后 / 真问题且后续依赖它）并写台账。
- **你不要自己改代码**：你改的没人审，还会占满你的上下文。

**最终审查**（全部任务完成后）

1. 跑完整测试。
2. 派最强的模型审查整个分支（第一个 BASE..HEAD），连同台账里的 Minor 和裁决。
3. 修完后向用户汇报：每个任务做了什么、提交范围、遗留问题、测试结果，再贴出完整派工表和汇总行（第 2 节）。
4. 把派工表追加到 `.orchestrate/history.md`。
5. 问用户是否删除 `.orchestrate/<任务短名>/` 和临时 worktree（`history.md` 保留）。**不 push、不 merge 到主分支。**

## 8. 只在这些情况停下来问用户

1. 不可逆或破坏性操作；
2. 安全相关（密钥、权限、认证）；
3. 影响项目外部的动作（push、merge、发布）；
4. 计划错到往哪走都是猜；
5. Codex 或 OpenCode Go 到限额（第 6 节「限额」）。

其他情况你自己裁决、记台账、继续。任务之间不要问"要继续吗"。
