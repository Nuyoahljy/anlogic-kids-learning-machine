# T022：当前视频业务与真实DFR0534的离线整机接入

2026-10-16；D053接续负责人01a142a0-2945-7823-b9c2-868aa816a6f6，继承旧板级01a14030-32d9-78f2-b274-91a370cc9ff0的T022成果。依据主D051，从板级fe5173964657dacc9c6723fe00e7ed5975901462接冻结音频3287af4ad8943e43f2dcd0d13c7b253dffd7e4b3。软件检查点e8466e2已按D055接受，物理探针完成但因负时序明确拒收。当前主为01a14468-1741-70a2-aea6-757eb183382f。本工程没有用户下载镜像，禁止bitgen和写入delivery；D0117和D0116原交付保持原样。

## 源码与配置边界

- [启动清单](../../evidence/sc520-card-recognition/audio22/start.json)逐SHA保护763个既有构建、交付及最终仿真文件；6个音频RTL和1个独立UART模型来自精确Git blob。原音频工作树、用户bench与当前视频源码均不修改。
- 新顶层在`fpga/custom_project/sc520-audio22/overlay/design_top_wrapper.v`；音频适配和独立显示在`fpga/rtl/sc520-card-recognition/audio22/`。仍编译原pixel14_pipeline和items14_system，使用其已有audio_event_valid/kind/item/cancel输出；旧T017文件全部保留。
- `pixel22_content/font_rom/panel/compositor`是本轮独立模块，避免改变D0117编译来源。新工程只有一份被实例化的显示字库；综合ROM证明核对实际3个字体ERAM，而不是按源码列表推断。新字库163字，原158个ID及位图完全不变。

| 配置 | 实际设置 | 用途 |
|---|---|---|
| [hardware-default.json](../../assets/templates/sc520-card-recognition/audio22/hardware-default.json) | 三VERIFIED均0，TRACKS为空；顶层默认560'd0 | 未配置业务路径，禁止播放，不代表硬件已就绪 |
| [offline-test.json](../../assets/templates/sc520-card-recognition/audio22/offline-test.json) | 三测试开关1，35槽0x1201～0x1223 | TEST ONLY；真实UART逻辑的仿真与路由探针，号码不是模块实际曲号 |

准备脚本只在新构建快照中进行上述明确替换，并保存profile.json；当前顶层默认保持0。探针以原真实视频时钟综合和布局布线，不能拿禁用后被裁剪的资源当音频通过。资源与时序只对这组确切合成映射有效；实际TRACKS若采用其他值或次序，综合优化可能变化，必须重新构建核验，不能直接沿用本探针预算。候选C18/D15/E12在D0117实际IO中未占用，本轮仅作为试验pad约束；连接器、1脚、电压、外部时序未核准，这里不提供接线表。

## 接口与时序

`pixel22_audio`全部业务端口位于HDMI域，clk=75MHz（真实工程）、tick_1ms使用已有S_p14_tick。reset_n来自与pipeline相同的S_rst_n && S_hdmi_rst_n；自身两级reset_pipe与原pipeline显示复位同沿释放。K4和其他上下文撤销只连接audio_cancel，不能复位播放器或清掉不确定故障。

| 端口 | 位宽/方向 | 含义 |
|---|---|---|
| audio_event_valid/kind/item | 输入1/3/4位 | 原业务已经确定的名称、问题、反馈与提示事件 |
| audio_cancel | 输入1位 | 取消旧上下文；原K4可在下一拍产生逻辑206重置提示，保持原控制语义 |
| uart_rx/busy_async、uart_tx | 输入1/1位、输出1位 | 冻结播放器真实串口和BUSY；不替换成mock |
| audio_idle/audio_fault | 输出1/1位 | 返回业务推进/故障；fault时idle=1不能证明物理静音 |
| initialized/queue_overflow | 输出1/1位 | 播放器初始化和队列溢出状态 |
| reset_released | 输出1位 | 第二级显示域复位释放，用于核对共同复位周期 |
| audio_state | 输出3位 | 0未配置，1初始化，2可用，3待播/播放事务，4故障 |

状态3由initialized && !audio_idle判断，文案“语音播放中”包含已排队、启动和播放阶段，不能单凭该文案宣称扬声器已出声。故障优先于initialized/idle，未配置优先显示“语音未配置”。

新compositor一次采样31位`frame_state={audio_state[2:0],business_state[27:0]}`，在原输入帧首取样；[30:28]是音频，[27:0]逐位保持D0117业务定义。六行诊断仍由原诊断模块单独拥有报文快照，没有增加800位重复暂存。处理与原图都保持N沿输入、N+5沿后输出，共六寄存层；K3在0/1切图、问答跳题，K1同拍优先及K4恢复原图不变。

WB/tone/54拍采集计算、960×480区域、256旋转模板、题库计分、I2C核心及Logo尺寸位置均不改。新显示标识D0220只用于隔离测试证据，不是下载版本。

## 软件资格

[软件总审](../../evidence/sc520-card-recognition/audio22/software-validation-v2.json)绑定十二轮输入快照和原生退出码，正常44场景/12,199,365检查/0错；四个实际DUT输出注错各native1/恰1错，四个500ns提前停止各native2/done0。602项当前输入/输出引用、763保护文件和旧158字形一致。

| 测试 | 正常结果 | 主要证据 |
|---|---|---|
| business | 19场景/54,448检查 | 当前items14合并、真实队列/播放器/9600 UART、五状态像素；探索去重、重播、问答、取消、K4不清故障、错tag、队列满、BUSY不一致、迟回/坏校验/无回应、初始化失败和停流 |
| pipeline | 5场景/807,474检查 | 实际1280×720 RGB96、256模板、CDC、当前业务→真实UART；空场重武装、苹果120A测试号、两次重播、问答计分一次、坏帧/停采、共同复位 |
| default | 3场景/8,328检查 | 正式三门控0/空映射实际接回当前业务，串口全过程零帧，探索/重播/切图/问答一次计分及反馈推进、K4正常；真实状态0进入renderer |
| render | 17场景/11,329,115检查 | 当前业务和四键、六层像素及旁带、全720p原图/处理/初始化/故障、六行诊断失效恢复 |

UART模型只通过实际位流和BUSY响应，不读取DUT状态来决定模块响应；测试检查器可以观察事务tag。wrong-tag单独向队列接口注入无关tag，监视器只在该明确注入拍排除“真实播放器tag匹配”断言，队列必须保持活动。负向pipeline修改DUT物理曲号输出，独立UART模型实际收到错误曲号后被检查器拒绝；不是改期望答案。

四幅实际PPM与独立golden逐像素一致，[预览目录](../../evidence/sc520-card-recognition/audio22/preview-v2/)含原图未配置、处理图初始化、问答播放和故障状态。真实UART测试用960kHz时钟/真实9600波特以缩短仿真；pipeline保留实际RGB几何与256模板，该pipeline用例的display_clk同为960kHz；独立render用例为75MHz。硬件75MHz资格由整机探针单独验证，不把仿真时钟当真实HDMI速率。

复现命令均在本worktree，Python为`C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`：

```powershell
python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-audio22.py --test business
python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-audio22.py --test render
python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-audio22.py --test pipeline
```

default另用`simulate-audio22-default.py --test default`。每类另带`--negative`、`--watchdog-probe`。原生退出和快照由runner逐轮保存；最终选取路径见软件总审。旧声明错误、超范围延时常量、错tag监视器与溢出后立刻复位截断UART的失败尝试均保留，最终资格只绑定修正后的TB；音频核心无修改。

## 物理探针与尚未放行事项

实际启动命令：`pwsh -NoProfile -File fpga/scripts/sc520-card-recognition/build-audio22.ps1 -RunId 6a50b220`。101源码引用/354输入独立冻结；本轮settings仅到opt_route，bitgen函数和命令双重拒绝，结束后扫描新目录不得存在bit。

[综合ROM绑定](../../evidence/sc520-card-recognition/audio22/rom-proofs/220-v1/bindings.json)和[证明](../../evidence/sc520-card-recognition/audio22/rom-proofs/220-v1/proof.json)确认39ROM、102400模板字/125独立BDD、3072字体y输入、640Logo选择真值。[最终拒收分析](../../evidence/sc520-card-recognition/audio22/probe-rejection-v2.json)确认39路由ROM、24条同步链、四mailbox、I2C/音频内部检查通过，但全局SWNS −2.045ns、STNS −1617.371ns，不能资格化。保持余量+0.020ns、HTNS0；19144 LUT6/21592 REG/19686 slice/107 ERAM/22 DSP。具体失败路径和保功能方案见[时序优化提案](audio22-timing-proposal.md)。

当前主七文档快照使用`audio22/coordinator220-v3/review.json`，逐SHA绑定D054/D055真实登记。v1/v2保留为D051及D052/D053历史。快照脚本第一次误在`display17/coordinator220-v1`新增同名文件，保留为错误路径历史，未改原D0117文件；正式T022审核只使用audio22目录版本。

原`6a50b220`综合exit0、布局完成，路由进程消失但没有原生退出或结束报告，因此只记中断，不能判布线通过或失败。`route220-v1`在启动TD前被CRLF配置行检查拒绝，未重跑TD。`route220-v2`于11:07:17后再次失去TD及父进程，没有原生退出/结果；[中断观察](../../evidence/sc520-card-recognition/audio22/route220-v2-interruption.json)保留真实状态，未猜定原因。当前`resume-audio22.ps1 -ParentRun 6a50b220 -ResumeRun route220-v3`在本聊天exec会话继续从原place.db恢复路由和报告；settings仅将start_step由opt_place改为opt_route，结束仍是opt_route。实际进度日志为`builds/route220-v3/phy_1.stdout.log`；不存在的phy_1/run.log不能作为判断依据。最终需读取父脚本写出的result/stages/failure及原生TD记录；v2旧会话退出码未知。

[接续核验](../../evidence/sc520-card-recognition/audio22/handoff-review-v1.json)已复核97个遗留文件、763保护、602软件引用、354输入及v2的86恢复副本；没有重跑仿真、综合或布局。X/Y及v2中断遗留的Z目前保留：TD GUI仍在运行，窗口标题与命令行未提供工程路径，不能确认其没有别名依赖。v3实际映射由恢复脚本在空闲盘符中选择并负责finally清理，活动路由期间不得解除。解除映射不代表删除真实构建目录。

本轮只交离线源码、测试和资源时序证据；无新的delivery或用户下载步骤。后续由主结合D0117显示结果、实板针位/1脚和电平、真实媒体TRACKS及BUSY结果，再决定是否生成可下载候选。C002偏色尚未修复，外部TX/RX/BUSY时序、CRC/ECC内容、DDR图与采集帧精确对应、真实声音和整机长测仍未验。

路由已在2026-10-16 16:13原生exit0结束，result/stages与报告完整，ChangedInputs为空且未生成bit；W映射已由父脚本finally解除。原严格终审实际exit1拒绝全局负余量，没有生成合格probe或integration-manifest。随后独立收集拒收证据，所有非全局时序子检查通过；恢复解析仅修正单对象stages和等值UTC末尾零，未放宽任何时序/复制/来源条件。

本次实际执行的拒收证据命令（产物已存在；重新执行须选新的output路径，保留历史）：

```powershell
python -B -X utf8 fpga/scripts/sc520-card-recognition/inspect-audio22-rejection.py evidence/sc520-card-recognition/builds/route220-v3 --bindings evidence/sc520-card-recognition/audio22/rom-proofs/220-v1/bindings.json --coordinator-review evidence/sc520-card-recognition/audio22/coordinator220-v3/review.json --output evidence/sc520-card-recognition/audio22/probe-rejection-v2.json
```
