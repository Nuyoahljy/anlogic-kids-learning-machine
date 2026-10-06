# SC520 问答控制软件验证报告

日期：2026-10-06，Asia/Shanghai。状态：RTL实现、实际仿真及显示预览完成，等待主对话审核。分支 `task/sc520-fixed-roi`，基础HEAD `f609426044982c986b54e999866be9f4c1af2682`；无新提交、推送、合并或下载。

## 已完成

独立实现待机/探索/问答、1..9九类预设10题、0..10计分、错答重试及揭示答案、重播、跳题、清分退出和一轮结束。独立按键模块包含两级同步与20ms消抖。音频抽象使用保序FIFO、tag关联、明确拒绝有限重试、取消确认和三类超时；未使用未知UART协议或GPIO。

每次放入只产生一次答案。新题与重试均重新要求可信移走；未知、抖动、连续换色和类别变化不会解除已消费的放入资格。内置测试来源可以显示，但禁止计分；切回摄像来源需重新确认空场。参数和精确优先级见 [局部接口](local-interface.md)。

## 最终实际仿真

工具：`D:/modeltech64_10.7/win64/vsim.exe`，ModelSim SE-64 10.7。每次运行独立目录，编译保存的输入快照；正常和负向均有0编译错误/告警，工具退出码由test.do读取test_done/errors决定。负向的退出1为预期，不能当成正常通过。

| 测试 | 正常检查数 / 错误 | 负向检查数 / 错误 | 主要证据 |
|---|---:|---:|---|
| control | 6007 / 0 | 6008 / 1 | 15场景、826周期、42答案事件、九类mask511；完整全对/全错/全跳/混合轮次为10/0/0/5分 |
| audio | 228 / 0 | 228 / 1 | 19场景；FIFO顺序、九编号、ACK、拒绝、ready/busy、错tag、精确超时、取消、溢出、复位 |
| keys | 1000022 / 0 | 1000023 / 1 | 小参数3次按下；默认50MHz/1000000拍20ms确认一次；抖动、长按、释放及复位 |
| system | 3405 / 0 | 3405 / 1 | 9场景、568周期、13接受事务、35答案事件；实际控制与FIFO串接 |

正常共 1,009,662 次检查，0错误；四组负向分别准确发现1错误并退出1。检查数包含逐拍不变量，不能当成百万个独立场景或硬件准确率。

集成验证证明：提前作答时题目先完成再播放反馈；ACK、busy下降和错tag不能充当曲终；反馈已播完仍须最小显示时间；重播和错误提示保序；skip清除旧待播并等待stop确认后发新题；清分/连续mode在取消期间只保留最终上下文。永久busy、ready恒低、持续ACK而无曲终/停止响应三类故障均实际触发fault，随后各完成一轮10题。reset共同复位后可恢复声音抽象。

专用audio负向在普通FIFO检查器前force错误req_kind；system负向同样破坏请求类型，经公共事务检查器报错。control/keys负向使用故意错误期望，验证断言和退出码传播。前两者提供真实输出损坏对照，不仅是打印FAIL。

## 最终证据位置与绑定

[verification-manifest.json](verification-manifest.json) 绑定8份最终运行manifest、输入快照、当前源码与前后SHA256、summary、transcript、CSV、WLF，以及交付脚本和预览hash。运行 `verify-evidence.py` 实际复核8项正常/负向资格及857份保护文件；任何当前输入变化、结果hash不符、非预期退出码或缺少完成标记都会拒绝通过。

最终运行位于本目录 `runs/`：

- control：`control-normal-20261006-203133-a469be98` / `control-negative-20261006-203133-bdf64c04`
- audio：`audio-normal-20261006-203008-6ddcc58e` / `audio-negative-20261006-203009-55e992f0`
- keys：`keys-normal-20261006-202458-710ac7c7` / `keys-negative-20261006-203009-eead3eeb`
- system：`system-normal-20261006-203403-8463f7da` / `system-negative-20261006-203403-f96a1471`

每个目录含inputs、run-manifest.json、summary.json、transcript.log、wave.wlf和ModelSim工作库；control/system另有trace.csv。WLF已生成并绑定hash，本次没有离线重开波形验证；功能结论来自真实仿真断言和CSV。

## 复现

在 `E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-fixed-roi` 执行：

```powershell
pwsh -File fpga/scripts/sc520-quiz-control/simulate.ps1 -Testcase control
pwsh -File fpga/scripts/sc520-quiz-control/simulate.ps1 -Testcase control -Negative
pwsh -File fpga/scripts/sc520-quiz-control/simulate.ps1 -Testcase audio
pwsh -File fpga/scripts/sc520-quiz-control/simulate.ps1 -Testcase audio -Negative
pwsh -File fpga/scripts/sc520-quiz-control/simulate.ps1 -Testcase keys
pwsh -File fpga/scripts/sc520-quiz-control/simulate.ps1 -Testcase keys -Negative
pwsh -File fpga/scripts/sc520-quiz-control/simulate.ps1 -Testcase system
pwsh -File fpga/scripts/sc520-quiz-control/simulate.ps1 -Testcase system -Negative
python fpga/scripts/sc520-quiz-control/verify-evidence.py
```

正常退出0、负向退出1；包装器不能忽略其他非零返回。可用 `-Simulator` 指定另一已安装ModelSim。默认不修改旧结果；新运行自动生成独立目录。`verify-evidence.py --write` 才更新交付manifest。仿真参数缩短为FB4tick、audio WAIT/PLAY/STOP4/6/3、system8/12/6；默认20ms按键则有专门默认实例实际运行，其他默认时长不是本轮实测音频时长。

```powershell
python fpga/scripts/sc520-quiz-control/render-preview.py --trace evidence/sc520-quiz-control/runs/control-normal-20261006-203133-a469be98/trace.csv --output evidence/sc520-quiz-control/display-preview.html
python fpga/scripts/sc520-quiz-control/render-preview.py --trace evidence/sc520-quiz-control/runs/system-normal-20261006-203403-8463f7da/trace.csv --output evidence/sc520-quiz-control/system-preview.html
```

重跑后用新目录替换trace路径。每次新结果仍须更新任务日志、新增共享JSON、运行索引及-Check，不由这些仿真脚本冒充自动登记。

## 显示检查

[控制预览](display-preview.html) 来自819行真实CSV/42答案事件，CSV SHA256 `23F105B4BB7CCD64EF5EB6914C6086AEFF07379F234D9C7857F557029073F93D`。

[串接故障预览](system-preview.html) 来自547行CSV/35答案事件，SHA256 `17D806402ABE8667F88590EC0D1E9665AB5741F2A8AC5AE731097818C73B6369`。页面可离线打开和选择时间点，不会生成新的仿真结果。

实际在Codex浏览器核查正确加1、测试源禁止计分、重试、揭示正确答案、10/10结束和故障警示；[UI核查记录](ui-checks.json)保留实际文本。一次预期文字写成“不参与计分”而页面写“禁止正式计分”，原断言失败保留，回读后更正期望并通过，未为迎合检查改页面。页面控制台未见error/warn。截图 [完整浏览器页面](display-preview-full.jpg) 和 [问答区域截图](display-preview.jpg) 来自真实浏览器渲染，后者仅裁去页面下方回放控件，未改内容。题目、反馈、分数和模拟标识完整可读。

## 发现与修复

首轮control为5903检查0错，但独立测试同时补强导致输入前后hash变化，运行脚本按设计拒绝资格化；旧目录保留。冻结后重新跑当前输入。代码审阅发现探索模式新样本与replay同拍会取旧display_item；修复为当前有效样本优先、未知样本清重播、首次自动事件与replay合并且消耗资格，新增定向用例已包含在6007检查中。

证据汇总脚本首次只识别FAIL而音频实际使用CHECK_FAIL，误拒绝音频负向；修复仅支持两种真实失败标记，仍核对非零errors、退出码及所有hash，最终8项通过。不修改测试日志或降低功能断言。

## 保全与未验收事项

857项保护hash零差异，覆盖旧三版候选、六工程的HDL/约束/清单/字库输入、既有.gitignore/.gitattributes、共享技术文件和准备资料。学习候选保持 `F2AF49F3185330A1416CD837D7086A0009EB9CC2321840A55F5D3C45CDB47BC0`。没有覆盖旧任务日志、识别阈值或准备对话目录。已有ignore规则会隐藏custom_project与evidence；本任务源码已逐文件登记，未来提交时须主对话按精确路径审核加入，不擅改他人的ignore。

本轮没有TD综合、布局布线、bit、GPIO、真实声音、实物识别或长测。所有摄像/按键/音频输入均为测试台模拟；20ms数字仿真不能证明物理按键抗干扰。旧三版只有用户手机图片初测报告，不当作实物基线。

未来播放器通过req/ready、busy、tag响应和stop确认适配，不绑定候选DFR0299。手册到达后需核实曲终、拒绝、取消、电气与素材寻址，再审核共享接口、毫秒时基、检测存在语义/CDC、按钮GPIO和独立视频集成。主对话可据本报告审核软件行为；硬件状态仍须另行验收。
