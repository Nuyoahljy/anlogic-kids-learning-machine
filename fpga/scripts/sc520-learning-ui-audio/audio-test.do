onerror {quit -force -code 1}
onbreak {resume}
set repo [file normalize [file join [file dirname [info script]] ../../..]]
if {![info exists negative]} {set negative 0}
if {![info exists sim_output]} {error "audio-test.do requires isolated sim_output"}
set output [file normalize $sim_output]
file mkdir $output
cd $output
transcript file transcript.log
if {[catch {
    vmap -c
    vlib work
    vmap work work
    set hdl [file join $repo fpga custom_project sc520-learning-ui-audio user_source hdl_source learning]
    vlog [file join $hdl audio_event_player.v] [file join $hdl mock_audio_player.v]
    vlog -sv [file join $repo fpga sim sc520-learning-ui-audio tb_audio.sv]
    set extra {}
    if {$negative} {lappend extra +negative_control}
    vsim -voptargs=+acc -wlf audio.wlf work.tb_audio {*}$extra
    log -r /tb_audio/*
    run 200 us
    set done [examine -radix unsigned /tb_audio/test_done]
    set errors [examine -radix unsigned /tb_audio/errors]
    set checks [examine -radix unsigned /tb_audio/checks]
    set cases [examine -radix unsigned /tb_audio/cases]
    set sum [open summary.json w]
    puts $sum [format {{"testcase":"audio","negative":%d,"done":%d,"errors":%d,"checks":%d,"cases":%d}} $negative $done $errors $checks $cases]
    close $sum
    puts "AUDIO_SUMMARY negative=$negative done=$done errors=$errors checks=$checks cases=$cases"
    if {$done != 1 || $errors != 0} {error "Audio self-check failed"}
} failure]} {
    puts "AUDIO_ERROR $failure"
    quit -force -code 1
}
quit -force -code 0
