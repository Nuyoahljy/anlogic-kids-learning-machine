// Shape evidence for the entire normalized scene glyph, independent of the
// colored subset used by block_frame_recognizer. A matching bit is only a
// qualification of that SAME shape; it does not create a block class.
module pixel14_block_shape_guard #(
    parameter integer MAX_DISTANCE=20
) (
    input wire clk,rst_n,flush,frame_start,sample_valid,
    input wire [9:0] sample_index,
    input wire sample_foreground,frame_end,frame_good,frame_present,
    input wire [31:0] frame_id,
    input wire frame_source_test,
    output reg out_frame,out_healthy,
    output reg [2:0] shape_ok,
    output reg [31:0] out_frame_id,
    output reg out_source_test,
    output reg [10:0] distance_circle,distance_square,distance_triangle
);
    localparam [1:0] IDLE=0,CAPTURE=1,DRAIN=2;
    reg [1:0] state;
    reg [10:0] count,dist_circle,dist_square,dist_triangle;
    reg bad,pending_valid,pending_fg,saved_good,saved_present;
    reg [31:0] active_id,saved_id;
    reg active_source,saved_source;
    wire [2:0] template_bits;
    wire rom_enable=state==CAPTURE && sample_valid && !frame_start && count<1024 && !flush;
    pixel14_block_shape_rom templates(.clk(clk),.en(rom_enable),.addr(sample_index),.data(template_bits));
    wire tag_bad=frame_id!=active_id || frame_source_test!=active_source;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;count<=0;dist_circle<=0;dist_square<=0;dist_triangle<=0;
            bad<=0;pending_valid<=0;pending_fg<=0;saved_good<=0;saved_present<=0;
            active_id<=0;saved_id<=0;active_source<=0;saved_source<=0;
        end else if(flush)begin
            state<=IDLE;count<=0;dist_circle<=0;dist_square<=0;dist_triangle<=0;
            bad<=0;pending_valid<=0;saved_good<=0;saved_present<=0;
        end else begin
            pending_valid<=0;
            if(frame_start)begin
                // A new frame can start while the prior DRAIN result is
                // published. Starting inside an incomplete capture poisons it.
                state<=CAPTURE;count<=0;dist_circle<=0;dist_square<=0;dist_triangle<=0;
                bad<=state==CAPTURE || sample_valid || frame_end;
                active_id<=frame_id;active_source<=frame_source_test;
            end else if(state==CAPTURE)begin
                if(tag_bad)bad<=1;
                if(pending_valid)begin
                    dist_circle<=dist_circle+(pending_fg^template_bits[0]);
                    dist_square<=dist_square+(pending_fg^template_bits[1]);
                    dist_triangle<=dist_triangle+(pending_fg^template_bits[2]);
                end
                if(sample_valid)begin
                    if(count>=1024 || {1'b0,sample_index}!=count)bad<=1;
                    if(count<1025)count<=count+1'b1;
                    pending_valid<=rom_enable;pending_fg<=sample_foreground;
                end
                if(frame_end)begin
                    saved_good<=frame_good && !bad && !tag_bad && count==1024 && !sample_valid;
                    saved_present<=frame_present;saved_id<=active_id;saved_source<=active_source;
                    state<=DRAIN;pending_valid<=0;
                end
            end else if(state==DRAIN)begin
                state<=IDLE;
            end else if(frame_end)begin
                saved_good<=0;saved_present<=frame_present;saved_id<=frame_id;saved_source<=frame_source_test;
                dist_circle<=0;dist_square<=0;dist_triangle<=0;state<=DRAIN;
            end
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            out_frame<=0;out_healthy<=0;shape_ok<=0;out_frame_id<=0;out_source_test<=0;
            distance_circle<=0;distance_square<=0;distance_triangle<=0;
        end else if(flush)begin
            out_frame<=0;out_healthy<=0;shape_ok<=0;
            distance_circle<=0;distance_square<=0;distance_triangle<=0;
        end else begin
            out_frame<=0;
            if(state==DRAIN)begin
                out_frame<=1;
                out_healthy<=saved_good && !sample_valid && !frame_end;
                shape_ok<=(saved_good && saved_present && !sample_valid && !frame_end) ?
                    {dist_triangle<=MAX_DISTANCE,dist_square<=MAX_DISTANCE,dist_circle<=MAX_DISTANCE} : 3'b000;
                out_frame_id<=saved_id;out_source_test<=saved_source;
                distance_circle<=dist_circle;distance_square<=dist_square;distance_triangle<=dist_triangle;
            end
        end
    end
    initial if(MAX_DISTANCE<0 || MAX_DISTANCE>1024)$error("block shape distance parameter error");
endmodule

// A synchronous constant ROM. Coordinate arithmetic runs at elaboration only;
// there are no run-time square/multiply operators on the sample data path.
module pixel14_block_shape_rom(input wire clk,en,input wire [9:0] addr,output reg [2:0] data);
    reg [2:0] bits[0:1023];
    integer i,x,y,dx,dy,ax;
    initial begin
        for(i=0;i<1024;i=i+1)begin
            bits[i]=0;x=i%32-6;y=i/32-6;
            if(x>=0 && x<20 && y>=0 && y<20)begin
                dx=2*x+1-20;dy=2*y+1-20;ax=dx<0 ? -dx : dx;
                bits[i][0]=(dx*dx+dy*dy)<=400;
                bits[i][1]=1;
                bits[i][2]=2*ax<=2*y+1;
            end
        end
    end
    always @(posedge clk)if(en)data<=bits[addr];
endmodule
