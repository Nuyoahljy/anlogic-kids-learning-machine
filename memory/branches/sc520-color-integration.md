# T026 固定颜色参数整机集成

- 状态：等待主对话审核
- 负责人：接续主聊天的唯一收尾代理 /root/color26_delivery_finish；接替已停止的 /root/color26_impl_resume，仅负责交付文档、工具与证据，不改冻结生产源。原主01a15235作为历史。
- 工作树：E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-color-integration；分支 task/sc520-color-integration；基础 c04530c。
- 用户授权：2026-10-19 接续主对话断点，将曝光1800、gain索引144、WB304/256/333、tone1、现场三色规则接入独立正式候选；显示相机底图饱和度×1.25。
- 最新主 D075 决定优先于工作树旧总文档；本代理不修改主专属文档。

## 方案和边界

全识别沿用 stage2（WB 后 tone1），stage1仅诊断旁路；保持54拍相机链、六层N+5显示、256模板、帧健康/背景/形状过滤、三帧连续确认、四键及问答。归一化采用精确100*(最大-次大)>=3*sum，sum0拒绝。G最大映射黄是当前传感器候选约定；纯绿归黄、理想等R/G黄色unknown、极暗偏色可命中，不能当作通用色彩定义。

主批准正式profile移除未核C18/D15/E12音频顶层端口/ADC；内部RX=1、BUSY=0，TX不引出；三VERIFIED0及空TRACKS。软件测试仍独立验证冻结音频核心。删除无外部输入后的RX/BUSY端口约束；实际综合若裁剪内部链须如实报告，不虚报CDC保留。

## 2026-10-19 首批实现

新建sc520-color26 overlay和sc520-color-integration RTL，历史T023/D0116/D0117/final05均未改。固定WB保留原统计和诊断链，只禁用自适应增益；新fixed_exposure等待初始化完成并发一次1800/144请求。新判色器用于积木及显示mask，饱和度仅作用mask之外的相机底图，OSD/Logo在后叠加。

已阅读根规则/入口/索引、主与工作树规则/记忆/接口/日志，核对现场JSON、分析脚本及修正ROI。实际源路径已核；SC520GainTbl索引144映射0F0080；AE分组表将1800编码3E00=00/3E01=70/3E02=80，并以3812=00/30分组。尚未运行本批编译/仿真/TD；不能视为通过。后续准备独立工程、样本/算术/完整显示与业务回归，再做正式profile综合布线。

## 待审核和风险

固定ROI每帧均值20/20不证明逐像素或背景/形状通过；新候选未生成bit、未下载/Flash。bitgen须主审核软件和物理后单独放行。

## 目标与验收条件

按D075/D076将固定现场参数接入独立整机，修复已复现的四个背景反例；保原十四类、四键/问答、54拍与N+5显示、未配置音频边界，最终软件和物理均交主审。bit须单独授权并绑定实际DB。

## 修改文件

新增任务局部RTL、sc520-color26/sc520-color26-bg工程、脚本、TB、hardware说明和evidence；历史tracked文件未修改，未改主专属文件。精确路径/用途见共享各批记录，实际构建图见261 inputs.json。

## 验证命令与结果

实际命令和结果逐批记录在后文；选定最终软件清单software-v2.json独立绑定7轮/296场景/124577044检查。物理尚待新261原生结束与主审，不引用260失败报告当通过。

## 证据路径

本树evidence/sc520-color-integration；主审与独立专项在共享learning/sc520-color-integration/review及main-review。源/工具快照、原始stdout、summary、输入/输出SHA均保留。

## 阻塞与风险

目前等待新261物理结论；4DN背景裕量为候选，边框干净而内区偏色会保守产生未知前景，多色边界也可能扩大包络。合成纹理通过不等于实板深/木背景通过。真实音频针位、媒体和BUSY仍未验。

## 待决策事项

主审核最终ROM、资源、时序和CDC后决定bitgen；真实设备仅用户按SRAM流程执行，本代理不自动下载或Flash。

## 建议总文档更新

主可在完成对应审核后更新D076实现与离线阶段，保留260负时序、四原反例及模型8DN失败历史；不得直接升级为硬件识别/语音验收。

## 下一分支交接

接手读根AGENTS/README/FILE_INDEX与最新主决策；沿用本树，先核实际在途PID和源SHA，不重建或覆盖旧run。后续仍由主指定唯一实现者。

## 首轮软件证据

2026-10-19 11:52，真实ModelSim10.7：numeric-normal-114833共163335向量/326694检查；render-normal-114848-ff3507四幅720p/17场景/11329115检查；pipeline-normal-114848-f6fc51场景到UART、四键问答5场景/807474检查；reset-normal-114921-8654d7七完整帧、54拍、固定WB与帧诊断/复位7场景/16485898检查。均native0/done1/errors0，原始输入快照和输出SHA见evidence/sc520-color-integration/runs下manifest。reset第一次仅TB声明位于task之后编译失败，已保留reset-normal-114848-61111c；修测试声明顺序后重跑，生产源未因测试改变。

现场stage2逐像素96000在数值RTL中全对照独立整数规则：蓝30287/32000、黄30918/32000、红30834/32000，其余unknown，无跨色误判；这不是形状/背景泛化验收。新四幅显示参考用第一真实stage2帧ROI均值swatch，其余文字、布局、字库、Logo由原独立字面生成器构造，未将DUT输出当golden。

固定曝光新增O_applied：实际请求必须经历AE配置done下降/上升才放行capture cfg_done，避免init完成但现场参数尚未写入的短窗口。原三帧迟滞与坏帧撤销保持。独立源准备器产生112工程引用/311哈希，正式profile默认三0空TRACKS，未开始TD。

## 背景反例与D076扩展（2026-10-19）

主转达用户明确要求继续修背景，不能把已有反例仅写成待泛化。四反例严格保留于scenes-normal-20261019-115257-c80240：21场景63帧/315检查，13错误/native1，不合格。四失败为红方深底(scene46/shape0)、红三角木底(scene0)、蓝方深底(scene1)、蓝三角木底(scene1)。其他5块/5卡/7均匀空场通过。同纹理仅换白底九块独立RTL对照scenes-normal-115620-a37f72，9场景135检查/native0；只说明颜色孔洞不是主要失败原因。

旧scene的RGB三通道±48洪泛吞掉了红方324个采样中的269、红三角171/171、蓝方1134/1156、蓝三角582/595。场景原始/模板/真实纹理SHA、范围与图示见scenes/manifest.json、scene-diagnosis-v1/diagnosis.json。原scene-model的相同洪泛/形状模型回读吻合真实RTL计数。

最小提案保留±48、边缘连通、纸张/形状与三帧，增加本帧边界R-G/B-G的min/max包络及小裕量。8DN的离线反例仍有红三角shape距离36，因此未接入生产；background-proposal-v2保留。独立敏感性envelope-evaluation-v1：2/4DN均21/21、6/8DN20/21。4DN对182旧rotation样本只替换scene时item/present、glyph/shape均不变；18类均匀/共同亮度波动/独立±4DN通道噪声背景为空。4DN仍为工程候选，不能当现场噪声统计校准。

原6a50b260输入冻结保持，syn PID27140 native0且10分区reset审计通过，phy在途；源修复若批准须独立新run，原run不具最终bit资格。独立审核代理另完成全RGB16,777,216算术0错及真实I2C12场景0错，证据在共享learning/sc520-color-integration/review，不由本日志伪称本代理执行。

## D076背景修复及真实时序反馈后的两级分类（2026-10-19 12:19）

主批准4DN包络新候选，新增pixel26_scene_preprocess和pixel26_bg_pipeline以及独立sc520-color26-bg项目，不改仍在构建的260源。首编译仅声明顺序错误被拒，scenes_bg/reset_bg两个失败目录保留，修声明顺序后原21场景/315检查/0错；原四失败期望完全不变。

完整scene-oracle-normal-20261019-121407-c11020：221场景（182旧fixture、21现场纹理合成、18空背景），95,278,070检查/native0；逐像素7200 RGB replay和1024归一化mask全部吻合独立oracle。这与此前模型仅比较glyph_count/shape不同，本轮确实比较每个输出mask位。

260真实物理反馈：Routed/Both SWNS -3.405ns、STNS -424.281ns；hold+0.020、HTNS0；最差scene replay RGB→归一化DSP×100→bbox共14级/12.875ns；明确拒收。同时report钩子audio reset不存在导致exit1，保留双重失败。Formal音频Q可能优化共享别名，不能靠名字断言全删除；新报告将保留全部audio对象及in/out，reset双端全无仅记录待独立证明，单边缺失仍拒绝。

主批准必要局部时序优化：新增pixel26_classify_pipe两级，A:max/diff/sum，B:移位加法×100与比较；pixel26_block_recognizer_piped将全部60位metadata同样延迟两级，原bbox/shape作为pixel26_block_core。原0.03规则、54拍图像、显示N+5、frame tags/shape三帧均保持。block_pipe-normal-121840-8ecbb6：23场景349478检查/native0，动态比对未流水版本每个完整健康/item/tag/source/count事件恰晚两拍，覆盖九形状、7种损坏元数据/栅格、flush、源切换及三帧恢复。

最终流水候选重新实际仿真：scenes_bg-normal-121713-17c1cc 21场景315检查0错；reset_bg-normal-121714-b483cf 7场景16485898检查0错；pipeline_bg-normal-121714-e55f8e 5场景807474检查0错。初版非流水bg证据保留。数值/显示未改，不重复其已通过测试。下一步新261完整综合布局布线，旧260不用于放行。

## 新261软件主审与构建接续

主已独立接受software-v2绑定的296场景/124577044检查；独立审查又完成新piped分类全16,777,216输入和metadata894检查。按主放行启动build-color26-bg.ps1 -RunId 6a50b261，117引用388输入，inputs SHA99CE59144021DC9FAA26F554850F0CCC530A1D816BC3467085A3B17C12EA5486。syn PID29740原生0，10分区reset综合资格通过；phy在途。旧260已经结束，未干预/重启它。

新增D0261 SRAM步骤草案和显式主批准JSON门控的generate-color26-bit.py；只执行--help，未bitgen。正式语音未配置、不暴露未核音频pad，用户只SRAM步骤另等主。software-v2.json保持软件结论，不回写物理通过。

非构建fixture生成器修为每次从原timing23 TB派生，避免重复在已派生TB插入oracle；未运行生成器覆盖现有测试输入，不影响冻结生产源/261。

## 软件源码Git检查点

已提交9c550baec978e68c836f6589c439eca950844e46：214新增文件，仅本任务范围，原c04530c已跟踪文件没有修改/删除。提交包括失败历史、独立候选源和软件证据；不是物理/bit放行。verify-color26-checkpoint.py逐字回读新候选源Git blob与261源/快照记录；结果见checkpoint-source-review.json。261原生布局布线继续，后续物理/bit证据另批提交。

## 2026-10-19 13:09 接手中断产物

本轮由主指定 /root/color26_impl_resume 接替唯一实现归属，沿用task/sc520-color-integration、HEAD9c550ba，不新建工作树。已重读根入口/规则/索引、主D075/D076及当日协调、工作树旧规则/记忆/接口与本日志。工作树总文档仍是旧初始化快照，当前范围以主D076及本轮接续派发为准，不回写主专属文档。

接手已有未提交内容为261 stages.json、result.json，SRAM草案漏检取证段、本日志检查点段及verify-color26-checkpoint.py。checkpoint-source-review.json实际于12:30:48产生，SHA256为08859073837F6E9F5E47B1C953CCA9181E805A07219734AA641623438FD401F5；历史记录已经登记它，本轮不伪称新生成或覆写。仅修核验脚本为已存在时比较语义而不写入，并同时核对全部388当前输入及快照。生产RTL、工程约束与冻结输入清单保持，后续执行结果另列。

261阶段记录显示syn_1 PID29740于12:26:39原生0，phy_1 PID29196于12:42:45原生0，ChangedInputs为空、没有bit。主已亲读报告头+0.107/+0.010ns双TNS0；这不替代独立ROM/CDC/全物理主审。未重跑TD、bitgen、下载或Flash，build result中的TimingQualified=false保持为生成器当时未签核状态。

generate-color26-bit.py已读：须Stage=bitgen_approved、ApprovedBy、Purpose=SRAM validation only、HardwareValidated=false，并核RouteDatabase/BuildInputs/SoftwareReview/PhysicalReview四SHA和全部当前源/快照；输出目录必须不存在。收到主绑定SHA批准前不执行。主审后具体命令为python -B -X utf8 fpga/scripts/sc520-card-recognition/generate-color26-bit.py --approval <主提供绝对JSON路径> --output <本树evidence/sc520-color-integration/下新目录>。三VERIFIED0/空TRACKS及音频外部隔离保持，实板背景/位置/光照仍待验证。

13:10实际执行python -B -X utf8 fpga/scripts/sc520-card-recognition/verify-color26-checkpoint.py，原生0：24任务生产源Git blob、388当前输入、74源快照均吻合；已有checkpoint结果仅校验不覆写，前后SHA保持。inputs.json SHA仍为99CE59144021DC9FAA26F554850F0CCC530A1D816BC3467085A3B17C12EA5486。git diff HEAD -- fpga/rtl fpga/custom_project为空；c04530c..HEAD的既有文件M/D/R为空。真实结果保存在resume-verification-20261019-131003.json。全树git diff --check只因原生stages.json的CRLF报空白，原产物不为格式化而改写；人工文件定向检查另执行。下一步等待独立物理结果和绑定SHA的主批准，当前无bitgen资格。

## D077 离线接受与 v4 唯一交付收尾（2026-10-19）

本节为当前状态，上文“物理待审核”“禁止bitgen”和“未生成bit”为原时点历史。主已实际执行 software-v2、固定261和bit身份复核，并接受离线阶段；当前收尾文件等待主对话审核，现场尚未验证，未合并稳定基线。

主批准为共享 learning/sc520-color-integration/main-review/final-261-20261019/bitgen-approval.json，限定从 SHA3A95B2E4A0C801703D5A498F161267F5D560328DC934F7BE0E0B867308001CC1 的原路由DB生成SRAM测试bit；不授权重构建、下载或Flash。原生构建 result 中 TimingQualified=false/BitGenerationAllowed=false 是生成器12:42:45当时未签核的历史状态，保持原字节；当前接受由独立主审核提供，不回写原报告。

旧实现先后实际生成四个目录。v1启动路径反斜杠导致脚本未执行，无bit；v2工具原生0且旧包装Complete=true，但原始stdout含8条PRJ-9210 ERROR，明确拒收；v3工程cwd修正后仍有6条MAX_PATH相关PRJ ERROR，拒收。v4临时subst共同worktrees父目录，保留fixed-roi与本树相对关系，原生0、无ERROR、stderr空、实际导入原DB和完成marker；finally解除本任务V盘。前三次结果和bit保留为历史，绝不覆盖、升级为合格或交付。

唯一bit为 evidence/sc520-color-integration/bitgen-d0261-v4/sc520-d0261.bit，1789539字节，SHA256 FB9CBC03119EF3F58F366BD0AAA09C895E7C7C877D1535250F983AE5C5346D40。主报告 delivery-261-20261019.json 实际核403受保护输入保持；冻结源仍9c550ba，388构建输入未变。生成器当前SHA与v4 result的GeneratorSHA256绑定，收尾没有再运行TD/bitgen。

当前生成器修复Windows路径、工程cwd、MAX_PATH临时映射和严格ERROR拒收；这两处工具改进及verify-color26-checkpoint.py随收尾提交。检查点工具固定比较已批准9c550ba，并核它是当前HEAD祖先，避免仅交付元数据提交使旧报告Commit比较失效；已有checkpoint-source-review.json不覆写。

交付清单 delivery-manifest.json 绑定主批准、软件/物理主审、适配证明、原DB、388输入清单、生成器、四次原始result/stdout/stderr和唯一bit。Git仅纳入小型清单/日志/Tcl/批准副本；bit、DB、TD缓存仍在本机原路径，按manifest迁移并复核SHA，不能把Git克隆当作完整交付包。

主实际物理结果为Routed/Both +0.107/+0.010ns、双TNS0；19040总slice、107ERAM、25DSP。12139个带LATCHMODE的寄存器LSLICE均DFF，不是19040个寄存器。厂商DDR告警窄证明、6条裁剪音频reset匹配critical及全部原失败保留，最紧recovery+.110ns；无MTBF、完整外部IO或DDR硬件结论。本次仅读既有主报告，不冒称重做独立物理或软件。

待决策及下一步：主审核本次收尾提交和共享登记后，按最终主审核与d0261-sram-guide.md交用户PROGRAM_SRAM，优先四原背景反例，再九积木/五卡/空场、位置光照、四键问答。4DN包络及干净边框/内区偏色限制保持；三VERIFIED0/TRACKS空、音频外部隔离保持，现场无声音不升级或降级本次颜色结论。不恢复无关开发。
