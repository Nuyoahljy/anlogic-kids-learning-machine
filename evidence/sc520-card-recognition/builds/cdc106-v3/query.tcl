if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/builds/6a50b106/td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_pr.db}
update_timing -mode final
set analysis_dir {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/builds/cdc106-v3/analysis}
source {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/fpga/custom_project/sc520-pixel14/overlay/report-pixel14-cdc.tcl}
} m]} {puts stderr $m;exit 1}
puts "PIXEL14_POSTHOC_CDC_OK"
exit 0

