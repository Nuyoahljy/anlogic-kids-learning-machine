# SC520 I0310R4C 初步终版工程包

本版为用户指定保留的初步终版。固定提交 `435d5df612d7611e5d97837302b718ea34666e5d`，GitHub 仓库为 `Nuyoahljy/anlogic-kids-learning-machine`，固定标签为 `sc520-i0310r4c-submission-v1`，冻结分支为 `release/sc520-i0310r4c-submission-v1`。后续增强候选不覆盖本版。

本 bit 实际启用苹果、香蕉、汽车、星星、雨伞五类图卡识别，以及跟踪框、图像风格、问答计分、TF 到 HDMI 音频、Logo 和 SW4 再校准。生产参数是 `SHAPE_ENABLE=0`、`TRACK_ENABLE=1`。原冻结说明中“卡片/几何识别”的历史措辞应以此处实际生产参数为准；颜色圆、正方形、三角形是后续独立增强任务。

## 文件

| 路径 | 用途 |
|---|---|
| `firmware/sc520_i0310r4c.bit` | 原冻结 bit，1789539 字节 |
| `sc520_i0310r4c_sources.zip` | 原构建字节快照，360 个源文件及逐文件清单 |
| `prepare.py` | 只依赖 Python 标准库的移机准备器 |
| `media/AUDIO.PAK` | 与冻结播放器匹配的版本 2 音频包 |
| `media/media-manifest.json` | 原32槽媒体来源、文本及哈希 |
| `MANIFEST.json` | 本交付包全部文件的长度与 SHA-256 |
| `evidence/` | 冻结、上传、软件、物理及路径准备的既有审核摘要 |

bit SHA-256 为 `E52E799C15F0507F22E69DEF6036EF218CDBF05EFC47D4EB53D5B1C1FC8DB87B`；源 ZIP 为 `ADEF639CB90DC41A1C23595ADC2D20978C881C7ADBD7A5D4F6A172312A05E96A`；AUDIO.PAK 为 `1F0DBF08B0215384941E40AE2A4343A0BCD27831A1E177B296B4B014C835C925`。

## 准备工程

在 Windows 上解压本交付包，使用 Python 3.12，在解压目录执行：

```powershell
python -I -B ./prepare.py --archive ./sc520_i0310r4c_sources.zip --output E:/sc520-r4c
```

`--output` 必须是尚不存在的短英文绝对路径。成功后，用 **TD 6.2.1 Engineer 6.2.168.116** 打开 `E:/sc520-r4c/project/td/camera_to_dsi_display.al`。器件为 PH1P35MDG324。准备器在创建目录前核验源 ZIP、全部360文件和工程依赖，达到 TD IP 加载路径260字符边界时拒绝并提示使用更短目录。

仅七个文件做绝对路径前缀适配，逐文件逆向还原核验；其余353文件保持原字节、行尾和编码，原 SDC、ADC 与 PLL 保持。原档案中的 j305/j309/j319 三处头文件来源均映射到包内相同917字节的 `recognition30_packet.vh`。新目录中 `preparation-result.json` 给出实际打开入口，`path-map.json` 给出完整映射。

新工程使用准备位置的绝对路径，整体移动之后应在目的位置重新准备。准备失败的目录保留，重试选另一个新目录。`evidence/` 和原 manifest 中的旧绝对路径是历史来源说明，移机准备不访问这些路径；完整原生数据库、四角 SDF 和全部仿真输出未收入本精简交付包。

## 媒体与上板

TF 卡使用 FAT32，将 `media/AUDIO.PAK` 复制到卡的根目录，文件名保持 `AUDIO.PAK`。本包为48kHz、单声道、16位、32槽的版本2；旧版本1会被播放器拒绝。当前五卡实际使用14槽，其余无色几何等槽的存在不代表当前 bit 已启用对应识别。

使用 TD Programmer 的 `PROGRAM_SRAM` 加载本包中的原 bit。先保持 SW4=0，检查启动、五卡、跟踪框、四键、风格、问答和 TF 音频。换光源后将 SW4 从0稳定拨到1，检查校准期间识别撤销、画面持续输出、重新锁定后恢复；持续为1不应反复触发。再拨回0后拨到1，重复一次并记录结果。

本版已有有界软件验证和原时钟最终布局布线证据：setup/hold WNS `+0.023/+0.020 ns`，TNS均0，Slice `20142/21216`、ERAM `103/108`、DSP `27/40`。STA覆盖率96.96%，CDC模型含未实测假设，外部 I/O 及真实摄像头、720p/CSI/DDR、两次 SW4 重校准、媒体听感与整机稳定性仍待实板验证。路径准备成功不代表重新综合或新 bit 已通过；此交付未写 Flash。
