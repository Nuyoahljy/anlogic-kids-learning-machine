# 采集域 RGB 四像素分析候选

`capture_rgb96` 在采集时钟域内分析 ISP 的四像素 RGB 组，输出卡片 32×32 采样和每 4×4 取中心的积木像素流。它不改 DDR，不把显示同步信号用作采集帧号。当前实现和测试属于独立 RTL 候选；是否通过以根任务实际运行的证据为准，本文不宣称已经连接板顶、真实相机或新 bit。

入口：[RTL](../../fpga/rtl/sc520-card-recognition/pixel14/capture_rgb96.v)、[测试](../../fpga/sim/sc520-card-recognition/tb_pixel14_capture.sv)。

## 输入责任

所有输入输出属于持续的 `clk` 采集域，复位低有效，`flush` 为同步取消。`flush` 清除本模块部分帧，不产生新的本地 `revoke`，也不生成帧号；持续的外部 `in_revoke` 电平仍向下游保持。

| 输入 | 必须满足的含义 |
|---|---|
| `in_frame_start` | 已经与真实采集帧关联的 ISP 帧开始，允许早于首个有效组，也支持与第一组同拍。不能是独立显示 VSync 或无采集依据的周期脉冲。 |
| `in_frame_id/source_test` | 该帧真实编号和来源；在 start 锁定，每个有效像素组核对相同值。模块不递增、不重置外部帧号。 |
| `in_valid/in_rgb96/in_eol` | 高到低依次为四个相邻 RGB888；每行精确 `FRAME_WIDTH/4` 组，EOL 与最后有效组同拍。允许组间及行间空拍，不自动补齐缺失组。 |
| `in_frame_done` | **上游确认该帧真实采集 EOF 已出现，且该帧 ISP 输出已经排空后**发出的最终关闭脉冲，必须位于 `in_valid=0、in_eol=0、in_frame_start=0` 的空拍。它不是 AWB tlast，也不能仅由最后预期像素生成。 |
| `in_frame_good` | 与 done 同拍、同帧的上游完整性资格。即使本模块像素数全部正确，good=0 仍不能发布健康帧。 |
| `in_done_id/source_test` | done 对应的身份，必须与 start 锁定值完全一致。 |
| `in_revoke` | 上游已发现错误或失效时立即撤销；可保持电平。不能由本模块 revoke 无条件回接成环。 |

真实 CSI EOF 通常早于 ISP 尾部排空，板顶适配器必须单独锁存这两类事件及其身份，再决定最终 done。少像素、ISP 停流、接收时钟停转不能无限等待“恰好达到预计像素数”；持续显示/控制时钟域的看门狗必须仍能撤销旧业务结果。这层关联、排空期限和跨时钟传送没有在本模块中实现。

## 两条输出

卡片输出 `card_frame_start`、`card_sample_valid/index/foreground` 直接适配现有串行 matcher 输入；完成输出为 `card_frame_end/good/present/id/source_test` 和 `roi_fg_count`。默认 ROI 为 `(400,120)` 起始的 480×480 方形，cell=15，中心为 `ROI+(cell/2)+n*cell`，保留原 32×32 模板几何。前景为任一通道小于 180，或最大最小通道差至少 40。`roi_fg_count` 统计原分辨率 ROI 内所有像素，不限于 1024 个采样点。

积木流的默认尺寸为 320×180，输出 `block_valid/sof/eol/x/y/rgb`：原图每个 4×4 区域选偏移 `(2,2)`，即输入组的 `[47:24]`；输出坐标为原坐标除以四。`block_frame_id/source_test` 从 start 到 EOF 保持，供下游从 SOF 开始锁定。`block_frame_end/good` 使用同一个外部 done 资格，不能靠最后一个缩小像素提交。

积木缺席判定另有全分辨率统计：`BLOCK_ROI_X/Y/WIDTH/HEIGHT` 默认为 `320/120/640/480`。`block_roi_fg_count` 统计该矩形全部原始像素，`block_frame_present` 只在健康完成时表示该计数是否非零，坏帧保持 present=1。下游必须用这个同帧 presence 决定是否允许累计缺席；下采样漏掉的细点仍然是前景，不能被当成物体已移走。白色物体与白色背景仍不能靠这个阈值区分，presence 不等于物理传感器的占用证明。

输出数据和标记由寄存器同时发布。正常完成前没有 `frame_end`；最后有效组之后至少需要一个输入空拍 done，使最后 sample 先于 matcher 消费结束事件。完成 strobes 为一拍，payload 只在对应 strobe 上消费。健康空背景和健康未知都必须交给后续分类/汇合，不得将 unknown 当 absence。

## 故障行为

- 每行长度、有效组数、空拍 EOL、帧中身份变化等错误首次出现时立即产生一次本地 revoke，后续该帧样本和缩小像素停止输出；若随后收到 done，两路都输出不健康完成记录。
- done 时核对完整行数、完整组数、1024 个采样及外部身份与资格；短帧立刻不健康，不能由像素计数替代真实 EOF。
- 未结束时又收到 start，保守终止旧帧并拒绝这个歧义新 start，等待后续新的完整开始；不会把旧像素重命名成新帧。
- 无 start 的数据被拒绝；连续孤立数据只产生一次本地 revoke。复位/flush 取消部分工作，不发布部分健康结果。

参数约束：帧宽高为四的倍数；卡片 ROI 至少128且为32的倍数，从而 cell≥4、每组至多一个采样，无需样本队列。小参数测试为256×256、ROI128；不支持ROI64。积木全分辨率矩形允许与卡片不同，必须位于帧内且计数不超20位。

## 旧工程来源审查

实际旧工程清单 `sc520-board-keys/td_project/camera_to_dsi_display.al` 选用 `isp/isp_top.v`、`isp/uial2axis.v`、根 `awb.v` 和 `quiz/hdmi_quiz.v`。AWB 96位出口在 `isp_top.v` 的 `awb_O_tdata/valid/last/user`，时钟为 `S_csi_rx_clk`；现有 `data_96bit_to_128bit` 高位先打包、`video_out` 高位先还原，因此本模块也按 `[95:72]→[71:48]→[47:24]→[23:0]` 排列像素。

AWB 的 `O_tuser=I_tuser` 刻意提前，为旧 DDR 输入 FIFO 复位预留时间；不能把它机械解释为首像素同拍。`O_tlast=(valid_d1==0)&&(valid_d2==1)` 对应该行最后有效组。上游 `signal_delay` 自行读出完整行，`uial2axis` 自行按计数生成行帧标记，因此只有下游 RGB 数量正确不足以证明真实采集完整。

可接入的原始观察包括顶层 `S_csi_frame_start/end`、长包声明长度、实际 HS 有效接收、`S_lane_error_any`、RAW 组数、每帧720长包及配置/I2C状态。现有最近帧诊断位必须与对应 tag 一起锁存，不能在结果到达时读取“当前最新”诊断。旧 CSI 解包接口没有提供 CRC/ECC 校验结果；该模块的 `frame_good` 只能表示调用者实际完成的检查，不能包装成所有物理误码都被检测。

旧 `video_in` 仅循环选择缓冲，顶层错误输入硬绑零；`video_out` 由显示 VSync 重新读取缓冲，没有完整写提交与身份绑定。因此本候选特意在采集域分析；OSD 展示的最新检测状态尚不能宣称与 DDR 当前显示图像精确逐帧对应。

## 验证覆盖与未验证范围

测试使用独立生成的全像素 RGB 和公开坐标公式，不读 DUT 内部计数器。覆盖256×256非四对齐ROI、阈值179/180与色差39/40、默认1280×720及cell15轮换四lane、1024中心样本、全部ROI前景、320×180或64×64像素、每行标记、early/start同拍、外部EOF缺失、上游坏帧与错身份、短帧、错误EOL、重叠start、持续revoke、静默flush、帧中复位及恢复。单像素 `(49,49)` 在积木ROI内、卡片ROI外且避开全部4×4中心；完整测试要求缩小图全白而积木present仍为1。

`+INJECT_FAULT=1` 强制一次真实 DUT `block_rgb` 输出，用同一数据检查器检出；根任务统一运行正常、负向和500ns提前结束并登记实际结果。本分工不自行执行生成测试结果的命令。TD综合、ROM映射、资源时序、实际CSI健康关联、CDC、相机颜色/像素顺序实测及硬件识别均待后续证据。
