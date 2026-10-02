# 任务、验收与共享索引工具

需要 Git 与 PowerShell 7.5+。所有命令在实际任务或主仓库根执行；不依赖固定盘符。具体角色与权限由 AGENTS 和可信任务卡决定。

## 本轮状态

主目录仍有 21 项旧改动，不能直接跑新建/同步。新实现位于 task/team-workflow，用户批准的 bootstrap 策略是 `e4992305dfd3fe4d8382e5edb4e6d90def470512`，差异基线仍为 main。后续普通任务使用已合入 main 的任务卡，不要照抄 bootstrap 策略绕过审批。

## 1. 创建独立任务

主对话先批准 `memory/tasks/<task-id>.json` 与对应日志。主目录必须干净，且当前分支等于 BaseBranch：

```powershell
pwsh -NoProfile -File tools/new-task-worktree.ps1 -TaskId env-bringup -WhatIf
pwsh -NoProfile -File tools/new-task-worktree.ps1 -TaskId env-bringup
```

Owner 默认来自卡，传入其他值会拒绝。可指定 RepoRoot、BaseBranch、PolicyRef、WorktreeRoot。WhatIf 不创建目录、不改日志、不提交。真正创建时仅在新 Worktree 提交启动日志，主目录 HEAD 不变。脚本产生的新目录与日志仍须共享登记。

## 2. 只读范围检查

进入任务 Worktree：

```powershell
pwsh -NoProfile -File tools/check-task.ps1 -TaskId env-bringup -Json
```

覆盖基线以来的提交、暂存、未暂存、未跟踪、删除及 rename 两端。权限从可信 BaseBranch/PolicyRef 读取，不从自己的卡读取。未知策略、越界、错误分支、主对话专属文件或缺日志都失败。

本轮升级的检查示例：

```powershell
pwsh -NoProfile -File tools/check-task.ps1 -TaskId team-workflow -BaseBranch main -PolicyRef e4992305dfd3fe4d8382e5edb4e6d90def470512 -Json
```

Passed 只描述请求的检查。未指定 AcceptanceReport 时不会宣称运行了测试；Json 中包含当前 HEAD、状态和失败原因。RequireReady 要求日志为“等待主对话审核”。

## 3. 检查与提交分离

先填写日志、完成本机批次登记，再把日志状态改为等待主对话审核：

```powershell
pwsh -NoProfile -File tools/finish-task.ps1 -TaskId env-bringup
pwsh -NoProfile -File tools/finish-task.ps1 -TaskId env-bringup -Commit -WorkspaceRoot '<本机工作区>' -IndexScript '<本机主库>/tools/update-workspace-index.ps1'
```

没有 Commit 只检查。显式提交前还会执行本机共享索引 -Check，只暂存获准任务文件，不运行 git add --all、不推送。WorkspaceRoot/IndexScript 必须指向同机可信入口，不让分支替换它；索引检查不能代替逐文件核对。

## 4. 对已提交源码运行验收

```powershell
pwsh -NoProfile -File tools/test-task.ps1 -TaskId env-bringup
```

可指定 BaseBranch、PolicyRef、OutputRoot。输出默认 `evidence/<task-id>/runs/<唯一运行号>/`；报告路径由命令实际打印，不手填假路径。每个批准命令以 Executable 和 Arguments 数组执行，无 Invoke-Expression。

先提交源码/说明再执行，报告钉住 HEAD 和策略身份，记录实际命令、时间、退出码、stdout/stderr、证据哈希、失败和未验证层级。缺可执行程序、没有 RequiredChecks、非预期退出或必要证据缺失不能认证。runs 已忽略，报告通过 PR 附件/Actions Artifact 分享，不为提交报告制造新的被测 HEAD。

复核报告：

```powershell
pwsh -NoProfile -File tools/check-task.ps1 -TaskId env-bringup -RequireReady -AcceptanceReport '<实际报告路径>' -Json
```

卡中的 ManualAcceptance 由总控和实际操作人逐项检查；脚本不会把供电、画面、时序或 30 分钟硬件测试自动认证。env-bringup 的 delivery-files 只是文件交付门槛。

## 5. PR 合并预检

```powershell
pwsh -NoProfile -File tools/merge-task.ps1 -TaskId env-bringup -PullRequestUrl 'https://github.com/<owner>/<repo>/pull/<number>' -AcceptanceReport '<实际报告路径>'
```

此脚本只做本地预检，输出 `Executed=false`、`MergeAuthorized=false` 及待核实事项。它不会查询 GitHub 状态、不会合并或删除 Worktree，也不再接受旧 Tag/RemoveWorktree 参数。

主对话另行核实 PR 仓库、base/head、远端 HEAD、CI 与保护状态，向用户确认具体 SHA 后，才执行输出的 `gh pr merge ... --merge --match-head-commit ...` 或在 GitHub 合并。不得省略远端复核，不使用 --admin、--auto 或本地 merge 直推 main。CI 诊断优先使用可用的 Code Review 检查工具。

## 6. 回归与 GitHub Actions

```powershell
pwsh -NoProfile -File tools/test-workspace-index.ps1
pwsh -NoProfile -File tools/test-task-workflow.ps1
pwsh -NoProfile -File tools/test-delivery.ps1
pwsh -NoProfile -File tools/check-delivery.ps1
```

前三项使用独立合成目录测试，不碰真实 main。交付检查验证 tracked 文件的路径/JSON/本地链接以及部分敏感内容与运行产物排除，不验证全部敏感历史、网络 URL、许可证、HDL 或硬件。测试生成的 runs 目录同样登记。

Actions 使用 Windows、只读仓库权限、无项目密钥，不用 pull_request_target。任务 PR 对当前 head 做路径检查和批准的脚本检查；main 做回归。首次 team-workflow 仅在差异基线等于 f609426 时允许上述固定 bootstrap 策略，之后全部从正式基线读卡。该例外不能用于其他任务或新的 main。

Actions 运行成功不等于 TD/ModelSim/上板通过；本轮若尚未连接 GitHub，则只有本地实测，不能宣称 CI 已上线。

## 7. 本机登记

```powershell
pwsh -NoProfile -File '<本机主库>/tools/update-workspace-index.ps1' -WorkspaceRoot '<本机工作区>'
pwsh -NoProfile -File '<本机主库>/tools/update-workspace-index.ps1' -WorkspaceRoot '<本机工作区>' -Check
```

先在 workspace-records 新增自己的真实 JSON，索引不能手改。共享索引脚本来自主目录已登记版本，本分支纳入作为运行依赖，主目录原件不改；其测试校验临时目标路径后才清理生成 fixture。
