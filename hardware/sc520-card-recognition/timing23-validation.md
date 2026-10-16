# T023：同周期复位分区与诊断译码验证

负责人：01a144c7-e802-7272-a29d-a8159f5ec84b /root。工作树为
`E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition`，
分支 `task/sc520-card-recognition`，增量审核起点
`9f670bc80f07ea178fa6a1787683bde7ca60b9d3`。

实施依据为主仓库 D057，D059 更新接续负责人。旧 T022 的物理拒收、D055
软件接受和 D0117/D0116 证据保持。最新主文档封存见
`evidence/sc520-card-recognition/timing23/coordinator230-v1/review.json`。

## 实现与合同

`timing23/pixel23_pipeline.v` 保留原 capture_reset 的两级链，增加九个
preserve 第二级寄存器。所有第二级均从同一 capture_reset[0] 取样，
使用同一 capture_clk 和异步断言源。释放仍在原第二个时钟沿，分别驱动采集、
场景预处理、积木、形状保护、积木确认、卡片确认、匹配器、颜色诊断和结果汇合。
剩余公共逻辑继续使用原第二级。

`pixel23_color_diag_osd.v` 在原 N 沿寄存行、列、字内坐标，六行字符选择
各自组合译码，在 N+1 沿寄存诊断 RGB。`pixel23_compositor.v` 保持原六层，
N 取样、N+5 沿后输出。800 位诊断快照仅一份，原六行字段、字形、帧首新包、
失效立即撤销和下一帧恢复语义保持。

54 拍 ISP、256 模板、Logo、四键/计分、真实 UART/队列、原厂 DDR 和原时钟保持。
新增 SDC 只有十条精确第一至第二级 2 ns max-delay；旧例外原样保留。
正式 overlay 的三个 VERIFIED 为 0、TRACKS 空；本次构建使用独立合成测试配置。
本阶段为离线探针，不生成 bit。

## 软件证据

入口：
`evidence/sc520-card-recognition/timing23/software-validation-v1.json`。

五组 render/pipeline/reset/business/default 各有正常、实际 DUT 输出注错、
500 ns 提前停止，共 15 轮资格成功。正常共 51 场景、28,685,263 检查、0 错误。
五个注错均原生 exit1/errors1/injected1，五个提前停止均 exit2/done0/errors0。
这些负向资格验证了检查器拒绝错误/不完整运行。

| 正常组 | 场景 | 检查 | 错误 |
|---|---:|---:|---:|
| business | 19 | 54,448 | 0 |
| default | 3 | 8,328 | 0 |
| render | 17 | 11,329,115 | 0 |
| pipeline | 5 | 807,474 | 0 |
| reset | 7 | 16,485,898 | 0 |

复位测试覆盖七个完整 720p 帧、不同释放相位、时钟停止时异步断言、
原第二沿恢复、坏 EOF/恢复、元数据错误和停采超时；
5,196,083 复位沿及 103 项业务/800 位 mailbox 稳定性检查通过。

四组既有独立 oracle 仅更名 DUT/测试顶层；872 当前输入/输出引用和
763 保护文件 SHA 一致。四幅 1280×720 输出逐像素等同冻结 golden，
目视确认全部诊断行、Logo、原图/处理、计分/音频状态和失效红色诊断。
预览位于 `timing23/preview-v1/actual-0-timing23.png` 至
`actual-3-timing23.png`。

原可选端口未连接告警仍有记录，正常 render 无告警。首次 reset 测试因变量
声明位置编译失败，修正测试声明后通过，失败目录
`runs/timing23-reset-normal-20261016-211859-380c9162` 保留。

完整原生命令、ModelSim 10.7 环境、源/快照/输出 SHA 和退出状态在各
run-manifest.json。运行入口为 bundled Python 的 simulate-timing23.py
及 simulate-timing23-extended.py；后续复现应产生独立新运行目录。
start-timing23.py、prepare-timing23-tests.py 和 extend-timing23-tests.py
是已执行的创建脚本，不能覆盖当前证据重放。

## 综合与 ROM

唯一新构建：`evidence/sc520-card-recognition/builds/6a50b230`。
实际命令：`pwsh -File fpga/scripts/sc520-card-recognition/build-timing23.ps1 -RunId 6a50b230`。
363 输入哈希、105 工程引用。原生 syn_1 exit0、结束标记和阶段成功日志齐全。

`reset-synthesis.json` 证实原一级及十个独立第二级保留，同源/同域/异步断言
及分区负载符合要求。本机 TD SWUG106 §4.2.14 的 preserve 属性已由实际网表核实。

初始 AL_MAP 负载数为 226/197/2480/346/185/52/51/312/1816/2027。
复读端口方向后，LUT 的 c 是输入，场景支路修正为 2481；其余一致。
原报告保留，最终审计另列精确 pin 统计。综合 pin 数不能直接与旧物理 fanout
2448 比较，尚不据此宣称最大复位负载下降。

`timing23/rom-proofs/syn230-v1/proof.json` 和 bindings.json 绑定 39 ROM：
102400 旋转模板字、125 独立 bank/class BDD、640 Logo mux 真值，以及字库
1024 行坐标。新坐标别名按实际 Q/D 和仅一层寄存关系证明，未改 RTL 或快照。
ROM 内容/选择综合证明不替代实际路由连接审核。

## 物理审核

本次唯一构建于 2026-10-16 22:27 完成，syn_1/phy_1 均原生 exit0，
输入变化为空，结束标记齐全，无 bit。原始报告和数据库保留，
没有重新综合、布局或路由。

| 指标 | 本次实际结果 |
|---|---:|
| Setup WNS / TNS | +0.102 ns / 0 |
| Hold WNS / TNS | +0.020 ns / 0 |
| STA 覆盖率 | 96.36% |
| LUT6 / REG | 19,163 / 21,801 |
| slice | 19,870 / 21,216 |
| ERAM / DSP | 107 / 22 |

`physical-audit-v2.json` 原生审计 exit0，15 项子审计全部通过：
39 ROM、原 24 同步链、新增十路复位、四 mailbox、全部所报 I2C/音频路径、
363 构建输入、软件原始证据及 763 保护文件。全球聚合时序和原时钟下的
setup/hold/recovery/removal 见证均按原标准通过；未覆盖路径、外部电气
和硬件仍不在本资格内。

形状 ROM 三个位的物理地址名出现 `_dup_4/_dup_6/_dup_3`。
`address-proofs/routed230-v1/` 使用未修改的厂商 FF/LUT/SCLK 模型，
独立遍历十一输入叶及前态/CE/reset 共 16,384 行：
正常 475,190 检查零错，真实输出注错 475,191 检查恰一错，
500 ns 早停 done0/native2。适配器只对本次网表和这个 ROM 的 addra/addrb
替换这三个已证明别名，其余位与常量逐位保留。结论限共同复位建立之后，
不包含厂商配置窗口、SDF 或整个网表等价。

TD 的寄存器集合可能同时选中一个 LSLICE 的两个 FF。
新报告逐条解码实际 clk2q 的 oqa/oqb，再映射网表，分别保留本支路与
同单元附带路径。十路物理源网扇出依次为
141/133/1415/237/98/31/29/179/1219/1354，不能与综合 pin 数混用。
原失败场景支路现在 recovery 最小 +1.682 ns；所有支路本 Q 路径均为正。
最长诊断分支源网延迟 9.173 ns、recovery +0.183 ns，仍如实保留紧余量。

首次 `physical-audit-v1.json` 保留为失败历史：全球时序已正，但 ROM 别名、
I2C/ADC 换行精确比较失败。I2C 两文件与 ADC 已证明仅 LF→CRLF，
其他字节完全一致，审计器只接受这项实际转换；没有改 RTL、约束或构建。
v1 原程序 SHA 保留，未能精确重构旧源，故不把当前源伪标为 v1；
最终 v2 程序已按报告 SHA 原字节归档到 `audit-source-v2/`。

大原始 STA 和 v1/v2 完整审计保留本地；提交的
`physical-audit-compact-v1.json` 只合并重复存储的复位路径，
往返重构与 v2 每个字段一致，并非另一次物理运行。
最终封存入口为
[validation-manifest-v1.json](../../evidence/sc520-card-recognition/timing23/validation-manifest-v1.json)。

工具进入 opt_route 后只生成审计报告，bitgen 被脚本显式拒绝。只管理本次自身
V 临时映射，finally 校验映射未改变后解除；XYZ 和用户 TD GUI 保持。
本阶段等待主对话审核。正式三门控仍为零、TRACKS 空；
本次离线成功不升级未知针位、电平、真实曲号、BUSY、颜色或硬件资格。
提交本任务增量、共享登记/index/-Check、finish-task 检查后，
向当前主 01a14468-1741-70a2-aea6-757eb183382f 通知一次。
