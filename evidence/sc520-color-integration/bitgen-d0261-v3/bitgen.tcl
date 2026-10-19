if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
cd {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-color-integration/evidence/sc520-color-integration/builds/6a50b261/td_project}
open_project {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-color-integration/evidence/sc520-color-integration/builds/6a50b261/td_project/camera_to_dsi_display.al} -noanalyze
import_db {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-color-integration/evidence/sc520-color-integration/builds/6a50b261/td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_pr.db}
cd {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-color-integration/evidence/sc520-color-integration/bitgen-d0261-v3}
bitgen -bit sc520-d0261.bit
} message]} {puts stderr $message;exit 1}
puts "MAIN_APPROVED_D0261_BITGEN_COMPLETE"
exit 0
