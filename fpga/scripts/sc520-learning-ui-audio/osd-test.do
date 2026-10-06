onerror {quit -force -code 1}
onbreak {resume}
set repo [file normalize [file join [file dirname [info script]] ../../..]]
if {![info exists negative]} {set negative 0}
if {![info exists sim_output]} {error "sim_output must name an isolated evidence directory"}
file mkdir $sim_output
cd $sim_output
transcript file transcript.log
vmap -c
vlib work
vmap work work
set hdl [file join $repo fpga custom_project sc520-learning-ui-audio user_source hdl_source learning]
set tests [file join $repo fpga sim sc520-learning-ui-audio]
vlog [file join $hdl learning_content.v] [file join $hdl learning_font_rom.v] [file join $hdl learning_osd.v]
vlog -sv +incdir+$tests [file join $tests tb_learning_osd.sv]
set extra {}
if {$negative} {lappend extra +negative_control}
vsim -voptargs=+acc -wlf summary.wlf work.tb_learning_osd {*}$extra
log /tb_learning_osd/test_done /tb_learning_osd/errors
run 20 ms
set done [examine -radix unsigned /tb_learning_osd/test_done]
set errors [examine -radix decimal /tb_learning_osd/errors]
set pixels [examine -radix decimal /tb_learning_osd/pixel_checks]
set content [examine -radix decimal /tb_learning_osd/content_checks]
puts "SIM_SUMMARY learning_osd negative=$negative done=$done errors=$errors content=$content pixels=$pixels"
set summary [open summary.json w]
puts $summary [format {{"testcase":"learning_osd","negative":%d,"done":%d,"errors":%d,"content_checks":%d,"pixel_checks":%d}} $negative $done $errors $content $pixels]
close $summary
if {$done != 1 || $errors != 0} {quit -force -code 1}
quit -force -code 0
