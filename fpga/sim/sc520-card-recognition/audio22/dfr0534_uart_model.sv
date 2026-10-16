`timescale 1ns/1ps
// Independent byte/bit-level peripheral model. Synthetic timing and track IDs;
// no DUT decoder, state, or response signals feed this model.
module dfr0534_uart_model(
    input wire clk,tx,
    input wire [2:0] response_policy,
    input wire hold_play,busy_mismatch,
    input wire [31:0] duration_ms,
    output reg rx=1,
    output wire busy
);
    localparam real BIT_NS=1000000000.0/9600;
    integer plays=0,stops=0,queries=0,playing_queries=0,modes=0,volumes=0;
    integer frames=0,checks=0;
    reg [15:0] tracks[0:255];
    reg [7:0] status=0;
    reg [7:0] last_mode=0,last_volume=0;
    realtime play_end=0;
    assign busy=busy_mismatch ? 1'b0 : (status==1);
    always @(posedge clk)
        if(status==1 && !hold_play && $realtime>=play_end) status=0;
    task automatic check(input bit ok,input string msg);
        checks++;
        if(!ok) $fatal(1,"UART_MODEL %s at %0t",msg,$time);
    endtask
    task automatic get_byte(output reg [7:0] value);
        @(negedge tx); #(BIT_NS/2); check(tx===0,"start bit");
        for(integer b=0;b<8;b++) begin #(BIT_NS);value[b]=tx;end
        #(BIT_NS);check(tx===1,"stop bit");
    endtask
    task automatic put_byte(input reg [7:0] value);
        rx=0;#(BIT_NS);
        for(integer b=0;b<8;b++) begin rx=value[b];#(BIT_NS);end
        rx=1;#(BIT_NS);
    endtask
    task automatic reply(input reg [7:0] value,input reg [2:0] policy);
        if(policy!=1) begin
            if(policy==3) #(60000000); else #(BIT_NS*2);
            put_byte(8'haa);put_byte(8'h01);put_byte(8'h01);
            put_byte(value);put_byte((8'hac+value) ^ (policy==2 ? 8'h01 : 8'h00));
        end
    endtask
    reg [7:0] byte_value,command,length,d0,d1,sum,checksum;
    initial forever begin
        get_byte(byte_value);check(byte_value==8'haa,"AA header");sum=byte_value;
        get_byte(command);sum=sum+command;
        get_byte(length);sum=sum+length;check(length<=2,"payload bound");d0=0;d1=0;
        for(integer i=0;i<length;i++) begin
            get_byte(byte_value);sum=sum+byte_value;
            if(i==0)d0=byte_value;else d1=byte_value;
        end
        get_byte(checksum);check(checksum==sum,"SUM8");frames++;
        $display("UART t=%0t cmd=%02h len=%0d d=%02h%02h",$time,command,length,d0,d1);
        case(command)
            8'h04: begin check(length==0,"stop payload");stops++;status=0;end
            8'h18: begin check(length==1 && d0==2,"single stop mode02");modes++;last_mode=d0;end
            8'h13: begin check(length==1 && d0==8,"volume8");volumes++;last_volume=d0;end
            8'h07: begin
                check(length==2 && d0==8'h12 && d1>=1 && d1<=35,"synthetic physical mapping");
                tracks[plays]={d0,d1};plays++;status=1;play_end=$realtime+duration_ms*1000000.0;
            end
            8'h01: begin
                check(length==0,"query payload");queries++;
                if(status==1)playing_queries++;
                fork reply(status,response_policy); join_none
            end
            default: $fatal(1,"UART_MODEL unexpected command %h",command);
        endcase
    end
endmodule
