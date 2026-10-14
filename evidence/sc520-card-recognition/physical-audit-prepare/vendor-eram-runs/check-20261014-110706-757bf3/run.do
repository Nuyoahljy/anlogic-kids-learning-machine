onerror {quit -force -code 2}
vlib work
vmap work work
vlog ph1p_phy_gsr.v ph1p_phy_eram_v2.v
vlog -sv tb_vendor_eram.sv
vsim -voptargs=+acc -wlf wave.wlf work.tb_vendor_eram work.PH1P_PHY_GSR
onfinish stop
run -all
set errors [examine -radix decimal /tb_vendor_eram/errors]
set checks [examine -radix decimal /tb_vendor_eram/checks]
set done [examine -radix unsigned /tb_vendor_eram/test_done]
set f [open summary.json w]
puts $f [format {{"errors":%d,"checks":%d,"done":%d}} $errors $checks $done]
close $f
if {!$done} {quit -force -code 2}
if {$errors} {quit -force -code 1}
quit -force -code 0
