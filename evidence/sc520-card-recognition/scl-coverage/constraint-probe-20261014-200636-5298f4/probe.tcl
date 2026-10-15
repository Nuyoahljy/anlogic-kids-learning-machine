if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/builds/6a50b112/td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_pr.db}
read_sdc {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/builds/6a50b112/overlay/pixel14.sdc}
help create_generated_clock
report_clock_summary -file original-clocks.rpt
set source_pin [get_pins {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
set scl_net [get_nets {u_uicfgcs520/u_i2c/scl_clk_syn_105}]
puts "SCL_SOURCE $source_pin SCL_NET $scl_net"
if {[llength $source_pin]!=1 || [llength $scl_net]!=1} {error "clock source/target not unique"}
create_generated_clock -name I2C_SCL -source $source_pin -edges {237 475 713} $scl_net
update_timing -mode final
report_clock_summary -file augmented-clocks.rpt
set regs [get_regs {u_uicfgcs520/u_i2c/*}]
set fd [open i2c-registers.txt w];puts $fd $regs;close $fd
report_timing_path -to $regs -ep_num 400 -path_num 2 -file i2c-inbound.rpt
report_timing_path -from $regs -ep_num 400 -path_num 2 -file i2c-outbound.rpt
report_timing_exception -file augmented-exceptions.rpt
report_timing_ignored -file augmented-ignored.rpt
} msg]} {puts stderr $msg;exit 1}
puts "SCL_PROBE_DONE"
exit 0
