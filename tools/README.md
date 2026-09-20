# 分支工具

这些脚本用于降低 Git Worktree 和项目记忆维护的操作难度。请在主仓库或对应 Worktree 中运行 PowerShell。

## 创建任务分支

在主仓库 `main` 干净时运行：

```powershell
pwsh -File .\tools\new-task-worktree.ps1 -TaskId env-bringup -Owner main
```

脚本会：

- 检查主仓库干净且位于 `main`。
- 创建 `task/<task-id>` 分支。
- 创建 `E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\<task-id>`。
- 把分支日志改为“进行中”，填写负责人、分支和基础提交。
- 在任务分支中提交这次状态变化。

## 完成任务分支

在任务 Worktree 中填写完日志并改为“等待主对话审核”后运行：

```powershell
pwsh -File .\tools\finish-task.ps1 -TaskId env-bringup
```

脚本会检查：

- 当前不是 `main`。
- 分支日志存在且到达审核状态。
- 没有修改主对话专属文件。
- 改动只位于任务许可目录。

检查通过后提交任务分支，但不会自动推送或合并。

## 主对话合并

回到主仓库 `main`，指定一条可核验的验收证据后运行：

```powershell
pwsh -File .\tools\merge-task.ps1 -TaskId env-bringup -AcceptanceEvidence .\evidence\env-bringup\acceptance.md
```

可选参数：

- `-Tag m1-bringup`：合并成功后创建标签。
- `-RemoveWorktree`：合并成功后删除对应 Worktree，但保留任务分支。

## 查看将要执行的操作

三个脚本都支持：

```powershell
pwsh -File .\tools\new-task-worktree.ps1 -TaskId env-bringup -Owner main -WhatIf
```

`-WhatIf` 只显示操作，不修改文件和 Git 状态。

