if {[catch {
 source settings.cfg
 if {$device_name ne "ph1_35p.db" || $package_name ne "PH1P35MDG324"} {error "Wrong device"}
 if {"syn_1" eq "phy_1" && $end_step ne "opt_route"} {error "T027 requires route-only"}
 proc bitgen {args} {error "T027 bitgen is prohibited"}
 source camera_to_dsi_display.tcl
 write_verilog pixel14-syn_1-netlist.v
 report_clock_summary -file pixel14-clocks.rpt
 report_timing_exception -file pixel14-exceptions.rpt
 if {"syn_1" eq "phy_1"} {source ../../../overlay/report-pixel14-cdc.tcl}
} message]} {puts stderr $message; exit 1}
puts "PIXEL14_STAGE_OK syn_1"
exit 0
