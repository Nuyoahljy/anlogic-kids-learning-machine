# T030 v3 同冻结数据库只读时钟复核准备

状态：准备与本地预检通过，等待独立及主审核；没有运行 TD。

原 D098 v2 于 2026-10-22 15:18:07 自然退出 1，数据库导入成功，但在 report 之前的 llength 唯一性 guard 失败。原日志没有保存集合值，不能确定是哪一项未解析。旧执行器、准备、失败目录及数据库保持不变。

本机官方 SWUG105 2024.11 印刷页 33、38 明确 get_ports/get_clocks 未加 -o 返回 UID；印刷页 78 说明 import db 后首次 STA 使用 update_timing。v3 在新的数据库副本中依次 import_device、import_db、update_timing -mode basic、read_sdc、update_timing -mode basic，先保存完整 clocks.rpt 和 gate.timing，再用 -o 保存两端口、两时钟和所有时钟五组诊断。原 9.660 ns / 13.468 ns 预算与原目标端口不变。该顺序是依据手册形成的候选，Tcl stub 不证明 TD 运行时语义。

执行器在运行前后核对旧完整三个目录集合、45 软件文件及工具和所有准备输入，保留原 v2 失败 lineage。报告时钟表通过唯一 Clock-Id 映射验证两原名称和精确 Decimal 周期；XML 保持 v2 的严格两组、正数一致端点及 nonclocks0 规则；五组可读查询必须精确解析，UID、重复、缺失、矛盾均拒收。手册展示的 ports:/clocks: 打印形式和确切返回名字两种证据可用；空或0返回仅作状态，不当作数量。stdout/stderr 严重告警、旧历史变化、新DB/bit、报告缺失/陈旧均拒收。

9 次真实 tkinter Tcl stub、5 次真实 CLI、19 结构解析、14 模拟 Popen 异常/报告分支和 2 历史目录检查通过。模拟 PID 900002 是测试替身，绝非 TD 进程。负时序的合法报告可使 AnalysisCompleted 成立，但 TimingQualified、ResourceAccepted 和 HardwareValidated 始终 false，留给独立与主审核。

仅未来精确主许可才可执行。许可 Stage=clock_reanalysis_only_approved、Candidate=D0300、Version=3、AnalysisAllowed=true，SynthesisAllowed/RouteAllowed/BitgenAllowed/HardwareAllowed 全 false；绑定 Program、Preparation、IndependentPreparationReview、MainSynthesisApproval、NativeSynthesisResult、PriorClockAnalysis、SoftwareFreeze、Tool 八项精确 Path/SHA256/Bytes，SourceCommit=1f0a6b72fabe3289d3f5d9f80a9f861570c15a7b。一次尝试后目录拒绝复用；失败保留，不自动重试。

## 当前文件身份

- E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-color-integration\fpga\scripts\sc520-card-recognition\prepare-shape-card30-clock-reanalysis-v3.py — 64D0E0CBCFE78F4E652B18565F4BD9C0122177C92A904E90AF1B373C2370DDBA / 10797 B
- E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-color-integration\fpga\scripts\sc520-card-recognition\execute-shape-card30-clock-reanalysis-v3.py — D80580711E4FFF5384D85211729EC9DE9EEF6C5969FFD620C4BA561A36A7E128 / 18661 B
- E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-color-integration\fpga\scripts\sc520-card-recognition\test-shape-card30-clock-reanalysis-v3.py — 68F8117EEB0DE8AD85C2E73417391A6E60705D0D66520EDD400519A4CB433C22 / 15285 B
- E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-color-integration\evidence\sc520-shape-card30\clock-reanalysis-prepared-20261022-1610-v3\preparation.json — 909AA08765E01FADA65B6298D9089272FD36ADA1FED8BDC1BA4A5E612C432AD5 / 78362 B
- E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-color-integration\evidence\sc520-shape-card30\clock-reanalysis-prepared-20261022-1610-v3\analysis.tcl — 7F951194469BEB67D3832C5F7C1D292D4E3421177E46CCCA41FF1469E42B792A / 1160 B
- E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-color-integration\evidence\sc520-shape-card30\clock-reanalysis-prepared-20261022-1610-v3\clocks.sdc — 92319D60209BF25A53B5F0290A91E88310A8657F5363B5AA688A65EA7E3BAD82 / 151 B
- E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-color-integration\evidence\sc520-shape-card30\clock-reanalysis-preflight-20261022-1610-v3\report.json — 3B2AA0FE29F34898A051D7C8BC6B832EFB31F90508737F355FC54448AC960198 / 221947 B
