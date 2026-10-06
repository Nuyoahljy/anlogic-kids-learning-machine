onerror {quit -force -code 2}
onbreak {resume}
set names(control) {quiz_control}
set names(audio) {quiz_audio_queue}
set names(keys) {quiz_key_debounce}
set names(system) {quiz_control quiz_audio_queue}
set tops(control) tb_quiz_control
set tops(audio) tb_quiz_audio_queue
set tops(keys) tb_quiz_key_debounce
set tops(system) tb_quiz_system
set top $tops($quiz_test)
vlib work
vmap work work
foreach module $names($quiz_test) {
    vlog -sv "$quiz_root/fpga/custom_project/sc520-quiz-control/$module.v"
}
vlog -sv "$quiz_root/fpga/sim/sc520-quiz-control/$top.sv"
set extra {}
if {$quiz_negative} {lappend extra +NEGATIVE}
vsim -voptargs=+acc -wlf wave.wlf work.$top {*}$extra +TRACE=trace.csv
onfinish stop
log -r /*
run -all
set done [examine -radix unsigned /$top/test_done]
set errors [examine -radix decimal /$top/errors]
set checks [examine -radix decimal /$top/checks]
set fd [open summary.json w]
puts $fd "{\"testcase\":\"$quiz_test\",\"negative\":$quiz_negative,\"done\":$done,\"errors\":$errors,\"checks\":$checks}"
close $fd
if {$done != 1 || $errors != 0} {quit -force -code 1}
quit -force -code 0
