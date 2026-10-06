# SC520 红黄蓝颜色分割

- 任务 ID：sc520-color-mask
- 状态：等待主对话审核
- 负责人：续开发对话 01a0fffd-0eb9-7010-9921-5b66e6c1f7d2
- 分支：task/sc520-fixed-roi（接续原开发；不新建分支、不提交、不推送）
- 基础提交：f609426044982c986b54e999866be9f4c1af2682
- 开始时间：2026-10-03T12:49:06.8966101+08:00
- 结束时间：2026-10-03（软件候选完成；等待用户物理验证）

## 目标与验收条件

用户授权继续开发直至需要上板。保留原 sc520 工程和候选镜像，在独立 sc520-color-mask 工程实现中心区域红/黄/蓝分割。框外保持原画面，框内目标显示纯色、其余黑色，保留红框。720p链路不变；不做形状分类，不改 item_id/检测共享接口。完成RTL自动检查、完整显示链仿真、故障注入、TD 6.2.1构建和候选哈希后停下交给用户。

## 已读文档

工作区 AGENTS/README/FILE_INDEX、最新overlay-observed和handoff；主库及当前Worktree AGENTS、PROJECT_MEMORY、PLAN、TASKS、DECISIONS、接口契约；旧任务日志及构建/仿真脚本；SC520更新说明。旧总记忆仍写待到货，不能覆盖最新现场记录；不改总控文件。

## 修改文件

仅本任务 fpga/custom_project/sc520-color-mask、fpga/scripts/sc520-color-mask、fpga/sim/sc520-color-mask、evidence/sc520-color-mask、本日志和共享 learning/sc520-color-mask、独立记录。原工程和旧bit保持不变。

## 验证命令与结果

启动：当前分支 task/sc520-fixed-roi，原任务6个未跟踪目录/文件保持原状。prepare验证复制227个输入。

实现批：新增rgb_color_segment和hdmi_color_mask，保持三拍接口延迟，使用9位通道比较避免8位加法回绕；黄色优先于红色，边框在分类之后叠加，避免红框污染采样。只改新工程顶层实例与三个源清单。新增color/display/sync测试和独立脚本，测试和构建尚待实际执行。

## 仿真验收（2026-10-03）

命令均在本Worktree使用PowerShell 7执行 fpga/scripts/sc520-color-mask/simulate.ps1。ModelSim SE-64 10.7：

- -Testcase color：155183样本，errors=0，none/red/yellow/blue=97364/22231/30454/5134；含阈值网格、两组65536通道组合、20000确定性随机样本、ROI边界和复位。
- -Testcase sync：389次输出检查，errors=0；启动无帧首旁路、短行、超长行、下一帧恢复、中途复位。
- -Testcase display：5完整帧、8778156周期、6579711有效像素、11180边框像素，errors=0；三拍RGB/DE/HS/VS对齐，框外透传、框内四类均有覆盖，16次复位检查。
- -Testcase display -Negative：故意破坏4拍RGB，errors=4并退出1，属于预期成功检出，不是正常用例失败。
- 所有vlog均0错误0警告。保留原VTC/mixer的18次读使能差异；测试未模拟DDR、MIPI、PLL或HDMI PHY。
- TD build.ps1当前已完成综合并进入phy_1；最终时序/镜像尚未验收。

## 最终构建与交付（2026-10-03）

- build.ps1：TD6.2.1 syn_1/phy_1均退出0，最终Setup/Hold WNS=1.091/0.020ns，TNS/FEP=0，STA覆盖95.44%。新旧WARNING文本集合比对没有新增，继承时钟关键警告未解决。
- 候选sc520_color_mask.bit，1789539字节，SHA256=8685C3A722C50994FAE584A811CEF4955D85A52F2C08753583430FB0F6EB26B0。
- package.ps1核验原227输入未变，新工程仅4个导入文件改变，2个新增RTL；四项仿真与229项构建输入绑定。旧回退bit哈希不变。
- 首次打包因node子进程PATH不含git中止；修正脚本定位捆绑Git后重试通过。未修改HDL或重做构建。
- 主库仍21项原有状态，旧工程和旧bit哈希不变，无新增提交。新增上板指南、运行报告和哈希清单，等用户用PROGRAM_SRAM验证颜色与长测；不自动下载。
- 最后核对16个文档链接、脚本解析和15个自编文件尾空白均通过。Worktree额外出现%SystemDrive%下4个Windows缓存db（12:52），生成进程未确认，仅observed补登记，不删不动不纳入候选。

## 证据路径

evidence/sc520-color-mask；用户步骤见 E:/juan/FPGA/learning/sc520-color-mask/README.md。

## 阻塞与风险

颜色阈值是初值，真实光照和白平衡需要用户验证。原工程时钟警告和约束覆盖不足仍存在。旧红框已由用户报告正常及720p，60Hz/摄像头fps/30分钟长测未证实。

## 待决策事项

不改变共享接口。正式合并、稳定版本、SC520总状态由主对话审核。

## 建议总文档更新

仅建议审核本任务证据后更新开发进度，不标成已上板。

## 下一分支交接

完成软件验证后交给用户SRAM下载；不自动操作下载器或Flash。

## 用户上板反馈补充（2026-10-03）

用户报告“两版都没有问题”；本版：第一版红框内不是目标颜色全黑，有目标颜色出现正常显示。下载截图显示sc520_color_mask.bit、PH1P35MDG324、PROGRAM_SRAM/5MHz及成功提示，附件已归档到evidence/sc520-color-mask/hardware/20261003-user-feedback。当前候选哈希与交付一致。画面功能正常为用户报告，未提供电视画面视频；拿走清框、三色逐项、空背景、30分钟长测和实测帧率仍待补证据。前文“未下载/待上板”保留为当时软件交付状态，不再代表本次用户已完成的下载；不将完整验收提前标为通过。主对话审核后再更新总状态。本轮不改HDL/bit，不提交不合并。

## 2026-10-03 用户授权的开发检查点提交

- 用户现已明确授权整理、提交并推送，替代本日志此前只针对当轮的“不提交、不推送”执行边界；不包含main合并或新的硬件操作授权。
- 本阶段自研源码、测试、原脚本及日志保留原路径；厂商/IP依赖通过校验包与增量恢复，不全量上传重复工程。候选bit与原始证据通过私有实验预发布附件保存，不标为稳定版。
- 本次没有改变原RTL、测试输入或候选镜像。新的恢复/验证入口及完整边界见 evidence/sc520-fixed-roi/checkpoint/README.md；实际新提交号、干净检出恢复与复验结果以后续共享登记及PR为准，不伪造历史验收。
