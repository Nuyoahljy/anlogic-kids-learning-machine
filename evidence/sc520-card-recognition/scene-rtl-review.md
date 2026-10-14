# 场景预处理 RTL 独立验证记录

- 负责人：`01a13561-2629-7fa2-86a0-4087ad34cc7c /root/scene_rtl`
- 工作树：`E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition`
- 接手基线：分支 `task/sc520-card-recognition`，HEAD `3089ae8ee0daa6ffdbb581179eb2453d6c4fef5a`；预处理器为中断遗留未提交文件，接手 SHA256 `0B6B3DCE36F689A20ED787CC1751721D18CC73F4287D1D8B37BB021D47BF2521`。
- 当前状态：本子任务等待 root 审核。最终候选的纸面分流、同步 RAM 和串行算术已完成 rotation-v1 全夹具独立像素验证，内核综合资源通过。原 scene-v2 的联合分类与 110 资源失败保留历史；整机、布线和实物仍由 root 的后续流程验收。

## 数据与健康合同

预处理输入是 `capture_rgb96` 已抽取的完整 `320×180` 栅格。在输入坐标 `[40,280)×[30,150)` 内按步长 2 采样，实际采样坐标为 `(41+2x,31+2y)`，形成 `120×60` 缓存。其操作区域对应原始 `1280×720` 的 `960×480` 区域；原始像素到该栅格的抽样由上游负责。

只有从 SOF 开始，坐标、行尾、像素数、样本数、frame_id、source 均一致且收到独立健康 EOF 后，缓存才进入处理队列。有效捕获期间即使 valid 为 0，frame_id/source 的变化也会撤销。无 EOF 或停流不会自行生成空场；外部真实帧超时撤销仍由整机采集/显示 watchdog 负责。

背景采用边界各通道 16 桶直方图的下中位数，桶值 `16*bin+8`。固定 RGB 最大通道差不超过 48 的像素，从边界做四邻接连通分离；其余像素为原始 scene。场景与 glyph 分别用中心保留的 `3×3` 至少 3 像素规则去噪。glyph 的颜色判据保持 `min(R,G,B)<180 || max-min>=40`。

scene 至少 12 格且包围盒至少 `3×3` 时视作物体。至少 75% 边界像素须支持同一背景；不满足时强制 present=1，保守输出未知。达到物体门槛的 scene 触碰任一采样边界也拒绝身份。两种拒绝都保留 frame_good=1 和 present=1，并送空白分类栅格，不能用来解除“先移走旧物体”的门槛。

卡片仍发送完整 1024 位序列；默认在 `[6,26)×[6,26)` 的 20 格区域归一化。以 inclusive 包围盒最长边 `side` 等比例居中：

```text
sx = floor((20*(2*xmin + width - side) + (2*(gx-6)+1)*side) / 40)
sy = floor((20*(2*ymin + height - side) + (2*(gy-6)+1)*side) / 40)
```

负分子或源坐标超出 glyph 包围盒的输出为 0。`NORMAL_SIZE` 保留偶数参数化能力；本候选验证的是 20。

## 缓存与验证边界

两个 RGB 缓存、flags、clean_mask 和 FIFO 都采用时钟同步读；大型数组没有复位循环。默认几何下的逻辑存储总量为 468000 bit（不含小直方图与寄存器）。这是数组容量计算，不是 TD 映射资源结果；ERAM 实际推断、布局布线和时序以 root 的独立工程报告为准。

独立 TB 消费生成器保存的 RGB、replay 和 mask 文件，逐像素比较 7200 个 replay 像素和 1024 个归一化位。没有利用 DUT 内部 RAM 计算期望值；内部背景寄存器仅用来额外核对外部模型给出的中位数。无 mem 的全量样本从已登记 PNG 通过精确匹配生成器 SHA 的模型展开，原图、模型、生成参考和脚本均快照并记录 SHA256。

控制测试覆盖：坐标/tag/source/EOL 错误、短栅格、坏健康证书、EOF 同拍像素、重复或缺失 SOF、缺失 EOF、空拍 tag/source 扰动、单独 SOF/EOL、认证 EOF 后额外像素、处理中 flush、两 bank 不同颜色内容的并行采集、第三帧超速溢出、下中位数偶数平分、75% 边界支持的两侧临界，以及停流不重复发布事件。

目前已完成的末轮控制测试为 `runs/scene-normal-20261014-102149-40fb234d`：23 场景、695348 检查、0 错，ModelSim 原生退出 0。单帧 EOF 到 card_end 最大 351687 拍；紧接双帧包含排队的最大延迟为 636972 拍。实际像素时钟与正常帧周期的符合性由整机核对，不以紧凑 TB 输入节奏冒充摄像头时序。

扩大测试 watchdog 时，首次使用未注明 64 位的 `10000000000` 延迟字面量，ModelSim 10.7 按 32 位规则编译拒绝。三轮失败目录 `scene-normal-20261014-102327-4c3e5c59`、`scene-negative-20261014-102327-8c54a65e`、`scene-watchdog-20261014-102327-654db2c7` 保留；它们都没有完成 RTL 功能测试。改为显式 `64'd10000000000` 后，真实 DUT 输出注错轮 `scene-negative-20261014-102506-661fcf4d` 得到 native exit1/errors1/injected1；500ns 提前结束轮 `scene-watchdog-20261014-102506-db646ffb` 得到 native exit2/done0，runner 分别按对应资格条件接受。

## 尚不能宣称解决的问题

1. 像素对照证明实现与指定整数模型一致，不等于模型的类别真值正确。root 已从整机测试查出 scene-v2 的星卡双支路冲突与另一种苹果被积木支路接受；模型原先只核卡片支路，遗漏最终合并结果。新候选拟加入亮色纸面分流，并由 root 检查积木实心性；新的模型/资产/测试保留独立版本。
2. 全面覆盖视野且与原背景同色的遮挡物，在单幅 RGB 图像中不能与空背景区分。小于面积门槛或落在采样间隔内的细小物体也不在本候选可靠检测范围。
3. 纸张整体低于 glyph 明度门槛、强旋转、透视和未建模印刷图案不能被本算法的合成通过数掩盖。用户报告的整幅暗沉与偏色由成像任务单独核查，本子任务没有真实摄像头或上板校准证据。

## scene-v2 全量结果与物理拒收

实际命令为 bundled Python `-B -X utf8 fpga/scripts/sc520-card-recognition/simulate-scene.py --all`。`runs/scene-normal-20261014-102647-4db0cfef` 完成 713 个外部夹具与 22 个控制场景，共 735 场景、28525292 检查、0 错，ModelSim 原生退出 0，done=1，输入和快照 SHA 全一致。单帧最大 EOF 延迟 351902 拍；含双帧排队最大 636972 拍。RTL SHA 为 `9536B815899E977DF80F0DDE50951D562B41E8822ABC16902B8B236361B4E31C`。

此结果覆盖模型一致性，包含压力场景的预期拒识，不能计为 713 个类别真值全部正确。scene-v2 仍有 31 个旋转、1 个透视与 5 个光度压力真值失败；原先卡片/未知卡真值检查漏核 block 支路的问题由 root 的整机测试揭示。

root 的 110 探索综合已超资源并主动停止物理流程。独立回读 `builds/6a50b110/td_project/camera_to_dsi_display_Runs/syn_1/camera_to_dsi_display_gate.area`，scene 层本身为 logic LUT 24292、seq 16722、ERAM 7、DSP 8、DRAM LUT 6144。原始 `td_20261014_102342.log` 第 585–589 行包括五个存储数组的 RAM 抽取，不能声称 FIFO 未被抽取。后续须依据映射而非前端“抽取 RAM”字样判断资源：两个 RGB 缓存的公共 mux 后读寄存器不利于映射同步 ERAM，多写地址的状态机存储写法也需改为独立单写口。新的资源修复与纸面路由另立验证批次，保留 110 和本轮一致性证据。

## 资源修复与纸面分流候选

候选 SHA256：`283152D97021C551FC6F3E2182088EFDE869BB042FBFD03ADF907453D3C7EE8A`。RGB 两 bank 分别有自己的同步读寄存器，读后再选择 bank；flags、clean_mask、FIFO 都把状态解码成唯一写 enable/address/data，独立 posedge 写口不再包含异步复位过程。没有使用未经验证的 RAM_STYLE 强制属性。

第一轮可比内核综合 `builds/scene-ram-ports-20261014-105332-948ef4` 原生退出 0，含输入寄存与 32 位可观测 signature 包装：LUT 4613、reg 2468、slice 3624、ERAM 28、DRAM 0、DSP 8。该轮综合 STA 为 SWNS -1.866ns，主要是 numerator 到 normalized 坐标的组合除法，仍不满足目标。

随后将常数地址/中心乘法写为明确 shift/add，归一化动态乘法用 6 拍逐位加法，除法用 24 拍余数恢复算法并行计算 x/y。整数结果与原公式相同，仅增加每个有效归一化样本的处理时钟。`builds/scene-serial-math-20261014-105849-d65c67` 原生退出 0：LUT 4774、reg 2580、slice 3723、ERAM 28、DRAM 0、DSP 0；SCENE_CLK 周期 9.660ns 时综合估计 SWNS +0.702ns，STNS 0。这是内核综合估计，不是整机布线或上板资格。

完整命令为 bundled Python `-B -X utf8 fpga/scripts/sc520-card-recognition/synthesize-scene.py --tag serial-math`。每次运行保存源快照、工具 SHA、命令、prj、SDC、Tcl、原生 stdout/stderr、网表、面积/时序报告和 manifest。脚本只执行 elaborate/RTL/gate 综合；没有生成 bit、place/route 或操作板卡。首次 Windows 脚本路径使用反斜杠被 TD 当作 Tcl 转义，下一轮直接内核顶层又超过 160 IO，均保留为失败目录；最终通过版本使用正斜杠与 118 IO 的寄存包装，脚本不会仅凭原生退出 0 声称综合成功。

纸面分流采用去噪 scene 中原始 RGB 满足 `min>=180 && max-min<40` 的格数 paper_count。当 scene 已达物体门槛、glyph_count>=12 且 `4*paper_count>scene_count` 时，仅将积木 replay 置白；card 数据、present 和健康值保留。4 倍比较显式扩成 18 位，避免 16 位计数左移溢出。低于 presence 门槛的残留 glyph 仍按原模型归一化，由 present=0 阻止匹配器接受；不会把“无类别”冒充“已移走”。

存储与串行算术变更后的 `runs/scene-normal-20261014-105849-c7c4b8dc` 已完成 23 控制/空场场景、695348 检查、0 错，双 bank 排队上限在该组为 660972 拍。

最终 rotation-v1 独立命令：bundled Python `-B -X utf8 fpga/scripts/sc520-card-recognition/simulate-scene.py --asset-root assets/templates/sc520-card-recognition/rotation-v1 --all`。`runs/scene-normal-20261014-110403-4d918084` 的 182 外部夹具与 24 控制场景共 206 场景、7848451 检查、0 错，原生退出 0，done=1；其中纸面抑制积木 replay 但保留 card、极小残差 present=0 但依合同保留归一化内容都有独立解析用例。单帧最大 365242 拍，排队最大 660972 拍；每个无排队夹具都检查小于 400000 拍。

最终 negative 与 watchdog 命令使用同一 asset-root，再分别加 `--negative --limit 1`、`--watchdog-probe --limit 1`。`runs/scene-negative-20261014-110403-57ba8892` 得到真实 DUT 输出注错 native1/errors1/injected1；`runs/scene-watchdog-20261014-110403-abcd139d` 得到 native2/done0。两轮被对应资格规则接受，不当作正常功能通过数。

`audit-scene.py` 独立回读最终三轮的当前输入、快照、输出和最终内核综合报告，聚合入口为 `scene-rtl-validation-v3.json`；已有报告可用 `--check` 只读复核。最终整机联合类别、确认滤波和问答仍由 root 的 720p 测试核验，本子任务没有单独提交 Git 或修改分支日志，交 root 统一记录与提交。
