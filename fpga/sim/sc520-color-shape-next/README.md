# pixel311 颜色投票观察器

这是 `sc520-color-shape-next` 的任务私有实验模块。它只接收一笔已经裁出的 glyph/sample 事务，统计红、黄、蓝票数，不连接当前生产顶层，也不连接 shape/category、题库、显示、音频或媒体。

固定颜色分类规则：

```text
hi = max(R,G,B), lo = min(R,G,B)
hi >= 32 且 hi - lo >= 24 才进入颜色判定
红色：R > 2G 且 R > 2B
黄色：min(R,G) >= 2B 且 max(R,G) <= 2*min(R,G)
蓝色：B > 2R 且 B > 2G
否则：未知
```

颜色规则按红、黄、蓝互斥顺序实现；未知是健康事务结果的一种，`out_event=1` 但 `out_color_valid=0`、`out_color=0`。坏事务使用 `out_revoke=1`，不产生 `out_event`。

输入事务协议：

| 信号 | 约定 |
|---|---|
| `in_start` | 空闲时锁存 `frame_id/source/expected_samples`；`expected_samples` 必须为 1 至 7200。活动事务再次 start 会撤销旧事务，当前拍不接收新事务。 |
| `in_valid` | 每拍最多一个样本。`in_index` 必须从 0 连续递增到锁存的 `expected_samples-1`；RGB 和 glyph 必须同拍有效。每个 valid 核对锁存的完整 32 位 frame_id 和 1 位 source。 |
| `in_end` | 结束事务。可以与最后一个 `in_valid` 同拍，也可以在最后一个样本之后单独出现。每个 end 同样核对锁存的完整 frame_id/source；`in_good` 只在此拍消费。 |
| `flush` | 同步高优先级清除活动事务和已发布颜色资格；若有待处理/已发布颜色，发出一次 `out_revoke`。 |
| `rst_n` | 异步低有效复位，清除活动、计数和输出。 |

`expected_samples` 包含所有样本，包括 `glyph=0` 的样本；`out_sample_count` 是接收样本总数，`out_glyph_count` 仅统计 glyph 样本。未知颜色 glyph 仍进入分母。无 `in_end` 不会产生结果，直到 flush 或下一次 start 撤销。

`in_expected_samples` 仅在 start 锁存，此后的总线无需保持；测试台在空闲拍把它改为 0，检查事务仍按起始值完成。帧号和来源在每个 valid/end 拍都必须与起始身份一致。

支持三种同拍边界：`start+valid`、`valid+end` 以及 `expected_samples=1` 时的 `start+valid+end`。孤立 valid/end、空事务 end、身份或 source 改变、索引跳变、超出 7200、坏 `in_good` 和活动重启均 fail-closed。

空闲时的新 `in_start` 会清除上一笔已发布 payload 的颜色资格，作为新事务的 supersede；这不是错误撤销，因此不会额外产生 `out_revoke`。错误撤销只对应活动事务或已发布结果被 `flush`、坏帧或协议错误清除。

健康事务结束后，唯一颜色 `w` 必须满足：

```text
glyph_count > 0
3*w >= 2*glyph_count
w >= 2*each_other_color_count
```

不满足时仍发健康 `out_event`，但颜色为未知。模块不执行跨帧过滤；统一过滤必须在后级、且只能使用这次完整事务结果。

## 测试范围

runner 默认使用当前固定模型输出目录：

```text
evidence/sc520-color-shape-next/model-v1-current-20261029-1118/
```

它先核对 `model.json` 的 Tool 路径、SHA-256 和 Bytes 与当前 `evaluate.py` 一致，并要求模型报告和 `vectors.json` 的两组向量完整一致。独立算术检查通过后，在本次新目录的 `input/model_vectors.svh` 生成测试调用，测试台实际运行全部 16 个 canonical 和 12 个 vote 向量。原 `model-v1` 报告属于旧工具版本，不能替代当前默认报告；也可用 `--vectors` 和 `--model-report` 显式指定相互匹配的报告。

另有四个固定阈值样例：`(31,0,0)->0`、`(32,0,0)->1`、`(32,9,9)->0`、`(32,8,8)->1`，分别检查亮度 31/32 与色差 23/24。它们单独计为 supplemental，不混入 16 个模型 canonical 的数量；这些样例不代表全部 RGB 空间。

协议用例检查三个同拍边界、7200 个样本计数、未知 glyph 分母、非 glyph 排除、真正的零 glyph、无 end 不发布、start 替换旧资格、孤立 valid/end、空或不完整 end、错误首索引/中间索引、valid 与单独 end 的错误 frame/source、expected=0/7201、坏 in_good、样本溢出、活动重启、待处理和已发布状态的 flush、空闲 flush、异步复位和单周期事件。分类向量 `(100,50,0)` 的正确结果是黄色 2。

## 准备与执行

默认只创建新隔离目录并冻结 DUT、测试台、runner、模型源码、模型报告、向量与命令，不启动 ModelSim：

```powershell
python -I -B E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-color-shape-next/fpga/sim/sc520-color-shape-next/run-color-vote.py --output E:/juan/FPGA/learning/sc520-color-shape-next/color-vote-v2-prepare
```

已存在的目录会被拒绝，不能重用失败目录。原生执行由 Root 审阅后显式传入 `--execute --allow-native`。以下两个命令分别使用全新目录：

```powershell
python -I -B E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-color-shape-next/fpga/sim/sc520-color-shape-next/run-color-vote.py --output E:/juan/FPGA/learning/sc520-color-shape-next/color-vote-v2-normal --execute --allow-native
python -I -B E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-color-shape-next/fpga/sim/sc520-color-shape-next/run-color-vote.py --output E:/juan/FPGA/learning/sc520-color-shape-next/color-vote-v2-checker-negative --execute --allow-native --inject-checker-failure
```

注错仅向测试台提供 `INJECT_CHECKER_FAILURE` 定义，让第一个红色向量故意期待蓝色；DUT 副本与正常测试字节相同。负向运行必须出现该 FAIL、非零 RESULT errors、`CheckerFailureObserved=true`、`Accepted=false`，且 runner 返回非零。它用于证明检查器会拒收错误，不能当作 DUT 失败或通过的证据。

正常等待上限为 180 秒；超时且本次根进程仍存活时，仅按本次 Popen 所拥有的精确 PID 使用 `taskkill /PID ... /T /F` 尝试清理其进程树，不按名称结束其他进程。清理自身另有有界等待，真实动作和结果留在 manifest；不重试仿真。超时分支尚未实测，根进程先退出而子进程继续持有管道的孤儿场景没有通用捕获，不能声称所有后代均已清理。

`run-manifest.json` 记录全部原输入与冻结副本、生成 include/命令、Python 和实际 ModelSim 工具的 SHA-256/Bytes 及前后保护检查。`result/acceptance.json` 保留原始 `NativeExitCode`、独立 `ReportSuccess`、最终 `Accepted` 和 `WrapperExitCode`，不会把超时或报告错误伪装成原生退出码。

通过要求原生退出为 0、保护对象不变、stdout 与 transcript 各恰有一条相同的 `RESULT errors=0` 和 `PASS color vote`、向量数量为 16/12/4，且所有日志中没有 FAIL、Fatal、WATCHDOG、工具 Error 或非零 Errors。任一条件缺失，runner 均返回非零；ModelSim 10.7 即使 `$fatal` 后返回 0，也不能绕过报告检查。

2026-10-29，Root 已实际执行 `color-vote-v2-normal-20261029-1132` 与 `color-vote-v2-negative-20261029-1132`。正常编译0错误/0警告，`errors=0 checks=403 events=41 revokes=19 canonical=16 votes=12 supplemental=4`，native/wrapper均0且Accepted=true。注错为`errors=1 checks=404`，native=0而wrapper=1、Accepted=false、CheckerFailureObserved=true；两轮全部保护对象未变。独立只读终审重核各20项绑定和两轮相同的7个输入文件通过。旧44-check运行不追认为新增覆盖。

本实验未运行 TD、route、bitgen、下载或 Flash，独立颜色统计不代表完整九色识别、五卡回退、资源时序或硬件通过。
