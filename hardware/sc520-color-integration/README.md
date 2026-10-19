# T026 固定色彩与背景分割候选

当前最终候选工程：`fpga/custom_project/sc520-color26-bg/`。当前构建编号 `6a50b261`；在软件和物理均经主对话审核前禁止生成、下载或写入 bit。旧 `sc520-color26` / `6a50b260` 保留为失败基线，不是可用镜像。

## 实现范围

| 环节 | 实际实现 |
|---|---|
| SC520CS配置 | 曝光半行1800、gain索引144；分组写3E00=00/3E01=70/3E02=80、3E09=0F/3E06=00/3E07=80；3812=00/30提交 |
| 启动资格 | 初始化完成后一次AE请求，必须经历AE忙到完成才使O_applied有效；送入原cfg_done两级同步和帧资格 |
| 颜色 | 固定Q8 WB304/256/333，截断后饱和，沿用tone1插值；全识别继续stage2，stage1只做诊断 |
| 三色 | sum非零且100×(最大分量−次大分量)≥3×sum；R/G/B最大分别为红/黄/蓝；无附加暗阈值 |
| 前景 | 保留原16桶边界中位数和RGB±48；同时要求R−G、B−G落在本帧边界最小/最大值±4内才属于可连通背景 |
| 背景存储 | 双bank各4个signed9极值；比较扩大signed10；随原bank归属/完整帧资格发布，不增加帧RAM |
| 时序 | 判色分两级，全部60位控制、坐标和frame ID同步延迟；原图像54拍和六层N+5显示不变 |
| 形状/卡片 | 原前景连通、纸张选择、形状守卫、256模板、同tag合并与三帧确认保持 |
| 显示 | 相机底图饱和度×1.25；Q8亮度77R+150G+29B，最终一次舍入和饱和；分割色块、文字、诊断和Logo不增强 |
| 语音 | 三VERIFIED=0、TRACKS空；正式顶层不引出未核音频三针位，内部RX=1/BUSY=0，冻结音频核心独立软件测试保持 |

新背景比较式不是色彩真值模型。它区分共同亮度变化和色差变化：木纹在RGB三通道共同变亮/变暗时，R−G和B−G基本不变；原48DN亮度宽容度得以保留。4DN为当前工程候选裕量，未视为现场噪声标定结果。

## 当前软件证据

`evidence/sc520-color-integration/software-v2.json` 绑定七轮选定软件证据、每份输入快照/输出SHA和当前构建输入。296场景、124,577,044检查、0错误包括：

- 163335数值向量与固定曝光启动资格；
- 四幅完整720p画面，字面独立golden逐像素比较、四键/问答/诊断/Logo及六层同步；
- 21场景的九种真实颜色纹理合成积木、五卡片和七均匀空场；原四反例期望未改，最终63帧通过；
- 七个完整54拍色彩/复位/观察帧，以及真实场景到UART模型的业务验证；
- 两级分类与未流水参考恰差两拍的23场景，包括坏栅格、坏tag/source/end、flush、三帧恢复；
- 221场景的完整7200像素scene replay和1024位归一化mask独立oracle比较。

主安排的独立审查另有全RGB数值穷举、真实I2C及新两级分类穷举/metadata测试，证据保存在共享 `learning/sc520-color-integration/review/`，没有混入上面的本代理检查数。

原失败必须保留：`scenes-normal-20261019-115257-c80240` 有四场景/13错误；`6a50b260` 最终建立余量−3.405ns且audio报告钩子失败。`background-proposal-v2` 的8DN仍不能恢复红木三角；这些都不是通过记录。

## 工程与复现

构建器从既有 `sc520-fixed-roi/fpga/custom_project/sc520-board-keys` 读取已封存的厂商IP及板级原工程，用新overlay替换实际入口。所有实际引用和IP附属文件逐项绑定在新构建 `inputs.json`；不要直接打开旧audio22或T023工程当作本候选。

```powershell
$py = 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $py -B -X utf8 fpga/scripts/sc520-card-recognition/prepare-color26-bg.py
& $py -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-color26.py --test scenes_bg
& $py -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-color26.py --test reset_bg
& $py -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-color26.py --test pipeline_bg
& $py -B -X utf8 fpga/scripts/sc520-card-recognition/simulate-color26.py --test block_pipe
```

上述测试使用已生成的独立fixture；生成器与来源SHA分别位于 `fixtures/`、`scenes/` 和 `scene-oracles-v1/`。已完成的测试不需要为了交接反复执行。需要新构建时使用未存在的八位十六进制RunId执行 `build-color26-bg.ps1`，不复用或覆盖261。

## 尚未证明的事项

现场包只来自固定画面；将真实纹理贴进旧几何是合成验证，不是新的深色/木色背景硬件实拍。均匀背景和同分布边界噪声通过，不保证干净边界中间突然偏色仍为空：独立测试中的内部红通道+6DN可以被保守判为未知前景。多色边界离群值也可能扩大包络、削弱分离能力。

G最大映射黄仅适合本组现场传感器域；理想等R/G黄色会拒识，纯绿会按黄处理，极暗偏色可以命中。形状、前景及三帧资格仍需同时满足。真实物体、位置/旋转/光照、最终镜头光学、长时间稳定性和音频实物仍待对应验收。
