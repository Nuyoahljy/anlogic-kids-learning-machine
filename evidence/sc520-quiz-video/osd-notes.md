# SC520 问答 OSD 局部接口与验证

日期：2026-10-06（Asia/Shanghai）；负责人：本任务协作子代理 `/root/preview_keys`。状态：独立实现已落盘，实际仿真、构建及父视频集成结论以本任务统一运行报告为准。旧问答控制和学习候选只读。

## 接口与布局

`quiz_osd` 完全组合，无额外像素时延。输入 `pixel_x[10:0]`、`pixel_y[9:0]`、`mode[1:0]`、`phase[1:0]`、`score[3:0]`、`question_index[3:0]`、`target_item[3:0]`、`display_item[3:0]`、`feedback[2:0]`、`source_test`、`armed`、`audio_fault`、`audio_busy`；输出 `active` 和 `rgb[23:0]`。父包装模块负责在帧首整体快照所有状态输入，本模块不另做跨时钟域或帧一致性处理。

面板 x=32..1247，顶部 y=8..111，底部 y=608..711。文字 x=48..1231，六行依次从 y=12/44/76/612/644/676 开始，每格 32×32，最多 37 格。中央 ROI x=320..959、y=120..599 从不激活。面板外 `active=0,rgb=0`；父层用 `active` 合成，不能把面板外零值直接覆盖摄像画面。

顶部三行显示模式、题号/10、分数/10；来源与正式计分限制；音频模拟状态和按键模拟脚本标识。底部三行显示题目或完成总分；正确、重试、揭示、移走要求或结束提示；当前识别或揭示的正确目标。完成阶段显示“本轮完成：共10题，总分”与两位分数。未知/不支持对象显示“未知目标”，越界分数或题号显示 `--`，非法模式/阶段/反馈显示状态异常，不伪装为正确作答。

模式 0=待机、1=探索、2=问答；phase 0=闲、1=等待、2=反馈、3=完成；feedback 0=无、1=正确、2=再试、3=揭示。对象编号 1..9 沿用红/黄/蓝与圆/方/三角组合。`source_test=1` 时顶部和底部同时明确“禁止正式计分”；摄像来源显示“实时画面，待实物验收”。音频与按键始终标为模拟，音频故障不让其它状态文字消失。

背景 `18242C`；普通文字 `F5F7FA`；题目/模式青色 `ABE8F2`；警示 `FFE3A3`；正确与完成 `9EF0CC`。本任务没有真实播放器或新物理按键绑定，不表示实物识别准确率已验收。

## 字库与复现

`generate-font.py` 依赖 Pillow，仅写本任务 `quiz_font_rom.v`、`quiz_content.v` 和 `quiz_bitmap_reference.svh`。默认字体为本机 `C:/Windows/Fonts/simsun.ttc` 的 SimSun 字面，16 px 灰度栅格以阈值 128 二值化，中文与 ASCII 均在 16×16 中居中并二倍显示。本次源字体 SHA-256：`1526AC24375F51F6EB73BC2D3F8072DBE4A80A3A65217677C9D9A84F67DAB2AB`。143 个字形、37 条文本；最长文本 20 格。首次生成因中文超出预留 128 槽拒绝输出，随后改为保留 ASCII 数字编号的紧凑编号并成功生成，未动旧字库。

```powershell
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' fpga/scripts/sc520-quiz-video/generate-font.py
```

只抽取本任务所需位图，不复制原字体文件，不宣称字体具有开源或对外分发许可。未来对外提交素材许可仍需审核。生成后 RTL 是组合 case ROM，不依赖运行时字体、图片文件、Python 或网络；TD 6.2.1 的实际资源和时序以完整工程构建为准。

## 专项仿真

顶层 `tb_quiz_osd`，编译三个 RTL 与 TB，并将 `fpga/sim/sc520-quiz-video` 加入 include 路径。`run -all`；输出 `test_done/errors/checks` 和 `SUMMARY` 后 `$finish`。父任务统一 ModelSim runner 保存实际输入/日志/结果哈希并传播错误退出码。

26 个界面场景覆盖九类题目、待机/探索、正确/重试/揭示/完成、0 与 10 分、非法项/状态/越界数值、音频模拟忙/故障、测试来源与移走资格。每个场景逐像素检查上下各 120 行；另完整检查中央 ROI 不激活、全部对象编号的文本选择、256 个字形编号的全部 16 行、尾部空白与面板边界。参考使用与生产字库相同的字体素材，以独立整张位图打包、独立坐标/颜色/文字选择计算核对输出；它不是独立字体美观性判断，仍需查看 PPM。

正常运行生成 `quiz-osd-00.ppm` 等 1280×240 图像，上半是实际 y=0..119 的输出，下半是实际 y=600..719 的输出。非 active 区仅填中性查看底色，不是摄像内容或上板照片。父级视频仿真再生成完整画面核对整帧合成。`+NEGATIVE` 只在一个实际 RGB 输出像素强制白色，由普通像素检查器报错；不修改预期常量冒充故障检测。

## 首轮实际仿真与像素图核查

父任务实际运行 `runs/osd-normal-20261006-221109-36182627`，本代理回读其 `summary.json`：`done=1,errors=0,checks=8320089`，26 场景正常通过。本轮没有改动冻结的 RTL、TB 或运行目录。ModelSim 10.7 对 `%02d` 的文件名产生前导空格，因此实际前三份 PPM 是 `quiz-osd- 0.ppm`、`quiz-osd- 1.ppm`、`quiz-osd- 2.ppm`；保留原名，只将预览 PNG 规范为 `quiz-osd-00.png` 等。

已实际执行：

```powershell
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' fpga/scripts/sc520-quiz-video/render-preview.py --run-directory evidence/sc520-quiz-video/runs/osd-normal-20261006-221109-36182627 --output-directory evidence/sc520-quiz-video/preview/osd-normal-20261006-221109-36182627
```

输出 11 张 1280×240 PNG，只做 PPM 解码与 PNG 无损编码，没有缩放、裁剪、重绘或改色。转换器逐张重新解码 PNG，并比较全部 RGB 像素与 PPM 一致；转换前后检查 PPM 未变化。`preview/osd-normal-20261006-221109-36182627/preview-manifest.json` 绑定源运行清单、生成器、11 对输入/输出 SHA-256、尺寸与逐像素相等结果。相同路径已有不同 PNG 时拒绝覆盖；后续全幅 PPM 可用同一脚本写入独立输出目录。

使用 `view_image` 实际查看全部 11 张 PNG（00、01、02、10..17）：确认待机/探索、红色圆形与蓝色三角形题目、正确加 1、黄色方形题目下黄色圆形错误重试、两次错答揭示蓝色三角形、10/10 总分完成、双处测试禁计分、音频模拟故障、移走后才能答题提示。各图音频模拟与按键模拟标志可见；原尺寸中文可辨认，未见文字越出面板或截断。`visual-review.json` 逐图记录实际观察，并再次核对 22 个源/输出文件哈希一致。

这些结论仅覆盖本次 RTL 上下屏条带与软件显示，不能替代后续完整视频合成、实物显示器过扫描/可读性或硬件声音检查。根任务继续统一登记本批文件与索引。

## 最终全幅视频预览核查

实际全幅运行 `runs/full-normal-20261006-233455-5f98e1af` 已结束。转换前回读并核对 `run-manifest.json` 与 `summary.json`：`testcase=full,negative=0,done=1,errors=0,checks=82601565,ExitCode=0,ChangedInputs=[]`。20 份当前输入逐一符合运行前后哈希，五份 PPM 符合运行清单输出哈希后，才执行以下转换：

```powershell
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' fpga/scripts/sc520-quiz-video/render-preview.py --run-directory evidence/sc520-quiz-video/runs/full-normal-20261006-233455-5f98e1af --output-directory evidence/sc520-quiz-video/preview/full-normal-20261006-233455-5f98e1af
```

生成 `question.png`、`correct.png`、`wrong.png`、`finished.png`、`cleared.png`，均为原样 1280×720。PNG 逐像素回读与 PPM 的 RGB 完全相同，未裁剪、缩放、改色或重绘。对应 `preview-manifest.json` 记录转换与输入输出哈希，`visual-review.json` 记录逐图实际检查和源运行资格。另核对早期 OSD 条带运行与本次全幅运行的 `quiz_osd.v`、`quiz_content.v`、`quiz_font_rom.v` 三份哈希一致；早期条带图不伪称来自本次全幅运行。

已用 `view_image` 逐张查看这五张完整 PNG：

- `question`：第 01 题、0 分、目标红色圆形、未知目标与移走提示。
- `correct`：中心红色圆形和青色检测框保留，显示正确加 1 分，分数为 01/10。
- `wrong`：第 02 题要求红色方形，实际红色圆形，显示再试一次且仍为 01/10。
- `finished`：第 10 题完成，总分 01；当前未知目标。此帧中央仍保留旧青框，下一张清分图已消失，属于既有检测框丢失延迟的可见表现，不据此声称检测框瞬时清除。
- `cleared`：返回待机、题号 `--`、分数 00/10，当前未知目标。

五图固定红色 ROI 均完整可见，题目/反馈面板未覆盖中央区域；中文与分数未见截断；音频模拟和按键模拟标识始终可见。灰色背景与红色几何图形是测试台送入真实 RTL 摄像路径的合成刺激，不是实物摄像照片。全幅有效区验证也不等于完整板级 MIPI/DDR/HDMI PHY 时序或真实出声验收。本批未修改 RTL、TB、冻结运行或既有条带 PNG，交根任务统一登记。
