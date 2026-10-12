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
foreach pair {{u_p14_pipeline/staging_fault_meta u_p14_pipeline/staging_fault_sync staging-fault} {S_p14_cfg_done[0] S_p14_cfg_done[1] config-done} {S_p14_cfg_error[0] S_p14_cfg_error[1] config-error}} {
    lassign $pair start finish name
    if {[llength [get_regs $start]] != 1 || [llength [get_regs $finish]] != 1} {error "CDC register resolution failed: $start $finish"}
    report_timing_path -from [get_regs $start] -to [get_regs $finish] -ep_num 1 -path_num 1 -file "${name}.rpt"
}
for {set i 0} {$i<4} {incr i} {
    set start [format {u_quiz_keys/keys_sync_meta[%d]} $i]
    set finish [format {u_quiz_keys/keys_sync_safe[%d]} $i]
    report_timing_path -from [get_regs $start] -to [get_regs $finish] -ep_num 1 -path_num 1 -file "key-${i}.rpt"
}
report_timing_exception -file original-exceptions.rpt
report_timing_ignored -file original-ignored.rpt
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
if {[llength $mipi_pin]!=1 || [llength $hdmi_pin]!=1} {error "CDC physical clock pins not resolved"}
create_clock -name MIPI_RX_BYTE_CLK -period 9.660 $mipi_pin
create_clock -name HDMI_PIXEL_CLK -period 13.333 $hdmi_pin
set payload_from [get_regs {u_p14_pipeline/forward/held_data*}]
set payload_to [get_regs {u_p14_pipeline/forward/dst_data*}]
set_max_delay -datapath_only -from $payload_from -to $payload_to 10.000
update_timing -mode final
if {[llength [get_clocks MIPI_RX_BYTE_CLK]]!=1 || [llength [get_clocks HDMI_PIXEL_CLK]]!=1} {error "CDC analysis clock reconstruction failed"}
report_clock_summary -file analysis-clocks.rpt
report_timing_path -from $payload_from -to $payload_to -ep_num 200 -path_num 1 -file payload-max10.rpt
report_timing_exception -file analysis-exceptions.rpt
report_timing_ignored -file analysis-ignored.rpt
puts "PIXEL14_CDC_PHYSICAL_REPORTS_OK"
cd $saved_cwd
