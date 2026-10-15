# Invoked after bitgen and original timing reports, on the same routed netlist.
# No export_db, route, optimize, or bitgen after this diagnostic constraint view.
set saved_cwd [pwd]
if {![info exists analysis_dir]} {set analysis_dir [file normalize ../../../analysis]}
file mkdir $analysis_dir
cd $analysis_dir
foreach direction {forward backward} {
    foreach signal {req ack fault} {
        set start "u_p14_pipeline/${direction}/${signal}_meta"
        set finish "u_p14_pipeline/${direction}/${signal}_sync"
        if {$signal eq "fault" && [llength [get_regs $start]]==0 && [llength [get_regs $finish]]==0} {
            puts "PIXEL14_CDC_OPTIMIZED_CONSTANT $direction fault"
            continue
        }
        if {[llength [get_regs $start]] != 1 || [llength [get_regs $finish]] != 1} {error "CDC register resolution failed: $start $finish"}
        report_timing_path -from [get_regs $start] -to [get_regs $finish] -ep_num 1 -path_num 1 -file "${direction}-${signal}.rpt"
    }
}
foreach mailbox {{u_p14_diag_cdc diagnostic} {u_p14_i2c_cdc i2c}} {
    lassign $mailbox instance name
    foreach signal {req ack} {
        set start "${instance}/${signal}_meta"
        set finish "${instance}/${signal}_sync"
        if {[llength [get_regs $start]] != 1 || [llength [get_regs $finish]] != 1} {error "Mailbox CDC register resolution failed: $start $finish"}
        report_timing_path -from [get_regs $start] -to [get_regs $finish] -ep_num 1 -path_num 1 -file "${name}-${signal}.rpt"
    }
}
foreach pair {{u_p14_pipeline/staging_fault_meta u_p14_pipeline/staging_fault_sync staging-fault} {S_p14_cfg_done[0] S_p14_cfg_done[1] config-done} {S_p14_cfg_error[0] S_p14_cfg_error[1] config-error} {u_uicfgcs520/busy_meta u_uicfgcs520/busy_sync i2c-busy} {u_uicfgcs520/error_meta u_uicfgcs520/error_sync i2c-error}} {
    lassign $pair start finish name
    if {[llength [get_regs $start]] != 1 || [llength [get_regs $finish]] != 1} {error "CDC register resolution failed: $start $finish"}
    report_timing_path -from [get_regs $start] -to [get_regs $finish] -ep_num 1 -path_num 1 -file "${name}.rpt"
}
for {set i 0} {$i<4} {incr i} {
    set start [format {u_quiz_keys/keys_sync_meta[%d]} $i]
    set finish [format {u_quiz_keys/keys_sync_safe[%d]} $i]
    report_timing_path -from [get_regs $start] -to [get_regs $finish] -ep_num 1 -path_num 1 -file "key-${i}.rpt"
}
# Additional T-018 synchronizers and all I2C input/output/reset path classes.
foreach pair {{{u_uicfgcs520/u_i2c/reset_pipe[0]} {u_uicfgcs520/u_i2c/reset_pipe[1]} i2c-reset} {u_uicfgcs520/u_i2c/sda_meta u_uicfgcs520/u_i2c/sda_sync i2c-sda}} {
    lassign $pair start finish name
    if {[llength [get_regs $start]]!=1 || [llength [get_regs $finish]]!=1} {error "I2C synchronization register missing: $start $finish"}
    report_timing_path -from [get_regs $start] -to [get_regs $finish] -ep_num 1 -path_num 1 -file "${name}.rpt"
}
set i2c_regs [get_regs {u_uicfgcs520/u_i2c/*}]
if {[llength $i2c_regs]<20} {error "I2C register enumeration unexpectedly empty"}
set fd [open i2c-core-objects.txt w];puts $fd $i2c_regs;close $fd
report_timing_path -to $i2c_regs -ep_num 400 -path_num 2 -file i2c-core-inbound.rpt
report_timing_path -from $i2c_regs -ep_num 400 -path_num 2 -file i2c-core-outbound.rpt
foreach signal {req ack} {
    set a [get_regs "u_p14_pipeline/*transport/link/${signal}_meta"]
    set b [get_regs "u_p14_pipeline/*transport/link/${signal}_sync"]
    if {[llength $a]!=1 || [llength $b]!=1} {error "Observation synchronizer missing: $signal"}
    report_timing_path -from $a -to $b -ep_num 1 -path_num 1 -file "color-${signal}.rpt"
}
report_timing_exception -file original-exceptions.rpt
report_timing_ignored -file original-ignored.rpt
report_clock_summary -file original-clocks.rpt
set payload_from [get_regs {u_p14_pipeline/forward/held_data*}]
set payload_to [get_regs {u_p14_pipeline/forward/dst_data*}]
if {[llength $payload_from]<32 || [llength $payload_to]<32} {error "Forward CDC payload unexpectedly optimized away"}
set fd [open payload-objects.txt w]
puts $fd "FROM [llength $payload_from] $payload_from"
puts $fd "TO [llength $payload_to] $payload_to"
close $fd
clear_sdc -user
# Re-deriving PLLs from cleared top clocks is unsupported in this routed TD
# context. Use the actual existing generated-clock output pins, at the periods
# in the original routed clock report; only the mailbox path is evaluated here.
set mipi_pin [get_pins {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]
set hdmi_pin [get_pins {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
set config_pin [get_pins {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
if {[llength $mipi_pin]!=1 || [llength $hdmi_pin]!=1 || [llength $config_pin]!=1} {error "CDC physical clock pins not resolved"}
create_clock -name MIPI_RX_BYTE_CLK -period 9.660 $mipi_pin
create_clock -name HDMI_PIXEL_CLK -period 13.333 $hdmi_pin
create_clock -name pll_clk_24m -period 42.000 $config_pin
set payload_from [get_regs {u_p14_pipeline/forward/held_data*}]
set payload_to [get_regs {u_p14_pipeline/forward/dst_data*}]
# No interactive max-delay exception: this view measures routed propagation.
# The audit compares actual data delays against an explicit external bound.
update_timing -mode final
if {[llength [get_clocks MIPI_RX_BYTE_CLK]]!=1 || [llength [get_clocks HDMI_PIXEL_CLK]]!=1 || [llength [get_clocks pll_clk_24m]]!=1} {error "CDC analysis clock reconstruction failed"}
report_clock_summary -file analysis-clocks.rpt
report_timing_path -from $payload_from -to $payload_to -ep_num 400 -path_num 1 -file payload-routing.rpt
set diagnostic_from [get_regs {u_p14_diag_cdc/held_data*}]
set diagnostic_to [get_regs {u_p14_diag_cdc/dst_data*}]
if {[llength $diagnostic_from]<32 || [llength $diagnostic_to]<32} {error "Diagnostic payload unexpectedly optimized away"}
set fd [open diagnostic-objects.txt w]
puts $fd "FROM [llength $diagnostic_from] $diagnostic_from"
puts $fd "TO [llength $diagnostic_to] $diagnostic_to"
close $fd
report_timing_path -from $diagnostic_from -to $diagnostic_to -ep_num 600 -path_num 1 -file diagnostic-routing.rpt
set i2c_from [get_regs {u_p14_i2c_cdc/held_data*}]
set i2c_to [get_regs {u_p14_i2c_cdc/dst_data*}]
# Some diagnostic bits are constants. Audit every retained logical bit against
# its routed Q/D pins instead of requiring the declared 32 bits to survive.
if {[llength $i2c_from]==0 || [llength $i2c_to]==0} {error "I2C diagnostic payload unexpectedly optimized away"}
set fd [open i2c-objects.txt w]
puts $fd "FROM [llength $i2c_from] $i2c_from"
puts $fd "TO [llength $i2c_to] $i2c_to"
close $fd
report_timing_path -from $i2c_from -to $i2c_to -ep_num 200 -path_num 1 -file i2c-routing.rpt
set color_from [get_regs {u_p14_pipeline/*transport/link/held_data*}]
set color_to [get_regs {u_p14_pipeline/*transport/link/dst_data*}]
if {[llength $color_from]<100 || [llength $color_to]<100} {error "Color observation mailbox unexpectedly missing"}
set fd [open color-objects.txt w];puts $fd "FROM [llength $color_from] $color_from";puts $fd "TO [llength $color_to] $color_to";close $fd
report_timing_path -from $color_from -to $color_to -ep_num 2400 -path_num 1 -file color-routing.rpt
report_timing_exception -file analysis-exceptions.rpt
report_timing_ignored -file analysis-ignored.rpt
puts "PIXEL14_CDC_PHYSICAL_REPORTS_OK"
cd $saved_cwd
