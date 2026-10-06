onerror {quit -force -code 1}
onbreak {resume}
set repo [file normalize [file join [file dirname [info script]] ../../..]]
if {![info exists negative]} {set negative 0}
if {![info exists sim_output]} {error "sim_output must be an independent run directory"}
file mkdir $sim_output
cd $sim_output
transcript file transcript.log
vmap -c
vlib work
vmap work work
set hdl [file join $repo fpga custom_project sc520-learning-ui-audio user_source hdl_source learning]
vlog [file join $hdl detection_adapter.v] [file join $hdl learning_events.v]
vlog -sv [file join $repo fpga sim sc520-learning-ui-audio tb_events.sv]
set extra {}
if {$negative} {lappend extra +negative_control}
vsim -voptargs=+acc -wlf events.wlf work.tb_events {*}$extra
log /tb_events/test_done /tb_events/errors /tb_events/ae /tb_events/cp /tb_events/di /tb_events/ai
run 100 us
set done [examine -radix unsigned /tb_events/test_done]
set errors [examine -radix unsigned /tb_events/errors]
set fields {}
foreach name {checks adapter_cases event_cases parameter_cases mapping_mask auto_events replay_events cancel_events} {
    lappend fields [format {"%s":%s} $name [examine -radix unsigned /tb_events/$name]]
}
set summary [open summary.json w]
puts $summary [format {{"testcase":"events","negative":%d,"done":%d,"errors":%d,%s}} $negative $done $errors [join $fields ,]]
close $summary
puts "SIM_SUMMARY testcase=events negative=$negative done=$done errors=$errors"
if {$done != 1 || $errors != 0} {quit -force -code 1}
quit -force -code 0
