// Two color slots cover the scene processor's two capture banks. Analysis
// arrives later and must carry the exact same32-bit acquisition tag.
module pixel14_observation_join (
    input wire clk,rst_n,flush,
    input wire color_event,color_good,
    input wire [622:0] color_data,
    input wire analysis_event,analysis_good,
    input wire [31:0] analysis_id,
    input wire [148:0] analysis_data,
    output reg out_event,
    output reg [799:0] out_packet
);
    reg [1:0] used;
    reg [622:0] slot0,slot1;
    reg flush_seen;
    wire hit0=used[0] && slot0[31:0]==analysis_id;
    wire hit1=used[1] && slot1[31:0]==analysis_id;
    wire simultaneous=color_event && color_good && color_data[31:0]==analysis_id;
    wire collision=(used[0] && slot0[31:0]==color_data[31:0]) ||
                   (used[1] && slot1[31:0]==color_data[31:0]);
    task invalid_packet;
        input [31:0] tag;
        input [7:0] reason;
        begin out_event<=1;out_packet<=0;out_packet[31:0]<=tag;out_packet[779:772]<=reason;end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin used<=0;slot0<=0;slot1<=0;flush_seen<=0;out_event<=0;out_packet<=0;end
        else begin
            out_event<=0;flush_seen<=flush;
            if(flush)begin used<=0;if(!flush_seen)invalid_packet(0,8'h01);end
            else begin
                if(color_event)begin
                    if(!color_good || collision)begin used<=0;invalid_packet(color_data[31:0],8'h02);end
                    else if(!used[0] || (analysis_event && hit0))begin used[0]<=1;slot0<=color_data;end
                    else if(!used[1] || (analysis_event && hit1))begin used[1]<=1;slot1<=color_data;end
                    else begin used<=0;invalid_packet(color_data[31:0],8'h04);end
                end
                if(analysis_event && !(color_event && (!color_good || collision)))begin
                    if(hit0)used[0]<=0;
                    if(hit1)used[1]<=0;
                    // A consumed slot may be replaced by another new color tag
                    // in the same clock; never clear the replacement.
                    if(color_event && color_good && color_data[31:0]!=analysis_id)begin
                        if(!used[0] || hit0)used[0]<=1;
                        else if(!used[1] || hit1)used[1]<=1;
                    end
                    if(!analysis_good || (hit0 && hit1))invalid_packet(analysis_id,8'h08);
                    else if(hit0 || hit1 || simultaneous)begin
                        out_event<=1;out_packet<=0;out_packet[780]<=1;
                        out_packet[622:0]<=hit0 ? slot0:hit1 ? slot1:color_data;
                        out_packet[771:623]<=analysis_data;
                        if(simultaneous && !hit0 && !hit1)begin
                            if(!used[0])used[0]<=0;else if(!used[1])used[1]<=0;
                        end
                    end else invalid_packet(analysis_id,8'h10);
                end
            end
        end
    end
endmodule
