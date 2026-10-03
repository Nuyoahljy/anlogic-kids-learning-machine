onerror {quit -force -code 1}
onbreak {resume}
set repo [file normalize [file join [file dirname [info script]] ../../..]]
if {![info exists testcase]} {set testcase display}
if {![info exists negative]} {set negative 0}
set runid "$testcase-$negative-[clock format [clock seconds] -format %Y%m%d-%H%M%S]-[pid]"
set output [file join $repo evidence sc520-color-mask sim-runs $runid]
if {[info exists sim_output]} {set output [file normalize $sim_output]}
file mkdir $output
cd $output
transcript file transcript.log
vmap -c
vlib work
vmap work work
set hdl [file join $repo fpga custom_project sc520-color-mask user_source hdl_source]
vlog [file join $hdl roi pixel_coord_adapter.v] [file join $hdl roi rgb_color_segment.v] [file join $hdl roi hdmi_color_mask.v]
vlog [file join $hdl vtc uivtc.v] [file join $hdl hdmi_mixer.v]
vlog -sv +incdir+[file join $repo fpga sim sc520-color-mask] [file join $repo fpga sim sc520-color-mask tb_$testcase.sv]
set extra {}
if {$negative} {lappend extra +negative_control}
vsim -voptargs=+acc -wlf summary.wlf work.tb_$testcase {*}$extra
log /tb_$testcase/test_done /tb_$testcase/errors
run 150 ms
set done [examine -radix unsigned /tb_$testcase/test_done]
set errors [examine -radix decimal /tb_$testcase/errors]
puts "SIM_SUMMARY testcase=$testcase negative=$negative done=$done errors=$errors"
set summary [open summary.json w]
puts $summary [format {{"testcase":"%s","negative":%d,"done":%d,"errors":%d}} $testcase $negative $done $errors]
close $summary
if {$done != 1 || $errors != 0} {quit -force -code 1}
quit -force -code 0
