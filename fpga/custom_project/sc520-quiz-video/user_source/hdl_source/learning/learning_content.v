// Experimental isolated display adapter; shared item_id numbering is unchanged.
module learning_content (
    input wire [3:0] item_id,
    input wire det_valid,
    input wire [1:0] line_index,
    input wire [5:0] char_index,
    output reg [7:0] glyph,
    output wire valid_item
);
    reg [191:0] text_bytes;
    wire [3:0] content_id = valid_item ? item_id : 4'd0;
    assign valid_item = det_valid && item_id >= 4'd1 && item_id <= 4'd9;
    always @* begin
        text_bytes = 192'd0;
        case ({line_index,content_id})
            6'd0: text_bytes = 192'h858687000000000000000000000000000000000000000000; // 无目标
            6'd1: text_bytes = 192'h888b8c900000000000000000000000000000000000000000; // 红色圆形
            6'd2: text_bytes = 192'h888b8d900000000000000000000000000000000000000000; // 红色方形
            6'd3: text_bytes = 192'h888b8e8f9000000000000000000000000000000000000000; // 红色三角形
            6'd4: text_bytes = 192'h898b8c900000000000000000000000000000000000000000; // 黄色圆形
            6'd5: text_bytes = 192'h898b8d900000000000000000000000000000000000000000; // 黄色方形
            6'd6: text_bytes = 192'h898b8e8f9000000000000000000000000000000000000000; // 黄色三角形
            6'd7: text_bytes = 192'h8a8b8c900000000000000000000000000000000000000000; // 蓝色圆形
            6'd8: text_bytes = 192'h8a8b8d900000000000000000000000000000000000000000; // 蓝色方形
            6'd9: text_bytes = 192'h8a8b8e8f9000000000000000000000000000000000000000; // 蓝色三角形
            6'd16: text_bytes = 192'h2d2d00000000000000000000000000000000000000000000; // --
            6'd17: text_bytes = 192'h686f6e67207365207975616e2078696e6700000000000000; // hong se yuan xing
            6'd18: text_bytes = 192'h686f6e672073652066616e672078696e6700000000000000; // hong se fang xing
            6'd19: text_bytes = 192'h686f6e672073652073616e206a69616f2078696e67000000; // hong se san jiao xing
            6'd20: text_bytes = 192'h6875616e67207365207975616e2078696e67000000000000; // huang se yuan xing
            6'd21: text_bytes = 192'h6875616e672073652066616e672078696e67000000000000; // huang se fang xing
            6'd22: text_bytes = 192'h6875616e672073652073616e206a69616f2078696e670000; // huang se san jiao xing
            6'd23: text_bytes = 192'h6c616e207365207975616e2078696e670000000000000000; // lan se yuan xing
            6'd24: text_bytes = 192'h6c616e2073652066616e672078696e670000000000000000; // lan se fang xing
            6'd25: text_bytes = 192'h6c616e2073652073616e206a69616f2078696e6700000000; // lan se san jiao xing
            6'd32: text_bytes = 192'h2d2d00000000000000000000000000000000000000000000; // --
            6'd33: text_bytes = 192'h72656420636972636c650000000000000000000000000000; // red circle
            6'd34: text_bytes = 192'h726564207371756172650000000000000000000000000000; // red square
            6'd35: text_bytes = 192'h72656420747269616e676c65000000000000000000000000; // red triangle
            6'd36: text_bytes = 192'h79656c6c6f7720636972636c650000000000000000000000; // yellow circle
            6'd37: text_bytes = 192'h79656c6c6f77207371756172650000000000000000000000; // yellow square
            6'd38: text_bytes = 192'h79656c6c6f7720747269616e676c65000000000000000000; // yellow triangle
            6'd39: text_bytes = 192'h626c756520636972636c6500000000000000000000000000; // blue circle
            6'd40: text_bytes = 192'h626c75652073717561726500000000000000000000000000; // blue square
            6'd41: text_bytes = 192'h626c756520747269616e676c650000000000000000000000; // blue triangle
            default: text_bytes = 192'd0;
        endcase
        glyph = 8'd0;
        case (char_index)
            6'd0: glyph = text_bytes[191:184];
            6'd1: glyph = text_bytes[183:176];
            6'd2: glyph = text_bytes[175:168];
            6'd3: glyph = text_bytes[167:160];
            6'd4: glyph = text_bytes[159:152];
            6'd5: glyph = text_bytes[151:144];
            6'd6: glyph = text_bytes[143:136];
            6'd7: glyph = text_bytes[135:128];
            6'd8: glyph = text_bytes[127:120];
            6'd9: glyph = text_bytes[119:112];
            6'd10: glyph = text_bytes[111:104];
            6'd11: glyph = text_bytes[103:96];
            6'd12: glyph = text_bytes[95:88];
            6'd13: glyph = text_bytes[87:80];
            6'd14: glyph = text_bytes[79:72];
            6'd15: glyph = text_bytes[71:64];
            6'd16: glyph = text_bytes[63:56];
            6'd17: glyph = text_bytes[55:48];
            6'd18: glyph = text_bytes[47:40];
            6'd19: glyph = text_bytes[39:32];
            6'd20: glyph = text_bytes[31:24];
            6'd21: glyph = text_bytes[23:16];
            6'd22: glyph = text_bytes[15:8];
            6'd23: glyph = text_bytes[7:0];
            default: glyph = 8'd0;
        endcase
    end
endmodule
