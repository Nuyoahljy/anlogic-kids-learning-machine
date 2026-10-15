"""Generate fixed-column diagnostic labels and the documented800-bit packet map."""
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[3]
rows=[{} for _ in range(6)];positions=[0]*6
def literal(row,text):
    for c in text:rows[row][positions[row]]=f'8\'h{ord(c):02x}';positions[row]+=1
def field(row,label,expression,digits):
    literal(row,label)
    for digit in reversed(range(digits)):
        rows[row][positions[row]]=f'digit({expression},3\'d{digit})';positions[row]+=1
    literal(row,' ')
def packet(row,label,offset,width,digits):
    expression=f"{{{32-width}'d0,snapshot[{offset+width-1}:{offset}]}}" if width<32 else f'snapshot[{offset+31}:{offset}]'
    field(row,label,expression,digits)
field(0,'D',"{16'd0,VERSION}",4);field(0,'F','snapshot[31:0]',8)
literal(0,'V');rows[0][positions[0]]='(snapshot[780] && display_fresh) ? "1":"0"';positions[0]+=1;literal(0,' ')
field(0,'A',"{24'd0,age}",2);packet(0,'X',772,8,2)
field(0,'E',"{16'd0,capture_snapshot[239:224]}",4);field(0,'B',"{24'd0,business}",2)
field(0,'Q','i2c_snapshot',8);packet(0,'GR',404,9,3);packet(0,'GB',413,9,3);packet(0,'N',422,21,6);literal(0,'W1 T1')
for roi,prefix in enumerate(['C','P']):
    for stage in range(3):packet(1,prefix+str(stage),32+(roi*3+stage)*24,24,6)
literal(1,'C280,168 P0C4,094')
for roi,prefix in enumerate(['MC','MP']):
    for stage in range(3):packet(2,prefix+str(stage),176+(roi*3+stage)*24,24,6)
literal(2,'0=RAW 1=WB 2=TONE')
for color,label in enumerate('RYB'):
    literal(3,label)
    for stage in range(3):
        packet(3,'' if stage==0 else '/',443+(stage*3+color)*20,20,5)
literal(3,'RAW THRESHOLD COUNTS')
packet(4,'S',623,16,4);packet(4,'G',639,16,4);packet(4,'P',655,16,4);packet(4,'V',671,8,2)
packet(4,'RB',679,4,1);packet(4,'SH',683,3,1)
for i,label in enumerate(['D','/','/']):packet(4,label,686+i*11,11,3)
packet(4,'BC',719,8,2);packet(4,'CC',727,8,2);packet(4,'I',735,4,1)
for i,label in enumerate(['M','/','/']):packet(4,label,739+i*11,11,3)
for start,label in [(320,'LC'),(362,'HC')]:
    literal(5,label)
    for i in range(6):
        expression=f"{{25'd0,snapshot[{start+i*7+6}:{start+i*7}]}}"
        for digit_index in [1,0]:rows[5][positions[5]]=f"digit({expression},3'd{digit_index})";positions[5]+=1
    literal(5,' ')
for label,hi,lo,digits in [('C',191,160,5),('R',159,128,5),('I',127,96,5),('H',223,208,4),('L',95,80,4),('Y',79,64,4)]:
    expression=f'capture_snapshot[{hi}:{lo}]' if hi-lo+1==32 else f"{{16'd0,capture_snapshot[{hi}:{lo}]}}"
    field(5,label,expression,digits)
assert max(positions)<=96,positions
source=(ROOT/'fpga/rtl/sc520-card-recognition/pixel14/pixel14_diag_osd.v').read_text(encoding='utf-8')
glyph=source[source.index('    function [4:0] glyph;'):source.index('    wire [4:0] dots=')]
extra={'M':'10001_11011_10101_10101_10001_10001_10001','P':'11110_10001_10001_11110_10000_10000_10000',
       'S':'01111_10000_10000_01110_00001_00001_11110','T':'11111_00100_00100_00100_00100_00100_00100',
       'U':'10001_10001_10001_10001_10001_10001_01110','V':'10001_10001_10001_10001_10001_01010_00100',
       'W':'10001_10001_10001_10101_10101_11011_10001','X':'10001_10001_01010_00100_01010_10001_10001',
       'O':'01110_10001_10001_10001_10001_10001_01110','/':'00001_00001_00010_00100_01000_10000_10000',
       ',':'00000_00000_00000_00000_00100_00100_01000','=':'00000_11111_00000_11111_00000_00000_00000'}
glyph=glyph.replace('                default:bitmap=0;', ''.join(f'                "{c}":bitmap=35\'b{bits};\n' for c,bits in extra.items())+'                default:bitmap=0;')
cases='\n'.join(f"                10'd{r*128+c}:character={v};" for r in range(6) for c,v in rows[r].items() if v!="8'h20")
rtl='''// Generated fixed layout. Existing768x72 diagnostic region; six8x12 rows.
module pixel14_color_diag_osd #(parameter [15:0] VERSION=16'h0114)(
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
    wire region=pixel_x>=32 && pixel_x<800 && pixel_y>=520 && pixel_y<592;
    wire [10:0] dx=pixel_x-32;wire [6:0] column=dx[9:3];
    reg [2:0] row;reg [3:0] dy;
    always @* begin
        if(pixel_y<532)begin row=0;dy=pixel_y-520;end
        else if(pixel_y<544)begin row=1;dy=pixel_y-532;end
        else if(pixel_y<556)begin row=2;dy=pixel_y-544;end
        else if(pixel_y<568)begin row=3;dy=pixel_y-556;end
        else if(pixel_y<580)begin row=4;dy=pixel_y-568;end
        else begin row=5;dy=pixel_y-580;end
    end
    function [7:0] digit;input [31:0] value;input [2:0] index;reg [3:0] nibble;
        begin nibble=value>>(index*4);digit=nibble<10 ? "0"+nibble:"A"+nibble-10;end
    endfunction
    reg [7:0] character;
    always @* begin character=" ";case({row,column})
@@CASES@@
                default:character=" ";
            endcase
    end
@@GLYPH@@
    wire [4:0] dots=glyph(character,dy[2:0]);
    wire lit=dx[2:0]<5 && dy<7 && dots[4-dx[2:0]];
    wire center_mark=pixel_x>=634 && pixel_x<646 && pixel_y>=354 && pixel_y<366 &&
        (pixel_x==634 || pixel_x==645 || pixel_y==354 || pixel_y==365);
    wire paper_mark=pixel_x>=190 && pixel_x<202 && pixel_y>=142 && pixel_y<154 &&
        (pixel_x==190 || pixel_x==201 || pixel_y==142 || pixel_y==153);
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin active<=0;rgb<=0;end
        else begin
            active<=region || center_mark || paper_mark;
            rgb<=region ? (lit ? (snapshot[780] && display_fresh ? 24'hffff80:24'hff9c9c):24'h101820):
                 center_mark ? 24'h00ffff:paper_mark ? 24'hff00ff:24'd0;
        end
endmodule
'''.replace('@@CASES@@',cases).replace('@@GLYPH@@',glyph)
(ROOT/'fpga/rtl/sc520-card-recognition/color_diag/pixel14_color_diag_osd.v').write_text(rtl,encoding='ascii')
schema={'PacketBits':800,'CompleteBit':780,'ReasonBits':[779,772],'FrameIdBits':[31,0],
 'Rows':[{str(k):v for k,v in row.items()} for row in rows],'ColumnsUsed':positions,
 'SampleRegion':{'Center':[636,356,8,8],'Paper':[192,144,8,8]},
 'StageOrder':['preWB','postWB','postTone'],'Means':'8x8 channel sums divided by64, floor',
 'DataBitLayout':{'samples':[175,32],'means':[319,176],'lowclip':[361,320],'highclip':[403,362],'gain_r':[412,404],'gain_b':[421,413],
  'neutral':[442,422],'color_hits':[622,443],'scene':[638,623],'glyph':[654,639],'paper':[670,655],'flags':[678,671],
  'raw_block':[682,679],'shape_bits':[685,683],'shape_distances':[718,686],'block_count':[726,719],'card_count':[734,727],
  'final_item':[738,735],'best':[749,739],'second':[760,750],'sample_foreground':[771,761]}}
(ROOT/'hardware/sc520-card-recognition/color-observation-layout.json').write_text(json.dumps(schema,indent=2)+'\n',encoding='utf-8')
print('COLOR_DIAG_OSD_GENERATED',positions)
