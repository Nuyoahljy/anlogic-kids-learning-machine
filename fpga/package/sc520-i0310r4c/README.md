# I0310R4C 移机准备

本工具从固定源码 ZIP 创建引用闭合的新工程目录。初步终版仍是提交 `435d5df612d7611e5d97837302b718ea34666e5d`、标签 `sc520-i0310r4c-submission-v1`；准备过程不覆盖原源码、原 ZIP 或原 bit。

本版实际启用苹果、香蕉、汽车、星星和雨伞五类图卡，生产参数为 `SHAPE_ENABLE=0`、`TRACK_ENABLE=1`。颜色圆、正方形和三角形属于后续候选，不能把源码中未启用的几何支路当作本 bit 的功能。

## 在另一台电脑准备

需要 Windows、Python 3.12 和本工具，以及原 [源码 ZIP](../../release/sc520-i0310r4c/sc520_i0310r4c_sources.zip)。ZIP 的 SHA-256 固定为 `ADEF639CB90DC41A1C23595ADC2D20978C881C7ADBD7A5D4F6A172312A05E96A`。工具只读取该 ZIP，不访问清单中的旧电脑绝对路径，也不依赖本机学习目录、TD 安装路径或 Git 仓库。

在本目录执行，按实际 ZIP 所在位置修改 `--archive`。`--output` 必须不存在，使用短英文绝对路径：

```powershell
python -I -B ./prepare.py --archive ../../release/sc520-i0310r4c/sc520_i0310r4c_sources.zip --output E:/sc520-r4c
```

成功后用 **TD 6.2.1 Engineer 6.2.168.116** 打开 `E:/sc520-r4c/project/td/camera_to_dsi_display.al`。器件保持 PH1P35MDG324，速度等级和原 PLL、SDC、ADC 不变。工具会检查 TD 从 `syn_1` 加载八份 IP XML 时的未规范化路径长度，达到 260 字符即在创建输出前拒绝，应换更短的新目录。

工程内采用当前准备位置的绝对路径。整体移动已准备目录后，应从原 ZIP 在目的位置重新准备，不能直接沿用旧位置引用。已有输出禁止覆盖；失败目录保留，修正后选择另一个新输出目录。

## 核验内容

工具核对 ZIP 的 361 个成员和 `snapshot-manifest.json` 中全部 360 个工程文件的长度、SHA-256，再只替换七个文件内的路径前缀：

| 文件 | 路径替换数 |
|---|---:|
| `td/camera_to_dsi_display.al` | 164 |
| `td/syn_1/camera_to_dsi_display.prj` | 164 |
| `td/syn_1/settings.cfg` | 5 |
| `owned/fpga/custom_project/sc520-system-integration/overlay/design_top_wrapper.v` | 4 |
| `owned/fpga/rtl/sc520-shape-card30/items30_result_join.v` | 1 |
| `owned/fpga/rtl/sc520-shape-card30/pixel30_pipeline.v` | 1 |
| `owned/fpga/rtl/sc520-system-integration/pixel301_pipeline.v` | 1 |

前四项和 `pixel301_pipeline.v` 的原根为 j319；另两个头文件入口分别保留了历史 j309、j305 前缀。新准备将三者映射到同一个包内 `recognition30_packet.vh`，并核其 917 字节及固定 `D4D30699…EA93` SHA-256。不会读取旧 j309、j305 目录。

每项替换都做逆向字节还原；其余 353 个工程文件保持原字节和行尾。落盘前核对两份工程各 164 个有序引用、153 个 HDL 编译项、八份 IP XML 的 58 个 fileset 引用、一个旧 IPC 输出、四个顶层 ROM 参数、三个任务头文件入口和五个设置引用，全部位于新工程内。厂商原源码的相对目录结构、条件编译分支及原注释保持原样，不把所有未启用分支的默认文件名当作生产实例参数。

`preparation-result.json` 保存实际准备结果、工具哈希、精确打开入口和路径长度；`path-map.json` 保存全部成员映射、七项替换和前后哈希。`archive/snapshot-manifest.json` 保留原清单，仅描述历史构建，不能作为新工程运行记录。

可对已成功准备的目录执行有界守卫检查。报告文件必须不存在且位于准备目录外；此检查只写这一份报告，不改工程内容：

```powershell
python -I -B ./test-prepare.py --archive ../../release/sc520-i0310r4c/sc520_i0310r4c_sources.zip --prepared E:/sc520-r4c --report E:/sc520-r4c-guards.json
```

检查覆盖坏 ZIP、越界及原始反斜杠成员、259/260 字符边界、缺失 ROM/头文件、已有输出拒绝，以及全部 363 个准备结果文件在拒绝前后保持一致。

## 验证边界

本准备只验证归档字节和工程引用，不运行 TD、不重新综合、不生成 bit，也不执行真实下载或 Flash。原 bit 的 SHA-256 为 `E52E799C15F0507F22E69DEF6036EF218CDBF05EFC47D4EB53D5B1C1FC8DB87B`；新编译的成功、资源、时序和 bit 一致性须另行验证。

源码 ZIP 不含音频 `AUDIO.PAK`、原路由数据库、四角 SDF 或完整软件仿真证据。音频媒体应使用与冻结播放器匹配的 version 2 包，由交付总清单单独绑定，不能复用旧 version 1 包。真实摄像头、720p/CSI/DDR、两次 SW4 重校准及整机稳定性仍待实板验收。
