if {[catch {
 source settings.cfg
 if {$device_name ne "ph1_35p.db" || $package_name ne "PH1P35MDG324"} {error "Wrong device"}
 source camera_to_dsi_display.tcl
 write_verilog pixel14-syn_1-netlist.v
 report_clock_summary -file pixel14-clocks.rpt
 report_timing_exception -file pixel14-exceptions.rpt
} message]} {puts stderr $message; exit 1}
puts "PIXEL14_syn_1_OK syn_1"
exit 0
