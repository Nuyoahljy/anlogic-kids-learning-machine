# 五类卡片与十四类采集视频开发

- 任务 ID：sc520-card-recognition
- 状态：等待主对话审核
- 负责人：01a144c7-e802-7272-a29d-a8159f5ec84b /root T023；新聊天接续 D057/T023，当前主 01a14468-1741-70a2-aea6-757eb183382f
- 分支：task/sc520-card-recognition
- 基础提交：f609426044982c986b54e999866be9f4c1af2682
- 开始时间：2026-10-10T19:31:42+08:00
- 结束时间：2026-10-16T23:12:12.445337+08:00；T023离线阶段完成待主审，T022拒收封存保持
- 工作目录：E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition


## D057/T023启动（2026-10-16）

从干净9f670bc沿用原工作树和分支，接替失败01a144ae；当前主D059仅更新负责人，D057技术范围不变。已核恢复快照7628跟踪文件及763保护文件SHA。主库现行文档优先于旧工作树总文档；不重建原工程，不reset/stash/切分支，XYZ已由主解除。

新增timing23局部候选：同capture_reset[0]驱动9个preserve第二级分区，原第二级保留；诊断原始坐标在N预译码、6行字符分组在N+1输出，单快照、六层N+5保持。只从本机TD6.2.1随附SWUG106第4.2.14确认preserve防合并，尚须实际网表确认。54拍ISP、音频冻结代码、时钟/例外与厂商DDR均保持。当前仅实现，仿真/物理待验证，禁止bitgen/下载。

下一步：针对性复位/首帧/坏帧/停采/payload以及完整720p/四键/音频回归，然后独立新候选综合布局布线，复核全部ROM、原24链及新增复位链、四mailbox和四类全局时序。

## T023软件验证完成（2026-10-16）

当前51场景/28,685,263检查/0错误；render、pipeline、reset、business、default五组各完成正常、实际DUT输出注错和500ns提前停止，共15轮资格成功。注错均原生exit1/errors1/injected1；提前停止均exit2/done0/errors0，未当作正常功能通过。使用bundled Python `-B -X utf8 fpga/scripts/sc520-card-recognition/simulate-timing23.py --test render|pipeline|reset`，各组另带`--negative`、`--watchdog-probe`；business/default由`simulate-timing23-extended.py`同参数运行。完整原生命令、环境、输入快照和输出SHA保存在各run-manifest。

复位新增不同相位释放、时钟停止时异步断言、原第二沿恢复、7个完整720p首帧、坏EOF/恢复、元数据错误及停采超时；检查5,196,083复位沿和103项业务/800位mailbox稳定性。第一次reset编译因任务引用变量声明顺序失败，修正测试声明位置后成功；失败目录timing23-reset-normal-20261016-211859-380c9162原样保留。

`audit-timing23-validation.py`实际成功：872项当前引用、763项旧保护文件SHA一致，四组独立测试仅更名DUT/顶层。四幅720p逐像素一致；已目视核全部诊断行、Logo、原图/处理、计分与音频状态和红色失效诊断。原可选端口缺失告警保留说明，正常render零告警。入口`evidence/sc520-card-recognition/timing23/software-validation-v1.json`及`preview-v1/actual-0..3-timing23.png`。

软件通过后RTL未变；随后新增综合复位拓扑审计和十条精确2ns一级至二级复位约束、专用时序报告，尚待实际TD执行。保持54拍、六层N+5、单800位快照、全部字形/256模板/四键/Logo/UART/队列和原厂DDR、时钟、既有例外。正式三个VERIFIED仍0、TRACKS空；测试profile独立。下一批启动唯一新run，仅综合及opt_route，不bitgen，实际检查保留属性和分区扇出后才布局。

## T023综合与ROM阶段（2026-10-16）

共享软件批次20261016-214833-sc520-timing23-939031和index/-Check成功后，实际执行`pwsh -File fpga/scripts/sc520-card-recognition/build-timing23.ps1 -RunId 6a50b230`；363输入哈希、105工程引用，syn_1原生exit0/新结束标记/阶段成功日志。`reset-synthesis.json`确认原一级及10个独立二级同D/clk/异步reset，preserve属性生效，各负载仅属约定分区；随后自动进入phy_1，当前布局布线中。只使用自身V映射和Hidden TD，XYZ不用，GUI不关闭。

首份综合负载统计为226/197/2480/346/185/52/51/312/1816/2027；后续精确pin-role回读发现AL_MAP LUT的c是输入，场景支路应为2481而非2480（其余一致）。原始reset-synthesis.json保持；最终物理审计补充精确统计。这些是综合输入pin统计，不和旧物理2448fanout直接等同，也不能认定全局最大负载下降。

执行`derive-timing23-rom-bindings.py .../6a50b230 --tag syn230-v1`最终成功：39绑定、102400旋转模板字、125独立bank/class BDD及640Logo选择真值。适配初次遇到新首层dy寄存别名，其后遇到解析器额外INIT=0；按实际Q/D、异步参数和一层时序关系补充1024行坐标真值证明后通过，未改RTL或构建快照。实际物理连接与时序仍待最终审计。

新增`snapshot-timing23-coordinator.py`已对7份最新主文档与其登记SHA封存到coordinator230-v1；新增`audit-timing23-physical.py`准备按真实新run检查，尚未运行，不引用T022正向报告作为新资格。

## T023最终离线时序交付（2026-10-16）

状态：等待主对话审核。唯一6a50b230于22:27完成，syn/phy原生exit0、输入变化为空，V临时映射已按finally解除；XYZ和用户TD GUI保持。没有重跑已完成构建或软件测试，无bitgen/bit/下载操作。全球SWNS +0.102ns/STNS0、HWNS +0.020ns/HTNS0，覆盖96.36%；资源19163LUT6/21801REG/19870slice/107ERAM/22DSP，满足slice≤21216和ERAM≤108。

本轮实际执行bundled Python `-B -X utf8 fpga/scripts/sc520-card-recognition/prove-timing23-address.py evidence/sc520-card-recognition/builds/6a50b230 --tag routed230-v1 --mode normal|negative|watchdog`，三轮资格均成功。正常16384行/475190检查/0错，注错475191检查/1错/native1，500ns早停49行/done0/native2。仅对新shape ROM实际复制的card_index[5/6/8]，使用未经修改的厂商FF/LUT/SCLK及十一独立输入叶证明共同复位后的局部Q行为；配置窗口未资格、无SDF或整个网表等价。

`audit-timing23-physical.py .../6a50b230 --bindings .../rom-proofs/syn230-v1/bindings.json --address-proof-dir .../address-proofs/routed230-v1 --coordinator-review .../coordinator230-v1/review.json --output .../physical-audit-v2.json`实际exit0。15项独立审核全通过：39ROM、原24同步链、新增十路复位、四mailbox、I2C/音频、原时钟例外/正式零门控/测试配置、363构建输入、872软件引用、763保护及导入。首次v1的ROM地址别名和三份换行差异失败保留；只在新审计器使用本次网表/精确ROM/三alias专项证明与严格LF→CRLF转换，不改原构建文件。

复位每条原始clk2q实际oqa/oqb已解码，同单元附带Q路径单独保留。十路物理源网扇出141/133/1415/237/98/31/29/179/1219/1354，各本Q路径均正；场景recovery +1.682ns，诊断最长源网9.173ns/recovery +0.183ns如实保留。不是把综合pin扇出或同LSLICE混合报告当本Q结果。

历史源完整性：v1程序SHA保留，逆向重构未匹配，未伪造v1源码快照。最终v2程序将按其报告SHA原字节封存；完整v1/v2与大STA报告保留本地，新compact视图往返重构全部字段，仅去重复存储。封存入口timing23/validation-manifest-v1.json，说明hardware/sc520-card-recognition/timing23-validation.md。当前源码/测试/脚本及独立生成证据均属本任务，旧T022/0117/0116和主专属文档保持。

未解决与建议主动作：请主按9f670bc之后增量审核本次离线时序/软件资格。正式三VERIFIED=0/TRACKS空，54拍、六层N+5、单800位诊断快照、31位业务音频快照、256模板、Logo、四键/计分、真实UART/队列、厂商DDR/时钟/旧例外不变。未知针位/电平/媒体曲号/BUSY、实物颜色和整机长测继续待验证，FullSystemTimingSignoff/HardwareValidated仍false。审核后由主决定后续正式配置和硬件阶段，本交付没有下载镜像。实际提交、finish-task/index检查与一次通知结果另以独立闭环批次登记。

提交前的完整git diff --cached --check因厂商STA固有对齐空白及继承overlay空白返回2，没有修改其原始字节。另发现九份新overlay被Git默认转为LF；任务局部sc520-timing23/.gitattributes设置-text，仅保留已构建副本的原字节，不改RTL内容。源码/脚本和文档的定向空白检查及全部提交blob与工作字节核对随后执行；原构建/软件哈希不变。

## D054/D055：T022物理拒收交付（2026-10-16）

当前主已按用户直接授权迁移为01a14468-1741-70a2-aea6-757eb183382f/local，已read_thread核用户原话并读191706主登记。e8466e2源码/软件阶段由新主D055接受；当前七主文档另存coordinator220-v3，v1/v2不回写。

route220-v3在16:13原生syn/phy exit0、ChangedInputs为空、无bit，W映射已由父脚本解除。旧exec会话后续不可用，以原父脚本result/stages和TD结束标记为原生证据，不重跑已完成构建。最终SWNS −2.045ns、STNS −1617.371ns、HWNS +0.020ns、HTNS0，严格总审exit1，物理明确拒收；不是合格候选。

最终probe-rejection-v2逐项核39路由ROM、原21加音频3条同步链、四mailbox保留80/106/28/762位Q/D；最长传播1.647/1.814/2.044/4.246ns，独立10ns界限内，不宣称异步setup/hold或MTBF。I2C 48寄存cell/1603原始路径和音频272寄存cell/7142原始路径全部核到真实PLL，setup/hold/recovery/removal均正；全局失败仍否决资格。资源19144 LUT6/21592 REG/19686 slice/107 ERAM/22 DSP，较0117增加672/428/620/0/0。354输入、86恢复复制、763保护、7导入和602软件引用保持。

初次拒收报告还记录恢复审计的格式问题：原单对象stages被误当数组，且PowerShell省略UTC小数末尾0。原文件不改，严格审计器仅增加单对象归一与精确小数时刻比较；实际100ns变化、PID变更、额外字段三类负向均拒绝。初版程序按原字节存audit-source-v1，原audit-attempt-1及probe-rejection-v1保留；没有改变时序标准或重跑仿真/TD。

失败定位：MIPI复位释放网扇出2448/net延迟11.386ns导致recovery −2.045；HDMI诊断x/y/snapshot到RGB setup −2.039；厂商DDR用户域事务FIFO setup −1.598。已交hardware/sc520-card-recognition/audio22-timing-proposal.md，建议下一独立候选做同源同周期复位分布、现有第一层预译码诊断坐标/分组字符选择，再完整重建核DDR路径。保持六寄存层、单快照、全部诊断/Logo/256模板/四键/真实时钟；未实现提案或擅自修改厂商DDR。

X/Y及旧v2残留Z仍保留：GUI28952标题/命令行无工程路径，不能证明无别名依赖；本次不关闭GUI、不删除真实目录。所有正式VERIFIED=0/空TRACKS、不bitgen、不发布新下载步骤；D0117/D0116保护、实物针位/BUSY/媒体/颜色与整机资格保持原界限。建议主审核拒收证据并批准下一阶段优化范围，本轮等待主对话审核。下方为真实历史进展。

封存：rejection-manifest-v1.json绑定当前指南、优化提案、原生结果、D054/D055快照和最终拒收报告。451项当前报告引用与13个指南/提案链接复核通过；提交保留全部解析路径与SHA，29.6/33.7MB两份音频原始STA报告按新运行目录局部.gitignore留本地，原字节未删除。其余构建大数据库按既有规则保留，86恢复清单另纳入提交。最终提交后的字节检查会另写独立证据，不能把该检查的Qualified误读为物理通过。

## D053/T022接续核验（2026-10-16）

接续阶段检查点：源码、默认/离线配置、44场景软件证据及继承核验已具备独立复核条件，先保存本地Git检查点。route220-v3仍在第三轮布线优化，未完成物理终审，不将检查点标成可下载或硬件通过；总任务继续进行中。该检查点不改变任何354项构建输入，不中止当前执行会话。

本地源码/软件检查点为e8466e2faf8abebc2ca645d5334a9ff56a81e36b，246文件中237与工作字节精确一致、9仅Git CRLF规范化；763保护和354输入复核仍一致。详见audio22/software-checkpoint-v1.json。该提交不包含尚未完成的物理资格，不可下载；本任务继续等待route220-v3原生结果。

11:10后发现route220-v2的TD35888及父30524均已不存在；stdout最后11:07:17停于2.5.2.4 Iter14/82冲突，stderr空，原生result/stages/failure和route-end均无。Windows Application自11:00未查到1000/1001/1002故障事件，原因仍未证明，不能当资源/时序失败；本聊天未终止进程。另存audio22/route220-v2-interruption.json，保留原始运行目录和残留Z。拟用本聊天可轮询的exec会话在全新route220-v3从原6a50b220合格place.db恢复，仅路由/报告，不重做综合/布局、不运行bitgen。GUI别名依赖仍不明确，X/Y/Z暂留；下一映射由恢复脚本选择空闲盘符并负责finally。

状态：进行中。重新读取根AGENTS/README/FILE_INDEX及103852/104330/105045/105341记录，主库七文档、T022范围、工作树规则和任务日志；主库D053归属优先于工作树旧总文档。工作目录和task分支不变，HEAD fe5173964657dacc9c6723fe00e7ed5975901462。主恢复快照97文件全部原SHA相符，未reset/stash/复制重建项目。

`review-audio22-handoff.py --output evidence/sc520-card-recognition/audio22/handoff-review-v1.json --owner '01a142a0-2945-7823-b9c2-868aa816a6f6 /root'`实际exit0：763保护文件、7精确音频Git导入、12轮仿真602原输入/输出引用、354构建输入和86恢复副本核对通过。44场景/12199365检查与正常0、注错1、早停2原生退出分别符合；未重跑仿真。旧158字形不变，四幅720p PPM/golden/preview逐像素一致且本负责人实际目视核对，音频文字未遮挡题号、分数、Logo和诊断。

`snapshot-audio22-coordinator.py --tag coordinator220-v2 --owner '01a142a0-2945-7823-b9c2-868aa816a6f6 /root'`实际exit0，七主文档绑定D052/D053真实SHA记录，旧v1保留。登记脚本改为必填owner，避免新批误署旧负责人，不属于构建输入。

在途route220-v2由原父PID30524等待TD PID35888，Z映射保持；进程持续从opt_route推进，不能将阶段性正余量视为最终资格。X/Y仍为原6a50b117/6a50b220映射；GUI PID28952标题仅Anlogic TD 6.2.1，命令行没有工程路径，当前未证明GUI无别名依赖，因此本批不解除映射、不关闭GUI。待原路由原生result/stages或failure产生后终审并核Z的finally清理。本轮不bitgen、不交付bit、不变正式三门控0/空TRACKS；当前主通知目标01a14297-b71d-7490-9ff2-c23a463ca0a9/local。

## D051/T022启动（2026-10-16）

2026-10-16恢复检查：原phy PID36608和父执行会话已不在，原日志最后更新10:18:18，止于阶段2.5.4.4重布线Iter5/215冲突；无原生退出、route结束标记、result或failure，故只能登记“中断、原因未证”。原布局数据库及结束标记完整，新增resume-audio22.ps1准备在独立route220-v1从同一place.db恢复，仅重做路由/报告；原354输入、综合和布局成果保留，bitgen仍禁止。终审器新增逐文件复制/布局DB/单项start_step变化核对；不宽放时序或输入资格。

恢复准备首轮route220-v1在TD启动前被配置CRLF的精确行检查拒绝，复制目录保留并追加failure.json，未执行综合/布局/路由。已核原行实际为set start_step opt_place加CRLF；仅修脚本接受LF/CRLF并前移校验，原配置不改。恢复使用route220-v2新目录。

物理检查点：6a50b220已综合exit0；原phy PID36608持续路由，本轮未重启。已完成前两相位，当前第三相位setup/hold优化后重布线。阶段性正余量不是最终资格；result.json尚未产生。后续应沿用本次DB，先检查原生退出/报告，再按hardware/audio22-integration.md末尾命令终审，不重复TD。当前软件v2的12轮44场景/12199365检查已完成。


补充正式默认端到端资格：default 3场景8328检查/0错，实际三门控0/空映射接当前items14与renderer，UART零帧且探索/问答计分反馈/K4推进正常，负向/早停正确拒绝。v2最终12轮共44场景12199365检查0错，原9轮原始输入未改变或重跑；软件v1保留历史。此补测只新增测试文件，不改已冻结220工程RTL。

从干净fe51739接续当前业务/显示与冻结3287af4真实音频。已核主D051范围与起始快照，原763个D0116/D0117构建/交付/最终仿真文件逐SHA冻结，7个音频RTL/独立UART模型按Git blob导入本任务audio22。独立sc520-audio22工程，正式默认三VERIFIED为0、TRACKS空；离线配置分离并标TEST ONLY。保持全部旧源/交付，不运行bitgen、不写delivery、不操作COM/硬件；当前实现中。新真实UART/完整items14合并业务19场景54448检查、实际RGB96/256模板pipeline→UART 5场景807474检查已通过；状态默认/初始化/可用/播放/故障、错tag/满队列/无回复/超时等有联合证据。四720p渲染17场景11329115检查首轮通过，最后输入冻结后资格重核中。测试只修TB声明/时间常量/独立错tag注入监视及溢出场景复位需等串行事务完整结束的时序；原音频核心不改。软件总审audio22/software-validation-v1.json已确认9轮，正常41场景12191037检查0错，3真实输出注错各native1/1错、3早停native2/done0；470当前引用/763旧保护及158字形不变、四720p逐像素一致。39ROM新综合绑定/125BDD/640Logo选择也通过，物理路由未完成。主快照脚本初次路径替换遗漏在display17/coordinator220-v1生成新文件，保留为生成错误历史；已修工具路径，正式引用audio22/coordinator220-v1，未覆盖任何0117原件。T017以下为已交付历史，本轮D051明确允许新离线开发。已完成新pixel22_audio同源两级复位、真实桥返回idle/fault、3位状态及同一次31位显示快照，单独163字字体保留旧158。新top默认三门控0/空映射，离线合成35槽分文件；C18/D15/E12核117实际IO未占用，仅探针候选。prepare-audio22 exit0，101源码引用/354输入冻结，6a50b220综合PID636启动，bitgen函数硬拒绝、流程止opt_route；未完成软件/物理资格。

## T017/D0117最终交付（2026-10-15，优先于下方历史）

状态：等待主对话审核。本轮接续负责人01a14030-32d9-78f2-b274-91a370cc9ff0，接管基线68e2b4d01485fa1b3049d81e98a09c2e3dc98a94；显示依赖edaced3542a4a056aa90397aefadb45e279e69e2。新compositor接当前业务28位状态单次帧首快照、六行诊断、唯一字体、同步Logo；全帧处理/原图同为六寄存层（N→N+5），统一SCENE=(160,120,960,480)。K3仅mode0/1切图，问答/结束页仍跳题语义，K4恢复原图、K1压同拍K3、K2保留。WB/tone/54拍、分类/256模板/计分/I2C及D0116 155保护文件保持；无音频或新GPIO接入。

现有最终5轮软件资格107场景/11,342,730检查/0错；RGB注错native1/恰1错与500ns提前停止native2/done0均如期拒绝。本次未重跑ModelSim，独立回读244项输入/输出/图引用，四幅720p实际PPM与golden/预览逐像素一致，三幅重新目视核布局（四图均有原负责人目视记录）。系统Python缺PIL的只读复核尝试未完成图比较，改用原Codex bundled Python后完整通过；没有据失败尝试声明成功。

物理原生syn/phy exit0，未重新综合/布局；335输入及76恢复复制文件一致。39ROM路由签名/地址/控制/输出、21组2ns同步链、4mailbox保留80/106/28/762位逐Q/D通过，最长传播1.909/1.684/1.418/2.974ns（独立10ns界限，非异步setup/hold或MTBF签核）。49个I2C寄存cell全回溯父PLL，1578路径setup/hold/recovery/removal最小1.383/0.075/39.296/0.109ns。原STA SWNS+0.104/HWNS+0.020ns、双TNS0、覆盖96.23%；18472LUT6/21164REG/19066slice/107ERAM/22DSP，相对116为-3/+203/+10/+10/0。保留混合扇出与局部时钟critical warnings。

首次终审日志audit-attempt-1.log因coordinator117-v1已过期被准确拒绝；主233543-7658fc真实登记7文档SHA后，另建coordinator117-v2，通过audit-attempt-2.log。快照脚本仅增加必填owner记录真实执行者，不改物理审计或约束。原v1/旧主登记/原TD结果不回写；TimingQualified=false是原构建待审初值，最终资格看display17/candidate-audit-v1.json。

已执行命令（cwd本worktree；Python路径C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe）：-B -X utf8 fpga/scripts/sc520-card-recognition/snapshot-display17-coordinator.py --tag coordinator117-v2 --owner '01a14030-32d9-78f2-b274-91a370cc9ff0 /root'；-B -X utf8 fpga/custom_project/sc520-pixel17/tools/audit-display17-candidate.py evidence/sc520-card-recognition/builds/phy117-v1 --bindings evidence/sc520-card-recognition/display17/rom-proofs/117-v1/bindings.json --coordinator-review evidence/sc520-card-recognition/display17/coordinator117-v2/review.json --software evidence/sc520-card-recognition/display17/software-validation-v1.json --output evidence/sc520-card-recognition/display17/candidate-audit-v1.json；-B -X utf8 fpga/scripts/sc520-card-recognition/seal-display17.py --audit evidence/sc520-card-recognition/display17/candidate-audit-v1.json。三命令均exit0。

交付bit：evidence/sc520-card-recognition/delivery-0117/sc520-pixel17-0117.bit，1789539字节，SHA256 E907703E4563C4E6DB4FB4FC99C3CBB8C7BFAE52830265576460A1CA4B1F0F1C，与phy117-v1原件一致。manifest.json绑定指南/软件/物理审核及预览，指南hardware/sc520-card-recognition/display17-integration.md列最少用户步骤。本地提交号和提交后字节核查在随后独立共享批绑定。提交前528个递归审核/manifest引用哈希及25文件链接通过；常规git diff --check把冻结源码CRLF当行末空白，显式cr-at-eol检查通过。finish-task第一次将自身日志CRLF提示误作越权路径而拒绝，未提交；仅将本日志统一LF后重试，冻结RTL/测试/构建输入不改。

建议主动作/下一分支：审核68e2b4d后的本任务增量及以上证据；通过后统一安排一次SRAM显示/按键验证（启动原图、0/1 K3、问答不切图、K4、Logo/六行/框），用户无需重做D0116原两图或全计分。颜色/IR问题未修复，无IR-cut为用户供应信息；外部SDA/RC/使能、CRC/ECC内容、精确DDR帧身份、实物长测和音频仍未验。ERAM仅余1块，下一整机接入重新核实际预算；HardwareValidated=false、FullSystemTimingSignoff=false。主文件由主更新，本轮未下载、Flash、COM、推送或合并。
## D047接管与现有结果核验（2026-10-15T23:33:37.3527002+08:00）

恢复快照206文件与D0116保护155文件逐SHA通过；当前task/sc520-card-recognition，HEAD68e2b4d，继承未提交内容，不reset/stash/切分支。phy117-v1已有21:47原生exit0及E907703E4563C4E6DB4FB4FC99C3CBB8C7BFAE52830265576460A1CA4B1F0F1C/1789539字节bit，不重新综合或布局。工作树总文档为旧历史，当前主库D047及随后归属记录优先。继续39路由ROM、21同步链、四mailbox、I2C复位及软件绑定审计；当前未交付。主恢复登记未带7主文档SHA已请求主在新批补登记，严格校验不放宽，coordinator117-v1原样保留。该请求已send成功；不等于主已完成补记。只改本任务文件，主文档/其他树不写，真实音频/硬件未接触。

## 2026-10-15 D046/T017接手

阶段进展：最终5轮软件资格通过，正常共107场景11,342,730检查0错；最终Logo RGB注错native1/恰1错、500ns提前停止native2/done0分别正确拒绝。四幅720p实际PPM与独立golden逐像素相同，155保护文件/9导入/152旧字形一致，汇总display17/software-validation-v1.json。D0117/build6a50b117的335输入/92引用综合exit0；21:14:32布局日志在start_timer中断，恢复时无进程/原生exit/最终result，不能归为资源或时序失败。新增resume-display17.ps1复制已冻结综合DB/源到独立phy117-v1续跑物理，不重新综合、不改原中断目录；源/复制SHA逐项检查。本版ROM和物理终审继续。针脚归属已由主PROJECT_MEMORY确认接回，不重复向用户确认。

21:41进展：当前syn39ROM已完成新字体3072个y输入检查、8Logo index平面/2palette平面、640组Logo mux真值及125个bank/class独立BDD验证，内容逐字与冻结模板/字体/Logo资产相符；proof与bindings在display17/rom-proofs/117-v1，单综合内容审核rom-content-syn-v1.json明确CandidateQualified=false。初始直接沿用116全matcher cone被精确比较拒绝后改为本版独立BDD，未放宽匹配。4幅实际预览均已目视检查。布局实际19066slice/18472LUT6/21164REG/107ERAM/22DSP，综合21537slice估算不代表最终超限；最终布线/时序仍在途。新物理审计/交付/提交复核脚本已准备，7主文档按最新登记封存coordinator117-v1；没有写主文档或原116文件。

从干净68e2b4d继续T017显示整机接入。D0116所有build/交付/两实拍共155文件逐SHA保护，接手3530任务源码/素材记录于evidence/sc520-card-recognition/display17/start.json。显示依赖9文件从edaced3 Git blob提取，不读活动副本，不导入frozen0109字体/诊断。新独立工程sc520-pixel17，拟定D0117/build6a50b117；当前实现中，未验证。只修改显示/业务状态导出兼容参数及必要测试，保持相机WB/tone/54拍、阈值、256模板、计分和I2C核心。K3上下文切图、K4原图、K1抑制同拍切图、K2保持；输入帧首生效。先取消旧renderer，再一次业务快照和当前六行诊断、共享字体、同步Logo组成六层链。所有先前完成段落为冻结历史。本批不接音频/新GPIO，不操作硬件、推送或合并。

## 目标与验收条件

### 2026-10-15 D036：同帧颜色观测接入

最终交付：D0116/build6a50b116，基础c74a430。新增三阶段实际tap、gain/neutral结算、同tag场景/形状/稳定快照、800位握手传输和六行诊断渲染；原WB=1/TONE=1、54拍视频、分类/模板/四键及I2C源码保持。最终软件13轮资格通过，正常115场景/47,435,158检查零错，4负向/4早停均如期拒绝。完整TD6.2.1两阶段exit0，SWNS +0.108ns、HWNS +0.020ns、双TNS0；321输入/39冻结快照、29ROM及125组bank/class BDD选择核验通过。

21组同步链逐一2ns预算/hold通过；四mailbox保留位80/106/28/762，最大传播1.420/1.303/1.837/2.459ns。新诊断32位帧号目标Q采用精确display_packet[31:0]别名，按冻结RTL直连及实际Q/D确认；本版ROM未出现113复制地址例外。49个I2C寄存器cell全部回溯父PLLclk1；1596路径的setup/hold/recovery/removal最小1.298/0.073/35.707/0.107ns。资源18475LUT6/20961REG/19056slice/97ERAM/22DSP；相比113净增3676LUT6/6994REG/3519slice，ERAM/DSP无新增。原诊断保留位减少来自六行渲染仅消费其上下文，未把106写成原175全部保留。

交付bit为[sc520-pixel14-0116.bit](../../evidence/sc520-card-recognition/delivery-0116/sc520-pixel14-0116.bit)，1789539字节，SHA256 8FE5D3A5DA18278CF5C42E7B78B687F17B4A4B4DE1A4ACD21E77CABEDCB82F23，与构建原件一致；见[交付清单](../../evidence/sc520-card-recognition/delivery-0116/manifest.json)、[用户采样与范围](../../hardware/sc520-card-recognition/pixel14-observation116.md)、[软件](../../evidence/sc520-card-recognition/observation-validation-v2.json)、[物理审核](../../evidence/sc520-card-recognition/builds/6a50b116/observation-candidate-audit-v1.json)。总审初次因主文档D039建模分工更新拒绝，已读取121929/122024真实记录并另存coordinator116-v2快照；v1历史保留，未忽略HDL或主文档变化。主记录SHA采用小写十六进制，只规范比较表示，原字节严格相等。

实际命令均在本工作树：bundled Python -B -X utf8执行simulate-pixel14.py --test color_taps/observation/observation_display以及各--negative/--watchdog-probe；simulate-color-scene.py --observation三模式；simulate-pixel14.py --test scene_system --rotation-variants 256；audit-observation-validation.py --output evidence/sc520-card-recognition/observation-validation-v2.json。构建命令pwsh -NoProfile -File fpga/scripts/sc520-card-recognition/build-pixel14.ps1 -RunId 6a50b116；ROM证明derive_scene_rom_bindings_v3.py evidence/sc520-card-recognition/builds/6a50b116 --tag 116-v1；audit-observation-candidate.py使用116-v1 bindings和coordinator116-v2/review.json，输出observation-candidate-audit-v1.json。全部运行完整argv/输入输出SHA存于各run-manifest，不为收尾重复RTL或TD。

待决策与建议主更新：请审核D036单诊断候选，之后只安排固定照明下单红圆覆盖青窗、白纸覆盖紫窗的一组实拍，再移走圆拍纸面对照。颜色尚未修复、HardwareValidated=false、FullSystemTimingSignoff=false；外部SDA/RC/使能传播、CRC/ECC、DDR帧身份和整机长测未验。保留混合扇出/局部时钟两告警；当前资源需在T017/音频接入前重新预算，本版未集成这些功能。用户针脚问题已按直接授权交当前主处理；本任务未确认针位或操作下载、Flash、真实COM、推送、合并。提交号及共享索引复核由最终提交批次绑定。

恢复更新：最终候选已改为D0116/build6a50b116；114/115探索版本因均值字节序及新包交付同拍age修复主动停止，全部旧结果保留。当前冻结RTL的13轮软件资格已通过，正常合计115场景/47,435,158检查/0错，包括28幅720p真实观测链路和80场景原识别回归；注错/提前停止各4轮按预期拒绝。116综合完成，29份ROM绑定、102400模板字及125个bank/class独立BDD选择通过；布局布线及物理总审仍在进行。已把用户针脚图问题按其直接要求发送当前主01a13d4f处理，本任务只继续颜色诊断，未确认实物接线。

主D035已接受T018 5026edc和C002局部c74a430；本轮从干净c74a4300abd1c65ab49ff9ba3be739434379a8f6继续。按D036保持WB=1、TONE=1、54拍视频、阈值、四键映射及原识别流程；对齐真实preWB/postWB/postTone像素和本帧增益、中性结算，按同采集tag合并scene/glyph/paper/presence、rawblock、shape、稳定计数，握手CDC和显示帧冻结。缺失/错tag/坏帧/停流只给不完整标志，不能拼旧帧。当前预定D0114单诊断候选，先不切旁路、不调曝光或饱和度，不接T017/音频RTL。所有旧镜像及23轮已审证据保留，新增输入/仿真/TD单独冻结。

### 2026-10-15 当前交付：T-018与C-002隔离诊断

当前主对话已迁移到01a13d4f-6f61-71f2-8aec-85ff85a4be7e，依据101031主接替记录和直接派发继续。候选D0113/build6a50b113仅修I2C内部时钟覆盖，不修改f81483c的图像/识别/模板。bit SHA567EFF7D3887F896915F11F2B909D58760BF04701CD1B92B5C19E36E5DF8771F，1789539字节；D0112原镜像保持。交付与范围见[说明](../../hardware/sc520-card-recognition/pixel14-scl113.md)、[清单](../../evidence/sc520-card-recognition/delivery-0113/manifest.json)。

T-018先在112原DB追加精确生成时钟，实际发现父→SCL hold=-3.055ns/removal=-3.379ns；未把所有父子路径false_path。随后只在自身overlay建立uii2c副本，内部全posedge父钟CE、239参数使SCL周期10080ns、2FF SDA和复位释放、事务数据锁存。原vendor未改，工程唯一引用已核。12上层模式8791检查0错，CE两组240相位/42复位偏移/488完成事务共496场景400555检查0错，正常/注错/提前停止均有独立资格；三卡线从机需外部复位恢复明确保留。[软件汇总](../../evidence/sc520-card-recognition/scl-coverage/software-validation.json)。

完整TD6.2.1两阶段exit0，311输入/快照一致；全局+0.142/+0.020ns、TNS0，14799LUT6/13967寄存器/15537slice/97ERAM/22DSP。I2C的49个带寄存器物理cell全部追回父PLLclk1，双向报告只有pll_clk_24m，setup/hold/recovery/removal最低1.115/0.055/39.435/0.091ns。原17链+新增SDA/reset共19链，三mailbox80/175/28位全覆盖，最长1.257/1.626/1.159ns；29ROM及精确125组独立bank/class BDD选择复核。[物理汇总](../../evidence/sc520-card-recognition/builds/6a50b113/scl-candidate-audit-v2.json)。

新route将shapeROM地址card_index[5]复制到_dup_4。保持旧审计器字节，T018适配器仅对该精确ROM的addra/b使用原厂模型证明的共同复位后等价映射，不做通用名称删后缀。2048输入/前态/CE/reset组合32796检查0错；最初1ns vendor配置模型q不同的2错证据保留，结论不含配置窗口。复位链原始Q/异步清零和PLL lock驱动已从真实网表核对。新主接替记录无每文件SHA，root另存确切文档SHA/对应记录SHA补绑定，未回滚主文档。

I/O边界：独立只读STA探针获得SCLpad传播1.338..2.803ns，SDA三态使能→pad未导出有效路径，探针因此返回未完成而非宣称I/O通过。仿真采用rise1000/fall300/slavevalid3450ns，得到SCL高低5040ns、SDAsetup最低1590ns/hold1518ns；实物RC/电平/输出使能传播/时钟容差与自动卡线恢复不在签核内，FullSystemTimingSignoff仍false。内部SCL覆盖缺口关闭不等于整个相机接口或识别功能完成。

C-002已实际查看两张D0112照片，计分初测正常只是用户报告。独立四组合真实color→分类计数300帧78613检查复现低饱和三色被tone或非单位WB破坏，白纸252被中性筛选排除；不是从屏拍提取的原始RGB。[反例与下一步方案](../../hardware/sc520-card-recognition/color-contract-next.md)。新增三阶段同帧诊断模块42场景1485检查0错、注错恰1/早停拒绝；只准备自包含模块与接口，未接ISP/CDC/OSD或113工程。首负向测试缺force传播delta未检出，root加1ps后重跑三模式；原失败保留。颜色定位产物与T018独立登记/提交，不改113镜像。后续最小A/B和诊断接入交主协调，仍禁止将COLOR_CORRECTION=0旧AWB称旁路。

T-019独立音频提交b0bff23已通知且获主审接受，音频/验证的后续用户日志不归本任务改写。本轮没有显示T017、音频RTL、硬件下载、Flash、真实COM、推送或合并。后面为之前时间顺序的开发记录。

### 2026-10-14 T-018接手

当前新主对话01a13a30-dddd-7a63-8384-6f9dde2bed6f按D-029接受f81483c为受限阶段候选，派发T-018补I2C SCL覆盖。工作树起点f81483c740d40e46262648d132bd07e6a5079a2f，开始干净，分支不变。已重读共享入口/索引、194011/194926主接手与审核记录、主库AGENTS/记忆/计划/任务/决策/接口/协调表和本日志；今后完成及真实阻塞只通知新主。保持D0112原字节供用户实拍，本轮不接T-017或改变识别算法。

范围：依据真实父钟、237覆盖分频、正负沿及SCL输出偏移补精确时序；验证父/子域request、payload、readback、busy/error稳定性、reset释放和外部I/O条件。先做现有路由DB独立约束观察，再据实际失败选择保留generated-clock或单父钟使能重构。不能仅按模块默认239生成约束，不能用宽泛false_path或放慢父钟掩盖问题；需要修改vendor uii2c时只在本任务overlay建立唯一活动副本。

并行只读scl_protocol_audit核对协议/器件资料。按主D-031另将音频台架T-019交audio_bench_fix在独立sc520-dfr0534工作树执行；其用户真实bench-sessions保持，不混入T-018提交。本识别日志仅记录调度，音频改动与本地提交由其自己的分支日志/共享记录管理。

### 2026-10-14 当前阶段交付

- 审核比较基线：3089ae8ee0daa6ffdbb581179eb2453d6c4fef5a。用户确认工程附带五张原卡全部不识别；本阶段完成成像灰化机制修复、960×480统一操作区、背景分离/归一化、每类256旋转模板和对称几何分流，不把软件结果当实物恢复。
- 最终候选：D0112 / build6a50b112。bit SHA256 `4C336D57C7D56DA5C132FCA38B75944C898F4D90EBE80D24842AE4DD4F2ADD47`，1789539字节；[复测说明](../../hardware/sc520-card-recognition/pixel14-rotation112.md)，[交付清单](../../evidence/sc520-card-recognition/delivery-0112/manifest.json)。活动TD工程已重新prepare为81个明确引用，包含旋转matcher、shape guard和块滤波器，不遗漏新增模块。
- 软件：最终[总审v2](../../evidence/sc520-card-recognition/rotation-software-validation-v2.json)验证8轮及4组件报告；80场景12813检查0错、28原相位拒识矩阵29场景449检查0错、旧720p管线19场景199检查0错。真实色彩RTL→全720p→识别→问答的24帧27648252检查0错，五张暗卡各第3帧正确确认，持续停留不重复计分；[色彩终审](../../evidence/sc520-card-recognition/color-validation-final.json)回读7轮并确认CSV与111逐字相同。所有注错/提前停止按预期拒绝。4320个中间角开发评测4292正确/28拒识/0错类，拒识未隐藏。
- 物理：TD6.2.1两阶段exit0、309输入与快照一致。原约束下SWNS+0.123/STNS0/HWNS+0.020/HTNS0；14779 LUT6、13939寄存器、15498slice、97/108 ERAM、22/40 DSP。29ROM含25个旋转bank逐字及译码/控制映射；17同步链setup/hold及80/175/28保留mailbox数据位Q/D完整，最坏传播1.381/1.516/1.331ns，未跳过跨域路径。[最终独立物理审计](../../evidence/sc520-card-recognition/builds/6a50b112/scene-candidate-audit-final.json)。
- 重要限制：原I2C内部SCL支路时钟/周期栏为空，112有25个物理时钟负载、0109为27；不是逻辑FF数，不能据覆盖率95.83%声称该域全部STA。root纠正辅助脚本把同一pin在两个报表中的重复行当唯一行及误假定旧负载也为25的问题，保留真实原报告，未改RTL/SDC/bit。[警告审查](../../evidence/sc520-card-recognition/physical-audit-prepare/candidate112-warnings-final.json)。仍无CRC/ECC数值证明、精确DDR帧身份、实物色彩/识别率/长测或真实音频资格。
- 交接建议：主对话先审核本阶段和上述继承覆盖限制，再安排用户受限SRAM实拍与SCL时序补齐。显示edaced3保留待T-017；不得直接复制第二套业务/字库/诊断，使用同一SCENE配置[160,1120)×[120,600)、原始S_p14_display_sof和当前健康/revoke状态。Logo自身10ERAM与当前97的理论和为107，非实际集成资格，须重新做整机资源/时序验证。本轮没有集成显示、上板、Flash、真实COM、推送或合并。
- 恢复说明：两次辅助代理服务错误/额度耗尽后，root直接接手落盘的脚本与报告，完成最终回读、警告修复、封存与登记，没有重新创建工作树或覆盖他人代码。D0109及1095个原scene-v1素材逐SHA保留。后续段落为真实时间顺序的开发历史，早期“进行中/待验证”不覆盖此当前阶段摘要。

2026-10-14 接续恢复：用户明确“继续执行”。工作目录、分支与 HEAD 3089ae8ee0daa6ffdbb581179eb2453d6c4fef5a 已重新核对；主对话恢复快照中的 1103 个遗留文件逐 SHA256 一致，未 reset、stash、另建工作树或覆盖遗留。主文档尚指旧负责人，按本聊天创建时明确接管授权执行，不将旧 ID 视为另一个活动写入者。共享规则、入口、索引、最新恢复记录及主库/工作树约定已重读。

本轮 root 负责接入、OSD、完整管线仿真、隔离 TD 6.2.1 与交付；imaging_audit 核对真实 SC520 曝光/增益、RAW 位宽、ISP/AWB 和显示/识别 RGB 链路；scene_model 接手整数模型和生成器，新结果使用 scene-v2 保留 scene-v1；scene_rtl 接手预处理器与独立测试。各代理只写划定文件，各批次自行登记，root 统一维护本日志和验收。

新增用户报告：使用纸质打印卡片，镜头画面总体暗沉、颜色偏灰且失真，影响识别。尚无本轮实拍或 RGB 量化，不能宣称已定位硬件根因。成像对照与场景算法分别验证；不能只改显示饱和度或放宽判色阈值宣称解决。旧 scene-v1 135 个卡片合成场景只有 27 个满足真值，须先诊断再建新验收，原样本不是通过基线。最终保留同物停留不重复计分、健康/未知/空场区分、坏帧/停流撤销资格，所有硬件复测由用户操作。

2026-10-14 进展：多模板匹配器先取同类三个变体的最小距离，再取不同类别第二名，避免把同类变体当低间隔拒识；默认单模板保留旧管线验证入口。独立人工距离测试24场景88检查0错，真实注错native1/errors1、提前停止native2/done0均符合预期；旧管线19场景199检查0错，现有显示47场景850417检查0错。新font生成45文案，保留SCENE_UI默认0的旧行为。场景20格归一化与3模板仍属候选，40/400有效格与旧40/784的比例不同，须用独立尺寸、负例和RTL整体测试评价，不把降低分辨率等同于准确率已提高。

主对话追加用户反馈：手机显示苹果等复杂图案也不识别，询问是否需要严格沿摄像头方向；当前尚未确认用户是否使用指定原卡图。已加入指定卡图/不同苹果图负例、有限平面旋转及透视压力对照，平移/尺寸修复不宣称支持任意旋转、倾斜或任意苹果照片。成像核查已发现旧AWB逐前缀累计调增益、gamma未实例化，真实RTL定量验证正在进行；这些机制尚不能代替纸卡实拍根因证据。

2026-10-14 用户随后直接确认使用工程附带五张卡面，并补充五张均不识别。此时已排除“用户另找图案”作为本次解释，旧上段的未确认仅是历史提问状态。五卡实物失败仍为用户报告，必须分别验证共用成像/取样链。真实旧AWB RTL对红220/40/30得到40/40/39，对蓝30/40/220得到39/40/40，对黄220/200/40得到199/200/199；同一红色在不同画面位置又出现40/40/39与88/40/32，证明前缀增益机制会改色。新候选保持整帧增益并增加独立tone开关，尚未硬件校准。

首次完整scene系统实际失败：p14-scene_system-normal-20261014-102329-ad9b9651，43场景/12180检查/8错。星星卡第三帧双路结果冲突被撤销，两张不同苹果负例被积木支路误作红三角；独立模型block预测与真实RTL不一致，已交模型/scene代理诊断，不以夹具模型通过代替系统验收。6a50b110为同时启动的TD资源探测构建，当前综合中，不能作为合格上板候选；之后若修源码必须重新构建，不覆盖此快照。

2026-10-14 后续核查纠正：block模型与RTL并没有上述语义差异，原scene-v2的truth_satisfied只按卡分支核对，遗漏联合仲裁；完整定义范围存在138个联合失败。原文件全部保留，rotation-v1的legacy-joint-comparison重新按最终结果核对。新增解析圆/方/三角轮廓guard：当前81真块最大距离17、138假块最小距离50；块必须通过对应形状，卡片必须不属于简单形状，双方在几何资格之后分别累计三帧。保证错误轮廓不能给之后的真目标贡献稳定帧。小积木/旋转积木仍有明确局限，不等于本次五卡旋转范围。

主D-025与20261014-102912-rotation-target记录已读取：用户明确五张配套卡在操作区内移动、变大小和0～360度平面旋转，透视另列实测范围。新增串行角度bank匹配器，每类256模板、五类并行，每模板400拍；模板RAM按variant*400+y*20+x、每字5bit布局。人工独立bank测试24场景88检查0错，注错与提前停止均拒绝。rotation-v1模型4320个独立中间角通过4292，28拒识保留，尚不能称为全部实物姿态通过。增加模板后曾出现圆形误苹果，已用独立简单形状否决处理；不启用造成更多误接受的±1格平移搜索。

6a50b110综合完成但资源拒收：54392 LUT、28129寄存器、50/108 ERAM、41/40 DSP；未进入可交付状态。root确认本任务phy PID53168/父68124后主动停止路由，保留intentionally-stopped.json及全部中间报告，未操作另一个TD或GUI。后续确认FIFO其实有RAM抽取，主要问题为两个RGB bank在读寄存器前合并mux形成6144个分布RAM LUT，以及flags等写端组织；scene代理改独立同步读写后局部仅4613 LUT/2468寄存器/28 ERAM/0分布RAM，继续核对归一化DSP。成像tone07已由delta乘法改逐码等价移位加法，256码与4轮仿真通过；实际整机资源必须用下一构建重新证明。

2026-10-14 全链路与时序续记：最终scene源码283152D9...EE8A独立206场景/7848451检查0错；rotation-v1系统80场景12813检查0错、28原相位拒识矩阵29场景449检查0错；真实输出注错和提前停止均正确拒绝。root软件总审rotation-software-validation-v1.json逐SHA验证8轮、4组件报告和1095旧scene素材、0109镜像及外部输入。真实color→capture→scene→rotation→业务另完成24个720p帧、27648252检查0错，五张原始gain65暗卡第3帧全部正确；其输出由真实RTL产生，after图片只作比较，不在输入预先tone。以上没有上板结论。

6a50b111两个阶段均exit0、309输入不变，资源已回到容量内（综合19865 LUT/13848寄存器/97 ERAM/22 DSP），但最终SWNS -3.084ns/STNS -399.690ns，保持+0.020ns，明确拒收。10条最差路径均来自color中性色选择、4lane求和、统计末组结算到DSP输入；不是旋转ROM。111生成的bit仅留历史，不能下载交付。29个ROM及25旋转bank逐字/选择译码已经独立核查；CDC完整报告17同步链和80/175/28保留数据位完整，日志空from/to只是Tcl集合echo呈现，不能据此误报缺路径，也未因此改SDC。

新color源5020B23A...420F31将统计改为4级，末组后4拍complete、6拍pending、rawSOF后4拍在首像素前统一提交增益；像素54拍路径和颜色数值保持。模块19场景及完整720p回归已通过，真实color-scene新轮进行中。root将版本标识设为D0112并启动6a50b112新快照构建，309输入、syn PID55356；待本轮自己的完整物理资格，不挪用111结果。主显示dba0181六层与Y24布局决定、20261014-111326共享记录已读，当前没有合入显示源码；ROI保持960×480，最终整机集成仍由主对话安排。

2026-10-13 使用性修复：用户反馈 D0109 非浅色背景持续要求移走旧物体、识别区域太小。主接续对话 01a1353e-db86-70e2-b918-7ee3d7f12973 按用户要求将实现交回本对话；本轮已 read_thread 核实用户授权、版号和分工。基础3089ae8ee0daa6ffdbb581179eb2453d6c4fef5a，工作树开始干净。已复读共享规则、最新主AGENTS/协调表、本库记忆/计划/任务/决策/接口/日志。范围只在本任务内新增背景/定位候选及接入、测试；不改前置工程、公共接口、四键映射或另一显示/Logo分支。

已查代码原因：capture_rgb96任何暗色/彩色像素即presence，只有计数严格0为空；quiz仍要求3个健康空场，导致普通纹理/阴影卡住。旧九类颜色候选有面积门槛，并非没有移走要求。当前卡片可见框480x480，积木实际640x480，区域不一致。新候选统一960x480操作范围，在120x60低分辨率缓存上用边界颜色参考与4连接背景剔除，少量噪点去除；保留未知目标presence，坏帧不当empty；图案bbox等比归一化到32x32并生成同口径模板，修摆位/尺寸限制。各阈值和可识别范围须实测/合成验证后如实报告，不能保证任意纹理或低对比目标。

分工：usability_design只写新pixel14_scene_preprocess.v；scene_model_tests独立Python参考、模板/样本、TB/runner；root负责参数化接入、端到端问答回归、文案、构建及最终统一登记提交。已有0109bit/快照不变，后续新候选独立build。健康/未知/空场和同物体持续停留不重复计分均为验收项。

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

- 状态：进行中。阶段基础提交 a698a53；负责人 SC520 断点恢复 /root，build_impl 负责原工程/构建与初始物理报告，review_compact 独立核对软件哈希和 CDC 逐位映射。build_impl 后续限流未能封存，root 接手最终恢复脚本、构建文档与登记；未覆盖其他任务。
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
