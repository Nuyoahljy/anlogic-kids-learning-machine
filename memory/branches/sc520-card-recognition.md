# 五类卡片识别独立开发

- 任务 ID：sc520-card-recognition
- 状态：等待主对话审核
- 负责人：本轮 SC520 后续开发对话 /root；前阶段负责人 01a120ad-c540-7f11-af3b-6360b8cee2e9 /root
- 分支：task/sc520-card-recognition
- 基础提交：f609426044982c986b54e999866be9f4c1af2682
- 开始时间：2026-10-10T19:31:42+08:00
- 结束时间：2026-10-10；精确运行时间见validation.json和各run-manifest.json
- 工作目录：E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition

## 目标与验收条件

用户授权在等待DFR0534快递与四键实物验证期间继续下一步，推进五类卡片识别独立软件开发。基于现有prep-v1图稿构建32x32二值模板、带全帧健康检查的固定方形ROI取样、串行像素距离匹配、unknown拒识和稳定滤波。只声明固定摆位下的软件模型验证，不把原图或人工变换当相机实测准确率。

## 已读文档

共享AGENTS/README/FILE_INDEX、最新DFR0534及四键交付记录；主仓库和本工作树AGENTS、总记忆/计划/任务/决策/接口，架构/素材约定，future-assets和prep-v1卡片说明，实际hdmi_quiz/detection_adapter/quiz_control/quiz_content。旧主文档仍有SC500/DFPlayer等历史状态，留主对话维护。原new-task-worktree脚本要求改动并清理主仓库，当前主仓库有他人未提交工作且无此任务日志，因此用git worktree add创建隔离新分支并在本工作树建立日志；没有修改主仓库文件。

## 修改文件

仅本任务fpga/rtl、sim、scripts下sc520-card-recognition目录，assets/templates/sc520-card-recognition、evidence/sc520-card-recognition、hardware/sc520-card-recognition、本日志和共享learning/sc520-card-recognition。已有打印图稿只读，派生物记录源哈希。

## 验证命令与结果

2026-10-10进展：五卡模板与69个软件样本已生成，独立数据检查8组通过、69次中心RGB故障注入全部检出。开发样本比较后选择MAX_DISTANCE40、MIN_MARGIN24、FG16..850；14个负样本全拒、5个标准图接受，但一格平移仅4/20接受。本组用于调参，不是留出验收准确率。

已实现sampler/ROM/matcher/filter/top，补空帧EOF健康拒绝记录。恢复后修复ModelSim只读ini复制、Windows长路径、TB变量笔误和1bit完成标志读取符号。保留全部历史失败输出；初始sim三个目录仅有启动片段，子代理报告vmap失败，不能当成功证据。

最终ModelSim SE-64 10.7正常验证：matcher35场景/29739检查、filter296场景/2370检查、pipeline285场景/16363650检查，合计616场景/16395759检查/零错误。pipeline使用真实320×180RGB输入、69样本各三帧和坏帧恢复；独立检查完整ROI前景、1024采样点、距离、元数据与稳定结果。新增EOF后恰好一个额外空拍的双帧交接，以及source/tag中途变化后两拍内撤销检查均通过。

完整命令：使用`C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe -B -X utf8 fpga/scripts/sc520-card-recognition/simulate.py`，分别传`--test matcher`、`--test filter`、`--test pipeline`、`--test matcher --negative`、`--test pipeline --negative`、`--test matcher --watchdog-probe`。均在本工作树根执行。两个negative分别强制实际DUT输出错误，原生退出1/errors1/injected1；watchdog-probe在500ns提前结束，原生退出2/done0/errors0。runner六次均按各自资格条件返回0，不把注错视为RTL功能通过。

最后执行同一Python的`-B -X utf8 fpga/scripts/sc520-card-recognition/audit-delivery.py`，返回0：回读六个最终运行的输入快照/当前源/输出哈希、三批数据manifest、max40的8组QA以及18项受保护旧文件，全部一致。默认720p参数未跑全幅仿真、未综合或上板。共享登记和Git提交随后在本批交接完成。

## 证据路径

总入口`evidence/sc520-card-recognition/validation.json`；保护基线`baseline.json`；最终运行在`runs/matcher-normal-20261010-200102-0678be96`、`filter-normal-20261010-200102-03f0f316`、`pipeline-normal-20261010-200358-122dc04c`、`matcher-negative-20261010-200113-1756163c`、`pipeline-negative-20261010-200358-6b9af9ea`、`matcher-watchdog-20261010-200113-af9eefde`。每目录保存run-start、run-manifest、summary及日志，快照/work/wlf保留磁盘并按目录登记，避免将编译缓存重复提交。

模板入口`assets/templates/sc520-card-recognition/prep-v1-max40`，其templates.mem SHA256为`49F75A4695A38AFB5290C301C9AB07B538968124A296E7F15711065C85E80C3F`。历史120及首次生成目录保留；默认生成器仍120，复现本阶段须显式`--max-distance 40`。接口与复现说明在`hardware/sc520-card-recognition/README.md`，教学在共享`E:/juan/FPGA/learning/sc520-card-recognition/README.md`。

## 阻塞与风险

尚无此套卡片的相机照片。居中/尺度/光照阈值为实验配置；不提供任意苹果等类别的泛化识别承诺。32x32采样以外的ROI前景另计存在性，白卡与白背景不能区分为物理有无。坏帧、未知和真实空背景必须分开。

默认ENABLE_OUTPUT=0；模块不含停流失活看门狗，帧超时需由上层flush。frame_id只透传不检查连续性。EOF后必须至少一个额外无效空拍；EOF后立即SOF不在支持协议中。动态切源必须满足上层清除约定。完整流水线软件验证不构成720p资源、时序或成像质量证明。

## 待决策事项

不改共享接口。五类结果与现有九类冲突须先拒识或使用显式调试模式，不能默认卡片优先。现有控制与字库仅1..9，10..14整机接入和题序另行审核。

## 建议总文档更新

先审核独立模块与模型证据；确认固定ROI协议、默认关输出、最短帧间隔及超时责任。实际卡片采集、模板校准、仲裁、字库题序及新的整机TD构建完成后再更新主状态。不可将本次616场景通过改写为实物识别通过。

## 下一分支交接

本轮交付独立代码和软件证据；当前四键826966ea及音频b982a64保持原状，用户继续各自验证。无新整机bit、下载、Flash、推送、合并或快递自动监控。

## 2026-10-11 继续开发：帧超时保护

- 阶段状态：等待主对话审核；基础提交 ad106b537a2216e6cfb1d2a4d920fe2cea2cff54，开始时本工作树干净。
- 用户请求：说明验证后的下一步，并继续可并行的软件开发。先完成 card_frame_guard 候选模块，补齐完全停流时旧卡片结果无法撤销的已知缺口。
- 范围：新增独立 guard、针对性 ModelSim 测试、证据与集成说明；不改现有识别器、四键工程或共享接口，不生成新的 bit。
- 验收条件：只有健康完整帧能重置超时；截止边沿与健康帧同时出现时健康优先；超时清除上游并输出一次不可信撤销；持续超时不反复触发；恢复后重新累计三帧；外部 flush 和无事件提前失效可撤销输出。持续 clk 和同域 tick_1ms 是使用前提。
- 资料差异：工作树总文档仍为 2026-09-20，主仓库为 2026-09-27，两者均早于 SC520/DFR0534 分支证据。本阶段沿用已读最新独立交付记录；只在此报告冲突，不回写主文档状态。
- 本阶段文件：新增 fpga/rtl/sc520-card-recognition/card_frame_guard.v、fpga/sim/sc520-card-recognition/tb_card_guard.sv、fpga/scripts/sc520-card-recognition/simulate-guard.py、hardware/sc520-card-recognition/frame-guard.md、evidence/sc520-card-recognition/guard-validation.json；更新任务日志和本任务硬件README；共享learning新增next-stage.md并更新README。
- 实际验证：在本工作树根使用 C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-guard.py，另分别增加 --negative 与 --watchdog-probe。ModelSim SE-64 10.7正常16场景/2432检查/0错误；注错exit1/errors1/injected1；提前500ns结束exit2/done0/errors0；runner三次均返回0。未改代码即一次通过，不以注错结果作为正常RTL通过。
- 证据：runs/guard-normal-20261011-193739-58901528、guard-negative-20261011-193739-7af1cf18、guard-watchdog-20261011-193739-ca45c3a0；各run-manifest保存完整命令、源/快照/输出哈希和实际退出状态。guard-validation.json汇总root回读三次运行的6项输入/5项输出（每轮）及15项旧文件保护基线，均一致。
- 结果：截止tick健康帧优先、连续坏帧不续期、held flush只一次撤销、TIMEOUT_MS=1/5、无事件撤销、候选count空拍保持、真实三帧滤波器同边沿清零及恢复均通过。旧616场景未重跑，原始验证文件保留。
- 限制与待决策：guard只保护完整健康结果中断；DDR继续重复旧帧、整体clk停止、可信采集帧号、跨域与视频接入仍未解决。下游必须把不健康记录及无事件失效适配为不可信撤销，不能仅当空背景；现有quiz_control仅present1/stable0不能清既有armed。默认100个tick阈值、十四类仲裁及接口扩展待审核。
- 下一步：主对话审核本候选和软件证据；在隔离工程推进十四类统一结果/显示/题序/音频事件与诊断画面，随后TD构建、卡片实拍校准和DFR0534实物接入。用户继续验证旧四键bit。root完成共享记录、索引、最终提交；本阶段不合并、不推送、不修改主接口。

## 2026-10-11 并行开发：十四类结果与业务候选

- 阶段状态：等待主对话审核；基础提交 b3bc3784825a7f4364488b68856360b454a742e1，启动时本工作树干净；旧sc520-fixed-roi存在多任务未提交文件，仅读取实际四键工程作来源参考。
- 用户授权：继续下一步开发并行。root负责同帧结果汇合、超时撤销、业务顶层和联调；items14_control负责十四类问答与题库，items14_display负责文字/同步字库/显示，items14_review审查仲裁和测试。
- 范围：本任务items14目录中的独立结果级软件子系统；接入两路完成帧记录，不声称完成相机像素链路或产生可上板bit。旧识别器/guard和四键工程保留，未修改主文档或共享模块接口。
- 候选策略：每路一个待匹配槽，帧号/来源必须一致；双稳定候选冲突拒识；健康空背景只有两路都无前景才成立；坏帧、错帧、溢出、超时等显式撤销答题资格。每轮十题，通过14项题库的起点轮转覆盖全部对象。具体本地接口和策略均待主对话审核。
- 验收：同帧错序/异步到达、冲突、非法编号、不可信撤销、真实空背景重新武装、14类显示与两轮问答/语音事件，以及三子系统联合软件测试，均按下述实际命令完成。
- 修改文件：新增本任务rtl/items14的7个RTL（join、system、control、question_bank、content、font_rom、osd）；4个tb_items14测试、字体生成/仿真/审计脚本及Tcl宏；11项派生字库/文案/参考/预览资产；3份items14接口说明；items14-baseline、validation历史及v2最终汇总、预览总览与20轮独立运行目录。本日志和本任务hardware README更新；共享learning新增items14.md并更新README/next-stage。逐文件绝对路径/哈希见共享批次登记。
- 实际生成：bundled Python -B -X utf8 fpga/scripts/sc520-card-recognition/generate-items14-font.py 两次exit0（同批迭代），152字形/44文案/7图；系统字体只读，未复制。root目视检查苹果/不可信原图及七图总览，文字和中心ROI分离；不称为板上显示验收。
- 实际仿真：同一Python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-items14.py --test join/control/display/system，每类另带 --negative 和 --watchdog-probe，ModelSim SE-64 10.7最终12轮资格全部通过。正常join34/3083、control16/3106、display47/850417、system10/802（场景/检查），合计107场景/857408检查/0错；4注错均实际force输出、native exit1/errors1/injected1；4个500ns提前停止native exit2/done0/errors0。工具编译/仿真无错误。
- 迭代与历史：首轮control normal因test$plusargs把INJECT_FAULT=0当true导致注错，正常资格失败，旧normal/negative保留；改数值解析、保留撤销时TEST来源并补7轮起点循环后重跑。system先8场景，再补问答已排队正答案与K2被新fault阻止、TEST超时后的帧快照；最后把不可信文字断言从共同前缀改为实际名称位置，重跑三模式，旧结果和早期audit保留。总20个运行目录，不混用历史为当前通过。
- 最终证据：evidence/sc520-card-recognition/items14-validation-v2.json；最终system为i14-system-*-20261011-200510三目录，其他九轮确切路径由audit-items14.py固定清单及v2汇总列出。执行同一Python的 -B -X utf8 fpga/scripts/sc520-card-recognition/audit-items14.py --output evidence/sc520-card-recognition/items14-validation-v2.json，exit0；root回读最终99项当前源/快照/前后哈希、60项输出、902项旧文件及5字库输出/7预览一致。早期items14-validation.json为历史，不绑定最终TB。
- 未解决：这里只接收完成帧记录，未接原RGB/摄像头/HDMI PHY/真实UART。旧block detector的hold、帧结算及card EOF需新适配；帧号必须来自真实采集，不能靠重播旧图的新标记骗过新鲜度检查。持续clk、跨域、100ms实时时基、TD ROM映射/资源/时序与实物卡片效果均待验证。双候选拒识和十题轮转仍是待审核本地策略。
- 建议主对话动作：审核本候选接口与软件证据后，建立隔离视频诊断工程，接入真实两路帧记录/预OSD像素及同步清除，完成TD6.2.1再给用户诊断bit实拍；DFR0534实测后接真实声音。不将本次107场景写为14类实物或整机通过。root完成共享登记/索引及本地提交，未合并/推送。
