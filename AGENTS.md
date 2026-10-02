# 项目协作规则

本文件适用于本项目主仓库以及所有 Git Worktree。任何 Codex 对话在修改文件前，都必须先读取并遵守本文件。

## 2026-10-02 总控实施入口

本次由用户授权的总控对话 `01a0fa88-5b2b-7ca1-b51f-76159bc35851` 在 `task/team-workflow` 实施协作升级。主仓库已有未提交改动保持原样；本分支在用户确认 GitHub PR 前不得合入 main。

所有任务先读所在机器工作区根目录的 AGENTS、README、FILE_INDEX 和相关批次。每批文件变化在该机器 workspace-records 新增独立记录，再通过主仓库 tools/update-workspace-index.ps1 刷新并 -Check；记录不是技术验收。

本轮委派的 `workflow-tools` 只允许修改指定的 tools 脚本、memory/tasks 下自己的任务卡、memory/branches/workflow-tools.md 和 evidence/workflow-tools；`bringup-kit` 只允许新增 hardware/first-bringup.md、hardware/first-bringup-record.md、memory/branches/bringup-kit.md 和 evidence/bringup-kit。主对话独占总文档、docs、.github 和其他任务卡。委派不得扩大目录权限或修改其他分支。

本轮允许任务分支提交和推送；主干合并、硬件烧录、接线和安全设置变化仍须用户确认。实际资料在 E:/juan/FPGA/Data，不使用旧文档目录。以下旧流程正由本分支更新；与本节冲突时以本节和用户批准计划为准。

## 1. 项目目标

项目名称：基于安路 PH1P35 的儿童启蒙识物学习机。

比赛：全国大学生嵌入式芯片与系统设计竞赛 2026 FPGA 赛道，安路科技赛题二。

平台：HX1P35A / PH1P35MDG324 + SC500CS。

工具：Anlogic TD 6.2.1。不得使用高于 6.2.1 的版本。

最终交付：一个完全离线、上电自动运行、整合基础要求和扩展功能的 FPGA bit 镜像，以及源码、测试证据、演示材料和提交文档。

## 2. 路径约定

- 主仓库：`E:\juan\FPGA\anlogic-kids-learning-machine`
- 分支工作目录：`E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\<task-id>`
- 原始比赛资料、TD 安装包、ModelSim 和大型压缩包继续保存在 `E:\juan\FPGA\文档`，不得复制进本仓库。
- 文件路径、HDL 标识符和 Git 分支名使用 ASCII；面向人的说明使用中文。

## 3. 每个分支的必读顺序

1. `AGENTS.md`
2. `PROJECT_MEMORY.md`
3. `PLAN.md`
4. `TASKS.md`
5. `DECISIONS.md`
6. `docs/03-interface-contracts.md`
7. 与本任务相关的 `docs/` 文件
8. `memory/branches/<task-id>.md`

如果文档之间冲突，以 `DECISIONS.md` 中编号更大的最新已接受决策和 `PROJECT_MEMORY.md` 为准，并在分支日志中报告冲突。

## 4. 写入权限

只有主对话可以修改以下文件：

- `PROJECT_MEMORY.md`
- `PLAN.md`
- `TASKS.md`
- `DECISIONS.md`
- `CHANGELOG.md`
- `AGENTS.md`
- `docs/`

分支对话只允许修改：

- `memory/branches/<task-id>.md`
- 任务明确拥有的 `fpga/`、`assets/`、`hardware/` 文件
- `evidence/<task-id>/` 下的证据文件

分支不得直接改变共享模块接口。若必须改变接口，应在分支日志的“待决策事项”和“建议总文档更新”中给出提案，由主对话审核后再修改 `docs/03-interface-contracts.md`。

## 5. 分支生命周期

### 开始

- 确认当前目录是自己的 Worktree：`git rev-parse --show-toplevel`。
- 确认当前分支不是 `main`：`git branch --show-current`。
- 将 `memory/branches/<task-id>.md` 的状态改为“进行中”，填写负责人、开始时间和基础提交。
- 记录本次任务的目标、输入文件、依赖和验收条件。

可使用：

```powershell
pwsh -File .\tools\new-task-worktree.ps1 -TaskId <task-id> -Owner <owner>
```

### 工作期间

- 每次有实质进展时更新分支日志，不能只在结束时一次性补写。
- 测试必须记录完整命令、环境、日期和实际结果，不得写未执行的测试。
- 波形、照片、视频和大型日志放入 `evidence/<task-id>/`；如果文件过大，只提交清单、路径和 SHA-256。
- 每个可上板版本单独提交，提交信息格式为 `feat(<task-id>): ...`、`fix(<task-id>): ...` 或 `test(<task-id>): ...`。

### 结束

- 在分支日志中将状态改为“等待主对话审核”。
- 填写修改文件、验证结果、证据、阻塞、风险、待决策事项、建议总文档更新和下一分支交接。
- 确认没有修改主对话专属文件。
- 提交全部任务文件，然后运行：

```powershell
pwsh -File .\tools\finish-task.ps1 -TaskId <task-id>
```

- 最后回复必须包含：状态、提交号、已完成内容、验收证据、未解决事项、建议主对话动作。

## 6. 主对话合并规则

主对话只有在以下条件全部满足后才能合并：

- 分支日志已到“等待主对话审核”。
- 验收证据真实、完整且可复现。
- `git diff main...<branch>` 只包含该任务拥有的文件和分支日志。
- 合并后不覆盖其他分支已接受的功能。

主对话合并命令由 `tools/merge-task.ps1` 执行。合并后主对话负责更新 `PROJECT_MEMORY.md`、`TASKS.md`、`DECISIONS.md`、`CHANGELOG.md` 和稳定文档，并按里程碑打标签。

## 7. 已锁定约束

- 视频基准：`1280x720@60fps`。
- 对象：9 个颜色形状积木和 5 类卡片，共 14 个 `item_id`。
- 对象识别采用中心识别区、颜色阈值、投影统计、形状特征和低分辨率模板匹配。
- 不使用云端、CNN/NPU、额外树莓派、Jetson、第二块 FPGA 或语音识别。
- 语音使用 DFPlayer Mini 和预录音频。
- 最终使用一个上电自动运行的 bit 镜像。
- 每周必须保留一个已验证的可上板版本。

## 8. 输出语言和格式

- 面向人的说明使用中文。
- 日期使用 `YYYY-MM-DD`，时间使用 `Asia/Shanghai`。
- 版本标签：`m1-bringup`、`m2-video`、`m3-detector`、`m4-feature-complete`、`v1.0-release`。
- 结论必须区分“已验证”“推断”“待验证”，不得把推断当作实测结果。
