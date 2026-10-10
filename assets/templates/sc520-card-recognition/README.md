# 五类卡片的软件模板与样本

原 SVG 只读来自 `E:/juan/FPGA/learning/sc520-next-stage-prep/cards/` 的 prep-v1 图稿。这里只保存派生模板、人工测试图像和软件参考；没有相机照片，不能据此声明实物准确率。

2026-10-10，主对话选择本阶段实验配置：`MAX_DISTANCE=40`、`MIN_MARGIN=24`、前景计数范围`16..850`，不采用额外的模板前景比率限制。当前数据入口为`prep-v1-max40/`。这些参数仍需用打印卡片和相机实拍校准，不是已经冻结的实物识别指标。

## 数据批次

| 目录 | 内容与状态 |
|---|---|
| `prep-v1/` | 首次生成，阈值120。69个样本，保留历史；Pillow `getdata()`给出弃用提示，输出本身生成成功。缺少后来新增的`vectors.list`。 |
| `prep-v1-r2/` | 阈值120基线，补`vectors.list`并消除弃用提示。8组独立结构与参考检查通过；3个圆形负样本误收为苹果，4个半遮挡样本仍接受。 |
| `prep-v1-max40/` | 本阶段已选择的阈值40实验数据，8组独立检查通过；这组14个负样本和5个半遮挡都拒识。5个canonical接受，20个一格位移仅4个接受。实物效果待验证。 |
| `qa-r2/`、`qa-max40/` | 各数据批次的独立验证报告；脚本不导入生成器，用RGB地址采样、整数XOR和bit_count重新算距离。 |
| `policy-comparison.json` | 保留选型时的阈值120、阈值40、阈值40加模板前景比率三个策略及逐项模型结果。主对话已选40且不加比率；额外比率只增加本组位移拒识。 |

阈值40是在观察同一组开发样本之后提出的，因此这些结果也不是留出测试准确率。三次数据生成没有改动原图；每轮输出目录都保留，脚本拒绝覆盖。

## 阈值40的实际模型结果

| 样本类别 | 数量 | 接受 | 拒识 |
|---|---:|---:|---:|
| 与模板同源的标准图（canonical） | 5 | 5 | 0 |
| 上下左右平移一格（4像素） | 20 | 4 | 16 |
| 正负5度旋转 | 10 | 10 | 0 |
| 亮度乘0.65或1.20 | 10 | 5 | 5 |
| 固定种子的椒盐噪点 | 5 | 5 | 0 |
| 右半幅白色遮挡 | 5 | 0 | 5 |
| 红黄蓝的圆、方、三角负样本 | 9 | 0 | 9 |
| 全白、全黑负样本 | 2 | 0 | 2 |
| 苹果与雨伞混合负样本 | 1 | 0 | 1 |
| 棋盘格未知负样本 | 1 | 0 | 1 |
| 采样点之间的细线负样本 | 1 | 0 | 1 |
| 合计 | 69 | 29 | 40 |

接受的已知样本均输出其预设类别，本组没有类别混淆。所有5个偏暗样本均拒识，说明固定亮度门限需要实拍校准；多数一格平移被拒，说明本阶段对居中摆放要求较高。14个负样本全部拒识只描述这组开发输入，不能扩展为任意未知物都可拒识。

`qa-max40/validation.json`记录2026-10-10 19:44:17（Asia/Shanghai）的8组结构和独立软件参考检查通过，包括69个样本和69次中心RGB故障注入检错。恢复任务时只读重算了231个清单文件的哈希与大小、五个源SVG哈希，以及三个策略的207个逐项输出，均与历史报告一致；没有改写历史报告或新造一次测试运行。

## 已核对的源文件

五个原稿均位于`E:/juan/FPGA/learning/sc520-next-stage-prep/cards/`，本轮核对存在性及完整SHA-256与`prep-v1-max40/templates.json`一致。

| 源文件 | SHA-256 |
|---|---|
| `card_10_apple.svg` | `ab75bc0617aa59baa4c830d3ccae05fc37f83aa79b5a20e8260bcad9937cb1cb` |
| `card_11_banana.svg` | `c967356a076cb6465d2c7ac2665c3284e6ab11515550f8abd8873ffd928c5b7f` |
| `card_12_car.svg` | `16555f84afce7fd75745603d964b1d051943996fe1a740f3b7dff576b5a1103a` |
| `card_13_star.svg` | `f3af10b786dfe76abab649d22fecd7f522d8df17fc10092f2f179a7cb7d73ae9` |
| `card_14_umbrella.svg` | `27be15a8e26ae457e5de2aea7ab70c983c7db6570b714931260df1b25194c46d` |

`prep-v1-max40/templates.mem`的SHA-256为`49f75a4695a38afb5290c301c9ab07b538968124a296e7f15711065c85e80c3f`。报告引用的Python、生成器、检查器、Node和sharp路径均已确认存在，当前生成器与检查器哈希仍匹配各自历史报告。

## 共同的数据接口

- 渲染器使用本机已有的 Node sharp/libvips，直接读原SVG并输出256×256 RGB。
- 模板为32×32，采样原图像素 `(8*gx+4,8*gy+4)`。前景条件为`min(R,G,B)<180 || max(R,G,B)-min(R,G,B)>=40`。
- `templates.mem`共1024行，每行5位hex，bit0..4依次是item10苹果、11香蕉、12汽车、13星星、14雨伞；按`gy*32+gx`顺序。
- RGB测试帧为320×180，ROI左上角(96,26)、大小128×128；采样点为ROI内`(4*gx+2,4*gy+2)`。其余画面纯白。
- canonical的ROI像素(x,y)取256图(2x,2y)，保证与模板点精确对齐。它只验证接口，不经过光学、打印、相机或ISP过程。
- `vectors/*.rgb.mem`仅保存128×128 ROI，16384行RRGGBB；`*.bits.mem`保存1024个0/1。PNG是同一RGB数据预览。
- `vectors.list`每行是`stem accepted best second sample_fg roi_fg truth`，数字为十进制；RGB路径为`vectors/<stem>.rgb.mem`。
- `vectors.meta.mem`每样本8个32位hex：index、truth、candidate、accepted、best、second、sample_fg、roi_fg。
- `vectors.json`保留语义标签与明确模型输出，两者不能混用。`model-report.json`完整报告拒识和误收。

采样点之间的细线案例：32×32前景计数为0，但128×128 ROI前景计数4096；最终输出必须与ROI存在性信息结合，不能把采样点全白直接说成“空背景”。

## 可复现脚本

生成器：`fpga/scripts/sc520-card-recognition/generate-templates.py`。为了保持现有历史报告对应的脚本字节，当前脚本缺省仍为120；省略参数会重现旧实验阈值。因此本阶段命令必须显式指定`--max-distance 40`。`--max-distance 120`仅用于复现历史对照。

下列是复现命令示例，本次恢复时没有重新执行生成。两个输出目录必须不存在；再次复现时更换新的目录名。

```powershell
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 `
  'E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/fpga/scripts/sc520-card-recognition/generate-templates.py' `
  --source 'E:/juan/FPGA/learning/sc520-next-stage-prep/cards' `
  --output 'E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/assets/templates/sc520-card-recognition/reproduce-max40-new' `
  --max-distance 40

& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B -X utf8 `
  'E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/fpga/scripts/sc520-card-recognition/test-template-data.py' `
  --input 'E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/assets/templates/sc520-card-recognition/reproduce-max40-new' `
  --output 'E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/assets/templates/sc520-card-recognition/reproduce-max40-qa-new'
```

生成器使用上述bundled Python旁边的`dependencies/node/bin/node.exe`与`dependencies/node/node_modules/sharp`；两者均已核对。若换Python环境，需要通过`--node`和`--node-module-root`指向实际安装位置。历史报告中的相对脚本与输出路径以工作树`E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/`为执行目录。

独立检查：`fpga/scripts/sc520-card-recognition/test-template-data.py --input <数据目录> --output <新的检查目录>`。核查输入原稿哈希、231个输出文件哈希、RGB与PNG一致、采样位、距离、前景门限、metadata、阈值边界以及69次中心像素故障注入检错。

运行依赖、完整命令和脚本哈希都记录在每轮`generation.json`及`validation.json`。所有文本为UTF-8/LF。没有修改共享接口、主项目状态、旧四键工程或音频工程。
