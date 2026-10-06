# SC520 问答与HDMI视频集成

- 任务 ID：sc520-quiz-video
- 状态：等待主对话审核
- 负责人：对话01a11124-e100-75e2-9e85-9f9686e23c73 /root；子代理audio、control_tests、preview_keys
- 分支：task/sc520-fixed-roi（独立任务子目录）
- 基础提交：f609426044982c986b54e999866be9f4c1af2682
- 开始时间：2026-10-06，Asia/Shanghai
- 结束时间：2026-10-07，Asia/Shanghai；构建/仿真于10月6日完成，交接整理跨至10月7日

## 目标与验收条件

用户授权继续“问答控制+摄像识别+HDMI显示集成”。独立复制学习候选，保持旧三bit、识别源码与控制候选不变；新工程增加题目、反馈、分数、结束页与明确的来源/模拟标识，进行真实RGB至检测/计分/像素输出仿真和TD6.2.1构建。音频/按键保持模拟，无新增GPIO、UART、购买、下载、Flash或自动提交/推送/合并。

## 已读文档

根AGENTS/README/FILE_INDEX与20261006-205906交接、手机图片初测/音频等待记录；本Worktree AGENTS、PROJECT_MEMORY、PLAN、TASKS、DECISIONS、产品规格、接口契约及sc520-quiz-control、sc520-learning-ui-audio日志/局部接口。总记忆/TASKS尚有旧状态，实际进展以最新已登记证据说明，不改主对话文件。

## 修改文件

fpga/custom_project/sc520-quiz-video、fpga/scripts/sc520-quiz-video、fpga/sim/sc520-quiz-video、evidence/sc520-quiz-video、本日志及根learning/sc520-quiz-video。

## 验证命令与结果

prepare已复制249份旧工程输入和2份问答RTL，旧输出缓存/bit未复制；883项保护hash已建立。读取实际PLL C4=75MHz并沿用原PLL字节，毫秒时基按75000拍生成。新OSD/包装模块已创建，仿真/TD尚待执行。

## 局部集成决定

所有新增检测/控制/音频/显示逻辑同一HDMI像素时钟，无新CDC总线。复位异步置位后两拍同步释放；检测结果关联已完成帧来源，源切换重置检测稳定器并撤销放入资格，不清已有分数。OSD在帧首整体快照，避免一帧中途变字。输入模拟test=1不得计分。新硬件候选仅模拟启动两次mode(1s探索/2s问答)，其后真实摄像输入答题；没有实体键映射，屏幕明确“按键模拟/音频模拟”。旧内置demo_pattern不进入新wrapper。此自动启动用于候选实验，非最终产品启动行为。

## 证据路径

evidence/sc520-quiz-video；origin.json逐文件保存复制来源，protected-before.json保存旧候选和输入，project-manifests.json核对引用均落在独立新工程。

## 阻塞与风险

真实音频手册预计10月8日到达，未购买且不固定DFR0299；本任务不等手册。存在证据仍依赖颜色候选/稳定框，实物准确率待验证；禁止凭手机图片推测改阈值。新顶层与局部接口仍须审核，尚未宣称TD或上板通过。

## 待决策事项

未来正式启动模式、物理按钮、检测帧域/存在证据、真实播放器适配。当前布局保留中心ROI，顶部/底部各三行中文；字形为本机SimSun子集，非开源许可证明。

## 建议总文档更新

待实际验证后再建议主对话审核，不能把软件候选登记当作物理验收。

## 下一分支交接

完成像素仿真、TD资源/时序、hash绑定及工作区登记后交接独立候选；真实音频/实体键/实物准确率另行开发验收。

## 2026-10-06 首轮实现进展
已完成新工程/9份quiz RTL/3套测试及构建封装。OSD首轮8320089检查0错误；runtime首轮450065检查0错误。首轮video因旧Verilog标识符matches在-sv下报错，修复runner编译模式并增加catch，不改旧检测源码。全链路及TD待验证；新文件初始批次登记为开发中。

## 集成验证进展
video正常111帧通过，最终summary为25732524检查0错误。OSD与runtime正向通过，各自负向1处预期错误且退出1；旧失败run保留。新wrapper声明顺序已修复。TD首轮遇到旧工具路径长度限制，使用evidence/sc520-quiz-video/b短目录重试。已新增局部接口、运行报告草稿、根教学导读与真实OSD PNG预览。全幅和TD仍在执行，尚不认定上板候选通过。

## 最终交接

独立问答视频候选已完成软件验证与TD构建。过程中实测复现坏帧重新武装问题（3个根因断言、7个计分/题序级联，总10错），只在新wrapper加入原始帧协议健康门控，未修改旧检测/控制字节；同一测试复测零错。追加VS-only、半行、超长行和VS/DE重叠验证，test_done后停止检查，最终打印与机器摘要一致。

最终ModelSim八项：runtime450065/0、OSD8320089/0、video28339538/0、full82601565/0；正常合计119711257次逐周期/逐像素检查。各负向分别450065/1、8320079/1、28339539/1、82601561/1，均预期退出1；全部输入变化0。video135帧（含坏帧）、九类覆盖；full32帧/1280x720有效区，缩短消隐、加速时基，不是完整MIPI/DDR/HDMI PHY仿真。最终运行ID见evidence/sc520-quiz-video/run-report.md，旧失败与中间结果全部保留。

最终TD为evidence/sc520-quiz-video/b/8f1b2f6f，TD6.2.1 Engineer6.2.168.116，两阶段退出0/fresh markers/ChangedInputs=[]，25归档及883保护hash通过。Setup0.132ns/Hold0.020ns/TNS0，STA覆盖96.38%；LUT12872、寄存器14415、ERAM39、DSP16。built.bit SHA256=945E6D5FB6FCA2FF252953AF1B989155D2C28BA2A06E663C67F96A08B1AD2334。旧中间构建b/b7784ad3不作为候选；最初路径过长失败保留。综合/物理警告规范化后与旧学习候选一致，无新quiz告警；未把继承时钟/未覆盖路径宣称已审核。

实际11张OSD条带及最终5张全幅PNG由PPM无损转换；协作代理逐张检查，root另实看正确与完成全幅，文字/ROI正常，完成图青框有旧框释放延迟如实保留。来源、转换hash与视觉说明见preview各run目录。

交付验证命令：python fpga/scripts/sc520-quiz-video/verify-evidence.py；python fpga/scripts/sc520-quiz-video/verify-build.py --build-directory evidence/sc520-quiz-video/b/8f1b2f6f。verification-manifest绑定最终8run与当前任务文档/脚本，delivery-manifest汇总最终构建、预览和交接哈希。根教学入口E:/juan/FPGA/learning/sc520-quiz-video/README.md。共享workspace-records最终批次与FILE_INDEX由统一脚本生成并Check后交接，不修改主对话总文档。

状态为等待主对话审核，无新Git提交/推送/合并，HEAD仍f609426044982c986b54e999866be9f4c1af2682。建议主对话审核局部来源/健康/存在语义与两次模拟启动控制，再安排实物上板验证。默认约1秒探索、2秒问答；只有模拟按键和无声播放器，没有新增GPIO/UART/下载/Flash。真实播放器未购买，等手册确认再接入；卡片识别、实体键、实物准确率及长期稳定性均不计入本轮通过。
