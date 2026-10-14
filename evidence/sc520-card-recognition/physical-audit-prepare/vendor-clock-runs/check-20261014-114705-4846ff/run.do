onerror {quit -force -code 2}
vlib work
vmap work work
vlog ph1p_phy_gsr.v ph1p_phy_gclk.v ph1p_phy_sclk_v2.v
vlog -sv tb_vendor_clocks.sv
vsim -voptargs=+acc -wlf wave.wlf work.tb_vendor_clocks work.PH1P_PHY_GSR
onfinish stop
run -all
set errors [examine -radix decimal /tb_vendor_clocks/errors]
set checks [examine -radix decimal /tb_vendor_clocks/checks]
set done [examine -radix unsigned /tb_vendor_clocks/test_done]
set fd [open summary.json w]
puts $fd [format {{"errors":%d,"checks":%d,"done":%d}} $errors $checks $done]
close $fd
if {!$done} {quit -force -code 2}
if {$errors} {quit -force -code 1}
quit -force -code 0
