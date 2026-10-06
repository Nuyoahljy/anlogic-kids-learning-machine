// Exploration-only presence session. No quiz, physical keys or transport policy.
module learning_events #(parameter integer REMOVE_FRAMES=2) (
    input wire clk, rst_n, flush,
    input wire det_update, present, det_valid,
    input wire [3:0] item_id,
    input wire replay_pulse,
    output reg display_valid,
    output reg [3:0] display_item,
    output reg [2:0] audio_event,
    output reg [3:0] audio_item_id,
    output reg cancel_pulse
);
    reg session_active, announced;
    reg [7:0] absent_frames;
    wire usable = present && det_valid && item_id >= 1 && item_id <= 9;
    wire parameters_ok = REMOVE_FRAMES >= 1 && REMOVE_FRAMES <= 255;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            display_valid<=0; display_item<=0; audio_event<=0; audio_item_id<=0;
            cancel_pulse<=0; session_active<=0; announced<=0; absent_frames<=0;
        end else begin
            audio_event<=0; audio_item_id<=0; cancel_pulse<=0;
            if (flush || !parameters_ok) begin
                display_valid<=0; display_item<=0; session_active<=0; announced<=0;
                absent_frames<=0; cancel_pulse<=1;
            end else begin
                if (replay_pulse && (det_update ? usable : display_valid)) begin
                    audio_event<=5;
                    audio_item_id<=det_update ? item_id : display_item;
                end
                if (det_update) begin
                    display_valid<=usable;
                    display_item<=usable ? item_id : 4'd0;
                    if (present) begin
                        session_active<=1; absent_frames<=0;
                        if (usable && !announced) begin
                            announced<=1; audio_event<=1; audio_item_id<=item_id;
                        end
                    end else begin
                        if (absent_frames < REMOVE_FRAMES) absent_frames<=absent_frames+1'b1;
                        if (absent_frames >= REMOVE_FRAMES-1) begin
                            if (session_active) cancel_pulse<=1;
                            session_active<=0; announced<=0;
                        end
                    end
                end
            end
        end
    end
endmodule
