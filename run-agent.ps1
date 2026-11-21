<#
.SYNOPSIS
  用外部 CLI（Codex / OpenCode）跑一个子任务，统一输出格式。

.DESCRIPTION
  主控（Claude Code 桌面端）通过这个脚本派活给 Codex 或 OpenCode。
  不管哪个后端，结果都统一成三个文件：
    <OutFile>              子 agent 的最终回复
    <OutFile>.log          完整运行日志（stdout + stderr）
    <OutFile>.status.json  机器可读的结果：后端、退出码、耗时、是否超时、STATUS 行

  另外每次运行都会往 <OutFile 所在目录>\dispatch-log.md 追加一行派工记录
  （时间、任务、后端、模型、模式、结果、耗时、备注），用 -Task 和 -Note 填任务名和备注。

  Claude 自己的子 agent 不走这个脚本，直接用 Agent 工具；它的派工记录由主控按同样格式手动追加。

.EXAMPLE
  ./run-agent.ps1 -Backend codex -WorkDir D:\proj -PromptFile .orchestrate\x\task-1-prompt.md -OutFile .orchestrate\x\task-1-out.md -Mode write -Model gpt-5.5 -Task "任务 1 实现：导出 CSV"
#>
param(
  [Parameter(Mandatory)][ValidateSet('codex', 'opencode')][string]$Backend,
  [Parameter(Mandatory)][string]$WorkDir,
  [Parameter(Mandatory)][string]$PromptFile,
  [Parameter(Mandatory)][string]$OutFile,
  [ValidateSet('read', 'write')][string]$Mode = 'read',
  [string]$Model = '',
  [int]$TimeoutMin = 60,
  [string]$Task = '',   # 派工记录里的任务名，例如 "任务 2 审查：登录接口"
  [string]$Note = ''    # 派工记录里的备注，例如 "Go 额度用完，改用免费模型"
)

$ErrorActionPreference = 'Stop'

# ============ 可修改区：每个后端的命令行参数 ============
# CLI 升级后参数变了，只改这里。
# {MODEL} 为空时整段 -m 参数会被去掉。
$Backends = @{
  codex    = @{
    Exe        = 'codex'
    # codex exec：-C 工作目录，-s 沙箱，-o 把最终回复写进文件，'-' 表示 prompt 从 stdin 读
    ReadArgs   = @('exec', '-C', '{WORKDIR}', '-s', 'read-only', '--skip-git-repo-check', '-o', '{OUTFILE}', '-')
    WriteArgs  = @('exec', '-C', '{WORKDIR}', '-s', 'workspace-write', '--skip-git-repo-check', '-o', '{OUTFILE}', '-')
    ModelArgs  = @('-m', '{MODEL}')
    PromptVia  = 'stdin'     # stdin：prompt 从标准输入传入
    WritesOut  = $true       # CLI 自己会写 OutFile
  }
  opencode = @{
    Exe        = 'opencode'
    # opencode run：没有目录参数，脚本会先切到 WorkDir；prompt 作为附件传入，避免命令行长度和引号问题
    # --auto 自动批准未被明确拒绝的权限。旧版 opencode 没有这个参数，报错就把它删掉。
    # 注意：消息必须放在 -f 前面，-f 是数组参数，会把它后面的文字都当成文件名。
    ReadArgs   = @('run', '请读取附件文件，严格按其中的指令执行。不要修改任何文件。', '-f', '{PROMPTFILE}')
    WriteArgs  = @('run', '--auto', '请读取附件文件，严格按其中的指令执行。', '-f', '{PROMPTFILE}')
    ModelArgs  = @('-m', '{MODEL}')  # 格式：provider/model，例如 anthropic/claude-sonnet-5-5
    PromptVia  = 'file'
    WritesOut  = $false      # 最终回复取自 stdout
  }
}
# ======================================================

function Resolve-FullPath([string]$p) {
  if ([IO.Path]::IsPathRooted($p)) { return [IO.Path]::GetFullPath($p) }
  return [IO.Path]::GetFullPath((Join-Path (Get-Location).Path $p))
}

$cfg = $Backends[$Backend]
$WorkDir = Resolve-FullPath $WorkDir
$PromptFile = Resolve-FullPath $PromptFile
$OutFile = Resolve-FullPath $OutFile
$LogFile = "$OutFile.log"
$StatusFile = "$OutFile.status.json"

if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) { throw "WorkDir 不存在：$WorkDir" }
if (-not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) { throw "PromptFile 不存在：$PromptFile" }
if (-not (Get-Command $cfg.Exe -ErrorAction SilentlyContinue)) { throw "找不到命令 '$($cfg.Exe)'。请先安装并确认它在 PATH 里。" }
New-Item -ItemType Directory -Force -Path (Split-Path $OutFile) | Out-Null
foreach ($f in @($OutFile, $LogFile, $StatusFile)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }

$template = if ($Mode -eq 'write') { $cfg.WriteArgs } else { $cfg.ReadArgs }
$argList = @()
if ($Model) {
  # 模型参数插在子命令（第一个参数）之后
  $argList += $template[0]
  $argList += ($cfg.ModelArgs | ForEach-Object { $_ -replace '\{MODEL\}', $Model })
  $argList += $template[1..($template.Count - 1)]
} else {
  $argList = $template
}
$argList = $argList | ForEach-Object {
  $_ -replace '\{WORKDIR\}', $WorkDir -replace '\{OUTFILE\}', $OutFile -replace '\{PROMPTFILE\}', $PromptFile
}

$start = Get-Date
# 在独立的 PowerShell 进程里跑，这样 .cmd / .ps1 形式的 CLI 都能正常调用，也方便超时后终止
$job = Start-Job -ScriptBlock {
  param($exe, [string[]]$a, $dir, $promptFile, $via, $log)
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $OutputEncoding = $utf8
  [Console]::OutputEncoding = $utf8
  Set-Location -LiteralPath $dir
  if ($via -eq 'stdin') {
    Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8 | & $exe @a *>&1 | Out-File -LiteralPath $log -Encoding utf8
  } else {
    & $exe @a *>&1 | Out-File -LiteralPath $log -Encoding utf8
  }
  $LASTEXITCODE
} -ArgumentList $cfg.Exe, $argList, $WorkDir, $PromptFile, $cfg.PromptVia, $LogFile

$finished = Wait-Job $job -Timeout ($TimeoutMin * 60)
$timedOut = -not $finished
$exitCode = $null
if ($timedOut) {
  Stop-Job $job
} else {
  $last = Receive-Job $job -ErrorAction SilentlyContinue | Select-Object -Last 1
  if ($null -ne $last) { $exitCode = [int]"$last" }
}
Remove-Job $job -Force

if (-not $cfg.WritesOut -and (Test-Path -LiteralPath $LogFile)) {
  Copy-Item -LiteralPath $LogFile -Destination $OutFile -Force
}

# 从最终回复里找 "STATUS: XXX" 行（所有提示词模板都要求子 agent 输出这一行）
$statusLine = ''
if (Test-Path -LiteralPath $OutFile) {
  $m = Select-String -LiteralPath $OutFile -Pattern '^\s*\**STATUS\**\s*[:：]\s*\**\s*([A-Z_]+)' | Select-Object -Last 1
  if ($m) { $statusLine = $m.Matches[0].Groups[1].Value }
}
if (-not $statusLine) {
  $statusLine = if ($timedOut) { 'TIMEOUT' } elseif ($exitCode -ne 0) { 'FAILED' } else { 'NO_STATUS' }
}

$result = [ordered]@{
  backend     = $Backend
  mode        = $Mode
  model       = $Model
  workdir     = $WorkDir
  exitCode    = $exitCode
  timedOut    = $timedOut
  durationSec = [int]((Get-Date) - $start).TotalSeconds
  status      = $statusLine
  outFile     = $OutFile
  logFile     = $LogFile
}
$result | ConvertTo-Json | Out-File -LiteralPath $StatusFile -Encoding utf8

# ---- 派工记录：追加到 OutFile 同目录的 dispatch-log.md ----
function Format-Cell([string]$s) { ($s -replace '\|', '/' -replace '\r?\n', ' ').Trim() }
$dispatchLog = Join-Path (Split-Path $OutFile) 'dispatch-log.md'
$taskName = if ($Task) { $Task } else { [IO.Path]::GetFileNameWithoutExtension($OutFile) }
$modelName = if ($Model) { $Model } else { '(CLI 默认)' }
$dur = $result.durationSec
$durText = if ($dur -ge 60) { '{0}m{1:00}s' -f [int][math]::Floor($dur / 60), ($dur % 60) } else { "${dur}s" }
$row = '| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} |' -f (Get-Date -Format 'MM-dd HH:mm'), (Format-Cell $taskName), $Backend, (Format-Cell $modelName), $Mode, $statusLine, $durText, (Format-Cell $Note)
$utf8 = New-Object System.Text.UTF8Encoding $false
if (-not (Test-Path -LiteralPath $dispatchLog)) {
  [IO.File]::WriteAllText($dispatchLog, "| 时间 | 任务 | 后端 | 模型 | 模式 | 结果 | 耗时 | 备注 |`n|---|---|---|---|---|---|---|---|`n", $utf8)
}
[IO.File]::AppendAllText($dispatchLog, "$row`n", $utf8)

$result['dispatchLog'] = $dispatchLog
$result | ConvertTo-Json
