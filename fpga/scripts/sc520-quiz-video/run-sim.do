onerror {quit -force -code 2}
onbreak {resume}
if {[catch {
vlib work
vmap work work
foreach src $quiz_sources {vlog $src}
vlog -sv +incdir+$quiz_root/fpga/sim/sc520-quiz-video $quiz_root/fpga/sim/sc520-quiz-video/$quiz_top.sv
set extra {}
if {$quiz_negative} {lappend extra +NEGATIVE}
if {$quiz_top eq "tb_quiz_video"} {lappend extra -gFULL=$quiz_full}
vsim -voptargs=+acc -wlf wave.wlf work.$quiz_top {*}$extra
onfinish stop
log /$quiz_top/test_done /$quiz_top/errors /$quiz_top/checks
if {$quiz_top eq "tb_quiz_video"} {
    log /$quiz_top/dut/mode /$quiz_top/dut/phase /$quiz_top/dut/score /$quiz_top/dut/question_index /$quiz_top/dut/target_item /$quiz_top/dut/det_update /$quiz_top/dut/det_valid /$quiz_top/dut/det_item /$quiz_top/dut/armed /$quiz_top/dut/audio_fault /$quiz_top/dut/answer_valid /$quiz_top/dut/answer_correct /$quiz_top/dut/osd_score /$quiz_top/dut/osd_feedback
}
run -all
set done [examine -radix unsigned /$quiz_top/test_done]
set errors [examine -radix decimal /$quiz_top/errors]
set checks [examine -radix decimal /$quiz_top/checks]
set fd [open summary.json w]
puts $fd "{\"testcase\":\"$quiz_test\",\"negative\":$quiz_negative,\"done\":$done,\"errors\":$errors,\"checks\":$checks}"
close $fd
} quiz_error]} {
    puts stderr "QUIZ_SIM_FAILURE: $quiz_error"
    quit -force -code 2
}
if {$done != 1 || $errors != 0} {quit -force -code 1}
quit -force -code 0
