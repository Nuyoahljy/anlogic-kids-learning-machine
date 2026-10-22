// Original panel geometry, original synchronous font, exactly one layer.
module pixel30_panel(
    input wire clk,rst_n,input wire [10:0] pixel_x,input wire [9:0] pixel_y,
    input wire [27:0] status,input wire display_mode,
    output wire active,output wire [23:0] rgb
);
    wire top_panel=pixel_y>=8 && pixel_y<112;
    wire bottom_panel=pixel_y>=608 && pixel_y<712;
    wire [9:0] local_y=bottom_panel ? pixel_y-612:pixel_y-12;
    wire [10:0] local_x=pixel_x-48;
    wire [2:0] line_index={1'b0,local_y[6:5]}+(bottom_panel ? 3'd3:3'd0);
    wire text_area=pixel_x>=48 && pixel_x<(bottom_panel ? 1232:1008) &&
        ((pixel_y>=12 && pixel_y<108) || (pixel_y>=612 && pixel_y<708));
    wire panel_active=pixel_x>=32 && pixel_x<1248 && (top_panel || bottom_panel);
    wire [7:0] glyph;wire [1:0] tone;wire [15:0] font_bits;
    items30_content content(
        .line_index(line_index),.char_index(local_x[10:5]),.mode(status[27:26]),.phase(status[25:24]),
        .score(status[23:20]),.question_index(status[19:16]),.target_item(status[15:12]),.display_item(status[11:8]),
        .feedback(status[7:5]),.source_test(status[4]),.armed(status[3]),
        .audio_fault(status[2]),.audio_busy(status[1]),.result_healthy(status[0]),.display_mode(display_mode),
        .glyph(glyph),.tone(tone));
    items14_font_rom font(.clk(clk),.glyph(glyph),.row(local_y[4:1]),.bits(font_bits));
    reg active_d,text_d;reg [3:0] column_d;reg [1:0] tone_d;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin active_d<=0;text_d<=0;column_d<=0;tone_d<=0;end
        else begin active_d<=panel_active;text_d<=text_area;column_d<=local_x[4:1];tone_d<=tone;end
    wire [23:0] ink=tone_d==1 ? 24'habe8f2:tone_d==2 ? 24'hffe3a3:tone_d==3 ? 24'h9ef0cc:24'hf5f7fa;
    assign active=active_d;
    assign rgb=!active_d ? 24'd0:text_d && font_bits[15-column_d] ? ink:24'h18242c;
endmodule

// Coordinates at N, packet-derived pixels at N+1. Snapshot is owned by compositor.
module pixel30_diagnostic #(parameter [15:0] VERSION=16'h0300)(
    input wire clk,rst_n,input wire [10:0] pixel_x,input wire [9:0] pixel_y,
    input wire [191:0] packet,input wire usable,input wire [7:0] age,
    output reg active,output reg [23:0] rgb
);
    wire region_next=pixel_x>=32 && pixel_x<800 && pixel_y>=520 && pixel_y<592;
    wire [10:0] dx=pixel_x-32;wire [9:0] dy=pixel_y-520;
    reg region;reg [2:0] row;reg [6:0] column;reg [2:0] dot_x;reg [3:0] dot_y;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin region<=0;row<=0;column<=0;dot_x<=0;dot_y<=0;end
        else begin
            region<=region_next;row<=dy/12;column<=dx[9:3];dot_x<=dx[2:0];dot_y<=dy%12;
        end
    function [7:0] digit;
        input [31:0] value;input [3:0] index;reg [3:0] nibble;
        begin nibble=value>>(index*4);digit=nibble<10 ? "0"+nibble:"A"+nibble-10;end
    endfunction
    function [7:0] single_digit;
        input available;input [31:0] value;input trailing;
        begin
            single_digit=available ? (trailing ? " ":digit(value,0)):(trailing ? "A":"N");
        end
    endfunction
    function [7:0] field_digit;
        input available;input [31:0] value;input [3:0] index,length;
        begin
            if(available)field_digit=digit(value,index);
            else field_digit=index==length-1 ? "N":index==length-2 ? "A":" ";
        end
    endfunction
    wire identity=usable && packet[186];
    wire scene_available=identity && packet[100];
    wire shape_available=identity && packet[101];
    wire card_available=identity && packet[102];
    wire arbitration_available=identity && packet[103];
    reg [7:0] character;
    always @* begin
        character=" ";
        case(row)
            0:case(column)
                0:character="D";1,2,3,4:character=digit({16'd0,VERSION},4-column);
                6:character="F";7,8,9,10,11,12,13,14:character=field_digit(identity,packet[31:0],14-column,8);
                16:character="H";17,18:character=single_digit(identity,{31'd0,packet[33]},column==18);
                20:character="P";21,22:character=single_digit(scene_available,{31'd0,packet[34]},column==22);
                24:character="V";25:character=digit({31'd0,identity&&packet[35]&&!packet[36]&&packet[33]},0);
                27:character="R";28:character=digit({31'd0,!identity||packet[36]},0);
                30:character="I";31,32:character=single_digit(identity&&packet[33]&&!packet[36],{28'd0,packet[43:40]},column==32);
                34:character="A";35,36:character=digit({24'd0,age},36-column);
                38:character="T";39,40:character=single_digit(identity,{31'd0,packet[32]},column==40);
                default:character=" ";
            endcase
            1:case(column)
                0:character="S";1:character="C";2,3,4,5:character=field_digit(scene_available,{16'd0,packet[79:64]},5-column,4);
                7:character="G";8:character="L";9,10,11,12:character=field_digit(scene_available,{16'd0,packet[95:80]},12-column,4);
                14:character="C";15:character="L";16,17:character=single_digit(scene_available,{31'd0,packet[37]},column==17);
                19:character="B";20,21:character=single_digit(scene_available,{31'd0,packet[38]},column==21);
                23:character="P";24,25:character=single_digit(scene_available,{31'd0,packet[39]},column==25);
                27:character="A";28:character="V";29:character=digit({29'd0,{card_available,shape_available,scene_available}},0);
                31:character="K";32:character=digit({31'd0,identity},0);
                default:character=" ";
            endcase
            2:case(column)
                0:character="S";1:character="H";2,3:character=single_digit(shape_available,{29'd0,packet[54:52]},column==3);
                5:character="C";6,7,8:character=field_digit(shape_available,{21'd0,packet[122:112]},8-column,3);
                10:character="Q";11,12,13:character=field_digit(shape_available,{21'd0,packet[133:123]},13-column,3);
                15:character="T";16,17,18:character=field_digit(shape_available,{21'd0,packet[144:134]},18-column,3);
                20:character="S";21:character="I";22,23:character=single_digit(shape_available,{28'd0,packet[47:44]},column==23);
                default:character=" ";
            endcase
            3:case(column)
                0:character="C";1:character="W";2,3:character=single_digit(card_available,{28'd0,packet[51:48]},column==3);
                5:character="C";6:character="Q";7,8:character=single_digit(card_available,{31'd0,packet[55]},column==8);
                10:character="B";11,12,13:character=field_digit(card_available,{21'd0,packet[155:145]},13-column,3);
                15:character="S";16,17,18:character=field_digit(card_available,{21'd0,packet[166:156]},18-column,3);
                20:character="F";21:character="G";22,23,24:character=field_digit(card_available,{21'd0,packet[177:167]},24-column,3);
                default:character=" ";
            endcase
            4:case(column)
                0:character="A";1:character="R";2,3:character=single_digit(arbitration_available,{28'd0,packet[99:96]},column==3);
                4:character="D";5:character="N";6:character=digit({31'd0,arbitration_available},0);
                8:character="C";9:character="N";10,11:character=field_digit(identity,{24'd0,packet[63:56]},11-column,2);
                13:character="R";14:character="S";15,16:character=field_digit(identity,{24'd0,packet[111:104]},16-column,2);
                default:character=" ";
            endcase
            5:case(column)
                0:character="C";1:character="A";2:character="T";3,4:character=single_digit(identity,{28'd0,packet[185:182]},column==4);
                6:character="R";7:character="E";8:character="V";9,10:character=single_digit(identity,{28'd0,packet[181:178]},column==10);
                12:character="F";13:character="R";14:character=digit({31'd0,usable},0);
                default:character=" ";
            endcase
            default:character=" ";
        endcase
    end
    function [4:0] glyph;
        input [7:0] ch;input [2:0] line;reg [34:0] bitmap;
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
                "K":bitmap=35'b10001_10010_10100_11000_10100_10010_10001;
                "L":bitmap=35'b10000_10000_10000_10000_10000_10000_11111;
                "N":bitmap=35'b10001_11001_11001_10101_10011_10011_10001;
                "P":bitmap=35'b11110_10001_10001_11110_10000_10000_10000;
                "Q":bitmap=35'b01110_10001_10001_10001_10101_10010_01101;
                "R":bitmap=35'b11110_10001_10001_11110_10100_10010_10001;
                "S":bitmap=35'b01111_10000_10000_01110_00001_00001_11110;
                "T":bitmap=35'b11111_00100_00100_00100_00100_00100_00100;
                "V":bitmap=35'b10001_10001_10001_10001_10001_01010_00100;
                "W":bitmap=35'b10001_10001_10001_10101_10101_11011_10001;
                default:bitmap=0;
            endcase
            case(line)
                0:glyph=bitmap[34:30];1:glyph=bitmap[29:25];2:glyph=bitmap[24:20];
                3:glyph=bitmap[19:15];4:glyph=bitmap[14:10];5:glyph=bitmap[9:5];
                6:glyph=bitmap[4:0];default:glyph=0;
            endcase
        end
    endfunction
    wire [4:0] dots=glyph(character,dot_y[2:0]);
    wire lit=dot_x<5 && dot_y<7 && dots[4-dot_x];
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin active<=0;rgb<=0;end
        else begin active<=region;rgb<=region ? (lit ? (identity&&packet[33]&&!packet[36] ? 24'hffff80:24'hff9c9c):24'h101820):24'd0;end
endmodule
