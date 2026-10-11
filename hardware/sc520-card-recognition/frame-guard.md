# 完整帧超时保护候选

本模块解决一个明确问题：视频没有再产生完整健康帧时，旧稳定卡片结果不能无限保留。源码为 [card_frame_guard.v](../../fpga/rtl/sc520-card-recognition/card_frame_guard.v)。它是独立候选，尚未接入摄像头工程或四键 bit；实际测试结论见文末证据入口。

## 接入方式

在同一持续运行的 `clk` 域，把 `card_recognizer` 的结果输出接到 guard 的同名 `in_*` 输入，其中 `stable_count` 对应 `in_stable_count`。guard 的 `recognizer_flush` 接回识别器 `flush`；外部切源、重配请求接 guard 的 `flush`，不能只清下游而保留上游候选。显示与仲裁使用 guard 的结果。

`tick_1ms` 必须由这个持续运行的时钟产生，是单周期脉冲，不得取自 VS、DE、像素有效或帧完成。该模块不包含跨时钟同步。若整个 `clk` 停止，本模块也不能执行超时；另一持续系统时钟域的监测与跨域撤销仍属于后续整机工作。

`TIMEOUT_MS` 默认为100，合法值为正整数。实际实现是“自复位、外部 flush 或最近健康完整帧起的第 N 个 tick 超时”。若 tick 周期严格为1ms，其相位使墙钟间隔处于约 N−1 至 N ms；本批仿真用加速、稀疏 tick，验证计数与边界，没有测量板上毫秒精度。默认100是候选配置，待结合实际帧周期及摄像头重配时间审核。

## 结果与优先级

| 情况 | 行为 |
|---|---|
| `in_frame && in_healthy` | 重启计时；健康空背景和未知图案也证明视频活跃，不要求识别成功 |
| 只有像素、VS，或连续坏帧 | 不重启计时；只有上游认定完整健康的结果事件可以续期 |
| 第N个tick恰好收到健康帧 | 健康帧优先，不触发超时 |
| 超时 | 同边沿向上游发清除请求，向下游发一次不可信撤销，`timed_out=1` |
| 一直没有恢复 | 保持无效结果，不重复发送超时清除，允许上游收集恢复帧 |
| 外部 `flush` | 优先于同拍结果；清超时标志并重启计时；持续高时保持清除，整段只发一次撤销 |
| 恢复健康帧 | 解除 `timed_out`；上游被清除过，仍需重新确认三帧才可稳定 |
| 无帧事件但上游提前撤销有效结果 | 下一采样边沿清 guard 的 valid/item/count；不虚构空背景或完整帧 |

撤销记录为 `out_frame=1, out_healthy=0, out_present=1, out_valid=0, out_item=0, out_stable_count=0`。帧号和来源保持上一条记录，表示撤销，不能把它当成新采集帧或推进采集帧计数。复位不产生记录，`out_present=1`只表示尚未确认空背景。

坏帧同样强制 present=1、valid=0、item/count=0；健康且 valid=1 的非法卡片编号（不在10..14）会撤销分类。健康未稳定的 count1/2 在帧间保留，直到上游实际清零。guard 不自行补算连续确认，不验证递增/重复帧号，也不校验模板准确率。

若摄像头停止更新，但DDR或显示侧仍重复输出完整旧帧，guard仍可能收到健康结果，因此不能识别这种画面不新鲜的情况。必须在后续接入采集侧帧完成与可信帧号，再单独验证；图像内容是否变化也不能直接当作摄像头活跃指标，因为静止物体本来可以不变化。

## 接入问答时的约束

`out_healthy=0` 必须被下游视为“不可信撤销”，同时清显示和答题武装状态，不能转换成真实空背景。当前四键 `quiz_control` 的 `present=1/stable=0` 并不足以清掉已经置位的 `armed`。现有坏帧路径通过 `source_test=1` 的不可信样本撤销武装；未来适配器可沿用这一语义，或先提出显式 revoke 接口供主对话审核。

无事件提前失效只反映在 valid/item/count 上；只在 `out_frame` 时锁存结果的消费者，还须监控有效结果下降并产生不可信撤销。不能仅连接 guard 的超时清除线就声称问答停流问题已经整机解决。

本轮不改 `detection_adapter`、`quiz_control` 或共享接口；九类积木与五类卡片的同帧仲裁、十四类字库/题序/音频和以上桥接仍待后续实现。

## 仿真复现

在本工作树根目录，使用本机 Python 和 ModelSim SE-64 10.7：

```powershell
$guardPython = 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $guardPython -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-guard.py
& $guardPython -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-guard.py --negative
& $guardPython -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-guard.py --watchdog-probe
```

每次运行保存独立目录及源快照、SHA256、命令、原生退出码与summary。正常要求done1/errors0；注错要求真实输出故障被检出，原生exit1/errors1/injected1；500ns提前结束要求exit2/done0/errors0。runner返回0只表示该运行符合自己的验收条件。

2026-10-11实际运行三条命令均符合验收条件：正常16场景/2432检查/0错误；注错原生exit1、errors1、injected1；500ns提前结束原生exit2、done0、errors0。真实三帧滤波器在超时同边沿清零，恢复第1/2帧不稳定、第3帧稳定；TIMEOUT_MS=1/5均覆盖。编译及仿真日志没有工具错误。

汇总见[guard-validation.json](../../evidence/sc520-card-recognition/guard-validation.json)。root回读三次运行的源、快照、输出哈希及15项受保护旧文件，全部一致。原始616场景属于2026-10-10的旧识别器验证，不计入本模块的新测试数；未做完整像素流回归或TD综合/时序/上板验证。
