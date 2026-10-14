onerror {quit -force -code 2}
vlib work
vmap work work
vlog -sv inputs/awb.v inputs/signal_delay.v inputs/pixel14_color_pipeline.v inputs/ip_behavioral_models.sv inputs/tb_color_pipeline.sv
vsim -voptargs=+acc -wlf wave.wlf work.tb_color_pipeline -gFULL=1 +INJECT_FAULT=0
onfinish stop
run -all
set errors [examine -radix decimal /tb_color_pipeline/errors]
set checks [examine -radix decimal /tb_color_pipeline/checks]
set scenarios [examine -radix decimal /tb_color_pipeline/scenarios]
set done [examine -radix unsigned /tb_color_pipeline/test_done]
set injected [examine -radix decimal /tb_color_pipeline/injected]
set f [open summary.json w]
puts $f [format {{"errors":%d,"checks":%d,"scenarios":%d,"done":%d,"injected":%d}} $errors $checks $scenarios $done $injected]
close $f
if {!$done} {quit -force -code 2}
if {$errors != 0} {quit -force -code 1}
quit -force -code 0
