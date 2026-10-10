# 五类卡片识别：独立模块接口与集成条件

本任务的软件入口为 `card_recognizer`，处理原始、尚未叠加 OSD 的 RGB888 坐标流，输出苹果10、香蕉11、汽车12、星星13、雨伞14。当前是独立软件实验，未接入四键整机工程、未综合、未生成新的 bit，也没有相机实拍验收。

2026-10-10软件验证已完成：matcher35、filter296、pipeline285，共616个正常场景、16395759次检查、零错误。两次输出注错和一次提前结束检查均被检出。69个RGB样本通过完整像素链路，另覆盖12类坏帧、空EOF、帧间最短支持间隔及中途source/tag异常两拍内撤销。状态为等待主对话审核。

源码位于 [card_recognizer.v](../../fpga/rtl/sc520-card-recognition/card_recognizer.v)，验证汇总见 [validation.json](../../evidence/sc520-card-recognition/validation.json)，素材和模型限制见 [模板说明](../../assets/templates/sc520-card-recognition/README.md)。

## 输入约定

所有输入同属 `clk` 域；上层负责跨时钟处理。`rst_n` 低有效异步复位，`flush` 同步清除所有未完成帧和稳定结果。

| 输入 | 使用约定 |
|---|---|
| `in_valid`、`in_rgb[23:0]` | 有效 RGB888 像素，每时钟最多一个；允许没有行帧标记的无效空拍 |
| `in_x[10:0]`、`in_y[9:0]` | 从(0,0)按行递增，完整覆盖参数指定画面；不接受只传 ROI |
| `in_sof` | 仅在该帧第一个有效像素为1 |
| `in_eol` | 仅在每行最后一个有效像素为1 |
| `in_frame_end` | 单独一拍，必须在完整画面之后的无效周期，且该拍SOF/EOL为0；仅收到最后像素不算完成 |
| 帧间隔 | EOF后至少再保留一个无效空拍，再送下一帧SOF；不支持EOF下一拍立即送新帧 |
| `in_frame_id`、`in_source_test` | 从首像素到EOF保持不变；ID只透传，不检查帧号递增或重复 |

默认画面1280×720，ROI为左上角(400,120)、480×480正方形，32×32格子中心采样。第(gx,gy)个点为`(ROI_X+CELL/2+gx*CELL, ROI_Y+CELL/2+gy*CELL)`，其中`CELL=ROI_SIZE/32`。ROI_SIZE须64..992且为32倍数，ROI须在画面内。运行时通过递增坐标采样，不使用逐像素除法。

RTL 仿真使用320×180、ROI(96,26)、128×128，以加快测试。默认720p参数没有在本批完整像素回归中运行，不能把小尺寸回归当作720p时序收敛证明。

## 匹配与输出

前景条件：`min(R,G,B)<180 || max(R,G,B)-min(R,G,B)>=40`。每个模板1024位，5路逐位计算Hamming距离。五个模板共5120位，即640字节逻辑数据；实际ERAM/LUT资源须以后综合确认。

本阶段实验配置为最佳距离≤40、次佳距离与最佳距离之差≥24、采样前景数16..850。没有平移搜索、尺度归一化、透视校正或光照自适应。标准图与模板同源；29/69接受是开发样本结果，不是独立测试准确率。阈值40改善了本组负样本拒识，但一格平移仅4/20接受，暗光5/5拒识。

`ENABLE_OUTPUT`默认0，关闭分类有效输出；独立仿真显式设为1。正式集成不能依赖默认值启用。`TEMPLATE_FILE`默认`templates.mem`；运行目录须提供对应文件。当前模板为[prep-v1-max40/templates.mem](../../assets/templates/sc520-card-recognition/prep-v1-max40/templates.mem)。TD加载路径与ROM推断须另行验证。

同来源、同类别连续3个健康帧才有稳定输出。类别变化从1重计；未知、坏帧、flush撤销稳定结果；计数饱和于255。采样器检测出像素协议错误后，通过fault_event清除滤波器，不必等到EOF。

| 输出 | 含义 |
|---|---|
| `out_frame` | 结果更新事件；只在此拍将ID、来源和诊断值作为一条完整记录消费 |
| `out_healthy` | 完整帧通过像素数量、顺序、SOF/EOL、来源、ID和采样数检查 |
| `out_present` | 健康帧ROI内检测到任何前景像素为1；坏帧输出1，避免误称空背景 |
| `out_valid`、`out_item` | 稳定且允许输出时为1及10..14；其余item为0 |
| `out_frame_id`、`out_source_test` | 对应帧首记录的标记；无首像素的孤立EOF使用EOF当次标记 |
| `stable_count` | 当前同来源同类别连续接受次数 |
| `best_distance`、`second_distance` | 最近完成帧的最佳、次佳距离，11位可表示0..1024 |
| `sample_fg_count`、`roi_fg_count` | 1024采样点前景数、整个ROI前景像素数；后者用于存在判断 |

全白画面输出healthy1/present0/valid0；有前景但不能分类输出healthy1/present1/valid0；坏帧在结果事件输出healthy0/present1/valid0。复位/flush期间的输出不是一条观测记录。白卡和白背景的物理存在无法由当前前景判定区分，因此界面宜写“未检测到前景”，不要写“没有卡片”。

若输入彻底停止且没有EOF、fault或flush，旧稳定结果会保持；本模块不包含失活看门狗。上层必须监控帧超时、切源、摄像头重配置，并通过flush撤销旧结果。重复frame_id也不会被拒绝，不能把重复帧标记计作独立观测保证。

## 复现验证

从本工作树根目录运行，Python为本机已有运行时：

```powershell
$cardPython = 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $cardPython -B -X utf8 fpga/scripts/sc520-card-recognition/simulate.py --test matcher
& $cardPython -B -X utf8 fpga/scripts/sc520-card-recognition/simulate.py --test filter
& $cardPython -B -X utf8 fpga/scripts/sc520-card-recognition/simulate.py --test pipeline
& $cardPython -B -X utf8 fpga/scripts/sc520-card-recognition/simulate.py --test matcher --negative
& $cardPython -B -X utf8 fpga/scripts/sc520-card-recognition/simulate.py --test pipeline --negative
& $cardPython -B -X utf8 fpga/scripts/sc520-card-recognition/simulate.py --test matcher --watchdog-probe
```

默认使用ModelSim SE-64 10.7和max40数据。每次运行保存独立目录、输入快照、完整命令和前后SHA256。正常用例要求原生退出0、done1、errors0；注错要求原生退出1、done1、errors1、injected1；提前500ns结束的检查要求原生退出2且done0/errors0。runner返回0表示对应资格条件成立，负向测试不代表错误RTL通过。历史失败目录保留在证据中。

Matcher测试显式使用距离阈值120，专门检查120/121、分差24/23等边界；pipeline使用模块缺省40，独立从RGB算预期结果。两者用途不同。

## 整机接入前必须完成

1. 固定卡片图案区域、摆位和光照，用SC520原始图像建立实拍与独立验收集，校准ROI和拒识阈值。
2. 增加卡片结果与九类积木结果的同帧仲裁；双候选冲突拒识或显式选择识别子模式，不能暗定卡片优先。
3. 审核并扩展当前仅支持1..9的detection_adapter、quiz_control、quiz_content，以及卡片中文字库、题序和音频映射。
4. 接入帧结束、足够空拍、来源标记及超时flush；验证预OSD取样位置与现有坐标流一致。
5. 在隔离工程做TD 6.2.1综合、资源和时序检查，通过后再生成新bit并上板。上述事项尚未完成。

这些为主对话更新接口与项目状态的建议，本分支没有改写主项目技术契约。
