"""Extend current glyph IDs and content for T017; preserve every old bitmap."""
from pathlib import Path
import hashlib,importlib.util,json,subprocess
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[3]
BASE='68e2b4d01485fa1b3049d81e98a09c2e3dc98a94'
spec=importlib.util.spec_from_file_location('old_items_font',Path(__file__).with_name('generate-items14-font.py'))
old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
def once(s,a,b):assert s.count(a)==1,(a,s.count(a));return s.replace(a,b)
def main():
    source='assets/templates/sc520-card-recognition/items14/font-manifest.json'
    previous=json.loads(subprocess.check_output(['git','show',BASE+':'+source],cwd=ROOT))
    font_path=Path(previous['font_path']);assert hashlib.sha256(font_path.read_bytes()).hexdigest().upper()==previous['font_sha256']
    font=ImageFont.truetype(str(font_path),16,index=0)
    ids={g['char']:g['id'] for g in previous['glyphs']}
    rows={g['id']:[int(x,16) for x in g['rows_hex']] for g in previous['glyphs']}
    texts=old.TEXTS+['语音未接入','原图','处理图','K1模式 K2重播 K3切图 K4清分','语音故障']
    unused=[i for i in range(1,256) if i not in ids.values()]
    for char in sorted(set(''.join(texts))-ids.keys()):
        code=unused.pop(0);ids[char]=code
        bitmap=Image.new('L',(16,16),0);box=font.getbbox(char);width,height=box[2]-box[0],box[3]-box[1]
        assert width<=16 and height<=16
        ImageDraw.Draw(bitmap).text(((16-width)//2-box[0],(16-height)//2-box[1]),char,font=font,fill=255)
        rows[code]=[sum(1<<(15-x) for x in range(16) if bitmap.getpixel((x,y))>=128) for y in range(16)]
        assert any(rows[code])
    table=['    function [7:0] text_glyph;','        input [5:0] text_id,position;','        begin text_glyph=0;case({text_id,position})']
    for tid,text in enumerate(texts):
        assert len(text)<=37
        for i,c in enumerate(text):
            if c!=' ':table.append(f"            12'd{tid*64+i}:text_glyph=8'd{ids[c]};")
    table+=['            endcase end','    endfunction']
    content=old.CONTENT.replace('@@TABLE@@','\n'.join(table)).replace('generate-items14-font.py','generate-display17-font.py')
    content=once(content,'parameter integer SCENE_UI=0','parameter integer SCENE_UI=0,DISPLAY_UI=0')
    content=once(content,'input wire source_test, armed, audio_fault, audio_busy, result_healthy,','input wire source_test, armed, audio_fault, audio_busy, result_healthy,\n    input wire display_mode,')
    content=once(content,'glyph=text_glyph(source_test ? 6\'d7 : 6\'d8,char_index);',
        "glyph=(DISPLAY_UI && char_index>=24) ? text_glyph(display_mode ? 6'd47:6'd46,char_index-24) : text_glyph(source_test ? 6'd7 : 6'd8,char_index);")
    content=once(content,"glyph=text_glyph(audio_fault ? 6'd11 : (audio_busy ? 6'd10 : 6'd9),char_index);",
        "glyph=DISPLAY_UI ? text_glyph(audio_fault ? 6'd49:6'd45,char_index) : text_glyph(audio_fault ? 6'd11 : (audio_busy ? 6'd10 : 6'd9),char_index);")
    content=once(content,'else if(mode==0 || mode==1) message_id=24;',"else if(mode==0 || mode==1) message_id=DISPLAY_UI ? 6'd48:6'd24;")
    rtl=ROOT/'fpga/rtl/sc520-card-recognition/items14';asset=ROOT/'assets/templates/sc520-card-recognition/display17'
    (rtl/'items14_content.v').write_text(content,encoding='ascii')
    words=[rows.get(a//16,[0]*16)[a%16] for a in range(4096)]
    rom=['// T017 extension; all D0116 glyph IDs and pixels are retained.',
        'module items14_font_rom(input wire clk,input wire [7:0] glyph,input wire [3:0] row,output reg [15:0] bits);',
        '(* ram_style = "bram" *) reg [15:0] rom [0:4095];','initial begin']
    rom.extend(f"    rom[12'd{a}]=16'h{v:04X};" for a,v in enumerate(words))
    rom+=['end','always @(posedge clk) bits <= rom[{glyph,row}];','endmodule','']
    (rtl/'items14_font_rom.v').write_text('\n'.join(rom),encoding='ascii')
    (asset/'font-reference.mem').write_text(''.join(f'{v:04X}\n' for v in words),encoding='ascii')
    manifest={'BaseCommit':BASE,'BaseManifest':source,'FontPath':str(font_path),'FontSHA256':previous['font_sha256'],
        'OldGlyphsPreserved':len(previous['glyphs']),'Glyphs':[{'char':c,'id':i,'rows_hex':[f'{v:04X}' for v in rows[i]]} for c,i in ids.items()],
        'Texts':texts,'TopTextMaxXExclusive':1008,'RowY':[12,44,76,612,644,676],'CellSize':[32,32],
        'Note':'Single shared current font; no frozen0109 text/font enters new project.'}
    (asset/'font-extension.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'glyphs':len(ids),'old_preserved':len(previous['glyphs']),'new_texts':len(texts)-len(old.TEXTS),'lsb_zero':all(v&1==0 for v in words)}))
if __name__=='__main__':main()
