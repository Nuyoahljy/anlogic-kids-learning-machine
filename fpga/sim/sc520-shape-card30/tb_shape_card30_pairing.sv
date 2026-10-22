`timescale 1ns/1ps
module tb_shape_card30_pairing;
  reg clk=0;always #5 clk=~clk; reg rst_n=0,flush=0,tick_1ms=0;
  reg scene_event=0,scene_healthy=1,scene_present=1,scene_source_test=0,scene_y_available=1;
  reg [31:0] scene_frame_id=0;reg [15:0] scene_count=100,scene_glyph_count=80;
  reg [7:0] scene_y_min=10,scene_y_max=100;reg [11:0] scene_bbox_width=20,scene_bbox_height=20;
  reg shape_event=0,shape_healthy=1,shape_present=1,shape_source_test=0,shape_aspect_good=1;
  reg [31:0] shape_frame_id=0;reg [10:0] shape_circle=5,shape_square=40,shape_triangle=50,shape_ellipse=80,shape_axis_circle=5;
  reg card_event=0,card_healthy=1,card_present=1,card_valid=0,card_source_test=0,card_qualified=1;
  reg [31:0] card_frame_id=0;reg [3:0] card_item=0;reg [7:0] card_count=0;reg [10:0] card_best=60,card_second=100;
  wire result_event,result_healthy,result_present,result_valid,result_revoke,result_source_test;
  wire [3:0] result_item;wire [31:0] result_frame_id;wire [7:0] result_count;
  wire [191:0] recognition_packet;
  wire packet_event,packet_fresh;wire [7:0] packet_age;
  pixel30_pipeline dut(.*);
  integer errors=0,checks=0;reg done=0;
  always @(posedge clk) #1 if(result_event || packet_event) $display("OBS t=%0t re=%b rv=%b rr=%b pe=%b",$time,result_event,result_valid,result_revoke,packet_event);
  task ck(input bit ok,input string s);begin checks++;if(!ok)begin errors++;$display("FAIL %s",s);end end endtask
  task clear_inputs;begin scene_event=0;shape_event=0;card_event=0;end endtask
  initial begin
    repeat(3)@(negedge clk);rst_n=1;
    // Arrivals are deliberately out of order and still form one same-frame packet.
    scene_frame_id=32'd7;shape_frame_id=32'd7;card_frame_id=32'd7;
    card_event=1;@(negedge clk);card_event=0;shape_event=1;@(negedge clk);shape_event=0;
    scene_event=1;@(negedge clk);scene_event=0;@(negedge clk);
    repeat(3) @(negedge clk);
    ck(result_event && result_healthy && !result_valid,"same-frame first confirmation");
    ck(packet_event && recognition_packet[35] && recognition_packet[34],"packet event and presence");
    // A mismatched identity is rejected and explicitly revoked.
    scene_frame_id=9;shape_frame_id=8;card_frame_id=9;scene_event=1;shape_event=1;card_event=1;
    @(negedge clk);clear_inputs();@(negedge clk);
    repeat(3) @(negedge clk);
    ck(result_event && result_revoke && !result_valid,"mismatched identity revoke");
    flush=1;@(negedge clk);flush=0;
    done=1;$display("RESULT pairing errors=%0d checks=%0d done=%0d",errors,checks,done);$finish;
  end
endmodule
