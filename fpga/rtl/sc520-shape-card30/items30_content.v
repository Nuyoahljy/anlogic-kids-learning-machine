// Preserve the original workflow text; replace only the new catalog's nouns.
module items30_content(
    input wire [2:0] line_index,input wire [5:0] char_index,
    input wire [1:0] mode,phase,
    input wire [3:0] score,question_index,target_item,display_item,
    input wire [2:0] feedback,
    input wire source_test,armed,audio_fault,audio_busy,result_healthy,display_mode,
    output reg [7:0] glyph,output wire [1:0] tone
);
    wire [7:0] original_glyph;
    items14_content #(.SCENE_UI(1),.DISPLAY_UI(1)) original(
        .line_index(line_index),.char_index(char_index),.mode(mode),.phase(phase),
        .score(score),.question_index(question_index),.target_item(target_item),.display_item(display_item),
        .feedback(feedback),.source_test(source_test),.armed(armed),.audio_fault(audio_fault),
        .audio_busy(audio_busy),.result_healthy(result_healthy),.display_mode(display_mode),
        .glyph(original_glyph),.tone(tone));
    function [7:0] object_glyph;
        input [3:0] item;input [5:0] column;
        begin
            object_glyph=0;
            case(item)
                1: case(column)0:object_glyph=34;1:object_glyph=58;default:object_glyph=0;endcase
                2: case(column)0:object_glyph=78;1:object_glyph=58;default:object_glyph=0;endcase
                3: case(column)0:object_glyph=3;1:object_glyph=124;2:object_glyph=58;default:object_glyph=0;endcase
                10:case(column)0:object_glyph=121;1:object_glyph=90;default:object_glyph=0;endcase
                11:case(column)0:object_glyph=147;1:object_glyph=123;default:object_glyph=0;endcase
                12:case(column)0:object_glyph=97;1:object_glyph=132;default:object_glyph=0;endcase
                13:case(column)0:object_glyph=81;1:object_glyph=81;default:object_glyph=0;endcase
                14:case(column)0:object_glyph=142;1:object_glyph=8;default:object_glyph=0;endcase
                default:case(column)
                    0:object_glyph=84;1:object_glyph=107;2:object_glyph=106;3:object_glyph=91;
                    default:object_glyph=0;
                endcase
            endcase
        end
    endfunction
    always @* begin
        glyph=original_glyph;
        if(line_index==3 && mode==2 && (phase==1 || phase==2) && char_index>=4)
            glyph=object_glyph(target_item,char_index-4);
        if(line_index==5 && result_healthy && char_index>=5)
            glyph=object_glyph(mode==2 && phase==2 && feedback==3 ? target_item:display_item,char_index-5);
    end
endmodule
