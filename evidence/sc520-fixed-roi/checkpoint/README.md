# SC520 实验开发检查点

状态：固定红框、颜色分割、动态框、形状首版的源码备份；不是正式识别验收或稳定发布。主项目总记忆仍由总控另行审核，main 不在本轮合并。

## 包含与不包含

Git 保存自研 ROI RTL、测试用例、原有构建/仿真/封装脚本、阶段日志，以及依赖清单和接入增量。四阶段各自保留真实工程路径；相同自研模块的阶段副本用于恢复历史候选，不把厂商代码复制五遍上传。

原有工程、bit、测试结果和外层 learning 导读均原位保留。厂商包、IP原文件、bit、构建缓存、波形、大报告、Windows缓存、许可证和凭据不进入源码提交。候选镜像与原始证据作为私有仓库的实验预发布附件交付；下载入口见[仓库 Releases](https://github.com/Nuyoahljy/anlogic-kids-learning-machine/releases)。

## 外部依赖

必须自行合法取得 SC520CS 参考包，不从本仓库下载厂商源码。文件可重命名，但内容 SHA-256 必须为：

`F3B51D6BA4A96B2669A10E88BDF014B1588E4D7D1A8D7103F5423BCEE42A0DEC`

来源记录：用户提供的 `lab_ex1_mipi_hdmi_SC520 (2).zip`；没有独立确认其公开再分发许可，因此本仓库仅保留输入哈希、归档条目名和修改增量。TD 固定为 6.2.1；ModelSim 使用合法安装版本，历史验证为 SE-64 10.7。

## 从干净克隆恢复

PowerShell 7.5+，先进入仓库根目录。不会覆盖任何已有不同文件，依赖包错误时直接停止。

```powershell
$archive = "D:/packages/lab_ex1_mipi_hdmi_SC520.zip"
foreach ($stage in @("baseline", "overlay", "color-mask", "dynamic-box", "shape")) {
    pwsh -NoProfile -File ./fpga/scripts/sc520-fixed-roi/restore-checkpoint.ps1 -Archive $archive -Stage $stage
    if ($LASTEXITCODE -ne 0) { throw "Restore failed: $stage" }
}
```

也可只恢复 shape。恢复器从校验过的包获取外部输入，将自研接入增量还原到原顶层/三个源清单，逐文件检查字节哈希（含BOM和换行）；不是只检查文件数量。它不会执行包内程序，也不下载或烧录。

在下一轮已修改源码的工作树中，恢复器或验证器会拒绝与旧检查点不一致的文件；应建立新检查点，不要覆盖新改动。

## 重新验证

```powershell
pwsh -NoProfile -File ./fpga/scripts/sc520-fixed-roi/verify-checkpoint.ps1 -Stage shape -ModelSimPath "D:/modeltech64_10.7/win64/vsim.exe"
if ($LASTEXITCODE -ne 0) { throw "Verification failed" }
```

验证要求干净的已提交检出，先核对工程输入，再运行10个正常测试和1个负向display测试，保存实际HEAD、工具结果、源码及日志哈希；负向预期errors=4/exit=1。输出在忽略的 `evidence/sc520-fixed-roi/checkpoint-runs/`。也支持overlay、color-mask、dynamic-box阶段。

已有各阶段build.ps1、simulate.ps1、prepare.ps1、package.ps1原样保留以保存历史来源，其工具安装路径和旧manifest包含本机约定；其他电脑优先用上述恢复/验证入口，不直接运行历史prepare覆盖工程。重新运行TD时核对相应build.ps1里的TD路径和6.2.1版本；新的bit未必与原布局布线结果逐字节相同，必须重新记录哈希和时序。

## 历史候选与验收边界

| 阶段 | bit | Setup WNS/ns | SHA-256 |
|---|---|---:|---|
| baseline | sc520_baseline.bit | 1.242 | `68C6AED27E91228BA678D627115BE9F51A5163284A97C187E16A46B6DBDEE725` |
| overlay | sc520_overlay.bit | 0.643 | `B2CA8F0674EA669F711D79BFFB7B333C65441790D759BB0A680FB4A9CB6B7CB7` |
| color-mask | sc520_color_mask.bit | 1.091 | `8685C3A722C50994FAE584A811CEF4955D85A52F2C08753583430FB0F6EB26B0` |
| dynamic-box | sc520_dynamic_box.bit | 0.229 | `804E37D822314BDC878326EE94DC35F48C032B23B38208EDD3091ECD88B8DA5A` |
| shape | sc520_shape.bit | 0.101 | `F5F88FD03A99FBD10C23FFCFF4AEC2E7B24991F492F323BEE52E6B10C4E1A254` |

- 固定框：有用户下载截图和电视红框照片；颜色/动态框：有用户初步正常反馈，不等同完整独立验收。
- 形状版：软件侧验证完成，尚无实物验收；C/S/T表示圆/方/三角，按颜色着色，未知显示问号。没有接入正式item_id、中文、语音和卡片识别。
- 形状采用填充率/长宽比启发式，不保证旋转、透视、多目标或反光情形。Setup余量0.101ns，Hold0.020ns，STA95.62%，继承时钟警告未消除。
- 实际帧率、30分钟稳定性、九类准确率、断电自启动均不能由脚本/CI通过推出。

本轮新提交只是将既有实验成果形成真实版本历史，不伪造过去的提交时间。正式可信任务卡与主项目状态更新仍待总控批准；本分支没有借用协作PR的绿色检查来宣称RTL的云端验证通过。新测试报告和提交号以本次PR及预发布附件为准。

首次检查点提交在独立发布检出中完成：活动 sc520-fixed-roi 工作树同时有另一对话进行 sc520-osd-demo，故其 HEAD 和新任务文件不在本轮移动或提交。不要将远程检查点强制 reset 到活动工作树；待新任务交接后再由总控协调同步。
