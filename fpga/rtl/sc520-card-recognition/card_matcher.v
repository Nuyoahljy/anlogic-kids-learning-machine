// Task-local 32x32 streaming template matcher. This is not a frozen board interface.
// frame_start precedes sample 0; frame_end follows sample 1023 on a separate clock.
// One result is published one clock after frame_end, including an orphan end in
// IDLE, which publishes an unhealthy record with cleared diagnostic scores.
// A start during capture/drain withdraws the unfinished frame and poisons the new
// frame. An end followed by a quiet clock is required before a new clean start.
module card_matcher #(
    parameter TEMPLATE_FILE = "templates.mem",
    parameter integer MAX_DISTANCE = 40,
    parameter integer MIN_MARGIN = 24,
    parameter integer MIN_FG = 16,
    parameter integer MAX_FG = 850,
    parameter integer ENABLE_OUTPUT = 0
) (
    input wire clk,
    input wire rst_n,
    input wire flush,
    input wire frame_start,
    input wire sample_valid,
    input wire [9:0] sample_index,
    input wire sample_foreground,
    input wire frame_end,
    input wire frame_good,
    input wire frame_present,
    input wire [31:0] frame_id,
    input wire frame_source_test,
    output reg out_frame,
    output reg out_healthy,
    output reg out_present,
    output reg out_valid,
    output reg [3:0] out_item,
    output reg [10:0] out_best,
    output reg [10:0] out_second,
    output reg [10:0] out_fg_count,
    output reg [31:0] out_frame_id,
    output reg out_source_test
);
    localparam [1:0] IDLE = 2'd0, CAPTURE = 2'd1, DRAIN = 2'd2;
    localparam PARAM_VALID = MAX_DISTANCE >= 0 && MAX_DISTANCE <= 1024 &&
        MIN_MARGIN >= 0 && MIN_MARGIN <= 1024 &&
        MIN_FG >= 0 && MIN_FG <= MAX_FG && MAX_FG <= 1024 &&
        (ENABLE_OUTPUT == 0 || ENABLE_OUTPUT == 1);
    reg [1:0] state;
    reg [10:0] sample_count;
    reg frame_bad;
    reg pending_valid, pending_foreground;
    reg [10:0] distance [0:4];
    reg [10:0] foreground_count;
    reg saved_healthy, saved_present, saved_source;
    reg [31:0] saved_frame_id;
    integer channel;

    // ROM data from the previous accepted sample is consumed with its delayed bit.
    wire rom_en = state == CAPTURE && sample_valid && !frame_start &&
        !flush && rst_n && sample_count < 11'd1024;
    wire [4:0] template_bits;
    card_template_rom #(.TEMPLATE_FILE(TEMPLATE_FILE)) templates (
        .clk(clk), .en(rom_en), .addr(sample_index), .data(template_bits)
    );

    reg [10:0] best_distance, second_distance;
    reg [3:0] best_item;
    integer rank_index;
    always @* begin
        best_distance = 11'd1025;
        second_distance = 11'd1025;
        best_item = 4'd0;
        for (rank_index = 0; rank_index < 5; rank_index = rank_index + 1) begin
            if (distance[rank_index] < best_distance) begin
                second_distance = best_distance;
                best_distance = distance[rank_index];
                best_item = 4'd10 + rank_index;
            end else if (distance[rank_index] < second_distance) begin
                second_distance = distance[rank_index];
            end
        end
    end
    wire [10:0] margin = second_distance - best_distance;
    wire clean_tail = !sample_valid && !frame_end;
    wire result_healthy = saved_healthy && clean_tail && PARAM_VALID;
    wire accepted = result_healthy && saved_present && ENABLE_OUTPUT == 1 &&
        foreground_count >= MIN_FG && foreground_count <= MAX_FG &&
        best_distance <= MAX_DISTANCE && second_distance > best_distance &&
        margin >= MIN_MARGIN;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            sample_count <= 0;
            frame_bad <= 0;
            pending_valid <= 0;
            pending_foreground <= 0;
            foreground_count <= 0;
            saved_healthy <= 0;
            saved_present <= 0;
            saved_source <= 0;
            saved_frame_id <= 0;
            out_frame <= 0;
            out_healthy <= 0;
            out_present <= 0;
            out_valid <= 0;
            out_item <= 0;
            out_best <= 0;
            out_second <= 0;
            out_fg_count <= 0;
            out_frame_id <= 0;
            out_source_test <= 0;
            for (channel = 0; channel < 5; channel = channel + 1) distance[channel] <= 0;
        end else if (flush) begin
            state <= IDLE;
            sample_count <= 0;
            frame_bad <= 0;
            pending_valid <= 0;
            pending_foreground <= 0;
            foreground_count <= 0;
            saved_healthy <= 0;
            saved_present <= 0;
            saved_source <= 0;
            saved_frame_id <= 0;
            out_frame <= 0;
            out_healthy <= 0;
            out_present <= 0;
            out_valid <= 0;
            out_item <= 0;
            out_best <= 0;
            out_second <= 0;
            out_fg_count <= 0;
            out_frame_id <= 0;
            out_source_test <= 0;
            for (channel = 0; channel < 5; channel = channel + 1) distance[channel] <= 0;
        end else begin
            out_frame <= 0;
            pending_valid <= 0;
            if (frame_start) begin
                // Starting never consumes a simultaneous sample or publishes an old frame.
                frame_bad <= state != IDLE || sample_valid || frame_end;
                state <= CAPTURE;
                sample_count <= 0;
                foreground_count <= 0;
                pending_foreground <= 0;
                saved_healthy <= 0;
                out_healthy <= 0;
                out_valid <= 0;
                out_item <= 0;
                for (channel = 0; channel < 5; channel = channel + 1) distance[channel] <= 0;
            end else if (state == CAPTURE) begin
                if (pending_valid) begin
                    for (channel = 0; channel < 5; channel = channel + 1)
                        distance[channel] <= distance[channel] +
                            {10'd0, (pending_foreground ^ template_bits[channel])};
                    foreground_count <= foreground_count + {10'd0, pending_foreground};
                end
                if (sample_valid) begin
                    if (sample_count >= 11'd1024 || {1'b0, sample_index} != sample_count)
                        frame_bad <= 1;
                    if (sample_count < 11'd1025) sample_count <= sample_count + 1'b1;
                    pending_valid <= rom_en;
                    pending_foreground <= sample_foreground;
                end
                if (frame_end) begin
                    saved_healthy <= frame_good && !frame_bad &&
                        sample_count == 11'd1024 && !sample_valid;
                    saved_present <= frame_present;
                    saved_source <= frame_source_test;
                    saved_frame_id <= frame_id;
                    pending_valid <= 0;
                    state <= DRAIN;
                end
            end else if (state == DRAIN) begin
                out_frame <= 1;
                out_healthy <= result_healthy;
                // A broken frame must never look like an observed empty foreground.
                out_present <= result_healthy ? saved_present : 1'b1;
                out_valid <= accepted;
                out_item <= accepted ? best_item : 4'd0;
                out_best <= best_distance;
                out_second <= second_distance;
                out_fg_count <= foreground_count;
                out_frame_id <= saved_frame_id;
                out_source_test <= saved_source;
                state <= IDLE;
            end else if (frame_end) begin
                // No start was observed: retain the frame's tag, but never reuse
                // scores or presence from a previous successfully captured frame.
                saved_healthy <= 0;
                saved_present <= 1;
                saved_source <= frame_source_test;
                saved_frame_id <= frame_id;
                sample_count <= 0;
                frame_bad <= 1;
                foreground_count <= 0;
                pending_foreground <= 0;
                out_healthy <= 0;
                out_valid <= 0;
                out_item <= 0;
                for (channel = 0; channel < 5; channel = channel + 1) distance[channel] <= 0;
                state <= DRAIN;
            end
        end
    end
    // synthesis translate_off
    initial begin
        if (!PARAM_VALID) $fatal(1, "card_matcher parameter out of supported range");
    end
    // synthesis translate_on
endmodule
