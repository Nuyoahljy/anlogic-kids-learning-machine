onerror {quit -force -code 2}
onbreak {resume}
vlib work
vmap work work
vlog {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/i2c-runs/ae-nack-20261013-193700-0327be28/inputs/uicfgcs520.v} {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/i2c-runs/ae-nack-20261013-193700-0327be28/inputs/uii2c.v} {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/i2c-runs/ae-nack-20261013-193700-0327be28/inputs/uics520reg_720p60.v} {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/i2c-runs/ae-nack-20261013-193700-0327be28/inputs/uics520regAE.v} {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/i2c-runs/ae-nack-20261013-193700-0327be28/inputs/SC520GainTbl.v}
vlog -sv {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/evidence/sc520-card-recognition/i2c-runs/ae-nack-20261013-193700-0327be28/inputs/tb_pixel14_i2c.sv}
vsim -voptargs=+acc -wlf wave.wlf work.tb_pixel14_i2c -gCLK_DIV=23 +MODE=3 +EXPECT_RECOVERY=0 +CHECKER_NEGATIVE=0
onfinish stop
run -all
set fd [open summary.json w]
set pieces [list]
set errors [examine -radix unsigned /tb_pixel14_i2c/errors]
lappend pieces "\"errors\":$errors"
set checks [examine -radix unsigned /tb_pixel14_i2c/checks]
lappend pieces "\"checks\":$checks"
set test_done [examine -radix unsigned /tb_pixel14_i2c/test_done]
lappend pieces "\"test_done\":$test_done"
set rx_bytes [examine -radix unsigned /tb_pixel14_i2c/rx_bytes]
lappend pieces "\"rx_bytes\":$rx_bytes"
set tx_bytes [examine -radix unsigned /tb_pixel14_i2c/tx_bytes]
lappend pieces "\"tx_bytes\":$tx_bytes"
set ack_count [examine -radix unsigned /tb_pixel14_i2c/ack_count]
lappend pieces "\"ack_count\":$ack_count"
set nack_count [examine -radix unsigned /tb_pixel14_i2c/nack_count]
lappend pieces "\"nack_count\":$nack_count"
set master_nacks [examine -radix unsigned /tb_pixel14_i2c/master_nacks]
lappend pieces "\"master_nacks\":$master_nacks"
set init_writes [examine -radix unsigned /tb_pixel14_i2c/init_writes]
lappend pieces "\"init_writes\":$init_writes"
set ae_writes [examine -radix unsigned /tb_pixel14_i2c/ae_writes]
lappend pieces "\"ae_writes\":$ae_writes"
set injected [examine -radix unsigned /tb_pixel14_i2c/injected]
lappend pieces "\"injected\":$injected"
set sticky_seen [examine -radix unsigned /tb_pixel14_i2c/sticky_seen]
lappend pieces "\"sticky_seen\":$sticky_seen"
set reset_gap_cycles [examine -radix unsigned /tb_pixel14_i2c/reset_gap_cycles]
lappend pieces "\"reset_gap_cycles\":$reset_gap_cycles"
set cfg_done [examine -radix unsigned /tb_pixel14_i2c/cfg_done]
lappend pieces "\"cfg_done\":$cfg_done"
set ae_done [examine -radix unsigned /tb_pixel14_i2c/ae_done]
lappend pieces "\"ae_done\":$ae_done"
set iic_error [examine -radix unsigned /tb_pixel14_i2c/iic_error]
lappend pieces "\"iic_error\":$iic_error"
set sensor_id [examine -radix unsigned /tb_pixel14_i2c/sensor_id]
lappend pieces "\"sensor_id\":$sensor_id"
set starts [examine -radix unsigned /tb_pixel14_i2c/starts]
lappend pieces "\"starts\":$starts"
set stops [examine -radix unsigned /tb_pixel14_i2c/stops]
lappend pieces "\"stops\":$stops"
set write_count [examine -radix unsigned /tb_pixel14_i2c/write_count]
lappend pieces "\"write_count\":$write_count"
set accepted_writes [examine -radix unsigned /tb_pixel14_i2c/accepted_writes]
lappend pieces "\"accepted_writes\":$accepted_writes"
puts $fd "{[join $pieces ,]}"
close $fd
if {!$test_done} {quit -force -code 2}
if {$errors != 0} {quit -force -code 1}
quit -force -code 0
