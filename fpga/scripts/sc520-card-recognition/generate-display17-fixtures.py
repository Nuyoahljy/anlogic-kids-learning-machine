"""Independent literal UI rows and pixel images for four complete720p cases."""
from pathlib import Path
import hashlib,json,re
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
ASSET=ROOT/'assets/templates/sc520-card-recognition/display17'
def main():
    m=json.loads((ASSET/'font-extension.json').read_text(encoding='utf-8'))
    glyph={g['char']:[int(v,16) for v in g['rows_hex']] for g in m['Glyphs']}
    old_tb=ROOT/'fpga/sim/sc520-card-recognition/tb_pixel14_observation_display.sv'
    tiny={c:int(bits.replace('_',''),2) for c,bits in re.findall(r'"(.)":bitmap=35\'b([01_]+)',old_tb.read_text(encoding='utf-8'))}
    assert len(tiny)>=30
    logo=np.asarray(Image.open(ASSET/'anlogic_logo_rgba.png').convert('RGBA'))
    assert logo.shape==(94,146,4)
    literal=[
        ['探索模式  题号 --/10   分数 00/10','摄像来源：实时画面，待实物验收'.ljust(24)+'原图','语音未接入',
         '探索学习：放入积木或卡片认识物体','K1模式 K2重播 K3切图 K4清分','当前识别：红色圆形'],
        ['探索模式  题号 --/10   分数 00/10','摄像来源：实时画面，待实物验收'.ljust(24)+'处理图','语音未接入',
         '探索学习：放入积木或卡片认识物体','K1模式 K2重播 K3切图 K4清分','当前识别：红色圆形'],
        ['问答模式  题号 01/10   分数 00/10','摄像来源：实时画面，待实物验收'.ljust(24)+'处理图','语音未接入',
         '请找出：红色圆形','已确认移走，请放入答案','当前识别：未知目标'],
        ['问答模式  题号 01/10   分数 00/10','摄像来源：实时画面，待实物验收'.ljust(24)+'处理图','语音未接入',
         '请找出：红色圆形','识别不可信：请移走物体，等待恢复','当前识别：不可信']]
    diagnostics=[
        'D0117 F12345678 V1 A12 X00 E0040 B43 Q01413E02 GR0FF GB102 N00ABC0 W1 T1',
        'C0A08080 C19F8080 C2B79D9D P0F0E8E0 P1EFF0E2 P2F4F5EA C280,168 P0C4,094',
        'MC09E7E7E MC19B7E7E MC2B69B9B MP0E8E0D8 MP1E7E8DA MP2EEEFE4 0=RAW 1=WB 2=TONE',
        'R00001 /00004 /00007 Y00002 /00005 /00008 B00003 /00006 /00009 RAW THRESHOLD COUNTS',
        'S0456 G0033 P0123 V35 RB2 SH5 D013 /045 /089 BC03 CC00 I2 M021 /050 /3AA ',
        'LC010203040506 HC0A0B0C0D0E0F C46500 R38400 I38400 H0330 L02D0 Y02D0 ']
    inks=[0xf5f7fa,0xabe8f2,0xffe3a3,0x9ef0cc]
    paths=[]
    for case,lines in enumerate(literal):
        image=np.zeros((720,1280),dtype=np.uint32)
        colors=[0xc04020,0xc0b030,0x3050c0,0x607080] if case==0 else [0xff0000,0xffff00,0x0000ff,0]
        for i,v in enumerate(colors):image[:,i*320:(i+1)*320]=v
        image[120,160:1120]=image[599,160:1120]=0xff0000
        image[120:600,160]=image[120:600,1119]=0xff0000
        image[8:112,32:1248]=image[608:712,32:1248]=0x18242c
        tones=[1,1,0,1 if case>=2 else 0,2 if case==3 else 0,2 if case==3 else 0]
        for row,text in enumerate(lines):
            assert len(text)<=30 if row<3 else len(text)<=37
            oy=[12,44,76,612,644,676][row]
            for col,char in enumerate(text):
                if char==' ':continue
                for y,bits in enumerate(glyph[char]):
                    for x in range(16):
                        if bits & (1<<(15-x)):image[oy+y*2:oy+y*2+2,48+col*32+x*2:50+col*32+x*2]=inks[tones[row]]
        image[520:592,32:800]=0x101820
        rows=list(diagnostics)
        if case==3:rows[0]=rows[0].replace(' V1 ',' V0 ')
        for row,text in enumerate(rows):
            for col,char in enumerate(text):
                bits=tiny.get(char,0)
                for y in range(7):
                    for x in range(5):
                        if bits&(1<<(34-y*5-x)):image[520+row*12+y,32+col*8+x]=0xff9c9c if case==3 else 0xffff80
        for x0,y0,x1,y1,c in [(634,354,646,366,0x00ffff),(190,142,202,154,0xff00ff)]:
            image[y0,x0:x1]=image[y1-1,x0:x1]=c;image[y0:y1,x0]=image[y0:y1,x1-1]=c
        overlay=logo[:,:,:3].astype(np.uint32);packed=(overlay[:,:,0]<<16)|(overlay[:,:,1]<<8)|overlay[:,:,2]
        target=image[24:118,1008:1154];target[logo[:,:,3]!=0]=packed[logo[:,:,3]!=0]
        p=ASSET/f'golden-{case}.mem';p.write_text(''.join(f'{v:06X}\n' for v in image.flat),encoding='ascii');paths.append(p)
        rgb=np.stack(((image>>16)&255,(image>>8)&255,image&255),axis=2).astype(np.uint8)
        Image.fromarray(rgb).save(ASSET/f'golden-{case}.png')
    manifest={'Cases':literal,'DiagnosticRows':diagnostics,'Modes':[0,1,1,1],'Fresh':[True,True,True,False],
      'Reference':'Literal expected user text; bitmap assets and official RGBA, no DUT calls or production RTL text selector.',
      'TinyGlyphReference':{'Path':str(old_tb),'SHA256':hashlib.sha256(old_tb.read_bytes()).hexdigest().upper()},
      'Files':[{'Path':str(p),'SHA256':hashlib.sha256(p.read_bytes()).hexdigest().upper()} for p in paths]}
    (ASSET/'golden-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('FOUR_LITERAL_720P_FIXTURES_READY')
if __name__=='__main__':main()
