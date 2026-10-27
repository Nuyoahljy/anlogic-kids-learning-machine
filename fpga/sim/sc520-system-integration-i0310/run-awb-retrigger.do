onerror {quit -code 1}
if {[file exists work]} {vdel -lib work -all}
vlib work
vlog -sv ../../rtl/sc520-system-integration-i0310/pixel310_awb_retrigger.v tb_pixel310_awb_retrigger.sv
vsim -c work.tb_pixel310_awb_retrigger
run -all
quit -code 0
