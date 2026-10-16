`timescale 1ns/1ps
// T020 task-local bridge for the c74a430 items14_* audio event ports.
// No physical track table or verified hardware profile is supplied by default.
// K4/context cancel must NOT reset this bridge: uncertainty is sticky until a
// common reset followed by the player's startup STOP and fresh status exchange.
module dfr0534_items14_audio #(
    parameter integer CLK_HZ=75000000, BAUD=9600,
    parameter [35*16-1:0] TRACKS=0,
    parameter integer MAP_VERIFIED=0, STATUS_VERIFIED=0, MODE_VERIFIED=0,
    parameter integer VOLUME=8, DEPTH=8,
    parameter integer BOOT_TICKS=2000, INIT_TICKS=6000,
    parameter integer QUERY_TICKS=100, RESPONSE_TICKS=250,
    parameter integer QUIET_TICKS=50, BUSY_FILTER_TICKS=5,
    parameter integer START_TICKS=3000, PLAY_TICKS=20000, STOP_TICKS=1000,
    // Queue watchdog covers the entire accepted transaction, including start.
    // STOP margin lets the player finish its own bounded protocol handling.
    parameter integer QUEUE_WAIT_TICKS=INIT_TICKS+1000,
    parameter integer QUEUE_PLAY_TICKS=START_TICKS+PLAY_TICKS+1000,
    parameter integer QUEUE_STOP_TICKS=STOP_TICKS+1000
)(
    input wire clk,rst_n,tick_1ms,
    input wire audio_event_valid,audio_cancel,
    input wire [2:0] audio_event_kind,
    input wire [3:0] audio_event_item,
    input wire uart_rx,busy_async,
    output wire uart_tx,audio_idle,audio_fault,
    output wire initialized,queue_overflow
);
    localparam integer ENABLED=MAP_VERIFIED && STATUS_VERIFIED && MODE_VERIFIED;
    reg service_started;
    wire queue_idle,queue_fault,player_fault;
    wire req_valid,req_ready,device_busy,stop_valid,rsp_valid;
    wire [2:0] req_kind;
    wire [3:0] req_item;
    wire [15:0] req_tag,stop_tag,rsp_tag;
    wire [1:0] rsp_code;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) service_started<=0;
        else if(initialized || player_fault) service_started<=1;

    // A disabled/unqualified profile is visible to business logic as unavailable.
    // idle allows UI progress on fault; it never certifies physical silence.
    assign audio_fault=!ENABLED || queue_fault || player_fault;
    assign audio_idle=audio_fault || (initialized && queue_idle);
    t020_audio_queue #(.DEPTH(DEPTH),.WAIT_TICKS(QUEUE_WAIT_TICKS),
        .PLAY_TICKS(QUEUE_PLAY_TICKS),.STOP_TICKS(QUEUE_STOP_TICKS)) queue(
        .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms && service_started),
        .cancel(audio_cancel || player_fault),
        .event_valid(audio_event_valid && ENABLED && !player_fault),
        .event_kind(audio_event_kind),.event_item(audio_event_item),
        .idle(queue_idle),.fault(queue_fault),.overflow(queue_overflow),
        .req_valid(req_valid),.req_kind(req_kind),.req_item(req_item),.req_tag(req_tag),
        .req_ready(req_ready),.device_busy(device_busy),
        .rsp_valid(rsp_valid),.rsp_tag(rsp_tag),.rsp_code(rsp_code),
        .stop_valid(stop_valid),.stop_tag(stop_tag));
    dfr0534_player #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.TRACKS(TRACKS),
        .MAP_VERIFIED(MAP_VERIFIED),.STATUS_VERIFIED(STATUS_VERIFIED),.MODE_VERIFIED(MODE_VERIFIED),
        .STOPPED_STATUS(8'h00),.PLAYING_STATUS(8'h01),.SINGLE_STOP_MODE(8'h02),
        .VOLUME(VOLUME),.BOOT_TICKS(BOOT_TICKS),.INIT_TICKS(INIT_TICKS),
        .QUERY_TICKS(QUERY_TICKS),.RESPONSE_TICKS(RESPONSE_TICKS),
        .QUIET_TICKS(QUIET_TICKS),.BUSY_FILTER_TICKS(BUSY_FILTER_TICKS),
        .START_TICKS(START_TICKS),.PLAY_TICKS(PLAY_TICKS),.STOP_TICKS(STOP_TICKS)) player(
        .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),
        .uart_rx(uart_rx),.busy_async(busy_async),.uart_tx(uart_tx),
        .req_valid(req_valid),.req_kind(req_kind),.req_item(req_item),.req_tag(req_tag),
        .req_ready(req_ready),.device_busy(device_busy),.stop_valid(stop_valid),.stop_tag(stop_tag),
        .rsp_valid(rsp_valid),.rsp_tag(rsp_tag),.rsp_code(rsp_code),
        .initialized(initialized),.fault(player_fault));
    // synthesis translate_off
    initial begin
        if(QUEUE_WAIT_TICKS<=INIT_TICKS || QUEUE_PLAY_TICKS<=START_TICKS+PLAY_TICKS ||
           QUEUE_STOP_TICKS<=STOP_TICKS)
            $fatal(1,"T020 queue deadlines must enclose player deadlines");
    end
    // synthesis translate_on
endmodule
