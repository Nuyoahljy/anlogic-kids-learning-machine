# 音频事件控制与无声模拟播放器验证

- 任务：sc520-learning-ui-audio，子代理 audio；上级对话 01a10505-771c-7690-ae31-3ed7451e4866。
- 日期：2026-10-04，Asia/Shanghai。
- 工作目录：E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-fixed-roi。
- Git：task/sc520-fixed-roi，HEAD f609426044982c986b54e999866be9f4c1af2682；未提交、未推送、未合并。
- 状态：独立 RTL 仿真完成，等待主对话审核局部事务语义。不是 DFPlayer 驱动或硬件音频验收。

## 模块与局部接口

本模块消费共享约定已有的 `audio_event[2:0]` 和 `audio_item_id[3:0]`，本轮支持事件 1（名称）、5（重播）及对象 1..9。其余事件或编号忽略，不修改共享契约。所有输入与 `clk` 同域；事件为一个时钟周期的脉冲；`tick` 是计时使能，每个为高的时钟沿计一次。

`audio_event_player.v` 输出 `cmd_valid/cmd_item/cmd_event/cmd_tag`，由 `cmd_ready` 握手；`player_busy=1` 时不发出有效命令，但计入等待超时。响应为 `rsp_valid/rsp_tag/rsp_error`。响应至少在接收命令后的下一时钟沿生效；仅 PLAYING 状态下与活动 tag 匹配的响应才有效。

| 状态 | 数值 | 行为 |
|---|---:|---|
| idle | 0 | 无活动事务；新事件或待播槽晋升为 offer |
| offer | 1 | 等待 ready 且不 busy；握手后进入 playing |
| playing | 2 | 等待匹配完成或明确拒绝响应 |
| fault | 3 | 清待播槽、停止自动命令；只有 flush 或 reset 可恢复 |

队列只有一项活动事务和一项待播内容，处理事件不会反压视频。自动名称事件与活动或待播同 item 时合并。重播允许活动同 item 再排一次；待播同 item 则合并并保留重播事件 5。不同 item 覆盖待播槽，以最后到达者为准。事件先入槽再晋升，避免待播晋升与同拍重复事件产生两个相同待播。活动完成同拍的自动同 item 事件也按重复合并。

`rsp_error=1` 的唯一语义是“适配器明确保证该事务没有开始播放”。此时最多重试 MAX_RETRIES 次，每次使用新 tag。超时无法知道是否已播放，不自动重试；错误重试耗尽也进入 fault。默认 READY_TIMEOUT_TICKS=300、PLAY_TIMEOUT_TICKS=900、MAX_RETRIES=1。计时参数小于 1 时按 1 tick 处理。握手优先于同拍等待超时；匹配响应优先于同拍播放超时。`completed_pulse/failed_pulse` 均只持续一拍。

`flush` 优先于事件、握手、响应和 tick，清活动与待播并推进 tag。本地 mock 与控制器必须同时 flush/reset。16 位 tag 不是无限历史标识；未来真实适配器必须保证旧响应不会存活到 65536 次命令/flush 的回绕，也必须在控制器 reset 时清自己的旧事务。当前两个模块遵守联合清除。

`mock_audio_player.v` 可综合，但只模拟忙状态和完成，没有 UART、物理引脚、音频样本、扬声器输出或真实声音。默认 PLAY_TICKS=120；接收命令当拍不计 tick，之后第 PLAY_TICKS 个 tick 返回成功，busy 时拒绝新握手。非法命令明确返回未执行错误。模块不包含也不推断 DFPlayer 的电平、连线、波特率、应答或 BUSY 行为。

## 实际命令与结果

工作目录为上述 Worktree：

```powershell
pwsh -File fpga/scripts/sc520-learning-ui-audio/audio-simulate.ps1
pwsh -File fpga/scripts/sc520-learning-ui-audio/audio-simulate.ps1 -Negative
```

脚本实际调用 D:/modeltech64_10.7/win64/vsim.exe，工具 transcript 确认为 ModelSim SE-64 10.7。每次在独立 `audio-runs/<run-id>/` 工作目录内生成 work 库、modelsim.ini、日志及 WLF，不共用厂商工程缓存。源码运行前后 SHA256 相同。

| 运行 | 目录 | 真实结果 |
|---|---|---|
| 首次正常 | audio-runs/audio-0-20261004-115544-958-9464 | 进程 0；124 检查，0 错误；输入未变化 |
| 增强 manifest 后正常 | audio-runs/audio-0-20261004-115625-326-32524 | 进程 0；124 检查，0 错误；295 驱动周期，28 握手，19 完成，6 故障脉冲 |
| 首次故障注入 | audio-runs/audio-1-20261004-115654-911-32004 | 进程 1；126 检查，1 个预期错误；done=1，输入未变化 |
| 默认参数补测后最终正常 | audio-runs/audio-0-20261004-115954-484-19824 | 进程 0；1456 检查，0 错误；1634 驱动周期；done=1，输入未变化 |
| 默认参数补测后最终负向 | audio-runs/audio-1-20261004-120025-070-28896 | 进程 1；1458 检查，1 个预期错误；1640 驱动周期；done=1，输入未变化 |

最终正常运行执行 27 组行为场景；日志中的第 28 个场景标题为负向入口，正常模式跳过注入。因此最终 summary 的 cases=28 不是 28 个正常功能用例。前 23 组的主控制器统计仍为 28 握手、19 完成、6 故障脉冲；默认参数实例单独断言，不混入该计数。两次最终运行的 RTL 编译和仿真工具均报告 0 Errors、0 Warnings；负向的自检错误单独由 testbench/脚本报告，不被工具语法计数覆盖。

实际覆盖：非法事件/编号、复位、成功与单周期完成、活动/待播自动去重、最新覆盖、主动重播及合并、待播晋升同拍重复、明确拒绝有限重试与新 tag、重试耗尽、ready 延迟与元数据稳定、busy 阻止握手与超时、无 tick 不计时、等待/播放超时边界、匹配响应优先级、错误 tag、flush 与旧响应、flush 同拍优先、fault 恢复、完成同拍事件、mock 两 tick 完成与联合取消、1 tick 参数边界及 0 次重试、直接 mock 非法输入与 busy 忽略新命令。

新增的 4 组使用未覆写参数的控制器及 mock，逐 tick 检查默认值：mock 在握手当拍 tick 为 1 时仍不计时，后续 1..119 tick 持续 busy，第 120 tick 才成功；ready 等待 1..299 tick 不故障，第 300 tick 进入 fault；播放 1..899 tick 不故障，第 900 tick 进入 fault；明确未执行错误首次换 tag 重试，第二次拒绝耗尽默认 MAX_RETRIES=1 并进入 fault。高速 tick 是逻辑使能测试，不冒充真实视频时间或声音时长。

故障注入把控制器状态强制为 idle，故意破坏等待超时后的 fault 转移；断言 `injected state fault must be detected` 失败。Tcl catch 与 PowerShell 将错误传播为退出码 1，没有将预期失败伪装成正常功能通过。

首轮没有发现或修复 RTL 功能错误。首次正常后先增强运行脚本，使 manifest 绑定 summary、transcript、launch 和 WLF 的绝对路径及 SHA256；随后按父对话复核补充默认参数覆盖，并以原字节 RTL 重跑正常与负向，所有历史输出保留。末次只读哈希核对命令首次因 PowerShell foreach 语句直接接管道而解析失败，没有执行或改文件；改为 Get-FileHash 列表管道后核对成功。WLF 已落盘并计算哈希，本轮未离线重开 WLF。

## 输入与输出绑定

最终正常和负向的 manifest.json 均含 SourceSHA256、InputsUnchanged、工具路径、原始 Tcl 命令、真实 ExitCode、ExpectedExitCode、SummaryPath、Summary 对象和 OutputSHA256。SourceSHA256 的相对路径以本报告的工作目录为基准。

| 源文件 | SHA256 |
|---|---|
| audio_event_player.v | FDD447F1B08C99CE0A2C26CC8E3A5C0F3594CAEFE3C956C8AB672DE2BBF6F212 |
| mock_audio_player.v | 6E1CDD67E148CBBFFC963B653EAE73F22E66DC53E0F06B15AAE89A762F8C68F4 |
| tb_audio.sv | C0DC861000F40E6374CB0A95FF7316ECAA1EFFCEA91D21725E06E084DDE2C348 |
| audio-test.do | B06E0BFF8F61A041454F929D31494A6ACE919B07441362481D891FD0B8CB0BC3 |
| audio-simulate.ps1 | 72AA9844D3D78198CFBA81CC773F8E5E3CF97CA5116B702846CB06D4FE748306 |

## 边界与交接

本子任务只写两个 audio RTL、tb_audio.sv、audio-test.do、audio-simulate.ps1、本报告与 audio-runs 输出目录，并独立登记共享根索引。父任务日志由上级对话统一更新。本次没有改共享 docs、其他任务源码、原 shape/OSD bit、.gitattributes/.gitignore 或 Git HEAD。

测试覆盖 3/4/1 的等待/播放/重试参数、1/1/0 边界控制器以及未覆写的默认 300/900/1 控制器；mock 覆盖 2、1 和默认 120 tick。独立模块默认参数已验证；父任务完整 wrapper 与 TD 构建另行记录，本报告不代替视频全帧验证。未执行门级仿真、真实串口、上板播放或完整整机测试。DFPlayer 实际型号、购买链接、对应协议和电气手册仍需用户提供，只有具备这些证据后才能设计物理适配器。

建议主对话审核这里的局部队列、明确未执行错误、超时锁定、tag 生命周期和联合 flush/reset 语义；保持共享契约不变。在局部 wrapper 中保留“模拟语音”标签，不将 mock 的完成脉冲表述为真实音频已播放。
