# 积木完整轮廓资格检查

日期：2026-10-14；负责人 `/root/imaging_audit`，父任务负责活动管线接线和最终构建。比较基线是当前scene-v2和未改的 `block_frame_recognizer`。既有110构建快照保留，不把新RTL当成其输入。

原积木支路仅按某一种颜色的面积/bbox比例判断形状。例如0.4～0.625占比就可能归入三角，卡片内的星形、香蕉或另版苹果局部色块会因此成为积木候选。此候选检查场景输出的**完整归一化glyph**，给已有颜色/形状结果增加一项独立资格。

私有新增文件：`fpga/rtl/sc520-card-recognition/pixel14/pixel14_block_shape_guard.v`，SHA256 `2BCB1AABD82168E05CC5E17C026D70A3FBC2B605444BF9050E244BF0AB4BD58B`。原积木识别器没有改动。

## 数学合同

输入为当前场景模块的32×32二值mask，20×20有效窗口在 `[6:26,6:26]`。窗口之外模板为零；比较全部1024位，不能漏掉外围异常像素。窗口内令x,y为0..19：

| shape_ok 位 | 形状 | 模板像素为1的条件 |
|---|---|---|
| 0 | 圆 | `(2x+1-20)^2+(2y+1-20)^2<=400` |
| 1 | 方 | 整个20×20窗口 |
| 2 | 正置三角 | `2*abs(2x+1-20)<=2y+1` |

三路Hamming距离各自不超过20则对应位为1。门控必须使用 `shape_ok[(block_item-1)%3]`，保留原颜色类别及原item，不能把任意一位通过都当成积木有效。它不创建类别、不强制卡片优先、不改变presence。形状不符仍为健康且有物体的未知候选。

同步常量ROM为1024×3，模板坐标运算只在初始化展开，不在采样数据通路上综合乘法器。输入端口与当前card流同名。每个start后需要严格按0..1023输入1024点，允许点间空拍；start同sample、end同sample、缺点、多点、重复index、帧号/来源中途变化都会拒绝。flush取消在途结果。END后一拍输出 `out_frame` 和同tag的 `shape_ok`/距离；下一SOF可同前帧结果发布同拍，测试确认前后tag不混合。root仅将同tag结果与已暂存的积木记录配对。

## 独立依据和验证

`generate_cases.py` 独立回读scene-v2的PNG，逐一核对manifest SHA，再重算scene mask并检查原mask SHA。选择 `required && block_item!=0` 的219例：81真积木的对应模板距离最大17，全部保留；129卡片、7扰动卡片、2另版图案，共138假积木的最近模板距离最小50，全部被拒。门槛20保留了3位正样本余量，距离已测负样本至少还有30位。

另增加解析模板、19/20/21位翻转阈值边界、全空/全满、8×8内孔，以及135个独立尺度/小角度理想块观测，共377个模型向量。ModelSim检查整个ROM的距离输出和13个流协议场景：正常390场景、389114检查、0错；真实输出注错native1/errors1/injected1；500ns提前结束native2/done0。三个运行的源/输入快照/输出SHA由 `audit_guard.py` 回读通过。证据位于 `evidence/sc520-card-recognition/block-shape-guard/guard-audit.json`。

```powershell
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 evidence/sc520-card-recognition/block-shape-guard/generate_cases.py
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 evidence/sc520-card-recognition/block-shape-guard/simulate_guard.py
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 evidence/sc520-card-recognition/block-shape-guard/simulate_guard.py --negative
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 evidence/sc520-card-recognition/block-shape-guard/simulate_guard.py --watchdog-probe
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 evidence/sc520-card-recognition/block-shape-guard/audit_guard.py
```

## 已测限制

这是一项允许20位误差的近似形状资格，小孔或轮廓噪点可在预算内通过，不能称为通用凸性/实心证明。135个独立压力观测仅用于量出范围，不计为135个正样本识别通过。

- 独立16格直径圆归一化距离21，被门槛20拒绝；20/28/40/56格圆在本次±15度观测通过。
- 16/20格正置三角的距离34/40，会被拒绝；较大正置三角通过。细小的采样边缘变化会影响归一化距离。
- ±2度方块在所测尺寸通过；±5度及更大的方/三角基本拒绝。当前三模板不提供任意旋转积木保证。

用户新目标是五张**配套卡片**的0～360度平面旋转；该目标由卡片旋转模板bank和主任务完成，不能混称此guard已支持旋转积木。若扩大积木旋转和小尺寸范围，需要在新变体/阈值方案下同时回归卡片及未知图案，不能单独放宽阈值。真实纸卡、光照、上板、TD及同tag门控的整机结果仍由父任务另验。
