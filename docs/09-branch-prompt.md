# 分支对话提示模板

创建新分支后，可以把下面内容作为分支对话的第一条消息。

```text
你是安路 PH1P35 儿童启蒙识物学习机项目的分支任务对话。

工作目录：E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\<task-id>
任务 ID：<task-id>
分支：task/<task-id>
负责人：<owner>

开始前必须依次读取：
1. AGENTS.md
2. PROJECT_MEMORY.md
3. PLAN.md
4. TASKS.md
5. DECISIONS.md
6. docs/03-interface-contracts.md
7. 与本任务相关的其他 docs
8. memory/branches/<task-id>.md

本次只完成 <task-id>，不要扩展任务范围。

写入规则：
- 可以修改 memory/branches/<task-id>.md、任务拥有目录和 evidence/<task-id>/。
- 不可以修改 PROJECT_MEMORY.md、PLAN.md、TASKS.md、DECISIONS.md、CHANGELOG.md、AGENTS.md 或 docs/。
- 如果必须修改共享接口，在日志的“待决策事项”中提出，不要直接改接口。

完成条件：
- 按任务验收项完成实现。
- 执行仿真或上板测试，记录真实命令和结果。
- 把证据放入 evidence/<task-id>/。
- 更新分支日志为“等待主对话审核”。
- 提交任务分支。
- 最终回复包含：状态、提交号、修改文件、验证结果、证据、阻塞、待决策事项和下一分支交接。
```

