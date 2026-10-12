# 五类卡片与十四类采集视频开发

- 任务 ID：sc520-card-recognition
- 状态：等待主对话审核
- 负责人：本轮 SC520 后续开发对话 /root；前阶段负责人 01a120ad-c540-7f11-af3b-6360b8cee2e9 /root
- 分支：task/sc520-card-recognition
- 基础提交：f609426044982c986b54e999866be9f4c1af2682
- 开始时间：2026-10-10T19:31:42+08:00
- 结束时间：2026-10-12；精确分阶段运行与恢复审计时间见各manifest、validation和recovery-audit.json
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

## 2026-10-11 下一步并行开发：采集像素与视频诊断

- 阶段状态：进行中；基础提交 a698a53e5dcf62819e2045b687d6cf386352d121，开始时本工作树干净。用户明确原四键bit和DFR0534实物继续待验证，允许继续软件开发。
- root负责像素协议/真实采集标签、联调与统一证据；video_block审计并实现本帧积木适配，video_build负责隔离工程与TD路径，video_provenance审查采集/DDR/跨域来源。首轮子任务只读，源码分工确认后才写。
- 当前发现：旧识别在DDR显示RGB之后，显示帧号不能证明采集新鲜；旧bbox/shape保持也不能直接作为当前完整帧结果。新候选从真实采集像素建立健康与tag，原四键工程和已提交items14作为保护基线。
- 验收目标：健康完整帧、坏帧/丢像素/溢出/中断与恢复的真实像素激励，当前帧两路结果和OSD旁带对齐，隔离构建实际可行性及TD6.2.1验证。具体硬件接入/bit产出以实际结果为准；软件仿真和构建不得写作上板通过。
- 修改登记：pixel14-baseline.json保护本任务既有文件、旧四键源/脚本/bit及主文档；逐路径见共享启动批次。任何新接口只作为本任务候选，不修改主接口/项目总状态。

## 2026-10-12 断点恢复：pixel14

- 当前负责人：SC520断点恢复对话 /root；读取关联聊天01a12ab4-0540-73a1-bb34-5857045b63cd后接手其未提交pixel14文件。HEAD仍为a698a53；原四键bit及DFR0534实物验证继续等待用户，不因开发而升级状态。
- 恢复时核对1284项保护基线一致。中断遗留capture/CDC/pipeline、runner、测试和六个运行目录此前仅有启动登记；本批以observed补登记，不冒称本轮创建或重跑。
- 尚缺当前帧积木识别模块、完整管线联调和真实CSI到ISP完成资格关联，不能作为可下载工程。继续补齐并实际验证；主文档/旧bit保持保护。

- 2026-10-12 root联调修复批次：独立审查确认前向mailbox无法接连续近邻两路结果、held flush只清一拍、done紧邻SOF与matcher DRAIN冲突。已改为采集双路暂存单包发送、同步持续flush及过早SOF撤销；新增完整RGB96管线TB并增加provenance runner入口，模板从快照定位。当前待实际仿真，不能标为通过。

- 2026-10-12 软件联调：因block分工多次限流而未落盘，root接手并完成block RTL及独立TB；只使用已接手任务文件。新增第三处隔离边界修复：外部短flush独立排队，避免隔离收尾时再次清除丢失。
- 实际命令：bundled Python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-pixel14.py，capture/cdc/block/pipeline四个--test各执行normal、--negative、--watchdog-probe。12轮均按资格返回0；正常capture19场景/1914703检查，cdc8/1440，block23/249，pipeline18/196，全部0错。4轮真实输出注错均native exit1/errors1/injected1；4轮500ns提前停止均native exit2/done0/errors0。没有用负向结果冒充正常通过。
- pipeline覆盖真实RGB96模板卡10..14、红方形、双路原子汇合、一次正确问答计分、完整前景漏采点、坏EOF、采集时钟停转、持有flush与帧中释放、采集tag重放、切源、EOF紧邻SOF、短flush重叠及视频RGB/DE同步。block以64×64完整光栅验证九类、混色、裁剪、未知、逐类健康与恢复；未使用实拍。
- 当前仍等待provenance实际vendor时序核对、TD工程/资源/时序；本批不是可上板版本。1284项保护完整性会在最终audit重新核对。

- 2026-10-12 最终软件验证：为核对默认几何，pipeline增加--full-resolution并实际以1280×720运行全部18场景；小几何历史仍保留。provenance编译实际厂商CSI/RAW解析器并测试最短包间隔及截短HS，正常18场景71检查。runner和输入快照冻结后，五类normal/negative/watchdog最终15轮通过，正常共86场景/1916659检查/0错。
- 已实际执行 audit-pixel14.py 返回0：15轮当前源码/输入快照/输出哈希全部一致，1284项旧代码、旧bit和主文件哈希未变。总证据 evidence/sc520-card-recognition/pixel14-validation.json。full pipeline正常p14-pipeline-normal-20261012-105005-c9d1ca68；最终各轮由总证据逐项列出。
- TD隔离工程由build_impl负责，已遇并保留初始XML/长路径/启动标记失败，后续运行进行中；这些探索结果不计为最终TD通过。真实硬件、精确DDR帧对应及声音仍待验证。

- 2026-10-12 首次完整TD 6a50b105完成但时序拒收：SWNS -5.063ns/STNS -70.009ns，HWNS +0.020ns，最差matcher distance到out_item串行排序；blocks框选择到输出另有负路径。bit仅为不合格候选，不建议下载；具体路径及sha由build批次登记。
- root据真实报告新增pixel14_card_matcher派生模块，旧受保护card_matcher保持原状。新模块用独立快照逐拍排序并允许下一帧采集同时进行；block的bbox选择与宽高差分拆开。pipeline转用新模块，TB新增最短帧间隔下两帧并行捕获与排序；首轮旧18场景对新RTL正常通过，最终回归正在重跑。审计v2独立保留首轮validation历史。
- 独立审查还发现provenance最终关闭同拍重复结束/开始标记可能漏拒，build_impl修复并新增四边沿测试。后续构建同时检查新CDC物理传播上界，不用时钟组切断替代验证。

- 2026-10-12 v2软件回读已完成：pipeline新排序/框选择流水线全720p 19场景199检查，provenance关闭边沿补测后22场景95检查；最终15轮正常共91场景1916686检查0错，负向和提前结束各五轮如预期拒绝。audit-pixel14.py实际返回0，当前源/快照/输出及1284保护一致，独立保留pixel14-validation-v2.json，不覆盖首轮软件历史。106已过综合进入P&R，ROM/IO与CDC由build批次报告。

- 2026-10-12 交接复核进行中：root与review_compact独立回读v2十五个manifest、126项输入及78项输出，正常91场景/1916686检查0错；1284保护文件全一致。106实际final_timing为SWNS +0.105ns/STNS0、HWNS +0.020ns/HTNS0；bitgen已完成，但追加CDC报告要求已优化的泛型fault端点而使phy进程退出1，原failure/stages/bit/DB保持不变。
- 原布线数据库的独立CDC报告正在建立恢复资格；root发现物理单元名与逻辑同步器名不一致后，已从LSLICE B触发器网表确认staging_fault打包映射。后续审计必须逐项映射逻辑net、物理Q/D和目标时钟，不得凭报告文件名或集合数量宣称通过。staging/config的实测2ns比较与req/ack实际2ns约束需分别记录；在最终audit落单前不宣称CDC资格。任务README已增加当前pixel14导航并标明原独立模块历史边界。

## 2026-10-12 pixel14 最终交接

- 状态：等待主对话审核。阶段基础提交 a698a53；负责人 SC520 断点恢复 /root，build_impl 负责原工程/构建与初始物理报告，review_compact 独立核对软件哈希和 CDC 逐位映射。build_impl 后续限流未能封存，root 接手最终恢复脚本、构建文档与登记；未覆盖其他任务。
- 完成内容：真实 AWB96/CSI 帧资格、卡片与本帧积木识别、两路原子结果包、双向握手/清除/超时恢复、十四类业务与预 OSD 视频接入，独立 overlay 工程和 TD 6.2.1 构建。新增分拍 matcher 修复 105 的真实负建立路径，block bbox 分段；关闭边沿标记、连续帧排序重叠及短 flush 重入均有回归。
- 软件结果：v2 十五轮资格通过，正常 91 场景/1,916,686 检查/0 错；五轮真实输出注错和五轮 500ns 提前停止按预期拒绝。完整 pipeline 为 1280×720。根与独立复核回读 126 项输入、78 项输出及 1284 项保护文件一致；没有为文档收尾重复运行已通过的 RTL 仿真。
- 106 原始构建：综合 exit0；bitgen 实际成功；随后报告钩子找不到综合已删除的泛型 fault 同步器，phy 进程 exit1。原 failure/stages、快照、数据库和 bit 均保留原样。最终 SWNS +0.105ns/STNS0、HWNS +0.020ns/HTNS0，覆盖 96.12%。资源为 slice15075、register15206、ERAM43、DSP17。105 的 -5.063ns 不合格镜像及此前尝试保留为历史。
- 独立恢复验收：root 实际执行 bundled Python -B -X utf8 fpga/custom_project/sc520-pixel14/tools/audit-recovery.py evidence/sc520-card-recognition/builds/6a50b106 evidence/sc520-card-recognition/builds/cdc106-v3，最终退出0，产生 6a50b106/recovery-audit.json。脚本首次因 config 第二级使用 provenance/cfg_done 别名而拒收，核对物理 Q/D 与 snapshot 顶层连线后修正审计器；无 RTL/SDC/bit 改动，无重复 TD。292 项输入记录与24快照通过，实现输入一致；唯一旧路径差异为 bitgen 后的报告辅助 Tcl。
- ROM/IO：模板1024×5及字库3×4096×5全部地址逐字 INIT 验证，4份签名存在于路由网表；四键 D5/A9/B9/C7 为 INPUT/LVCMOS33/PULLUP。bit位于 evidence/sc520-card-recognition/builds/6a50b106/td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit，1,789,539 字节，SHA256 3909C31AA81D7EB5C3153EFC2DBAC6D54C655A82A698107AA08CB0B14AFC0ABD。
- CDC：物理单元名可能是其他寄存器，已按逻辑 net、物理 Q/D 与寄存器选择解码确认打包别名。4条req/ack和4键实际2ns预算通过且hold正；staging/config是原周期预算，实测延迟分别0.604/0.405/1.429ns，小于2ns但不称2ns约束生效。payload目标集合160项中，排除19条setup+19条min同域附带路径，剩余80+80条跨域路径覆盖全部80有效位，69为dst_data、11为同位joiner别名。最大传播1.397ns；10ns是恢复审计的外部上限，工具未应用尝试的10ns exception。0.110ns相位预算/异步负slack不作为CDC通过或失败结论，也不提供MTBF证明。
- 修改与证据入口：本任务 pixel14 RTL、5个TB、仿真/审计/构建脚本、custom_project/sc520-pixel14 overlay与配置，硬件README及4份pixel14说明，v2软件汇总、106恢复audit、全部历史run/build目录和本日志。源/脚本/文档逐文件，生成目录及关键bit路径按共享最终批次登记；缓存、网表和bit保留本地，Git仅收小型清单与报告。
- 阻塞与风险：没有相机实拍校准、新bit上板、真实HDMI/按键/长时间运行或音频播放证据。仍未核算CSI CRC/ECC数值，没有采集tag与DDR显示帧的精确绑定；停流保护依赖显示时钟持续运行。该恢复资格只绑定本轮bit，不自动适用于下一轮路由。实验模板与固定ROI不能当任意物体分类准确率。
- 待决策与建议主对话更新：审核pixel14本地接口、真实采集身份、双候选拒识、问答清除与候选bit及物理报告后，再决定接口接受和合并。主文档仍含SC500/DFPlayer及旧环境状态，须由主对话结合各分支证据更新，本任务未修改。
- 下一步：旧四键826966ea bit与DFR0534实物测试继续独立待完成；主对话审核后安排新候选的相机/视频实测、卡片模板校准，再接真实音频。未下载、写Flash、替换旧bit、推送或合并。最终本地提交号及finish-task检查结果由共享提交批次绑定。
