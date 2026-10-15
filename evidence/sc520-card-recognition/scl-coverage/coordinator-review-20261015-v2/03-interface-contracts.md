# 接口契约

> 本文件由主对话冻结和维护。分支不得直接修改；如需变化，必须提交提案。

2026-10-14现状说明：下文DFPlayer协议和旧识别坐标为历史设计，不能直接用于当前D0112或DFR0534接线。D0112音频仍为常量空闲旁路，DFR0534仅独立驱动及参数阶段实测，完整接口/针位/正式映射尚未冻结。当前候选范围及验收以[主审核](../../learning/sc520-contest-roadmap/main-takeover-review-20261014.md)和[协调表](10-active-coordination.md)为准；本注不将候选自动提升为稳定公共接口。

## 1. 对象编号

| `item_id` | 对象 |
|---:|---|
| 0 | 无目标 |
| 1 | 红色圆形 |
| 2 | 红色方形 |
| 3 | 红色三角形 |
| 4 | 黄色圆形 |
| 5 | 黄色方形 |
| 6 | 黄色三角形 |
| 7 | 蓝色圆形 |
| 8 | 蓝色方形 |
| 9 | 蓝色三角形 |
| 10 | 苹果 |
| 11 | 香蕉 |
| 12 | 汽车 |
| 13 | 星星 |
| 14 | 雨伞 |

保留 `15` 给调试或未来对象，不参与当前计分。

## 2. 检测结果

逻辑接口：

```verilog
wire        det_valid;
wire [31:0] frame_id;
wire [3:0]  item_id;
wire [1:0]  color_id;
wire [1:0]  shape_id;
wire [9:0]  bbox_x;
wire [9:0]  bbox_y;
wire [9:0]  bbox_w;
wire [9:0]  bbox_h;
wire [7:0]  stable_count;
```

定义：

| 信号 | 定义 |
|---|---|
| `det_valid` | 当前存在稳定且可信的检测结果 |
| `frame_id` | 采集帧计数，从每个完整帧开始递增 |
| `item_id` | 0 至 14，见对象编号 |
| `color_id` | 0=无颜色，1=红，2=黄，3=蓝 |
| `shape_id` | 0=未知，1=圆，2=方，3=三角 |
| `bbox_x/y` | 在 320x180 内部识别坐标中的左上角 |
| `bbox_w/h` | 在 320x180 内部识别坐标中的尺寸 |
| `stable_count` | 当前候选连续一致的帧数，饱和到 255 |

约束：

- `det_valid=1` 时，`item_id` 必须非 0，包围盒必须位于识别区内。
- 卡片结果的 `color_id` 和 `shape_id` 可以保留其主特征，但下游不得依赖它们判断卡片。
- OSD 负责把内部坐标缩放到 HDMI 的 1280x720。

## 3. 模式与计分

```verilog
wire [1:0] mode;
wire [3:0] score;
wire       quiz_active;
wire [3:0] quiz_target_item_id;
wire       quiz_answer_valid;
wire       quiz_answer_correct;
```

| `mode` | 含义 |
|---:|---|
| 0 | 待机 |
| 1 | 探索 |
| 2 | 问答 |
| 3 | 调试或保留 |

规则：

- `score` 范围为 0 至 10。
- 每次从“无目标”变为“稳定目标”只允许产生一次答案事件。
- 目标持续存在时不重复判题。
- `quiz_answer_valid` 为单周期脉冲。

## 4. 按键

顶层物理 IO 可以是低有效，但内部统一为高有效单周期脉冲：

```verilog
wire key_mode_pulse;
wire key_replay_pulse;
wire key_skip_pulse;
wire key_reset_pulse;
```

- 消抖时间：20 ms。
- 按下后只产生一个脉冲。
- 长按功能不属于当前版本。

## 5. 音频事件与 DFPlayer

```verilog
wire [2:0] audio_event;
wire [3:0] audio_item_id;
```

| `audio_event` | 含义 |
|---:|---|
| 0 | 无事件 |
| 1 | 播放对象名称 |
| 2 | 播放问答题目 |
| 3 | 回答正确 |
| 4 | 回答错误 |
| 5 | 重播当前内容 |
| 6 | 重置语音 |
| 7 | 调试或保留 |

事件为单周期脉冲，`audio_uart` 负责排队和发送。

DFPlayer 参数：

- UART：9600 baud，8N1。
- 命令帧：10 字节 `7E FF 06 CMD 00 P1 P2 CHECKSUM EF`。
- 校验：从版本字节到 P2 的累加和取反加一。
- 选曲命令：`0x03`。

音频文件编号：

| 文件编号 | 内容 |
|---:|---|
| 0001 至 0014 | 对应 `item_id` 的名称和说明 |
| 0101 至 0114 | 对应 `item_id` 的问答题目 |
| 0201 | 回答正确 |
| 0202 | 回答错误 |
| 0203 | 重播提示 |
| 0204 | 进入探索模式 |
| 0205 | 进入问答模式 |
| 0206 | 分数重置 |
| 0207 | 完成 10 题 |

## 6. OSD 输入

```verilog
wire [1:0]  osd_mode;
wire [3:0]  osd_item_id;
wire [3:0]  osd_score;
wire [31:0] osd_frame_id;
wire [15:0] osd_latency_frames;
wire        osd_det_valid;
wire [9:0]  osd_bbox_x;
wire [9:0]  osd_bbox_y;
wire [9:0]  osd_bbox_w;
wire [9:0]  osd_bbox_h;
wire        osd_feedback_valid;
wire        osd_feedback_correct;
```

OSD 优先级从高到低：

1. 问答正误反馈。
2. 对象名称、拼音和英文。
3. 检测框。
4. 模式、帧号、延迟和分数。
5. 安路 Logo。

## 7. 分支日志接口

每个分支日志必须至少包含以下一级字段：

```markdown
- 任务 ID：
- 状态：
- 负责人：
- 分支：
- 基础提交：
- 开始时间：
- 结束时间：
- 目标与验收条件：
- 已读文档：
- 修改文件：
- 验证命令与结果：
- 证据路径：
- 阻塞与风险：
- 待决策事项：
- 建议总文档更新：
- 下一分支交接：
```

状态只能是：`待启动`、`进行中`、`等待主对话审核`、`已合并`、`阻塞`、`取消`。

