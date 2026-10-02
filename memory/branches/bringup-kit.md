# 分支任务：bringup-kit

- 任务 ID：`bringup-kit`
- 状态：等待主对话审核
- 负责人：本次用户直接委派的 Codex bringup-kit 执行对话
- 分支：`task/bringup-kit`
- 工作目录：`E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/bringup-kit`
- 基础提交：`c08ffbe`
- 开始时间：2026-10-02T11:30:16+08:00
- 结束时间：2026-10-02T11:42:54+08:00（文档与来源静态验证完成，提交/登记见后续批次）

## 目标与验收条件

只新增首轮上板指南、全空白验收记录和本日志；必要小证据限 `evidence/bringup-kit/`。面向两名零基础用户、两台 Windows、共用一块板；目标交付日 2026-11-04。指南按断电核验、确认后扫描、官方候选临时下载、工作副本重编译、30 分钟稳定与断电恢复组织。

验收本任务的文档完整性、来源定位、路径和安全门禁，不执行硬件操作、编译或仿真，不修改 HDL、tools、docs 或主对话总文档，不推送、不合并。

## 已读文档

- 共享根目录 `AGENTS.md`、`README.md`、`FILE_INDEX.md` 及 `workspace-records/README.md`。
- 最新协调批次 `20261002-112258-team-workflow-init-35851`；历史编译批次 `20260929-111655-lab1-build-audit-b741`。
- 本 Worktree 的 `AGENTS.md`、`PROJECT_MEMORY.md`、`PLAN.md`、`TASKS.md`、`DECISIONS.md`、`docs/03-interface-contracts.md`。
- `docs/06-test-plan.md`、`docs/07-risk-register.md`、`hardware/README.md`、`memory/branches/env-bringup.md`、分支日志模板。
- 用户本轮更严格写集与安全要求优先；未发现本树 hardware、memory、evidence 下更深层 AGENTS。

## 修改文件

- `hardware/first-bringup.md`：新增，断电核对、确认后扫描与临时下载、重编译、30 分钟与断电重载恢复；分层排错及可配置路径/来源哈希。
- `hardware/first-bringup-record.md`：新增，全空白现场验收模板，含授权、输入版本、bit 哈希、失败与稳定性证据。
- `memory/branches/bringup-kit.md`：新增，本任务进度和审核交接。

## 验证命令与结果

| 时间 | 命令或操作 | 实际结果 | 边界 |
|---|---|---|---|
| 2026-10-02 开始核查 | `git rev-parse --show-toplevel`、`git branch --show-current`、`git status --porcelain=v1` | 目录及 `task/bringup-kit` 正确，初始工作树干净，HEAD=`c08ffbe` | 没有认领主库旧改动 |
| 2026-10-02 来源核查 | `Get-ChildItem -Recurse -File -Include *.bit,*.al,*.prj`；`Get-FileHash -Algorithm SHA256 -LiteralPath <实际 bit 绝对路径>` | 官方候选与工作副本都存在 `phy_1`、`best_result` 普通/压缩 bit；同套普通 bit 的两个目录哈希相同，两套间不同 | 仅文件存在性与字节哈希，不等于来源认证或上板成功 |
| 2026-10-02 工程核查 | `Select-String` 读取工作副本 `.al` 的 Family、Device、TOP_MODULE | `PH1` / `PH1P35MDG324` / `design_top_wrapper` | 不是实物器件扫描结果 |
| 2026-10-02 文档检查 | PowerShell 正则提取三个文件的 Markdown 链接，逐项 `Test-Path -LiteralPath` | 初稿 4 个链接、交接日志补链后最终 6 个链接全部存在；19 个资料、报告、工程和 bit 路径全部存在 | 将来执行时的证据目录尚未创建，不作为已存在链接 |
| 2026-10-02 命令检查 | `Parser::ParseInput` 解析指南 PowerShell 块，检查命令白名单后执行该只读代码块 | 解析无错误；只含 Join-Path/Test-Path/Get-Item/Format-List/Get-FileHash；两个 bit 及 .al 的路径、大小、时间、完整 SHA-256 显示正常 | 首次混合对象输出未清晰显示哈希，已改 Format-List 并重新验证 |
| 2026-10-02 模板检查 | PowerShell 遍历验收表的非表头行，检查实际数据列全部等于“待填写”；搜索已勾选项、64 位哈希和实测日期 | 99 行数据全部空白占位，无已填日期、哈希、勾选通过 | 不把静态步骤名称或观察点当实测数据 |
| 2026-10-02 安全与边界检查 | 检查禁止带电 FPC、确认门禁、历史覆盖率边界；检索旧安全设置绕过和运行中插拔指令 | 新指南有明确禁止与单独确认；未复制旧危险操作指令 | 现场菜单、实物接法和供电仍需真人核验 |
| 2026-10-02 缺资料负向检查 | 在内存中将指南只读代码块的 WorkspaceRoot 替换为已确认不存在的随机路径后执行 | 正确抛出“缺少文件”并停止，没有创建目录或空文件 | 不会误把空目录当可用资料 |
| 2026-10-02 旧结束脚本只读检查 | `pwsh -NoProfile -File ./tools/finish-task.ps1 -TaskId bringup-kit -BaseBranch c08ffbe -WhatIf` | 退出码 0；预览只提交 3 个任务文件，没有实际提交或改文件 | 使用用户委派基础提交，避免误计继承的主对话初始化 |
| 2026-10-02 提交前检查 | `git diff --cached --check`、`git diff --cached --name-only`、三文件白名单对比 | 退出码 0；暂存内容只有本日志和两个新增硬件文档 | 只对精确文件路径执行 git add；不推送、不合并 |

验证环境为本机 Windows PowerShell；索引使用 PowerShell 7.6.5。为核对扫描入口，只读使用随附 Python/pypdf 提取本机 `PH1P35烧写程序的使用方法.pdf` 第 2—3 页文本，核实 AL-LINK-FT、刷新、Apply and Close；未据此声称已操作 GUI，也没有把第 1 页驱动替换作为获授权步骤。

本任务只比较相对于 `c08ffbe` 的变更；该基础提交含主对话初始化，不将 `main...HEAD` 中继承的改动归给本任务。最终提交前检查精确三文件白名单，不用全目录 `git add`，不运行编译/仿真。历史 finish-task 会自行提交，因此只允许用 `-BaseBranch c08ffbe -WhatIf` 验证其检查路径，不能让它代替显式三文件提交。

## 证据路径

只读输入在本机 `E:/juan/FPGA/Data/` 与 `E:/juan/FPGA/anlogic_2026/lab1_mipi_hdmi/`。实际 bit 路径、哈希和资料目录写入[指南](../../hardware/first-bringup.md)的本机说明；[空白记录](../../hardware/first-bringup-record.md)供后续真人执行。本任务没有硬件照片、烧录结果、新构建或仿真产物，没有新建 evidence 文件。

官方候选普通 bit SHA-256 为 `F6813EF7C3722D5C9F0E74336E9A27E51E2FDF2EB3F30EB337AA09ADD0AC5604`；工作副本历史普通 bit 为 `AC5741B43B23BCC8A0D1B674829E9E157EA6B2386B784F8C94B876EF14751E0D`。工作副本 `.al` 本次 SHA-256 为 `636ADCB358580FAA499698BDF278EA7C5EBD65FBF30EA6A52C20ACA2E800DF2B`，不是整个输入集合的版本证明。

启动共享记录：`E:/juan/FPGA/workspace-records/20261002-113146-bringup-kit-start-b80f.json`，当时索引生成与 `-Check` 均成功（19 批次、262 路径）。完成批次按实际登记时间新增，记录本次三文件与提交身份并重建索引，不改启动历史。

## 阻塞与风险

- 到货是用户报告；板卡/摄像头实物型号、供电、FPC 方向、附件兼容性和功能仍待核对。
- 历史编译记录只有 95.64% STA coverage，不是全约束或上板验收；不能从当前源码反推历史 bit 的完整来源。
- 旧测试表含运行中插拔 FPC，旧风险文档含改变 Windows 安全设置的指引；本分支不能改 docs，将在新指南明确停止条件并向主对话建议修正。

## 待决策事项

无接口或技术方案变更提案。连接、扫描、临时下载均由用户在执行前确认；Flash 固化和驱动/安全设置变化需要独立确认。

## 建议总文档更新

主对话按用户报告更新到货状态但保留型号与功能待验证；修订过期日期、资料根目录、`docs/06-test-plan.md` 的 IO-01 与 `docs/07-risk-register.md` 的驱动安全门禁、env-bringup 日志的强制复制旧路径描述。已有工作副本不搬迁/复制。不将本任务文档通过等同于 `m1-bringup`。

## 下一分支交接

主对话审核本分支相对 `c08ffbe` 的三个新增文档、来源哈希和安全门禁；不推送、不合并。用户下一步只需提供断电状态的板卡正反面、摄像头正反面、供电铭牌、FPC 两端与接口照片，补齐手册版本/页码；核对完成并确认连接/扫描后，才执行指南第 2 步。

## 2026-10-02 审查修正：运行证据归属

- 2026-10-02T11:56:36+08:00 接受用户定向修正，基础提交 `39833c9`，本 Worktree 起始干净；只改指南/模板的运行目录说明及本日志，不重做其他内容。
- 实际执行者为 `env-bringup`，填写版和运行证据统一放 `evidence/env-bringup/runs/<run-id>/`；指南编制/验证证据仍属 `evidence/bringup-kit/`，不因此扩张本分支写集。本次只改文字，没有创建、迁移或复制证据目录。
- `runs/` 为不随源码提交的本地运行产物，跨电脑交接用 `evidence/env-bringup/` 下非忽略清单记录相对路径、共享链接和哈希，不依赖 Git 自动同步运行文件。
- 已只读核对总控树新 `.gitignore`：`git -C E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/team-workflow check-ignore -v --no-index evidence/env-bringup/runs/path-check/record.md` 退出 0，命中第 46 行 `evidence/*/runs/`；没有创建测试文件。本分支旧 `.gitignore` 不在写集中，不修改；最终规则由主对话集成。
- 此修正按用户明确给出的 `env-bringup` 写集对齐；本次未找到可直接读取的 `env-bringup.json`，不声称已运行新任务权限检查器。主对话集成后仍需用正式任务卡复核。文档状态继续为等待主对话审核，不代表硬件通过。
- 本次实际验证：与 `git show HEAD:<文件>` 逐行比较，指南和模板各仅一行目录/归属说明变化，模板所有待填数据与其他内容原样保留；旧运行路径已无残留，6 个本地 Markdown 链接存在，`git diff --check` 通过，改动严格为原三个文档。未执行编译、硬件操作、推送或合并。
