onerror {quit -force -code 2}
onbreak {resume}
if {[catch {
vlib work
vmap work work
vlog {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/runs/scene-normal-20261014-102149-40fb234d/inputs/pixel14_scene_preprocess.v}
vlog -sv {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/runs/scene-normal-20261014-102149-40fb234d/inputs/tb_pixel14_scene.sv}
vsim -voptargs=+acc -wlf wave.wlf work.tb_pixel14_scene -gNORMAL_SIZE=20 +ASSET_ROOT=E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/runs/scene-normal-20261014-102149-40fb234d/inputs +INJECT_FAULT=0
onfinish stop
run -all
} failure]} {puts stderr $failure; quit -force -code 2}
set fd [open summary.json w]
puts $fd [format {{"errors":%d,"checks":%d,"scenarios":%d,"done":%d,"injected":%d,"max_latency":%d,"max_single_latency":%d,"fixtures":%d}} [examine -radix decimal /tb_pixel14_scene/errors] [examine -radix decimal /tb_pixel14_scene/checks] [examine -radix decimal /tb_pixel14_scene/scenarios] [examine -radix unsigned /tb_pixel14_scene/test_done] [examine -radix decimal /tb_pixel14_scene/injected] [examine -radix decimal /tb_pixel14_scene/max_latency] [examine -radix decimal /tb_pixel14_scene/max_single_latency] [examine -radix decimal /tb_pixel14_scene/fixture_count]]
close $fd
if {![examine -radix unsigned /tb_pixel14_scene/test_done]} {quit -force -code 2}
if {[examine -radix decimal /tb_pixel14_scene/errors] != 0} {quit -force -code 1}
quit -force -code 0
