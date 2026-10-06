# 学习内容与底部 OSD 验证记录

负责人：子代理 learning_osd，任务 sc520-learning-ui-audio。时间：2026-10-04（Asia/Shanghai）。状态：模块软件验证完成，等待集成及主对话审核；未上板。

## 实现与接口

新增 `learning_content.v`、`learning_font_rom.v`、`learning_osd.v`。未修改旧 OSD、旧候选、共享契约、主对话文档、工程或 wrapper。

`learning_osd` 的输入为 `pixel_x[10:0]`、`pixel_y[9:0]`、`item_id[3:0]`、`det_valid`、`demo_mode`、`audio_status[1:0]`；输出为 `active` 和 `rgb[23:0]`。全部组合逻辑，不增加视频周期延迟。有效面板仅为 x=32..1247、y=608..711；字高32像素，三行分别从y=612、644、676开始。父 wrapper 继续负责视频时序、顶部检测和输入来源显示。

学习内容逐字遵守 `docs/01-product-spec.md` 中1..9对应中文、无声调拼音、英文；不更改共享编号。只有 `det_valid=1 && 1<=item_id<=9` 显示学习内容，否则显示“无目标”和两行“--”。10..14在共享契约中是卡片，属于本轮未实现输入，局部显示适配降级为空，不是重新定义这些编号。

右侧始终显示“语音模拟”，状态0/1/2/3分别为“空闲／等待／播放／故障”；第二行“测试输入”或“摄像输入”明显区分来源，第三行固定“仅软件验证”。`audio_status` 是局部抽象播放器状态，不代表真实DFPlayer行为。学习内容使用近白字，避免用难辨认的深蓝原色作为蓝色对象名称。

字体为本机 SimSun 14像素的63个单色位图字符子集，中文16x16、ASCII占前8列，以2倍放大显示。生成器校验没有字体回退、ASCII没有溢出8像素单元。原字体文件未复制，也不声明字体开源；对外发布字体资产前仍需确认适用授权。

## 实际命令和结果

工作目录均为：

```text
E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-fixed-roi
```

使用 ModelSim SE-64 10.7，未调用更高版本TD。

```powershell
pwsh -File fpga/scripts/sc520-learning-ui-audio/generate-learning-font.ps1
pwsh -File fpga/scripts/sc520-learning-ui-audio/osd-simulate.ps1
pwsh -File fpga/scripts/sc520-learning-ui-audio/osd-simulate.ps1 -Negative
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' fpga/scripts/sc520-learning-ui-audio/render-osd.py evidence/sc520-learning-ui-audio/osd-runs/osd-0-20261004-115526-32396
```

| 运行 | 实际结果 | 证据 |
|---|---|---|
| 字模生成 | FONT_GENERATED glyphs=63 | [字模数据](font/glyphs.json)、[字模图](font/atlas.png) |
| 正常仿真，11:55:26启动 | 33场景，8192内容查询，5406984像素检查；done=1，errors=0；编译及仿真0 errors/0 warnings，进程退出0 | [summary](osd-runs/osd-0-20261004-115526-32396/summary.json)、[完整日志](osd-runs/osd-0-20261004-115526-32396/transcript.log)、[源哈希与命令](osd-runs/osd-0-20261004-115526-32396/run-manifest.json) |
| 故障注入，11:55:56启动 | 强制DUT RGB为ffffff，5406984像素检查均报错；内容8192查询仍完成；done=1，errors=5406984，进程退出1，达到预期 | [summary](osd-runs/osd-1-20261004-115556-32272/summary.json)、[完整日志](osd-runs/osd-1-20261004-115556-32272/transcript.log)、[源哈希与命令](osd-runs/osd-1-20261004-115556-32272/run-manifest.json) |
| 图像导出 | 正常RTL输出的12张1280x128 PPM转PNG，生成一张联系表；PPM/PNG逐份有SHA256 | [图像清单](osd-runs/osd-0-20261004-115526-32396/render-manifest.json)、[联系表](osd-runs/osd-0-20261004-115526-32396/contact-sheet.png) |

内容检查覆盖16种编号、两种有效位、4个行索引和64个字符位置，包含字符串尾部补零。像素检查覆盖九种目标分别处于测试和摄像模式、无目标0、本轮未实现10..14、保留15、有效位清除和所有音频状态。每场景逐像素检查整个y=592..719底部条带，并检查ROI、面板邻接边界、720p之外的可表示坐标。

预期像素使用 `learning_osd_reference.svh` 中独立函数 `learning_reference_rgb(x,y,item,valid,demo,status)`，返回区外0；可供父级全帧回归引用。内容参考按颜色和形状分解、Unicode标签与字符串生成，不读取DUT内部信号或DUT内容表。字形参考使用独立256位完整字图表示，DUT使用逐行ROM；二者的字形来源均是本机实际渲染，文字方向和可读性另做视觉核对。

实际查看了最长拼音“huang se san jiao xing”的[第5场景](osd-runs/osd-0-20261004-115526-32396/panel-5.png)、12场景联系表和63字模图。九项中文、拼音、英文对应，文字未裁切；空场景没有残留目标名，状态与来源标签完整。图片仅为RTL仿真像素，不能当作摄像头或硬件证据。

PowerShell两脚本Parser检查通过，Python绘图脚本AST解析通过。系统默认Python缺少Pillow，改用应用提供的Python运行时后正常输出；未安装包、未留下该探测的输出文件。首次HDL编译和功能仿真即通过，无需修改RTL；故障注入是检查器验证，不是发现并修复了产品故障。WLF已生成，未离线重开，不单独宣称波形归档通过。

## 源码哈希

以下为正常和故障仿真时的源码，两个run-manifest保存了仿真输入的前后哈希一致检查。集成若修改任一源，必须重新运行对应回归。

| 文件 | SHA256 |
|---|---|
| `fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source/learning/learning_content.v` | `B219F032C6A1894CD90F1294F3E6BF5D77A793C71FA4FC0317496B4539EA2082` |
| `fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source/learning/learning_font_rom.v` | `DD5FBC6FCB1AFFF248E99EA0A3AB49BB8C21B3352F1BC8F3047B68A5D1D1E51F` |
| `fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source/learning/learning_osd.v` | `9759F2BB4CF8D8294B324C6C1A49099133D8C3979522A00FCE1C70261F7403D3` |
| `fpga/scripts/sc520-learning-ui-audio/generate-learning-font.ps1` | `3E4928C43258DD56A00EAA28FDAD5E3E22A30345B4644F068727A8883B13231A` |
| `fpga/scripts/sc520-learning-ui-audio/osd-simulate.ps1` | `D4795A6C70517FC556376B3265AA2BC7BF9C7015D04FD20998EA60D2341E47E0` |
| `fpga/scripts/sc520-learning-ui-audio/osd-test.do` | `8C5BAB22B2DAB553508E3E71900A2F3B2ADEB0F2F6878725AD623DBEE32C563F` |
| `fpga/scripts/sc520-learning-ui-audio/render-osd.py` | `F8BBF714372F615AF42FA31FC926F0420AF4C3F0F42C590E8BAFBAA6B356DE42` |
| `fpga/sim/sc520-learning-ui-audio/tb_learning_osd.sv` | `41121DBA9D99B3197058E58FD1D08CB3F6306D220FEC1C82F1AE3AE2BDB2BD3B` |
| `fpga/sim/sc520-learning-ui-audio/learning_font_reference.svh` | `5626BC7CD79E4CA1A46707379BBAAA11053BAE5822AF21F747985140D88730BB` |
| `fpga/sim/sc520-learning-ui-audio/learning_osd_reference.svh` | `FA404980C9485ADDCEA52F32703D7EA61992D670AB14C152542A1B592EA1E188` |

## 保全与剩余边界

本轮只读复核两份原候选哈希，仍为：

- shape：`F5F88FD03A99FBD10C23FFCFF4AEC2E7B24991F492F323BEE52E6B10C4E1A254`。
- OSD：`9D3B1CBDB271CF9C3198F4FC9DE49580B54BE2E918B4233829A6625D2D20945B`。

本模块软件验证不包含帧域稳定事件、音频队列与超时、父wrapper、FPGA布局布线时序、摄像头实物识别或真实DFPlayer联调。父任务负责独立工程集成、完整视频回归及TD6.2.1构建。未新增物理IO、UART、电气假设或接线，不进行下载和Flash操作。

本子代理报告作为任务日志的专项证据交给父对话汇入 `memory/branches/sc520-learning-ui-audio.md`，不并发覆盖父日志。共享根登记只认领本专项文件和生成目录；登记不代表共享接口已批准或Git已合并。
