if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
cd {U:/sc520-color-integration/evidence/sc520-shape27/builds/6a50b270-phy-r2/td_project}
open_project {U:/sc520-color-integration/evidence/sc520-shape27/builds/6a50b270-phy-r2/td_project/camera_to_dsi_display.al} -noanalyze
import_db {U:/sc520-color-integration/evidence/sc520-shape27/builds/6a50b270-phy-r2/td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_pr.db}
cd {U:/sc520-color-integration/evidence/sc520-shape27/bitgen-d0270-v1}
bitgen -bit sc520-d0270.bit
} message]} {puts stderr $message;exit 1}
puts "MAIN_APPROVED_D0270_BITGEN_COMPLETE"
exit 0
