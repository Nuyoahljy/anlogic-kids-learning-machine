# SC520 学习界面与模拟音频：验证报告

日期：2026-10-04，Asia/Shanghai。状态：软件验证与候选封装完成，等待主对话审核及用户硬件验证。无新Git提交；分支task/sc520-fixed-roi，基础HEAD f609426044982c986b54e999866be9f4c1af2682。没有下载、Flash、推送、合并、购买或向原对话发消息。

## 结果与实现

独立工程继承已核对的OSD软件候选241份输入，只修改板级top的一处叠加模块实例名与3份工程清单；新增8份学习模块。相机、DDR、HDMI、PLL、SDC、曝光按键及旧任务源码保持原字节。基线是软件候选，尚无OSD/形状实物验收。

识别稳定后按现有1..9编号显示中文、拼音和英文；界面保留真实结果与测试来源区别。自动名称事件只在一次存在过程中触发，未知结果清学习内容，确认移走解除锁存。播放器抽象支持去重、最新待播队列、主动重播、busy、有限明确拒绝重试、迟到响应防护和超时fault。顶层采用无声mock，标明“语音模拟”，没有UART与新增音频引脚。[局部接口提案](local-interface.md)等待主对话审核，未改共享契约。

## 实际验证

ModelSim SE-64 10.7；TD工具限定6.2.1 Engineer6.2.168.116。最终测试的源码/脚本、进程退出码、summary与实际日志由封装脚本逐一检查，11项为7个正常运行和4个预期失败控制。

| 运行 | 实际覆盖与结果 |
|---|---|
| events | 13081检查，604检测适配场景、50事件场景、3102参数场景，九编号全覆盖，0错误 |
| events负向 | 故意设置错误复位期望，1错误、退出1；是检查器负向，非RTL故障 |
| audio | 27正常行为场景、1456检查，0错误；默认120tick完成、300/900tick超时与最多1次明确拒绝重试逐tick核对 |
| audio负向 | 强制错误状态，1458检查中1预期错误、退出1 |
| learning_osd | 33场景、8192内容查询、5406984像素，0错误；九中文/拼音/英文、非法项、无目标、来源与状态 |
| learning_osd负向 | 强制错误RGB，5406984像素检查均报告预期错误、退出1 |
| sequence | 默认180帧场景计数与切换、复位，12644检查，0错误 |
| demo | 384x240，88帧8110080像素、8286176周期，0错误；自动事件总数10 |
| demo负向 | 整链4拍RGB注入，4错误、退出1 |
| full | 1280x720，88帧81100800像素、108900096周期，0错误；学习UI、模拟状态、类别、清除、三拍同步及10次自动事件 |
| transition修复后 | 35帧3225600像素、3295839检查，0错误；真实像素红方→黄方→移位→空白→蓝方，播报2次、取消1次；独立框x/y/w/h、适配坐标、计数与UI |

[事件专项](events-report.md)、[音频专项](audio-report.md)、[OSD专项](osd-report.md)、[切换回归及失败快照](transition-report.md)提供完整命令、hash和覆盖细节。最终full目录为sim-runs/full-0-20261004-120640-32188；demo为demo-0-20261004-120640-31752，负向demo-1-20261004-120810-30112，sequence-0-20261004-120810-32716。

full/demo为缩短仿真设每场景8帧，默认180由sequence独立检查。测试的摄像来源仍是合成RGB；没有仿真真实MIPI、DDR、HDMI PHY。full边框像素参考沿用DUT稳定框，位置/宽度另查；transition新增独立x/y/w/h参考以补足这部分。不是任意颜色、角度、光照或遮挡的准确率证明。

## 发现的问题与修复

首版标准88帧测试和TD（Setup131ps、Hold20ps）虽通过，独立审阅发现连续换色或移动时box_valid暂时撤销，会被误当移走。新transition真实复现11错误：播报4次/取消3次；同一TB与期望未改，wrapper把存在条件改为det_present || candidate_valid后，结果为0错误、播报2次/取消1次。前后日志、源快照和独立登记保留。最终采用修复后的wrapper BABB610956591F4C4095E176660DE9F282350A9C685BF7DCD5BBA7DC10476586，所有wrapper依赖仿真及TD重跑。

一次辅助Python读取中文脚本因默认GBK解码失败，显式UTF-8修正；系统Python缺Pillow时转换失败，改用应用自带Python后成功，未安装依赖。音频第一次正常后加强manifest输出hash并重跑，后又补默认参数回归；旧输出保留。所有失败与中间成功结果没有冒充最终候选依据。

构建证据审阅发现旧build脚本只绑定bit与源码、报告还在可变phy目录。新增archive-build.py明确在TD完成后归档bit/时序/面积，核对报告时间范围与实际stdout的时序，绑定日志和各文件hash；package只用独立归档。当前已运行的build仍是补丁前脚本，因此完成后显式调用归档并记录真实时间；未来build自动归档且保存构建脚本快照。

## 视觉检查与素材

[黄色方形整帧仿真](previews/full-0-20261004-120640-32188/test-yellow-square.png)和[摄像来源空场景仿真](previews/full-0-20261004-120640-32188/camera-synthetic-empty.png)已实际查看，底部文字完整且在ROI下方，未覆盖目标；另有红圆、蓝三角与摄像来源红方。[预览清单](previews/full-0-20261004-120640-32188/manifest.json)将原PPM与PNG绑定hash，转换未重绘像素。空场景截图是第86帧，文字已清除、模拟播放取消确认尚未结束；第87帧模拟状态清为空闲已由full逐像素及状态断言检查，未伪造该帧截图。

字库为本机SimSun的63字位图子集，未复制原字体文件、不声称开源；最终对外素材许可仍需审核。模拟截图不是上板照片，显示器过扫描、实物颜色阈值和字体可读性仍待验证。

## 复现命令

在E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-fixed-roi执行：

```powershell
pwsh -File fpga/scripts/sc520-learning-ui-audio/events-simulate.ps1
pwsh -File fpga/scripts/sc520-learning-ui-audio/events-simulate.ps1 -Negative
pwsh -File fpga/scripts/sc520-learning-ui-audio/audio-simulate.ps1
pwsh -File fpga/scripts/sc520-learning-ui-audio/audio-simulate.ps1 -Negative
pwsh -File fpga/scripts/sc520-learning-ui-audio/osd-simulate.ps1
pwsh -File fpga/scripts/sc520-learning-ui-audio/osd-simulate.ps1 -Negative
pwsh -File fpga/scripts/sc520-learning-ui-audio/transition-simulate.ps1 -Phase after-fix
pwsh -File fpga/scripts/sc520-learning-ui-audio/simulate.ps1 -Testcase sequence
pwsh -File fpga/scripts/sc520-learning-ui-audio/simulate.ps1 -Testcase demo
pwsh -File fpga/scripts/sc520-learning-ui-audio/simulate.ps1 -Testcase demo -Negative
pwsh -File fpga/scripts/sc520-learning-ui-audio/simulate.ps1 -Testcase full
pwsh -File fpga/scripts/sc520-learning-ui-audio/build.ps1 -Rebuild
python fpga/scripts/sc520-learning-ui-audio/archive-build.py --build-directory evidence/sc520-learning-ui-audio/builds/learning-ui-audio-20261004-120640-18752
python fpga/scripts/sc520-learning-ui-audio/package.py --build-directory evidence/sc520-learning-ui-audio/builds/learning-ui-audio-20261004-120640-18752
& 'C:/Users/33630/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' fpga/scripts/sc520-learning-ui-audio/render-sim.py --run-directory evidence/sc520-learning-ui-audio/sim-runs/full-0-20261004-120640-32188
```

负向命令退出1是预期结果，不可被包装脚本吞掉；正常应退出0。build/模拟重跑后目录会改变，替换为新路径。已有工程不重复prepare；package拒绝覆盖不同SHA的候选。新运行生成文件后仍需任务日志、独立JSON登记、统一索引生成及Check。

## 构建与候选

修复后构建[结果](builds/learning-ui-audio-20261004-120640-18752/result.json)、[独立归档](builds/learning-ui-audio-20261004-120640-18752/archive-manifest.json)和[最终时序](builds/learning-ui-audio-20261004-120640-18752/final_timing.rpt)均已绑定到[候选清单](candidate-manifest.json)。综合、物理实现均退出0、bitgen完成。当前运行启动时尚无新归档步骤，完成后实际显式运行archive-build.py，BuilderSnapshotAvailable=false如实保留；归档时间见manifest，不伪称原脚本自动捕获。

| 指标 | OSD输入候选 | 本轮修复后候选 |
|---|---:|---:|
| Setup WNS | 0.136 ns | 0.102 ns |
| Hold WNS | 0.020 ns | 0.020 ns |
| Setup/Hold TNS | 0 / 0 | 0 / 0 |
| STA覆盖 | 96.10% | 96.24% |
| LUT6 | 12055 | 13434 |
| 寄存器 | 14179 | 14299 |
| Slice | 14178 | 15472 |
| ERAM / DSP | 39 / 16 | 39 / 16 |

时序余量较小、约束覆盖不完整。[告警对比](warning-comparison.json)检查综合97条与物理9条不同WARNING文本，与OSD候选集合相同，无新增或消失；不代表这些继承的IP位宽、混合时钟扇出、PLL/IO和本地时钟路由问题已经解决。

[sc520_learning_ui_audio.bit](candidates/sc520_learning_ui_audio.bit)：1789539字节，SHA256 `F2AF49F3185330A1416CD837D7086A0009EB9CC2321840A55F5D3C45CDB47BC0`。独立归档逐项核对bit、时序/面积、stdout/stderr与源码快照，package核对11项最终测试和1508个保护输入；重复封装只允许相同SHA，候选采用exclusive创建避免覆盖。首版131ps构建及previous.bit仅保留历史，不作修复后候选依据。

## 边界与交接

两份原bit哈希不变；原1508项保护输入已复核。没有提交，未运行会触发提交的finish-task；既有.gitattributes/.gitignore由检查点对话维护，本轮保持原样。新learning源码可能被当前Git忽略规则排除，未来检查点须明确核对写集，不能据git status短列表断言已上传。

真实DFPlayer型号、购买链接、协议、电气和存储文件规则缺失；继续边界是对应硬件资料与主对话接口审核。不能声称串口/真实音频/整机联调完成。五类卡片和完整问答尚未开发。本轮方案不包含捕获帧号接口，不能擅接共享frame_id。主对话建议只审核软件和局部存在/取消/队列语义，再安排独立硬件验证。

[用户导读与上板清单](E:/juan/FPGA/learning/sc520-learning-ui-audio/README.md)；本任务日志memory/branches/sc520-learning-ui-audio.md是交接入口。
