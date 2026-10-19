// HDMI显示时钟域、预OSD RGB888处理支路；原图与分割均经过同一层寄存器。
// 所有输入必须与clk同域同拍，rst_n异步置位复位、由外部同步释放。
// 输入在一个上升沿被采样，输出在该沿之后更新：一层寄存器/一个像素周期延迟。
// mode_request必须已同步clk；in_frame_start是一帧一个周期的合法标记，
// 可位于首个有效像素或其前的消隐。该标记同拍像素立即使用新模式，
// 后续像素保持此模式到下一次标记；模块不检测伪造或缺失的帧标记。
// 本显示掩模不绑定AWB96采集帧、识别frame_id或识别器的稳定结果。
module pixel26_processing_display #(
    parameter integer ROI_ENABLE = 0,
    parameter integer X_MIN = 320,
    parameter integer X_MAX = 959,
    parameter integer Y_MIN = 120,
    parameter integer Y_MAX = 599
) (
    input wire clk,
    input wire rst_n,
    input wire in_frame_start,
    input wire in_de,
    input wire in_hsync,
    input wire in_vsync,
    input wire mode_request,
    input wire [10:0] in_x,
    input wire [9:0] in_y,
    input wire [23:0] in_rgb,
    output reg out_frame_start,
    output reg out_de,
    output reg out_hsync,
    output reg out_vsync,
    output reg out_mode,
    output reg [10:0] out_x,
    output reg [9:0] out_y,
    output reg [23:0] out_rgb,
    output reg [1:0] out_color_id
);
    reg frame_mode;
    wire pixel_mode = in_frame_start ? mode_request : frame_mode;

    // ROI包含两个端点；默认ROI_ENABLE=0，整个有效画面参与分割。
    // ROI_ENABLE=1时，ROI外输出增强后的相机底图，out_color_id置0。
    wire in_scope = (ROI_ENABLE == 0) ||
                    (in_x >= X_MIN && in_x <= X_MAX &&
                     in_y >= Y_MIN && in_y <= Y_MAX);
    wire [1:0] classified_color;
    pixel26_color_classify classify (
        .in_rgb(in_rgb),
        .color_id(classified_color)
    );

    wire [23:0] enhanced_rgb;
    pixel26_saturation enhance(.in_rgb(in_rgb),.out_rgb(enhanced_rgb));
    wire [23:0] segmented_rgb = classified_color == 2'd1 ? 24'hff0000 :
                               classified_color == 2'd2 ? 24'hffff00 :
                               classified_color == 2'd3 ? 24'h0000ff : 24'h000000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_mode <= 1'b0;
            out_frame_start <= 1'b0;
            out_de <= 1'b0;
            out_hsync <= 1'b0;
            out_vsync <= 1'b0;
            out_mode <= 1'b0;
            out_x <= 11'd0;
            out_y <= 10'd0;
            out_rgb <= 24'd0;
            out_color_id <= 2'd0;
        end else begin
            if (in_frame_start)
                frame_mode <= mode_request;

            out_frame_start <= in_frame_start;
            out_de <= in_de;
            out_hsync <= in_hsync;
            out_vsync <= in_vsync;
            out_mode <= pixel_mode;
            // 消隐期间也保持坐标、同步与frame_start的一拍对应关系。
            out_x <= in_x;
            out_y <= in_y;
            out_rgb <= !in_de ? 24'd0 :
                       (pixel_mode && in_scope) ? segmented_rgb : enhanced_rgb;
            // 分类旁带不受显示模式影响；消隐或ROI外无有效分类。
            out_color_id <= (in_de && in_scope) ? classified_color : 2'd0;
        end
    end

    // 参数契约按坐标端口范围检查，允许单像素ROI。
    // 实际1280x720画面的ROI位置仍由集成方约束；禁用ROI也必须给出合法参数。
    // synthesis translate_off
    initial begin
        if ((ROI_ENABLE != 0 && ROI_ENABLE != 1) ||
            X_MIN < 0 || X_MAX > 2047 || X_MIN > X_MAX ||
            Y_MIN < 0 || Y_MAX > 1023 || Y_MIN > Y_MAX)
            $fatal(1, "pixel26_processing_display invalid ROI parameters");
    end
    // synthesis translate_on
endmodule
