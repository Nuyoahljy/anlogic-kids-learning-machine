# 五类卡片与十四类采集视频开发

- 任务 ID：sc520-card-recognition
- 状态：等待主对话审核
- 负责人：本轮 SC520 后续开发对话 /root；前阶段负责人 01a120ad-c540-7f11-af3b-6360b8cee2e9 /root
- 分支：task/sc520-card-recognition
- 基础提交：f609426044982c986b54e999866be9f4c1af2682
- 开始时间：2026-10-10T19:31:42+08:00
- 结束时间：2026-10-13；本轮软件/构建完成，0109实物待用户复测
- 工作目录：E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition

## 目标与验收条件

2026-10-13 恢复补充：当前 /root 接续聊天 01a1330e-e77e-7561-85bf-16b9be3cb203 最后未处理的两张 0107 照片和用户“仍不可信、所有操作留在工程内”的反馈。基础提交 b27bcdf494bbae10d6d8ee119dd9842d5badb79b，开始工作树干净，工作目录已用 git rev-parse 核实。照片可辨 D0107/E0002/H0330/F8002/B49，C46500/R38400/I38400/L02D0/Y02D0/G0000；N 分别 4403、3F69，附件顺序不能视作拍摄时序。先定位 I2C 错误标志语义，复现后修复并生成独立候选，保留真实配置错误拒绝能力。软件和构建通过不替代实物复测。所有新交付位于 E:/juan/FPGA，本轮不使用 C 盘输出目录，已有外部历史导出不搬动。主仓库和本 Worktree 总文档仍早于最新 SC520 证据，冲突仅记录供主对话审核。

2026-10-13 19:26 进展：i2c_root_cause 已独立核对 E0002、sticky 配置错误和写完成仍推进的代码路径，未找到正常读末尾 NACK 被当错的证据；开始仅在本任务 overlay 新建事务重试配置模块。i2c_bus_tests 以真实外部 SCL/SDA 从机模型跑通旧版全 165 初始化及 8 AE 写入，700 个写向字节全 ACK 时 error=0；init/AE 单 NACK 则仍完成但永久 error=1，符合故障机制，实物首次 NACK 位置尚未知。root 接入独立 32 位配置诊断 mailbox 与 Q 字段，重用原 256 位帧诊断的填充位，保留像素/行数全部有效位；AE 更新期间 cfg_done 资格暂停，成功后下个完整帧恢复。i2c_build_audit 负责新增 mailbox/同步链的 SDC 和逐位物理审计，并保留 107 审计器原字节快照。

root 实际运行 bundled Python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-pixel14.py --test diag，及 --negative、--watchdog-probe：正常 7 场景/745 检查/0 错；真实 active 注错 1 错/native1；500ns 结束 done0/native2。三个运行目录为 p14-diag-normal-20261013-192610-04f33cc8、p14-diag-negative-20261013-192642-afd4b82b、p14-diag-watchdog-20261013-192642-9d92de92。新增 Q 八位逐像素与帧内保持检查通过；完整配置候选/TD 构建尚待进行。

2026-10-13 19:29 构建启动：新配置 overlay 语法检查无错误，root 完整审读状态机；真实总线模型已通过正常、ID/init/AE 单 NACK 恢复、三类永久 NACK 终止等首轮测试，最终结果以独立 manifest 为准。新配置文件 SHA256 851363FA8C2F4940CE60FF80A0A90204D85DB5D2DF92816F14BFD26668DF9B2A，冻结后运行 prepare-pixel14.py，75 个工程引用中只有一份 uicfgcs520，确认为本任务 overlay。随后执行 pwsh -NoProfile -File fpga/scripts/sc520-card-recognition/build-pixel14.ps1 -RunId 6a50b108，296 项构建输入已快照，syn_1 启动 PID63700。构建中、未验收；源文件冻结，独立审计工具及说明可继续更新。旧前置工作树未改动。

用户授权在等待DFR0534快递与四键实物验证期间继续下一步，推进五类卡片识别独立软件开发。基于现有prep-v1图稿构建32x32二值模板、带全帧健康检查的固定方形ROI取样、串行像素距离匹配、unknown拒识和稳定滤波。只声明固定摆位下的软件模型验证，不把原图或人工变换当相机实测准确率。

## 已读文档

共享AGENTS/README/FILE_INDEX、最新DFR0534及四键交付记录；主仓库和本工作树AGENTS、总记忆/计划/任务/决策/接口，架构/素材约定，future-assets和prep-v1卡片说明，实际hdmi_quiz/detection_adapter/quiz_control/quiz_content。旧主文档仍有SC500/DFPlayer等历史状态，留主对话维护。原new-task-worktree脚本要求改动并清理主仓库，当前主仓库有他人未提交工作且无此任务日志，因此用git worktree add创建隔离新分支并在本工作树建立日志；没有修改主仓库文件。

## 修改文件

2026-10-13 最终候选调整：108 已完成两阶段 exit0，建立/保持余量 0.132/0.020 ns，17 同步链及 80/204/28 位业务/帧诊断/I2C mailbox 逐位审计通过。首次审计错误地要求原始 clock_summary 列出派生时钟，但它只列两个根时钟组；改为精确校验根组集合，并保留 final_timing 与新报告的全部派生周期逐项比对，第二次通过。原108审计器已按 SHA256 323F2912...6566C 归档，未改旧审计。

交付前发现108的Q借道采集域，配置失败无MIPI时钟时可能失去排障信息。109把32位I2C mailbox直接送HDMI域，OSD单独锁存Q；D0109由显示域常量给出。源码再次冻结并启动6a50b109。本轮显示测试8场景885检查0错、注错native1/提前结束native2均通过；v6软件回读为123场景1917919检查，27轮I2C汇总中25功能轮19712检查0错。物理资格待109新报告，不挪用108数值。

并发核查：2026-10-13 19:45主对话01a13319-8623-7201-8b08-0e27f34437f7更新五份主统筹文档，使旧保护检查准确报错；本对话重新读取AGENTS/总记忆/决策/活动协调表及20261013-194557-sc520-main-coordination-start-d281cc。已登记各文件旧/新哈希及该记录的哈希，只允许该五个确切文档版本作为外部变化；其余1279项和870项历史仍严格验哈希。未回滚或修改主文件。协调表的“0108”指本次排障任务，交付版已演进到0109；建议主对话从最终记录更新版本指向，不合并显示分支祖先代码。原0107外部C盘导出留作历史，本次交付仅E盘。

2026-10-13 19:56：6a50b109两阶段exit0，但基础STA为SWNS -0.274/STNS -4.556/HWNS 0.020 ns，candidate审计按预期拒绝。逐条原始负路径均为新I2C mailbox跨pll_clk_24m与HDMI_PIXEL_CLK的held_data或req/ack，预算仅0.653/0.674 ns；两源同PLL导致原有MIPI异步分组没有覆盖这条新通道。新增三条限定源/目标时钟且through本mailbox确切网络的false_path；同域meta->sync继续2ns时序检查，无例外物理数据传播继续逐位<10ns审计。未改RTL或仿真输入，再生成6a50b10a独立构建，D0109版号不变。旧109负结果保留，最终资格待本次报告。root独立回读I2C最终27轮：189输入原件/189快照/216输出均哈希一致，25功能轮19712检查0错。

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

2026-10-13 本轮最终交接优先：0109/6a50b10a软件及构建资格通过；用户从 evidence/sc520-card-recognition/delivery-0109/sc520-pixel14-0109.bit 临时加载后拍 D0109/E/Q/G/B 两张间隔画面。配置错误根因机制已仿真复现，实物首次NACK事务/电气原因仍待Q确认；未操作下载、Flash、真实COM、Git推送或合并。原0107与两个中间构建均保留。主对话请审核本次增量，再按实际照片决定后续集成，不将处理显示分支的107祖先重新当新成果合并。

实际终审：6a50b10a两个阶段exit0，bit SHA256 3A7CD3912C0C72FC6553382E2FB00B61F3A432B251C1C236A35BDFE1FAC7D3F8，1789539字节；SWNS0.112/HWNS0.020/TNS0；15934slice/16159reg/43ERAM/17DSP，4ROM/4键通过。17同步链2ns及hold通过，80/175/28位三mailbox逐位Q/D，最长1.317/1.500/1.381ns；原ignored报告对应I2C req/ack/payload恰1/1/28路径。10a首次总审因主对话TASKS再次变动拒绝，重新读195120调度记录并按精确SHA补v2外部文档映射后成功，不忽略任何HDL变化。软件v7为18轮123场景1917919检查0错；I2C27轮含25功能19712检查0错。主统筹五文档外部变化明确列出，其余1279保护项及870历史项一致。raw result中的TimingQualified=false是构建脚本写入的待验初值，最终资格只看独立candidate-audit.json，不改历史result。

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

## 2026-10-12 106实物反馈与不可信排障

- 用户报告本轮按键与画面正常、画面实时变化，但始终显示“识别不可信”。随后浅色空背景对照照片仍显示同一提示；照片只证明此刻界面状态，动态画面与按键为用户报告，不等于全部时长/准确率验收。证据保存在evidence/sc520-card-recognition/hardware/pixel14-untrusted-20261012.jpg，原临时附件未移动。
- 共享sc520-validation在19:50记录的“整体初测基本无异常、黄色手机图案较难识别”属于其镜像未重新哈希的用户反馈，不覆盖本对话106故障；不擅自修改其验证记录或主状态。
- 当前基础38552a5，工作树开始时干净。root负责源码接入与诊断；review_compact已只读发现HS窗口与CSI包结束不能等同，负责真实厂商串接尾部用例复现；新诊断显示和构建支持按各自独立文件分工。旧106bit/DB/快照与历史audit不改写，后续软件结果另建新汇总。
- 高优先级假设：106在CSI EOF同拍hs_valid仍高时判坏，且强制RAW长包HS窗口恰为803拍。实际vendor按头解码EOF，D-PHY aligned-valid窗口不按CSI WC裁尾；合法尾部可导致健康图像全部被拒。须先用真实parser复现，不能单凭推断宣布板上根因。
- 计划：保持精确WC/CSI/RAW/ISP总数及缺CRC/截短拒绝，接受有界长包HS尾并等HS退出后关闭；增加首个错误与实际HS/EOF/计数/超时诊断，统一仿真和TD6.2.1生成新候选供用户复测。背景未知不会直接破坏帧健康，不以降低分类阈值掩盖采集错误。

## 2026-10-13 断点恢复：107排障候选

- 状态：进行中；阶段基础38552a5。当前对话根据用户连续“从断点继续运行/继续执行/继续”接手上一对话遗留boardfix源码、18轮v3证据和107构建；未重新编译或操作硬件。当前照片单独归档，拍摄时镜像未回读。
- 已查实107于2026-10-12 20:26完成syn/phy两阶段exit0。root实际运行audit-candidate.py，首次因同域打包CEA路径无法解析而退出1；保留audit.json，修新审计器后第二次exit0。294输入/快照、4ROM、4键、13同步链、业务80位/诊断176位核对通过。SWNS +0.117ns、HWNS +0.020ns，TNS均0；bit SHA256 3AC5E069788CA11EA2136D36AAE5993447C2A2C62B9109C821F7DE77C6834044。
- 同域附带路径24/464条分别逐条保留，跨域160/352条无缺位；最大传播1.604/1.321ns，对比外部10ns限值，不宣称异步setup/hold或MTBF通过。旧106历史和bit保持原样。
- review_provenance独立回读v3 provenance证据通过，并提出ISP先排空而EOF HS仍高的补测。因代理限流，tail_tests以独立上下文接手指定TB补测，audit_review只读复核物理审计。root负责验收、文档、索引与提交。最终软件结果以随后独立v4汇总为准。
- 已补写hardware/pixel14-boardfix107.md和历史入口指向，明确HS长度不等于CRC数值完整性；未改变分类阈值、正式共享接口和主项目状态。

- 最终软件：tail_tests新增8场景，正常46场景443检查0错；注错1错/native1；500ns提前结束done0/native2。新增三run目录为20261013-103504-5eb7de71、103537-2e29faf0、103551-ec8025f8，全部源/输入/输出哈希通过。root执行audit-pixel14.py --output evidence/sc520-card-recognition/pixel14-validation-v4.json退出0，18轮资格通过，正常121场景/1,917,079检查/0错，1284保护文件与870历史文件一致。其他5类测试源码未变，沿用并重新回读2026-10-12实际合格证据，没有为收尾重复运行。
- 补测结论：ISP已排空、EOF HS仍高16拍期间不提前完成，退出后仅一次健康完成。缺CRC或缺1载荷字加尾字可能通过，载荷替代有独立比较检出1字不一致；两个字均缺时尾0/1拒绝、尾2通过。此为CRC/ECC及数据内容不验证的已知限制，不宣称通用完整性保护。
- 最终物理回读：audit_review已确认报告路径总数和13同步链，后续因限流未完成全量回读；root独立按原报告逐项匹配，业务184=160跨域+24同域，诊断816=352跨域+464同域，与candidate-audit全部selected/excluded一一对应；294输入/快照、28候选审计引用和34基础审计产物哈希一致。最终STA覆盖95.86%，不用覆盖比例推断未分析路径安全。
- 交付：输出目录含sc520-pixel14-0107.bit、SC520-0107-guide.md和SC520-0107-manifest.json，导出字节及SHA与原构建相同；工作区内delivery-0107.json登记外部输出确切路径与哈希。源码、说明、关键JSON逐文件登记，生成运行/构建目录按批次登记；大型bit/数据库/全路由报告保留本地，Git纳入精简资格及哈希索引。
- 当前状态：等待主对话审核；本地检查点由随后finish-task绑定。建议审核107候选后用户以PROGRAM_SRAM实拍D0107三行，先确认E/N/G及完整帧计数，再据B位图继续定位；未上板、未Flash、未推送、未合并、未接真实声音。主项目状态/共享接口由主对话决定，本任务未修改。
