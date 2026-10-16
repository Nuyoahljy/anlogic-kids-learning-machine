// T022 current-pipeline adapter. Hardware defaults never enable playback.
// reset_n must be the SAME asynchronous source used by pixel14_pipeline.
// Both release after two HDMI clock edges. Keys only drive audio_cancel.
module pixel22_audio #(
    parameter integer CLK_HZ=75000000,BAUD=9600,
    parameter [559:0] TRACKS=0,
    parameter integer MAP_VERIFIED=0,STATUS_VERIFIED=0,MODE_VERIFIED=0,
    parameter integer DEPTH=8,BOOT_TICKS=2000,INIT_TICKS=6000,
    parameter integer QUERY_TICKS=100,RESPONSE_TICKS=250,QUIET_TICKS=50,BUSY_FILTER_TICKS=5,
    parameter integer START_TICKS=3000,PLAY_TICKS=20000,STOP_TICKS=1000
)(
    input wire clk,reset_n,tick_1ms,
    input wire audio_event_valid,audio_cancel,
    input wire [2:0] audio_event_kind,input wire [3:0] audio_event_item,
    input wire uart_rx,busy_async,
    output wire uart_tx,audio_idle,audio_fault,initialized,queue_overflow,
    output wire reset_released,output wire [2:0] audio_state
);
    (* async_reg="true",keep="true" *) reg [1:0] reset_pipe;
    always @(posedge clk or negedge reset_n)
        if(!reset_n)reset_pipe<=0;else reset_pipe<={reset_pipe[0],1'b1};
    assign reset_released=reset_pipe[1];
    localparam integer CONFIGURED=MAP_VERIFIED && STATUS_VERIFIED && MODE_VERIFIED;
    // 0 unavailable, 1 initializing, 2 ready, 3 pending/playing, 4 fault.
    // fault-idle means business can progress, never that sound has stopped.
    assign audio_state=!CONFIGURED ? 3'd0:audio_fault ? 3'd4:
                       !initialized ? 3'd1:audio_idle ? 3'd2:3'd3;
    dfr0534_items14_audio #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.TRACKS(TRACKS),
        .MAP_VERIFIED(MAP_VERIFIED),.STATUS_VERIFIED(STATUS_VERIFIED),.MODE_VERIFIED(MODE_VERIFIED),
        .DEPTH(DEPTH),.BOOT_TICKS(BOOT_TICKS),.INIT_TICKS(INIT_TICKS),.QUERY_TICKS(QUERY_TICKS),
        .RESPONSE_TICKS(RESPONSE_TICKS),.QUIET_TICKS(QUIET_TICKS),.BUSY_FILTER_TICKS(BUSY_FILTER_TICKS),
        .START_TICKS(START_TICKS),.PLAY_TICKS(PLAY_TICKS),.STOP_TICKS(STOP_TICKS)) bridge(
        .clk(clk),.rst_n(reset_released),.tick_1ms(tick_1ms),.audio_event_valid(audio_event_valid),
        .audio_event_kind(audio_event_kind),.audio_event_item(audio_event_item),.audio_cancel(audio_cancel),
        .uart_rx(uart_rx),.busy_async(busy_async),.uart_tx(uart_tx),.audio_idle(audio_idle),
        .audio_fault(audio_fault),.initialized(initialized),.queue_overflow(queue_overflow));
endmodule
