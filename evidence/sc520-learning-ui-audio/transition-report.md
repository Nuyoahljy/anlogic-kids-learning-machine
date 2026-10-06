# 连续目标切换的集成回归

- 负责人：`event_verification`；父任务 `sc520-learning-ui-audio`。
- 日期：2026-10-04，Asia/Shanghai。
- 工作目录：`E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-fixed-roi`。
- 分支及基础提交：`task/sc520-fixed-roi` / `f609426044982c986b54e999866be9f4c1af2682`。
- 状态：修复前集成缺陷已复现；父任务修复后同一测试零错误通过，待全尺寸回归和主对话审核。
- 本代理只修改测试、独立脚本、本报告、运行目录及共享登记；RTL 修复由父任务负责，未提交、推送、下载或操作硬件。

## 输入与判定

完整 `hdmi_learning` 包括坐标适配、颜色分割、候选框统计、框稳定、形状判断与确认、学习事件和模拟播放器。测试真正提供 384×240 像素、行消隐和帧同步，不强制 DUT 的检测输出。ROI 为 x=16..367、y=144..223；SCENE_FRAMES=1，前十帧完成九种测试源加空白，随后 25 个相机帧按如下顺序输入：

| 相机帧索引 | 输入 | 位置 |
|---|---|---|
| 0..4 | 红色方形 | x=100..131，y=160..191 |
| 5..9 | 黄色方形 | 同上 |
| 10..14 | 黄色方形向右移动 60 像素 | x=160..191，y=160..191 |
| 15..19 | 空白 | 无方形 |
| 20..24 | 蓝色方形 | x=100..131，y=160..191 |

连续有效的前三段只允许首次红方产生一次自动事件；换成黄色与移动后 UI 可重新显示稳定结果，但不得取消/重播。空白解除后，蓝方产生第二次自动事件。原始候选与稳定框的 x/y/w/h 均由输入方形坐标直接计算，适配后的 320×180 坐标也独立计算；未使用 DUT 框坐标作为期望。逐帧核对稳定计数与 UI，逐拍核对三拍视频控制延迟，独立统计实际音频事件及取消脉冲。

## 修复前实际结果

```powershell
pwsh -NoProfile -File fpga/scripts/sc520-learning-ui-audio/transition-simulate.ps1 -Phase before-fix
```

ModelSim SE-64 10.7，运行目录 `transition-runs/before-fix-20261004-120520-7128-c83a00/`：

```text
OBSERVED_AUTO camera_frame=3 event=1 item=2
OBSERVED_CANCEL camera_frame=7 candidate_valid=1
OBSERVED_AUTO camera_frame=8 event=1 item=5
OBSERVED_CANCEL camera_frame=12 candidate_valid=1
OBSERVED_AUTO camera_frame=13 event=1 item=5
OBSERVED_CANCEL camera_frame=18 candidate_valid=0
OBSERVED_AUTO camera_frame=23 event=1 item=8
TRANSITION_RESULT done=1 errors=11 checks=3295847 frames=35 pixels=3225600 cycles=3295643 auto_events=4 cancel_events=3 mapping_checks=25 bbox_checks=31
```

仿真进程及 PowerShell 退出 1，编译/运行工具 Errors: 0, Warnings: 0；11 个功能检查失败均来自多余取消/播报及其累计断言。25 次 UI 检查、31 次独立框几何检查、适配坐标和稳定计数均未失败。

原因已由输入实际复现：`learning_events.present` 只连接适配器的 `det_present`，而它来自稳定后的 `box_valid`。颜色或位置突变使框稳定器重新确认两帧；这两帧原始 `candidate_valid` 仍为 1，却被事件层解释成移走，触发取消和重新武装。父任务已收到完整反例并负责修复连接。

每次运行的 `run-manifest.json` 保存完整展开命令、全部 RTL/测试/脚本及两旧 bit 的源前后 SHA256、进程退出码、summary 与输出文件哈希。该次 `ChangedInputs` 为空。修复前 wrapper 原文保存在 `hdmi_learning.snapshot.v`；该快照仅用于重现旧缺陷，不进入当前工程。

## 修复后同一测试复验

父任务将 wrapper 中学习事件层的存在输入改为 `learning_presence = det_present || candidate_valid`；稳定识别资格仍来自原适配器。有效但正在重新确认的目标不会被解释成移走。本代理没有修改任何 RTL，也没有修改测试、脚本或预期。

```powershell
pwsh -NoProfile -File fpga/scripts/sc520-learning-ui-audio/transition-simulate.ps1 -Phase after-fix
```

运行目录 `transition-runs/after-fix-20261004-120645-26456-281fec/` 的实际输出：

```text
OBSERVED_AUTO camera_frame=3 event=1 item=2
OBSERVED_CANCEL camera_frame=18 candidate_valid=0
OBSERVED_AUTO camera_frame=23 event=1 item=8
TRANSITION_RESULT done=1 errors=0 checks=3295839 frames=35 pixels=3225600 cycles=3295643 auto_events=2 cancel_events=1 mapping_checks=25 bbox_checks=31
```

ModelSim 与 PowerShell 退出 0，编译/运行工具 Errors: 0, Warnings: 0。35 帧、3,225,600 像素时段内，只有首次红方与真实移走后的蓝方自动播报，真实空白取消一次；换色和移动保持会话。25 次 UI 检查、31 次独立原始/稳定框几何检查及适配坐标、稳定计数、三拍视频控制均通过。检查总数相对失败运行少 8，原因是错误版本多出的两个自动事件和两个取消分别额外调用了事件检查器；输入帧数、像素、时钟周期及测试源码完全相同。

两个 manifest 的全部输入 SHA256 逐项比较，只有 `learning/hdmi_learning.v` 改变；修复后 wrapper SHA256 为 `BABB610956591F4C4095E176660DE9F282350A9C685BF7DCD5BBA7DC10476586`。两次运行各自源前后保持一致。修复前后 wrapper 都分别保存独立快照，旧失败证据没有覆盖。原 shape 与 OSD 两个 bit 的前后 SHA256 分别仍为 `F5F88FD03A99FBD10C23FFCFF4AEC2E7B24991F492F323BEE52E6B10C4E1A254` 和 `9D3B1CBDB271CF9C3198F4FC9DE49580B54BE2E918B4233829A6625D2D20945B`。

## 验证边界与后续

修复后已经使用原测试，不调整预期来掩盖旧失败。此测试检查相机输入到事件/框/UI 状态的集成行为与视频控制延迟；小画面不包含 y=608..711 底部面板，不替代 full 720p 像素/OSD 回归。模拟播放器未产生真实声音，未验证 DFPlayer 或任何上板行为。波形文件已输出但本代理未离线重开。父任务需将此反例和修复结果汇总到任务日志，并以修复后的源码重跑 full 和 TD；修复前的构建不作为最终候选。
