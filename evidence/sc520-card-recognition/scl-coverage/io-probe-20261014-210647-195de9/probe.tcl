if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/builds/6a50b113/td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_pr.db}
read_sdc {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/builds/6a50b113/overlay/pixel14.sdc}
update_timing -mode final
set parent_clock [get_clocks pll_clk_24m]
set scl_port [get_ports O_cam_scl]
set sda_port [get_ports IO_cam_sda]
if {[llength $parent_clock]!=1 || [llength $scl_port]!=1 || [llength $sda_port]!=1} {error "I2C measurement endpoints not resolved"}
# Zero external delay creates reportable output endpoints for MEASUREMENT.
# These commands are not sensor timing constraints and do not alter the bit.
set_output_delay -clock $parent_clock -max 0 $scl_port
set_output_delay -clock $parent_clock -min 0 $scl_port
set_output_delay -clock $parent_clock -max 0 $sda_port
set_output_delay -clock $parent_clock -min 0 $sda_port
update_timing -mode final
report_timing_path -to [get_ports O_cam_scl] -ep_num 4 -path_num 20 -file scl-pad.rpt
report_timing_path -to [get_ports IO_cam_sda] -ep_num 4 -path_num 20 -file sda-pad.rpt
report_timing_exception -file probe-exceptions.rpt
} msg]} {puts stderr $msg;exit 1}
puts "I2C_IO_PROBE_DONE"
exit 0
