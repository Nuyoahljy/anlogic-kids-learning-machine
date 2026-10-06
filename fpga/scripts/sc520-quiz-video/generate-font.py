#!/usr/bin/env python3
"""Generate this task's local SimSun subset and text tables. Requires Pillow.

Only the new task's ROM/content/reference files are written. The original font
file is not copied, and no open-source redistribution licence is asserted.
"""
import argparse
import hashlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

TEXTS = [
    "", "待机模式", "探索模式", "问答模式", "模式异常",
    "题号", "分数",
    "测试来源：内置画面，禁止正式计分",
    "摄像来源：实时画面，待实物验收",
    "音频模拟：空闲    按键模拟：脚本控制",
    "音频模拟：播放    按键模拟：脚本控制",
    "音频模拟：故障    按键模拟：脚本控制",
    "请放置积木，或切换到问答模式",
    "探索学习：放入积木认识颜色和形状",
    "请找出：", "本轮完成：共10题，总分", "状态异常：请复位",
    "测试画面只作演示，不参与正式计分",
    "答题结束，可清分退出或切换模式",
    "回答正确！加1分，请先移走积木",
    "再试一次！请先移走，再重新放入",
    "两次答错，显示答案，本题不加分",
    "已确认移走，请放入答案", "请先移走旧物体，再放入答案",
    "相同物体持续存在时不重复触发",
    "当前识别：", "正确答案：", "未知目标",
    "红色圆形", "红色方形", "红色三角形",
    "黄色圆形", "黄色方形", "黄色三角形",
    "蓝色圆形", "蓝色方形", "蓝色三角形",
]

CONTENT = r'''// Generated text assets with manually specified presentation selectors.
module quiz_content(
    input wire [2:0] line_index,
    input wire [5:0] char_index,
    input wire [1:0] mode, phase,
    input wire [3:0] score, question_index, target_item, display_item,
    input wire [2:0] feedback,
    input wire source_test, armed, audio_fault, audio_busy,
    output reg [7:0] glyph,
    output reg [1:0] tone
);
@@TABLE@@
    function [7:0] digit;
        input [3:0] number;
        input tens;
        begin
            if (number > 10) digit=8'd45;
            else if(tens) digit=number==10 ? 8'd49 : 8'd48;
            else digit=number==10 ? 8'd48 : 8'd48+number;
        end
    endfunction
    function [7:0] object_glyph;
        input [3:0] item;
        input [5:0] column;
        begin
            if (item >= 1 && item <= 9) object_glyph=text_glyph(6'd27+item,column);
            else object_glyph=text_glyph(6'd27,column);
        end
    endfunction
    reg [5:0] message_id;
    always @* begin
        glyph=0; tone=0; message_id=0;
        case(line_index)
            0: begin
                tone=1;
                if(char_index<4) glyph=text_glyph({4'd0,mode}+6'd1,char_index);
                else if(char_index>=6 && char_index<8) glyph=text_glyph(6'd5,char_index-6);
                else if(char_index==9 || char_index==10)
                    glyph=mode==2 && question_index>=1 ? digit(question_index,char_index==9) : 8'd45;
                else if(char_index==11 || char_index==22) glyph=8'd47;
                else if(char_index==12 || char_index==23) glyph=8'd49;
                else if(char_index==13 || char_index==24) glyph=8'd48;
                else if(char_index>=17 && char_index<19) glyph=text_glyph(6'd6,char_index-17);
                else if(char_index==20 || char_index==21) glyph=digit(score,char_index==20);
            end
            1: begin
                glyph=text_glyph(source_test ? 6'd7 : 6'd8,char_index);
                tone=source_test ? 2 : 1;
            end
            2: begin
                glyph=text_glyph(audio_fault ? 6'd11 : (audio_busy ? 6'd10 : 6'd9),char_index);
                tone=audio_fault ? 2 : 0;
            end
            3: begin
                if(mode==0) glyph=text_glyph(6'd12,char_index);
                else if(mode==1) glyph=text_glyph(6'd13,char_index);
                else if(mode!=2 || phase==0) glyph=text_glyph(6'd16,char_index);
                else if(phase==3) begin
                    if(char_index<14) glyph=text_glyph(6'd15,char_index);
                    else if(char_index==14 || char_index==15) glyph=digit(score,char_index==14);
                    tone=3;
                end else begin
                    if(char_index<4) glyph=text_glyph(6'd14,char_index);
                    else glyph=object_glyph(target_item,char_index-4);
                    tone=1;
                end
            end
            4: begin
                if(source_test) begin message_id=17; tone=2; end
                else if(mode==2 && phase==3) begin message_id=18; tone=3; end
                else if(mode==2 && phase==2) begin
                    case(feedback)
                        1: begin message_id=19; tone=3; end
                        2: begin message_id=20; tone=2; end
                        3: begin message_id=21; tone=2; end
                        default: begin message_id=16; tone=2; end
                    endcase
                end else if(mode==2 && phase==1) message_id=armed ? 22 : 23;
                else if(mode==0 || mode==1) message_id=24;
                else begin message_id=16; tone=2; end
                glyph=text_glyph(message_id,char_index);
            end
            5: begin
                if(mode==2 && phase==2 && feedback==3) begin
                    tone=2;
                    if(char_index<5) glyph=text_glyph(6'd26,char_index);
                    else glyph=object_glyph(target_item,char_index-5);
                end else begin
                    if(char_index<5) glyph=text_glyph(6'd25,char_index);
                    else glyph=object_glyph(display_item,char_index-5);
                end
            end
            default: begin end
        endcase
    end
endmodule
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, default=Path("C:/Windows/Fonts/simsun.ttc"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    rtl_dir = repo / "fpga/custom_project/sc520-quiz-video/user_source/hdl_source/quiz"
    sim_dir = repo / "fpga/sim/sc520-quiz-video"
    font = ImageFont.truetype(str(args.font), 16, index=0)
    if font.getname()[0].lower() not in ("simsun", "宋体"):
        raise ValueError("Required SimSun face unavailable; no silent fallback")
    digest = hashlib.sha256(args.font.read_bytes()).hexdigest().upper()
    ascii_chars = " -/0123456789"
    chinese = sorted(set("".join(TEXTS)) - set(ascii_chars))
    available = [i for i in range(1, 256) if i not in map(ord, ascii_chars)]
    if len(chinese) > len(available):
        raise ValueError("8-bit glyph space exhausted")
    ids = {c: ord(c) for c in ascii_chars}
    ids.update(dict(zip(chinese, available)))
    font_rows = {}
    for char, code in sorted(ids.items(), key=lambda pair: pair[1]):
        bitmap = Image.new("L", (16,16), 0)
        if char != " ":
            box = font.getbbox(char)
            width, height = box[2]-box[0], box[3]-box[1]
            if width>16 or height>16:
                raise ValueError(f"Glyph exceeds 16x16: {char!r} {box}")
            ImageDraw.Draw(bitmap).text(((16-width)//2-box[0], (16-height)//2-box[1]),char,font=font,fill=255)
        rows = [sum((1 << (15-x)) for x in range(16) if bitmap.getpixel((x,y))>=128) for y in range(16)]
        if char != " " and not any(rows):
            raise ValueError("Empty glyph: "+char)
        font_rows[code]=rows
    header = f"// Local SimSun 16px, monochrome threshold 128; source SHA256 {digest}.\n"
    rom=[header,"module quiz_font_rom(input wire [7:0] glyph,input wire [3:0] row,output reg [15:0] bits);",
         "always @* begin", "    bits=0;", "    case({glyph,row})"]
    ref=[header,"// Full-bitmap reference: same font asset, independent pixel addressing in TB.",
         "function automatic [255:0] quiz_ref_bitmap(input integer glyph_id);", "begin", "quiz_ref_bitmap=0;", "case(glyph_id)"]
    for code, rows in font_rows.items():
        for row,bits in enumerate(rows):
            if bits: rom.append(f"        12'd{code*16+row}: bits=16'h{bits:04X};")
        ref.append(f"{code}: quiz_ref_bitmap=256'h{''.join(f'{r:04X}' for r in rows)};")
    rom += ["    endcase", "end", "endmodule", ""]
    ref += ["endcase", "end", "endfunction"]
    table=["    function [7:0] text_glyph;", "        input [5:0] text_id,position;", "        begin", "            text_glyph=0;", "            case({text_id,position})"]
    ref += ["function automatic integer quiz_ref_text(input integer text_id,input integer position);", "begin", "quiz_ref_text=0;", "case(text_id)"]
    for tid,text in enumerate(TEXTS):
        if len(text)>37: raise ValueError(f"Text {tid} exceeds viewport")
        ref += [f"{tid}: begin", "case(position)"]
        for pos,char in enumerate(text):
            code=ids[char]
            if char!=" ":
                table.append(f"                12'd{tid*64+pos}: text_glyph=8'd{code};")
                ref.append(f"{pos}: quiz_ref_text={code};")
        ref += ["default: quiz_ref_text=0;", "endcase", "end"]
    table += ["            endcase", "        end", "    endfunction"]
    ref += ["endcase", "end", "endfunction", ""]
    rtl_dir.mkdir(parents=True,exist_ok=True); sim_dir.mkdir(parents=True,exist_ok=True)
    (rtl_dir / "quiz_font_rom.v").write_text("\n".join(rom),encoding="ascii")
    (rtl_dir / "quiz_content.v").write_text(CONTENT.replace("@@TABLE@@","\n".join(table)),encoding="ascii")
    (sim_dir / "quiz_bitmap_reference.svh").write_text("\n".join(ref),encoding="ascii")
    print(f"QUIZ_FONT glyphs={len(ids)} text_entries={len(TEXTS)} max_columns={max(map(len,TEXTS))} font_sha256={digest}")


if __name__ == "__main__": main()
