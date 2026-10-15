# T017：当前业务、处理图、同帧诊断与安路Logo整合

负责人：01a14030-32d9-78f2-b274-91a370cc9ff0 /root，按D047/D048接续原开发。基线68e2b4d；显示来源edaced3542a4a056aa90397aefadb45e279e69e2。D0117的软件与物理审计已通过，等待主对话审核；未上板。独立工程`fpga/custom_project/sc520-pixel17`，综合6a50b117、物理phy117-v1。

## 使用与分工

- K1照旧切换待机、探索、问答；K2照旧重播。待机/探索的K3切换原图与全画面颜色分割，问答的K3只按原语义跳题；完成页K3不切图。
- K4优先清分并请求原图；K1与K3同拍时只切业务模式。输入显示帧首接受显示请求，界面显示已生效的原图/处理图。K3/K4与帧首同拍时，该帧直接采用请求优先级计算后的模式。
- 仅消费原有消抖脉冲；显示切换不产生识别flush、计分、重播或音频事件。音频未接入时明确显示“语音未接入”；没有新GPIO、长按或真实播放器。
- D0116及原两图继续作为光学对照；本阶段不要求用户为显示接入重刷或重做两图。相机、WB/tone、54拍采集RGB、曝光/增益、分类阈值和256模板不改变。

## 实际链路

`预OSD HDMI RGB/XY/DE/HS/VS/FS → processing → 当前字体/诊断/导框 → 同步Logo四层 → HDMI TX`。

输入N沿采样，输出N+5沿后出现，共六寄存层。前两层分别为处理支路和字体/诊断/video寄存；后四层保持已审同步Logo。原图/处理图都走同一路径。输出带对齐的坐标、DE、HS、VS、帧首、模式、颜色分类和三种叠加标志；实际TX接VS/DE/RGB，未增加不存在的HS输入。

`items14_system`增加兼容的RENDER_ENABLE参数及28位render_state，默认仍走原业务面板；新工程明确关闭旧面板并断开旧已混合视频输出。render_state直接来自当前业务寄存器及撤销门控，result_healthy保持原事件更新。compositor在原输入帧首只锁一次该状态，处理后一拍使用新快照；没有从旧osd_*快照再锁一次。

六行诊断模块仍独占800位报文快照，在原输入帧首取样，处理后一拍的坐标供其渲染。未新增一份800位暂存。新鲜位在帧内失效后锁存失效，随后新数据不能恢复旧快照，直到下次输入帧首重新取样。F号依旧仅绑定采集报文，不保证与DDR背景图同帧；E/B/Q等仍为独立上下文。

识别和可见导框共同使用顶层P17_SCENE=(160,120,960,480)。Logo(1008,24)，146×94；上方三行文字限制在x<1008，实际题号/分数位保留，处理模式标签在第二行。反馈和目标文字保留在底部面板。唯一当前字体沿用原152字形ID和位图，新增6字形及5句提示，没有编译显示分支的frozen0109副本。

## 来源与验证入口

- [启动保护与Git提取记录](../../evidence/sc520-card-recognition/display17/start.json)：155个冻结构建/交付/两图文件，3530接手源码/素材；9个显示依赖逐字节来自edaced3。
- RTL位于`fpga/rtl/sc520-card-recognition/display17`；共享业务和字体仍在items14；旧D0116 overlay保持原样。
- `simulate-display17.py --test system`及`--negative`、`--watchdog-probe`串接真实当前业务、键路由、新渲染器，覆盖14类、20题计分、撤销/停流、多键/问答完成页、四幅720p、帧中变更与失效恢复。逐像素期望来自独立文字行、当前位图资产及官方RGBA，不调用DUT逻辑。
- 旧默认`simulate-items14.py --test system`和256模板`simulate-pixel14.py --test scene_system --rotation-variants 256`确认兼容路径。最终5轮资格正常共107场景11,342,730检查零错；默认业务10/802，新渲染17/11,329,115，分类80/12,813。最终RGB注错native1/恰1错、500ns提前停止native2/done0按预期拒绝，见[软件审核](../../evidence/sc520-card-recognition/display17/software-validation-v1.json)。四幅实际PPM与独立golden逐像素相同，4幅预览都已目视检查。
- 构建命令：`pwsh -NoProfile -File fpga/scripts/sc520-card-recognition/build-pixel17.ps1 -RunId 6a50b117`，335输入/92源码引用独立冻结。综合exit0，原布局在21:14:32中断且无原生退出结果；`resume-display17.ps1`复制冻结DB/源到独立phy117-v1续跑物理，原目录保持。没有为中断重复综合。
- 新39ROM的地址/选择及内容已按本版网表证明：[绑定](../../evidence/sc520-card-recognition/display17/rom-proofs/117-v1/bindings.json)、[证明](../../evidence/sc520-card-recognition/display17/rom-proofs/117-v1/proof.json)、[综合内容审核](../../evidence/sc520-card-recognition/display17/rom-content-syn-v1.json)。含25模板bank/102400字/125独立BDD、新字体3平面的3072组y值，以及Logo8 index/2 palette平面和640组选择真值；最终路由签名、地址、输出与控制连接均已通过本版物理审核。

## 最终物理审计与交付

[物理审计](../../evidence/sc520-card-recognition/display17/candidate-audit-v1.json)核对335项当前输入及冻结快照、76份恢复复制文件；综合没有重跑。原物理于2026-10-15 21:47完成，综合/物理均原生exit0。接续审核首次准确拒绝已过期的主文档v1快照；主233543批补齐7份SHA后，另建[coordinator117-v2](../../evidence/sc520-card-recognition/display17/coordinator117-v2/review.json)并通过。历史快照及失败日志保留，未放宽审核条件。原result.json的TimingQualified=false是构建时待审初值，最终资格见独立审计，不回写历史结果。

| 项目 | 本版结果 |
|---|---|
| 建立/保持 | SWNS +0.104 ns，HWNS +0.020 ns，双TNS 0；原STA覆盖96.23% |
| 资源 | LUT6 18472，寄存器21164，slice 19066/21216，ERAM 107/108，DSP 22/40 |
| 相对D0116 | LUT6 -3，寄存器 +203，slice +10，ERAM +10，DSP不变 |
| 同步链 | 21组逐Q/D核对，meta→sync 2 ns预算及hold通过 |
| 四组mailbox | 业务80、诊断106、I2C 28、颜色762个保留位；最大传播1.909/1.684/1.418/2.974 ns |
| I2C内部覆盖 | 49寄存器cell均回溯父PLL时钟；1578条路径，setup/hold/recovery/removal最小1.383/0.075/39.296/0.109 ns |

mailbox逐位检查的是独立10 ns传播上限，不称异步setup/hold或MTBF通过。两条既有critical warning保留：相机时钟混合扇出、1条时钟使用局部布线。ERAM仅余1块，后续整机音频接入须重新核资源与实际时序。

唯一候选：[sc520-pixel17-0117.bit](../../evidence/sc520-card-recognition/delivery-0117/sc520-pixel17-0117.bit)，1,789,539字节，SHA256 `E907703E4563C4E6DB4FB4FC99C3CBB8C7BFAE52830265576460A1CA4B1F0F1C`；[manifest](../../evidence/sc520-card-recognition/delivery-0117/manifest.json)绑定原bit、软硬审计、指南和预览。D0116的155保护文件、9份edaced3导入及152个旧字形保留。接续独立回读244项软件输入/输出/图引用，四幅720p实际PPM与golden及预览逐像素相同；没有重复ModelSim或TD。

接续实际审核命令（工作目录为本worktree，Python为Codex bundled Python 3.12）：

```powershell
python -B -X utf8 fpga/scripts/sc520-card-recognition/snapshot-display17-coordinator.py --tag coordinator117-v2 --owner '01a14030-32d9-78f2-b274-91a370cc9ff0 /root'
python -B -X utf8 fpga/custom_project/sc520-pixel17/tools/audit-display17-candidate.py evidence/sc520-card-recognition/builds/phy117-v1 --bindings evidence/sc520-card-recognition/display17/rom-proofs/117-v1/bindings.json --coordinator-review evidence/sc520-card-recognition/display17/coordinator117-v2/review.json --software evidence/sc520-card-recognition/display17/software-validation-v1.json --output evidence/sc520-card-recognition/display17/candidate-audit-v1.json
python -B -X utf8 fpga/scripts/sc520-card-recognition/seal-display17.py --audit evidence/sc520-card-recognition/display17/candidate-audit-v1.json
```

以上是本次已用输出名；复核应指定新的快照/审计输出，不覆盖旧证据。封存脚本拒绝覆盖已有交付目录。本次完整解释器路径为`C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`。

## 建议主审核后安排的最少上板步骤

当前仅是待审核建议，由主对话统一发布可执行步骤。保持相机、照明、接线不变，只使用PROGRAM_SRAM临时加载上面的交付bit，先核SHA；本批不固化Flash、不接音频。

1. 检查启动为原图、D0117、视频持续刷新；Logo、题号/分数、六行诊断及960×480导框完整。保留一张全屏照片。
2. 待机与探索各用K3切换原图/处理图，标签与实际画面一致；观察边界残影、持续撕裂和卡住。K1换模式后显示选择保持。
3. 进入问答后K3仍只跳题，完成页也不切图；从处理图按K4应回待机、清分并恢复原图。K2保留重播业务语义，本版没有真实声音。
4. 反馈版号、步骤/按键顺序、实际标签和异常位置，另保留一张处理图照片；有撕裂/停流等动态异常再补短视频。不重复D0116两图或完整计分验收；光学比较继续用D0116。

## 边界

处理图为显示域的重新判色，不反馈识别，不代表色彩或IR问题修复。用户报告模组无IR-cut，原白纸预WB裁切和tone红命中归零证据仍有效；本次不重复索取。外部SDA/RC/使能传播、传感器电气、CRC/ECC内容、DDR背景与采集帧精确身份、整机长测仍未验。HardwareValidated=false、AudioIntegrated=false、FullSystemTimingSignoff=false。未执行下载、Flash、真实COM、Git推送或合并。
