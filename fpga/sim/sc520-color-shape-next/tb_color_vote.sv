`timescale 1ns/1ps

module tb_color_vote;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic flush = 1'b0;
    logic in_start = 1'b0;
    logic in_valid = 1'b0;
    logic in_end = 1'b0;
    logic in_good = 1'b1;
    logic [31:0] in_frame_id = 32'd0;
    logic in_source = 1'b0;
    logic [12:0] in_expected_samples = 13'd0;
    logic [12:0] in_index = 13'd0;
    logic [23:0] in_rgb = 24'd0;
    logic in_glyph = 1'b0;
    wire out_event;
    wire out_color_valid;
    wire [1:0] out_color;
    wire out_revoke;
    wire [31:0] out_frame_id;
    wire out_source;
    wire [12:0] out_sample_count;
    wire [12:0] out_glyph_count;
    wire [12:0] out_red_count;
    wire [12:0] out_yellow_count;
    wire [12:0] out_blue_count;

    integer errors = 0;
    integer checks = 0;
    integer events = 0;
    integer revokes = 0;
    integer canonical_vectors = 0;
    integer vote_vectors = 0;
    integer supplemental_vectors = 0;

    always #5 clk = ~clk;

    pixel311_color_vote dut (
        .clk(clk), .rst_n(rst_n), .flush(flush),
        .in_start(in_start), .in_valid(in_valid), .in_end(in_end),
        .in_good(in_good), .in_frame_id(in_frame_id), .in_source(in_source),
        .in_expected_samples(in_expected_samples), .in_index(in_index),
        .in_rgb(in_rgb), .in_glyph(in_glyph),
        .out_event(out_event), .out_color_valid(out_color_valid),
        .out_color(out_color), .out_revoke(out_revoke),
        .out_frame_id(out_frame_id), .out_source(out_source),
        .out_sample_count(out_sample_count), .out_glyph_count(out_glyph_count),
        .out_red_count(out_red_count), .out_yellow_count(out_yellow_count),
        .out_blue_count(out_blue_count)
    );

    always @(posedge clk) begin
        #2;
        if (out_event) events = events + 1;
        if (out_revoke) revokes = revokes + 1;
    end

    task automatic check(input bit condition, input string message);
        begin
            checks = checks + 1;
            if (!condition) begin
                errors = errors + 1;
                $display("FAIL %s at %0t", message, $time);
            end
        end
    endtask

    task automatic idle_cycle;
        begin
            @(negedge clk);
            in_start = 1'b0;
            in_valid = 1'b0;
            in_end = 1'b0;
            in_good = 1'b1;
            in_expected_samples = 13'd0;
            in_rgb = 24'd0;
            in_glyph = 1'b0;
        end
    endtask

    task automatic start_only(input [31:0] id, input bit source, input integer total);
        begin
            @(negedge clk);
            in_frame_id = id;
            in_source = source;
            in_expected_samples = total[12:0];
            in_index = 13'd0;
            in_start = 1'b1;
            in_valid = 1'b0;
            in_end = 1'b0;
            @(posedge clk);
            #1;
            idle_cycle();
        end
    endtask

    task automatic sample(
        input integer idx, input [23:0] rgb, input bit glyph
    );
        begin
            @(negedge clk);
            in_start = 1'b0;
            in_valid = 1'b1;
            in_end = 1'b0;
            in_good = 1'b1;
            in_index = idx[12:0];
            in_rgb = rgb;
            in_glyph = glyph;
            @(posedge clk);
            #1;
            idle_cycle();
        end
    endtask

    task automatic finish(input bit good);
        begin
            @(negedge clk);
            in_start = 1'b0;
            in_valid = 1'b0;
            in_end = 1'b1;
            in_good = good;
            @(posedge clk);
            #1;
            idle_cycle();
        end
    endtask

    task automatic check_result(
        input string name, input [31:0] id, input bit source,
        input integer total, input integer glyphs,
        input integer reds, input integer yellows, input integer blues,
        input [1:0] expected_color
    );
        begin
            check(out_event && !out_revoke, {name, ": healthy event"});
            check(out_color_valid == (expected_color != 2'd0),
                  {name, ": color qualification"});
            check(out_color == expected_color, {name, ": color"});
            check(out_frame_id == id && out_source == source,
                  {name, ": full frame/source identity"});
            check(out_sample_count == total && out_glyph_count == glyphs,
                  {name, ": sample/glyph counts"});
            check(out_red_count == reds && out_yellow_count == yellows &&
                  out_blue_count == blues, {name, ": all color counts"});
        end
    endtask

    task automatic check_pulses_clear(
        input bit expected_valid, input [1:0] expected_color
    );
        begin
            @(posedge clk);
            #1;
            check(!out_event && !out_revoke, "event/revoke are single-cycle pulses");
            check(out_color_valid == expected_valid && out_color == expected_color,
                  "idle preserves published color qualification");
            idle_cycle();
        end
    endtask

    task automatic single_color(
        input string name, input [31:0] id, input bit source,
        input [23:0] rgb, input [1:0] expected_color
    );
        begin
            @(negedge clk);
            in_frame_id = id;
            in_source = source;
            in_expected_samples = 13'd1;
            in_index = 13'd0;
            in_rgb = rgb;
            in_glyph = 1'b1;
            in_start = 1'b1;
            in_valid = 1'b1;
            in_end = 1'b1;
            in_good = 1'b1;
            @(posedge clk);
            #1;
            check_result(name, id, source, 1, 1,
                         expected_color == 2'd1, expected_color == 2'd2,
                         expected_color == 2'd3, expected_color);
            idle_cycle();
        end
    endtask

    task automatic run_canonical(
        input string name, input [31:0] id, input bit source,
        input [23:0] rgb, input [1:0] expected_color
    );
        begin
            canonical_vectors = canonical_vectors + 1;
            single_color(name, id, source, rgb, expected_color);
`ifdef INJECT_CHECKER_FAILURE
            if (canonical_vectors == 1)
                check(out_color == 2'd3,
                      "INJECT_CHECKER_FAILURE first red vector deliberately expects blue");
`endif
            check_pulses_clear(expected_color != 2'd0, expected_color);
        end
    endtask

    function automatic [23:0] rgb_for_color(input [1:0] color_id);
        begin
            case (color_id)
                2'd1: rgb_for_color = 24'hFF0000;
                2'd2: rgb_for_color = 24'hFFFF00;
                2'd3: rgb_for_color = 24'h0000FF;
                default: rgb_for_color = 24'h606060;
            endcase
        end
    endfunction

    task automatic run_vote(
        input string name, input [31:0] id, input bit source,
        input integer total, input [31:0] packed_ids,
        input integer reds, input integer yellows, input integer blues,
        input [1:0] expected_color
    );
        integer i;
        begin
            vote_vectors = vote_vectors + 1;
            start_only(id, source, total);
            for (i = 0; i < total; i = i + 1)
                sample(i, rgb_for_color((packed_ids >> (2 * i)) & 2'b11), 1'b1);
            finish(1'b1);
            check_result(name, id, source, total, total, reds, yellows, blues,
                         expected_color);
            idle_cycle();
            check_pulses_clear(expected_color != 2'd0, expected_color);
        end
    endtask

    task automatic expect_revoke(input string message);
        begin
            @(posedge clk);
            #1;
            check(out_revoke, message);
            check(!out_event && !out_color_valid && out_color == 2'd0,
                  "revoke clears event/color");
            check(out_sample_count == 0 && out_glyph_count == 0 &&
                  out_red_count == 0 && out_yellow_count == 0 &&
                  out_blue_count == 0, "revoke clears every published count");
            idle_cycle();
            check_pulses_clear(1'b0, 2'd0);
        end
    endtask

    task automatic high_count_boundary;
        integer i;
        begin
            start_only(32'hF1230040, 1'b0, 7200);
            for (i = 0; i < 7200; i = i + 1) begin
                @(negedge clk);
                in_start = 1'b0;
                in_valid = 1'b1;
                in_end = 1'b0;
                in_good = 1'b1;
                in_index = i[12:0];
                in_glyph = 1'b1;
                if (i < 5000)
                    in_rgb = 24'hF01010;
                else if (i < 6000)
                    in_rgb = 24'h1010F0;
                else if (i < 7000)
                    in_rgb = 24'hF0F010;
                else
                    in_rgb = 24'h808080;
                @(posedge clk);
                #1;
            end
            idle_cycle();
            finish(1'b1);
            check_result("7200-sample counters", 32'hF1230040, 1'b0,
                         7200, 7200, 5000, 1000, 1000, 2'd1);
            idle_cycle();
            check_pulses_clear(1'b1, 2'd1);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // The runner generates these calls from the frozen model/vector pair.
`include "model_vectors.svh"
        check(canonical_vectors == 16 && vote_vectors == 12,
              "all frozen 16 canonical and 12 vote vectors executed");

        single_color("high minimum below", 32'd1, 1'b0, 24'h1F0000, 2'd0);
        single_color("high minimum equal", 32'd2, 1'b1, 24'h200000, 2'd1);
        single_color("chroma below", 32'd3, 1'b0, 24'h200909, 2'd0);
        single_color("chroma equal", 32'd4, 1'b1, 24'h200808, 2'd1);
        supplemental_vectors = 4;
        high_count_boundary();

        // start+valid consumes index zero while keeping the transaction open.
        @(negedge clk);
        in_frame_id = 32'h12345678; in_source = 1'b1;
        in_expected_samples = 13'd2; in_index = 13'd0;
        in_start = 1'b1; in_valid = 1'b1; in_end = 1'b0;
        in_good = 1'b1; in_rgb = 24'hFF0000; in_glyph = 1'b1;
        @(posedge clk); #1;
        check(!out_event && !out_revoke && !out_color_valid,
              "start/valid first sample remains pending");
        idle_cycle();
        sample(1, 24'hFF0000, 1'b1);
        finish(1'b1);
        check_result("start/valid then end-only", 32'h12345678, 1'b1,
                     2, 2, 2, 0, 0, 2'd1);
        idle_cycle();

        // valid+end includes the last sample before checking expected count.
        start_only(32'hFEDCBA98, 1'b0, 2);
        sample(0, 24'h0000FF, 1'b1);
        @(negedge clk);
        in_valid = 1'b1; in_end = 1'b1; in_good = 1'b1;
        in_index = 13'd1; in_rgb = 24'h0000FF; in_glyph = 1'b1;
        @(posedge clk); #1;
        check_result("last valid/end", 32'hFEDCBA98, 1'b0,
                     2, 2, 0, 0, 2, 2'd3);
        idle_cycle();

        // Glyph=false samples count in total but not in color denominator.
        start_only(32'd11, 1'b0, 4);
        sample(0, 24'hF01010, 1'b1);
        sample(1, 24'hF01010, 1'b1);
        sample(2, 24'h1010F0, 1'b0);
        sample(3, 24'h000000, 1'b0);
        finish(1'b1);
        check_result("non-glyph exclusion", 32'd11, 1'b0,
                     4, 2, 2, 0, 0, 2'd1);
        idle_cycle();
        start_only(32'd12, 1'b1, 2);
        sample(0, 24'hFF0000, 1'b0);
        sample(1, 24'hFFFF00, 1'b0);
        finish(1'b1);
        check_result("zero glyph denominator", 32'd12, 1'b1,
                     2, 0, 0, 0, 0, 2'd0);
        idle_cycle();

        // Complete sample count alone cannot publish without end.
        start_only(32'd13, 1'b0, 1);
        sample(0, 24'hFF0000, 1'b1);
        repeat (2) begin
            @(posedge clk); #1;
            check(!out_event && !out_revoke && !out_color_valid,
                  "complete samples wait for explicit end");
            idle_cycle();
        end
        finish(1'b1);
        check_result("delayed end-only", 32'd13, 1'b0, 1, 1, 1, 0, 0, 2'd1);
        idle_cycle();

        // Only start consumes expected_samples; subsequent idle drives it zero.
        start_only(32'd14, 1'b0, 1);
        check(!out_event && !out_revoke && !out_color_valid &&
              out_sample_count == 0 && out_glyph_count == 0,
              "new idle start supersedes previously published qualification");
        sample(0, 24'hFFFF00, 1'b1);
        finish(1'b1);
        check_result("start-latched expected", 32'd14, 1'b0,
                     1, 1, 0, 1, 0, 2'd2);
        idle_cycle();

        // Isolated strobes and invalid expected bounds.
        @(negedge clk);
        in_valid = 1'b1; in_index = 13'd0; in_frame_id = 32'd20;
        in_rgb = 24'hF01010; in_glyph = 1'b1;
        expect_revoke("isolated valid revokes");

        @(negedge clk);
        in_end = 1'b1;
        expect_revoke("isolated end revokes");

        @(negedge clk);
        in_start = 1'b1; in_expected_samples = 13'd0;
        expect_revoke("expected zero revokes");

        @(negedge clk);
        in_start = 1'b1; in_expected_samples = 13'd7201;
        expect_revoke("expected above 7200 revokes");

        start_only(32'd200, 1'b0, 1);
        @(negedge clk);
        in_end = 1'b1;
        expect_revoke("empty transaction end revokes");

        start_only(32'd201, 1'b0, 2);
        sample(0, 24'hFF0000, 1'b1);
        @(negedge clk);
        in_end = 1'b1;
        expect_revoke("incomplete transaction end revokes");

        start_only(32'd21, 1'b0, 2);
        @(negedge clk);
        in_valid = 1'b1; in_index = 13'd1; in_frame_id = 32'd21;
        in_rgb = 24'hF01010; in_glyph = 1'b1;
        expect_revoke("nonzero first index revokes");

        start_only(32'd210, 1'b0, 3);
        sample(0, 24'hFF0000, 1'b1);
        @(negedge clk);
        in_valid = 1'b1; in_index = 13'd2;
        in_rgb = 24'hFF0000; in_glyph = 1'b1;
        expect_revoke("skipped middle index revokes");

        start_only(32'd22, 1'b0, 1);
        @(negedge clk);
        in_start = 1'b1; in_expected_samples = 13'd1;
        expect_revoke("active restart revokes without accepting new start");

        start_only(32'h12345678, 1'b0, 1);
        @(negedge clk);
        in_valid = 1'b1; in_index = 13'd0; in_frame_id = 32'h92345678;
        in_rgb = 24'hF01010; in_glyph = 1'b1;
        expect_revoke("valid full-width frame identity mismatch revokes");

        start_only(32'd230, 1'b0, 1);
        @(negedge clk);
        in_valid = 1'b1; in_index = 13'd0; in_source = 1'b1;
        in_rgb = 24'hFF0000; in_glyph = 1'b1;
        expect_revoke("valid source identity mismatch revokes");

        start_only(32'h12345678, 1'b0, 1);
        sample(0, 24'hFF0000, 1'b1);
        @(negedge clk);
        in_end = 1'b1; in_frame_id = 32'h92345678;
        expect_revoke("end-only full-width frame identity mismatch revokes");

        start_only(32'd232, 1'b0, 1);
        sample(0, 24'hFF0000, 1'b1);
        @(negedge clk);
        in_end = 1'b1; in_source = 1'b1;
        expect_revoke("end-only source identity mismatch revokes");

        start_only(32'd24, 1'b0, 1);
        @(negedge clk);
        in_valid = 1'b1; in_index = 13'd0; in_frame_id = 32'd24;
        in_rgb = 24'hF01010; in_glyph = 1'b1;
        in_end = 1'b1; in_good = 1'b0;
        expect_revoke("bad frame end revokes");

        start_only(32'd240, 1'b0, 1);
        sample(0, 24'hFF0000, 1'b1);
        @(negedge clk);
        in_end = 1'b1; in_good = 1'b0;
        expect_revoke("bad end-only health revokes");

        start_only(32'd25, 1'b0, 1);
        sample(0, 24'hF01010, 1'b1);
        @(negedge clk);
        in_valid = 1'b1; in_index = 13'd1; in_frame_id = 32'd25;
        in_rgb = 24'hF01010; in_glyph = 1'b1;
        expect_revoke("sample overflow revokes");

        // Flush has priority even when all input transaction strobes coincide.
        start_only(32'd30, 1'b0, 2);
        sample(0, 24'hF01010, 1'b1);
        @(negedge clk);
        flush = 1'b1; in_start = 1'b1; in_valid = 1'b1; in_end = 1'b1;
        @(posedge clk); #1;
        check(out_revoke && !out_event && !out_color_valid,
              "flush revokes pending transaction before coincident strobes");
        idle_cycle();
        flush = 1'b0;
        check_pulses_clear(1'b0, 2'd0);

        single_color("pre-flush published", 32'd31, 1'b0, 24'hFF0000, 2'd1);
        @(negedge clk);
        flush = 1'b1;
        @(posedge clk); #1;
        check(out_revoke && !out_event && !out_color_valid &&
              out_color == 0 && out_sample_count == 0 && out_glyph_count == 0 &&
              out_red_count == 0 && out_yellow_count == 0 && out_blue_count == 0,
              "flush revokes published color and counts");
        idle_cycle();
        flush = 1'b0;
        check_pulses_clear(1'b0, 2'd0);
        @(negedge clk);
        flush = 1'b1;
        @(posedge clk); #1;
        check(!out_revoke && !out_event && !out_color_valid,
              "idle flush has no spurious revoke");
        idle_cycle();
        flush = 1'b0;

        single_color("pre-reset published", 32'd32, 1'b0, 24'hFF0000, 2'd1);
        rst_n = 1'b0;
        #1;
        check(!out_event && !out_revoke && !out_color_valid && out_color == 2'd0,
              "async reset clears published color");
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        start_only(32'd33, 1'b0, 2);
        sample(0, 24'hFF0000, 1'b1);
        rst_n = 1'b0;
        #1;
        check(!out_event && !out_revoke && !out_color_valid &&
              out_sample_count == 0 && out_glyph_count == 0 &&
              out_red_count == 0 && out_yellow_count == 0 && out_blue_count == 0,
              "async reset clears pending transaction and all counts");
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        idle_cycle();
        @(negedge clk);
        in_end = 1'b1;
        expect_revoke("reset removed pending context");

        $display("RESULT errors=%0d checks=%0d events=%0d revokes=%0d canonical=%0d votes=%0d supplemental=%0d",
                 errors, checks, events, revokes, canonical_vectors, vote_vectors,
                 supplemental_vectors);
        if (errors != 0)
            $fatal(1, "color vote test failed");
        $display("PASS color vote");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "WATCHDOG color vote");
    end
endmodule
