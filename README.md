# orchestrate

轻量级多 agent 编排 skill：Claude Code 当主控，把任务分派给 Claude 子 agent、Codex、OpenCode 并行协作，内置防冲突、交叉审查和断点续做。

## 安装

```powershell
git clone git@github.com:jason118666/orchestrate.git "$HOME\.claude\skills\orchestrate"
```

装好后新开一个 Claude Code 会话，输入：

```
/orchestrate 给用户模块加上导出 CSV 的功能
```

## 依赖

- Claude Code（桌面端或 CLI 都可以）。Claude 工人走内置子 agent，不需要 Claude CLI。
- 可选：[Codex CLI](https://github.com/openai/codex)、[OpenCode](https://opencode.ai)。没装的后端会自动改用 Claude。
- Windows PowerShell 5.1 或 PowerShell 7。

## 文件

| 文件 | 作用 |
|---|---|
| `SKILL.md` | 编排流程和规则：规模判断、后端分工、防冲突、审查修复循环、台账 |
| `prompts.md` | 探索、实现、审查三个提示词模板，三个后端通用 |
| `run-agent.ps1` | 调用 Codex / OpenCode 的统一入口，输出统一的 `status.json`。各后端参数集中在脚本顶部的"可修改区" |
| `NOTICE.md` | 参考过的项目和许可证说明 |

## 更新

```powershell
git -C "$HOME\.claude\skills\orchestrate" pull
```

注意：`run-agent.ps1` 必须保持 **UTF-8 带 BOM**，否则 Windows PowerShell 5.1 读不了里面的中文。
