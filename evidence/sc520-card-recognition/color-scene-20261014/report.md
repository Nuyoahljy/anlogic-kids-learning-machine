# 实际成像RTL与场景识别组合验证

日期：2026-10-14；基础HEAD3089ae8，工作树task/sc520-card-recognition。本子任务仅新增独立TB、runner和证据，未修改111构建冻结的色彩/场景/识别/业务RTL或模板。

## 实际结果

正常ModelSim原生exit0、8场景、24个完整1280×720 RGB96帧、27,648,252检查、0错误。真实color.O_tdata注错原生exit1、92检查、1错误，证明检查器能检测真实输出损坏；500ns提前停止原生exit2、done0、errors0，不能被当作测试完成。三个runner资格均exit0。

输入五张原始gain65-before PNG逐字节转mem，在TB中仅按bp像素4×4重复为720p光栅，没有先在软件中tone再喂DUT。真实pixel14_color_pipeline使用默认WB_ENABLE=1、TONE_ENABLE=1，输出直接接真实pixel14_pipeline（scene/ROTATION_VARIANTS256/shape/filter/CDC/items14业务）。gain65-after PNG仅作为独立输出参考。

五张暗卡各连续3个实际色彩处理帧；前2帧未确认，第3帧分别输出10、11、12、13、14。每帧完整输入/输出230400组、720行；全部24帧输入到色彩输出延迟54拍，R/B白平衡增益始终256，原图计算的全帧中性像素计数与RTL一致。单独720p四色lane探针包含不同RGB字节和黑/白端点，全部输出逐96bit比较，无lane错位。

在实际灰空场3帧重新武装后，原始暗苹果通过真实color→识别链，3帧后计分一次；随后又保持2帧，score与answer计数都保持1。父任务另有完整四键/停流/坏帧回归，这里只覆盖成像接口和暗卡后的防重复计分。

## 测试边界

TB驱动递增源帧标签，将真实color的提前SOF、O_valid、O_tlast、RGB96直接送到采集。每行80拍消隐；最后输出数据及行尾完全排空后，TB单独给qualified EOF。这个外部EOF激励不代表CSI/RAW解包验证。capture和display使用异步时钟；该测试不包含真实摄像头、DDR、HDMI PHY、Flash或上板。

编译的是原vendor根目录signal_delay.v，不改其内容；其双口RAM为imaging-audit/ip_behavioral_models.sv中显式行为模型。新色彩路径未实例化该文件中的divider。此结果不作为vendor RAM物理时序或TD资格，也不能证明现实纸卡暗沉已经解决。

## 复现

在本工作树使用bundled Python执行`-B -X utf8 fpga/scripts/sc520-card-recognition/simulate-color-scene.py`，分别不加选项、`--negative`、`--watchdog-probe`。每次新建独立运行目录，冻结全部HDL/TB/runner、模板、原始before/after PNG及转换清单，保留命令、日志、CSV、summary、输入和输出SHA。

- `E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-card-recognition\evidence\sc520-card-recognition\runs\p14-color-scene-normal-20261014-112236-86c86046`：native 0，{'errors': 0, 'checks': 27648252, 'scenarios': 8, 'done': 1, 'injected': 0, 'frames': 24}，38输入快照。
- `E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-card-recognition\evidence\sc520-card-recognition\runs\p14-color-scene-negative-20261014-112210-20cf1a38`：native 1，{'errors': 1, 'checks': 92, 'scenarios': 1, 'done': 1, 'injected': 1, 'frames': 1}，38输入快照。
- `E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-card-recognition\evidence\sc520-card-recognition\runs\p14-color-scene-watchdog-20261014-112236-536bed67`：native 2，{'errors': 0, 'checks': 0, 'scenarios': 1, 'done': 0, 'injected': 0, 'frames': 0}，38输入快照。

独立回读audit.json共178项检查、0失败，覆盖三轮源文件/快照/生成mem/输出哈希及CSV的完整帧、54拍、单位WB、五卡确认和一次计分。
