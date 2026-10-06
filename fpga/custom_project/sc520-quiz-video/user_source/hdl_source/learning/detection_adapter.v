// Task-local adapter. Sample after both box and shape registers have settled.
// Coordinates are display pixels; division by four covers their 320x180 cells.
// This does not publish the shared capture-domain frame_id contract.
module detection_adapter (
    input wire clk, rst_n, flush, sample,
    input wire box_valid,
    input wire [1:0] box_color, shape_color, shape,
    input wire [10:0] left, right,
    input wire [9:0] top, bottom,
    input wire [7:0] box_count, shape_count,
    output reg det_update, present, det_valid,
    output reg [3:0] item_id,
    output reg [9:0] bbox_x, bbox_y, bbox_w, bbox_h,
    output reg [7:0] stable_count
);
    wire bounds_ok = left <= right && top <= bottom && right < 1280 && bottom < 720;
    wire qualified = box_valid && bounds_ok && box_color != 0 &&
        shape_color == box_color && shape != 0 && box_count >= 3 && shape_count >= 3;
    reg [3:0] mapped;
    always @* begin
        mapped = 0;
        case ({shape_color,shape})
            4'b0101: mapped=1; 4'b0110: mapped=2; 4'b0111: mapped=3;
            4'b1001: mapped=4; 4'b1010: mapped=5; 4'b1011: mapped=6;
            4'b1101: mapped=7; 4'b1110: mapped=8; 4'b1111: mapped=9;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            det_update<=0; present<=0; det_valid<=0; item_id<=0;
            bbox_x<=0; bbox_y<=0; bbox_w<=0; bbox_h<=0; stable_count<=0;
        end else if (flush) begin
            det_update<=0; present<=0; det_valid<=0; item_id<=0;
            bbox_x<=0; bbox_y<=0; bbox_w<=0; bbox_h<=0; stable_count<=0;
        end else begin
            det_update<=sample;
            if (sample) begin
                present<=box_valid; // Unknown shape must not rearm the presence latch.
                det_valid<=qualified;
                item_id<=qualified ? mapped : 4'd0;
                bbox_x<=qualified ? {1'b0,left[10:2]} : 10'd0;
                bbox_y<=qualified ? {2'b0,top[9:2]} : 10'd0;
                bbox_w<=qualified ? {1'b0,right[10:2]}-{1'b0,left[10:2]}+10'd1 : 10'd0;
                bbox_h<=qualified ? {2'b0,bottom[9:2]}-{2'b0,top[9:2]}+10'd1 : 10'd0;
                stable_count<=qualified ? (box_count < shape_count ? box_count : shape_count) : 8'd0;
            end
        end
    end
endmodule
