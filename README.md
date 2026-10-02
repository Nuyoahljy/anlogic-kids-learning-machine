# 基于安路 PH1P35 的儿童启蒙识物学习机

本仓库用于管理 2026 年全国大学生嵌入式芯片与系统设计竞赛安路 FPGA 赛道赛题二的规划、实现、验证和提交材料。

项目入口：

- [项目总记忆](PROJECT_MEMORY.md)
- [执行计划](PLAN.md)
- [任务清单](TASKS.md)
- [关键决策](DECISIONS.md)
- [分支协作规则](AGENTS.md)
- [两台电脑的 GitHub 操作](docs/10-github-collaboration.md)
- [首轮上板指南](hardware/first-bringup.md)
- [首轮验收空白记录](hardware/first-bringup-record.md)
- [按需主对话总控](docs/08-ai-workflow.md)
- [本轮实施与真实验证](memory/branches/team-workflow.md)

主项目只保存文本资料、HDL 源码、约束、测试脚本、素材和关键发布物。安路安装包、原始比赛压缩包和大型中间产物继续保存在外部资料目录。

## 快速开始

主对话进入：

```powershell
Set-Location E:\juan\FPGA\anlogic-kids-learning-machine
```

当主仓库干净且位于 `main` 时，创建任务分支和工作目录：

```powershell
pwsh -File .\tools\new-task-worktree.ps1 -TaskId env-bringup
```

任务完成后，在对应任务目录中运行：

```powershell
pwsh -File .\tools\finish-task.ps1 -TaskId env-bringup
```

finish-task 默认只检查，显式提交选项才提交；参数和验收入口见 tools/README.md。总控审核后，仍需用户确认才通过 GitHub PR 合并；不本地 merge 后推 main。

当前 2026-10-02 流程升级在 task/team-workflow，主目录 21 项旧改动原样保留，不能直接在脏 main 执行上述创建/同步。到货是用户报告，板卡扫描、镜像下载与真实画面尚待用户执行。
