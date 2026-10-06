# SC520 问答视频集成验证报告

负责人：对话 `01a11124-e100-75e2-9e85-9f9686e23c73`，协作代理 audio/control_tests/preview_keys。工作目录 `E:\juan\FPGA\worktrees\anlogic-kids-learning-machine\sc520-fixed-roi`，分支 `task/sc520-fixed-roi`，基础提交 `f609426044982c986b54e999866be9f4c1af2682`；未提交、推送、合并或下载硬件。

## 状态

问答视频集成的软件验证与 TD 6.2.1 构建已完成，**等待主对话审核，硬件待验证**。最终四项正常仿真合计 119711257 次逐周期/逐像素检查、零错误，该数字不是独立场景数量；四项负向各捕获一个预期错误且退出 1。旧三份候选和既有识别/问答控制输入的 883 项保护哈希无差异。249 份工程输入及两份问答 RTL 的复制来源见 [origin.json](origin.json)，新工程的三份引用清单见 [project-manifests.json](project-manifests.json)。

## 实现范围

摄像头 RGB 进入既有中心区颜色形状识别，识别结果驱动 10 题问答，HDMI 顶部/底部显示题号、分数、题目、反馈、来源和模拟状态。新增帧首整体状态快照、75 MHz 独立毫秒时基、坏帧撤销答题资格、模拟播放握手和两次启动模式脉冲；旧 PLL、识别阈值和视频输入链保持原样。接口细节及存在检测限制见 [local-interface.md](local-interface.md)。

候选复位后约 1 秒进入探索，约 2 秒进入问答。之后依靠摄像头结果作答；板上重播/跳题/清零尚无实体键。当前音频为无声模拟，不代表真实播放器功能。候选中的两次自动模式脉冲仅供实验，非最终产品启动规范。

## 仿真

工具 `D:/modeltech64_10.7/win64/vsim.exe`，ModelSim SE-64 10.7。统一命令 `pwsh -File fpga/scripts/sc520-quiz-video/simulate.ps1 -Testcase <runtime|osd|video|full>`，负向添加 `-Negative`。每轮独立输入快照，保存执行命令、前后输入及输出 SHA-256、`summary.json`、`run-manifest.json`、日志和波形。最终摘要以仿真停止后读取的 `summary.json` 为准。

| 测试 | 正常检查数 / 错误 / 退出码 | 负向检查数 / 错误 / 退出码 |
|---|---|---|
| runtime | 450065 / 0 / 0 | 450065 / 1 / 1 |
| osd | 8320089 / 0 / 0 | 8320079 / 1 / 1 |
| video | 28339538 / 0 / 0 | 28339539 / 1 / 1 |
| full | 82601565 / 0 / 0 | 82601561 / 1 / 1 |

八次 `done=1`、`ChangedInputs=[]`，ModelSim 工具编译/运行警告均为零。负向差异来自实际故障检查和是否导出图像，不要求正负检查总数相同。下列为最终明确选择，早期运行未被混入：

- runtime：[正常](runs/runtime-normal-20261006-222026-6b8c8b66/run-manifest.json)、[负向](runs/runtime-negative-20261006-222336-317f0009/run-manifest.json)。
- osd：[正常](runs/osd-normal-20261006-222336-18ed6cf4/run-manifest.json)、[负向](runs/osd-negative-20261006-222515-35cee85f/run-manifest.json)。
- video：[正常](runs/video-normal-20261006-233313-bae91a0b/run-manifest.json)、[负向](runs/video-negative-20261006-233455-cee7abcc/run-manifest.json)。
- full：[正常](runs/full-normal-20261006-233455-5f98e1af/run-manifest.json)、[负向](runs/full-negative-20261006-233455-00c510a2/run-manifest.json)。

runtime 独立验证默认 75000 拍/毫秒、复位、启动模式键以及 ACK/曲终/停止优先级。OSD 覆盖 26 场景、全部字形/内容选择和实际像素；video 小参数从真实合成 RGB 开始，覆盖九类目标、未知彩色目标、持续放置、移走后回答、错题、重播、来源切换、帧中跳题、结束/清零及停视频后的独立计时。最终 video 共 135 帧（含有意构造的坏帧）、11337435 个有效输入像素、99138 项稀疏 UI 检查；覆盖仅 VS、半行、超长行、VS/DE 重叠，坏帧撤销资格且恢复原物体不能再答。full 共 32 帧、29491200 个有效像素、547584 项 UI 检查，保留 1280×720 有效像素并导出五幅完整 PPM。

负向分别破坏一个真实 tick 或输出像素，普通检查器必须发现错误且进程退出 1，不把负向当作 DUT 功能通过。全幅测试缩短了行/帧消隐并加速控制计时，没有验证完整 1650×750/60 Hz、MIPI、DDR 和 HDMI PHY。

## 中间问题和保留证据

1. `runs/video-normal-20261006-221109-c12738cc`：旧 `shape_confirm.v` 的合法 Verilog 名字 `matches` 被 `-sv` 当成关键字，未进入测试。最初工具返回 0，但 runner 因缺完成摘要拒绝结果；不能算通过。
2. `runs/video-normal-20261006-222507-bc086ce7`：Verilog 模式下新包装器先用后声明 `coord_valid/coord_sof`，编译返回 2。已同步修复生成器和新包装器的声明顺序；不改原识别源码。
3. runner 对 `.v` 使用 Verilog、TB 使用 SystemVerilog，并增加 Tcl `catch` 传播失败退出码。旧 OSD 首轮结果保留，最终使用修复 runner 后的正常/负向组合。
4. `builds/quiz-video-20261006-223935-b2a51c39`：TD 首次综合受路径长度限制，将磁盘存在的旧 IP 文件报为缺失，未生成 bit。改用任务证据目录内更短的独立构建路径，旧失败日志保留。
5. 独立审查发现坏帧与无目标结果混淆。同一扩展测试在旧包装器运行 `runs/video-normal-20261006-231143-7eeacd66`，实际复现 10 处错误：三项根因分别是坏帧未撤销已有资格、坏帧重新累积出资格、恢复原物体发生额外作答；其余七项为计分/题序级联，输入变化为零。新包装器增加原始视频协议健康门控与坏帧立即撤销，旧识别器和控制器字节不变，保持同一测试复测。
6. `b/b7784ad3` 是健康门控修复前的中间构建，虽然综合/布局布线通过且 Setup 119 ps、Hold 20 ps、TNS 0，仍不可作为最终交接候选。它的源码快照、bit 和报告完整保留，最终使用修复后的独立构建。
7. `runs/video-normal-20261006-231919-c42bd8de` 用同一坏帧测试验证修复，10 处错误归零。最后为保证日志与机器摘要一致，TB 在 `test_done` 后停止检查，避免结束等待期间多计两项空白检查；增加长行/VS-DE 重叠输入后重新执行最终四项 video/full 测试，未放宽检查器。

## 画面

[OSD 像素说明及视觉核查](osd-notes.md)。预览由仿真实际 PPM 无损转 PNG；原 PPM、PNG 与输入清单哈希均保留。早期 OSD 预览绑定其首轮运行，相关 OSD RTL/TB 未变，不能冒充后续全幅视频画面。

最终全幅预览对应上表 full 正常运行：[题目](preview/full-normal-20261006-233455-5f98e1af/question.png)、[答对加分](preview/full-normal-20261006-233455-5f98e1af/correct.png)、[答错重试](preview/full-normal-20261006-233455-5f98e1af/wrong.png)、[本轮完成](preview/full-normal-20261006-233455-5f98e1af/finished.png)、[清分待机](preview/full-normal-20261006-233455-5f98e1af/cleared.png)。五图均逐像素转换相等并逐张视觉检查，中心 ROI 保留、文字无截断；完成画面上的残留青框来自原检测框释放延迟，清分画面已消失，不宣称检测框瞬间清除。见 [图像哈希清单](preview/full-normal-20261006-233455-5f98e1af/preview-manifest.json) 与 [逐图核查](preview/full-normal-20261006-233455-5f98e1af/visual-review.json)。

![最终RTL仿真的正确答题画面](preview/full-normal-20261006-233455-5f98e1af/correct.png)

更细的范围见 [视频测试说明](video-test-notes.md) 与 [时基/模拟播放器测试说明](runtime-notes.md)。

## TD 构建

仅使用 `D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe`。构建命令 `pwsh -File fpga/scripts/sc520-quiz-video/build.ps1`，每轮先校验输入、复制新快照，再依次综合、布局布线、归档及核验。

健康门控修复后的构建为 [b/8f1b2f6f](b/8f1b2f6f)，2026-10-06 23:25:53（Asia/Shanghai）完成；综合/实现均返回 0，完成标记在本次运行产生，输入无变化。25 份归档及 883 个保护文件核对通过。

| 项目 | 实际结果 |
|---|---:|
| Routed Setup WNS / TNS | 0.132 ns / 0 |
| Routed Hold WNS / TNS | 0.020 ns / 0 |
| 建立/保持违例端点 | 0 / 0 |
| STA 覆盖率 | 96.38% |
| LUT / 寄存器 | 12872 / 14415 |
| Slice / ERAM / DSP | 14994 / 39 / 16 |
| IO / PLL | 58 / 3 |

正时序余量不等于全部约束或未覆盖路径已经审核，STA 覆盖率并非 100%。报告原件：[时序](b/8f1b2f6f/final_timing.rpt)、[资源](b/8f1b2f6f/final_area.rpt)、[构建归档及哈希](b/8f1b2f6f/archive-manifest.json)。

交接候选：[built.bit](b/8f1b2f6f/built.bit)，1789539 字节，SHA-256：

```text
945E6D5FB6FCA2FF252953AF1B989155D2C28BA2A06E663C67F96A08B1AD2334
```

压缩版本为同目录 [built_compress.bit](b/8f1b2f6f/built_compress.bit)，1346033 字节，SHA-256 为 `F698D640ECCEC1FD3DA059D38EAEACB19886EDBF41AD8651A66EA7376E4C8A4D`。它们均未下载或进行真实硬件验收，后续使用前应核对哈希。

综合警告已与旧学习候选对照：严格去重各 97 行，归一化 HDL 行号后 77 项集合相同；物理阶段各 9 项集合也相同，没有新增 quiz 模块警告。原 IP 的位宽、连接、无驱动及继承时钟告警仍保留，不能宣称全工程零警告。详见 [警告对照说明](warning-analysis.md) 和 [原文与日志哈希](warning-analysis.json)。

## 交接边界

没有真实音频、新增实体按键、实物识别准确率、冷启动或长时间稳定性验收。旧三版仅沿用用户报告的手机图片初测，未转为实物通过。卡片识别不在本轮范围。真实播放器资料预计 10 月 8 日取得，未据候选型号冻结任何供电、GPIO 或协议。

主对话需审核局部问答规则、来源/存在证据及候选启动方式，再安排实物验证和真实音频/按键接入。根工作区索引登记代表可追溯交接，不等于技术合并或上板通过。教学入口：[从识别到问答画面](../../../../../learning/sc520-quiz-video/README.md)。
