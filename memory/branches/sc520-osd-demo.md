# SC520 中文OSD与启动测试模式

- 任务 ID：sc520-osd-demo
- 状态：等待主对话审核
- 负责人：开发对话01a0fffd-0eb9-7010-9921-5b66e6c1f7d2
- 分支：task/sc520-fixed-roi
- 基础提交：f609426044982c986b54e999866be9f4c1af2682
- 开始时间：2026-10-03（Asia/Shanghai）

## 目标与验收条件

用户授权继续开发至上板前，已先说明下次测试与九片彩纸准备。独立工程启动自动展示红黄蓝x圆方三角及空白，每场景180视频帧，之后进入摄像头模式，复位重播，不改变原曝光按键。测试图送入同一颜色/统计/分类链，中文显示实际识别结果，并独立标明输入和模式，避免伪造识别。保留旧版回退，暂不调实物阈值，不改共享接口。

## 已读文档

根AGENTS/README/FILE_INDEX和最新shape交接；仓库规则、PROJECT_MEMORY/PLAN/TASKS/DECISIONS/接口及shape日志。总记忆仍为旧状态，不能覆盖最新证据，只有主对话可更新。形状版未实物验证。

## 修改范围

仅本任务fpga/custom_project、scripts、sim、evidence、分支日志与learning/sc520-osd-demo及共享登记。旧任务、main和曝光按键保持不变。

## 验证与进展

启动核对分支及未提交文件，无新提交。准备独立源快照；软件仿真、综合布局布线和字形可视检查待执行。

## 实现进展（2026-10-03）

新增启动场景控制、无乘法图形发生器、29字16x16点阵ROM、中文OSD与独立wrapper。输入预期与识别结果分行展示；模式/场景切换在消隐期清空检测历史。上电演示10场景各180帧后转摄像头，按键及相机/DDR/PLL配置未改。字体来自本机SimSun栅格化子集，未复制原字体文件；首次英文Name检查遇中文本地化名导致脚本拒绝，改用FontFamily英文标识后生成成功，另缩小到14px字身留边距，已查看atlas。最初OSD参考模型误把白色“输入/识别”前缀当彩色，修正测试参考后13状态585728像素errors=0。sequence和pattern初测通过，待最终源码绑定回归。TD构建正在进行；未上板。

## 验证完成（2026-10-03）

ModelSim15项正常仿真全部errors=0，demo/display两项注入各4错误且退出1符合预期。新增full验证88个720p帧、81100800像素、108900096周期；默认180帧场景由sequence的12644检查单独验证。TD6.2.1综合/物理/bitgen退出0，Setup136ps、Hold20ps、TNS0、STA96.10%；与形状版warning行集合无新增，继承警告仍存在。封装17项源哈希与回退核对通过，候选SHA256 9D3B1CBDB271CF9C3198F4FC9DE49580B54BE2E918B4233829A6625D2D20945B，1789539字节。已导出5幅仿真PNG并查看黄色方形、蓝色三角和摄像模式无目标，均不是实物证据。测试参考修复过程与失败日志如实保留。

实际命令：pwsh -File fpga/scripts/sc520-osd-demo/simulate.ps1 -Testcase <sequence|pattern|osd|demo|full|classifier|confirm|label|shapes|stats|stability|capacity|color|sync|display>；另demo/display -Negative；build.ps1；package.ps1 -BuildDirectory evidence/sc520-osd-demo/builds/osd-demo-20261003-191555-58524。Python render-sim.py将全尺寸仿真PPM转PNG。完整复现、资源、覆盖与局限见evidence/sc520-osd-demo/run-report.md；用户清单E:/juan/FPGA/learning/sc520-osd-demo/README.md。

无新提交，未运行finish-task提交流程；保留上一版回退。下一步用户SRAM验证A组无需实物，B组九片彩纸和30分钟长测可后补。建议主对话仅审核软件完成，不改成硬件通过。

## 最终交接核对

文档链接全部存在；任务PowerShell脚本Parser和Python AST检查通过；再次package确认17项与输入/bit哈希仍一致。main仍有21项原有改动，本对话未触碰。最终发现Worktree的.gitattributes/.gitignore已由协作对话01a0fc00-4206-72f0-83e0-187c5e76a1e5登记修改（20261003-190942-sc520-checkpoint-prepare-5e76.json），为选择性检查点规则，不回滚、不纳为本任务改动；其隔离提交记录明确未包含本OSD任务，不应声称本版已上传GitHub。当前活动HEAD仍为基础提交。

## 风险与待决策

启动演示约30秒以720p60设计时序估计，不是实测帧率；摄像头/DDR配置仍需原接线。本地诊断不是正式共享item_id接口；字体来源和生成方式随证据记录。实物识别仍受朝向、光照和多目标限制。

## 建议总文档更新及交接

只报告本任务软件/硬件各自证据，主对话审核决定接口接入。不下载、不写Flash、不提交推送合并。

## 2026-10-04 对话分工

用户明确要求原对话01a0fffd-0eb9-7010-9921-5b66e6c1f7d2保留为验证入口，等待sc520_shape.bit和sc520_osd_demo.bit的上板反馈；不在此对话继续扩展下一阶段功能。两份候选仍是软件已验证、硬件待验证，原bit及工程保持不变。

新建对话01a10505-771c-7690-ae31-3ed7451e4866，标题“SC520 学习界面与语音逻辑开发”，承接独立任务sc520-learning-ui-audio的软件与仿真：识别事件/去重、学习内容映射与中文/拼音/英文显示、播放器抽象及模拟测试。实际DFPlayer型号和手册尚缺，不臆造电气连接或协议；共享接口变更仍须主对话审核。新对话只在自己的任务目录和日志写入，不覆盖此处待验证候选，也不得将内置演示通过写成实物识别通过。

本批仅交接与分工登记，未重跑仿真/构建，未下载、写Flash、提交或推送；后续验证照片/视频仍由用户发回原对话。
