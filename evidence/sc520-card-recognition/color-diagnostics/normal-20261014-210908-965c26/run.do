onerror {quit -force -code 2}
onbreak {resume}
vlib work
vmap work work
vlog -sv {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/color-diagnostics/normal-20261014-210908-965c26/inputs/pixel14_color_diagnostics.v} {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/color-diagnostics/normal-20261014-210908-965c26/inputs/tb_pixel14_color_diagnostics.sv}
vsim -voptargs=+acc work.tb_pixel14_color_diagnostics +INJECT_FAULT=0
onfinish stop
run -all
set errors [examine -radix unsigned /tb_pixel14_color_diagnostics/errors]
set checks [examine -radix unsigned /tb_pixel14_color_diagnostics/checks]
set scenarios [examine -radix unsigned /tb_pixel14_color_diagnostics/scenarios]
set injected [examine -radix unsigned /tb_pixel14_color_diagnostics/injected]
set test_done [examine -radix unsigned /tb_pixel14_color_diagnostics/test_done]
set fd [open summary.json w]
puts $fd [format {{"errors":%d,"checks":%d,"scenarios":%d,"injected":%d,"done":%d}} $errors $checks $scenarios $injected $test_done]
close $fd
if {!$test_done} {quit -force -code 2}
if {$errors} {quit -force -code 1}
quit -force -code 0
