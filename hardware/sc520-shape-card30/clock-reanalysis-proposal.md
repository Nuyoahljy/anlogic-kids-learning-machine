# T030同门级数据库只读时钟重分析提案

状态：2026-10-22仅准备，未获新TD执行许可。不得重综合、覆盖原v4或替换D096原报告。

## 原因与来源

D096唯一原生综合0完成，原result E539F853、gate DB 4EA4A925保持。两条create_clock在elaborate之后直接调用遭USR-8122严重告警，get_ports为空；catch没有抛错，最终只有默认20ns DeriveClock，原9.660/13.468预算未生效。原时序SWNS=-8.780ns不能签核，更不能用重分析改写成原流程已按双时钟完成。

已全文核本地TD6.2.1官方DefaultFlow.tcl的elaborate/read_sdc，以及SynIpFlow.tcl的read_sdc；旧已审probe-i2c-io.py采用import_db/read_sdc后get_ports/get_clocks唯一guard。只复用这些已存在命令，不猜测新增sdcinfo命令。

## 唯一新准备

create-only最终`clock-reanalysis-prepared-20261022-1405-v2`复制同一4EA4门级数据库，保留原v1准备与预检。两条SDC分别在capture_clk上9.660ns、display_clk上13.468ns，不添加false_path/multicycle/IO预算，不改时钟周期。Tcl仅import_device/import_db/read_sdc/get_ports/get_clocks/唯一性guard/update_timing/report_clock_summary/report_timing_summary。两个端口各唯一、两个命名时钟各唯一且get_clocks总数为2才输出报告。

没有open_project/elaborate/optimize/export_db/write_verilog/place/route/bit/subst。数据库只作为输入，不导出或覆盖；新内存时序视图不是新综合来源、不是物理时序。无硬件/板级ADC，本probe的非原子输入更新和显示跨域问题仍不得当生产CDC。

## 门禁与失败处理

准备文件和执行器分别封hash；原全部56项历史、全部45软件输入、参考官方脚本、主综合批准、原result/DB与复制DB始末核验。六Tcl stub覆盖正常和read_sdc/端口重复/时钟缺失/update/report失败，stub不是TD。

未来独立及主精确`clock_reanalysis_only_approved`和批准SHA后才允许一次只读TD。严格执行器拒绝原综合批准、hash错误、源HEAD变化、旧started/native/result/stdout/报告和活动TDconsole。无自动重试/kill；wait或poll异常保留真实活动子进程、无伪FinishedAt。失败依旧write-once保存native/result、全部输出、输入变化和严重告警。任何新db/bit，完成marker不新鲜，stdout或stderr出现CRITICAL-WARNING/ERROR均不接受分析完成。

最终v2使用结构化报告核验：唯一Clock Summary详细表按Name/C-Period(ns)绑定两原时钟与精确Decimal周期，排除重复/额外DeriveClock和错周期，拒绝缺字段或非法行；XML必须clock_summary单groups节点、size2、两个唯一合法clock_group且各size1，正数一致clock端点与nonclocks0。表与XML必须同时通过，不能用任意子串出现伪装通过。预检另覆盖错周期、额外默认时钟、stderr严重告警及XML非法结构。

分析完成只代表同DB的双时钟报告生成。无论负余量大小，TimingQualified/ResourceAccepted/HardwareValidated仍为false；主和独立需结合全部原资源/ROM/复位CDC完成D089审核后才进入正式交付。
