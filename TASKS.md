# 任务清单

> 只有主对话可以修改本文件。分支在自己的日志中报告进度，主对话审核后回填状态和合并结果。

状态说明：`待启动`、`进行中`、`等待审核`、`已合并`、`阻塞`、`取消`。

| ID | 任务 | 负责人 | 依赖 | 状态 | 验收结果 | 分支日志 |
|---|---|---|---|---|---|---|
| T-001 | 建立仓库、文档记忆和 Git Worktree 流程 | main | 无 | 进行中 | 待提交 | `memory/daily/2026-09-20.md` |
| T-002 | 硬件采购、到货核验和演示台准备 | team | 无 | 待启动 | 待验证 | `memory/branches/hardware-demo.md` |
| T-003 | TD 6.2.1、License、驱动和 lab1 上板 | main | T-002 | 待启动 | 待验证 | `memory/branches/env-bringup.md` |
| T-004 | 自研视频基线、DDR2、HDMI 和接口冻结 | main | T-003 | 待启动 | 待验证 | `memory/branches/video-pipeline.md` |
| T-005 | 字模、语音、卡片和积木素材 | team | 无 | 待启动 | 待验证 | `memory/branches/learning-assets.md` |
| T-006 | 仿真、测试脚本和接口验证 | team | T-004 | 待启动 | 待验证 | `memory/branches/simulation-doc.md` |
| T-007 | 9 类颜色形状积木检测 | main | T-004 | 待启动 | 待验证 | `memory/branches/color-shape-detector.md` |
| T-008 | 5 类卡片模板匹配 | team | T-004、T-005 | 待启动 | 待验证 | `memory/branches/card-detector.md` |
| T-009 | 中文/拼音/英文/检测框 OSD | team | T-004、T-005 | 待启动 | 待验证 | `memory/branches/osd-font.md` |
| T-010 | DFPlayer、模式状态机和计分 | team | T-004、T-005 | 待启动 | 待验证 | `memory/branches/audio-quiz.md` |
| T-011 | 单镜像整机联调和延迟可视化 | main | T-007、T-008、T-009、T-010 | 待启动 | 待验证 | `memory/branches/system-integration.md` |
| T-012 | 稳定性、资源、时序和鲁棒性测试 | team | T-011 | 待启动 | 待验证 | `memory/branches/verification-submission.md` |
| T-013 | 测试报告、视频、PPT、说明和提交包 | team | T-012 | 待启动 | 待验证 | `memory/branches/verification-submission.md` |

## 当前关键任务

1. T-001 完成初始提交。
2. T-002 核对硬件数量、到货时间和演示环境。
3. T-003 在开发板可用后立即完成环境上板和 lab1 验收。

## 审核队列

当前没有等待审核的分支。

