# T-018 I2C SCL 协议与时序只读审计

审计日期：2026-10-14，Asia/Shanghai。负责人：接续板级聊天 `01a13561-2629-7fa2-86a0-4087ad34cc7c` 的 `/root/scl_protocol_audit`。基线：`task/sc520-card-recognition`，`f81483c740d40e46262648d132bd07e6a5079a2f`，D0112 / 6a50b112。

本报告只读核查 RTL、工程引用、原始时序报告及既有仿真记录。没有新跑 RTL/TD、改 RTL/SDC、操作硬件或真实 COM，没有证明实物总线电气时序。独立审计文件由本代理登记；分支日志由拥有该日志的 root 汇总，本代理不并发编辑。

## 结论与方案选择

T-018 的第一选择是保留当前派生 SCL，添加精确的相关生成时钟并完成双边沿、父子域、复位及 I/O 报告。它最小化已经验证的总线与重试行为变化。当前有明确的 238 分频、50% 占空和相位公式；没有源码依据把 SCL 当作异步时钟，也没有证据证明其频率过低所以可以不约束。

父时钟使能是有价值的后续结构，但机械地将 `always @(posedge/negedge scl_clk)` 换成 `always @(posedge I_clk) if (ce)` 并不逐拍等价。旧设计在父时钟 NBA 更新 `scl_clk` 后才运行子域过程，能读到同一父沿刚更新的 request/reset；CE 过程读的是旧值，请求与虚拟正沿相撞时可能晚一个 SCL 周期。若准确约束后仍有不可接受的时钟路由、hold 或 recovery/removal 问题，再用独立等价矩阵选择 CE，并把允许的请求延迟、复位相位变化写成明确合同。CE 也不能代替外部 SDA 延迟或上拉边沿的验证。

两方案都需要新物理构建，不得把本报告登记等同于 FullSystemTimingSignoff。

## 活动入口与分频实证

活动 `fpga/custom_project/sc520-pixel14/td_project/camera_to_dsi_display.al` 第 192 行只引用前置 `sc520-fixed-roi/fpga/custom_project/sc520-board-keys/user_source/hdl_source/uics500_cfg/uii2c.v`；第 288 行配置模块只引用本任务 `overlay/uicfgcs520.v`。并非前置同名配置模块正在活动。`prepare-pixel14.py` 当前只替换配置模块，没有替换 uii2c；若后续改位级驱动，应在本任务 overlay 建唯一副本，同时修改 prepare 的映射和测试 runner 的来源，不能修改前置工作树。

活动顶层 532-542 行由同一 PLL 的 `clk1_out` 驱动 `S_24m_clk`，561-564 行覆盖参数为 `23809524 / 100000 - 1`，整数结果是 **237**，不是配置模块默认值 239。6a50b112 原 `final_timing.rpt` 的 `pll_clk_24m` 为 42.000 ns，rise 0、fall 21 ns；下列数值按此约束名义周期计算，未包含晶振误差、抖动、管脚/电平转换/布线延迟。

| 项目 | 源码公式/值 | 名义结果 |
|---|---|---|
| 半周期分频 | `SCL_DIV = CLK_DIV/2 = 118`，计数包含 0 至 118 | 119 个父周期 |
| 内部完整周期 | `2*(SCL_DIV+1)` | 238 拍 = 9996 ns，约 100040.016 Hz |
| 外部更新比较值 | `OFFSET = 118 - 118/4 = 89` | 内部边沿之后第 90 个父沿更新外部 SCL |
| 外部 SCL 正常高/低宽 | 119 拍 | 各 4998 ns |
| SDA 发送变化 | 内部 SCL 正沿 | 上次外部下降之后 29 拍 = 1218 ns |
| 数据到外部上升建立窗口 | 90 拍 | 3780 ns |
| SDA/ACK 采样 | 内部 SCL 负沿 | 外部上升之后 29 拍 = 1218 ns |
| 从上一外部下降到采样 | 148 拍 | 6216 ns |
| 从采样到下一外部下降 | 90 拍 | 3780 ns |

`OFFSET` 不是时间本身。由于比较采用更新前的 `clkdiv`，实际延迟是 `(OFFSET+1)*Tparent`。若用默认 239 重新计算则为 240 拍 / 10080 ns，不能拿这个数字约束当前 237 候选。

状态强制 SCL 高时外部不再是持续方波。内部 `scl_clk` 一直运行，而 `scl_r` 在 IDLE、STOP1、STOP2 为 1；外部 `O_iic_scl` 只在 offset 比较点采样它。名义 START hold 为 209 拍 / 8778 ns，repeated-START setup 与 STOP setup 为 148 拍 / 6216 ns；这些是由状态机推导，尚未对全状态/延迟模型新跑断言。

## 跨域协议

| 信号路径 | 真实使用 | 必须核查 |
|---|---|---|
| 父域 `iic_req` 到内部 SCL 正沿 | ST_REQUEST 拉高，直到 `busy_sync` 为 1 才撤销；子状态机 IDLE 和 busy 都直接读取，未另做 request 同步 | related-clock setup/hold、请求与子正沿重合；不能整域 false-path |
| 父域 `wr_data/wr_cnt/rd_cnt/iic_mode` 到 SCL 正沿 | ST_SETUP 设置，下一父沿才发请求；到 ST_FINISH 后才更改。uii2c 在 START/W_ACK 逐字节再次读取原始总线 | 保持数据协议与每个实际保留位/控制端点；不能只验证地址第一个字节 |
| SCL 正沿 `O_iic_busy` 到父域 | `busy_meta -> busy_sync` 两级，配置机先等 busy=1 再等 busy=0 | SCL 源 FF 到 meta 的相关时序，以及 meta 到 sync 的原 2 ns setup 与 hold；原报告只证明后段 |
| SCL 负沿 `O_iic_bus_error` 到父域 | 两级 error 同步；父域 transaction_error 保留本次错误，FINISH 还检查 live error_sync | 负沿到父沿的相位、最短错误脉宽及完成边界；原设计错误通常保持一个完整 SCL 周期 |
| SCL 负沿 `O_rd_data` 到父域 `O_sensor_id` | 不逐位同步。R_ACK 负沿锁存读字节；busy 结束、两级同步、ST_SETTLE 三拍后才在 FINISH 读取 | 实际 data path 与保持时间；正常单字节读中读数据写入到 busy 下降已有约 3.5 个内部周期，随后还有父域等待 |
| SCL 正沿状态/计数与 SCL 负沿采样/error | 正负沿之间直接使用状态、计数和 rd_req；busy 正沿也读取 error | 子域两方向 half-cycle setup/hold；不能只生成正沿域报告 |
| SCL 状态/时钟到父域外部 SCL 寄存器 | `scl_r` 由状态/内部 SCL 组合生成；`O_iic_scl` 在父时钟 offset 点采样 | 子域到父域路径和时钟作为数据的路径，不能漏掉 mixed-fanout 分支 |

`O_iic_bus_error` 仅在 W_ACK 且 SDA=1 时置位，正常读尾 R_ACK 的主机 NACK 没有被这段代码当作错误。外层只有整表成功才清 O_iic_error，失败可重试三次，timeout 则锁 ST_ERROR；补约束或 CE 不应改变这些语义。

既有 27 轮最终回归包含真实 237/239 divider 及 23 加速配置，有正常、NACK 恢复、永久失败、ID 拒绝、AE 快照和超时。源码中的从机只观察管脚，因此可以证明序列/重试行为。它在外部 SCL 下降沿零延迟更新 ACK/读数据，使用理想 tri1，没有 tVD、上升时间、独立 reset 相位扫描或周期/脉宽断言；不能用此前功能通过代替本次 I/O 或复位时序资格。`normal-20261013-193734-eaea5ece` 是 500 ns watchdog 探针，done=0/checks=0 是预期拒绝证据，不是正常完成轮。

## 复位边界

顶层 `S_cam_i2c_ready` 在 24 MHz 域产生，作为配置及位级驱动低有效复位的释放。PLL lock 下降异步清顶层上电计数；计数到 23810 后释放 PWDNB，到 142857 附近释放 I2C ready。主机没有直接测量 DOVDD/AVDD/DVDD 的真实电平，不能单凭计数器宣称完整物理上电时序通过。

uii2c 的 `clkdiv`、`scl_clk` 和 `O_iic_scl` 无 I_rstn 分支，依赖初始化且在复位期间继续运行；状态、busy、error 异步清零；发送/接收移位数据、bcnt、O_rd_data 并非全部复位。状态 IDLE 会释放 SDA，并使 offset 更新最终将 SCL 拉高，所以中途复位可能先见 SDA 上升而外部 SCL 稍后恢复。此行为不能擅自改成“异步复位立即令两线为高”。

因为 I2C ready 不复位分频器，其释放可能靠近内部正/负沿。需要新 STA 的 recovery/removal 加上所有 238 个父周期相位的仿真（含任意子周期内再次复位）；仅固定 12 个父周期后撤复位不足。CE 若主动重置 divider 或使外部 SCL 立即为高，属于有意语义变化，应单独列验收。

## 外部 I/O 依据与限制

本地 SC520CS-03 V1.6 第 10 页声明标准 I2C，低 SID 地址为写 0x6c / 读 0x6d；第 29 页 SCL 类型为输入，SDA 为 open-drain 输入/输出。uii2c 将 SDA 实现为拉低或高阻；SCL 为输出寄存器，不读取引脚，未支持 clock stretching、多主仲裁或 stuck-bus recovery。这里只针对当前单 SC520 从机，不能推广成通用 I2C 主机已合规。

本地第 11 页已完整抽取并渲染为 `sc520-i2c-timing-page11.png`，表 1-4：Standard-mode 最高 100 kHz，tLOW 4.7、tHIGH 4.0、tHD;STA 4.0、tSU;STA 4.7、tSU;STO 4.0、tBUF 4.7，tSU;DAT 250 ns，rise 1000 ns，fall 300 ns，tVD;DAT/ACK 3.45；Fast-mode 为 400 kHz，数据建立 100 ns，rise/fall 各 300 ns，tVD;DAT/ACK 0.9。该本地 PDF 的若干 Unit 格视觉与文本均显示 `s`，缺少微秒前缀；此处按其标准 I2C 时序表语境理解为 us，正式约束依据仍应交叉核对有效原厂版本，不能把排版问题隐藏。

237 分频约 100.040 kHz，比 Standard-mode 100 kHz 高约 0.040%，严格 Standard-mode 上限不满足。SC520 另列 Fast-mode 并不证明本板慢边沿满足 Fast-mode；不能仅拿 400 kHz 上限宣称闭合。若本任务改 239 以明确低于 100 kHz，应标明有意分频修正，与 CE 等价试验分开。对原 237 的 retained-clock 约束必须忠实描述实际 9996 ns。

I/O 约束建议采用与父时钟相关的外部 SCL 相位参考：外部下降到内部采样为 6216 ns，对 tVD;DAT/ACK max 3450 ns 有名义余量，但还要加入板级传播、输入路径、时钟偏差和适当电平边沿预算；SDA 最早变化在外部下降后，以及采样后到下一外部下降的 hold 窗口，需用 min/max 两侧证明。输出要检查 SDA 拉低与释放的实际 OE 路径及 SCL 输出路径，不要仅检查内部 `sda_o` FF。

`pin.adc` 第 5-6 行为 K3/J3、LVCMOS33、8 mA、PULLUP；传感器裸芯片 DOVDD=1.8V，模块电平转换与上拉网络必须依据实际模块电路。此报告没有重新核对转接板/模块电路、负载或现场 rise/fall，因此不能给出未经依据的绝对 pad delay 或将真实 I/O 标记通过。

## 两种路线的交付门槛

保留 SCL：

1. 对综合和物理阶段的唯一 `scl_clk` 实际源/端点建立 238 分频时钟，父时钟为 `pll_clk_24m`，确认输出周期 9996 ns、半周期 4998 ns；不要用 unconstrained root clock 或异步 clock group 丢失父子关系。
2. 验证计数器到生成时钟的映射、物理 clock loads 全部归入正确时钟；25 是现候选物理负载数，不是逻辑 FF 固定要求，优化可改变数量。
3. 每组父子和正负沿路径至少一份 max/min 代表路径，并对所有实际保留端点做覆盖审计；明确 recovery/removal 是否被报告及其端点。
4. 对外部 SCL/SDA 的 min/max 时序依据单列，外部模型以最慢合法 tVD、ACK/NACK、非零边沿、reset 相位进行相关回归。
5. 完整 TD 新快照，复核时钟利用率/告警、原 mailbox/同步器/ROM、整机正时序及源文件哈希，再由主对话审核。

父时钟 CE：

1. 位级寄存器全部在父时钟域时，仍保持 rise/fall 两个虚拟事件和 offset 独立事件；保留计数包含零、寄存输出、开漏 SDA、既有 reset/initial 行为，或明确记录变化。
2. 使用旧/新并列实例与外部从机；至少扫 238 个请求/复位相位，特意覆盖 request 与虚拟正沿、error 与 busy 完成重合；同时比较内部握手和外部完整字节，允许的整体启动延迟必须先定义。
3. 若保留 busy/error 两级返回，应确认同域后的脉冲、settle/retry/timeout语义；若移除它们，则另验配置完成与诊断时刻。
4. 新物理报告证明内部 SCL 不再作为 FF 时钟，所有新 FF 属于父域并具备 setup/hold/recovery/removal覆盖；外部 I/O 和实际电气限制仍独立存在。

## 本次实际验证

已读共享 AGENTS/README/FILE_INDEX 任务入口、最新 20261014-194926 主审及 192914/191926 D0112 记录，主库 AGENTS/PROJECT_MEMORY/活动协调表，本工作树 AGENTS/PROJECT_MEMORY/PLAN/TASKS/DECISIONS/接口/分支日志。进入时 git status 干净，HEAD 为 f81483c。

使用 PowerShell Get-Content/rg 读取实际源与报告；bundled Python `-B -X utf8` + pypdf 完整提取相关 PDF 页，pypdfium2 按 1.6 倍渲染第 11 页并通过 view_image 人工查看。审计源 SHA256、参数推导、原始路径和本次边界存于 `protocol-audit.json`。没有重新执行旧仿真、TD 或硬件测试。

外网对 NXP UM10204 的检索/打开未取得可用完整表格，未以它作为完成交叉核验的证据；当地 SC520 文件的单位排版疑点保留为后续核查项。
