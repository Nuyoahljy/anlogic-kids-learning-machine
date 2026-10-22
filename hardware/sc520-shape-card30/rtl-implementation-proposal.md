# T030 固定C有界原型RTL实施提案

2026-10-21，Codex `/root/contour29_reconcile`。状态：等待独立完整C复核与主一次软件实施批准。本文件不授权RTL、综合、route、bit或硬件。本侧按D089最终只交模块候选及获准后一次综合，由指定总集成方统一完整物理。

## 已测范围

固定C报告为`evidence/sc520-shape-card30/model-c-v1/report.json`，SHA `9B2924425413E6817962D667A5A8B3780F87EA9A6F76F6C79C95DFAC4CFED610`。全部组0错类/0unknown误收/0误苹果，原正确卡回退0；这不等于全部几何稳定。

- 原182和保留203各有5暗卡漏识，原完整数据保留；原62组全对，new202仍17漏识。
- holdout80卡79正确、1漏识；苹果`h_card_10_a157_s67_g100`保守拒识，不为消掉该例修改模型。
- holdout72几何42正确、30漏识；原new142组仍50漏识。圆在原/holdout均正确；方主要支持0/90度，三角主要支持正放，其他角度正例仍明确列miss。
- holdout30负例与1280原模板均正确。模板无RGB/Y/bbox不作实物几何证据；182holdout实际158独立decoded图且有3个与原集重叠，不以总行数作独立实测数量。

建议仅把C作为固定白底、几何正放及既定尺度内的保守软件原型，不宣称现场验收或任意角度。原模型A/B及其全部失败留存。

## 源文件

原目录文件不修改。新RTL均放`fpga/rtl/sc520-shape-card30/`：

| 文件 | 明确职责与复用边界 |
|---|---|
| pixel30_scene_preprocess.v | 从实际D0261 pixel26_scene_preprocess独立派生；双RGB bank/flags/clean_mask/FIFO不增；增加完整glyph Ymin/max与bbox/元数据输出；仅两种完整glyph归一流 |
| pixel30_shape_scores.v | full3基本+12负ellipse距离、axis2圆alias距；复用同16bit1024word常量ROM，一次读口，17计数；保raw/effective分离 |
| pixel30_arbitrate.v | 真实同帧scene/shape/card单事务scoreboard、固定C决策、原因位；不颜色分类、不两族分别累计 |
| pixel30_pipeline.v | 复用原capture、matcher、统一3帧filter与CDC组件；包含192组包/一次CDC发送、反向清空、安全失效、display鲜度运输 |
| items30_result_filter.v | 独立统一确认filter，合法集合仅1..3/10..14；沿原三帧状态/来源切换/复位/flush/8位饱和计数，旧card filter原件不改 |
| items30_result_join.v | 单结果结构/合法8ID、frame/source新鲜性、100ms超时与立即撤销；不保旧block/card双pair |
| items30_quiz_control.v | 独立派生原四键控制，8合法目录/8槽，保持10题10分/撤走/测试不计分 |
| items30_question_bank.v | 唯一8槽顺序1,10,2,11,3,12,13,14；轮起点+2mod8 |
| items30_system.v | 新单结果join/control/28bit render_state；保业务和图像快照分界 |
| items30_content.v | 无色圆方三角新名称/提问/答案；复用既有字形ID，不沿旧红色文案 |
| pixel30_panel.v | 同旧panel一层字体延迟绘制业务+192诊断，缺值显NA；不实例旧color diag panel |
| pixel30_compositor.v | 原视频处理1层+新panel1层+原Logo4层，N+5；原输入FS单次快照，版本0300 |

另加一个任务私有常量头`recognition30_packet.vh`，只命名已批准192字段/原因位/合法目录，单独逐位测试。不是扩公共头或修改旧模块。

不新增封装模块仅为换名；12模块对应独立时钟/事务/业务/绘制职责。若现有组件可原样复用就直接例化，不复制其源码。

## 直接复用清单

- `capture_rgb96.v`：原输入完成时机/身份和ROI采样；不动ISP或54拍链。
- `pixel14_rotation_matcher.v`与原`rotation-v1/templates.mem`：五卡256变体、5bit模板、400点与旧类间margin24，零新增模板。自身40门槛保持，C仅在仲裁对苹果施加32；不能把旧matcher max全局改32。
- 原`card_result_filter.v`只接受10..14，不能原样用于新1..3确认。本候选新增`items30_result_filter.v`，统一仲裁后唯一实例/参数3；candidate精确合法集合1..3/10..14，保持原last_source/reset/flush/next_count8位饱和算法。外部仲裁/join也独立核合法集合，但不能用外部判断代替filter内部资格修正。旧filter原件不改。
- `pixel14_result_cdc.v`：参数WIDTH=192用于最终packet，WIDTH=1用于真实反向清空；不改其握手、reset和fault算法。移除旧132双结果通道、800 observer及额外颜色transport，避免再加一套诊断CDC。
- 已冻结字体ROM、Logo、原图/处理图选择及显示delay组件原样复用；新content直接沿现有glyph ID选字。

新catalog资产`assets/templates/sc520-shape-card30/item_catalog.json`明确目录shape3-cards5-v1、合法8ID、文字和media_mapping_required；不填真实曲号。几何ROM若复用原T02916bit文件，只认其静态基本/负ellipse/alias常量及SHA，不导入body/recovery算法或原RTL。新runtime或验收配置必须明确禁止音频硬件门控，三VERIFIED0/TRACKS空。

本阶段不新增活动整机顶层、AWB、style、TF、音频GPIO或改原ADC/SDC。模块测试的极小wrapper只作为testbench，不注册为新活动板级工程。

## 场景提取与评分时机

保原D0261 background chroma envelope/过滤/健康语义，scene与glyph仍同原RAM及过滤流程。不新增一份RGB frame或双mask存储。

Y只从本帧真实clean glyph中心RGB取得。原FILTER_CHECK遍历3x3邻域，FILTER_STORE时的rgb_q可能已指最后邻居，不能直接用它算中心亮度。新派生在`filter_neighbor==4`时锁存10bit扩宽求和后的center_y，在后续FILTER_STORE且filtered_glyph成立时更新Ymin/max；bbox与glyph_count在同一资格上更新。每process bank启动/flush/坏帧必须清Yavailability，不复用上一帧extrema。

原full规范化输出完整1024点，五卡matcher只消费这条原full流。随后同一scene FSM第二pass输出完整glyph独立宽高归一，shape scorer只累计2个圆alias负/轴距；其余3+12距只从full流累计。两pass共用原clean_mask同步读口及同一ROM，不能同拍从单口读两个不同地址；不复制mask换吞吐。

metadata在同帧第二pass完成后一次发布：Yavailability/min/max、bbox宽高、scene/glyph/paper_flag/clip/border、id/source。shape scorer发布原full3/ellipse最小/axis最小及健康，同步显式结束事件；card matcher可能先或后完成，仲裁必须真实等待，不能依赖固定延迟猜已到齐。

## 固定C与统一确认

严格按冻结B17模型：Yspan>64只拒几何；bbox有效且min*8>=max*7才用axis降低effective circle；raw full circle永不被覆盖。唯一形状资格<=20且fullEllipse>min(effective3)+8，几何还须cardbest>geometrybest+8。卡自身margin24、仅苹果<=32其余<=40，卡还须min(effective3,fullEllipse)>cardbest+8。Y拒几何不删形状竞争分数，不以SH0自动放卡。

所有乘8/7/10bitY操作扩宽，不能Verilog隐式截断。scoreboard所有记录带id/source，支持合法先后到达，重复/错身份/缺项或占槽冲突立即撤销，不把held值装作本帧。

arb记录和全部raw分数/元数据锁存后，统一filter下一沿只消费这一笔。filter out_frame时把其更新后item/count与同id/source arb记录组192包；用显式pending/完成事件，不在同一NBA沿拼旧count/旧第三帧item。候选0、空场、坏帧、source变化/flush均打断唯一确认链。

192packet遵循主`recognition-packet-contract.md`，包括availability、不可用2047、unknown identity清零、原full三距离、raw统一候选和确认item/count。packet fresh只表示运输年龄，不等于healthy；latest invalid事务必须撤回业务旧可信类别。不能只在成功时更新diagnostic。

## 测试及唯一Runner

新增一份直接`simulate-shape-card30.py`显式选择新/旧依赖与输入快照，不扩旧exec/replace链。每run保真实command/PID/native、源码/输入前后SHA、summary/done以及失败历史；源选单不得同时编译旧/新同名模块。原所有runner/TB/fixtures不改。

建议TB分6个明确验收面：

1. `tb_shape_card30_scene.sv`：原D0261单mask在同图上逐位等价；Y中心取样、bbox、full/axis规范化独立数组期望，边界/首末/RAM同步延迟；所有旧2071适用RGB及holdout182来源不改。
2. `tb_shape_card30_scores.sv`：17距逐项与模型一致、原1024×16 ROM常量推导；circle raw/effective、Y/7:8/aspect/ellipse/卡32/40/margin24/8等号及±1；shape bits不把negative当正。
3. `tb_shape_card30_pairing.sv`：scene/shape/card各到达顺序/错tag/source/重复/丢失、超时、flush；新统一filter对1/2/3/10..14分别实际三帧确认、4..9负向、统一0清count、三帧前后边界和撤销恢复，所有192位组解包。
4. `tb_shape_card30_system.sv`：完整RGB pipeline固定C逐case/3帧/原新Truth；8类题库10题/10分、全键/答案/移走/测试不计分、无色文字音频事件，不触真实UART/GPIO。
5. `tb_shape_card30_stream.sv`：原capture/display双时钟、4帧不等待的约60fps、双bank、192 busy/overrun/鲜度/年龄/100ms/epoch清空；原1.2M每帧上界不放宽，轴pass实际周期纳入。
6. `tb_shape_card30_render.sv`：四720p场景逐像素/目视、0300与新无色文案、同FS单次快照、图像54拍与N+5/Logo位置；NA和最新invalid不能显示旧可信ID。

每类注错至少一项实际负向（如axis/full错接、错第三帧、未清pending或位图错一位），证明checker能拒错误；不通过改期望或拉timeout掩盖失败。

## 资源目标与交付

目标是scene/matcher/geometry ERAM不增加，删除颜色core与observer/800transport/旧diagpanel，使用一个192识别/诊断复合packet替代双结果加颜色packet。不是承诺仅删类别即可释放scene28/matcher26等共享RAM。

新增axis pass与17距/Y/仲裁必须用实际软件吞吐和后续一次综合核RAM读写推导、LUT/REG/DSP/ERAM/关键告警，不能以模型预算当资源已省。综合前软件独立/主审和精确输入批准仍必须完成；本侧不再运行临时整机完整route或bit。
