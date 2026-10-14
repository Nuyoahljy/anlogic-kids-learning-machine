# SC520 新候选物理审计准备

负责人：`01a13561-2629-7fa2-86a0-4087ad34cc7c /root/scene_rtl`。本记录接续 imaging_audit 的 `20261014-112910-sc520-physical-audit-prepare-eeb091` 批次，不修改旧 0109 审计器、111 原始报告、数据库或 bit。

## 111 的实际结论

111 仍不具备候选资格：原路由报告 SWNS=-3.084ns、STNS=-399.690ns、HWNS=0.020ns、HTNS=0。`physical-readback-111-v2.json` 记录新审计器仍在原 STA 检查处明确拒绝，不会因为 ROM 和 CDC 通过而接受该镜像。

此前“CDC `-from/-to` 为空，可能漏报”的判断已排除。TD 对集合参数的命令回显不包含可打印内容；setup 的 2ns 例外路径在原报告后面的分组，不能只读首页。对 111 原报告完整解析，现有报告无需修改或重导：

| 通道 | 保留逻辑位 | 跨域 setup+hold 路径 | 同域打包附带路径 | 总路径 | 最大数据传播 |
|---|---:|---:|---:|---:|---:|
| business | 80 | 160 | 46 | 206 | 1.091ns |
| diagnostic | 175 | 350 | 465 | 815 | 1.613ns |
| i2c | 28 | 56 | 56 | 112 | 1.133ns |

所有保留跨域位均逐项核对物理 SourceQ、DestinationQ、数据输入端点、逻辑位号和时钟对，setup/hold 的同位端点必须相同，传播小于外部 10ns 上界。没有丢弃无法解释的跨域路径。同域打包附带路径保留在报告及 ExcludedPathDetails 中，不计作跨域 payload。

17 条同步链各有 setup 与 hold，setup 的 2ns 约束实际生效且正余量，最小 hold slack 为 0.055ns。原时钟周期和重建分析时钟均单独核对。不将异步相位 slack 称作同步建立/保持资格或 MTBF 证明。

## 审计器补强

`audit-scene-build.py` 除全部 ROM INIT/INITP、逻辑字、地址和输出映射外，增加路由后参数及连接检查：CS 极性、读模式、写禁止、使能、复位等必须与已证明的综合网表相同；仅允许未连接引脚标签改名。路由插入的 SCLK 和固定 input0 的 GCLK 必须逐级追回原综合时钟，未知配置或环路直接拒绝。

该 GCLK/SCLK 配置用未改动的 TD 6.2.1 原厂仿真模型实际验证，512 检查、0 错，输入时钟的四种电平组合均覆盖。3 条仿真警告来自与实际网表一致的未连接 SCLK `ce/dlytrim`，原日志保留。它证明配置功能，不代替物理时钟时序。

资源解析同时接受综合报告的 `#slice*` 与路由报告的 `#slice`，要求物理 slice 容量存在；超限不得因星号被跳过。`candidate-guard-tests-v1.json` 的 44 个检查通过，包括真实 29 个 ROM 控制正例、CS/地址/输出/时钟/寄存模式/写禁止等破坏负例、时钟环路、110 的 slice 和 DSP 超限，以及 111 路由资源表。原文件只读，故障注入仅修改内存中的副本。

`derive_scene_rom_bindings_v2.py` 为新候选封存实际使用的绑定程序和 decoder 字节，避免后续维护 live 脚本使旧证明失去可复现依据。原 v1 生成器和 111-v1 证明保持原样。v2 已在 111 实际复核 29 ROM、25 bank、102400×5 位、3200 条 CS 真值、40 条选择寄存器真值和 2000 条输出 mux 真值，输出为 `rom-bindings-111-v2.json` 与 `rom-binding-proof-111-v2.json`。

## 112 完成后

使用 bundled Python，先执行 `derive_scene_rom_bindings_v2.py <112构建绝对路径> --tag 112-v1`，再执行 `audit-scene-candidate.py <112构建绝对路径> --bindings <rom-bindings-112-v1.json绝对路径> --output <新的候选审计JSON绝对路径>`。

生成器若因新综合网表映射变化拒绝，须按该版物理节点重新推导；不能沿用 111 的 SHA 或映射。全候选要求两构建阶段成功、当前输入及快照一致、原 STA 零违规、资源不过限、四键 IO、29 ROM 绑定和 17 链及全部活动 mailbox 位通过。`--rom-only`、`--cdc-only`、`--historical` 均不授予新候选资格。所有检查与实物/上板验收分开。
