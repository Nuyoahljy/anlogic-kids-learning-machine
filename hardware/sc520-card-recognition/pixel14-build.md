# pixel14 隔离视频候选工程

> 本页保留 2026-10-12 106 的构建与当时验证边界。后续用户反馈其持续“不可信”，当前107修复、实际资格与复测入口见 [0107排障说明](pixel14-boardfix107.md)。下文803拍固定HS限制属于106历史实现，107已改为有界尾部。

本工程为 SC520 真实采集分析、十四类业务和 HDMI OSD 的独立候选。未下载 SRAM、未写 Flash、未接真实语音；构建通过也不代表相机识别、按键电压或上板显示通过。旧四键候选 826966ea 及其源码未修改。

## 工程入口与复现

- `fpga/custom_project/sc520-pixel14/td_project/camera_to_dsi_display.al` 是本任务工程；`overlay/` 只含顶层、导出 AWB96 的 ISP、引脚和时序约束。
- `fpga/scripts/sc520-card-recognition/prepare-pixel14.py` 重建工程清单；它引用旧 `sc520-fixed-roi/fpga/custom_project/sc520-board-keys` 中厂商源码、IP 和约束依赖，不复制整个旧工程。
- `fpga/scripts/sc520-card-recognition/build-pixel14.ps1` 使用 TD `D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe`，为每次运行创建独立 `evidence/sc520-card-recognition/builds/<8位ID>/`。当前任务 RTL、overlay、模板和构建脚本逐项快照，外部引用连同 IP 附属文件在运行前后核哈希。
- TD 6.2.1 会将同盘绝对引用转换为相对路径，在深目录下触发 Windows 旧路径限制。脚本临时选用空闲 X/Y/Z/W/V 盘符，以 `subst` 映射本次构建根目录；运行结束解除本次映射。不会覆盖既有盘符或复制厂商目录。

在本工作树根目录执行：

```powershell
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 fpga/scripts/sc520-card-recognition/prepare-pixel14.py
pwsh -NoProfile -File fpga/scripts/sc520-card-recognition/build-pixel14.ps1
```

工程清单使用原项目 720p60 的 PLL、DDR2、MIPI 与 HDMI IP，器件 PH1P35MDG324，速度等级 3。四键仍是输入 D5/A9/B9/C7、LVCMOS33/PULLUP；仅异步口到第一级同步寄存器设 false path，meta→safe 保留 2 ns 最大延迟和 hold 检查。物理电压验证沿用旧候选的待验证状态。

## 精确采集信号与帧资格

原工程顶层 `S_ISP_O_tdata` 为 128 位 DDR 打包数据，不是四像素 RGB。新 `overlay/isp_top.v` 保持原 128 位输出和打包路径，额外导出 `u_awb` 后、`data_96bit_to_128bit` 前的 `awb_O_tdata[95:0]`、`awb_O_tuser`、`awb_O_tlast` 和 `awb_O_tvalid`。所有识别像素在 `S_csi_rx_clk` 域按高位到低位四个 RGB888 消费。

`pixel14_capture_provenance` 在同一采集域观察真实 CSI SOF/EOF、解码长包长度、HS 有效节拍、CSI 有效数据、RAW SOF/EOF/有效组、AWB96 SOF/EOL/有效组。摄像头配置完成和 I2C 错误先经两级同步；不使用旧“最近一帧”诊断寄存器代替本帧健康。

每次真实 CSI SOF 递增 32 位编号。正常 720p 帧必须有 720 个 RAW10 长包，每包声明 800 个 16 位字，实际 HS burst 为 803 拍（2 拍头、800 拍有效载荷、1 拍 CRC）；整帧 CSI 有效数据为 288000 个 32 位字，RAW 和 RGB 各 230400 个四像素组，RGB 每行 320 组且 EOL 正确。模块只核 CRC 占位长度，不验证其数值；厂商接口未输出 CRC/ECC 校验结果，故不能宣称全部传输错误可检测。

厂商 `isp/csi_unpacket_2lane.v` 中长度来自 RAW10 包头、单位为 16 位字，并在 HS 无效时清零；SOF/EOF 为实际短包头的寄存解码。`isp/raw10_unpacket_2lane.v` 将 CSI EOF 仅延迟一拍，但 RAW 重组有多级延迟，因此适配器只锁存 RAW EOF，直到最终关闭才核对 RAW 总数。不会因 EOF 到达时最后 RAW 组尚在途而提前判坏。

最终 done 必须同时拥有本帧 CSI EOF、RAW EOF、完整 RGB 栅格和至少连续 64 拍 RGB 空闲；发布在无 valid/EOL/SOF 的当前空拍。最后一个 RGB 像素、HDMI VSync 或显示重播都不能单独产生健康完成。异常包长、HS 截短、lane/config 错误、错误 EOL、重叠 SOF、计数溢出会撤销；缺 EOF/停流在 2000000 个持续采集时钟内到期。采集时钟停止由持续 75 MHz 显示域的 1 ms 时基和 100 ms 业务看门狗撤销旧结果。

## 显示与音频边界

新 OSD 接在原 `hdmi_mixer` 输出与 HDMI TX 之间，保留 DDR 的原预 OSD RGB 路径。按输入 DE 计数生成 1280×720 显示坐标，视频旁带由 `pixel14_pipeline` 与 OSD ROM 同步延迟。检测输出显式启用 `ENABLE_OUTPUT=1`，使用既有 `prep-v1-max40/templates.mem`；它仍是实验模板和固定摆位候选。

物理来源固定 `source_test=0`，真实采集结果通过握手 mailbox 跨域。旧 DDR 缓冲没有完整写入提交和显示帧身份绑定，OSD 代表最近健康采集分析，不能声称与当前显示图像精确逐帧对应。音频接口暂接 idle=1/fault=0，仅形成内部事件；没有 UART、外部音频 IO 或真实播放。

## 已执行与构建迭代

2026-10-12 最终 ModelSim SE-64 10.7：provenance 正常 22 场景、95 检查、0 错误；真实输出注错 native exit1、errors1/injected1；500 ns 提前停止 native exit2、done0/errors0。三模式 runner 均按资格返回0。最终正常测试 `p14-provenance-normal-20261012-110743-625b8ade`，注错 `p14-provenance-negative-20261012-110746-71f2ebf0`，提前停止 `p14-provenance-watchdog-20261012-110749-e4d7b4cf`。新增四个关闭边沿重复标记拒绝测试；较早的 18 场景/71 检查及理想协议测试均保留为历史。全软件十五轮证据见 [pixel14-validation-v2.json](../../evidence/sc520-card-recognition/pixel14-validation-v2.json)。

测试还直接编译实际被旧 `.al` 引用的两个厂商 CSI/RAW 模块，生成合法头、RAW10 载荷和 CRC 占位，不替换其实现。在 64×4 几何、包间 1/2/4/8 个空拍下均读到 CSI80/RAW64/EOF1，并各产生一个健康完成；实质截短 HS 包即使后面提供完整 RGB 也不能发布健康完成。该测试验证接口节拍与计数，CRC/ECC 和 MIPI 模拟电气仍不在覆盖内。

构建历史：`6a50b102` 为准备器第一次遇 TD 非标准 XML 格式失败；`6a50b103` 失败于外部源长路径；`6a50b104` 实际综合成功，但启动器成功 token 占位替换错误导致脚本拒收，且该轮被后续 provenance 修正替代。`6a50b105` 完成综合、布局布线和 bitgen，但 SWNS=-5.063 ns、STNS=-70.009 ns，时序不合格。上述原目录和记录均保留。

根据 105 的实际关键路径，root 新增独立分拍排序 `pixel14_card_matcher`，并将积木 bbox 选择与宽高差分拆为两拍；旧 `card_matcher.v` 不变。新实现重新通过完整 720p 管线及十五轮软件回归后，完成 `6a50b106`。

## 106 最终构建与恢复资格

[独立恢复审计](../../evidence/sc520-card-recognition/builds/6a50b106/recovery-audit.json) 已通过，状态为“候选待主对话审核”。106 原始综合退出 0，布局布线进程退出 1：bitgen 已成功结束，随后报告钩子要求已经被综合优化掉的泛型 `fault_meta/fault_sync`，触发端点错误。原 `failure.json`、`stages.json`、快照、布线数据库和 bit 均未改写；恢复审计独立记录实际结果，不把原进程退出码改成 0。

| 检查 | 本轮实际结果 |
|---|---|
| 最终建立时序 | SWNS +0.105 ns，STNS 0 |
| 最终保持时序 | HWNS +0.020 ns，HTNS 0 |
| 工具报告覆盖 | 96.12%；采集 103.520 MHz，显示 75.002 MHz |
| 资源 | 15,075 slice；15,206 register；43 ERAM；17 DSP |
| ROM | 1 个 1024×5 模板和 3 个 4096×5 字库逐地址 INIT 校验；4 份初始化签名均存在于最终网表 |
| 四键 IO | D5/A9/B9/C7，输入、LVCMOS33、PULLUP，与原工程一致 |
| 源与快照 | 292 项输入记录、24 个快照核对；实现输入不变，仅 bitgen 后报告辅助脚本与原快照不同 |
| 保护基线 | 1284 项旧代码、旧 bit 及主文档哈希一致 |

本轮未压缩 [camera_to_dsi_display.bit](../../evidence/sc520-card-recognition/builds/6a50b106/td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit) 为 **1,789,539 字节**，SHA-256：

```text
3909C31AA81D7EB5C3153EFC2DBAC6D54C655A82A698107AA08CB0B14AFC0ABD
```

该文件留在本地证据目录，大型数据库、网表和 bit 不纳入 Git；提交保留源、配置、清单、哈希及关键物理报告。此候选没有替换旧四键 `826966ea`，没有下载或写 Flash。

## 跨时钟物理复核

`cdc106-v3` 对同一 106 布线数据库进行只读分析。四路请求/应答同步器和四键在原始约束视图中均有实际 2 ns setup 预算，hold 检查保留且裕量为正。staging fault 与摄像头配置同步器使用原时钟周期预算，下面的 2 ns 比较仅是事后传播观测。

| 同步器 | 最大数据延迟 ns | Hold 裕量 ns | 实际 setup 预算 |
|---|---:|---:|---|
| forward req / ack | 0.628 / 0.446 | 0.141 / 0.091 | 2 ns |
| backward req / ack | 0.383 / 0.446 | 0.122 / 0.091 | 2 ns |
| 四键 0/1/2/3 | 0.405 / 0.405 / 0.307 / 0.405 | 0.133 / 0.133 / 0.104 / 0.133 | 2 ns |
| staging fault | 0.604 | 0.155 | 13.333 ns |
| config done / error | 0.405 / 1.429 | 0.133 / 0.395 | 9.660 ns |

TD 会把不同逻辑触发器打包进同一个 LSLICE，物理实例名可能显示为视频 DE 或 provenance 计数器。恢复审计从物理 Q/D、选择参数及实际逻辑 net 核对路径身份，不能只依赖实例名。泛型 mailbox fault 同步器为常量而被删除；实际溢出保护 `staging_fault` 的独立同步链已经检查。

多位握手数据另在清除异步时钟组切断后，用实际 MIPI/PLL 输出引脚及原 9.660/13.333 ns 周期恢复时钟。查询的目标集合因打包别名扩展为 160 项；报告中 19 条 setup 和 19 条 min 是额外同域路径，均从跨域统计排除。剩余 **80 条 setup + 80 条 min** 覆盖全部 80 个有效数据位，无缺位、重复或错位；69 个目标保持 `dst_data` 名称，11 个为 joiner 字段别名。

真实跨域 setup 报告的数据传播延迟为 **0.440～1.397 ns**，每条均小于恢复审计采用的 **10 ns 外部传播上限**。TD 在此只读上下文中没有实际应用尝试的 10 ns `set_max_delay`；报告里的 0.110 ns budget 来自两个异步时钟的相位计算，其负 slack 不作为 CDC setup 验收结论。这里通过的是逐位路径身份和实际传播上限核对，不宣称“10 ns 约束收敛”、异步 setup/hold 收敛或亚稳态 MTBF 证明。

较早 `cdc106-check`/`cdc106-v2` 的默认派生时钟视图不足以证明原时钟下的传播，保留为探索历史。只有 v3 被本轮恢复审计引用。本报告资格只绑定当前 bit 与布线；未来重新构建必须重新检查。

恢复审计命令（不会运行 TD，也不会覆盖已有报告）：

```powershell
python -B -X utf8 fpga/custom_project/sc520-pixel14/tools/audit-recovery.py `
  evidence/sc520-card-recognition/builds/6a50b106 `
  evidence/sc520-card-recognition/builds/cdc106-v3 `
  --output evidence/sc520-card-recognition/builds/6a50b106/recovery-recheck.json
```

本次 root 实际使用 bundled Python 执行同一命令，首次输出为 `recovery-audit.json`，退出 0。已对当前源码、全部快照、ROM、IO、时序、逐位 CDC 和保护基线作实际断言。恢复产物的哈希在本次审计时登记，不伪造此前探索运行尚未记录的起止哈希。

下一步由主对话审核候选与软件接口；旧四键 bit、DFR0534 实物测试仍独立待完成。实拍阈值、真实 HDMI/按键/长时间运行、新候选上板、DFR0534 音频接入及精确 DDR 显示帧绑定尚未验证。
