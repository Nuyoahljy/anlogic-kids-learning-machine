# T030 独立综合准备

状态：仅计划，等待完整软件独立审核、主审核、Git 检查点及精确综合批准。当前没有执行 TD、创建活动板级工程、修改 ADC/SDC/profile、布局布线、bitgen 或上板。

## 隔离目标

使用 TD 6.2.1，保持现有 PH1P35MDG324 器件与原 capture/display 时钟预算，不迁移 ISP/AWB 或其他功能。新隔离测试工程应位于本任务 evidence 的 create-only 目录，绝不能覆盖旧 294/r4 或活动板级工程。仅综合完整 `pixel30_pipeline`，默认 `RENDER_ENABLE=1`、`ROTATION_VARIANTS=256`、三帧确认和 1.2M 周期预算，不能用禁用显示的资源报告代表完整候选。

顶层 wrapper 必须把 RGB96、capture-close/frame-id/source/revoke、显示时钟和 video RGB/坐标/同步、tick、四键、flush 及音频 idle/fault作为实际输入，把完整视频、业务/音频事件、识别结果、192包及运输健康输出连接为可观察输出。不得绑常量裁掉字体/Logo/模板/确认/CDC/业务，也不得为了好看的资源结果把输出关掉。板级 SRAM/Flash/UART/I2C/DDRx/MIPI/ADC/SDC不属于本次模块候选。

## 输入冻结

未来批准须绑定提交号和 `source-freeze.json` 中全部13任务RTL、私有packet头、8个共享RTL及全部模板/字体/Logo/目录/接口文件的 SHA/大小；包含实际模板102400词、几何1024词、Logo index16384词及palette1024词。模板文件路径应显式绝对绑定，不靠运行目录碰巧找到同名文件。编译顺序由源清单给出，wrapper和Tcl也须先材料化、独立全文核验后再授权。

软件证据至少包含完整973 RGB scene和2253 scorer、固定C仲裁、27场matcher旧新逐拍/memory/tie/malformed、300场filter、十题/四键、完整真实RGB96双时钟/60fps/超速/flush链，以及四幅720p逐像素字体/Logo和全NA诊断。故意错误oracle必须原生1且恰好1错，正常应原生0/0错/准确场景及检查数，前后输入保持。

## 唯一执行与后审

主审核另批允许一次真实综合后才创建并启动 TD，记录真实命令、创建时间、PID/父PID、原生退出和完整stdout/stderr；失败或中断保留原件，不自动重试。仅运行综合/门级优化，不调用 `opt_place`、`opt_route`、`bitgen` 或下载命令。

真实综合完成后单独核新数据库与网表新鲜性/哈希、所有源/ROM前后保持；审总量和分层 LUT/REG/ERAM/DSP，逐一核 RAM/ROM 推断、容量、模板完整初始化、字体/Logo保留、两域复位释放与CDC存活，审所有关键告警和意外常量裁剪。原scene28/matcher26/shape1 ERAM只是历史归属，不能预报净减量。

综合通过不等于物理时序通过。识别侧完成主审核/登记/冻结后由主对话发给指定总集成对话；整合方统一其他功能和最终完整布局布线、物理/bit/现场验证，本任务不提前授权其开工。
