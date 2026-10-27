// I0309 V2: fixed "X0400 Y320" caption. No division, frame buffer, or font RAM.
// Binary conversion takes eleven clocks after the original SOF. The four
// pixel registers match processing + style (sample N -> output after N+3).
module pixel309_track_caption #(
    parameter integer X_ORIGIN=704,Y_ORIGIN=84
)(
    input wire clk,rst_n,in_frame_start,in_de,
    input wire [10:0] in_x,track_x,
    input wire [9:0] in_y,track_y,
    input wire track_valid,
    output wire out_ink
);
    reg visible,ready,busy;
    reg [3:0] shift_step;
    reg [10:0] binary_x,binary_y;
    reg [15:0] bcd_x;
    reg [11:0] bcd_y;
    wire [15:0] adjusted_x={
        bcd_x[15:12]>=5?bcd_x[15:12]+4'd3:bcd_x[15:12],
        bcd_x[11:8]>=5?bcd_x[11:8]+4'd3:bcd_x[11:8],
        bcd_x[7:4]>=5?bcd_x[7:4]+4'd3:bcd_x[7:4],
        bcd_x[3:0]>=5?bcd_x[3:0]+4'd3:bcd_x[3:0]};
    wire [11:0] adjusted_y={
        bcd_y[11:8]>=5?bcd_y[11:8]+4'd3:bcd_y[11:8],
        bcd_y[7:4]>=5?bcd_y[7:4]+4'd3:bcd_y[7:4],
        bcd_y[3:0]>=5?bcd_y[3:0]+4'd3:bcd_y[3:0]};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            visible<=0;ready<=0;busy<=0;shift_step<=0;
            binary_x<=0;binary_y<=0;bcd_x<=0;bcd_y<=0;
        end else if(in_frame_start)begin
            // Y uses three digits; the production 720-line raster always fits.
            visible<=track_valid && track_y<10'd1000;
            busy<=track_valid && track_y<10'd1000;
            ready<=0;shift_step<=0;
            binary_x<=track_x;binary_y<={1'b0,track_y};bcd_x<=0;bcd_y<=0;
        end else if(!track_valid)begin
            // Reappearance during this frame cannot resurrect the old caption.
            visible<=0;ready<=0;busy<=0;
        end else if(busy)begin
            bcd_x<={adjusted_x[14:0],binary_x[10]};
            bcd_y<={adjusted_y[10:0],binary_y[10]};
            binary_x<={binary_x[9:0],1'b0};
            binary_y<={binary_y[9:0],1'b0};
            if(shift_step==4'd10)begin ready<=1;busy<=0;end
            else shift_step<=shift_step+1'b1;
        end
    end

    // Five columns, seven rows, doubled in both axes; sixteen-pixel pitch.
    // Symbols 0..9 are decimal digits, A=X, B=Y, and F is blank.
    function [4:0] font_row;
        input [3:0] symbol;
        input [2:0] row;
        reg [34:0] bitmap;
        begin
            case(symbol)
                4'd0:bitmap=35'b01110_10001_10001_10001_10001_10001_01110;
                4'd1:bitmap=35'b00100_01100_00100_00100_00100_00100_01110;
                4'd2:bitmap=35'b01110_10001_00001_00010_00100_01000_11111;
                4'd3:bitmap=35'b11110_00001_00001_01110_00001_00001_11110;
                4'd4:bitmap=35'b00010_00110_01010_10010_11111_00010_00010;
                4'd5:bitmap=35'b11111_10000_10000_11110_00001_00001_11110;
                4'd6:bitmap=35'b01110_10000_10000_11110_10001_10001_01110;
                4'd7:bitmap=35'b11111_00001_00010_00100_01000_01000_01000;
                4'd8:bitmap=35'b01110_10001_10001_01110_10001_10001_01110;
                4'd9:bitmap=35'b01110_10001_10001_01111_00001_00001_01110;
                4'ha:bitmap=35'b10001_10001_01010_00100_01010_10001_10001;
                4'hb:bitmap=35'b10001_10001_01010_00100_00100_00100_00100;
                default:bitmap=35'd0;
            endcase
            case(row)
                0:font_row=bitmap[34:30];1:font_row=bitmap[29:25];
                2:font_row=bitmap[24:20];3:font_row=bitmap[19:15];
                4:font_row=bitmap[14:10];5:font_row=bitmap[9:5];
                6:font_row=bitmap[4:0];default:font_row=0;
            endcase
        end
    endfunction
    wire [10:0] local_x=in_x-X_ORIGIN;
    wire [9:0] local_y=in_y-Y_ORIGIN;
    wire text_area=in_x>=X_ORIGIN && in_x<X_ORIGIN+160 &&
        in_y>=Y_ORIGIN && in_y<Y_ORIGIN+14;
    reg [3:0] pixel_symbol;
    always @* begin
        case(local_x[7:4])
            0:pixel_symbol=4'ha;
            1:pixel_symbol=bcd_x[15:12];2:pixel_symbol=bcd_x[11:8];
            3:pixel_symbol=bcd_x[7:4];4:pixel_symbol=bcd_x[3:0];
            6:pixel_symbol=4'hb;
            7:pixel_symbol=bcd_y[11:8];8:pixel_symbol=bcd_y[7:4];
            9:pixel_symbol=bcd_y[3:0];default:pixel_symbol=4'hf;
        endcase
    end
    reg s0_active,s1_active,s2_ink,s3_ink;
    reg [3:0] s0_symbol;
    reg [2:0] s0_row,s0_column,s1_column;
    reg [4:0] s1_bits;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            s0_active<=0;s1_active<=0;s2_ink<=0;s3_ink<=0;
            s0_symbol<=4'hf;s0_row<=0;s0_column<=0;s1_column<=0;s1_bits<=0;
        end else begin
            // Never read the previous frame's BCD on the new SOF input pixel.
            s0_active<=in_de && text_area && visible && ready && track_valid && !in_frame_start;
            s0_symbol<=pixel_symbol;s0_row<=local_y[3:1];s0_column<=local_x[3:1];
            s1_bits<=font_row(s0_symbol,s0_row);s1_column<=s0_column;s1_active<=s0_active;
            s2_ink<=s1_active && s1_column<5 && s1_bits[4-s1_column];
            s3_ink<=s2_ink;
        end
    end
    assign out_ink=s3_ink;
endmodule
