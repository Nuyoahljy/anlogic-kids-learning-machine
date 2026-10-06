# SC520 中文OSD与启动演示：软件验证报告

日期：2026-10-03（Asia/Shanghai）。负责人：开发对话01a0fffd-0eb9-7010-9921-5b66e6c1f7d2。
状态：软件验证完成，等待用户上板与主对话审核。基础HEAD f609426044982c986b54e999866be9f4c1af2682，分支task/sc520-fixed-roi；无新提交、推送、合并、下载或Flash操作。

## 实现与证据绑定

[来源清单](origin.json)记录从形状版236份输入逐份校验复制。仅导入顶层实例和al/syn-prj/phy-prj四份工程清单按预期变化，原形状工程及回退bit未改。新模块demo_sequence、demo_pattern、osd_font_rom、chinese_osd、hdmi_osd_demo独立新增。相机、DDR、PLL/SDC、曝光按键和共享接口未改，没有共享item_id输出。

测试像素在坐标适配后、颜色分割前注入；统计、动态框、形状分类/确认与摄像模式共用。中文分三行分别显示模式、输入来源/预期、实际识别结果，不把预期编号赋给分类结果。OSD在统计之后叠加，不会把文字本身识别为目标。切换场景/模式时清除检测历史，视频延迟保持3拍。启动10场景各180视频帧后进入摄像模式，复位重播；约30秒来自60fps设计值，不是实测帧率。

## 实际执行环境与结果

Windows、PowerShell7、ModelSim10.7、TD6.2.1 Engineer6.2.168.116；Python/Pillow用于转换仿真PPM为PNG。最终15项正常仿真errors=0/exit0，2项故障注入各errors=4/exit1符合预期，选中运行的ModelSim编译0 errors/0 warnings。

| 测试 | 实际覆盖 |
|---|---|
| sequence | 默认180帧/场景，12644项检查，模式/场景/计数/复位与单拍切换脉冲 |
| pattern | 629376像素；独立平方根圆轮廓参考、方/三角、颜色、背景、位移端点 |
| osd | 13状态585728像素；九组合、未知、无目标、摄像来源、字库逐像素与区域外无效 |
| demo | 384x240，88帧8110080像素、8286176周期、88次状态检查；九组合→空白→模拟摄像目标→移走→复位 |
| demo -Negative | 同样覆盖，强制4拍错误RGB，实际检测4错误并退出1 |
| full | 1280x720，88帧81100800像素、108900096周期、88次状态检查，已知形状/中文/同步延迟/模式切换与清除 |
| classifier / confirm | 156边界样本 / 282确认检查 |
| label / shapes | 旧字形120000检查 / 110合成帧1351680像素（3色×3形×3尺寸） |
| stats / stability / capacity | 19用例9728像素 / 323检查 / 1843200像素 |
| color / sync | 155183颜色样本 / 389同步检查 |
| display | 旧uivtc+mixer+shape链26个720p帧、25933311有效像素、34765656周期、27帧状态检查、16复位检查 |
| display -Negative | 旧链4拍故障注入检测到4错误，退出1 |

为缩短仿真，demo/full把每场景设为8帧；180帧默认计数另由sequence验证。full输入采用1650x750总周期结构，测试台简化hs脉冲；原uivtc/mixer由display独立回归，不声称新工程的完整相机/DDR/HDMI PHY端到端仿真。框的状态/位置/宽度另有检查，像素边框参考使用DUT稳定边界；像素源、预期类别、中文内容和RGB参考独立计算。旧display的inherited_read_skips=39保留为既有观察，不当作实测丢帧。

## 构建与时序

[构建结果](builds/osd-demo-20261003-191555-58524/result.json)中综合和物理实现退出0，bitgen完成。[时序](builds/osd-demo-20261003-191555-58524/final_timing.rpt)与[资源](builds/osd-demo-20261003-191555-58524/final_area.rpt)已随候选封装绑定哈希。

| 指标 | 形状版 | 本版 |
|---|---:|---:|
| Setup WNS | 0.101ns | 0.136ns |
| Hold WNS | 0.020ns | 0.020ns |
| STA覆盖 | 95.62% | 96.10% |
| LUT6 | 11423 | 12055 |
| 寄存器 | 14214 | 14179 |
| Slice | 13760 | 14178 |
| ERAM | 39 | 39 |
| DSP | 16 | 16 |

Setup/Hold TNS=0、NUM_FEPS=0。时序为正但余量较小且约束覆盖不完整；综合/物理warning行集合与旧形状版比较无新增，仍保留混合时钟扇出、PLL IO/local-routing及IP警告，不宣称问题已修复。资源下降项是工具优化后的全设计统计，不代表删除了必要逻辑。

## 字体与视觉检查

字库由generate-font.ps1用本机SimSun生成29字位图子集，16x16单元内14像素字身、HDMI放大2倍；未复制原字体文件，不将字体称为开源，最终公开素材许可由主对话审核。[字形数据](font/glyphs.json)和[字形图](font/atlas.png)保留来源与映射。

全尺寸仿真直接导出5幅PPM，render-sim.py无重绘转换成PNG：[清单](previews/manifest.json)。已查看黄色正方形、蓝色三角形、摄像模式无目标三幅，文字、模式与检测框位置符合预期；蓝色字的实际显示器可读性仍应上板检查。

- [黄色正方形仿真](previews/test-yellow-square.png)
- [蓝色三角形仿真](previews/test-blue-triangle.png)
- [摄像模式无目标仿真](previews/camera-synthetic-empty.png)

所有预览都是RTL仿真，不是板上照片；“摄像模式”预览也使用测试台合成RGB，不证明摄像头实物识别成功。

## 调试历史

首次字体英文名称检查遇本地化Name，脚本按设计拒绝后改用FontFamily英文标识。第一次OSD测试参考误把白色字段前缀按目标色比较；修正参考后通过。整链测试台曾有无空格十六进制常量与问号的词法错误，以及误套用掩膜版黑背景规则；按现有保留原画面的动态框链修正参考后通过。失败日志原位保留，未用于通过证据；本轮未为了通过测试修改分类阈值。

## 复现

在 E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-fixed-roi 中执行：

~~~powershell
foreach ($test in @('sequence','pattern','osd','demo','full','classifier','confirm','label','shapes','stats','stability','capacity','color','sync','display')) {
    pwsh -File ./fpga/scripts/sc520-osd-demo/simulate.ps1 -Testcase $test
    if ($LASTEXITCODE -ne 0) { throw "Failed: $test" }
}
foreach ($test in @('demo','display')) {
    pwsh -File ./fpga/scripts/sc520-osd-demo/simulate.ps1 -Testcase $test -Negative
    if ($LASTEXITCODE -ne 1) { throw "Expected negative exit 1: $test" }
}
pwsh -File ./fpga/scripts/sc520-osd-demo/build.ps1 -Rebuild
pwsh -File ./fpga/scripts/sc520-osd-demo/package.ps1 -BuildDirectory 'E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-fixed-roi/evidence/sc520-osd-demo/builds/osd-demo-20261003-191555-58524'
~~~

最后一行是本次实际构建目录，重建后应替换为新输出路径。现有工程不要重复prepare；build -Rebuild先保留previous.bit，package拒绝用不同哈希覆盖既有候选。重跑生成输出后必须用register登记并更新根索引。

## 候选与下一步

[sc520_osd_demo.bit](candidates/sc520_osd_demo.bit)：1789539字节；SHA256 9D3B1CBDB271CF9C3198F4FC9DE49580B54BE2E918B4233829A6625D2D20945B。[候选清单](candidate-manifest.json)校验17项测试、输入快照和旧源，HardwareValidated=false。

[用户上板清单与实物准备](<E:/juan/FPGA/learning/sc520-osd-demo/README.md>)。先无需实物测试自动演示、中文、空白清除及摄像接管；再用九片彩纸实测，另做30分钟长测。内置目标不能验证光照、镜头、分割阈值、真实准确率。只有用户实测反馈后才建议主对话更新对应硬件状态，未修改项目总记忆或正式接口。
