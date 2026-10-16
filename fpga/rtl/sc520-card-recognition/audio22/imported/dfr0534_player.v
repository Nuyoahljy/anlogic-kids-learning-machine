`timescale 1ns/1ps
// Independent peripheral, intentionally not bound to the old video top/pins.
// Set all three verification flags only after testing the actual module and
// loading an explicit TRACKS table. The zero/default build never sends bytes.
module dfr0534_player #(
    parameter integer CLK_HZ=75000000, BAUD=9600, MAX_DATA=16,
    parameter integer RX_GAP_CYCLES=CLK_HZ/20,
    parameter [35*16-1:0] TRACKS=0,
    parameter integer MAP_VERIFIED=0, STATUS_VERIFIED=0, MODE_VERIFIED=0,
    parameter [7:0] STOPPED_STATUS=8'h00, PLAYING_STATUS=8'h01,
    parameter [7:0] SINGLE_STOP_MODE=8'h02,
    parameter integer VOLUME=20, BOOT_TICKS=2000, INIT_TICKS=6000,
    parameter integer QUERY_TICKS=100, RESPONSE_TICKS=250,
    parameter integer QUIET_TICKS=50, BUSY_FILTER_TICKS=5,
    parameter integer START_TICKS=3000, PLAY_TICKS=20000, STOP_TICKS=1000
)(
    input wire clk, rst_n, tick_1ms,
    input wire uart_rx, busy_async, output wire uart_tx,
    input wire req_valid, input wire [2:0] req_kind,
    input wire [3:0] req_item, input wire [15:0] req_tag,
    output wire req_ready, device_busy,
    input wire stop_valid, input wire [15:0] stop_tag,
    output wire rsp_valid, output wire [15:0] rsp_tag,
    output wire [1:0] rsp_code,
    output wire initialized, fault
);
    wire map_hit;
    wire [15:0] logical_id, physical_track;
    wire cmd_valid, cmd_ready, tx_done, tx_error;
    wire [7:0] cmd, cmd_len, rx_cmd, rx_len;
    wire [MAX_DATA*8-1:0] cmd_data, rx_data;
    wire rx_valid, rx_error, rx_activity, rx_frame_start, flush_rx;
    dfr0534_track_map #(.TRACKS(TRACKS)) mapping(
        .req_kind(req_kind),.req_item(req_item),.logical_id(logical_id),
        .physical_track(physical_track),.map_hit(map_hit));
    dfr0534_link #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.MAX_DATA(MAX_DATA),
                  .RX_GAP_CYCLES(RX_GAP_CYCLES)) link(
        .clk(clk),.rst_n(rst_n),.uart_rx(uart_rx),.uart_tx(uart_tx),
        .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd(cmd),
        .cmd_len(cmd_len),.cmd_data(cmd_data),.tx_done(tx_done),.tx_error(tx_error),
        .flush_rx(flush_rx),.rx_valid(rx_valid),.rx_error(rx_error),
        .rx_activity(rx_activity),.rx_frame_start(rx_frame_start),
        .rx_cmd(rx_cmd),.rx_len(rx_len),.rx_data(rx_data));
    dfr0534_player_core #(.MAX_DATA(MAX_DATA),.MAP_VERIFIED(MAP_VERIFIED),
        .STATUS_VERIFIED(STATUS_VERIFIED),.MODE_VERIFIED(MODE_VERIFIED),
        .STOPPED_STATUS(STOPPED_STATUS),.PLAYING_STATUS(PLAYING_STATUS),
        .SINGLE_STOP_MODE(SINGLE_STOP_MODE),.VOLUME(VOLUME),
        .BOOT_TICKS(BOOT_TICKS),.INIT_TICKS(INIT_TICKS),.QUERY_TICKS(QUERY_TICKS),
        .RESPONSE_TICKS(RESPONSE_TICKS),.QUIET_TICKS(QUIET_TICKS),
        .BUSY_FILTER_TICKS(BUSY_FILTER_TICKS),.START_TICKS(START_TICKS),
        .PLAY_TICKS(PLAY_TICKS),.STOP_TICKS(STOP_TICKS)) core(
        .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),.busy_async(busy_async),
        .req_valid(req_valid),.req_kind(req_kind),.req_item(req_item),.req_tag(req_tag),
        .req_ready(req_ready),.device_busy(device_busy),
        .stop_valid(stop_valid),.stop_tag(stop_tag),
        .rsp_valid(rsp_valid),.rsp_tag(rsp_tag),.rsp_code(rsp_code),
        .map_hit(map_hit),.physical_track(physical_track),
        .initialized(initialized),.fault(fault),
        .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd(cmd),.cmd_len(cmd_len),
        .cmd_data(cmd_data),.tx_done(tx_done),.tx_error(tx_error),
        .rx_valid(rx_valid),.rx_error(rx_error),.rx_activity(rx_activity),
        .rx_frame_start(rx_frame_start),.rx_cmd(rx_cmd),.rx_len(rx_len),
        .rx_data(rx_data),.flush_rx(flush_rx));
endmodule
