# 分支任务：team-workflow

- 任务 ID：team-workflow
- 状态：等待主对话审核
- 负责人：coordinator
- 对话标识：01a0fa88-5b2b-7ca1-b51f-76159bc35851
- 分支：task/team-workflow
- 基础提交：f609426
- 开始时间：2026-10-02
- 结束时间：2026-10-02 软件交付待最终复核；远程与上板未完成

## 目标与验收条件

落实两人零基础上板计划、GitHub PR 单入口、按需总控及可复核任务检查。不执行烧录、不合并 main，不改已有 HDL。

## 修改文件

本分支的总控规则、计划、协作文档、任务卡、脚本与回归测试；最终精确清单见 Git diff 和共享登记。

## 验证命令与结果

初始化只读核查：主仓库 main/HEAD=f609426，21 项旧状态不变；Git 无远程，gh 未安装，Git Credential Manager 未列出 GitHub 账号。未运行 HDL 或硬件验证。

- 工具代理提交 c08a3f4，代理原提交的回归 73/73 通过；这不是整合 HEAD 的测试结论。
- 硬件指南代理提交 39833c9、db17c53；仅文档与路径验证，未操作硬件。实际执行输出已改为 evidence/env-bringup/runs。
- 总控已独立跑通索引 8 项、交付检查器 8 项，完成 PowerShell 语法解析、YAML 安全触发/只读权限检查及范围预检。
- 整合复核发现并修复：旧模板带反引号和待创建分支导致启动失败；worker 不应修改 .github；验收报告应绑定 BaseCommit；CI 的远程基线需钉成隔离本地分支。相应新增回归，最终数量与结果以整合 HEAD 的报告为准。
- 最终验收须在源码/说明提交后执行：pwsh -NoProfile -File tools/test-task.ps1 -TaskId team-workflow -BaseBranch main -PolicyRef e4992305dfd3fe4d8382e5edb4e6d90def470512。报告与 stdout/stderr 位于本任务 runs，之后只生成输出和共享登记，不再修改被测源码。
- 报告核验：check-task 同一 TaskId/BaseBranch/PolicyRef，加 -RequireReady -AcceptanceReport <实际报告路径> -Json。未获得匹配报告前不得声称最终验收通过。
- GitHub 官方设备登录等待本人确认后过期退出 1；没有收到凭据，没有创建远程、邀请或 PR，没有运行真实 GitHub Actions。本人就绪后重新认证，不重复发送过期授权码。

## 遗留改动审计

初始 21 项由 17 个已跟踪修改和 4 个未跟踪文件组成。采购相关可从主目录 2026-09-27 日志解释，工作区规范/索引相关可从 2026-09-28 共享记录解释；这些上下文不等于完整历史追溯或本轮接手授权。53 个主库文件哈希、文件集合、main HEAD 与状态在结束时再次核对。原文件不回滚、不迁移、不全量提交。

本分支只将已有、已登记的两个统一索引脚本作为必要运行依赖引入，主库原件不改。D-016..018 沿用已有决策编号和日期，不把历史采购事件写成本次发生。完整采购台账仍在主目录，未擅自并入本次提交。

## 证据路径

- evidence/team-workflow/main-before.json：主仓库文件哈希、状态和初始提交的只读快照。
- evidence/team-workflow/runs：总控独立验收报告、逐命令原始日志及交付检查 fixture；运行报告的 Head 必须与验收版本一致。
- evidence/workflow-tools/runs：整合后脚本回归的 summary.json 与独立临时仓库；不能将代理树原报告冒充整合版。
- 共享根 workspace-records 中本轮 team-workflow、workflow-tools、bringup-kit 批次；最新批次记录最终命令、HEAD、报告和索引结果。

## 阻塞与风险

GitHub 本人登录、队友账号、旧改动最终处置和实物上板均需人参与；不自动承接不明旧改动。

## 待决策事项

仅在用户确认后合并主干、下载镜像或改变接线。

## 建议总文档更新

本次由总控在隔离分支提出更新；正式主仓库仍保留原状态，待 PR 审核。

## 下一分支交接

最终报告核验成功后，用户可先提供断电状态下板卡、摄像头、FPC 两端和供电铭牌照片，再确认连接/扫描。另一条线由本人完成 GitHub 认证并给出队友用户名，建私有仓库和首 PR。main 合并仍必须确认，不因本轮软件检查通过自动操作硬件。
