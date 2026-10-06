module demo_sequence #(parameter integer SCENE_FRAMES = 180) (
    input wire clk, rst_n, frame_tick,
    output reg demo_mode,
    output reg [3:0] scene,
    output reg [15:0] scene_frame,
    output reg scene_changed,
    output reg [1:0] expected_shape, expected_color
);
    reg armed;
    always @* begin
        expected_shape = 0;
        expected_color = 0;
        if (demo_mode && scene < 9) begin
            case (scene)
                0,3,6: expected_shape = 1;
                1,4,7: expected_shape = 2;
                2,5,8: expected_shape = 3;
            endcase
            if (scene < 3) expected_color = 1;
            else if (scene < 6) expected_color = 2;
            else expected_color = 3;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            demo_mode <= 1; scene <= 0; scene_frame <= 0;
            scene_changed <= 0; armed <= 0;
        end else begin
            scene_changed <= 0;
            if (frame_tick) begin
                if (!armed) armed <= 1;
                else if (demo_mode) begin
                    if (scene_frame == SCENE_FRAMES-1) begin
                        scene_frame <= 0; scene_changed <= 1;
                        if (scene == 9) demo_mode <= 0;
                        else scene <= scene + 1'b1;
                    end else scene_frame <= scene_frame + 1'b1;
                end
            end
        end
    end
endmodule
