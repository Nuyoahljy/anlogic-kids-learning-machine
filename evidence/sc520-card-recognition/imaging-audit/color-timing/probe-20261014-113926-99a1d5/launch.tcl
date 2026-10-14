if {[catch {source settings.cfg; source flow.tcl; report_timing_path -ep_num 30 -path_num 1 -file paths.rpt; write_verilog routed.v} msg]} {puts stderr $msg;exit 1}
puts "COLOR_TIMING_DONE"
exit 0
