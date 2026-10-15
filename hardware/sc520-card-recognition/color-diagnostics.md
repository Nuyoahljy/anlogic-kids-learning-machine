# C-002 三阶段同帧色彩诊断候选

本页对应 `fpga/rtl/sc520-card-recognition/color_diag/pixel14_color_diagnostics.v`，负责人为接续板级聊天 `01a13561-2629-7fa2-86a0-4087ad34cc7c` 的 `/root/color_diag_local` 子任务。基于 `task/sc520-card-recognition`、HEAD `f81483c` 开发，2026-10-14。该模块独立存在，尚未接入 ISP、识别、OSD 或 D0113 工程，未生成 bit，不能用于宣称 D0112 实拍问题已解决。分支日志由父任务统一维护。

它接收已经对齐的 WB 前、WB 后、tone 后 RGB96，并形成一个有帧号的完整快照。诊断不会修改 RGB、白平衡增益、tone 或识别阈值，也不产生真实 CSI 健康、曝光读回或识别结果。

## 输入与坐标

所有端口位于 `clk` 域；`rst_n` 为异步低有效复位，`flush` 为同步撤销。没有 ready/backpressure。

| 输入 | 精确定义 |
|---|---|
| `in_pre_wb / in_post_wb / in_post_tone[95:0]` | 同一帧、同一行、同一组四个像素的 RGB888。三路必须由适配器预先对齐，模块不含阶段延迟补偿。 |
| `in_valid` | 本拍四个像素全部有效，不支持部分 lane mask。 |
| `in_sof` | 一帧开始，可在第一个 valid 前的空拍，也可与第一个 valid 同拍。活动帧中再次 SOF 拒绝当前帧和冲突的新帧。 |
| `in_eol` | 仅与每行最后一个 valid 同拍为 1。 |
| `in_frame_id[31:0]` | SOF 锁存；每个 valid 的值必须相同。空拍允许改变，帧号不要求连续。 |
| `in_gain_r / in_gain_b[8:0]` | 本帧实际应用的 Q8 增益。首个 valid 锁存，以后每个 valid 均检查不变；不在提前的 SOF 上锁存。 |
| `in_frame_done / in_frame_good` | 外部认证该帧实际采集已经结束且对齐后的 ISP 输出已排空。done 必须空拍，不能以本模块最后一个像素自行冒充真实 EOF。good 仅在 done 时求值。 |
| `in_done_id[31:0]` | done 所认证的帧号，必须等于 SOF 帧号。 |
| `in_neutral_count[20:0]` | 与 done_id 绑定的该帧最终中性样本数，于合格 done 锁存。该关联是上游适配器的责任，不是本模块能从 RGB 自动证明的事实。 |

默认 `LANE0_MSB=1`：画面最左像素为 RGB96 `[95:72]`，其后为 `[71:48]`、`[47:24]`、`[23:0]`，每像素为 `{R,G,B}`。这与当前 `capture_rgb96.v` 一致。`LANE0_MSB=0` 反转这四个 24 位字的空间顺序，不交换 R/G/B。后续接线必须检查三路真正的 packing 与延迟，不能仅按信号名认为已经对齐。

坐标从 `(0,0)` 开始，只有 valid 推进横坐标；每组推进四像素，最后一组必须有 eol，行尾推进纵坐标。默认几何为：

| 区域 | 半开范围 | 每帧像素数 | 单点样本坐标 |
|---|---|---:|---|
| 判色统计区 | `[160,1120) × [120,600)` | 460800 | 不另采样 |
| 中心参考窗，ROI 0 | `[636,644) × [356,364)` | 64 | `(640,360)` |
| 白纸参考窗，ROI 1 | `[192,200) × [144,152)` | 64 | `(196,148)` |

白纸窗只是固定位置的参考窗，不包含“该位置一定有白纸”的自动判定。板级演示需在该位置放参考纸，并显示/记录窗口位置；它被目标、阴影或背景覆盖时，仍只是该处的采样值。中心窗也不随目标框移动。

## 输出布局与含义

`out_valid` 是新快照的单拍脉冲，必须和 `out_trusted=1` 一起采纳。`out_trusted` 在新 SOF、任何协议错误、flush 或 reset 后撤销。旧 payload 可以保持，但 `out_trusted=0` 时不得作为当前可信值显示；`out_frame_id` 仅在可信发布时更新。flush 不伪造新帧、不发出错误事件。所有字段一起发布，跨时钟域转移时必须作为同一组稳定 payload 处理，不能逐字段自由同步。

索引均从总线低位开始。stage 为 `0=WB前，1=WB后，2=tone后`；ROI 为 `0=中心，1=白纸参考`；channel 为 `0=R，1=G，2=B`；color 为 `0=红，1=黄，2=蓝`。

| 输出 | 位段规则 / 含义 |
|---|---|
| `out_frame_id`, `out_gain_r/b`, `out_neutral_count` | 当前快照的帧号、首有效组应用增益、done 时该帧最终中性数。 |
| `out_class_pixels[COUNT_BITS-1:0]` | 判色统计区的实际像素分母。 |
| `out_color_hits[9*COUNT_BITS-1:0]` | `[(stage*3+color)*COUNT_BITS +: COUNT_BITS]`；三阶段各自的原始阈值命中数。 |
| `out_roi_pixels[2*ROI_COUNT_BITS-1:0]` | `[roi*ROI_COUNT_BITS +: ROI_COUNT_BITS]`；三个阶段共用的窗口像素分母。 |
| `out_roi_rgb_sum[18*SUM_BITS-1:0]` | `[((roi*3+stage)*3+channel)*SUM_BITS +: SUM_BITS]`；窗口内通道和。后端可用 sum / out_roi_pixels 算均值；本模块无除法。 |
| `out_roi_lowclip/highclip[6*ROI_COUNT_BITS-1:0]` | `[(roi*3+stage)*ROI_COUNT_BITS +: ROI_COUNT_BITS]`；窗口中任一通道 `<= LOW_CLIP` / `>= HIGH_CLIP` 的像素数，同一像素每项最多计一次。默认门槛 8 / 247，含等号，低高可同时命中。 |
| `out_sample_rgb[143:0]` | `[(roi*3+stage)*24 +: 24]`，同一固定坐标的 RGB888。 |
| `out_sample_present[1:0]` | 每个 ROI 的固定单点是否实际被采到，合格发布必须为 `2'b11`。 |
| `out_sample_xy[47:0]` | 常量 `{paper_y[11:0], paper_x[11:0], center_y[11:0], center_x[11:0]}`，两个坐标为 `origin + floor(size/2)`。 |
| `out_reject`, `out_reject_reason[7:0]` | 拒收事件及原因位。原因在错误时锁存、下一个 SOF 清除；连续孤立数据可能连续产生事件，不能解释为独立坏帧个数。 |

原因位从低到高为：0=SOF/发布排空冲突；1=无帧有效数据；2=EOL 无 valid；3=栅格数量/行尾错误；4=有效数据或 done 的帧号不符；5=done 条件或外部 good 不合格；6=帧内应用增益变化；7=排空后内部采样覆盖不完整。可同时置多个原因位。

三色阈值精确沿用冻结 `block_frame_recognizer.v` 的布尔条件，计算时通道扩展为 9 位避免 `+32` 回绕：

```text
red:    R>=80, R-G>=32, R-B>=32
yellow: R>=96, G>=80, B<=96, |R-G|<=80, R-B>=32, G-B>=24
blue:   B>=80, B-R>=24, B-G>=24
```

这里分别计原始命中，红和黄可以同时命中；并非现识别器 `yellow > red > blue` 的优先级选择后 area，也不等于下采样后的积木面积、presence、scene 选择、shape 资格或稳定结果。统计为全分辨率判色区，不可直接与 320×180 分支的数值比较。`lowclip/highclip` 是定义的数值风险指标，不能单凭它们断言传感器饱和或曝光不足。

## 排空、拒收与资源边界

第一级寄存每组四个 lane 的命中数、窗口通道和、样本；第二级累加帧统计，RGB 比较不与帧级累加器处于同一个组合级。

```text
边沿 t0: 接收最后一组 valid+eol，注册最后一组贡献
边沿 t1: 接收 blank done+good+done_id，累加最后一组，锁存 neutral_count
边沿 t2: 必须无 valid/sof/eol/done；覆盖检查后 out_valid=1
边沿 t3: 可接下一帧 SOF（可同首 valid）
```

done 可以比 t1 更晚；额外空拍不增加计数。任何缺行、短行、长行、多像素、提前 SOF、valid 中帧号跳变、错误 done_id、坏 good、帧内增益变化都撤销信任。错误后丢弃数据，直到新的合格 SOF。flush 同样取消尚未发布的贡献与 pending；停流超时仍由上游产生 flush，本模块无时基看门狗。输入组全部对齐只是使用前提，本模块无法检测“三路各自自洽但彼此错一帧”的未标记接线错误。

参数要求每行宽度为 4 的倍数，宽 4..4096、高 1..4096，两个参考窗和判色区均非空且在帧内。两个参考窗可重叠，分别计数。计数器按包括最大值的位宽计算；默认 class 计数 20 位、窗口计数 7 位、和 15 位。HDL 中没有帧缓存、运行时乘除法或显式 DSP/BRAM；寄存器、LUT 数和实际时序仍待独立综合/整机布局布线，不以代码结构冒充物理资格。

## 验证与后续接入

独立测试为 `fpga/sim/sc520-card-recognition/tb_pixel14_color_diagnostics.sv`，runner 为 `fpga/scripts/sc520-card-recognition/simulate-color-diagnostics.py`。在本工作树根运行：

```powershell
python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-color-diagnostics.py
python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-color-diagnostics.py --negative
python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-color-diagnostics.py --probe
```

ModelSim SE-64 10.7 的每轮独立输出位于 `evidence/sc520-card-recognition/color-diagnostics/<mode>-<timestamp>-<suffix>/`，包含输入快照、源码 SHA256、真实命令、transcript、summary 和 result。正常运行要求完整 42 场景、零错误、done=1/native exit 0；注错在实际 DUT 输出帧号上 force，一项检查报错且 injected=1/native exit 1 才证明检查器检出；提前停止运行 500ns，done=0/native exit 2 才通过早停资格。runner 的 qualified 是该模式资格，不把注错轮写成 RTL 零错误通过。

测试覆盖两个 1280×720 完整帧、四个不同采样 lane、两种 lane 顺序、非 4 对齐窗口、重叠的最小 1 像素窗、末像素采样及排空、三阶段不同 RGB、独立阈值边界与 clip 等号、invalid 毒数据、跨帧 ID/增益、中性数、每种坏帧恢复、flush/pending冲突和复位。测试使用人工构造的已对齐三阶段数据；生产 WB/tone 数值的反例见父任务独立 color-contract 证据，本测试不代替那项联合验证。

下一步由父任务在新候选中建立 WB 前/后/tone 后同像素 tap，并给应用增益与最终中性数绑定正确帧号。当前 color 模块 raw SOF 比输出像素早，增益在 raw SOF 后更新，中性计数在下一 raw SOF 清零，直接连层级内部寄存器不足以证明身份。scene/glyph/paper/presence/raw block/shape distance/stability 由识别域另采，需通过同一帧号合成快照；本模块没有伪造这些字段。后续任何顶层、CDC、OSD、工程输入或 SDC 改动须独立冻结、回归和物理审核，不能混入在途 T-018 的 D0113 证据。
