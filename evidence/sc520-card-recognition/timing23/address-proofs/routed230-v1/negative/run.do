onerror {quit -force -code 3}
vlib work
vmap work work
vlog al_phy_glbl.v al_map_seq.v al_map_lut.v ph1p_phy_gsr.v ph1p_phy_lslice.v ph1p_phy_sclk_v2.v
vlog -sv tb_address.sv
vsim -voptargs=+acc -wlf wave.wlf work.tb_address work.PH1P_PHY_GSR work.glbl
onfinish stop
run 1 ms
set fd [open summary.json w]
puts $fd [format {{"errors":%d,"checks":%d,"rows":%d,"injected":%d,"done":%d}} [examine -radix decimal /tb_address/errors] [examine -radix decimal /tb_address/checks] [examine -radix decimal /tb_address/rows] [examine -radix decimal /tb_address/injected] [examine -radix unsigned /tb_address/test_done]]
close $fd
if {![examine -radix unsigned /tb_address/test_done]} {quit -force -code 2}
if {[examine -radix decimal /tb_address/errors]} {quit -force -code 1}
quit -force -code 0
