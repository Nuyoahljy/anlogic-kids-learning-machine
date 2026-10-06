# 检测适配与学习事件独立仿真记录

- 任务：`sc520-learning-ui-audio`，子任务负责人 `event_verification`。
- 日期：2026-10-04，Asia/Shanghai。
- 状态：模块软件仿真通过，等待父任务集成审核；未上板、未提交或推送。
- 工作目录：`E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-fixed-roi`。
- 分支及基础提交：`task/sc520-fixed-roi`，`f609426044982c986b54e999866be9f4c1af2682`。
- 本代理写入范围：`tb_events.sv`、`events-simulate.ps1`、`events-test.do`、本报告及 `events-runs/`。未改动 RTL、父任务日志、共享契约或原候选。

已读根目录 AGENTS/README/FILE_INDEX、最新启动与对话分工登记、仓库 AGENTS/PROJECT_MEMORY/PLAN/TASKS/DECISIONS、接口契约及本任务日志。旧总文档中的硬件与工具状态没有被本报告扩展认定。

## 实际命令和结果

在上述工作目录执行：

```powershell
pwsh -NoProfile -File fpga/scripts/sc520-learning-ui-audio/events-simulate.ps1
pwsh -NoProfile -File fpga/scripts/sc520-learning-ui-audio/events-simulate.ps1 -Negative
```

脚本调用 `D:/modeltech64_10.7/win64/vsim.exe -c`，完整展开后的 `-l`、`-do`、工作目录和源前后 SHA256 见每次运行的 `run-manifest.json`。ModelSim SE-64 10.7 编译与运行均报告工具 Errors: 0, Warnings: 0；负向的功能检查错误在本测试的 errors 中体现，并正确传播为进程退出 1。

| 运行目录（相对本报告） | 检查结果 | 进程退出 |
|---|---|---:|
| `events-runs/normal-20261004-115506-30800-662e20/` | done=1，errors=0，checks=13081 | 0 |
| `events-runs/negative-20261004-115545-31228-961722/` | done=1，errors=1，checks=13082；仅预设错误期望触发 | 1 |

两次均为 adapter_cases=604、event_cases=50、parameter_cases=3102、mapping_mask=511。正常运行中观察到 5 次自动名称事件、2 次有效重播事件、3 次取消脉冲。每次运行包含 `summary.json`、`run-manifest.json`、`transcript.log`、`launch.log`、`events.wlf` 和独立 ModelSim 编译库。波形存在但未离线重开；结论来自运行中的自动检查，不依赖截图。

## 覆盖与独立性

适配器参考使用整数除法计算坐标单元覆盖，使用 `(color-1)*3+shape` 计算对象编号，未读取 DUT 内部 mapped、qualified 或任何层级状态。检查全部输出的值和 sample/flush/reset 优先级。

- 红黄蓝与圆方三角九种组合；全部 64 种 box_color/shape_color/shape 输入组合；512 个固定种子混合输入。
- 无框、颜色不匹配、未知颜色、未知形状、稳定计数 2/3 边界、饱和输入 255、取两计数最小值。
- x/y 反向、1280/720 越界、全屏 0..1279 与 0..719、右下单像素、非四倍数边界、跨单元两像素和恰好一个单元。
- sample 单拍更新及低电平保持、flush 与 sample 竞争、reset 与 flush/sample 竞争。

事件测试逐拍给定外部可观察输出的明确期望，未复制 DUT 状态机或读取 announced/session_active/absent_frames。

- 首次稳定播报一次，持续目标不重复；未稳定或未知瞬变清除 UI，但存在会话不重新武装。
- 直接更换全部 1..9 对象仅更新 UI；同拍有效重播选用新 ID，无 det_update 的重播选用已有 UI。
- 一次缺帧不重新武装；无 det_update 的空周期不增加移除计数；连续两次无 present 取消一次，继续无目标不重复取消，放回可再次播报。
- item_id=0、10..15 被本轮积木事件层拒绝，不冒称卡片已实现；present=0 即使 det_valid=1 也不可播报。
- replay 无有效显示/检测时无效；事件为单周期；flush 清状态且取消优先；reset 优先于 flush、检测与重播。
- 参数 REMOVE_FRAMES=1、2、3、255：逐一测试移除阈值前、等于阈值、超过阈值以及间插无更新周期；0 与 256 持续禁止显示和音频并保持 cancel，reset 时 cancel 清零。

## 审核讨论、失败传播与边界

最初静态审阅提出“首次稳定与 replay 同拍时是否应为事件 5”的歧义。父任务明确本地策略是首次自动名称事件 1 优先，同拍只发一次，随后置 announced，后续 replay 才发 5。因此测试按该明确策略检查，RTL 未为此修改，也没有将这次讨论冒充已执行的 RTL 失败。

负向控制通过 `+negative_control`，在适配器复位后人为注入错误期望 item_id=9；实际仍为 0，自动检查记录 `FAIL ... injected incorrect checker expectation after reset`，summary.errors=1，Tcl `quit -code 1` 和 PowerShell `exit 1` 均生效。这是检查器与脚本失败传播证据，不是 RTL 故障注入或硬件故障覆盖。正常测试首跑通过，无编译错误或 RTL 修复历史。

present 按原始 box_valid 保持，即使形状、计数或包围盒不合格也不会因此重新武装；它不是完整共享 det_valid 的别名。无效参数持续 cancel 是当前防护行为，不能将它称作单次取消事件。以上本地语义待主对话审核，不改写共享接口文件。

## 源码与保护输入

两次运行的下列 SHA256 前后完全一致，ChangedInputs 为空：

| 文件 | SHA256 |
|---|---|
| `detection_adapter.v` | `88C8D2C28ADA81E18A4DBDB251E1169476D84B07B2EFED95E063EC0F7BEFBCAD` |
| `learning_events.v` | `57C8321B1897B3ABF63918FEB12300F0EA2BBEBAB137D1BD8157CD1A71C121E2` |
| `tb_events.sv` | `8A09DD1310BFC5361841C3C5CD2250D0DA6A6ACEF0C580FC15B1499AC158DC6B` |
| `events-test.do` | `15136DBE6BBACA67EBC4B080AE168CAD067CCB3A0759DC453B14F19166D51233` |
| `events-simulate.ps1` | `99658FFA4EB799E11DFBBE446B525443E1124384853D6705664AAC61D6580524` |
| 原 `sc520_shape.bit` | `F5F88FD03A99FBD10C23FFCFF4AEC2E7B24991F492F323BEE52E6B10C4E1A254` |
| 原 `sc520_osd_demo.bit` | `9D3B1CBDB271CF9C3198F4FC9DE49580B54BE2E918B4233829A6625D2D20945B` |

本次验证边界为两个模块的同步软件行为，未连接实际视频帧采样链路或播放器，未证明真实检测准确率、DFPlayer 行为、HDMI 像素效果、时序收敛或上板稳定性。后续由父任务独立验证集成采样点及 UI/音频链路，并在其任务日志汇总本报告。
