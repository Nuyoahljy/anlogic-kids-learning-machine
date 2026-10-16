// Logical audio IDs are not DFR0534 physical track numbers.
// TRACKS must be populated from a separately verified media manifest.
// Slot 0 is TRACKS[15:0]; slots are 1..14, 101..114, then 201..207.
// The all-zero default disables every mapping. This module does not certify
// a populated table, the module's file order, or successful playback.
module dfr0534_track_map #(
    parameter [35*16-1:0] TRACKS = 0
) (
    input wire [2:0] req_kind,
    input wire [3:0] req_item,
    output reg [15:0] logical_id,
    output reg [15:0] physical_track,
    output reg map_hit
);
    reg [5:0] slot_index;

    always @* begin
        logical_id = 16'd0;
        physical_track = 16'd0;
        map_hit = 1'b0;
        slot_index = 6'd0;

        case (req_kind)
            3'd1: begin
                if (req_item >= 4'd1 && req_item <= 4'd14) begin
                    logical_id = {12'd0, req_item};
                    slot_index = {2'd0, req_item} - 6'd1;
                end
            end
            3'd2: begin
                if (req_item >= 4'd1 && req_item <= 4'd14) begin
                    logical_id = 16'd100 + {12'd0, req_item};
                    slot_index = 6'd13 + {2'd0, req_item};
                end
            end
            // Feedback carries the current target item; ignore that payload.
            3'd3: begin logical_id = 16'd201; slot_index = 6'd28; end
            3'd4: begin logical_id = 16'd202; slot_index = 6'd29; end
            3'd6: begin logical_id = 16'd206; slot_index = 6'd33; end
            3'd7: begin logical_id = 16'd207; slot_index = 6'd34; end
            // Replay is already resolved to kind 1 or 2 by quiz_control.
            // Kinds 0 and 5 do not expose reserved prompts 203, 204 or 205.
            default: begin end
        endcase

        if (logical_id != 16'd0) begin
            physical_track = TRACKS[slot_index*16 +: 16];
            map_hit = (physical_track != 16'd0);
        end
    end
endmodule
