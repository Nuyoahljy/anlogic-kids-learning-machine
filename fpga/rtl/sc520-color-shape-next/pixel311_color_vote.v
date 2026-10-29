// Task-private streaming color vote observer.
// This module consumes one bounded glyph/sample transaction and never
// connects to the production top level or shape/category pipeline.
module pixel311_color_vote #(
    parameter integer MAX_SAMPLES = 7200
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,
    input  wire        in_start,
    input  wire        in_valid,
    input  wire        in_end,
    input  wire        in_good,
    input  wire [31:0] in_frame_id,
    input  wire        in_source,
    input  wire [12:0] in_expected_samples,
    input  wire [12:0] in_index,
    input  wire [23:0] in_rgb,
    input  wire        in_glyph,
    output reg         out_event,
    output reg         out_color_valid,
    output reg  [1:0]  out_color,
    output reg         out_revoke,
    output reg  [31:0] out_frame_id,
    output reg         out_source,
    output reg  [12:0] out_sample_count,
    output reg  [12:0] out_glyph_count,
    output reg  [12:0] out_red_count,
    output reg  [12:0] out_yellow_count,
    output reg  [12:0] out_blue_count
);
    localparam [1:0] COLOR_UNKNOWN = 2'd0;
    localparam [1:0] COLOR_RED     = 2'd1;
    localparam [1:0] COLOR_YELLOW  = 2'd2;
    localparam [1:0] COLOR_BLUE    = 2'd3;

    reg        active;
    reg [31:0] frame_q;
    reg        source_q;
    reg [12:0] expected_q;
    reg [12:0] sample_q;
    reg [12:0] glyph_q;
    reg [12:0] red_q;
    reg [12:0] yellow_q;
    reg [12:0] blue_q;

    // These temporaries are assigned on every active clock edge before they
    // are consumed by the nonblocking state updates below.
    reg        work_fault;
    reg        work_context;
    reg        work_end;
    reg [31:0] work_frame;
    reg        work_source;
    reg [12:0] work_expected;
    reg [12:0] work_samples;
    reg [12:0] work_glyph;
    reg [12:0] work_red;
    reg [12:0] work_yellow;
    reg [12:0] work_blue;
    reg [1:0]  work_vote;
    reg        work_vote_valid;
    reg [1:0]  sample_color;

    function [1:0] classify_rgb;
        input [23:0] rgb;
        reg [7:0] r;
        reg [7:0] g;
        reg [7:0] b;
        reg [7:0] hi;
        reg [7:0] lo;
        reg [7:0] rg_min;
        reg [7:0] rg_max;
        reg [8:0] r_ext;
        reg [8:0] g_ext;
        reg [8:0] b_ext;
        reg [8:0] two_b;
        reg [8:0] two_rg_min;
        begin
            r = rgb[23:16];
            g = rgb[15:8];
            b = rgb[7:0];
            r_ext = {1'b0, r};
            g_ext = {1'b0, g};
            b_ext = {1'b0, b};

            hi = r;
            if (g > hi)
                hi = g;
            if (b > hi)
                hi = b;
            lo = r;
            if (g < lo)
                lo = g;
            if (b < lo)
                lo = b;

            rg_min = (r < g) ? r : g;
            rg_max = (r > g) ? r : g;
            two_b = b_ext << 1;
            two_rg_min = {1'b0, rg_min} << 1;

            classify_rgb = COLOR_UNKNOWN;
            if (hi >= 8'd32 && (hi - lo) >= 8'd24) begin
                if (r_ext > (g_ext << 1) && r_ext > (b_ext << 1))
                    classify_rgb = COLOR_RED;
                else if ({1'b0, rg_min} >= two_b &&
                         {1'b0, rg_max} <= two_rg_min)
                    classify_rgb = COLOR_YELLOW;
                else if (b_ext > (r_ext << 1) && b_ext > (g_ext << 1))
                    classify_rgb = COLOR_BLUE;
            end
        end
    endfunction

    // Return {valid, color}. Unknown is a healthy event with valid=0.
    function [2:0] decide_vote;
        input [12:0] glyph_count;
        input [12:0] red_count;
        input [12:0] yellow_count;
        input [12:0] blue_count;
        reg [1:0] winner;
        reg [12:0] winner_count;
        reg [14:0] three_winner;
        reg [14:0] two_glyph;
        reg unique_winner;
        begin
            winner = COLOR_UNKNOWN;
            winner_count = 13'd0;
            unique_winner = 1'b0;
            if (red_count > yellow_count && red_count > blue_count) begin
                winner = COLOR_RED;
                winner_count = red_count;
                unique_winner = 1'b1;
            end else if (yellow_count > red_count && yellow_count > blue_count) begin
                winner = COLOR_YELLOW;
                winner_count = yellow_count;
                unique_winner = 1'b1;
            end else if (blue_count > red_count && blue_count > yellow_count) begin
                winner = COLOR_BLUE;
                winner_count = blue_count;
                unique_winner = 1'b1;
            end
            three_winner = {2'd0, winner_count} * 15'd3;
            two_glyph = {2'd0, glyph_count} * 15'd2;
            decide_vote = {1'b0, COLOR_UNKNOWN};
            if (glyph_count != 13'd0 && unique_winner &&
                three_winner >= two_glyph) begin
                if (winner == COLOR_RED &&
                    {1'b0, red_count} >= ({1'b0, yellow_count} << 1) &&
                    {1'b0, red_count} >= ({1'b0, blue_count} << 1))
                    decide_vote = {1'b1, COLOR_RED};
                else if (winner == COLOR_YELLOW &&
                         {1'b0, yellow_count} >= ({1'b0, red_count} << 1) &&
                         {1'b0, yellow_count} >= ({1'b0, blue_count} << 1))
                    decide_vote = {1'b1, COLOR_YELLOW};
                else if (winner == COLOR_BLUE &&
                         {1'b0, blue_count} >= ({1'b0, red_count} << 1) &&
                         {1'b0, blue_count} >= ({1'b0, yellow_count} << 1))
                    decide_vote = {1'b1, COLOR_BLUE};
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active <= 1'b0;
            frame_q <= 32'd0;
            source_q <= 1'b0;
            expected_q <= 13'd0;
            sample_q <= 13'd0;
            glyph_q <= 13'd0;
            red_q <= 13'd0;
            yellow_q <= 13'd0;
            blue_q <= 13'd0;
            out_event <= 1'b0;
            out_color_valid <= 1'b0;
            out_color <= COLOR_UNKNOWN;
            out_revoke <= 1'b0;
            out_frame_id <= 32'd0;
            out_source <= 1'b0;
            out_sample_count <= 13'd0;
            out_glyph_count <= 13'd0;
            out_red_count <= 13'd0;
            out_yellow_count <= 13'd0;
            out_blue_count <= 13'd0;
        end else begin
            out_event <= 1'b0;
            out_revoke <= 1'b0;
            work_fault = 1'b0;
            work_context = active;
            work_end = 1'b0;
            work_frame = frame_q;
            work_source = source_q;
            work_expected = expected_q;
            work_samples = sample_q;
            work_glyph = glyph_q;
            work_red = red_q;
            work_yellow = yellow_q;
            work_blue = blue_q;
            sample_color = classify_rgb(in_rgb);
            work_vote = COLOR_UNKNOWN;
            work_vote_valid = 1'b0;

            if (flush) begin
                if (active || out_color_valid)
                    out_revoke <= 1'b1;
                active <= 1'b0;
                expected_q <= 13'd0;
                sample_q <= 13'd0;
                glyph_q <= 13'd0;
                red_q <= 13'd0;
                yellow_q <= 13'd0;
                blue_q <= 13'd0;
                out_color_valid <= 1'b0;
                out_color <= COLOR_UNKNOWN;
                out_sample_count <= 13'd0;
                out_glyph_count <= 13'd0;
                out_red_count <= 13'd0;
                out_yellow_count <= 13'd0;
                out_blue_count <= 13'd0;
            end else begin
                // A start is accepted only while idle. An active restart
                // revokes the old transaction and is not a new transaction.
                if (in_start) begin
                    if (active || in_expected_samples == 13'd0 ||
                        in_expected_samples > MAX_SAMPLES) begin
                        work_fault = 1'b1;
                    end else begin
                        work_context = 1'b1;
                        work_frame = in_frame_id;
                        work_source = in_source;
                        work_expected = in_expected_samples;
                        work_samples = 13'd0;
                        work_glyph = 13'd0;
                        work_red = 13'd0;
                        work_yellow = 13'd0;
                        work_blue = 13'd0;
                        active <= 1'b1;
                        frame_q <= in_frame_id;
                        source_q <= in_source;
                        expected_q <= in_expected_samples;
                        sample_q <= 13'd0;
                        glyph_q <= 13'd0;
                        red_q <= 13'd0;
                        yellow_q <= 13'd0;
                        blue_q <= 13'd0;
                        out_color_valid <= 1'b0;
                        out_color <= COLOR_UNKNOWN;
                        out_sample_count <= 13'd0;
                        out_glyph_count <= 13'd0;
                        out_red_count <= 13'd0;
                        out_yellow_count <= 13'd0;
                        out_blue_count <= 13'd0;
                    end
                end else if (!active && (in_valid || in_end)) begin
                    work_fault = 1'b1;
                end

                if (!work_fault && in_valid) begin
                    if (!work_context || in_frame_id != work_frame ||
                        in_source != work_source ||
                        in_index != work_samples ||
                        work_samples >= work_expected ||
                        work_samples >= MAX_SAMPLES) begin
                        work_fault = 1'b1;
                    end else begin
                        work_samples = work_samples + 13'd1;
                        if (in_glyph) begin
                            work_glyph = work_glyph + 13'd1;
                            case (sample_color)
                                COLOR_RED:    work_red = work_red + 13'd1;
                                COLOR_YELLOW: work_yellow = work_yellow + 13'd1;
                                COLOR_BLUE:   work_blue = work_blue + 13'd1;
                                default: begin end
                            endcase
                        end
                    end
                end

                if (!work_fault && in_end) begin
                    work_end = 1'b1;
                    if (!work_context || in_frame_id != work_frame ||
                        in_source != work_source || !in_good ||
                        work_samples != work_expected) begin
                        work_fault = 1'b1;
                    end else begin
                        {work_vote_valid, work_vote} =
                            decide_vote(work_glyph, work_red, work_yellow, work_blue);
                    end
                end

                if (work_fault) begin
                    active <= 1'b0;
                    expected_q <= 13'd0;
                    sample_q <= 13'd0;
                    glyph_q <= 13'd0;
                    red_q <= 13'd0;
                    yellow_q <= 13'd0;
                    blue_q <= 13'd0;
                    out_color_valid <= 1'b0;
                    out_color <= COLOR_UNKNOWN;
                    out_sample_count <= 13'd0;
                    out_glyph_count <= 13'd0;
                    out_red_count <= 13'd0;
                    out_yellow_count <= 13'd0;
                    out_blue_count <= 13'd0;
                    out_revoke <= 1'b1;
                end else begin
                    sample_q <= work_samples;
                    glyph_q <= work_glyph;
                    red_q <= work_red;
                    yellow_q <= work_yellow;
                    blue_q <= work_blue;
                    if (work_end) begin
                        active <= 1'b0;
                        expected_q <= 13'd0;
                        out_event <= 1'b1;
                        out_color_valid <= work_vote_valid;
                        out_color <= work_vote_valid ? work_vote : COLOR_UNKNOWN;
                        out_frame_id <= work_frame;
                        out_source <= work_source;
                        out_sample_count <= work_samples;
                        out_glyph_count <= work_glyph;
                        out_red_count <= work_red;
                        out_yellow_count <= work_yellow;
                        out_blue_count <= work_blue;
                    end
                end
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (MAX_SAMPLES < 1 || MAX_SAMPLES > 7200)
            $fatal(1, "pixel311_color_vote MAX_SAMPLES must be 1..7200");
    end
    // synthesis translate_on
endmodule
