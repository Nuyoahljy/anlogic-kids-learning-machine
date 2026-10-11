# 十四类结果级整合候选

本阶段在 `task/sc520-card-recognition` 的独立 `items14` 模块中完成两路结果汇合、十四类问答、显示和音频事件连接。入口 [items14_system.v](../../fpga/rtl/sc520-card-recognition/items14/items14_system.v) 接收检测结果记录及OSD坐标，不接收相机RGB像素，不绑定IO、HDMI PHY或音频UART；当前没有新增bit。

旧四键826966ea、原始卡片识别器和帧保护模块保持原文件。项目主文档仍旧于分支记录；本页是待审核的本地接口和策略，未修改 `docs/03-interface-contracts.md`。

## 数据流与边界

```text
积木完成帧记录 ─┐
               ├─ items14_result_join ── items14_quiz_control ── 音频事件
卡片完成帧记录 ─┘          │                      │
                   撤销/清上游请求          帧首状态快照
                                                  │
                                       items14_osd / 同步字库
```

所有信号同属持续 `clk` 域。`tick_1ms` 必须是独立于视频有效信号的同域单周期脉冲。本批使用加速时基，不证明物理毫秒准确度。`TIMEOUT_MS=100`为候选配置，超时定义为最近健康配对结果后的第N个tick；若tick严格1ms，则墙钟等待与相位有关，约N−1至N ms。完整时钟停止时本计数器不能继续运行。

两路前缀分别为 `block_` 和 `card_`：

| 后缀 | 定义 |
|---|---|
| `event` | 完成帧记录单周期脉冲；只有此拍消费下面的payload |
| `healthy` | 该路完成帧通过真实像素协议检查 |
| `present` | 该路ROI有前景；未知物体也可以为1 |
| `valid` / `item[3:0]` | 该完成帧的稳定分类，积木合法1..9，卡片合法10..14 |
| `frame_id[31:0]` / `source_test` | 从采集/结算时锁定并随流水传递的帧号及来源；不能在结果到达时读当前帧号 |
| `count[7:0]` | 该帧稳定计数诊断，汇合器不重新计算确认 |
| `revoke` | 无完整帧事件的提前失效、切源或上游保护通知；不能仅把held valid拉低而不通知 |

每个健康帧包括空背景和未知图案都必须产生两路记录。一侧持续产生事件不能掩盖另一侧失活；直接关闭某检测器而不提供该帧记录将触发超时。

## 汇合、分类与撤销

每路只缓存一条待配对记录；允许积木先到、卡片先到或同拍到达，不依赖固定流水延迟。仅帧号和来源完全一致才配对，帧间不得混用旧hold值。已有本路待配对记录时再来本路event视为溢出，即使另一侧同拍也有记录，仍保守丢弃两槽并撤销。

| 配对情况 | 结果 |
|---|---|
| 两个合法稳定候选 | 健康但冲突：valid0、item0、conflict1、revoke1，清上游候选；没有默认卡片优先 |
| 只有一个合法稳定候选 | 选择该item，另一侧present不构成冲突 |
| 无稳定候选但任一侧有前景 | 健康未知：present1、valid0，不伪装物体移走，也不主动撤销正常三帧确认前已获得的armed |
| 无稳定候选且两侧都无前景 | 健康空背景：present0、valid0，才允许问答累计缺席样本 |
| 任一坏帧、非法valid编号、valid但present0、错帧/错来源、槽溢出 | 不可信撤销：healthy0、present1、valid0、item/count0，并清两槽 |

已接收过健康配对后，后续帧号必须模32位向前：差值1..2^31−1合法，支持FFFFFFFF到0；重复、倒序和半环差值拒绝。内部错误/超时保留最后帧号和来源，避免旧帧被当成新帧；只有外部 `flush` 开启新帧号时期，允许重新绑定来源。它只能检查输入标记，不保证标记真来自采集侧，也不能发现DDR持续重播旧图且另加新帧号的情况。

只有结构合法、同帧同来源、次序有效的健康配对续期；冲突代表视频仍活跃，也续期，但其分类被撤销。超时截止tick与健康配对同拍时配对优先。一直失活只产生一次超时撤销；恢复健康配对后重新计时。持续外部flush/revoke期间持续清除上游，整段只产生一次撤销事件。外部flush重置计时和帧号历史，单纯revoke不清历史。

`detectors_flush`为**同域同步清除请求**，必须接到两路检测器的同步清除端口；不能改作异步复位，不能复位持续帧号生成器。超时/故障下游撤销记录保留此前发布的帧号和来源，表示撤销旧结果，不是新采集帧。冲突记录使用本次完整配对的标记。

## 问答、显示与音频事件

[控制候选](items14-control.md)保留四键、每轮十题、满分10、答错重试和移走后重新武装。题库顺序为 `1,10,2,11,3,12,4,13,5,14,6,7,8,9`；K1再次进入问答时起点加10模14，单轮十项不重复，连续两轮覆盖14类。K4和复位恢复初始起点。

控制器显式接受 `sample_healthy` 和 `revoke`，不再把测试来源同时当作健康标志。撤销清显示/armed/缺席计数及待播事件，不直接改变分数、题目或模式；K4>K1>有效K3>撤销>其他。失效保留最后健康来源标签，不把TEST误改成CAMERA。

顶层将汇合器的注册撤销与当拍同步清除请求一起送给控制器，阻止上一拍排队的有效记录在新故障边沿被消费。恢复分类本身不会被当作物体已经移走，仍需三次明确的健康空背景才能重新答题。

[显示候选](items14-display.md)包含14类对象名称、152字形和44条文案。题目对象与当前识别分别显示；不可信状态遮蔽旧对象。顶层只在 `video_frame_start` 快照整组状态，帧中不撕裂；OSD active/RGB比输入坐标晚一拍，接入视频时须同步延迟RGB/VS/HS/DE。中心ROI不被上下文字面板遮挡。

`audio_event_valid/kind/item`已连到业务输出，并通过联合测试核对1..14对象和题目；`audio_idle/fault`由调用者提供。这里不包含播放器队列或DFR0534串口，显示仍标明音频模拟；实际曲号映射和播音不能由事件测试推断。

## 旧视频工程接入前必须处理

旧四键清单实际使用 `sc520-board-keys/user_source/hdl_source/quiz/hdmi_quiz.v`、`learning/detection_adapter.v`及本工程roi模块。它在显示vsync结算帧，再经过形状计算与adapter才有结果；卡片会在自己的EOF后结算，不能强求两个event同拍。适配器必须在相同真实完成帧上锁定并流水传递tag/source。

旧 `learning_presence` 包含仍被保持的box结果，而卡片present表示其ROI任意前景，二者语义不同。接入时还须审核当前帧valid与健康门控，保证其不是其他帧保留的稳定结果；不可机械把旧hold信号重命名成上述完成帧记录。

下一阶段在隔离视频工程接入：预OSD原像素、EOF及空拍、两路完成记录、持续时钟与采集侧健康、明确来源切换/撤销、OSD旁带延迟。之后执行TD 6.2.1资源/时序与ROM映射检查，产生诊断bit，再做卡片实拍校准。当前结果级验证没有替代这些工作。

## 复现本阶段软件验证

在本工作树根目录运行：

```powershell
$itemsPython = 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
foreach ($itemsTest in @('join','control','display','system')) {
    & $itemsPython -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-items14.py --test $itemsTest
    & $itemsPython -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-items14.py --test $itemsTest --negative
    & $itemsPython -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-items14.py --test $itemsTest --watchdog-probe
}
```

每次有独立输入快照、前后哈希、命令、日志、summary与原生退出码。normal要求exit0/done1/errors0；negative要求真实输出force被检出且exit1/errors1/injected1；500ns提前结束要求exit2/done0/errors0。三种runner都返回0表示分别满足预期，不混用为正常功能通过。

正常软件结果：join34场景/3083检查，control16场景/3106检查，display47场景/850417检查，system10场景/802检查，合计107场景/857408检查、0错误；四次真实输出注错和四次提前结束也均符合预期。初始control测试把存在的`INJECT_FAULT=0`参数误当true，导致一次正常资格失败；失败及同批旧注错目录保留，改为数值解析并补来源保持后重新运行最终三种模式。联合测试补充真正问答待答状态下“已排队正确答案+同拍故障和K2”的零计分检查，以及TEST来源超时后来源/告警在同一帧首更新的检查；早期8场景结果作为历史保留。

汇总与保护核对见[items14-validation-v2.json](../../evidence/sc520-card-recognition/items14-validation-v2.json)。最后将不可信显示断言从共用的“当前识别”前缀改为有区分力的对象字段后，system三种模式重新通过，统计数不变；早期汇总items14-validation.json保留为历史。运行 `audit-items14.py` 可不产生新文件地回读最终12轮输入/输出、902项旧文件、5项字体派生输出和7张预览哈希。

七张图和[总览](../../evidence/sc520-card-recognition/items14-preview-sheet.png)是软件预览。root目视检查文本完整、上下区域分离和中心ROI未被文字遮挡；小字形在实际屏幕上的清晰度待上板验证。
