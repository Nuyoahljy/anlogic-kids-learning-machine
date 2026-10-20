# Invoked after opt_route and original timing reports; bitgen forbidden, on the same routed netlist.
# No export_db, route, optimize, or bitgen after this diagnostic constraint view.
set saved_cwd [pwd]
if {![info exists analysis_dir]} {set analysis_dir [file normalize ../../../analysis]}
file mkdir $analysis_dir
cd $analysis_dir
set reset_source [get_regs {u_p14_pipeline/capture_reset[0]}]
if {[llength $reset_source]!=1} {error "T023 reset first stage missing"}
set reset_second [list {u_p14_pipeline/capture_reset[1]}]
for {set i 0} {$i<9} {incr i} {lappend reset_second [format {u_p14_pipeline/capture_release[%d]} $i]}
set reset_fd [open reset23-objects.txt w]
puts $reset_fd "FROM $reset_source"
set index 0
foreach name $reset_second {
    set destination [get_regs $name]
    if {[llength $destination]!=1} {error "T023 reset second stage missing: $name"}
    puts $reset_fd "TO $destination"
    report_timing_path -from $reset_source -to $destination -ep_num 1 -path_num 1 -file "reset23-${index}.rpt"
    report_timing_path -from $destination -ep_num 12000 -path_num 2 -file "reset23-${index}-outbound.rpt"
    incr index
}
close $reset_fd
foreach direction {forward backward} {
    foreach signal {req ack fault} {
        set start "u_p14_pipeline/${direction}/${signal}_meta"
        set finish "u_p14_pipeline/${direction}/${signal}_sync"
        if {$signal eq "fault" && [llength [get_regs $start]]==0 && [llength [get_regs $finish]]==0} {
            puts "PIXEL14_CDC_OPTIMIZED_CONSTANT $direction fault"
            continue
        }
        if {[llength [get_regs $start]] != 1 || [llength [get_regs $finish]] != 1} {error "CDC register resolution failed: $start $finish"}
        report_timing_path -from [get_regs $start] -to [get_regs $finish] -ep_num 1 -path_num 1 -file "${direction}-${signal}.rpt"
    }
}
foreach mailbox {{u_p14_diag_cdc diagnostic} {u_p14_i2c_cdc i2c}} {
    lassign $mailbox instance name
    foreach signal {req ack} {
        set start "${instance}/${signal}_meta"
        set finish "${instance}/${signal}_sync"
        if {[llength [get_regs $start]] != 1 || [llength [get_regs $finish]] != 1} {error "Mailbox CDC register resolution failed: $start $finish"}
        report_timing_path -from [get_regs $start] -to [get_regs $finish] -ep_num 1 -path_num 1 -file "${name}-${signal}.rpt"
    }
}
foreach pair {{u_p14_pipeline/staging_fault_meta u_p14_pipeline/staging_fault_sync staging-fault} {S_p14_cfg_done[0] S_p14_cfg_done[1] config-done} {S_p14_cfg_error[0] S_p14_cfg_error[1] config-error} {u_uicfgcs520/busy_meta u_uicfgcs520/busy_sync i2c-busy} {u_uicfgcs520/error_meta u_uicfgcs520/error_sync i2c-error}} {
    lassign $pair start finish name
    if {[llength [get_regs $start]] != 1 || [llength [get_regs $finish]] != 1} {error "CDC register resolution failed: $start $finish"}
    report_timing_path -from [get_regs $start] -to [get_regs $finish] -ep_num 1 -path_num 1 -file "${name}.rpt"
}
for {set i 0} {$i<4} {incr i} {
    set start [format {u_quiz_keys/keys_sync_meta[%d]} $i]
    set finish [format {u_quiz_keys/keys_sync_safe[%d]} $i]
    report_timing_path -from [get_regs $start] -to [get_regs $finish] -ep_num 1 -path_num 1 -file "key-${i}.rpt"
}
# Additional T-018 synchronizers and all I2C input/output/reset path classes.
foreach pair {{{u_uicfgcs520/u_i2c/reset_pipe[0]} {u_uicfgcs520/u_i2c/reset_pipe[1]} i2c-reset} {u_uicfgcs520/u_i2c/sda_meta u_uicfgcs520/u_i2c/sda_sync i2c-sda}} {
    lassign $pair start finish name
    if {[llength [get_regs $start]]!=1 || [llength [get_regs $finish]]!=1} {error "I2C synchronization register missing: $start $finish"}
    report_timing_path -from [get_regs $start] -to [get_regs $finish] -ep_num 1 -path_num 1 -file "${name}.rpt"
}
set i2c_regs [get_regs {u_uicfgcs520/u_i2c/*}]
if {[llength $i2c_regs]<20} {error "I2C register enumeration unexpectedly empty"}
set fd [open i2c-core-objects.txt w];puts $fd $i2c_regs;close $fd
report_timing_path -to $i2c_regs -ep_num 400 -path_num 2 -file i2c-core-inbound.rpt
report_timing_path -from $i2c_regs -ep_num 400 -path_num 2 -file i2c-core-outbound.rpt
foreach signal {req ack} {
    set a [get_regs "u_p14_pipeline/*transport/link/${signal}_meta"]
    set b [get_regs "u_p14_pipeline/*transport/link/${signal}_sync"]
    if {[llength $a]!=1 || [llength $b]!=1} {error "Observation synchronizer missing: $signal"}
    report_timing_path -from $a -to $b -ep_num 1 -path_num 1 -file "color-${signal}.rpt"
}
set audio_resolution [open audio-resolution.txt w]
foreach pair {{{u_a22_audio/reset_pipe[0]} {u_a22_audio/reset_pipe[1]} audio-reset}} {
    lassign $pair start finish name
    set audio_start [get_regs $start];set audio_finish [get_regs $finish]
    puts $audio_resolution "$name START $audio_start FINISH $audio_finish"
    if {[llength $audio_start]==1 && [llength $audio_finish]==1} {
        report_timing_path -from $audio_start -to $audio_finish -ep_num 1 -path_num 1 -file "${name}.rpt"
    } elseif {[llength $audio_start]==0 && [llength $audio_finish]==0} {
        puts $audio_resolution "UNRESOLVED: physical audit must prove optimization or alias; this is not qualification."
    } else {
        error "Partially resolved audio reset chain requires alias investigation"
    }
}
set audio_regs [get_regs {u_a22_audio/*}]
puts $audio_resolution "ALL_AUDIO_REGS $audio_regs"
close $audio_resolution
# Hardware profile is unconfigured; constant RX/BUSY are not asynchronous inputs.
set fd [open audio-objects.txt w];puts $fd $audio_regs;close $fd
if {[llength $audio_regs]>0} {
    report_timing_path -to $audio_regs -ep_num 6000 -path_num 2 -file audio-inbound.rpt
    report_timing_path -from $audio_regs -ep_num 6000 -path_num 2 -file audio-outbound.rpt
}
report_timing_exception -file original-exceptions.rpt
report_timing_ignored -file original-ignored.rpt
report_clock_summary -file original-clocks.rpt
set payload_from [get_regs {u_p14_pipeline/forward/held_data*}]
set payload_to [get_regs {u_p14_pipeline/forward/dst_data*}]
if {[llength $payload_from]<32 || [llength $payload_to]<32} {error "Forward CDC payload unexpectedly optimized away"}
set fd [open payload-objects.txt w]
puts $fd "FROM [llength $payload_from] $payload_from"
puts $fd "TO [llength $payload_to] $payload_to"
close $fd
# Record T027's new retained endpoints under the original routed constraints.
# A missing logical name remains an audit question: it is never a timing PASS.
set shape27_fd [open shape27-objects.txt w]
set shape27_regs [list]
foreach pattern {
    {u_p14_pipeline/*scene_mode*scene/replay_glyph*}
    {u_p14_pipeline/*glyph_color_mode*blocks/*}
    {u_p14_pipeline/*glyph_color_mode*blocks/core/glyph_area*}
    {u_p14_pipeline/*glyph_color_mode*blocks/core/area*}
    {u_p14_pipeline/*glyph_color_mode*blocks/core/selected_area*}
    {u_p14_pipeline/*glyph_color_mode*blocks/core/coverage_good*}
    {u_p14_pipeline/*guarded_block_confirmation*raw_pending*}
    {u_p14_pipeline/*guarded_block_confirmation*raw_record*}
    {u_p14_pipeline/*guarded_block_confirmation*block_confirmation/*}
    {u_p14_pipeline/*shape_mode*shape_guard/*}
} {
    set resolved [get_regs $pattern]
    puts $shape27_fd "PATTERN $pattern COUNT [llength $resolved]"
    puts $shape27_fd "REGS $resolved"
    if {[llength $resolved]==0} {
        puts $shape27_fd "UNRESOLVED: independent netlist alias/optimization proof required"
    }
    foreach object $resolved {lappend shape27_regs $object}
}
set shape27_regs [lsort -unique $shape27_regs]
puts $shape27_fd "ALL_COUNT [llength $shape27_regs]"
puts $shape27_fd "ALL_REGS $shape27_regs"
set shape27_ep_num [expr {2 * [llength $shape27_regs]}]
puts $shape27_fd "ENDPOINT_LIMIT $shape27_ep_num"
close $shape27_fd
if {[llength [get_regs {u_p14_pipeline/*glyph_color_mode*blocks/*}]]==0} {
    error "T027 color/glyph core register set missing; do not qualify empty endpoint reports"
}
report_timing_path -to $shape27_regs -ep_num $shape27_ep_num -path_num 2 -file shape27-inbound.rpt
report_timing_path -from $shape27_regs -ep_num $shape27_ep_num -path_num 2 -file shape27-outbound.rpt
# T029's added contour phases and root-held metadata under the same constraints.
set contour29_fd [open contour29-objects.txt w]
set contour29_regs [list]
foreach pattern {
    {u_p14_pipeline/*scene_mode*scene/*}
    {u_p14_pipeline/*scene_mode*scene/ct_*}
    {u_p14_pipeline/*scene_mode*scene/contour_*}
    {u_p14_pipeline/*scene_mode*scene/full_axis_fg*}
    {u_p14_pipeline/*scene_mode*scene/state*}
    {u_p14_pipeline/*shape_mode*shape_guard/*}
    {u_p14_pipeline/saved_shape*}
    {u_p14_pipeline/saved_contour_color*}
    {u_p14_pipeline/shape_pending*}
    {u_p14_pipeline/block_record*}
    {u_p14_pipeline/card_record*}
    {u_p14_pipeline/card_diagnostics*}
    {u_p14_pipeline/block_pending*}
    {u_p14_pipeline/card_pending*}
    {u_p14_pipeline/revoke_pending*}
    {u_p14_pipeline/*guarded_block_confirmation*raw_*}
    {u_p14_pipeline/*guarded_block_confirmation*block_confirmation/*}
    {u_p14_pipeline/confirmation/*}
} {
    set resolved [get_regs $pattern]
    puts $contour29_fd "PATTERN $pattern COUNT [llength $resolved]"
    puts $contour29_fd "REGS $resolved"
    if {[llength $resolved]==0} {puts $contour29_fd "UNRESOLVED: independent exact-net/packed-Q proof required"}
    foreach object $resolved {lappend contour29_regs $object}
}
set contour29_regs [lsort -unique $contour29_regs]
puts $contour29_fd "ALL_COUNT [llength $contour29_regs]"
puts $contour29_fd "ALL_REGS $contour29_regs"
set contour29_ep_num [expr {2 * [llength $contour29_regs]}]
puts $contour29_fd "ENDPOINT_LIMIT $contour29_ep_num"
close $contour29_fd
if {[llength $contour29_regs]==0} {error "T029 contour/geometry endpoint population missing"}
report_timing_path -to $contour29_regs -ep_num $contour29_ep_num -path_num 2 -file contour29-inbound.rpt
report_timing_path -from $contour29_regs -ep_num $contour29_ep_num -path_num 2 -file contour29-outbound.rpt
clear_sdc -user
# Re-deriving PLLs from cleared top clocks is unsupported in this routed TD
# context. Use the actual existing generated-clock output pins, at the periods
# in the original routed clock report; only the mailbox path is evaluated here.
set mipi_pin [get_pins {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]
set hdmi_pin [get_pins {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
set config_pin [get_pins {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
if {[llength $mipi_pin]!=1 || [llength $hdmi_pin]!=1 || [llength $config_pin]!=1} {error "CDC physical clock pins not resolved"}
create_clock -name MIPI_RX_BYTE_CLK -period 9.660 $mipi_pin
create_clock -name HDMI_PIXEL_CLK -period 13.333 $hdmi_pin
create_clock -name pll_clk_24m -period 42.000 $config_pin
set payload_from [get_regs {u_p14_pipeline/forward/held_data*}]
set payload_to [get_regs {u_p14_pipeline/forward/dst_data*}]
# No interactive max-delay exception: this view measures routed propagation.
# The audit compares actual data delays against an explicit external bound.
update_timing -mode final
if {[llength [get_clocks MIPI_RX_BYTE_CLK]]!=1 || [llength [get_clocks HDMI_PIXEL_CLK]]!=1 || [llength [get_clocks pll_clk_24m]]!=1} {error "CDC analysis clock reconstruction failed"}
report_clock_summary -file analysis-clocks.rpt
report_timing_path -from $payload_from -to $payload_to -ep_num 400 -path_num 1 -file payload-routing.rpt
set diagnostic_from [get_regs {u_p14_diag_cdc/held_data*}]
set diagnostic_to [get_regs {u_p14_diag_cdc/dst_data*}]
if {[llength $diagnostic_from]<32 || [llength $diagnostic_to]<32} {error "Diagnostic payload unexpectedly optimized away"}
set fd [open diagnostic-objects.txt w]
puts $fd "FROM [llength $diagnostic_from] $diagnostic_from"
puts $fd "TO [llength $diagnostic_to] $diagnostic_to"
close $fd
report_timing_path -from $diagnostic_from -to $diagnostic_to -ep_num 600 -path_num 1 -file diagnostic-routing.rpt
set i2c_from [get_regs {u_p14_i2c_cdc/held_data*}]
set i2c_to [get_regs {u_p14_i2c_cdc/dst_data*}]
# Some diagnostic bits are constants. Audit every retained logical bit against
# its routed Q/D pins instead of requiring the declared 32 bits to survive.
if {[llength $i2c_from]==0 || [llength $i2c_to]==0} {error "I2C diagnostic payload unexpectedly optimized away"}
set fd [open i2c-objects.txt w]
puts $fd "FROM [llength $i2c_from] $i2c_from"
puts $fd "TO [llength $i2c_to] $i2c_to"
close $fd
report_timing_path -from $i2c_from -to $i2c_to -ep_num 200 -path_num 1 -file i2c-routing.rpt
set color_from [get_regs {u_p14_pipeline/*transport/link/held_data*}]
set color_to [get_regs {u_p14_pipeline/*transport/link/dst_data*}]
if {[llength $color_from]<100 || [llength $color_to]<100} {error "Color observation mailbox unexpectedly missing"}
set fd [open color-objects.txt w];puts $fd "FROM [llength $color_from] $color_from";puts $fd "TO [llength $color_to] $color_to";close $fd
report_timing_path -from $color_from -to $color_to -ep_num 2400 -path_num 1 -file color-routing.rpt
report_timing_exception -file analysis-exceptions.rpt
report_timing_ignored -file analysis-ignored.rpt
puts "PIXEL14_CDC_PHYSICAL_REPORTS_OK"
cd $saved_cwd
