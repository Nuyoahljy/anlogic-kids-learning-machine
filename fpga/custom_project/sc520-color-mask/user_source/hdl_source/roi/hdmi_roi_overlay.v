module hdmi_roi_overlay #(
    parameter integer FRAME_WIDTH = 1280,
    parameter integer FRAME_HEIGHT = 720,
    parameter integer X_MIN = 320,
    parameter integer X_MAX = 959,
    parameter integer Y_MIN = 120,
    parameter integer Y_MAX = 599
) (
    input wire clk,
    input wire rst_n,
    input wire in_vsync,
    input wire in_hsync,
    input wire in_de,
    input wire [23:0] in_rgb,
    output wire out_vsync,
    output wire out_hsync,
    output wire out_de,
    output wire [23:0] out_rgb
);
    reg [2:0] vsync_pipe;
    reg [2:0] hsync_pipe;
    reg [2:0] de_pipe;
    reg [23:0] rgb_sample;
    reg [23:0] rgb_delay;
    reg [23:0] rgb_fallback;
    reg frame_pending;
    wire sample_sof = de_pipe[0] && frame_pending;
    wire sample_eol = de_pipe[0] && !in_de;
    wire [23:0] coord_rgb;
    wire [10:0] coord_x;
    wire [9:0] coord_y;
    wire coord_valid;
    wire coord_sof;
    wire coord_eol;
    wire [23:0] overlay_rgb;
    wire overlay_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vsync_pipe <= 0;
            hsync_pipe <= 0;
            de_pipe <= 0;
            rgb_sample <= 0;
            rgb_delay <= 0;
            rgb_fallback <= 0;
            frame_pending <= 0;
        end else begin
            vsync_pipe <= {vsync_pipe[1:0], in_vsync};
            hsync_pipe <= {hsync_pipe[1:0], in_hsync};
            de_pipe <= {de_pipe[1:0], in_de};
            rgb_sample <= in_rgb;
            rgb_delay <= rgb_sample;
            rgb_fallback <= rgb_delay;
            if (in_vsync && !vsync_pipe[0])
                frame_pending <= 1;
            else if (de_pipe[0])
                frame_pending <= 0;
        end
    end

    pixel_coord_adapter #(
        .FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT)
    ) coordinates (
        .clk(clk), .rst_n(rst_n),
        .in_rgb(rgb_sample), .in_valid(de_pipe[0]),
        .in_sof(sample_sof), .in_eol(sample_eol),
        .out_rgb(coord_rgb), .out_x(coord_x), .out_y(coord_y),
        .out_valid(coord_valid), .out_sof(coord_sof), .out_eol(coord_eol)
    );

    fixed_rect_overlay #(
        .X_MIN(X_MIN), .X_MAX(X_MAX), .Y_MIN(Y_MIN), .Y_MAX(Y_MAX)
    ) rectangle (
        .clk(clk), .rst_n(rst_n),
        .in_rgb(coord_rgb), .in_x(coord_x), .in_y(coord_y),
        .in_valid(coord_valid), .in_sof(coord_sof), .in_eol(coord_eol),
        .out_rgb(overlay_rgb), .out_x(), .out_y(),
        .out_valid(overlay_valid), .out_sof(), .out_eol()
    );

    assign out_vsync = vsync_pipe[2];
    assign out_hsync = hsync_pipe[2];
    assign out_de = de_pipe[2];
    assign out_rgb = !out_de ? 24'd0 :
                     overlay_valid ? overlay_rgb : rgb_fallback;
endmodule
