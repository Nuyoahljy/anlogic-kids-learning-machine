# 采集像素至十四类业务的集成候选

> 本页描述106的软件与接口历史；2026-10-13当前候选已为107，修复合法HS尾部并加入屏幕诊断，见 [0107排障与复测](pixel14-boardfix107.md)。下文“尚未上板”是106交付当时状态；其后的实物不可信反馈及107待复测状态以当前入口为准。

本阶段接续 `a698a53` 的结果级子系统，把真实采集域的四像素 RGB 输入接入两路识别、跨时钟结果传送、问答和 OSD。原四键 `826966ea` bit 和 DFR0534 实物验证继续独立等待；本候选的源码、仿真和构建均不能替代板上验收。

入口：[管线 RTL](../../fpga/rtl/sc520-card-recognition/pixel14/pixel14_pipeline.v)、[完整像素测试](../../fpga/sim/sc520-card-recognition/tb_pixel14_pipeline.sv)、[采集协议](pixel14-capture.md)。最终软件证据由 [audit-pixel14.py](../../fpga/scripts/sc520-card-recognition/audit-pixel14.py) 生成 [pixel14-validation-v2.json](../../evidence/sc520-card-recognition/pixel14-validation-v2.json)；只有实际存在且通过回读校验的结果才代表本次验证完成。

## 数据和时钟

`capture_clk` 域消费高位先行的四个 RGB888 像素。卡片分析全尺寸 ROI 的前景并抽取 32×32 模板；积木分析每 4×4 的中心像素，使用原分辨率独立前景计数判定缺席。二者只在关联的完整健康采集帧结束后出结果。默认 `ENABLE_OUTPUT=0`；实验启用必须明确设置为 1。

采集适配必须从真实 CSI SOF 建立帧号，并核对 RAW/ISP 与该帧关联的输入。ISP 行计数或 HDMI VSync 均不能独自建立采集健康资格。`in_frame_done` 必须为最终排空的空拍；done 后至少再留一个没有 start/done/valid 的空拍。紧邻 done 的新 SOF 会被管线明确撤销，避免 matcher 的排空阶段吞掉旧结果。

两路完成事件通常相隔数拍。管线分别暂存两路完整记录，合成一个原子包后在 mailbox ready 时发送；不会把合法的近邻完成事件当成两次 mailbox 写入。包携带两路各自的帧号、来源、健康、前景、类别、稳定计数，以及卡片距离诊断。显示域的 joiner 再核验同帧与帧号前进；两路均为稳定候选时执行已有的冲突拒识策略。

实际TD首次路由发现原五距离组合排序超出采集时钟预算，因此本候选使用独立 `pixel14_card_matcher`：捕获完整帧的距离快照后，每拍比较一个模板，再分拍计算间隔和发布结果。下一帧可在原规定的空拍之后继续采集；排序操作使用旧帧独立快照，标签、前景和距离不会被新帧覆盖。既有受保护的 `card_matcher.v` 保持原样。

暂存容量为一个待发双路结果，此外 mailbox 可保留一个传输中的包。相同结果槽未消费又被写入才视作真实溢出，永久撤销可信状态直到公共复位。普通坏帧撤销可等待传输空位，不需要通过永久溢出表达。停止的显示域最终会触发此容量边界，不能据此宣称支持无界缓存。

## 清除、超时和恢复

显示域持续时钟提供 `tick_1ms`，默认 100 次 tick 未得到健康配对时撤销识别、答题资格和排队音频。采集时钟停转时，这个时基仍须运行。旧画面继续从 DDR 输出不产生新的采集结果，也不能继续续期。

内部撤销经反向 mailbox 清采集端，并在握手往返及额外显示空拍期间隔离旧包。普通撤销不重置真实采集帧号；显式外部 `flush` 才开启新的业务身份周期。持续外部 flush 经两级同步持续清除采集端；解除后必须等待新的 SOF，不能从半帧恢复。外部短 flush 的上升沿独立排队，即使前一次隔离尚未结束，也不会因合并 clear 电平而丢失。

两路稳定计数均在清除后重新累计，默认需三个新的完整健康帧。健康未知、坏帧和真实空背景分开；坏帧或超时不能充当“用户拿走物体”而重新允许答题。

公共 `rst_n` 同时复位两个时钟域，各自同步释放。mailbox 数据是握手保持的多位数据，物理实现仍需正确 CDC 约束；RTL 仿真不能验证亚稳态。独立同步的外部 flush 电平仅用于持续保持，短脉冲依靠 mailbox 排队覆盖。

## 显示与声音范围

输入 `video_rgb` 必须是 DDR 的预 OSD 像素，`pixel_x/y`、DE 和同步属于相同显示拍。文字、ROI 边框、RGB、DE、VSync、HSync统一延迟一拍；空白区输出黑色。业务状态在显示帧开始锁存，保持整帧文字一致。

结果显示当前最新可信采集状态。旧 DDR 控制器没有提供与显示帧绑定的采集 tag，因此本候选不保证检测状态与屏上旧图逐帧精确对应，不将此作为精确延迟测量。卡片模板仍为固定摆位实验配置，真实相机颜色、光照、尺寸及识别效果需要实拍校准。

这里只生成十四类音频事件；真实 DFR0534 协议、排队与播放接入须结合待完成的实物验证。不得把诊断工程的音频事件当作已听到正确声音。

## 复现

在本工作树根，用已安装的 Python 执行：

```powershell
python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-pixel14.py --test capture
python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-pixel14.py --test block
python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-pixel14.py --test cdc
python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-pixel14.py --test pipeline --full-resolution
python -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-pixel14.py --test provenance
```

每项另执行 `--negative` 和 `--watchdog-probe`。正常必须原生退出 0、完成标记为 1 且无错；负向强制真实 DUT 输出错误，必须原生退出 1、检出一次错误；500ns 提前结束必须退出 2、完成标记为 0。三者的 runner 返回 0 只表示各自资格符合预期，负向不表示功能通过。

```powershell
python -B -X utf8 fpga/scripts/sc520-card-recognition/audit-pixel14.py
```

审计检查所有十五轮最终输入仍等于当前源码与快照，输出哈希完整，以及 1284 项受保护旧文件未变。最终pipeline使用1280×720完整几何；较早256×256联调结果保留为历史。provenance额外编译实际工程引用的厂商CSI/RAW解析器，覆盖真实协议串接；原厂源码只读。历史失败或旧源码运行保留原目录，不替换成新的成功结果。ModelSim 的完整命令、版本、输入和退出状态见各次 `run-manifest.json`。

2026-10-12 最终v2软件回读：十五轮资格通过，五类正常合计91个场景、1,916,686次检查、0错。负向与提前结束各五轮都按预期被拒绝。覆盖排序流水化后的最短间隔连续帧，以及provenance关闭边沿四种新错误；对应报告为 `pixel14-validation-v2.json`。较早的86场景 `pixel14-validation.json` 对应时序修复前源码，作为历史保留。TD构建结果和物理CDC评估另见 [构建说明](pixel14-build.md)，不计入本软件结论。

106 已生成独立诊断 bit，最终 SWNS +0.105 ns、HWNS +0.020 ns；原报告钩子失败历史保留，独立恢复审计已核对 ROM、IO、输入和逐位 CDC 传播。当前状态为候选等待主对话审核，尚未上板；只有本轮精确 bit 与布线符合该恢复资格，后续重建不能直接沿用。
