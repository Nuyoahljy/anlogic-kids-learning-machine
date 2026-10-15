onerror {quit -force -code 2}
onbreak {resume}
vlib work
vmap work work
vlog -sv {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/color-contract/watchdog-20261014-204420-a66a57/inputs/pixel14_color_pipeline.v} {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/color-contract/watchdog-20261014-204420-a66a57/inputs/block_frame_recognizer.v} {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/color-contract/watchdog-20261014-204420-a66a57/inputs/signal_delay.v} {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/color-contract/watchdog-20261014-204420-a66a57/inputs/ip_behavioral_models.sv} {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/color-contract/watchdog-20261014-204420-a66a57/inputs/tb_pixel14_color_contract.sv}
vsim -voptargs=+acc work.tb_pixel14_color_contract +INJECT_FAULT=0
onfinish stop
run 500 ns
set e [examine -radix decimal /tb_pixel14_color_contract/errors]
set n [examine -radix decimal /tb_pixel14_color_contract/checks]
set d [examine -radix unsigned /tb_pixel14_color_contract/test_done]
set i [examine -radix decimal /tb_pixel14_color_contract/injected]
set fd [open summary.json w]
puts $fd [format {{"errors":%d,"checks":%d,"done":%d,"injected":%d}} $e $n $d $i]
close $fd
if {!$d} {quit -force -code 2}
if {$e} {quit -force -code 1}
quit -force -code 0
