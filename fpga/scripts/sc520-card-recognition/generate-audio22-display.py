"""Extend an isolated display copy; never mutate D0117's inputs or glyphs."""
from pathlib import Path
import hashlib,json
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[3]
def once(s,a,b):assert s.count(a)==1,(a,s.count(a));return s.replace(a,b)
def main():
    rtl=ROOT/'fpga/rtl/sc520-card-recognition';out=rtl/'audio22';assets=ROOT/'assets/templates/sc520-card-recognition/audio22'
    assets.mkdir(parents=True,exist_ok=True)
    old=json.loads((ROOT/'assets/templates/sc520-card-recognition/display17/font-extension.json').read_text(encoding='utf-8'))
    font_path=Path(old['FontPath']);assert hashlib.sha256(font_path.read_bytes()).hexdigest().upper()==old['FontSHA256']
    font=ImageFont.truetype(str(font_path),16,index=0)
    glyphs=list(old['Glyphs']);ids={g['char']:g['id'] for g in glyphs}
    messages=['语音未配置','语音初始化中','语音可用','语音播放中','语音故障']
    unused=[i for i in range(1,256) if i not in ids.values()]
    for c in sorted(set(''.join(messages))-ids.keys()):
        code=unused.pop(0);ids[c]=code;im=Image.new('L',(16,16),0);b=font.getbbox(c);w,h=b[2]-b[0],b[3]-b[1]
        assert w<=16 and h<=16
        ImageDraw.Draw(im).text(((16-w)//2-b[0],(16-h)//2-b[1]),c,font=font,fill=255)
        rows=[sum(1<<(15-x) for x in range(16) if im.getpixel((x,y))>=128) for y in range(16)];assert any(rows)
        glyphs.append({'char':c,'id':code,'rows_hex':[f'{v:04X}' for v in rows]})
    byid={g['id']:[int(x,16) for x in g['rows_hex']] for g in glyphs}
    words=[byid.get(a//16,[0]*16)[a%16] for a in range(4096)]
    for g in old['Glyphs']:assert byid[g['id']]==[int(x,16) for x in g['rows_hex']]
    content=(rtl/'items14/items14_content.v').read_text(encoding='utf-8').replace('module items14_content','module pixel22_content')
    content=once(content,'input wire display_mode,','input wire display_mode,\n    input wire [2:0] audio_state,')
    additions=[]
    for t,msg in enumerate(messages,50):
        for i,c in enumerate(msg):additions.append(f"            12'd{t*64+i}:text_glyph=8'd{ids[c]};")
    content=once(content,'            endcase end','\n'.join(additions)+'\n            endcase end')
    content=once(content,"glyph=DISPLAY_UI ? text_glyph(audio_fault ? 6'd49:6'd45,char_index) : text_glyph(audio_fault ? 6'd11 : (audio_busy ? 6'd10 : 6'd9),char_index);",
                 "glyph=text_glyph(6'd50+{3'd0,(audio_state<=4 ? audio_state:3'd4)},char_index);")
    content=once(content,'tone=audio_fault ? 2 : 0;','tone=audio_state==4 ? 2:audio_state==2 ? 3:0;')
    (out/'pixel22_content.v').write_text(content,encoding='ascii',newline='\n')
    rom=['// T022 isolated font; preserves all158 D0117 IDs and bitmaps.','module pixel22_font_rom(input wire clk,input wire [7:0] glyph,input wire [3:0] row,output reg [15:0] bits);',
         '(* ram_style="bram" *) reg [15:0] rom [0:4095];','initial begin']
    rom += [f"rom[12'd{i}]=16'h{x:04X};" for i,x in enumerate(words)]
    rom += ['end','always @(posedge clk) bits<=rom[{glyph,row}];','endmodule','']
    (out/'pixel22_font_rom.v').write_text('\n'.join(rom),encoding='ascii',newline='\n')
    (assets/'font-reference.mem').write_text(''.join(f'{x:04X}\n' for x in words),encoding='ascii',newline='\n')
    panel=(rtl/'display17/pixel17_panel.v').read_text(encoding='utf-8').replace('module pixel17_panel','module pixel22_panel')
    panel=once(panel,'input wire [27:0] status,input wire display_mode,','input wire [27:0] status,input wire [2:0] audio_state,input wire display_mode,')
    panel=panel.replace('items14_content #','pixel22_content #').replace('items14_font_rom font','pixel22_font_rom font')
    panel=once(panel,'.display_mode(display_mode),','.display_mode(display_mode),.audio_state(audio_state),')
    (out/'pixel22_panel.v').write_text(panel,encoding='ascii',newline='\n')
    compositor=(rtl/'display17/pixel17_compositor.v').read_text(encoding='utf-8').replace('module pixel17_compositor','module pixel22_compositor')
    compositor=compositor.replace("VERSION=16'h0117","VERSION=16'h0220")
    compositor=once(compositor,'input wire [27:0] business_state,','input wire [27:0] business_state,input wire [2:0] audio_state,')
    compositor=once(compositor,'reg [27:0] status;','reg [30:0] frame_state;\n    wire [27:0] status=frame_state[27:0];')
    compositor=once(compositor,'if(!rst_n)status<=0;else if(in_frame_start)status<=business_state;','if(!rst_n)frame_state<=0;else if(in_frame_start)frame_state<={audio_state,business_state};')
    compositor=compositor.replace('pixel17_panel panel','pixel22_panel panel')
    compositor=once(compositor,'.status(status),','.status(status),.audio_state(frame_state[30:28]),')
    (out/'pixel22_compositor.v').write_text(compositor,encoding='ascii',newline='\n')
    m={**old,'Source':'fe51739 isolated extension','Glyphs':glyphs,'AudioMessages':messages,'AudioTextIDs':list(range(50,55)),
       'OldGlyphsPreserved':len(old['Glyphs']),'GlyphCount':len(glyphs),'FontLSBZero':all((v&1)==0 for v in words)}
    (assets/'font-extension.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps({'Glyphs':len(glyphs),'Preserved':len(old['Glyphs']),'FontLSBZero':m['FontLSBZero']}))
if __name__=='__main__':main()
