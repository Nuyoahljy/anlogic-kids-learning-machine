# SC520 颜色形状独立增强实验

- 任务 ID：sc520-color-shape-next
- 状态：等待主对话审核
- 负责人：Codex /root local/01a18534-9515-79d0-8443-217f618fd923
- 分支：task/sc520-color-shape-next
- 基础提交：435d5df612d7611e5d97837302b718ea34666e5d
- 开始时间：2026-10-29T10:11:10.4374063+08:00
- 工作目录：E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-color-shape-next

## 目标与验收条件

用户先前明确要求：整理并上传当前初步终版；即使GitHub失败也保留该版，随后可尝试继续开发颜色圆、正方形和三角形。原初步终版435d5df和整理交付c4e34de均已实际上传GitHub且远端核验；共享登记Generate/-Check已通过1312记录/33826路径，允许开始本独立实验。

本阶段先固定红黄蓝与圆/正方形/三角形的模型和真值，再实现有界、同帧的任务私有颜色统计模块。灰、绿、青、品红、无主色、坏帧、缺记录、身份变更和溢出都须验证；不能照搬旧传感器域“G最大=黄色”规则或用无色T030真值替代九色真值。目标是得到可审核的软件/模块实验结果，不宣称已接入正式整机或现场通过。

## 已读文档与历史边界

Root已读共享AGENTS/README/FILE_INDEX、最新冻结与交付记录，主库当前AGENTS/PROJECT_MEMORY/PLAN/TASKS/DECISIONS/interface和原树/本新树同名文档及集成日志。新树继承2026-09-20总文档和旧任务日志是历史；主库D106与精确I0310R4C冻结范围优先：SC520、原75MHz/9.660ns/13.333ns/2.666ns、54拍取样、N+8、TF-HDMI版本2及五卡实际生产。新的九色目录、文字、题库和媒体须独立版本，不能默改原目录。

原submission-v1 tag/branch均435d5df，原bit/source ZIP/媒体/离线bundle不动。新Worktree通过精确Git commit单独创建；主库既有未提交资料和全部旧Worktree保持，不为创建实验先提交或回滚主库。

## 当前分工

Root单写本任务日志和共享learning记录，负责范围、模型接受、模块/仿真阶段审核及实际交接。model作者仅写新任务fpga/model/sc520-color-shape-next；rtl作者仅写新任务fpga/rtl和fpga/sim/sc520-color-shape-next；独立审者只读审核。具体角色接收与结果另按实际记录。

先模型纯Python分析与固定输入，再按明确接口实现颜色观察器并用独立算术oracle仿真。只改新增任务私有文件；现有生产顶层、原模块、PLL、SDC、ADC、媒体和UI不改。本阶段不TD/route/bit/下载/Flash，最终整机接入及物理另审。

## 初步只读发现

现有pixel307_scene保存完整RGB双bank/clean_mask，可在真实glyph统计位置复用；没有新增图像RAM的必然需要。几何可复用pixel302_shape_scores，但旧B17只有白底/正放/已测尺度的有界资格，不能凭复用声称任意旋转或五卡零回退。

旧pixel26_classify_pipe的黄色规则以G最大为前提，理想黄色(255,255,0)会拒识，绿色(0,255,0)会被判黄。当前R4C已换AWB，旧final05模型不能直接恢复。新候选需要先保留这个反例，再固定规则和测试。

## 修改文件

本阶段起始仅新建Worktree和本日志，后续新增模型/模块逐文件登记。继承8683个tracked文件的实际来源由435d5df Git tree定义，未逐文件重新人工审核。

## 验证命令与结果

`git worktree add -b task/sc520-color-shape-next E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-color-shape-next 435d5df612d7611e5d97837302b718ea34666e5d`实际自然0；新树tracked status为空、分支和绝对路径准确。尚未新模型或仿真，不将计划写成通过。

## 阻塞与风险

当前原整机只余1074 Slice、5 ERAM、13 DSP，setup余量0.023ns；新增几何与九色相关下游能否满足资源和时序待新构建。新模型合成数据或历史RGB不等同当前实拍颜色。版本2音频包含无色几何槽，九色媒体需独立适配。

## 待决策事项与建议总文档更新

只有模型与独立模块通过后才决定是否接入完整整机；新任务局部catalog不得升级为公共稳定接口。向统筹主建议记录初步终版已冻结/上传与增强实验已开始，不改变实板资格。

## 下一分支交接

从本日志和共享最新记录继续；原初步终版与c4e34de交付包始终可回退。任何新TD/整机发布须先完成相应软件、资源、时序和新bit审核。

## 2026-10-29 模型与颜色观察器验证收尾

固定模型首轮实际执行返回0：16个canonical、12个vote boundary全部通过；旧62个fixture中47个颜色资格、46个已知颜色真值全部通过，16个unknown expected保留，所有输入SHA/Bytes前后不变。模型不推断shape；`clipped` 行颜色阶段可能得到红色资格，已作为明确限制记录，必须由完整glyph/clip/health门控拒收。Root观察见 `E:/juan/FPGA/learning/sc520-color-shape-next/model-review-root-20261029.json`。

私有`pixel311_color_vote`由四个实验文件组成，已做静态检查和Python runner `--help`/`py_compile`。实际ModelSim SE-64 10.7首轮编译0 errors/0 warnings，但测试台结束拍多等一个时钟，结果为`errors=3 checks=44`；保留首轮目录和原因。修正测试台采样时机后，第二轮隔离目录 `E:/juan/FPGA/learning/sc520-color-shape-next/color-vote-run-20261029-1102` 实际返回0，编译0 errors/0 warnings，`RESULT errors=0 checks=44 events=8 revokes=7`、`PASS color vote`。高计数7200、三种同拍边界、连续index、frame/source/expected错误、活动重启、坏end、flush和异步复位均在TB覆盖。

这次通过只接受任务私有颜色事务观察器和固定规则边界：不接shape、category、scene、题库、音频、生产顶层或公共接口，不代表九色识别、五卡无回退、资源、时序、bit或硬件通过。原生产树和435d5df初步终版未改，尚未运行TD/route/bitgen/下载/Flash。下一步由独立只读审核复核本批模型/RTL/TB/两次运行日志，Root再决定是否提交实验分支。

## 2026-10-29 11:36 最终窄修复与实验阶段封存

终审发现旧44项统计的覆盖摘要过宽，并发现end-only结束拍遗漏frame/source核验、旧runner只看原生退出码。旧失败/旧有限通过/旧报告均保留；纠正说明位于 `E:/juan/FPGA/learning/sc520-color-shape-next/review-corrections-20261029.json`，不将旧44项追认为新增覆盖。

color_vote_fix只修本任务四个源/文档：DUT结束拍完整身份检查、TB按准确向量生成include、16模型颜色/12投票/4额外阈值与真实协议负例，以及runner严格RESULT/PASS/错误/保护对象判定。固定颜色模型不变。Root用当前E0B5812E重跑模型为 `model-v1-current-20261029-1118`，63输入逐哈希不变，16+12及46已知参考结果保持；旧05C报告不冒称绑定当前代码。

Root实际执行两条create-only命令（各180秒正常等待上限）：

```powershell
python -I -B fpga/sim/sc520-color-shape-next/run-color-vote.py --output E:/juan/FPGA/learning/sc520-color-shape-next/color-vote-v2-normal-20261029-1132 --execute --allow-native
python -I -B fpga/sim/sc520-color-shape-next/run-color-vote.py --output E:/juan/FPGA/learning/sc520-color-shape-next/color-vote-v2-negative-20261029-1132 --execute --allow-native --inject-checker-failure
```

正常compile0/0，native/wrapper0，`errors=0 checks=403 events=41 revokes=19 canonical=16 votes=12 supplemental=4`及单个PASS，Accepted=true。检查器负向故意将首个红向量期待蓝色，真实`errors=1 checks=404`、FAIL/Fatal/无PASS，native0而wrapper1，Accepted=false、CheckerFailureObserved=true。两轮所有保护对象不变。终审color_vote_review_final只读逐核每轮20绑定、跨轮7相同冻结文件及28条生成向量调用，通过且无新增阻断。

当前只封存颜色观察器实验，不接生产scene/shape或下游。clip/完整glyph/健康、跨事务freshness、九色几何、五卡回归、完整物理与硬件仍待后续。超时/孤儿清理未实测，不能称全后代清理已验证。本阶段没有TD/route/bit/下载/Flash。

## 证据路径

- `evidence/sc520-color-shape-next/stage-review-20261029.json`：Root记录实际原生和独立终审，不冒称独立作者文件。
- `evidence/sc520-color-shape-next/model-v1-current-20261029-1118/`：当前模型与向量。
- `E:/juan/FPGA/learning/sc520-color-shape-next/color-vote-v2-normal-20261029-1132/`：正常日志/接受/输入快照。
- `E:/juan/FPGA/learning/sc520-color-shape-next/color-vote-v2-negative-20261029-1132/`：检查器负向拒收证据。

## 待决策事项

先保留当前实验检查点。若继续九色几何整机候选，须从精确源码ZIP角色取scene/shape，另行审核真实完整glyph接点、同帧仲裁、新catalog/题库/媒体及五卡回退，再核新资源和时序。当前不把只靠颜色观察器的局部结果作为放行条件。

## 建议总文档更新

建议统筹主记录：初步终版435d5df与整理交付c4e34de已上传；独立颜色观察器实验阶段已验证。不得更新为九色整机、完整时序、实板或Flash通过。
