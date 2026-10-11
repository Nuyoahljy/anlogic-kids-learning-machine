# 十四类中文显示候选

本目录候选把九类积木与五类卡片接到同一套中文显示表。`item_id=10..14` 依次显示苹果、香蕉、汽车、星星、雨伞；`0` 和 `15` 显示未知目标。问答仍为十题、满分十分。本候选尚未通过整机 TD 资源/时序或上板验证，七张预览都是软件按字模绘制的示意图。

## 文件与生成入口

- [items14_content.v](../../fpga/rtl/sc520-card-recognition/items14/items14_content.v)：十四类文案、题目/当前识别/答案显示选择和不可信提示。
- [items14_font_rom.v](../../fpga/rtl/sc520-card-recognition/items14/items14_font_rom.v)：本机宋体的 152 个字形；4096×16 位初始化 ROM，一拍同步读取。
- [items14_osd.v](../../fpga/rtl/sc520-card-recognition/items14/items14_osd.v)：双面板、像素对齐和文字配色。
- [generate-items14-font.py](../../fpga/scripts/sc520-card-recognition/generate-items14-font.py)：文案和字形生成器；修改文案应改此文件后再运行，不手改生成的两个 RTL 文件。
- [text-manifest.json](../../assets/templates/sc520-card-recognition/items14/text-manifest.json)：44 条中文原文、字形编号、对象映射和未知/不可信定义。
- [font-manifest.json](../../assets/templates/sc520-card-recognition/items14/font-manifest.json)：字体来源哈希、152 个字形的完整行位图、旧文件来源哈希、输出哈希、预览说明和坐标定义。
- [tb_items14_display.sv](../../fpga/sim/sc520-card-recognition/tb_items14_display.sv)：独立显示测试。

在当前工作树根目录运行：

```powershell
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 fpga/scripts/sc520-card-recognition/generate-items14-font.py
```

2026-10-11 本轮实际生成命令返回 0，输出 `glyphs=152 texts=44 previews=7 max_columns=20`。字体为 `C:/Windows/Fonts/simsun.ttc` 中第 0 个宋体字面，字号 16、阈值 128；字形逐个检查不为空且不超出 16×16 像素。字体文件 SHA256 为 `1526AC24375F51F6EB73BC2D3F8072DBE4A80A3A65217677C9D9A84F67DAB2AB`。只保存派生位图，没有复制系统字体文件；不据此推断字体的再分发许可。

生成器运行时不依赖另一工作树。旧四键 `generate-font.py`、`quiz_content.v`、`quiz_font_rom.v` 和 `quiz_osd.v` 只作为初始只读参考，绝对来源根及四项 SHA256 已写入 `font-manifest.json`。原四键代码和可用 bit 没有被本显示子任务修改。

## 候选接口与整机约束

`items14_content` 沿用原来的 `line_index[2:0]`、`char_index[5:0]`、`mode/phase[1:0]`、`score/question_index/target_item/display_item[3:0]`、`feedback[2:0]`、`source_test/armed/audio_fault/audio_busy`，新增 `result_healthy`，输出 `glyph[7:0]` 和 `tone[1:0]`。

`items14_osd` 沿用原 OSD 的 `clk/rst_n`、`pixel_x[10:0]`、`pixel_y[9:0]` 及以上状态输入，新增 `result_healthy`，输出 `active` 和 `rgb[23:0]`。这是任务内新模块接口提案，没有修改共享接口文档。父模块必须在帧起点一起锁存显示状态，且把摄像底图像素、DE、HS、VS 等旁带也延迟一拍；本 OSD 不提供跨时钟同步或帧锁存。

显示语义如下：

| 条件 | 显示行为 |
|---|---|
| 探索 | 提示“放入积木或卡片认识物体”；当前识别显示 `display_item` |
| 问答进行中 | “请找出”显示 `target_item`；当前识别独立显示 `display_item`，不把题目目标当成识别结果 |
| 两次答错、展示答案 | 使用“正确答案”标签显示 `target_item` |
| `result_healthy=0` | 提示“识别不可信：请移走物体，等待恢复”，当前识别区显示“不可信”，隐藏旧识别和答案展示；题目目标仍保留 |
| `source_test=1` | 保留“测试来源：内置画面，禁止正式计分”；健康时另提示测试画面不参与正式计分 |
| 十题完成 | 题号和分数上限保持 `/10`；完成文案显示“共10题” |

`result_healthy` 只控制显示提示，不会替代上游坏帧/超时撤销或控制器的禁止计分逻辑。`source_test` 仍只代表画面来源，不能为了显示错误而把摄像来源改写成测试来源。这里的音频行明确为“音频模拟”；真实 DFR0534 的接入与状态含义仍待整机阶段验证。

## 版面与预览

720p 有效区内，面板水平范围为 `32≤x<1248`，上面板为 `8≤y<112`，下面板为 `608≤y<712`。文字起点是 `x=48`，六行分别位于 `y=12/44/76/612/644/676`，16×16 字模放大两倍成为 32×32 字格。中心识别区 `320≤x<960、120≤y<600` 不进入任一面板。所有当前文案最长 20 字，视口可容纳 37 字。

预览下方额外 56 像素为软件示意说明，不属于 HDMI 有效区或 RTL 输出。中心框和占位说明也只在软件预览里出现。预览入口：

- [苹果](../../assets/templates/sc520-card-recognition/items14/preview-explore-10.png)
- [香蕉](../../assets/templates/sc520-card-recognition/items14/preview-explore-11.png)
- [汽车](../../assets/templates/sc520-card-recognition/items14/preview-explore-12.png)
- [星星](../../assets/templates/sc520-card-recognition/items14/preview-explore-13.png)
- [雨伞](../../assets/templates/sc520-card-recognition/items14/preview-explore-14.png)
- [问答：题目雨伞，当前苹果](../../assets/templates/sc520-card-recognition/items14/preview-quiz.png)
- [不可信：隐藏旧苹果结果](../../assets/templates/sc520-card-recognition/items14/preview-unhealthy.png)

## 测试与证据边界

显示测试从 `items14_text_reference.svh` 读取清单生成的文案期望，从 `items14_bitmap_reference.svh` 读取完整 256 位字形期望；不调用 DUT 的 `text_glyph` 或直接读取 DUT ROM。统一 runner 应把两份 SVH 和三个 RTL、TB 一起复制到输入快照，并以 `+incdir+<快照目录>` 编译。位图由同一字体派生，测试验证地址、缩放、流水对齐和显示选择，不把它当成独立字体设计正确性证明。

```powershell
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-items14.py --test display
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-items14.py --test display --negative
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-items14.py --test display --watchdog-probe
```

TB 逐项检查 1..14 的当前对象及题目目标、0/15 未知、尾部空白、题目与检测分离、坏帧提示优先级、测试来源、十题满分、反馈及音频状态；遍历所有 4096 个 ROM 地址，并逐像素核对名字、题目、告警、题号/分数和面板边界。另检查中心 ROI、异步复位、复位后的旁带与 ROM 一拍延迟。`INJECT_FAULT` 通过 `$value$plusargs("INJECT_FAULT=%d",...)` 读取，负向模式强制一次真实 DUT 字形输出，并要求只检出一个故障；20 ms 仿真看门狗防止测试无结束。

上述 ModelSim 命令由本轮 root 统一执行与登记。生成完成本身不代表测试通过，实际退出码、checks/scenarios、当前源快照和哈希以各独立 `i14-display-*` 运行目录的 `run-manifest.json`、`summary.json` 和本轮分支日志为准。完整摄像链路、诊断 bit、字体 ROM 的 TD 映射、时序和实物屏幕清晰度仍待验证。
