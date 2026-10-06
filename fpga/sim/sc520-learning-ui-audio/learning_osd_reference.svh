// Specification-based reference: formula decomposition and Unicode labels.
// Does not inspect DUT signals or read DUT RTL. Include inside a testbench module.
`include "learning_font_reference.svh"
function automatic integer learning_reference_unicode(input integer codepoint);
    begin
        learning_reference_unicode=0;
        case (codepoint)
            16'h4e2d: learning_reference_unicode=128; // 中
            16'h6587: learning_reference_unicode=129; // 文
            16'h62fc: learning_reference_unicode=130; // 拼
            16'h97f3: learning_reference_unicode=131; // 音
            16'h82f1: learning_reference_unicode=132; // 英
            16'h65e0: learning_reference_unicode=133; // 无
            16'h76ee: learning_reference_unicode=134; // 目
            16'h6807: learning_reference_unicode=135; // 标
            16'h7ea2: learning_reference_unicode=136; // 红
            16'h9ec4: learning_reference_unicode=137; // 黄
            16'h84dd: learning_reference_unicode=138; // 蓝
            16'h8272: learning_reference_unicode=139; // 色
            16'h5706: learning_reference_unicode=140; // 圆
            16'h65b9: learning_reference_unicode=141; // 方
            16'h4e09: learning_reference_unicode=142; // 三
            16'h89d2: learning_reference_unicode=143; // 角
            16'h5f62: learning_reference_unicode=144; // 形
            16'h8bed: learning_reference_unicode=145; // 语
            16'h6a21: learning_reference_unicode=146; // 模
            16'h62df: learning_reference_unicode=147; // 拟
            16'h7a7a: learning_reference_unicode=148; // 空
            16'h95f2: learning_reference_unicode=149; // 闲
            16'h7b49: learning_reference_unicode=150; // 等
            16'h5f85: learning_reference_unicode=151; // 待
            16'h64ad: learning_reference_unicode=152; // 播
            16'h653e: learning_reference_unicode=153; // 放
            16'h6545: learning_reference_unicode=154; // 故
            16'h969c: learning_reference_unicode=155; // 障
            16'h6d4b: learning_reference_unicode=156; // 测
            16'h8bd5: learning_reference_unicode=157; // 试
            16'h8f93: learning_reference_unicode=158; // 输
            16'h5165: learning_reference_unicode=159; // 入
            16'h6444: learning_reference_unicode=160; // 摄
            16'h50cf: learning_reference_unicode=161; // 像
            16'h4ec5: learning_reference_unicode=162; // 仅
            16'h8f6f: learning_reference_unicode=163; // 软
            16'h4ef6: learning_reference_unicode=164; // 件
            16'h9a8c: learning_reference_unicode=165; // 验
            16'h8bc1: learning_reference_unicode=166; // 证
            default: if (codepoint < 128) learning_reference_unicode=codepoint;
        endcase
    end
endfunction

function automatic integer learning_expected_glyph(input integer item, input bit valid,
    input integer line_number, input integer position);
    integer color_number, shape_number, codepoint;
    string text_line, color_word, shape_word;
    begin
        text_line="";codepoint=0;color_number=0;shape_number=0;
        if (!valid || item < 1 || item > 9) begin
            if (line_number == 0) begin
                case (position)
                    0: codepoint=16'h65e0; // 无
                    1: codepoint=16'h76ee; // 目
                    2: codepoint=16'h6807; // 标
                endcase
            end else if (line_number == 1 || line_number == 2) text_line="--";
        end else begin
            color_number=(item-1)/3;
            shape_number=(item-1)%3;
            if (line_number == 0) begin
                case (position)
                    0: case (color_number)
                        0: codepoint=16'h7ea2; 1: codepoint=16'h9ec4; 2: codepoint=16'h84dd;
                    endcase
                    1: codepoint=16'h8272;
                    2: case (shape_number)
                        0: codepoint=16'h5706; 1: codepoint=16'h65b9; 2: codepoint=16'h4e09;
                    endcase
                    3: codepoint=shape_number == 2 ? 16'h89d2 : 16'h5f62;
                    4: if(shape_number==2) codepoint=16'h5f62;
                endcase
            end else if (line_number == 1) begin
                case(color_number)
                    0:color_word="hong";1:color_word="huang";2:color_word="lan";
                endcase
                case(shape_number)
                    0:shape_word="yuan xing";1:shape_word="fang xing";2:shape_word="san jiao xing";
                endcase
                text_line={color_word," se ",shape_word};
            end else if (line_number == 2) begin
                case(color_number)
                    0:color_word="red";1:color_word="yellow";2:color_word="blue";
                endcase
                case(shape_number)
                    0:shape_word="circle";1:shape_word="square";2:shape_word="triangle";
                endcase
                text_line={color_word," ",shape_word};
            end
        end
        if (line_number > 0 && position >= 0 && position < text_line.len()) codepoint=text_line[position];
        learning_expected_glyph=learning_reference_unicode(codepoint);
    end
endfunction

function automatic [23:0] learning_reference_rgb(input integer xpos, input integer ypos,
    input integer item, input bit valid, input bit demo, input logic [1:0] status);
    integer glyph_id, codepoint, font_row, font_column, line_number, position;
    reg [255:0] bitmap;
    reg [23:0] ink;
    bit panel, meaningful_item;
    begin
        panel=(xpos>=32 && xpos<=1247 && ypos>=608 && ypos<=711);
        meaningful_item=valid && item>=1 && item<=9;
        glyph_id=0;codepoint=0;font_row=0;font_column=0;
        line_number=0;position=0;ink=24'hf5f7fa;
        if(panel && ypos>=612 && ypos<=707) begin
            line_number=(ypos-612)/32;
            font_row=((ypos-612)%32)/2;
            if(xpos>=48 && xpos<=143) begin
                position=(xpos-48)/32;font_column=((xpos-48)%32)/2;
                if(position==0)begin
                    case(line_number)
                        0:codepoint=16'h4e2d;1:codepoint=16'h62fc;2:codepoint=16'h82f1;
                    endcase
                end else if(position==1) codepoint=line_number==1 ? 16'h97f3 : 16'h6587;
                else if(position==2)codepoint=58;
                glyph_id=learning_reference_unicode(codepoint);ink=24'hc4d6e3;
            end else if(xpos>=160 && xpos<=863) begin
                if(line_number==0)begin
                    position=(xpos-160)/32;font_column=((xpos-160)%32)/2;
                end else begin
                    position=(xpos-160)/16;font_column=((xpos-160)%16)/2;
                end
                glyph_id=learning_expected_glyph(item,valid,line_number,position);
                if(!meaningful_item)ink=24'hc4d6e3;
            end else if(xpos>=928 && xpos<=1215) begin
                position=(xpos-928)/32;font_column=((xpos-928)%32)/2;
                case(line_number)
                    0:begin
                        case(position)
                            0:codepoint=16'h8bed;1:codepoint=16'h97f3;2:codepoint=16'h6a21;3:codepoint=16'h62df;4:codepoint=58;
                            5:case(status)
                                0:codepoint=16'h7a7a;1:codepoint=16'h7b49;2:codepoint=16'h64ad;3:codepoint=16'h6545;
                            endcase
                            6:case(status)
                                0:codepoint=16'h95f2;1:codepoint=16'h5f85;2:codepoint=16'h653e;3:codepoint=16'h969c;
                            endcase
                        endcase
                        if(status==3)ink=24'hffcc99;
                        else if(status==2)ink=24'h9ef0cc;
                    end
                    1:begin
                        case(position)
                            0:codepoint=demo ? 16'h6d4b : 16'h6444;
                            1:codepoint=demo ? 16'h8bd5 : 16'h50cf;
                            2:codepoint=16'h8f93;3:codepoint=16'h5165;
                        endcase
                        ink=demo ? 24'hffe3a3 : 24'habe8f2;
                    end
                    2:begin
                        case(position)
                            0:codepoint=16'h4ec5;1:codepoint=16'h8f6f;2:codepoint=16'h4ef6;3:codepoint=16'h9a8c;4:codepoint=16'h8bc1;
                        endcase
                        ink=24'hc4d6e3;
                    end
                endcase
                glyph_id=learning_reference_unicode(codepoint);
            end
        end
        bitmap=learning_reference_bitmap(glyph_id);
        learning_reference_rgb=panel ? (bitmap[255-font_row*16-font_column] ? ink : 24'h18242c) : 24'h000000;
    end
endfunction
