// Lossless synchronous-ROM alternative to sc520_logo_overlay.
// Official pixels and provenance: assets/sc520-processing-display/logo_manifest.json.
// Four register stages: address -> index ROM -> palette ROM -> RGB mix.
// An input sampled at edge N appears after edge N+3 (four register layers).
// All inputs must be synchronous to clk; rst_n asserts asynchronously and must
// be released synchronously by the caller. No frame/mode decision is made here.
`default_nettype none
module sc520_logo_pipeline #(
    parameter integer X_ORIGIN = 1008,
    parameter integer Y_ORIGIN = 32,
    parameter INDEX_FILE = "assets/sc520-processing-display/anlogic_logo_index.mem",
    parameter PALETTE_FILE = "assets/sc520-processing-display/anlogic_logo_palette.mem"
) (
    input wire clk,
    input wire rst_n,
    input wire in_frame_start,
    input wire in_de,
    input wire in_hsync,
    input wire in_vsync,
    input wire in_mode,
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
    output reg logo_active
);
    localparam integer LOGO_WIDTH = 146;
    localparam integer LOGO_HEIGHT = 94;

    // TD 6.2.1 ROM-Inference-Styles template specifies the value "bram".
    // Fully initialized, padded tables keep every possible address defined.
    (* rom_style = "bram" *) reg [9:0] index_rom [0:16383];
    (* rom_style = "bram" *) reg [23:0] palette_rom [0:1023];
    initial begin
        $readmemh(INDEX_FILE, index_rom);
        $readmemh(PALETTE_FILE, palette_rom);
    end

    wire inside_logo = in_de && (in_x >= X_ORIGIN) &&
                       (in_x < X_ORIGIN + LOGO_WIDTH) &&
                       (in_y >= Y_ORIGIN) &&
                       (in_y < Y_ORIGIN + LOGO_HEIGHT);
    wire [10:0] offset_x = in_x - X_ORIGIN;
    wire [9:0] offset_y = in_y - Y_ORIGIN;
    wire [13:0] y_extended = {7'd0, offset_y[6:0]};
    wire [13:0] x_extended = {6'd0, offset_x[7:0]};
    // 146 = 128+16+2, explicit bounded adders rather than a variable multiplier.
    wire [13:0] row_address = (y_extended << 7) + (y_extended << 4) +
                             (y_extended << 1) + x_extended;

    reg [13:0] s1_address;
    reg [9:0] s2_index;
    reg [23:0] s3_color;
    // {frame_start, de, hsync, vsync, mode, x[10:0], y[9:0], rgb[23:0]}.
    reg [49:0] s1_video, s2_video, s3_video;
    reg s1_inside, s2_inside, s3_opaque;
    reg s1_valid, s2_valid, s3_valid;

    // The address, memories and ROM read registers intentionally have no reset.
    // TD must be able to absorb the address register into its ERAM read path.
    // Reset acts on video/valid only, preventing old ROM data from escaping.
    always @(posedge clk) begin
        s1_address <= inside_logo ? row_address : 14'd0;
        s2_index <= index_rom[s1_address];
        s3_color <= palette_rom[s2_index];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_video <= 50'd0;
            s2_video <= 50'd0;
            s3_video <= 50'd0;
            s1_inside <= 1'b0;
            s2_inside <= 1'b0;
            s3_opaque <= 1'b0;
            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
            s3_valid <= 1'b0;
            {out_frame_start, out_de, out_hsync, out_vsync, out_mode,
             out_x, out_y, out_rgb, logo_active} <= 51'd0;
        end else begin
            s1_video <= {in_frame_start, in_de, in_hsync, in_vsync, in_mode,
                         in_x, in_y, in_rgb};
            s2_video <= s1_video;
            s3_video <= s2_video;
            s1_inside <= inside_logo;
            s2_inside <= s1_inside;
            s3_opaque <= s2_inside && (s2_index != 10'd0);
            s1_valid <= 1'b1;
            s2_valid <= s1_valid;
            s3_valid <= s2_valid;

            if (s3_valid) begin
                {out_frame_start, out_de, out_hsync, out_vsync, out_mode,
                 out_x, out_y} <= s3_video[49:24];
                out_rgb <= !s3_video[48] ? 24'd0 :
                           s3_opaque ? s3_color : s3_video[23:0];
                logo_active <= s3_video[48] && s3_opaque;
            end else begin
                {out_frame_start, out_de, out_hsync, out_vsync, out_mode,
                 out_x, out_y, out_rgb, logo_active} <= 51'd0;
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (X_ORIGIN < 0 || X_ORIGIN > 2047 || Y_ORIGIN < 0 || Y_ORIGIN > 1023)
            $fatal(1, "sc520_logo_pipeline invalid origin");
    end
    // synthesis translate_on
endmodule
`default_nettype wire
