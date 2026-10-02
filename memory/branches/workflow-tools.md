# 分支任务：workflow-tools

- 任务 ID：workflow-tools
- 状态：等待主对话审核
- 负责人：workflow-tools
- 分支：task/workflow-tools
- 基础提交：c08ffbe
- 开始时间：2026-10-02
- 结束时间：2026-10-02
- 目标与验收条件：严格任务范围、只读检查、显式提交、真实测试报告；在隔离临时 Git 仓库回归，不改真实 main。
- 已读文档：共享 AGENTS/README/FILE_INDEX 与 20261002-112258-team-workflow-init-35851；本树 AGENTS/PROJECT_MEMORY/PLAN/TASKS/DECISIONS/docs/03-interface-contracts.md。
- 修改文件：指定七个 tools 脚本、自身任务卡、本日志、evidence/workflow-tools。
- 验证命令与结果：开发阶段两次运行 pwsh -NoProfile -File tools/test-task-workflow.ps1，分别 67/67 和 73/73 通过。git diff --check 无空白错误（仅本机 LF/CRLF 提示）。提交后还将运行同一命令，最终提交号与结果由 runs 内新 summary.json 钉住，不再把报告混入源码提交。
- 证据路径：evidence/workflow-tools/runs/regression-20261002-113520-291-0902c80a/summary.json；evidence/workflow-tools/runs/regression-20261002-114434-932-e2d4e8a7/summary.json；提交后最终运行另有独立目录。目录内 command-N.json 包含实际每个子进程的命令、退出码和 stdout/stderr。
- 阻塞与风险：任务分支新建的卡不能自行授权。需主对话审核并提交相同卡，提供明确批准的 PolicyRef SHA 后才能对真实任务执行检查；BaseBranch 仅负责 diff 基线。
- 待决策事项：无新增 HDL 接口决策；merge-task 仅提供本地预检和精确 GitHub 命令，不执行网络操作。
- 建议总文档更新：采用本日志接口规范；旧 finish 自动提交和本地 merge/tag/remove 行为废弃。
- 下一分支交接：主对话读取本日志及最终报告，审核后整合；不能将脚本回归称为 HDL/上板通过。

## 已冻结工具接口

任务卡 JSON：`TaskId`、`Owner`、`Role`（worker/coordinator）、`AllowedPaths`（数组，仅 ASCII 仓库相对 exact 或末尾 `/` 目录前缀）、`RequiredChecks`（检查 ID 数组）、`Checks`（数组）。检查字段为 `Id`、`Executable`、`Arguments`（字符串数组）、可选 `ExpectedExitCode`（默认 0）、可选 `EvidencePaths`（仓库相对文件数组，默认空）。每项检查必定另存并哈希 stdout/stderr；负向测试的匹配非零退出码标为 expected_failure，不标普通 pass。

所有命令使用 PowerShell 7.5+，支持 `-RepoRoot`（默认脚本父目录）、`-TaskId`、`-BaseBranch`（默认 main，必须为本地分支，diff 基线）、`-PolicyRef`（默认 BaseBranch；显式值必须为主对话明确批准的完整 40/64 位提交 SHA，或等于 BaseBranch）。权限与 diff 基线分离；策略读取失败绝不回退到工作树卡，拒绝 HEAD 和当前任务分支自授权。自身卡不可在任务分支自扩权；改权限须主对话先批准新的 PolicyRef。显式 PolicyRef 的批准责任在主对话，工具不会把任意 SHA 称为已获人批准。

- new-task-worktree：另有 `-Owner`（默认卡 Owner）、`-WorktreeRoot`（默认从 Git common dir 的主检出推导）、`-WhatIf`。要求调用检出位于 BaseBranch 且干净，卡与日志已提交；只在新树提交启动日志。
- check-task：`-Json`、`-RequireReady`、`-AcceptanceReport`（可选）。只读，失败退出非零，检查提交差异、索引、工作区、未跟踪文件、rename 两端。
- finish-task：默认只读；`-Commit` 才精确 add/commit。提交必须提供 `-WorkspaceRoot` 与 `-IndexScript`（主库索引脚本绝对路径）并通过其 `-Check`；可另传 `-CommitMessage`，不推送。
- test-task：`-OutputRoot` 仅允许 evidence/本任务/runs 或其子目录；默认该目录。逐命令执行，不使用 Invoke-Expression。实际源码及跟踪文件必须干净；既有未跟踪 runs 输出不冒充源码变更。每次新建 run 目录，输出 report.json、日志、复制的指定证据与 SHA256。所有源码和文档先提交，再测试；报告不再混入源码提交，主对话负责统一 ignore 规则。
- merge-task：`-PullRequestUrl`、`-AcceptanceReport`；仅本地只读预检并输出固定 HEAD 的 gh pr merge --merge --match-head-commit 命令；返回 LocalPreflightOnly，PR/CI/远程状态仍待独立核验。不支持旧 Tag/RemoveWorktree，不执行合并。

## 进展

2026-10-02：已发现旧 new-task-worktree 提交调用仍固定 RepoRoot；旧 finish 自动 git add --all；旧 merge 本地合并、打标签与删除树。将分别修复/移除。尝试向祖先主对话发送接口消息被工具禁止，接口及时落在本日志供主对话读取。

2026-10-02：七个脚本首版完成，按补充约定分离 PolicyRef 和 BaseBranch。已启动临时 Git 仓库回归，保留每次调用的真实 stdout/stderr/退出码；尚未声明最终通过。merge 只读降级明确不验证远程 PR/CI、不执行 gh。

2026-10-02：73 项开发回归全部通过，覆盖子树启动提交、脏基线/错误分支、只读 WhatIf/check/finish、提交/暂存/未暂存/未跟踪/删除/rename、主对话文件保护、自扩权、缺卡/日志/工具/证据、退出 1 与预期失败区分、证据 hash/HEAD 不匹配、测试修改源码、索引失败阻止提交、已干净无需新提交、合并命令仅生成及仓库不匹配拒绝。增加回归报告的源码 HEAD、干净状态和七脚本哈希以便最终提交后复测。

## 验收边界与交接

- PolicyRef 必须由主对话或可信 CI 指定；调用方显式选择一个 SHA 本身不是人工批准证据。卡由策略来源读取，任务本地卡必须与其一致；任何更新必须先获得主对话批准。
- 报告校验是 HEAD、命令、退出码和文件哈希的一致性检查，不是防恶意伪造的数字签名；主对话仍需独立复跑，不把 stdout 的 PASS 字样当验收依据。
- 73 项脚本回归不覆盖 TD、ModelSim、硬件或 GitHub 网络状态。merge-task 永不执行；输出命令前本地检查只包含任务状态、权限、真实报告和 origin/PR URL 仓库一致性。必须另查真实 PR base/head、SHA、CI、草稿/开放状态、用户确认。
- 原 tools/README.md 与 docs 由主对话更新；旧 AcceptanceEvidence、Tag、RemoveWorktree 参数已移除。finish-task 不再自动提交；Commit 要求主检出内索引脚本真实存在并通过 -Check。
- runs 只保存本机证据及临时仓库，不删除、不自动提交、不推送。主对话新增的 evidence/*/runs/ 忽略规则应随整合应用；报告通过 PR 附件或私有 Release 交接。
- 不合并 main、不改主库的 21 项旧状态，不运行 TD/ModelSim、不安装工具或联网。
