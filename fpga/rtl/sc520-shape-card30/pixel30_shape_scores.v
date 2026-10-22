module pixel30_shape_scores #(
    parameter GEOMETRY_FILE="contour29-shapes.mem"
)(
    input wire clk,rst_n,flush,
    input wire full_start,full_valid,full_end,axis_start,axis_valid,axis_end,
    input wire [9:0] sample_index,
    input wire sample_fg,frame_good,frame_present,
    input wire [31:0] frame_id,input wire frame_source,
    output reg out_frame,out_healthy,out_present,
    output reg [31:0] out_id,output reg out_source,
    output reg [10:0] circle_distance,square_distance,triangle_distance,ellipse_distance,axis_circle_distance
);
    localparam [2:0] IDLE=0,FULL=1,WAIT_AXIS=2,AXIS=3,DRAIN=4;
    reg [2:0] state;
    reg [15:0] rom[0:1023];reg [15:0] rom_q;
    reg [10:0] distances[0:14],axis0,axis1;
    reg [10:0] full_count,axis_count;
    reg pending_full,pending_axis,pending_fg,bad,good_saved,present_saved;
    reg [31:0] active_id;reg active_source;
    integer i,j;reg [10:0] ellipse_min;
    wire identity_bad=frame_id!=active_id || frame_source!=active_source;
    wire protocol_bad=
        (full_valid && (state!=FULL || axis_valid || full_end || axis_end || axis_start)) ||
        (axis_valid && (state!=AXIS || full_valid || full_end || axis_end || axis_start)) ||
        (full_end && (state!=FULL || full_valid || axis_valid || axis_start || axis_end)) ||
        (axis_start && (state!=WAIT_AXIS || full_valid || axis_valid || full_end || axis_end)) ||
        (axis_end && (state!=AXIS || full_valid || axis_valid || full_end || axis_start));
    wire full_read=state==FULL && full_valid && !full_start && full_count<1024;
    wire axis_read=state==AXIS && axis_valid && !axis_start && axis_count<1024;
    initial $readmemh(GEOMETRY_FILE,rom);
    always @(posedge clk)if(full_read || axis_read)rom_q<=rom[sample_index];
    always @* begin
        ellipse_min=11'd2047;
        for(j=3;j<15;j=j+1)if(distances[j]<ellipse_min)ellipse_min=distances[j];
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;full_count<=0;axis_count<=0;
            pending_full<=0;pending_axis<=0;pending_fg<=0;bad<=0;good_saved<=0;present_saved<=1;
            active_id<=0;active_source<=0;axis0<=0;axis1<=0;
            out_frame<=0;out_healthy<=0;out_present<=1;out_id<=0;out_source<=0;
            circle_distance<=2047;square_distance<=2047;triangle_distance<=2047;
            ellipse_distance<=2047;axis_circle_distance<=2047;
            for(i=0;i<15;i=i+1)distances[i]<=0;
        end else if(flush)begin
            state<=IDLE;pending_full<=0;pending_axis<=0;bad<=0;full_count<=0;axis_count<=0;
            out_frame<=0;out_healthy<=0;out_present<=1;
            circle_distance<=2047;square_distance<=2047;triangle_distance<=2047;
            ellipse_distance<=2047;axis_circle_distance<=2047;
        end else begin
            out_frame<=0;pending_full<=full_read;pending_axis<=axis_read;
            if(full_read || axis_read)pending_fg<=sample_fg;
            if(pending_full)for(i=0;i<15;i=i+1)
                distances[i]<=distances[i]+(pending_fg^rom_q[i<3 ? i:i+1]);
            if(pending_axis)begin
                axis0<=axis0+(pending_fg^rom_q[0]);
                axis1<=axis1+(pending_fg^rom_q[3]);
            end
            if(full_start)begin
                state<=FULL;full_count<=0;axis_count<=0;pending_full<=0;pending_axis<=0;
                bad<=state!=IDLE || full_valid || axis_start || axis_valid || full_end || axis_end;
                active_id<=frame_id;active_source<=frame_source;good_saved<=0;
                axis0<=0;axis1<=0;for(i=0;i<15;i=i+1)distances[i]<=0;
            end else begin
                if((state!=IDLE && state!=DRAIN && identity_bad) || protocol_bad)bad<=1;
                if(full_valid)begin
                    if(state!=FULL || full_count>=1024 || {1'b0,sample_index}!=full_count)bad<=1;
                    if(full_count<1025)full_count<=full_count+1'b1;
                end
                if(axis_valid)begin
                    if(state!=AXIS || axis_count>=1024 || {1'b0,sample_index}!=axis_count)bad<=1;
                    if(axis_count<1025)axis_count<=axis_count+1'b1;
                end
                if(full_end)begin
                    good_saved<=state==FULL && full_count==1024 && !bad && !identity_bad && !protocol_bad && frame_good;
                    present_saved<=frame_present;state<=WAIT_AXIS;
                end
                if(axis_start)begin
                    if(state!=WAIT_AXIS || axis_valid || axis_end)bad<=1;
                    state<=AXIS;axis_count<=0;axis0<=0;axis1<=0;
                end
                if(axis_end)begin
                    good_saved<=good_saved && state==AXIS && axis_count==1024 && !bad && !identity_bad &&
                        !protocol_bad && frame_good && frame_present==present_saved;
                    state<=DRAIN;
                end
                if(state==DRAIN)begin
                    out_frame<=1;out_healthy<=good_saved && !full_valid && !axis_valid && !full_end && !axis_end;
                    out_present<=present_saved;out_id<=active_id;out_source<=active_source;
                    circle_distance<=distances[0];square_distance<=distances[1];triangle_distance<=distances[2];
                    ellipse_distance<=ellipse_min;axis_circle_distance<=axis0<axis1 ? axis0:axis1;
                    state<=IDLE;
                end
            end
        end
    end
endmodule
