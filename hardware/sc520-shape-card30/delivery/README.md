# D0300 八类识别模块交付草稿

**状态：草稿。软件候选已接受；完整资源、原双时钟及最终交付均待主审核。尚未正式交付或授权总集成开工。**

源码提交：`1f0a6b72fabe3289d3f5d9f80a9f861570c15a7b`。目录语义：`shape3-cards5-v1`。候选只接受固定白底、几何正放和已测尺度，不代表现场八类全通过。

## 文件入口

- `manifest-draft.json`：D089 六类证据、绝对路径/SHA256/字节数、未完成门槛、接口与集成依赖。
- `compile-order.txt`：21 个运行时 RTL 的冻结编译顺序，含13个任务 RTL 和8个共享 RTL。
- `verification-draft.json`：本轮45个冻结文件与原提交 Git blob 的实际字节验证，以及38项证据引用的完整性。

原 freeze 共45项：21源、10资产/合同、9测试、4工具、1共享验证参考。冻结的 interface、synthesis-plan、source-freeze 中部分 Stage 是早期历史状态；后续软件接受以主 `software-approved-20261022.json` 为准。本草稿不回写旧冻结文件。

## D089 六类证据

| 项目 | 已有证据 | 当前结论 |
|---|---|---|
| 1. 冻结源码、ROM、编译序 | 45文件与1f0a6b72 Git字节一致，21源顺序和4个外部ROM参数明确 | 软件冻结保持；最终交付检查点待主确认 |
| 2. 模型与RTL一致性 | 全973 RGB场景、2253评分合同0错；14个选定探测/显示报告及独立、主审 | 有界软件接受；漏识与原真值保留 |
| 3. 同帧、CDC、吞吐与192位 | 39帧完整RGB96/RENDER_ENABLE1链，实际FIFO7200、EOF最慢465142 capture周期，以及独立异常/CDC审查 | 软件接受；物理与亚稳态未接受 |
| 4. 八类业务与显示 | 三帧确认、八槽十题十分、四键、四幅720p逐像素、完整NA、逻辑音频事件 | 软件接受；真实媒体与硬件未接受 |
| 5. 新综合与资源 | 单次真实native0，E539结果、4EA4 DB、DD998网表；ROM/mailbox部分审核 | 完整资源和原双时钟pending，不能签核物理 |
| 6. 范围、失败与依赖 | 主软件接受的全部限制、接口/目录/显示/音频边界 | 完整披露；现场仍待验证 |

综合后legalize的 gate_full 观察为9142 LUT、5570 REG、6339估算slice、68 ERAM、8 DSP、137 IO。它是带可观察包装器的模块探针；包装器225位可写输入存储、译码、phase、输出mux及pads须单独解释，不得把这些数值当整机占用、净节省、布线成功或板级引脚资格。

## 集成接口与资产

顶层为 `pixel30_pipeline`，全部端口和参数以冻结源为准。编译时加入 `fpga/rtl/sc520-shape-card30` 头文件搜索路径，使用 `recognition30_packet.vh`；保留 `RENDER_ENABLE=1`。4个ROM参数的原始绝对路径和SHA见 manifest 的 `ROMParameterBindings`。保留items14字体、font-extension与完整Logo等共享依赖，不能因旧文件名含color而删除。

输入为真实capture域RGB96、帧身份、来源、行尾、帧好坏与撤销；独立display域包括1ms tick、业务键路由、视频同步与像素。保留54拍输入对齐前提、六寄存显示层N+5、同源复位分别同步释放。稳定192位前向邮箱把业务和真实诊断作为同一原子包运输，1位反向clear不能省略。

合法类别：0未知、1圆、2方、3三角、10苹果、11香蕉、12汽车、13星星、14雨伞；4..9和15禁止输出或出题。1..3不可沿用旧红色几何文案或旧音频曲号。三帧确认在最终统一仲裁之后；未知目标present=1，不能当空场。

fresh只说明运输和年龄有效，不等于healthy。坏包、缺项、身份错、来源切换及超时必须立即撤销业务可信度；显示帧起始单次快照，撤销保持到下一合法帧。无数据完整显示NA，0距离不能代替不可用值。`obs_conflict`是固定0的兼容口，实际歧义在packet reason bit4。原五卡raw winner在距离拒识时仍保留真实最近类。

## 时钟与验证范围

实现目标保持capture9.660 ns、display13.468 ns。39帧软件链的冻结激励为capture9.660 ns、display13.333 ns；其约16.66476546 ms间隔由循环和标记推导，绝非硬件测量或原预算下的物理通过。两者分别记录，不混作同一个测试。

原综合时钟调用失效，只产生默认20 ns报告；D098 v2只读分析在guard失败，native1且无时钟报告。D100 v3已于2026-10-22 17:35:11至17:35:20真实执行一次：TD31708自然native0、外层1，完整新报告仍默认20 ns；五次可读查询均报告本机不支持-o，clock名称查询为空。执行器按报告、查询及严重错误拒收，AnalysisCompleted=false。全部旧输入/目录保持，未重试；当前需定位read_sdc后的真实约束应用语义，不能只去掉-o就判成功。完整资源和clock主接受字段仍为空。

## 可复现软件入口

使用本机捆绑Python完整路径，以 `-B -X utf8` 运行冻结 `simulate-shape-card30.py`：全量scene用 `--test scene --all`，全量scores用 `--test scores --all`；matcher、filter、quiz、render选择对应 `--test`，正向与 `--negative` 分开运行。链路runner为 `simulate-shape-card30-chain.py`：正常完整链使用 `--test stream --matrix --render-enable --full-fps`，负向为 `--test stream --matrix --negative`；system使用 `--test system` 及 `--negative`。

以上是复现入口。本草稿没有重跑软件，不提供旧TD目录重新执行指令；精确历史命令与原生结果可由manifest绑定的运行报告追溯。全量scene/scorer历史运行缺工具始末SHA且使用旧runner快照；后续加固runner的正负smoke是独立证据，不冒称全量重跑。原失败报告保持。

## 必须保留的限制与收尾

原17个阴影/近圆、50个新增姿态、30个holdout姿态、1个holdout苹果、5个暗卡漏识均保留；这些组可能含重叠来源，不能相加当独立现场错误率。没有任意底色、任意姿态、替换颜色或光照鲁棒性承诺。诊断frame_id不证明DDR相机图像与业务上下文逐帧同步。

只交逻辑音频事件。真实曲号/媒体映射、UART/GPIO、BUSY、电平、播放器与三个VERIFIED门控未验。AWB、显示风格、音频由总集成统一接入。本侧不进行route或bit；总集成须重新完成原时钟全物理、ROM/reset/CDC、最终固定DB bit与用户上板验证。

正式交付前仍需完整资源与原双时钟结论、主精确接受、任务范围检查点、共享登记/索引Check，以及主向指定整合对话发送并确认接收。当前草稿不完成这些步骤。
