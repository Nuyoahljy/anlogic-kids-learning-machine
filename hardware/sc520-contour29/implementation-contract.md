# T029 v4 实现合同候选

2026-10-20，Codex /root/shape27_delivery。本文提交主审核后才进入完整RTL，非已验证接口或资源结论。模型证据以evidence/sc520-contour29/model-v4/report.json为本轮入口，v1/v2/v3保留失败。

## 资格与拒识

原full glyph的3bit理想圆/方/三角距离<=20，原glyph内主色覆盖>=2/3和各>=2倍其他色全部保持。原严格形状已接受且无新同帧明确冲突的基类沿原资格；T027的20%/25%内部灰/错色损伤用例仍须保持。

新增恢复仅当旧full shape为0时评估，必须同时满足：

- 原full glyph颜色覆盖和主导成立；色body封闭域自身覆盖>=2/3，body主色与full相同，面积均至少12。
- 色种子来自glyph、旧3%赢家、相对边界色度包络差异；仅同色对向端点、1采样格且色度差至少8DN补缺。mask不会仅因灰度阴影边缘而扩大。
- 种子与闭域宽高均在4/5..5/4；修补不触闭域四个极值边界。body按独立宽高归一后，半径19或20采样圆距离<=20且严格优于非圆椭圆族。半径19是新增采样别名，明确改变可接受模板集合，不能声称完全沿旧圆模板边界。
- full glyph处于body闭域以外的像素少于12；达到旧最小有意义成分面积12时保持未知，不能删除外部柄/尾巴/中性轮廓。内部封闭孔洞与外连缺口不同，后者导致外部残差时可以保守未知。
- full轮廓与非圆椭圆族的最近距离>20，不能让body恢复盖过完整轮廓的明确反证；完整与body出现不同基类资格时未知。
- 原卡片raw无效，或恢复几何距离+16严格小于同帧card_best；新body不无条件优先。所有判断完成后才计三帧。

五卡仍用原256模板、best<=40和异类margin>=24。SH0不是充分通行证；同帧full/body轴归一圆证据或非圆椭圆距离<=20作为negative_only拒识，不能作为公开SH圆位。否则原card_best+16须严格小于full/body可用canonical几何最近距离。没有红色禁苹果规则，也不因为无色body就认空场；present/纸面/触边/健康完全沿full scene。

固定模型真值下，182旧样本无新增丢失、62原T027全部通过、1280原模板无新增negative拒识；148合成无错类及圆走苹果，只有7项恢复、46项原定圆保持未知。显著中性阴影、连通到外界的缺损和几何竞争不清并非全部恢复，不按本模型宣称实际识别通过。

## 结构与局部位宽

| 来源→接收方 | 新增局部信号 | 位宽与语义 |
|---|---|---|
| pixel29_scene→pixel29_shape_guard | contour_fg | 1，同card_valid/index拍，body按最长边规范化 |
| scene→shape_guard | contour_axis_fg / full_axis_fg | 各1，同index拍，body/full按独立宽高规范化 |
| scene→shape_guard | contour_qualified / contour_aspect_good / contour_boundary_repair / contour_exterior_ok | 各1，与card_id/source同帧；前者包含area/颜色主导/纸面触边 |
| scene→pipeline | contour_color | 2，1/2/3；不替代full glyph颜色核的原覆盖结果 |
| shape_guard→pipeline | original_shape_ok / contour_shape_ok | 各3，仅圆/方/三角 |
| shape_guard→pipeline | negative_only / recovery_geometry_good | 各1，negative不映射SH位 |
| shape_guard→pipeline | recovery_distance / geometry_minimum | 各11，与其frame_id32/source1/healthy1一同缓存 |
| pipeline内部 | raw_record | 原49位，仍绑定完整glyph颜色证据 |
| pipeline内部 | shape证据快照 | 形状与内部负类/恢复距离固定字段+frame_id32/source1/healthy，公开诊断包不扩宽 |

完整与色轮廓由一个1024地址、16bit常量ROM并行比较：bit0/1/2为原圆20/方/三角，bit3为圆19采样别名，bit4..15为非圆椭圆aspect0.6/0.8 × angle0/30/60/90/120/150。1024×16=16384bit容量目标落单20K块；必须用新综合确认实际bank、地址与内容，不预称零新增ERAM。

原scene完成背景filter后，flags[1:0]/fifo按阶段复用为seed/bridge和外部flood，clean_mask维持2位。旧RGB仍只读，不加数组reset；三次额外规范化读取串行复用原shift/add与长除法。不将运行时变量平方/除法塞入像素关键路径。

## 事件身份与周期

采集54拍、显示六层N+5和observer timeout不变。新shape先完成并缓存，但基类确认改为在同帧matcher完成match_event之后，与五卡一起计算最终资格并分别进入原三帧过滤。full原基类与恢复基类都不能在shape阶段先积累、再被card覆写。

raw、full shape、body、negative、card及诊断均须frame_id/source/healthy一致。任一缺记录、坏tag/source、超界/乱序采样、同槽覆盖、drop/flush/source epoch变化，须即时撤销可信资格和计数，不把缺结果当空场。新原子pair仍由已有mailbox发送，不新增独立跨域通道。

粗略最差计算：N=7200，双flood各不超过约16N状态拍，旧filter29N，seed约3N、bridge约15N、汇总约3N、replay3N，四组400有效格规范化各约35拍，256卡模板102400拍，合计约0.8M capture clocks量级，低于既有1.2M帧完成等待界。该值仅预算；RTL须记录真实总状态周期、最大FIFO、256模板最差完成时刻及连续60fps bank不溢出，任何实际越界不能放宽等待值来通过。

## 独立验证

真实旧D0270与D0290相同文件/标签完整跑，保留旧苹果误报。独立guard TB不用本模型当期望；比较16bit ROM全部1024字、距离/negative/public SH，覆盖角度/aspect和±1边界。pipeline覆盖先shape后match、相邻frame交错、丢shape/raw/match、身份错误、source epoch、坏EOF、复位/flush、原三帧及撤销恢复。全旧九类/五卡、灰图卡、灰大图红patch、外appendage、孔洞、空场、触边、纸面及旧21场景仍保留；四720p/N+5与原业务回归后才软件主审。
