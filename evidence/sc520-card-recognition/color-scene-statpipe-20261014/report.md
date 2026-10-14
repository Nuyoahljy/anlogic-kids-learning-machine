# 统计流水时序修复后的实际成像组合回归

日期：2026-10-14；基础HEAD3089ae8，工作树task/sc520-card-recognition。色彩源码由imaging_audit修改，本子任务没有修改RTL、TB、runner、模板或图像数据，只在新目录重跑三类测试。111原组合证据保留。

新color SHA256：5020B23A8126103E0D1D5C9BB67DC8C93F55ED1C95B775FC1894B4D813420F31。该版将中性选择和四lane求和分成四级；成像代理给出的合同是末原始输入后第4拍完整统计、满足中性参考时第6拍pending，新SOF后第4拍更新gain，像素路径仍54拍。组合TB原有末组后88拍检查不需改变，未放松完整统计或同帧增益条件。

## 实际结果

- 正常：ModelSim native0，8场景、24个720p RGB96完整帧、27,648,252检查、0错误。
- 实际color.O_tdata注错：native1，92检查、1错误、injected1；runner按预期资格通过。
- 500ns提前停止：native2、done0、errors0；runner按预期资格通过，不能冒充仿真完成。

五张gain65原始暗卡仍分别在第3帧输出10/11/12/13/14；每帧230400组、720行，54拍延迟和WB256保持不变，全帧中性计数精确；黑白端点和4lane逐96bit输出检查通过。暗苹果计分一次，后续两帧停留不重答。新旧正常运行的整个observations.csv逐字节相同，包含逐帧统计、延迟、观测ID、计分及后EOF等待时间。

38项输入路径相同，仅color源码SHA从3A2CEB5F...FFC26F变为5020B23A...420F31；TB、runner、其他RTL、模板、原PNG及派生before/after mem完全未变。没有重跑4320模型或父任务80系统矩阵。

## 命令与证据

三轮均实际执行bundled Python `-B -X utf8 fpga/scripts/sc520-card-recognition/simulate-color-scene.py`，分别正常、`--negative`、`--watchdog-probe`。

- `E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-card-recognition\evidence\sc520-card-recognition\runs\p14-color-scene-normal-20261014-113622-2fe1c13c`：{'errors': 0, 'checks': 27648252, 'scenarios': 8, 'done': 1, 'injected': 0, 'frames': 24}。
- `E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-card-recognition\evidence\sc520-card-recognition\runs\p14-color-scene-negative-20261014-113622-791a2fcf`：{'errors': 1, 'checks': 92, 'scenarios': 1, 'done': 1, 'injected': 1, 'frames': 1}。
- `E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-card-recognition\evidence\sc520-card-recognition\runs\p14-color-scene-watchdog-20261014-113622-0564ebcd`：{'errors': 0, 'checks': 0, 'scenarios': 1, 'done': 0, 'injected': 0, 'frames': 0}。

独立audit.json共232项检查、0失败，核对新三轮原件/快照/输出、111基线快照和结果、唯一来源变化、全部派生数据和CSV相同。

外部qualified EOF仍由TB在真实color末行排空后提供；vendor signal_delay原件和显式行为RAM边界不变。该回归只证明新统计流水在此RTL组合条件下保持行为，不证明CSI/RAW/DDR/PHY、vendorRAM物理时序、新TD或实际摄像头已通过。
