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
    {q0000 outbound {u_p14_pipeline/glyph_color_mode$blocks/classify/eb[1]}}
    {q0001 outbound {u_p14_pipeline/glyph_color_mode$blocks/classify/eb[4]}}
    {q0002 outbound {u_p14_pipeline/glyph_color_mode$blocks/classify/eb[6]}}
    {q0003 outbound {u_p14_pipeline/glyph_color_mode$blocks/classify/eb[7]}}
    {q0004 outbound {u_p14_pipeline/glyph_color_mode$blocks/classify/er[1]}}
    {q0005 outbound {u_p14_pipeline/glyph_color_mode$blocks/classify/er[2]}}
    {q0006 outbound {u_p14_pipeline/glyph_color_mode$blocks/classify/er[3]}}
    {q0007 outbound {u_p14_pipeline/glyph_color_mode$blocks/classify/es[5]}}
    {q0008 outbound {u_p14_pipeline/glyph_color_mode$blocks/classify/es[8]}}
    {q0009 outbound {u_p14_pipeline/glyph_color_mode$blocks/classify/es[9]}}
    {q0010 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/active}}
    {q0011 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/active_id[17]}}
    {q0012 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[0][10]}}
    {q0013 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[0][12]}}
    {q0014 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[0][13]}}
    {q0015 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[0][17]}}
    {q0016 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[0][7]}}
    {q0017 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[0][8]}}
    {q0018 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[1][15]}}
    {q0019 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[1][16]}}
    {q0020 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[1][17]}}
    {q0021 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[1][19]}}
    {q0022 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[1][3]}}
    {q0023 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[2][0]}}
    {q0024 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[2][10]}}
    {q0025 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[2][15]}}
    {q0026 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[2][16]}}
    {q0027 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[2][19]}}
    {q0028 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[2][3]}}
    {q0029 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/area[2][7]}}
    {q0030 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/candidate[0]}}
    {q0031 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/expected_x[3]}}
    {q0032 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/expected_x[6]}}
    {q0033 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/expected_x[7]}}
    {q0034 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/expected_y[0]}}
    {q0035 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/expected_y[3]}}
    {q0036 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/expected_y[5]}}
    {q0037 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/glyph_area[14]}}
    {q0038 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/glyph_area[15]}}
    {q0039 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/glyph_area[6]}}
    {q0040 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/glyph_area[7]}}
    {q0041 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/glyph_top[3]}}
    {q0042 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_color[1]}}
    {q0043 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_frame_id[13]}}
    {q0044 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_frame_id[15]}}
    {q0045 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_frame_id[19]}}
    {q0046 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_frame_id[21]}}
    {q0047 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_frame_id[24]}}
    {q0048 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_frame_id[27]}}
    {q0049 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_frame_id[30]}}
    {q0050 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_frame_id[5]}}
    {q0051 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_glyph}}
    {q0052 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_x[0]}}
    {q0053 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_x[4]}}
    {q0054 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_x[8]}}
    {q0055 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_y[0]}}
    {q0056 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/in_y[4]}}
    {q0057 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/pixels[10]}}
    {q0058 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/pixels[11]}}
    {q0059 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/pixels[2]}}
    {q0060 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/saved_present}}
    {q0061 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/selected_area[10]}}
    {q0062 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/selected_area[11]}}
    {q0063 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/selected_area[14]}}
    {q0064 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/selected_area[16]}}
    {q0065 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/selected_area[19]}}
    {q0066 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/selected_area[1]}}
    {q0067 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/selected_area[4]}}
    {q0068 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/selected_area[7]}}
    {q0069 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/selected_area[8]}}
    {q0070 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/selected_area[9]}}
    {q0071 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/stage_reg_syn_1[2]}}
    {q0072 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/stage_reg_syn_1[3]}}
    {q0073 outbound {u_p14_pipeline/glyph_color_mode$blocks/core/stage_reg_syn_1[4]}}
    {q0074 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[13]}}
    {q0075 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[17]}}
    {q0076 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[21]}}
    {q0077 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[23]}}
    {q0078 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[24]}}
    {q0079 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[27]}}
    {q0080 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[28]}}
    {q0081 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[31]}}
    {q0082 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[34]}}
    {q0083 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[37]}}
    {q0084 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[39]}}
    {q0085 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[42]}}
    {q0086 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[47]}}
    {q0087 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[48]}}
    {q0088 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[51]}}
    {q0089 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[55]}}
    {q0090 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[56]}}
    {q0091 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[57]}}
    {q0092 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[58]}}
    {q0093 outbound {u_p14_pipeline/glyph_color_mode$blocks/meta_a[9]}}
    {q0094 outbound {u_p14_pipeline/guarded_block_confirmation$block_confirmation/out_item[0]}}
    {q0095 outbound {u_p14_pipeline/guarded_block_confirmation$raw_record[19]}}
    {q0096 outbound {u_p14_pipeline/guarded_block_confirmation$raw_record[30]}}
    {q0097 outbound {u_p14_pipeline/guarded_block_confirmation$raw_record[32]}}
    {q0098 outbound {u_p14_pipeline/guarded_block_confirmation$raw_record[39]}}
    {q0099 outbound {u_p14_pipeline/guarded_block_confirmation$raw_record[43]}}
    {q0100 outbound {u_p14_pipeline/scene_mode$scene/card_id[22]}}
    {q0101 outbound {u_p14_pipeline/scene_mode$scene/card_id[8]}}
    {q0102 outbound {u_p14_pipeline/scene_mode$scene/card_index[0]}}
    {q0103 outbound {u_p14_pipeline/scene_mode$scene/replay_rgb[0]}}
    {q0104 outbound {u_p14_pipeline/scene_mode$scene/replay_rgb[15]}}
    {q0105 outbound {u_p14_pipeline/scene_mode$scene/replay_rgb[17]}}
    {q0106 outbound {u_p14_pipeline/scene_mode$scene/replay_rgb[20]}}
    {q0107 outbound {u_p14_pipeline/scene_mode$scene/replay_rgb[23]}}
    {q0108 outbound {u_p14_pipeline/scene_mode$scene/replay_rgb[7]}}
    {q0109 outbound {u_p14_pipeline/shape_id[10]}}
    {q0110 outbound {u_p14_pipeline/shape_id[11]}}
    {q0111 outbound {u_p14_pipeline/shape_id[17]}}
    {q0112 outbound {u_p14_pipeline/shape_id[18]}}
    {q0113 outbound {u_p14_pipeline/shape_id[1]}}
    {q0114 outbound {u_p14_pipeline/shape_id[23]}}
    {q0115 outbound {u_p14_pipeline/shape_id[24]}}
    {q0116 outbound {u_p14_pipeline/shape_id[26]}}
    {q0117 outbound {u_p14_pipeline/shape_id[29]}}
    {q0118 outbound {u_p14_pipeline/shape_id[3]}}
    {q0119 outbound {u_p14_pipeline/shape_id[4]}}
    {q0120 outbound {u_p14_pipeline/shape_id[5]}}
    {q0121 outbound {u_p14_pipeline/shape_id[7]}}
    {q0122 outbound {u_p14_pipeline/shape_id[9]}}
    {q0123 outbound {u_p14_pipeline/shape_mode$shape_guard/dist_triangle[1]}}
    {q0124 outbound {u_p14_pipeline/shape_mode$shape_guard/dist_triangle[8]}}
    {q0125 outbound {u_p14_pipeline/shape_mode$shape_guard/dist_triangle[9]}}
    {q0126 outbound {u_p14_pipeline/shape_mode$shape_guard/saved_good}}
    {q0127 outbound {u_p14_pipeline/shape_mode$shape_guard/saved_present}}
} {
    lassign $query id direction q
    set resolved [get_regs $q]
    puts $fd "QUERY $id $direction {$q} COUNT [llength $resolved] RESOLVED {$resolved}"
    flush $fd
    if {[llength $resolved]!=1} {error "Exact Q did not resolve uniquely: $q"}
    if {$direction eq "inbound"} {
        report_timing_path -to $resolved -ep_num 4 -path_num 2 -file ${id}-${direction}.rpt
    } else {
        set qnet [get_nets $q]
        if {[llength $qnet]!=1} {error "Exact Q net did not resolve uniquely: $q"}
        puts "T027_THROUGH $id {$q} COUNT [llength $qnet]"
        report_timing_path -from $resolved -through $qnet -ep_num 4 -path_num 2 -file ${id}-${direction}.rpt
    }
}
close $fd
puts "T027_ENDPOINT_PROBE_DONE"
} message]} {puts stderr $message; exit 1}
exit 0
