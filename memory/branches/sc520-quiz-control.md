# SC520 问答计分与交互逻辑

- 任务 ID：sc520-quiz-control
- 状态：等待主对话审核
- 负责人：对话 01a11124-e100-75e2-9e85-9f9686e23c73 /root；子代理 audio、control_tests、preview_keys
- 分支：task/sc520-fixed-roi（按派发使用此 Worktree 的独立任务目录）
- 基础提交：f609426044982c986b54e999866be9f4c1af2682
- 开始时间：2026-10-06，Asia/Shanghai
- 结束时间：2026-10-06，Asia/Shanghai；软件交接完成

## 目标与验收条件

独立实现九类积木的待机、探索、10题问答、0..10计分、重试、跳题、重播和清分；明确空场景确认和测试来源隔离。实现顺序音频抽象与按键消抖，用实际仿真覆盖正常、异常、多事件同拍和负向检查器。输出实际仿真驱动的屏幕反馈预览和可复现证据。本任务无 UART、GPIO、视频工程或 bit 集成。

## 已读文档

根 AGENTS、README、FILE_INDEX 中相关最新记录；20261006-184810 手机图片反馈与 20261006-201715 问答派发记录；主仓库及本 Worktree 的 AGENTS、PROJECT_MEMORY、PLAN、TASKS、DECISIONS、产品规格、接口契约、audio-quiz 日志；旧学习候选 run-report、local-interface、candidate-manifest 和分支日志；准备目录 controls-and-acceptance、future-assets、audio-map、audio-scripts。

已有未提交内容属于旧任务（含 .gitignore/.gitattributes）；只读复用不覆盖。只找到探索事件/音频和旧按键模块，无现成问答计分 RTL。产品要求10题，第二次错误揭示答案、预设1..9再1、反馈最短1500ms为本任务可调整局部决策。DFPlayer尚未购买，旧契约UART细节不绑定未知实物。用户手机图片初测不是实物稳定性证据；不调整识别阈值。

## 修改文件

仅本任务 fpga/custom_project、fpga/sim、fpga/scripts、evidence 子目录、自身日志及根 learning/sc520-quiz-control。最终清单随登记记录和运行报告补齐。

最终3个RTL：quiz_control.v、quiz_audio_queue.v、quiz_key_debounce.v；4个TB：tb_quiz_control.sv、tb_quiz_audio_queue.sv、tb_quiz_key_debounce.sv、tb_quiz_system.sv；4个工具：simulate.ps1、test.do、render-preview.py、verify-evidence.py。证据包含运行快照/日志/WLF/CSV、protected-before.json、verification-manifest.json、run-report.md、local-interface.md、audio-notes.md、preview-notes.md、两份HTML预览、UI核查JSON及完整/裁剪JPG。根learning/sc520-quiz-control/README.md为教学入口。没有修改旧任务、共享契约或主对话技术状态。

## 验证命令与结果

开始时只读核对分支与HEAD；最终在ModelSim SE-64 10.7执行simulate.ps1的control/audio/keys/system各正负两项，正常总计1009662检查零错，四负向均1个预期错误且退出1。控制15场景6007检查、音频19场景228检查、按键1000022检查、串接9场景3405检查。全部最终Inputs前后hash相同；verify-evidence.py复核8项及857份保护hash零差异。真实执行命令、完整目录与局限见evidence/sc520-quiz-control/run-report.md。

## 证据路径

evidence/sc520-quiz-control/run-report.md 与 verification-manifest.json，最终8项run目录由后者绑定。正常control/system实际CSV生成离线交互HTML并在Codex浏览器核对题目、反馈、score、测试来源禁计分和故障状态；实际截图与ui-checks.json已保存。

## 阻塞与风险

现有检测 det_valid=0 不能证明物体移走，新局部输入须提供独立存在证据；接入时必须审核。真实模块曲终/停止/应答、物理按键和CDC待资料与上板验收。用户未授权提交/推送/合并/下载，本任务不执行仓库finish脚本或提交。

## 待决策事项

审核局部重试/题序、明确存在接口、音频FIFO/取消/故障恢复及未来适配器。kind7为本地完成事件，共享接口仍保留；replay在本地解析为名称/题目，不能直接当共享契约已经冻结。现有.gitignore第60/65行隐藏custom_project和evidence，后续需主对话按精确任务路径审核纳入Git；本轮不改他人的ignore、未提交、未运行finish-task.ps1。

## 建议总文档更新

建议主对话将本任务标为“独立RTL与模拟正常/异常验证完成，待接口审核和硬件接入”，保持真实语音、实物识别、GPIO、CDC、TD时序/资源未验收。不同于T-010整机audio-quiz完成，不回填卡片14项或真实声音通过。

## 下一分支交接

真实音频资料到达后接适配器；独立视频集成、物理按键和实物识别验收后再生成新候选。

## 首轮实现与实际仿真（2026-10-06）

已落盘核心控制、顺序音频队列、两级同步消抖及三个独立TB；运行脚本保存不可变输入快照、前后SHA256、工具退出码、summary、transcript和WLF。ModelSim SE-64 10.7 首轮：control 5903检查/0错，但TB于运行时继续补强、ChangedInputs=1，包装器拒绝其作为最终证据，保留旧快照。audio 228检查/19场景/0错；keys 1000022检查/0错，默认50MHz与1000000拍消抖实测，3次小参数按下及1次默认参数按下。没有运行TD或硬件下载。下一步冻结测试并运行最终正常/负向、串接集成和真实CSV预览。

已保存857份旧任务源码、约束、工程清单、候选bit、准备资料与共享文件的保护hash，交接前复核。此阶段局部实现及证据仍在开发中。

## 最终回归、显示与交接（2026-10-06）

审阅发现探索新sample与replay同拍取旧display_item；已修为当前sample优先，未知不重播旧项，首次探索放入+replay合为一次且消耗armed。新增定向TB并冻结后control正负均预期。串接三类故障各完整答完10题，音频不响应不阻塞控制；实际FIFO输出破坏负向经公共检查器报错。首轮输入变化、汇总脚本FAIL/CHECK_FAIL拼写差异及UI期望文字差异均保留/如实记录，未改日志伪造通过。

8项最终运行的代码/脚本、输出文件与当前输入hash已绑定；旧三bit和其他保护项857份零差异，学习bit保持F2AF49F3185330A1416CD837D7086A0009EB9CC2321840A55F5D3C45CDB47BC0。显示预览来自实际CSV，截图只裁剪未重绘；没有TD构建或新硬件候选。JSON登记分首轮开发及最终交接两批，使用主仓库统一脚本生成FILE_INDEX并-Check；不直接改索引。后续用户可按根learning导读复现。
