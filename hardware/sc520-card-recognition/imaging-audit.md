# SC520 成像链路审计与颜色修复候选

当前统计流水补充（2026-10-14）：111最终建立时序为-3.084ns，真实最差路径从输入RGB经中性色比较、四lane累加和帧末累计，进入统计乘法DSP输入。统计现拆为四级：每lane min/max、中性色选择、两两求和、四lane求和；SOF/valid/EOL同延迟4拍。当前SHA为 `5020B23A8126103E0D1D5C9BB67DC8C93F55ED1C95B775FC1894B4D813420F31`。输入最后EOL后第4拍完成精确统计，第6拍产生pending；有可用pending时，在新rawSOF后第4拍原子更新增益，早于首像素输出的54拍。像素延迟/RAM/增益乘法/饱和/tone/输出段与111字节一致。最终原19场景加720p共20场景4836551检查0错，真实注错及500ns提前结束按预期拒绝；增加每帧全lane统计量和4/6拍精确时序断言，包含SOF同首组且需要更新增益的情况。证据为 `evidence/sc520-card-recognition/imaging-audit/stats-pipeline-audit.json`，复现 `audit_stats_pipeline.py`。

9.660ns独立核TD6.2.1已实际完成布局布线：SWNS+1.035ns、STNS0，像素源码未再修改；探测工程整体仍不合格，HWNS-1.232ns、HTNS-45.176ns。报告所列10条最差负hold/removal路径起于探测包装的外部pixel_byte或rst_n，不能据此推断所有未列出的内部hold路径通过。保留原负结果、不改输入延迟或falsepath掩盖；112整机的真实IO/复位约束和整体布线仍须另验。核探测未bitgen，目录 `imaging-audit/color-timing/probe-20261014-113926-99a1d5`。

前一实现补充（2026-10-14）：父任务110资源探测报告DSP超量后，本代理仅将 `tone07` 的小乘法替换成常量移位加法，SHA为 `3A2CEB5F9289A3B23D1CC8120B8375A385FB1D2E284933CAE68FFA2107FFC26F`。独立审计确认函数以外字节不变、全部256码输出相等；原normal/720p/negative/watchdog四轮重跑通过，正常为20场景4836515检查0错，54拍延迟及观测CSV完全相同。证据见 `evidence/sc520-card-recognition/imaging-audit/tone-shift-audit.json`，复现脚本 `audit_tone_shift.py`。八个像素增益乘法及两个帧统计乘法未改。下面原审计及旧SHA保留作为比较基线，`audit_imaging.py`和`audit_tone_shift.py`检查各自原候选而非当前实现。

日期：2026-10-14。负责人：接续板级聊天的 `/root/imaging_audit` 子代理。比较基线为 `3089ae8`、D0109 构建 `6a50b10a`；本页只报告本任务的成像数字链路，不宣布上板通过。主任务负责活动顶层、场景算法、TD 构建和最终交付。

用户报告使用纸质打印卡片，镜头总体暗沉、颜色偏灰且识别失败。本轮没有新的实拍、传感器原始像素、光照测量或寄存器读回。已经复现的是旧 AWB 的颜色破坏机制，不能因此把全部实物问题都归因于 AWB。

## 实际链路和范围

工程入口是 `fpga/custom_project/sc520-pixel14/td_project/camera_to_dsi_display.al`。D0109 的绑定依据为 `evidence/sc520-card-recognition/builds/6a50b10a/inputs.json`，不能凭同名源码判断实际使用者。新候选的 `isp_top` 和顶层接线由 root 修改，下面的旧链路结论绑定 0109 的只读快照。

| 环节 | 实际使用 | 核查结论 |
|---|---|---|
| 相机初始化 | 本任务 `overlay/uicfgcs520.v` 实例化前置工程 `uics520reg_720p60` | 原厂 HD 表：1280×720、VTS=1000，非清单里另存的 `uics520reg` 旧裁切表 |
| 曝光与增益 | 前置工程 `uiisp_beta/ae_set.v`、`SC520GainTbl.v`、`uics520regAE.v` | 请求曝光1991半行、模拟16倍、数字1倍。是固定默认值及手动调整，没有亮度反馈；ACK成功不是寄存器生效读回 |
| RAW10 | `raw10_unpacket_2lane` → `mipi_to_raw_converter` | 每像素取高8位 `[9:2]` 等四组；合法1023映射255，没有发现把高位截成低位的源码证据。低2位量化损失是现有设计，不等于画面被额外压成四分之一亮度 |
| Bayer与插值 | `demosaic` 参数 `BGGR` | 逐像素插值后 `{0,R,G,B}`；尚无实物色卡或RAW像素验证 Bayer 相位和光学颜色 |
| 128→96 | `data128_96` | 删除每个32位像素的填充字节并颠倒四像素组序，不交换 R/G/B 通道。采集按高位开始取lane，与这份布局对应 |
| 旧 AWB | 前置工程根层 `awb.v` | 每帧累加器从1起始，只用每组第1个像素；低于总通道和720者参与。连续按累计G/R、G/B改变R/B，G保持原值 |
| 旧 tone | 0109 `overlay/isp_top.v` | 文件尾有 `axis_gamma_rgb96` 定义，但无实例；不能把它当成已启用的色彩曲线 |
| 分叉 | `awb_O_tdata` | 同一 RGB96 同时送识别tap和 `data_96bit_to_128bit`。显示再经过DDR及 `video_out` 字节重组，识别不经过显示增强 |
| HDMI | `hdmi_tx`、加密核心 | 明确 `VIDEO_FORMAT="RGB"`，前端可达0..255；未测加密核心AVI量程声明和显示器处理，不能从参数推断实物量程匹配 |

本地原厂资料为 `E:/juan/FPGA/Data/HX1P35A_Contest_202606/SC520CS摄像头资料/SC520CS-03_数据手册_V1.6.pdf`。实际读取第19–21页：传感器无内建AEC/AGC；曝光最小4半行、最大 `2*VTS-9`；`3e09=0f` 为16倍模拟，`3e06/3e07=00/80` 为1倍数字。资料还说明第N帧写入曝光/增益在N+2帧生效。因此本轮没有改相机曝光寄存器。当前顶层把手动曝光位固定释放，保留的两位I_button端口只连手动增益；四个业务键属于另一RTL接口。这里仅陈述端口连接，不据此认定实物按钮数量或位置。

## 已复现的旧 AWB 缺陷

真实且未修改的 `awb.v`、`signal_delay.v` 编译进 ModelSim。测试明确以无符号48/32、50拍流水除法器和同步双口RAM行为模型代替IP边界，参数与活动 divider.ipc 一致；它证明 AWB 算法与端口逻辑的行为，不是厂商IP时序、门级等价或硬件资格。

| 数字输入 RGB | 旧 AWB 实测输出 RGB | 新候选单位增益、关闭tone |
|---|---|---|
| (220,40,30) 红色满帧 | (40,40,39) | (220,40,30) |
| (30,40,220) 蓝色满帧 | (39,40,40) | (30,40,220) |
| (220,200,40) 黄色满帧 | 最后为(199,200,199) | (220,200,40) |
| 同一红色置于第1及第3行，中间有灰色 | (40,40,39) 与 (88,40,32) | 两处相同 |

旧算法把“场景平均色就是中性灰”应用到画面前缀，遇大面积有色物体或有色背景就会消除对象本身的通道差，并随前方画面改变。积木阈值要求明确的R/G/B差，卡片二值化也会受亮度变化影响；这条缺陷能同时影响显示和识别。

## 私有颜色修复

文件为 `fpga/custom_project/sc520-pixel14/overlay/pixel14_color_pipeline.v`，冻结 SHA256 `86E8E1F5A9422B509141AFB5502F535EA70CD04DD941900B97E4F95639077F8C`。

- 四个lane都参与参考选择。仅 `min>=64`、`max<=247`、`max-min<=max/4` 的近中性色参与，默认整帧至少1024个参考像素。暗像素、已裁切白色和鲜艳纯色不作为白平衡参考。
- 完整 RGB 组数、每行组数和行结束标记都符合几何后，才计算下一帧增益。R/B增益Q8限制192..384，即0.75..1.5，每帧最多改1/256，死区为目标值的1/64；G不缩放。没有可信参考则保留之前的增益。
- 增益只在下一SOF应用，整帧不变。SOF打断旧延迟输出会丢弃新帧输出并标记本地统计坏帧，禁止混用两个帧的增益。此处统计只检查RGB结构，CSI错误、CRC/ECC或I2C状态仍由外部provenance负责；颜色模块本身没有这些故障输入。
- 增益结果向下截取8位并饱和到255，再可选经过16段gamma0.7近似。曲线端点0/255和单调性已逐值验证。它是经验性亮度候选，不是已标定的sRGB曲线或相机色彩校正矩阵。
- `WB_ENABLE=0,TONE_ENABLE=0` 是逐字节旁路；`WB_ENABLE=1,TONE_ENABLE=0` 是只改白平衡；两个都为1是候选。root在 `isp_top` 的generate保留原AWB分支作完整旧版对照。选中链路同时服务识别和DDR。

曲线示例：128→157、160→184、165→188、255→255。旧前景条件 `min<180` 在单位WB时对应的首个非暗输入变成155：灰160经tone成为184，灰128仍小于180。完整逐值表见 `tone-curve.csv`，scene联合模型另由场景子任务验证，不能仅凭这几个值宣布任意纸白和背景都可识别。

## 时序约定和测试

SOF是提前控制脉冲，保持原 `O_tuser=I_tuser`。两拍输入寄存器和原 `signal_delay(DATA96,50)` 保留DDR输入FIFO的复位准备时间。新增颜色输出实测首组输入至首组输出54拍，EOL与本行最后一个有效四像素组同拍；root负责实际ISP/provenance/DDR接线及总延迟。继承的行缓冲要求连续行内payload；ready只透传，不是支持任意背压的AXI缓冲。

实际执行（bundled Python，`-B -X utf8`）：

```powershell
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 evidence/sc520-card-recognition/imaging-audit/simulate_color.py
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 evidence/sc520-card-recognition/imaging-audit/simulate_color.py --full-resolution
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 evidence/sc520-card-recognition/imaging-audit/simulate_color.py --negative
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 evidence/sc520-card-recognition/imaging-audit/simulate_color.py --watchdog-probe
```

最终正常：19个小帧场景111832检查 + 1个1280×720完整帧4724683检查，共20场景4836515检查0错。720p四lane共921600个中性样本，R/G/B总和110592000/138240000/117964800无溢出，下一SOF才应用257增益。覆盖全部通道字节值、lane顺序、单调曲线、饱和、SOF同首组/提前、EOL同末组/紧随空拍、缺EOL、额外EOL、纯色保持、停止输入及SOF打断延迟尾部。注入真实输出错误得到native1/errors1/injected1；500ns提前结束得到native2/done0。确切目录、输入/输出/快照SHA与审计结果见 `imaging-audit.json`。

后续需要用户在固定镜头、固定光照和同一摆放位置拍一张包含白纸、灰色区域和红/黄/蓝纸卡的原始画面，并拍对应HDMI画面，保留D/E/Q/G诊断值。若只能提供一种证据，优先给整屏HDMI照片及同场景手机直拍；说明室内灯/日光即可，暂不要求购买色卡。照片可判断整体趋势，量化颜色差仍需采集RGB样本。该步骤由主任务统一向用户提出。
