// HDMI RGB888 的组合判色器；仅供显示，不产生识别帧结果。
// 自研规则来源：sc520-fixed-roi 工程 roi/rgb_color_segment.v，
// SHA256 35051F8DBE446AFD73DAE6488B15FFC1D4ABF80BC3635CC918F5468A26F180EA。
// 已核对启动基线 c300a81 中 pixel14/block_frame_recognizer.v 的规则相同。
// 编码：0=其他，1=红，2=黄，3=蓝；黄色优先，避免黄/红重叠误选。
module sc520_color_classify (
    input wire [23:0] in_rgb,
    output wire [1:0] color_id
);
    // 先扩展为9位，255+80等边界运算不会以8位回绕。
    wire [8:0] red = {1'b0, in_rgb[23:16]};
    wire [8:0] green = {1'b0, in_rgb[15:8]};
    wire [8:0] blue = {1'b0, in_rgb[7:0]};

    wire red_hit = red >= 9'd80 &&
                   red >= green + 9'd32 &&
                   red >= blue + 9'd32;
    wire blue_hit = blue >= 9'd80 &&
                    blue >= red + 9'd24 &&
                    blue >= green + 9'd24;
    wire yellow_hit = red >= 9'd96 && green >= 9'd80 &&
                      blue <= 9'd96 &&
                      red <= green + 9'd80 &&
                      green <= red + 9'd80 &&
                      red >= blue + 9'd32 &&
                      green >= blue + 9'd24;

    assign color_id = yellow_hit ? 2'd2 :
                      red_hit ? 2'd1 :
                      blue_hit ? 2'd3 : 2'd0;
endmodule
