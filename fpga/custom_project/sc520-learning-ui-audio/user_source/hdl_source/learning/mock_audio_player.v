// Synthesizable silent player model. No physical pins or actual sound output.
// A command is completed on the PLAY_TICKS-th tick AFTER its handshake.
module mock_audio_player #(
    parameter integer PLAY_TICKS = 120
)(
    input wire clk, input wire rst_n, input wire flush, input wire tick,
    input wire cmd_valid, output wire cmd_ready,
    input wire [3:0] cmd_item, input wire [2:0] cmd_event, input wire [15:0] cmd_tag,
    output reg rsp_valid, output reg [15:0] rsp_tag, output reg rsp_error,
    output reg player_busy
);
    localparam integer PLAY_LIMIT=(PLAY_TICKS<1)?1:PLAY_TICKS;
    function integer bits_for;
        input integer value; integer n;
        begin n=value-1; bits_for=0; while(n>0) begin bits_for=bits_for+1; n=n>>1; end
        if(bits_for<1) bits_for=1; end
    endfunction
    reg [bits_for(PLAY_LIMIT)-1:0] ticks_elapsed;
    reg [15:0] accepted_tag;
    assign cmd_ready=rst_n && !flush && !player_busy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rsp_valid<=0; rsp_tag<=0; rsp_error<=0; player_busy<=0; ticks_elapsed<=0; accepted_tag<=0;
        end else begin
            rsp_valid<=0; rsp_error<=0;
            if(flush) begin
                player_busy<=0; ticks_elapsed<=0; accepted_tag<=0; rsp_tag<=0;
            end else if(!player_busy && cmd_valid) begin
                if(cmd_item>=4'd1 && cmd_item<=4'd9 && (cmd_event==3'd1 || cmd_event==3'd5)) begin
                    accepted_tag<=cmd_tag; ticks_elapsed<=0; player_busy<=1;
                end else begin
                    // Explicit rejection guarantees that this mock did not start.
                    rsp_valid<=1; rsp_tag<=cmd_tag; rsp_error<=1;
                end
            end else if(player_busy && tick) begin
                if(ticks_elapsed>=PLAY_LIMIT-1) begin
                    player_busy<=0; ticks_elapsed<=0; rsp_valid<=1; rsp_tag<=accepted_tag;
                end else ticks_elapsed<=ticks_elapsed+1'b1;
            end
        end
    end
endmodule
