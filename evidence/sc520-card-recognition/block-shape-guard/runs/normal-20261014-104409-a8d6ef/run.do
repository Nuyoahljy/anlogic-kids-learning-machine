onerror {quit -force -code 2}
vlib work
vmap work work
vlog inputs/pixel14_block_shape_guard.v
vlog -sv inputs/tb_block_shape_guard.sv
vsim -voptargs=+acc -wlf wave.wlf work.tb_block_shape_guard +INJECT_FAULT=0
onfinish stop
run -all
set errors [examine -radix decimal /tb_block_shape_guard/errors]
set checks [examine -radix decimal /tb_block_shape_guard/checks]
set scenarios [examine -radix decimal /tb_block_shape_guard/scenarios]
set done [examine -radix unsigned /tb_block_shape_guard/test_done]
set injected [examine -radix decimal /tb_block_shape_guard/injected]
set f [open summary.json w]
puts $f [format {{"errors":%d,"checks":%d,"scenarios":%d,"done":%d,"injected":%d}} $errors $checks $scenarios $done $injected]
close $f
if {!$done} {quit -force -code 2}
if {$errors != 0} {quit -force -code 1}
quit -force -code 0
