// Display-only diagnostics: 16x24 character cells, 5x7 glyphs at 2x scale.
// Coordinates/status are sampled at the same pre-OSD pixel clock as pixel14.
module pixel14_diag_osd (
    input wire clk,rst_n,frame_start,
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [255:0] diagnostic,
    input wire [7:0] business_flags,
    output reg active,
    output reg [23:0] rgb
);
    reg [255:0] snapshot;
    reg [7:0] business;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin snapshot<=0;business<=0;end
        else if(frame_start) begin snapshot<=diagnostic;business<=business_flags;end
    wire region_active=pixel_x>=32 && pixel_x<800 && pixel_y>=520 && pixel_y<592;
    wire [10:0] dx=pixel_x-32;
    wire [5:0] column=dx[9:4];
    reg [1:0] line;
    reg [4:0] dy;
    always @* begin
        if(pixel_y<544) begin line=0;dy=pixel_y-520;end
        else if(pixel_y<568) begin line=1;dy=pixel_y-544;end
        else begin line=2;dy=pixel_y-568;end
    end
    function [7:0] hexchar;
        input [3:0] value;
        begin hexchar=value<10 ? 8'h30+value : 8'h41+(value-10);end
    endfunction
    function [7:0] digit;
        input [31:0] value;
        input [2:0] index;
        begin
            case(index)
                0:digit=hexchar(value[3:0]);1:digit=hexchar(value[7:4]);
                2:digit=hexchar(value[11:8]);3:digit=hexchar(value[15:12]);
                4:digit=hexchar(value[19:16]);5:digit=hexchar(value[23:20]);
                6:digit=hexchar(value[27:24]);default:digit=hexchar(value[31:28]);
            endcase
        end
    endfunction
    reg [7:0] character;
    always @* begin
        character=8'h20;
        case(line)
            0: begin
                // D0107 Ehhhh Hhhhh Fhhhh Bhh
                case(column)
                    0:character="D";6:character="E";12:character="H";
                    18:character="F";24:character="B";
                    default:begin
                        if(column>=1 && column<=4) character=digit({16'd0,snapshot[255:240]},4-column);
                        else if(column>=7 && column<=10) character=digit({16'd0,snapshot[239:224]},10-column);
                        else if(column>=13 && column<=16) character=digit({16'd0,snapshot[223:208]},16-column);
                        else if(column>=19 && column<=22) character=digit({16'd0,snapshot[207:192]},22-column);
                        else if(column>=25 && column<=26) character=digit({24'd0,business},26-column);
                    end
                endcase
            end
            1: begin
                // Chhhhh Rhhhhh Ihhhhh
                case(column)
                    0:character="C";7:character="R";14:character="I";
                    default:begin
                        if(column>=1 && column<=5) character=digit(snapshot[191:160],5-column);
                        else if(column>=8 && column<=12) character=digit(snapshot[159:128],12-column);
                        else if(column>=15 && column<=19) character=digit(snapshot[127:96],19-column);
                    end
                endcase
            end
            default: begin
                // Lhhhh Yhhhh Ahhhhhh Nhhhh Ghhhh
                case(column)
                    0:character="L";6:character="Y";12:character="A";
                    20:character="N";26:character="G";
                    default:begin
                        if(column>=1 && column<=4) character=digit({16'd0,snapshot[95:80]},4-column);
                        else if(column>=7 && column<=10) character=digit({16'd0,snapshot[79:64]},10-column);
                        else if(column>=13 && column<=18) character=digit(snapshot[63:32],18-column);
                        else if(column>=21 && column<=24) character=digit({16'd0,snapshot[31:16]},24-column);
                        else if(column>=27 && column<=30) character=digit({16'd0,snapshot[15:0]},30-column);
                    end
                endcase
            end
        endcase
    end
    function [4:0] glyph;
        input [7:0] ch;
        input [2:0] row;
        reg [34:0] bitmap;
        begin
            case(ch)
                "0":bitmap=35'b01110_10001_10011_10101_11001_10001_01110;
                "1":bitmap=35'b00100_01100_00100_00100_00100_00100_01110;
                "2":bitmap=35'b01110_10001_00001_00010_00100_01000_11111;
                "3":bitmap=35'b11110_00001_00001_01110_00001_00001_11110;
                "4":bitmap=35'b00010_00110_01010_10010_11111_00010_00010;
                "5":bitmap=35'b11111_10000_10000_11110_00001_00001_11110;
                "6":bitmap=35'b01110_10000_10000_11110_10001_10001_01110;
                "7":bitmap=35'b11111_00001_00010_00100_01000_01000_01000;
                "8":bitmap=35'b01110_10001_10001_01110_10001_10001_01110;
                "9":bitmap=35'b01110_10001_10001_01111_00001_00001_01110;
                "A":bitmap=35'b01110_10001_10001_11111_10001_10001_10001;
                "B":bitmap=35'b11110_10001_10001_11110_10001_10001_11110;
                "C":bitmap=35'b01111_10000_10000_10000_10000_10000_01111;
                "D":bitmap=35'b11110_10001_10001_10001_10001_10001_11110;
                "E":bitmap=35'b11111_10000_10000_11110_10000_10000_11111;
                "F":bitmap=35'b11111_10000_10000_11110_10000_10000_10000;
                "G":bitmap=35'b01111_10000_10000_10111_10001_10001_01111;
                "H":bitmap=35'b10001_10001_10001_11111_10001_10001_10001;
                "I":bitmap=35'b01110_00100_00100_00100_00100_00100_01110;
                "L":bitmap=35'b10000_10000_10000_10000_10000_10000_11111;
                "N":bitmap=35'b10001_11001_11001_10101_10011_10011_10001;
                "R":bitmap=35'b11110_10001_10001_11110_10100_10010_10001;
                "Y":bitmap=35'b10001_10001_01010_00100_00100_00100_00100;
                default:bitmap=0;
            endcase
            case(row)
                0:glyph=bitmap[34:30];1:glyph=bitmap[29:25];2:glyph=bitmap[24:20];
                3:glyph=bitmap[19:15];4:glyph=bitmap[14:10];5:glyph=bitmap[9:5];
                6:glyph=bitmap[4:0];default:glyph=0;
            endcase
        end
    endfunction
    wire [4:0] dots=glyph(character,dy[3:1]);
    wire lit=dx[3:0]<10 && dy<14 && dots[4-dx[3:1]];
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin active<=0;rgb<=0;end
        else begin
            active<=region_active;
            rgb<=!region_active ? 24'd0 : lit ? 24'hffff80 : 24'h101820;
        end
endmodule
