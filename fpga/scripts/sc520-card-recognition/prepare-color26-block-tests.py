"""Retain geometric/health expectations and compare exact two-cycle event shift."""
from pathlib import Path
R=Path(__file__).resolve().parents[3];P=R/'fpga/sim/sc520-color-integration/tb_color26_block_pipe.sv'
s=(R/'fpga/sim/sc520-card-recognition/tb_pixel14_block.sv').read_text().replace('tb_pixel14_block','tb_color26_block_pipe').replace('block_frame_recognizer #','pixel26_block_recognizer_piped #')
# Old ideal yellow was R-largest. Use independently measured stage2 yellow,
# keeping all 9 object/shape IDs, geometry, and malformed-stream expectations.
s=s.replace("24'hffd020","24'h93ac76")
insert='''
  wire ref_frame,ref_healthy,ref_present,ref_valid,ref_source,ref_revoke;
  wire [3:0] ref_item;wire [31:0] ref_id;wire [7:0] ref_count;
  pixel26_block_recognizer #(.FRAME_WIDTH(64),.FRAME_HEIGHT(64),.X_MIN(8),.X_MAX(55),
    .Y_MIN(8),.Y_MAX(55),.MIN_AREA(16)) reference(
    .out_frame(ref_frame),.out_healthy(ref_healthy),.out_present(ref_present),.out_valid(ref_valid),
    .out_item(ref_item),.out_frame_id(ref_id),.out_source_test(ref_source),.stable_count(ref_count),.out_revoke(ref_revoke),.*);
  reg [1:0] reference_events=0;reg [47:0] reference_data0=0,reference_data1=0;
  always @(posedge clk)begin
    if(!rst_n||flush)begin reference_events<=0;reference_data0<=0;reference_data1<=0;end
    else begin
      reference_events<={reference_events[0],ref_frame};
      reference_data0<={ref_healthy,ref_present,ref_valid,ref_item,ref_id,ref_source,ref_count};reference_data1<=reference_data0;
    end
    #1;
    if(rst_n&&!flush)begin
      ck(out_frame===reference_events[1],"completed event differs from exact two-cycle reference offset");
      if(out_frame)ck({out_healthy,out_present,out_valid,out_item,out_frame_id,out_source_test,stable_count}===reference_data1,
        "complete tag/source/health/item/count atomically follows two-cycle offset");
    end
  end
'''
s=s.replace('  initial begin\n    unused=',insert+'\n  initial begin\n    unused=')
P.write_text(s,encoding='utf-8',newline='\n');print('BLOCK_PIPE_CONTRACT_TEST_CREATED')
