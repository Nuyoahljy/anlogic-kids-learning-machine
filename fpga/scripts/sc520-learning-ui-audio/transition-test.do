onerror {quit -force -code 1}
onbreak {resume}
set repo [file normalize [file join [file dirname [info script]] ../../..]]
if {![info exists sim_output]} {error "sim_output required"}
file mkdir $sim_output
cd $sim_output
transcript file transcript.log
vmap -c
vlib work
vmap work work
set hdl [file join $repo fpga custom_project sc520-learning-ui-audio user_source hdl_source]
foreach name {pixel_coord_adapter rgb_color_segment shape_classifier shape_confirm color_bbox_stats bbox_stabilizer demo_sequence demo_pattern osd_font_rom chinese_osd} {
    vlog [file join $hdl roi $name.v]
}
vlog {*}[glob [file join $hdl learning *.v]]
vlog -sv [file join $repo fpga sim sc520-learning-ui-audio tb_transition.sv]
vsim -voptargs=+acc -wlf transition.wlf work.tb_transition
log /tb_transition/test_done /tb_transition/errors /tb_transition/camera_frame /tb_transition/dut/audio_event /tb_transition/dut/audio_item /tb_transition/dut/cancel_audio /tb_transition/dut/display_item /tb_transition/dut/candidate_valid /tb_transition/dut/box_valid
run 40 ms
set done [examine -radix unsigned /tb_transition/test_done]
set errors [examine -radix unsigned /tb_transition/errors]
set fields {}
foreach name {checks frames checked_pixels checked_cycles auto_events cancel_events mapping_checks bbox_checks} {
    lappend fields [format {"%s":%s} $name [examine -radix unsigned /tb_transition/$name]]
}
set summary [open summary.json w]
puts $summary [format {{"testcase":"transition","done":%d,"errors":%d,%s}} $done $errors [join $fields ,]]
close $summary
puts "SIM_SUMMARY testcase=transition done=$done errors=$errors"
if {$done!=1 || $errors!=0} {quit -force -code 1}
quit -force -code 0
