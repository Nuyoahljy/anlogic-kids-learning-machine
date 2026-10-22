# T030 真实综合后审清单

状态：2026-10-22仅准备；D094软件接受不等于综合执行或物理资格。真正启动还需要未来 `synth_only_approved` 绑定精确源提交、软件审核、独立准备审核、wrapper仿真、准备清单、执行器和TD工具。

## 原始来源

先核始末真实PID/父PID、命令、cwd、UTC/本地时间、native退出；`synthesis.complete`精确完成内容和新鲜性、stdout准确完成行、新`shape30_gate.db`/`shape30_gate.v`及全部原始report哈希/大小。失败或中断不得补写成功、沿用旧294/r4数据库或重试覆盖。执行前后software freeze全部45条、额外原matcher验证参考、准备文件/ROM副本、审核绑定和TD哈希保持，任何变化列入ValidationErrors。

## 全量和分层资源

读取完整rtl.area、gate.area、gate_full.area、综合网表和全部告警，不只看某个leaf或总面积摘要。逐项列LUT/REG/ERAM/DSP与PH1P35容量；分别列pipeline及capture/scene/scorer/matcher/arb/filter/forward192/reverse1/join/quiz/display/font/Logo和wrapper225bit输入存储、四分块写入decoder/mux、3bitphase、64bit观察mux与pads。资源探针不等价于最终生产输入接口或逐周期时序；新增存储不得计为识别模块节省。

确认scene仍保原双bank与7200 FIFO，matcher全256variant/102400五bit模板、完整400capture mask、形状1024×16ROM与17个比较计数真实存活；字体/Logo完整实例和ROM不能在 `RENDER_ENABLE=1` 被裁掉。不存在colorobserver/旧800transport/旧重颜色形状core实例，不因旧ERAM归属而预填净减量。

## 初始化和推断

按每个真实RAM/ROM实例列宽度、深度、block数、ROM初始化来源、端口同步读和推断告警。模板102400、几何1024、Logo index16384、palette1024及font位图均核来源SHA与网表初始化/映射；检查不存在漏读、截断、黑Logo、空字体或未初始化X。检查捕获mask无不必要异步复位妨碍RAM、两pass流和snapshot状态实际保留。

## 时钟、复位、CDC和告警

本隔离两时钟9.660ns和13.468ns只保持模块预算，不包含板级PLL/IO时序签核。核clock summary与gate timing，发现未约束/生成时钟或clockasdata立即报告；不加宽时钟预算清告警，不用gate timing充route结果。实际capture/display双级复位释放、capture_release六复制、192mailbox request/ack+held payload、反向clear、故障和flush同步器全部在网表存活且正确时钟/复位归属。

逐条审重要告警：ROM/RAM推断失败、constant pruning、宽度截断、未驱动、多驱动、锁存器、CDC/异步复位、timing unconstrained、blackbox、top IO容量、优化错误。新v4仅模块资源探针，137名义IO为3直接时钟复位+64数据+2选择+1使能+67观察，不超过现有PH1P35报告160容量。原v1/v2/v3包装295名义IO仅作为准备风险保留，没有新TD失败；未找到本地TD6.2.1文档可证明的virtual/noIO选项，不臆造参数。不占用板针位/ADC，不以其IO报告签实际板。审任何工具追加文件，不从成功token推断全部质量。

## 结论门禁

报告只写“实际综合完成/资源候选通过或未通过”，不得写整机时序/bit/八类实物通过。原有白底/正放/已测尺度模型范围和全部miss保持。独立与主接受本次综合/资源后才由主发冻结模块给指定整合对话；最终完整布局布线、ROM/reset/CDC实际端点、bit和现场由总集成负责。
