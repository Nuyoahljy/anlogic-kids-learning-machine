onerror {quit -force -code 2}
onbreak {resume}
vlib work
vmap work work
vlog {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/scl-coverage/ce-tests-negative-20261014-203926-072d7d3a/inputs/uii2c.v}
vlog -sv {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/scl-coverage/ce-tests-negative-20261014-203926-072d7d3a/inputs/tb_pixel14_i2c_ce.sv}
vsim -voptargs=+acc -wlf wave.wlf work.tb_pixel14_i2c_ce +CHECKER_NEGATIVE=1
onfinish stop
run -all
set fd [open summary.json w]
set pieces [list]
set errors [examine -radix unsigned /tb_pixel14_i2c_ce/errors]
lappend pieces "\"errors\":$errors"
set checks [examine -radix unsigned /tb_pixel14_i2c_ce/checks]
lappend pieces "\"checks\":$checks"
set test_done [examine -radix unsigned /tb_pixel14_i2c_ce/test_done]
lappend pieces "\"test_done\":$test_done"
set injected [examine -radix unsigned /tb_pixel14_i2c_ce/injected]
lappend pieces "\"injected\":$injected"
set cases [examine -radix unsigned /tb_pixel14_i2c_ce/cases]
lappend pieces "\"cases\":$cases"
set phase_cases [examine -radix unsigned /tb_pixel14_i2c_ce/phase_cases]
lappend pieces "\"phase_cases\":$phase_cases"
set same_edge_cases [examine -radix unsigned /tb_pixel14_i2c_ce/same_edge_cases]
lappend pieces "\"same_edge_cases\":$same_edge_cases"
set completed_transactions [examine -radix unsigned /tb_pixel14_i2c_ce/completed_transactions]
lappend pieces "\"completed_transactions\":$completed_transactions"
set abort_cases [examine -radix unsigned /tb_pixel14_i2c_ce/abort_cases]
lappend pieces "\"abort_cases\":$abort_cases"
set stuck_cases [examine -radix unsigned /tb_pixel14_i2c_ce/stuck_cases]
lappend pieces "\"stuck_cases\":$stuck_cases"
set external_slave_clears [examine -radix unsigned /tb_pixel14_i2c_ce/external_slave_clears]
lappend pieces "\"external_slave_clears\":$external_slave_clears"
set reset_assertions [examine -radix unsigned /tb_pixel14_i2c_ce/reset_assertions]
lappend pieces "\"reset_assertions\":$reset_assertions"
set reset_release_offsets [examine -radix unsigned /tb_pixel14_i2c_ce/reset_release_offsets]
lappend pieces "\"reset_release_offsets\":$reset_release_offsets"
set request_phase_coverage [examine -radix unsigned /tb_pixel14_i2c_ce/request_phase_coverage]
lappend pieces "\"request_phase_coverage\":$request_phase_coverage"
set same_edge_phase_coverage [examine -radix unsigned /tb_pixel14_i2c_ce/same_edge_phase_coverage]
lappend pieces "\"same_edge_phase_coverage\":$same_edge_phase_coverage"
set starts [examine -radix unsigned /tb_pixel14_i2c_ce/starts]
lappend pieces "\"starts\":$starts"
set repeated_starts [examine -radix unsigned /tb_pixel14_i2c_ce/repeated_starts]
lappend pieces "\"repeated_starts\":$repeated_starts"
set stops [examine -radix unsigned /tb_pixel14_i2c_ce/stops]
lappend pieces "\"stops\":$stops"
set rx_bytes [examine -radix unsigned /tb_pixel14_i2c_ce/rx_bytes]
lappend pieces "\"rx_bytes\":$rx_bytes"
set tx_bytes [examine -radix unsigned /tb_pixel14_i2c_ce/tx_bytes]
lappend pieces "\"tx_bytes\":$tx_bytes"
set ack_count [examine -radix unsigned /tb_pixel14_i2c_ce/ack_count]
lappend pieces "\"ack_count\":$ack_count"
set master_nacks [examine -radix unsigned /tb_pixel14_i2c_ce/master_nacks]
lappend pieces "\"master_nacks\":$master_nacks"
set busy_requests [examine -radix unsigned /tb_pixel14_i2c_ce/busy_requests]
lappend pieces "\"busy_requests\":$busy_requests"
set payload_mutations [examine -radix unsigned /tb_pixel14_i2c_ce/payload_mutations]
lappend pieces "\"payload_mutations\":$payload_mutations"
set high_checks [examine -radix unsigned /tb_pixel14_i2c_ce/high_checks]
lappend pieces "\"high_checks\":$high_checks"
set low_checks [examine -radix unsigned /tb_pixel14_i2c_ce/low_checks]
lappend pieces "\"low_checks\":$low_checks"
set setup_checks [examine -radix unsigned /tb_pixel14_i2c_ce/setup_checks]
lappend pieces "\"setup_checks\":$setup_checks"
set hold_checks [examine -radix unsigned /tb_pixel14_i2c_ce/hold_checks]
lappend pieces "\"hold_checks\":$hold_checks"
set start_hold_checks [examine -radix unsigned /tb_pixel14_i2c_ce/start_hold_checks]
lappend pieces "\"start_hold_checks\":$start_hold_checks"
set restart_setup_checks [examine -radix unsigned /tb_pixel14_i2c_ce/restart_setup_checks]
lappend pieces "\"restart_setup_checks\":$restart_setup_checks"
set stop_setup_checks [examine -radix unsigned /tb_pixel14_i2c_ce/stop_setup_checks]
lappend pieces "\"stop_setup_checks\":$stop_setup_checks"
set min_high_ns [examine -radix unsigned /tb_pixel14_i2c_ce/min_high_ns]
lappend pieces "\"min_high_ns\":$min_high_ns"
set min_low_ns [examine -radix unsigned /tb_pixel14_i2c_ce/min_low_ns]
lappend pieces "\"min_low_ns\":$min_low_ns"
set min_setup_ns [examine -radix unsigned /tb_pixel14_i2c_ce/min_setup_ns]
lappend pieces "\"min_setup_ns\":$min_setup_ns"
set min_hold_ns [examine -radix unsigned /tb_pixel14_i2c_ce/min_hold_ns]
lappend pieces "\"min_hold_ns\":$min_hold_ns"
set max_data_valid_ns [examine -radix unsigned /tb_pixel14_i2c_ce/max_data_valid_ns]
lappend pieces "\"max_data_valid_ns\":$max_data_valid_ns"
set min_start_hold_ns [examine -radix unsigned /tb_pixel14_i2c_ce/min_start_hold_ns]
lappend pieces "\"min_start_hold_ns\":$min_start_hold_ns"
set min_restart_setup_ns [examine -radix unsigned /tb_pixel14_i2c_ce/min_restart_setup_ns]
lappend pieces "\"min_restart_setup_ns\":$min_restart_setup_ns"
set min_stop_setup_ns [examine -radix unsigned /tb_pixel14_i2c_ce/min_stop_setup_ns]
lappend pieces "\"min_stop_setup_ns\":$min_stop_setup_ns"
set min_bus_free_ns [examine -radix unsigned /tb_pixel14_i2c_ce/min_bus_free_ns]
lappend pieces "\"min_bus_free_ns\":$min_bus_free_ns"
set min_accept_cycles [examine -radix unsigned /tb_pixel14_i2c_ce/min_accept_cycles]
lappend pieces "\"min_accept_cycles\":$min_accept_cycles"
set max_accept_cycles [examine -radix unsigned /tb_pixel14_i2c_ce/max_accept_cycles]
lappend pieces "\"max_accept_cycles\":$max_accept_cycles"
puts $fd "{[join $pieces ,]}"
close $fd
if {!$test_done} {quit -force -code 2}
if {$errors != 0} {quit -force -code 1}
quit -force -code 0
