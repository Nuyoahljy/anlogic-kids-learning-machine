# Read-only timing extraction. Launcher must use a fresh output working directory.
if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-color-integration/evidence/sc520-shape27/builds/6a50b270-phy-r2/td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_pr.db}
update_timing -mode final
report_timing_summary -file preflight-timing.rpt
report_clock_summary -file preflight-clocks.rpt
report_timing_exception -file preflight-exceptions.rpt
report_timing_ignored -file preflight-ignored.rpt
set f [open preflight-timing.rpt r]; set timing [read $f]; close $f
if {![regexp {Confidence\s+:\s+Routed} $timing] || ![regexp {Both \(Slow and Fast\)} $timing]} {error "Expected original Routed/Both timing view"}
foreach {key expected} {SWNS 0.103 STNS 0.000 HWNS 0.020 HTNS 0.000} {
    set expr [format {%s\s*:\s*([-+0-9.]+)ns} $key]
    if {![regexp $expr $timing unused value] || abs($value-$expected)>0.0000001} {error "Original timing mismatch for $key"}
}
set f [open preflight-clocks.rpt r]; set actual_clocks [string trim [read $f]]; close $f
set f [open {E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-color-integration/evidence/sc520-shape27/builds/6a50b270-phy-r2/analysis/original-clocks.rpt} r]; set expected_clocks [string trim [read $f]]; close $f
if {$actual_clocks ne $expected_clocks} {error "Original clock groups changed"}
puts "T027_PROBE_ORIGINAL_TIMING_OK"
set fd [open query-results.txt w]
foreach query {
    {q0000 inbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[1]}}
    {q0001 inbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[16]}}
    {q0002 outbound {u_p14_pipeline/glyph_color_mode$blocks/classify/eb[0]}}
    {q0003 outbound {u_p14_pipeline/shape_mode$shape_guard/count[9]}}
    {q0004 outbound {u_p14_pipeline/guarded_block_confirmation$raw_record[14]}}
} {
    lassign $query id direction q
    set resolved [get_regs $q]
    puts $fd "QUERY $id $direction {$q} COUNT [llength $resolved] RESOLVED {$resolved}"
    flush $fd
    if {[llength $resolved]!=1} {error "Exact Q did not resolve uniquely: $q"}
    if {$direction eq "inbound"} {
        report_timing_path -to $resolved -ep_num 4 -path_num 2 -file ${id}-${direction}.rpt
    } else {
        report_timing_path -from $resolved -ep_num 4 -path_num 2 -file ${id}-${direction}.rpt
    }
}
close $fd
puts "T027_ENDPOINT_PROBE_DONE"
} message]} {puts stderr $message; exit 1}
exit 0
