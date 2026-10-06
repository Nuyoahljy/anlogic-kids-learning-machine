`timescale 1ns/1ps
// Local, unbound key input. Board polarity and pins belong in a future wrapper.
// A held key after reset is treated as a new press after full qualification.
module quiz_key_debounce #(
    parameter integer CLOCK_HZ = 50000000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer DEBOUNCE_CYCLES = (CLOCK_HZ / 1000) * DEBOUNCE_MS
        + ((CLOCK_HZ % 1000) * DEBOUNCE_MS + 999) / 1000
) (
    input wire clk,
    input wire rst_n,
    input wire key_async,
    output reg key_level,
    output reg key_pulse
);
    localparam integer QUALIFY_CYCLES = (DEBOUNCE_CYCLES < 1) ? 1 : DEBOUNCE_CYCLES;
    localparam integer COUNT_WIDTH = (QUALIFY_CYCLES < 2) ? 1 : $clog2(QUALIFY_CYCLES);
    // Synthesis placement/CDC constraints must be supplied by the final wrapper.
    (* async_reg = "true" *) reg key_meta;
    (* async_reg = "true" *) reg key_sync;
    reg [COUNT_WIDTH-1:0] stable_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 1'b0;
            key_sync <= 1'b0;
        end else begin
            key_meta <= key_async;
            key_sync <= key_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_level <= 1'b0;
            key_pulse <= 1'b0;
            stable_count <= {COUNT_WIDTH{1'b0}};
        end else begin
            key_pulse <= 1'b0;
            if (key_sync == key_level) begin
                stable_count <= {COUNT_WIDTH{1'b0}};
            end else if (stable_count == QUALIFY_CYCLES - 1) begin
                key_level <= key_sync;
                key_pulse <= key_sync;
                stable_count <= {COUNT_WIDTH{1'b0}};
            end else begin
                stable_count <= stable_count + 1'b1;
            end
        end
    end
endmodule
