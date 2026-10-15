onerror {quit -force -code 2}
onbreak {resume}
if {[catch {
    foreach name {anlogic_logo_index.mem anlogic_logo_palette.mem} {file copy [file join $card_assets $name] $name}
    vlib work
    vmap work work
    vlog {*}$card_sources
    vlog -sv +incdir+$card_assets $card_tb
    vsim -voptargs=+acc -wlf wave.wlf work.$card_top +ASSET_ROOT=$card_assets +INJECT_FAULT=$card_negative
    onfinish stop
    if {$card_probe} {run 500 ns} else {run -all}
} failure]} {
    puts stderr "CARD_SIM_ERROR: $failure"
    quit -force -code 2
}
if {[catch {
    set errors [examine -radix decimal /$card_top/errors]
    set checks [examine -radix decimal /$card_top/checks]
    set scenarios [examine -radix decimal /$card_top/scenarios]
    set done [examine -radix unsigned /$card_top/test_done]
    set injected 0
    catch {set injected [examine -radix decimal /$card_top/injected]}
    set fd [open summary.json w]
    puts $fd [format {{"errors":%d,"checks":%d,"scenarios":%d,"done":%d,"injected":%d}} $errors $checks $scenarios $done $injected]
    close $fd
} failure]} {
    puts stderr "CARD_SUMMARY_ERROR: $failure"
    quit -force -code 2
}
puts "CARD_SIM_FINISHED $card_top errors=$errors checks=$checks scenarios=$scenarios done=$done injected=$injected"
if {!$done} {quit -force -code 2}
if {$errors != 0} {quit -force -code 1}
quit -force -code 0
