onerror {quit -force -code 2}
vlib work
vmap work work
vlog al_phy_glbl.v al_map_seq.v al_map_lut.v ph1p_phy_gsr.v ph1p_phy_lslice.v ph1p_phy_sclk_v2.v
vlog -sv tb_duplicate_q.sv
vsim -voptargs=+acc -wlf wave.wlf work.tb_duplicate_q work.PH1P_PHY_GSR work.glbl
onfinish stop
run -all
set errors [examine -radix decimal /tb_duplicate_q/errors]
set checks [examine -radix decimal /tb_duplicate_q/checks]
set rows [examine -radix decimal /tb_duplicate_q/rows]
set comb_rows [examine -radix decimal /tb_duplicate_q/comb_rows]
set done [examine -radix unsigned /tb_duplicate_q/test_done]
set fd [open summary.json w]
puts $fd [format {{"errors":%d,"checks":%d,"rows":%d,"comb_rows":%d,"done":%d}} $errors $checks $rows $comb_rows $done]
close $fd
if {!$done} {quit -force -code 2}
if {$errors} {quit -force -code 1}
quit -force -code 0
