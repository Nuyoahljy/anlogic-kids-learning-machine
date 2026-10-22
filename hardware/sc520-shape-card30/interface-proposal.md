# T030 局部接口与最小文件提案

状态：等待主审核。2026-10-21，Codex `/root/contour29_reconcile`。本文件只是接口/资源方案，不是RTL、软件接受或TD许可。

## 识别数据流

从已冻结D0261实际活动链 `pixel26_bg_pipeline + pixel26_scene_preprocess` 抽取独立候选，不使用旧 `pixel26_pipeline` 中引用的另一份 `pixel14_scene_preprocess` 作为本次基线。

保原capture健康、双bank、边界背景分离、scene/glyph去噪与present。唯一完整glyph规范化输入同时给三形状评分与原五图卡模板匹配；模型B如必要，只增加完整glyph的负几何证据或第二种完整glyph归一化，绝无颜色body、边缘桥接、闭合或圆恢复路径。

shape/card同tag/source且健康完整后，只执行一次仲裁，再统一三帧确认；一个最终结果经单结果CDC与合法ID/新鲜性/超时join送业务。未知目标保持present，真实空场才能满足撤走门控。不得用颜色结果代替几何证据，不保两套独立三帧累计。

## 新目录

`catalog_id=shape3-cards5-v1`，版本字段为1：

| item | 含义 | 媒体要求 |
|---:|---|---|
| 0 | 未知/无有效类别 | 不触发物体学习媒体 |
| 1 | 圆形，不分色 | 必须新显式映射，不复用旧红圆曲号 |
| 2 | 方形，不分色 | 必须新显式映射，不复用旧红方曲号 |
| 3 | 三角形，不分色 | 必须新显式映射，不复用旧红三角曲号 |
| 10..14 | 原苹果/香蕉/汽车/星星/雨伞 | 由集成方核真实曲号与媒体；本候选不放行硬件 |

4..9在识别、题目、答案与物体音频事件接口上均非法。图卡不重编号。新`item_catalog.json`将包含语义键、中文无色名称、问题文字、目录版本和`media_mapping_required=true`，不填写未经验证的物理曲号。

题库顺序固定为`1,10,2,11,3,12,13,14`，8槽回绕；每轮仍10题/10分，下一轮起点加10模8，即加2模8。按键优先级、移走/重放、错误反馈、测试来源不计分等沿原业务语义。

## 192位识别诊断提案

新端口名建议为`recognition_packet[191:0]`及其独立`recognition_fresh/fault/age`，不继续输出或重新解释旧800位颜色统计。原800相关module、文件和历史契约完全保留，仅不在新工程实例化。

所有payload字段在capture域同一最终识别事务上单次组包。原始shape/card评分必须和packet的frame_id/source同帧，不能与上一帧持有值拼接。第1/2个健康帧可带真实评分与`valid=0,count=1/2`；第3帧后才给稳定有效类别。

| 位 | 字段 | 宽度 |
|---|---|---:|
| 31:0 | frame_id | 32 |
| 32 | source_test | 1 |
| 33 | frame/transaction healthy | 1 |
| 34 | present | 1 |
| 35 | confirmed valid | 1 |
| 36 | transaction revoke/invalid | 1 |
| 37 | scene clipped | 1 |
| 38 | border uncertain | 1 |
| 39 | paper amount diagnostic flag，仅统计不决定类别 | 1 |
| 43:40 | 最终item，0/1/2/3/10..14 | 4 |
| 47:44 | 本帧原始几何候选，0..3 | 4 |
| 51:48 | 本帧原始五卡最优类，10..14或0 | 4 |
| 54:52 | 三基本shape资格位，圆/方/三角 | 3 |
| 55 | 原五卡自身距离/margin资格 | 1 |
| 63:56 | 最终仲裁类别的连续确认计数 | 8 |
| 79:64 | scene_count | 16 |
| 95:80 | glyph_count | 16 |
| 99:96 | 本帧统一仲裁item，0/1/2/3/10..14 | 4 |
| 102:100 | scene/shape/card availability，各1位 | 3 |
| 103 | arbitration_done，实际本帧仲裁已完成 | 1 |
| 111:104 | 拒识/撤销原因bitmask | 8 |
| 122:112 | 完整glyph圆距离 | 11 |
| 133:123 | 完整glyph方距离 | 11 |
| 144:134 | 完整glyph三角距离 | 11 |
| 155:145 | 五卡best距离 | 11 |
| 166:156 | 五卡second距离 | 11 |
| 177:167 | 规范化foreground数 | 11 |
| 181:178 | packet revision=1 | 4 |
| 185:182 | catalog revision=1 | 4 |
| 186 | identity_known | 1 |
| 191:187 | reserved，必须0 | 5 |

原因bitmask按主修订：bit0坏帧/输入撤销，bit1身份/source/重复，bit2缺项/scoreboard超时，bit3触边/背景不可信，bit4竞争歧义，bit5分数/margin不符，bit6 overrun，bit7 flush/epoch。允许同一事务同时置多个真实原因。健康空场不能置bit5假称识别失败；其present=0、仲裁item0和有效完整availability足以区分空场。

availability位100=scene、101=shape、102=card，只表示相同frame_id/source的真实记录已经收到，并不等同这些记录healthy。错tag/source或重复记录不得强置available；尚未收到的记录为0。frame_id不能确定时identity_known=0，不伪填上帧身份。

shape/card记录不可用时，对应11位距离必须为`11'h7ff`不可用标记，候选和资格清零，不把初始化0当精确匹配。scene不可用时计数0只是占位，UI按available显示不可用，不能认作健康空场。

本帧统一仲裁item是三帧前的实际唯一候选；confirmed item仍在43:40。raw统一仲裁0立即使统一确认计数和confirmed item清零，不保留任一旧分族计数。任何非法ID强制显示/结果为0，并置对应结构/来源原因，绝不传出4..9。

若坏帧/撤销时无法确定frame身份，不伪造新的有效packet；通过revoke旁带立即使display fresh失效。`identity_known=0`的诊断不得被认作同帧识别结果。held payload可供故障定位但UI不能显示它为当前可信类别。

运输复用原已经过测试的bundled-data mailbox，宽度改192的实例是新接口，不修改原CDC模块。组包前等待scene/shape/card/确认记录的真实join；丢失、身份不匹配或已占槽重复写入为真实fault，撤销旧结果，不能覆盖掉问题帧。

fresh/age在display域以1ms tick独立维护，不从packet伪造：完整新packet更新age=0；age饱和计数；超时、revoke、flush、CDC overrun或source epoch不符立即fresh=0。只有下一笔完整同源事务和原恢复清空协议完成后恢复fresh；不以原data保持为新鲜。timeout参数保持原预算，具体恢复时序沿原mailbox/反向清空门禁。

诊断fresh不等于healthy：最新完整无效包可以是fresh=1/healthy=0，但必须把业务可信item/confirmed item撤销为0，不能以“该包新鲜”继续展示旧类别。新包即使分数拒识，也替代旧诊断快照；不是只在识别成功时更新UI。跨域失效旁带和packet抵达同拍时失效优先。

## 内部来源与组包时机

1. scene统计来自新scene的P_FINAL真实场景完成事件，scene/glyph计数和clip/border/paper diagnostic flag与该process bank的id/source一起锁存。paper只作统计，不定义目标是纸质还是几何。
2. 3shape距离来自该1024点完整glyph流的真实DRAIN结果，shape的id/source/健康一起入单槽；五卡best/second/fg及原始winner来自原matcher真实EMIT，同样入单槽。两者不能从held上帧值读取。
3. 单scoreboard等待同一id/source的scene、shape、card三项实际available。最后一项到达时将其当前记录与先前两槽比较；不靠NBA后值猜测该沿已有数据。检测到乱序/重复/占槽冲突则闭合为撤销事务，不覆盖旧槽继续装作完整。
4. scoreboard完整且健康才执行统一仲裁。仲裁结果及该帧全部分数/统计作为一份记录锁存；`arbitration_done=1`表示这一笔实际仲裁，`raw item=0`仍是一笔健康未知或空场，必须清零统一三帧计数。未完成的坏帧事务不能伪称done。
5. 统一三帧filter在仲裁事件后的约定下一capture沿消费整条记录，输出对应frame_id/source/item/count。诊断packet只在filter该帧输出事件时，把锁存的同帧评分和本次真实确认结果组包；不在同一个沿拼filter尚未更新的NBA输出。
6. 占槽直到packet发送/接收协议允许释放，同一frame不能发两次或先发shape后覆card。坏帧、flush、epoch、输入撤销会立即清pending与旧可信项；对仍可定位的失败事务可以发identity_known的invalid诊断，对无法定位的故障只发失效旁带，不伪归上帧。

本包只绑定capture识别事务，不把其ID当DDR相机图像或独立业务上下文已逐帧对齐的证明。具体字段以主`learning/sc520-shape-card30/recognition-packet-contract.md`为最终接口合同；本提案已按该合同修订，原800包原件与解释均不变。

上述时序是待RTL合同；无困难需借用颜色core、两套分类确认或原800统计来实现。scoreboard超时和transport超时仍需区分：前者是缺scene/shape/card，后者是本完整packet未能及时运输，原因分别置bit2/bit6并撤销。最终时钟预算/slot容量必须由真实双bank/60fps/超速回归验证，不能由方案假定。

## 新显示文件边界

建议独立新增 `pixel30_panel.v` 和 `pixel30_compositor.v`，原`pixel22_panel/content`及`pixel23_color_diag_osd`原件不改。新业务内容 `items30_content.v` 只使用现有字体已包含字形，不改旧字体ID/位图。若确需新字形，必须另登记独立字体资产与逐像素参考。

新compositor：

- 第1层原相机处理/原图与处理图选择，第2层新业务面板与新识别诊断，第3..6层原Logo；输入N采样、N+5呈现保持。
- 原输入FS单次锁存业务与诊断快照；不得双重frame snapshot或让新字号/面板改变视频管线。
- 诊断面板只显示本任务真实scene/shape/card/item/frame/count/reason/fresh，不显示不存在的WB/颜色统计。
- 旧重型color observer、800位统计transport、旧color diag panel不实例化。颜色统计无效状态不得伪装成全0的有效颜色结果。
- 图像/ISP54拍、显示位置与不重叠约束、四键切图语义保持；本任务不合其他gray/cartoon/style或AWB候选。

## 最小源文件清单

所有新RTL位于`fpga/rtl/sc520-shape-card30/`，不覆盖旧模块：

| 文件 | 职责 |
|---|---|
| pixel30_scene_preprocess.v | 独立单完整glyph场景，保持旧capture/bank/present与规范化契约 |
| pixel30_shape_scores.v | 三shape距离，模型主审后明确是否增加仅full负证据 |
| pixel30_arbitrate.v | 同帧双族评分join和一次仲裁、拒识 |
| pixel30_pipeline.v | capture、统一三帧、单结果CDC、轻量192组包/运输 |
| items30_result_join.v | 单结果合法ID/新鲜性/超时与撤销；不保旧block/card双pair |
| items30_quiz_control.v | 8类合法集合/8槽，保持10题和四键/计分 |
| items30_question_bank.v | 唯一8槽顺序表 |
| items30_system.v | 新single-result join、业务及render_state连接 |
| items30_content.v | 新目录无色文字/提问/回答内容 |
| pixel30_panel.v | 复用现有字体、单层业务/识别诊断绘制 |
| pixel30_compositor.v | 明确D0300版本、原六层显示、移除旧color diag panel |

新配置/交接资产建议为`assets/templates/sc520-shape-card30/item_catalog.json`、`hardware/sc520-shape-card30/recognition-interface.json`。本阶段不新建活动顶层、ADC、SDC或运行profile；后续若主准离线物理资源试验，独立profile继续三VERIFIED0/TRACKS空，不接真实音频引脚，不调用集成方工程。

## 资源机制与门槛

原Placed leaf事实仅作归属：scene28ERAM、matcher26ERAM、shape1ERAM是共享主要容量；删9色类不能直接声称回收这55个ERAM。

真正拟移除颜色core、颜色资格/确认缓存、双pair逻辑，以及observer约2903逻辑LUT/3798REG与800transport约787逻辑LUT/1437REG。该3690 LUT/5235REG是原模块leaf归属，不是新综合保证减量；诊断/单join新增成本需扣除，厂商优化共享也可能改变数值。

模型A为3基本距/1规范化mask。模型B-full-negative只用完整glyph的3基本+12椭圆负距，复用原16bit/1024字ROM（未用的r19 bit可留常量但不恢复圆）；保守预留16个计数、仍约1ERAM。模型B-axis-negative再增加完整glyph独立宽高归一的2个负圆距离，保守预留18计数/2归一mask；没有颜色body、桥接和原34距/四mask。上述只为机制估算，软件与资源方案主审后才能新TD实测。

本候选不以全unknown或删负例完成。模型必须逐组列错类、每类miss、unknown误报、真五卡回退以及同图SourceTruth/TaskTruth，保留暗卡和颜色退役前的已知失败。
