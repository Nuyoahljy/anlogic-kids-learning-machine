// T023: coordinate register at N, RGB register at N+1. One packet snapshot.
// Six row-local character selectors; original six 8x12 rows and glyphs retained.
module pixel23_color_diag_osd #(parameter [15:0] VERSION=16'h0220)(
    input wire clk,rst_n,frame_start,
    input wire [10:0] pixel_x,input wire [9:0] pixel_y,
    input wire [799:0] packet,input wire fresh,input wire [7:0] age_ms,
    input wire [255:0] diagnostic,input wire [31:0] i2c_diagnostic,input wire [7:0] business_flags,
    output reg active,output reg [23:0] rgb);
    reg [799:0] snapshot;reg [255:0] capture_snapshot;reg [31:0] i2c_snapshot;reg [7:0] business,age;
    reg snapshot_fresh,invalidated;
    wire display_fresh=snapshot_fresh && !invalidated && fresh;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin snapshot<=0;capture_snapshot<=0;i2c_snapshot<=0;business<=0;age<=255;snapshot_fresh<=0;invalidated<=0;end
        else if(frame_start)begin snapshot<=packet;capture_snapshot<=diagnostic;i2c_snapshot<=i2c_diagnostic;business<=business_flags;age<=age_ms;snapshot_fresh<=fresh;invalidated<=0;end
        else if(!fresh)invalidated<=1;
    wire region_next=pixel_x>=32 && pixel_x<800 && pixel_y>=520 && pixel_y<592;
    wire [10:0] dx=pixel_x-32;wire [6:0] column_next=dx[9:3];
    reg [2:0] row_next;reg [3:0] dy_next;
    always @* begin
        if(pixel_y<532)begin row_next=0;dy_next=pixel_y-520;end
        else if(pixel_y<544)begin row_next=1;dy_next=pixel_y-532;end
        else if(pixel_y<556)begin row_next=2;dy_next=pixel_y-544;end
        else if(pixel_y<568)begin row_next=3;dy_next=pixel_y-556;end
        else if(pixel_y<580)begin row_next=4;dy_next=pixel_y-568;end
        else begin row_next=5;dy_next=pixel_y-580;end
    end
    wire center_next=pixel_x>=634 && pixel_x<646 && pixel_y>=354 && pixel_y<366 &&
        (pixel_x==634 || pixel_x==645 || pixel_y==354 || pixel_y==365);
    wire paper_next=pixel_x>=190 && pixel_x<202 && pixel_y>=142 && pixel_y<154 &&
        (pixel_x==190 || pixel_x==201 || pixel_y==142 || pixel_y==153);
    reg region,center_mark,paper_mark;
    reg [5:0] row_select;
    reg [6:0] column;
    reg [2:0] dot_x;
    reg [3:0] dy;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin region<=0;center_mark<=0;paper_mark<=0;row_select<=0;column<=0;dot_x<=0;dy<=0;end
        else begin
            region<=region_next;center_mark<=center_next;paper_mark<=paper_next;
            row_select<=6'b000001<<row_next;column<=column_next;dot_x<=dx[2:0];dy<=dy_next;
        end
    function [7:0] digit;input [31:0] value;input [2:0] index;reg [3:0] nibble;
        begin nibble=value>>(index*4);digit=nibble<10 ? "0"+nibble:"A"+nibble-10;end
    endfunction
    reg [7:0] row_character[0:5];
    always @* begin row_character[0]=" ";case(column)
        7'd0:row_character[0]=8'h44;
        7'd1:row_character[0]=digit({16'd0,VERSION},3'd3);
        7'd2:row_character[0]=digit({16'd0,VERSION},3'd2);
        7'd3:row_character[0]=digit({16'd0,VERSION},3'd1);
        7'd4:row_character[0]=digit({16'd0,VERSION},3'd0);
        7'd6:row_character[0]=8'h46;
        7'd7:row_character[0]=digit(snapshot[31:0],3'd7);
        7'd8:row_character[0]=digit(snapshot[31:0],3'd6);
        7'd9:row_character[0]=digit(snapshot[31:0],3'd5);
        7'd10:row_character[0]=digit(snapshot[31:0],3'd4);
        7'd11:row_character[0]=digit(snapshot[31:0],3'd3);
        7'd12:row_character[0]=digit(snapshot[31:0],3'd2);
        7'd13:row_character[0]=digit(snapshot[31:0],3'd1);
        7'd14:row_character[0]=digit(snapshot[31:0],3'd0);
        7'd16:row_character[0]=8'h56;
        7'd17:row_character[0]=(snapshot[780] && display_fresh) ? "1":"0";
        7'd19:row_character[0]=8'h41;
        7'd20:row_character[0]=digit({24'd0,age},3'd1);
        7'd21:row_character[0]=digit({24'd0,age},3'd0);
        7'd23:row_character[0]=8'h58;
        7'd24:row_character[0]=digit({24'd0,snapshot[779:772]},3'd1);
        7'd25:row_character[0]=digit({24'd0,snapshot[779:772]},3'd0);
        7'd27:row_character[0]=8'h45;
        7'd28:row_character[0]=digit({16'd0,capture_snapshot[239:224]},3'd3);
        7'd29:row_character[0]=digit({16'd0,capture_snapshot[239:224]},3'd2);
        7'd30:row_character[0]=digit({16'd0,capture_snapshot[239:224]},3'd1);
        7'd31:row_character[0]=digit({16'd0,capture_snapshot[239:224]},3'd0);
        7'd33:row_character[0]=8'h42;
        7'd34:row_character[0]=digit({24'd0,business},3'd1);
        7'd35:row_character[0]=digit({24'd0,business},3'd0);
        7'd37:row_character[0]=8'h51;
        7'd38:row_character[0]=digit(i2c_snapshot,3'd7);
        7'd39:row_character[0]=digit(i2c_snapshot,3'd6);
        7'd40:row_character[0]=digit(i2c_snapshot,3'd5);
        7'd41:row_character[0]=digit(i2c_snapshot,3'd4);
        7'd42:row_character[0]=digit(i2c_snapshot,3'd3);
        7'd43:row_character[0]=digit(i2c_snapshot,3'd2);
        7'd44:row_character[0]=digit(i2c_snapshot,3'd1);
        7'd45:row_character[0]=digit(i2c_snapshot,3'd0);
        7'd47:row_character[0]=8'h47;
        7'd48:row_character[0]=8'h52;
        7'd49:row_character[0]=digit({23'd0,snapshot[412:404]},3'd2);
        7'd50:row_character[0]=digit({23'd0,snapshot[412:404]},3'd1);
        7'd51:row_character[0]=digit({23'd0,snapshot[412:404]},3'd0);
        7'd53:row_character[0]=8'h47;
        7'd54:row_character[0]=8'h42;
        7'd55:row_character[0]=digit({23'd0,snapshot[421:413]},3'd2);
        7'd56:row_character[0]=digit({23'd0,snapshot[421:413]},3'd1);
        7'd57:row_character[0]=digit({23'd0,snapshot[421:413]},3'd0);
        7'd59:row_character[0]=8'h4e;
        7'd60:row_character[0]=digit({11'd0,snapshot[442:422]},3'd5);
        7'd61:row_character[0]=digit({11'd0,snapshot[442:422]},3'd4);
        7'd62:row_character[0]=digit({11'd0,snapshot[442:422]},3'd3);
        7'd63:row_character[0]=digit({11'd0,snapshot[442:422]},3'd2);
        7'd64:row_character[0]=digit({11'd0,snapshot[442:422]},3'd1);
        7'd65:row_character[0]=digit({11'd0,snapshot[442:422]},3'd0);
        7'd67:row_character[0]=8'h57;
        7'd68:row_character[0]=8'h31;
        7'd70:row_character[0]=8'h54;
        7'd71:row_character[0]=8'h31;
        default:row_character[0]=" ";
    endcase end
    always @* begin row_character[1]=" ";case(column)
        7'd0:row_character[1]=8'h43;
        7'd1:row_character[1]=8'h30;
        7'd2:row_character[1]=digit({8'd0,snapshot[55:32]},3'd5);
        7'd3:row_character[1]=digit({8'd0,snapshot[55:32]},3'd4);
        7'd4:row_character[1]=digit({8'd0,snapshot[55:32]},3'd3);
        7'd5:row_character[1]=digit({8'd0,snapshot[55:32]},3'd2);
        7'd6:row_character[1]=digit({8'd0,snapshot[55:32]},3'd1);
        7'd7:row_character[1]=digit({8'd0,snapshot[55:32]},3'd0);
        7'd9:row_character[1]=8'h43;
        7'd10:row_character[1]=8'h31;
        7'd11:row_character[1]=digit({8'd0,snapshot[79:56]},3'd5);
        7'd12:row_character[1]=digit({8'd0,snapshot[79:56]},3'd4);
        7'd13:row_character[1]=digit({8'd0,snapshot[79:56]},3'd3);
        7'd14:row_character[1]=digit({8'd0,snapshot[79:56]},3'd2);
        7'd15:row_character[1]=digit({8'd0,snapshot[79:56]},3'd1);
        7'd16:row_character[1]=digit({8'd0,snapshot[79:56]},3'd0);
        7'd18:row_character[1]=8'h43;
        7'd19:row_character[1]=8'h32;
        7'd20:row_character[1]=digit({8'd0,snapshot[103:80]},3'd5);
        7'd21:row_character[1]=digit({8'd0,snapshot[103:80]},3'd4);
        7'd22:row_character[1]=digit({8'd0,snapshot[103:80]},3'd3);
        7'd23:row_character[1]=digit({8'd0,snapshot[103:80]},3'd2);
        7'd24:row_character[1]=digit({8'd0,snapshot[103:80]},3'd1);
        7'd25:row_character[1]=digit({8'd0,snapshot[103:80]},3'd0);
        7'd27:row_character[1]=8'h50;
        7'd28:row_character[1]=8'h30;
        7'd29:row_character[1]=digit({8'd0,snapshot[127:104]},3'd5);
        7'd30:row_character[1]=digit({8'd0,snapshot[127:104]},3'd4);
        7'd31:row_character[1]=digit({8'd0,snapshot[127:104]},3'd3);
        7'd32:row_character[1]=digit({8'd0,snapshot[127:104]},3'd2);
        7'd33:row_character[1]=digit({8'd0,snapshot[127:104]},3'd1);
        7'd34:row_character[1]=digit({8'd0,snapshot[127:104]},3'd0);
        7'd36:row_character[1]=8'h50;
        7'd37:row_character[1]=8'h31;
        7'd38:row_character[1]=digit({8'd0,snapshot[151:128]},3'd5);
        7'd39:row_character[1]=digit({8'd0,snapshot[151:128]},3'd4);
        7'd40:row_character[1]=digit({8'd0,snapshot[151:128]},3'd3);
        7'd41:row_character[1]=digit({8'd0,snapshot[151:128]},3'd2);
        7'd42:row_character[1]=digit({8'd0,snapshot[151:128]},3'd1);
        7'd43:row_character[1]=digit({8'd0,snapshot[151:128]},3'd0);
        7'd45:row_character[1]=8'h50;
        7'd46:row_character[1]=8'h32;
        7'd47:row_character[1]=digit({8'd0,snapshot[175:152]},3'd5);
        7'd48:row_character[1]=digit({8'd0,snapshot[175:152]},3'd4);
        7'd49:row_character[1]=digit({8'd0,snapshot[175:152]},3'd3);
        7'd50:row_character[1]=digit({8'd0,snapshot[175:152]},3'd2);
        7'd51:row_character[1]=digit({8'd0,snapshot[175:152]},3'd1);
        7'd52:row_character[1]=digit({8'd0,snapshot[175:152]},3'd0);
        7'd54:row_character[1]=8'h43;
        7'd55:row_character[1]=8'h32;
        7'd56:row_character[1]=8'h38;
        7'd57:row_character[1]=8'h30;
        7'd58:row_character[1]=8'h2c;
        7'd59:row_character[1]=8'h31;
        7'd60:row_character[1]=8'h36;
        7'd61:row_character[1]=8'h38;
        7'd63:row_character[1]=8'h50;
        7'd64:row_character[1]=8'h30;
        7'd65:row_character[1]=8'h43;
        7'd66:row_character[1]=8'h34;
        7'd67:row_character[1]=8'h2c;
        7'd68:row_character[1]=8'h30;
        7'd69:row_character[1]=8'h39;
        7'd70:row_character[1]=8'h34;
        default:row_character[1]=" ";
    endcase end
    always @* begin row_character[2]=" ";case(column)
        7'd0:row_character[2]=8'h4d;
        7'd1:row_character[2]=8'h43;
        7'd2:row_character[2]=8'h30;
        7'd3:row_character[2]=digit({8'd0,snapshot[199:176]},3'd5);
        7'd4:row_character[2]=digit({8'd0,snapshot[199:176]},3'd4);
        7'd5:row_character[2]=digit({8'd0,snapshot[199:176]},3'd3);
        7'd6:row_character[2]=digit({8'd0,snapshot[199:176]},3'd2);
        7'd7:row_character[2]=digit({8'd0,snapshot[199:176]},3'd1);
        7'd8:row_character[2]=digit({8'd0,snapshot[199:176]},3'd0);
        7'd10:row_character[2]=8'h4d;
        7'd11:row_character[2]=8'h43;
        7'd12:row_character[2]=8'h31;
        7'd13:row_character[2]=digit({8'd0,snapshot[223:200]},3'd5);
        7'd14:row_character[2]=digit({8'd0,snapshot[223:200]},3'd4);
        7'd15:row_character[2]=digit({8'd0,snapshot[223:200]},3'd3);
        7'd16:row_character[2]=digit({8'd0,snapshot[223:200]},3'd2);
        7'd17:row_character[2]=digit({8'd0,snapshot[223:200]},3'd1);
        7'd18:row_character[2]=digit({8'd0,snapshot[223:200]},3'd0);
        7'd20:row_character[2]=8'h4d;
        7'd21:row_character[2]=8'h43;
        7'd22:row_character[2]=8'h32;
        7'd23:row_character[2]=digit({8'd0,snapshot[247:224]},3'd5);
        7'd24:row_character[2]=digit({8'd0,snapshot[247:224]},3'd4);
        7'd25:row_character[2]=digit({8'd0,snapshot[247:224]},3'd3);
        7'd26:row_character[2]=digit({8'd0,snapshot[247:224]},3'd2);
        7'd27:row_character[2]=digit({8'd0,snapshot[247:224]},3'd1);
        7'd28:row_character[2]=digit({8'd0,snapshot[247:224]},3'd0);
        7'd30:row_character[2]=8'h4d;
        7'd31:row_character[2]=8'h50;
        7'd32:row_character[2]=8'h30;
        7'd33:row_character[2]=digit({8'd0,snapshot[271:248]},3'd5);
        7'd34:row_character[2]=digit({8'd0,snapshot[271:248]},3'd4);
        7'd35:row_character[2]=digit({8'd0,snapshot[271:248]},3'd3);
        7'd36:row_character[2]=digit({8'd0,snapshot[271:248]},3'd2);
        7'd37:row_character[2]=digit({8'd0,snapshot[271:248]},3'd1);
        7'd38:row_character[2]=digit({8'd0,snapshot[271:248]},3'd0);
        7'd40:row_character[2]=8'h4d;
        7'd41:row_character[2]=8'h50;
        7'd42:row_character[2]=8'h31;
        7'd43:row_character[2]=digit({8'd0,snapshot[295:272]},3'd5);
        7'd44:row_character[2]=digit({8'd0,snapshot[295:272]},3'd4);
        7'd45:row_character[2]=digit({8'd0,snapshot[295:272]},3'd3);
        7'd46:row_character[2]=digit({8'd0,snapshot[295:272]},3'd2);
        7'd47:row_character[2]=digit({8'd0,snapshot[295:272]},3'd1);
        7'd48:row_character[2]=digit({8'd0,snapshot[295:272]},3'd0);
        7'd50:row_character[2]=8'h4d;
        7'd51:row_character[2]=8'h50;
        7'd52:row_character[2]=8'h32;
        7'd53:row_character[2]=digit({8'd0,snapshot[319:296]},3'd5);
        7'd54:row_character[2]=digit({8'd0,snapshot[319:296]},3'd4);
        7'd55:row_character[2]=digit({8'd0,snapshot[319:296]},3'd3);
        7'd56:row_character[2]=digit({8'd0,snapshot[319:296]},3'd2);
        7'd57:row_character[2]=digit({8'd0,snapshot[319:296]},3'd1);
        7'd58:row_character[2]=digit({8'd0,snapshot[319:296]},3'd0);
        7'd60:row_character[2]=8'h30;
        7'd61:row_character[2]=8'h3d;
        7'd62:row_character[2]=8'h52;
        7'd63:row_character[2]=8'h41;
        7'd64:row_character[2]=8'h57;
        7'd66:row_character[2]=8'h31;
        7'd67:row_character[2]=8'h3d;
        7'd68:row_character[2]=8'h57;
        7'd69:row_character[2]=8'h42;
        7'd71:row_character[2]=8'h32;
        7'd72:row_character[2]=8'h3d;
        7'd73:row_character[2]=8'h54;
        7'd74:row_character[2]=8'h4f;
        7'd75:row_character[2]=8'h4e;
        7'd76:row_character[2]=8'h45;
        default:row_character[2]=" ";
    endcase end
    always @* begin row_character[3]=" ";case(column)
        7'd0:row_character[3]=8'h52;
        7'd1:row_character[3]=digit({12'd0,snapshot[462:443]},3'd4);
        7'd2:row_character[3]=digit({12'd0,snapshot[462:443]},3'd3);
        7'd3:row_character[3]=digit({12'd0,snapshot[462:443]},3'd2);
        7'd4:row_character[3]=digit({12'd0,snapshot[462:443]},3'd1);
        7'd5:row_character[3]=digit({12'd0,snapshot[462:443]},3'd0);
        7'd7:row_character[3]=8'h2f;
        7'd8:row_character[3]=digit({12'd0,snapshot[522:503]},3'd4);
        7'd9:row_character[3]=digit({12'd0,snapshot[522:503]},3'd3);
        7'd10:row_character[3]=digit({12'd0,snapshot[522:503]},3'd2);
        7'd11:row_character[3]=digit({12'd0,snapshot[522:503]},3'd1);
        7'd12:row_character[3]=digit({12'd0,snapshot[522:503]},3'd0);
        7'd14:row_character[3]=8'h2f;
        7'd15:row_character[3]=digit({12'd0,snapshot[582:563]},3'd4);
        7'd16:row_character[3]=digit({12'd0,snapshot[582:563]},3'd3);
        7'd17:row_character[3]=digit({12'd0,snapshot[582:563]},3'd2);
        7'd18:row_character[3]=digit({12'd0,snapshot[582:563]},3'd1);
        7'd19:row_character[3]=digit({12'd0,snapshot[582:563]},3'd0);
        7'd21:row_character[3]=8'h59;
        7'd22:row_character[3]=digit({12'd0,snapshot[482:463]},3'd4);
        7'd23:row_character[3]=digit({12'd0,snapshot[482:463]},3'd3);
        7'd24:row_character[3]=digit({12'd0,snapshot[482:463]},3'd2);
        7'd25:row_character[3]=digit({12'd0,snapshot[482:463]},3'd1);
        7'd26:row_character[3]=digit({12'd0,snapshot[482:463]},3'd0);
        7'd28:row_character[3]=8'h2f;
        7'd29:row_character[3]=digit({12'd0,snapshot[542:523]},3'd4);
        7'd30:row_character[3]=digit({12'd0,snapshot[542:523]},3'd3);
        7'd31:row_character[3]=digit({12'd0,snapshot[542:523]},3'd2);
        7'd32:row_character[3]=digit({12'd0,snapshot[542:523]},3'd1);
        7'd33:row_character[3]=digit({12'd0,snapshot[542:523]},3'd0);
        7'd35:row_character[3]=8'h2f;
        7'd36:row_character[3]=digit({12'd0,snapshot[602:583]},3'd4);
        7'd37:row_character[3]=digit({12'd0,snapshot[602:583]},3'd3);
        7'd38:row_character[3]=digit({12'd0,snapshot[602:583]},3'd2);
        7'd39:row_character[3]=digit({12'd0,snapshot[602:583]},3'd1);
        7'd40:row_character[3]=digit({12'd0,snapshot[602:583]},3'd0);
        7'd42:row_character[3]=8'h42;
        7'd43:row_character[3]=digit({12'd0,snapshot[502:483]},3'd4);
        7'd44:row_character[3]=digit({12'd0,snapshot[502:483]},3'd3);
        7'd45:row_character[3]=digit({12'd0,snapshot[502:483]},3'd2);
        7'd46:row_character[3]=digit({12'd0,snapshot[502:483]},3'd1);
        7'd47:row_character[3]=digit({12'd0,snapshot[502:483]},3'd0);
        7'd49:row_character[3]=8'h2f;
        7'd50:row_character[3]=digit({12'd0,snapshot[562:543]},3'd4);
        7'd51:row_character[3]=digit({12'd0,snapshot[562:543]},3'd3);
        7'd52:row_character[3]=digit({12'd0,snapshot[562:543]},3'd2);
        7'd53:row_character[3]=digit({12'd0,snapshot[562:543]},3'd1);
        7'd54:row_character[3]=digit({12'd0,snapshot[562:543]},3'd0);
        7'd56:row_character[3]=8'h2f;
        7'd57:row_character[3]=digit({12'd0,snapshot[622:603]},3'd4);
        7'd58:row_character[3]=digit({12'd0,snapshot[622:603]},3'd3);
        7'd59:row_character[3]=digit({12'd0,snapshot[622:603]},3'd2);
        7'd60:row_character[3]=digit({12'd0,snapshot[622:603]},3'd1);
        7'd61:row_character[3]=digit({12'd0,snapshot[622:603]},3'd0);
        7'd63:row_character[3]=8'h52;
        7'd64:row_character[3]=8'h41;
        7'd65:row_character[3]=8'h57;
        7'd67:row_character[3]=8'h54;
        7'd68:row_character[3]=8'h48;
        7'd69:row_character[3]=8'h52;
        7'd70:row_character[3]=8'h45;
        7'd71:row_character[3]=8'h53;
        7'd72:row_character[3]=8'h48;
        7'd73:row_character[3]=8'h4f;
        7'd74:row_character[3]=8'h4c;
        7'd75:row_character[3]=8'h44;
        7'd77:row_character[3]=8'h43;
        7'd78:row_character[3]=8'h4f;
        7'd79:row_character[3]=8'h55;
        7'd80:row_character[3]=8'h4e;
        7'd81:row_character[3]=8'h54;
        7'd82:row_character[3]=8'h53;
        default:row_character[3]=" ";
    endcase end
    always @* begin row_character[4]=" ";case(column)
        7'd0:row_character[4]=8'h53;
        7'd1:row_character[4]=digit({16'd0,snapshot[638:623]},3'd3);
        7'd2:row_character[4]=digit({16'd0,snapshot[638:623]},3'd2);
        7'd3:row_character[4]=digit({16'd0,snapshot[638:623]},3'd1);
        7'd4:row_character[4]=digit({16'd0,snapshot[638:623]},3'd0);
        7'd6:row_character[4]=8'h47;
        7'd7:row_character[4]=digit({16'd0,snapshot[654:639]},3'd3);
        7'd8:row_character[4]=digit({16'd0,snapshot[654:639]},3'd2);
        7'd9:row_character[4]=digit({16'd0,snapshot[654:639]},3'd1);
        7'd10:row_character[4]=digit({16'd0,snapshot[654:639]},3'd0);
        7'd12:row_character[4]=8'h50;
        7'd13:row_character[4]=digit({16'd0,snapshot[670:655]},3'd3);
        7'd14:row_character[4]=digit({16'd0,snapshot[670:655]},3'd2);
        7'd15:row_character[4]=digit({16'd0,snapshot[670:655]},3'd1);
        7'd16:row_character[4]=digit({16'd0,snapshot[670:655]},3'd0);
        7'd18:row_character[4]=8'h56;
        7'd19:row_character[4]=digit({24'd0,snapshot[678:671]},3'd1);
        7'd20:row_character[4]=digit({24'd0,snapshot[678:671]},3'd0);
        7'd22:row_character[4]=8'h52;
        7'd23:row_character[4]=8'h42;
        7'd24:row_character[4]=digit({28'd0,snapshot[682:679]},3'd0);
        7'd26:row_character[4]=8'h53;
        7'd27:row_character[4]=8'h48;
        7'd28:row_character[4]=digit({29'd0,snapshot[685:683]},3'd0);
        7'd30:row_character[4]=8'h44;
        7'd31:row_character[4]=digit({21'd0,snapshot[696:686]},3'd2);
        7'd32:row_character[4]=digit({21'd0,snapshot[696:686]},3'd1);
        7'd33:row_character[4]=digit({21'd0,snapshot[696:686]},3'd0);
        7'd35:row_character[4]=8'h2f;
        7'd36:row_character[4]=digit({21'd0,snapshot[707:697]},3'd2);
        7'd37:row_character[4]=digit({21'd0,snapshot[707:697]},3'd1);
        7'd38:row_character[4]=digit({21'd0,snapshot[707:697]},3'd0);
        7'd40:row_character[4]=8'h2f;
        7'd41:row_character[4]=digit({21'd0,snapshot[718:708]},3'd2);
        7'd42:row_character[4]=digit({21'd0,snapshot[718:708]},3'd1);
        7'd43:row_character[4]=digit({21'd0,snapshot[718:708]},3'd0);
        7'd45:row_character[4]=8'h42;
        7'd46:row_character[4]=8'h43;
        7'd47:row_character[4]=digit({24'd0,snapshot[726:719]},3'd1);
        7'd48:row_character[4]=digit({24'd0,snapshot[726:719]},3'd0);
        7'd50:row_character[4]=8'h43;
        7'd51:row_character[4]=8'h43;
        7'd52:row_character[4]=digit({24'd0,snapshot[734:727]},3'd1);
        7'd53:row_character[4]=digit({24'd0,snapshot[734:727]},3'd0);
        7'd55:row_character[4]=8'h49;
        7'd56:row_character[4]=digit({28'd0,snapshot[738:735]},3'd0);
        7'd58:row_character[4]=8'h4d;
        7'd59:row_character[4]=digit({21'd0,snapshot[749:739]},3'd2);
        7'd60:row_character[4]=digit({21'd0,snapshot[749:739]},3'd1);
        7'd61:row_character[4]=digit({21'd0,snapshot[749:739]},3'd0);
        7'd63:row_character[4]=8'h2f;
        7'd64:row_character[4]=digit({21'd0,snapshot[760:750]},3'd2);
        7'd65:row_character[4]=digit({21'd0,snapshot[760:750]},3'd1);
        7'd66:row_character[4]=digit({21'd0,snapshot[760:750]},3'd0);
        7'd68:row_character[4]=8'h2f;
        7'd69:row_character[4]=digit({21'd0,snapshot[771:761]},3'd2);
        7'd70:row_character[4]=digit({21'd0,snapshot[771:761]},3'd1);
        7'd71:row_character[4]=digit({21'd0,snapshot[771:761]},3'd0);
        default:row_character[4]=" ";
    endcase end
    always @* begin row_character[5]=" ";case(column)
        7'd0:row_character[5]=8'h4c;
        7'd1:row_character[5]=8'h43;
        7'd2:row_character[5]=digit({25'd0,snapshot[326:320]},3'd1);
        7'd3:row_character[5]=digit({25'd0,snapshot[326:320]},3'd0);
        7'd4:row_character[5]=digit({25'd0,snapshot[333:327]},3'd1);
        7'd5:row_character[5]=digit({25'd0,snapshot[333:327]},3'd0);
        7'd6:row_character[5]=digit({25'd0,snapshot[340:334]},3'd1);
        7'd7:row_character[5]=digit({25'd0,snapshot[340:334]},3'd0);
        7'd8:row_character[5]=digit({25'd0,snapshot[347:341]},3'd1);
        7'd9:row_character[5]=digit({25'd0,snapshot[347:341]},3'd0);
        7'd10:row_character[5]=digit({25'd0,snapshot[354:348]},3'd1);
        7'd11:row_character[5]=digit({25'd0,snapshot[354:348]},3'd0);
        7'd12:row_character[5]=digit({25'd0,snapshot[361:355]},3'd1);
        7'd13:row_character[5]=digit({25'd0,snapshot[361:355]},3'd0);
        7'd15:row_character[5]=8'h48;
        7'd16:row_character[5]=8'h43;
        7'd17:row_character[5]=digit({25'd0,snapshot[368:362]},3'd1);
        7'd18:row_character[5]=digit({25'd0,snapshot[368:362]},3'd0);
        7'd19:row_character[5]=digit({25'd0,snapshot[375:369]},3'd1);
        7'd20:row_character[5]=digit({25'd0,snapshot[375:369]},3'd0);
        7'd21:row_character[5]=digit({25'd0,snapshot[382:376]},3'd1);
        7'd22:row_character[5]=digit({25'd0,snapshot[382:376]},3'd0);
        7'd23:row_character[5]=digit({25'd0,snapshot[389:383]},3'd1);
        7'd24:row_character[5]=digit({25'd0,snapshot[389:383]},3'd0);
        7'd25:row_character[5]=digit({25'd0,snapshot[396:390]},3'd1);
        7'd26:row_character[5]=digit({25'd0,snapshot[396:390]},3'd0);
        7'd27:row_character[5]=digit({25'd0,snapshot[403:397]},3'd1);
        7'd28:row_character[5]=digit({25'd0,snapshot[403:397]},3'd0);
        7'd30:row_character[5]=8'h43;
        7'd31:row_character[5]=digit(capture_snapshot[191:160],3'd4);
        7'd32:row_character[5]=digit(capture_snapshot[191:160],3'd3);
        7'd33:row_character[5]=digit(capture_snapshot[191:160],3'd2);
        7'd34:row_character[5]=digit(capture_snapshot[191:160],3'd1);
        7'd35:row_character[5]=digit(capture_snapshot[191:160],3'd0);
        7'd37:row_character[5]=8'h52;
        7'd38:row_character[5]=digit(capture_snapshot[159:128],3'd4);
        7'd39:row_character[5]=digit(capture_snapshot[159:128],3'd3);
        7'd40:row_character[5]=digit(capture_snapshot[159:128],3'd2);
        7'd41:row_character[5]=digit(capture_snapshot[159:128],3'd1);
        7'd42:row_character[5]=digit(capture_snapshot[159:128],3'd0);
        7'd44:row_character[5]=8'h49;
        7'd45:row_character[5]=digit(capture_snapshot[127:96],3'd4);
        7'd46:row_character[5]=digit(capture_snapshot[127:96],3'd3);
        7'd47:row_character[5]=digit(capture_snapshot[127:96],3'd2);
        7'd48:row_character[5]=digit(capture_snapshot[127:96],3'd1);
        7'd49:row_character[5]=digit(capture_snapshot[127:96],3'd0);
        7'd51:row_character[5]=8'h48;
        7'd52:row_character[5]=digit({16'd0,capture_snapshot[223:208]},3'd3);
        7'd53:row_character[5]=digit({16'd0,capture_snapshot[223:208]},3'd2);
        7'd54:row_character[5]=digit({16'd0,capture_snapshot[223:208]},3'd1);
        7'd55:row_character[5]=digit({16'd0,capture_snapshot[223:208]},3'd0);
        7'd57:row_character[5]=8'h4c;
        7'd58:row_character[5]=digit({16'd0,capture_snapshot[95:80]},3'd3);
        7'd59:row_character[5]=digit({16'd0,capture_snapshot[95:80]},3'd2);
        7'd60:row_character[5]=digit({16'd0,capture_snapshot[95:80]},3'd1);
        7'd61:row_character[5]=digit({16'd0,capture_snapshot[95:80]},3'd0);
        7'd63:row_character[5]=8'h59;
        7'd64:row_character[5]=digit({16'd0,capture_snapshot[79:64]},3'd3);
        7'd65:row_character[5]=digit({16'd0,capture_snapshot[79:64]},3'd2);
        7'd66:row_character[5]=digit({16'd0,capture_snapshot[79:64]},3'd1);
        7'd67:row_character[5]=digit({16'd0,capture_snapshot[79:64]},3'd0);
        default:row_character[5]=" ";
    endcase end
    wire [7:0] character=({8{row_select[0]}} & row_character[0]) |
        ({8{row_select[1]}} & row_character[1]) |
        ({8{row_select[2]}} & row_character[2]) |
        ({8{row_select[3]}} & row_character[3]) |
        ({8{row_select[4]}} & row_character[4]) |
        ({8{row_select[5]}} & row_character[5]);
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
                "Q":bitmap=35'b01110_10001_10001_10001_10101_10010_01101;
                "R":bitmap=35'b11110_10001_10001_11110_10100_10010_10001;
                "Y":bitmap=35'b10001_10001_01010_00100_00100_00100_00100;
                "M":bitmap=35'b10001_11011_10101_10101_10001_10001_10001;
                "P":bitmap=35'b11110_10001_10001_11110_10000_10000_10000;
                "S":bitmap=35'b01111_10000_10000_01110_00001_00001_11110;
                "T":bitmap=35'b11111_00100_00100_00100_00100_00100_00100;
                "U":bitmap=35'b10001_10001_10001_10001_10001_10001_01110;
                "V":bitmap=35'b10001_10001_10001_10001_10001_01010_00100;
                "W":bitmap=35'b10001_10001_10001_10101_10101_11011_10001;
                "X":bitmap=35'b10001_10001_01010_00100_01010_10001_10001;
                "O":bitmap=35'b01110_10001_10001_10001_10001_10001_01110;
                "/":bitmap=35'b00001_00001_00010_00100_01000_10000_10000;
                ",":bitmap=35'b00000_00000_00000_00000_00100_00100_01000;
                "=":bitmap=35'b00000_11111_00000_11111_00000_00000_00000;
                default:bitmap=0;
            endcase
            case(row)
                0:glyph=bitmap[34:30];1:glyph=bitmap[29:25];2:glyph=bitmap[24:20];
                3:glyph=bitmap[19:15];4:glyph=bitmap[14:10];5:glyph=bitmap[9:5];
                6:glyph=bitmap[4:0];default:glyph=0;
            endcase
        end
    endfunction

    wire [4:0] dots=glyph(character,dy[2:0]);
    wire lit=dot_x<5 && dy<7 && dots[4-dot_x];
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin active<=0;rgb<=0;end
        else begin
            active<=region || center_mark || paper_mark;
            rgb<=region ? (lit ? (snapshot[780] && display_fresh ? 24'hffff80:24'hff9c9c):24'h101820):
                 center_mark ? 24'h00ffff:paper_mark ? 24'hff00ff:24'd0;
        end
endmodule
