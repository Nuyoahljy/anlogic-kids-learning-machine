# SC520 形状分类首版

- 任务 ID：sc520-shape
- 状态：等待主对话审核；等待用户上板验证
- 负责人：开发对话01a0fffd-0eb9-7010-9921-5b66e6c1f7d2
- 分支：task/sc520-fixed-roi（继续独立工程，不新建分支）
- 基础提交：f609426044982c986b54e999866be9f4c1af2682
- 开始时间：2026-10-03T16:34:04.5104747+08:00
- 软件交接日期：2026-10-03（Asia/Shanghai）

## 目标与验收条件

用户授权继续至上板前。保留动态框原工程和候选，单独开发平面正视圆/方/三角的填充率与长宽比首版，显示C/S/T/?并按颜色着色。仅限单个完整单色目标，非旋转不变或通用识别。判别间隙及截断目标拒识。不改共享item_id或320x180接口。要求单元、合成形状、完整显示链、故障注入和TD编译验证，最后用户实物验证。

## 已读文档

根AGENTS/README/FILE_INDEX、最新硬件反馈；当前Worktree规则、总记忆、PLAN、TASKS、DECISIONS、接口及动态框日志。总文档旧状态不覆盖最新反馈，仅主对话可回填。

## 修改文件

本任务fpga/custom_project/sc520-shape、scripts/sim对应目录、evidence/sc520-shape、本日志、learning/sc520-shape和独立共享记录。

## 验证命令与结果

启动核对当前分支未提交状态；旧动态框功能正常为用户报告，30分钟长测待证实。

## 实现批

新增shape_classifier、shape_confirm、shape_label和hdmi_shape。用12拍移位累加计算矩形面积，随后分级比较填充率，不新增视频帧缓存。圆/方要求宽高比0.8..1.25，三角0.5..1.75；填充率阈值按128分母：圆88..110，方116..128，三角51..80。尺寸小于24或触识别区边缘拒识。连续3帧同形同色确认，未知立即清除形状标签，保留独立动态框行为。左上C/S/T/?，按颜色着色；不输出共享item_id。已编写边界、合成9类3尺寸、字形及原动态框回归，实际执行待完成。

## 软件验证批（2026-10-03）

ModelSim 10.7完成10项正常测试（errors=0）和1项故障注入（预期errors=4、exit=1）。TD6.2.1综合、布局布线、bitgen退出0；Setup WNS=0.101ns，Hold WNS=0.020ns，TNS=0，STA覆盖95.62%。封装校验11个测试、232份原输入及源码快照；仅4份导入文件按预期调整，新RTL独立新增。SHA256 F5F88FD03A99FBD10C23FFCFF4AEC2E7B24991F492F323BEE52E6B10C4E1A254。尚未下载。常数比例运算仍使用DSP，最终16个，比动态框增加8；不得宣称零DSP增量。完整结果与复现命令将收录run-report.md。

## 证据路径

evidence/sc520-shape；learning/sc520-shape/README.md。

## 阻塞与风险

面积与包围盒特征存在歧义，旋转方块可能类似三角填充率，椭圆/不规则物体可误判；仅限定输入场景的启发式首版。真实分割孔洞、阴影及透视需上板校准。继承时钟警告，旧Setup余量0.229ns。

## 待决策事项

识别共享接口与正式9类item_id输出由主对话审核，不擅改。

## 建议总文档更新

仅按实际软件/用户上板证据审核，不自动更新总项目。

## 交付与复现

实际命令：pwsh -File fpga/scripts/sc520-shape/simulate.ps1 -Testcase <classifier|confirm|label|shapes|stats|stability|capacity|color|sync|display>；另执行display -Negative。pwsh -File fpga/scripts/sc520-shape/build.ps1；pwsh -File fpga/scripts/sc520-shape/package.ps1 -BuildDirectory evidence/sc520-shape/builds/shape-20261003-164524-39380。完整覆盖、环境、指标及限制见evidence/sc520-shape/run-report.md。用户入口E:/juan/FPGA/learning/sc520-shape/README.md。新候选1789539字节。封装与哈希检查通过，继承warning逐行集合无新增，STA不是100%。全部测试是软件证据，未进行上板。

提交号：无新提交，保持用户未授权提交约束；未执行finish-task提交流程，未修改主对话专属文档。建议主对话仅登记软件完成、硬件待测，收到九组合照片/视频后决定特征增强和接口接入。

## 下一分支交接

不自动下载、不写Flash、不提交推送合并；提供新候选与旧版回退，等待用户9种颜色形状组合实测。

## 2026-10-03 用户授权的开发检查点提交

- 用户现已明确授权整理、提交并推送，替代本日志此前只针对当轮的“不提交、不推送”执行边界；不包含main合并或新的硬件操作授权。
- 本阶段自研源码、测试、原脚本及日志保留原路径；厂商/IP依赖通过校验包与增量恢复，不全量上传重复工程。候选bit与原始证据通过私有实验预发布附件保存，不标为稳定版。
- 本次没有改变原RTL、测试输入或候选镜像。新的恢复/验证入口及完整边界见 evidence/sc520-fixed-roi/checkpoint/README.md；实际新提交号、干净检出恢复与复验结果以后续共享登记及PR为准，不伪造历史验收。
