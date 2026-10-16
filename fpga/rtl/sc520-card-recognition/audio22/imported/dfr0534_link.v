// DFR0534 UART transport. This module does not infer playback or stop status.
// Frame: AA CMD LEN DATA[0..LEN-1] SUM8; SUM8 includes AA, CMD, LEN and DATA.
// cmd_data[7:0] is sent first. Invalid lengths are consumed with tx_error.
module dfr0534_link #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 9600,
    parameter integer MAX_DATA = 16,
    parameter integer RX_GAP_CYCLES = CLK_HZ / 20
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    uart_rx,
    output wire                    uart_tx,
    input  wire                    cmd_valid,
    output wire                    cmd_ready,
    input  wire [7:0]              cmd,
    input  wire [7:0]              cmd_len,
    input  wire [MAX_DATA*8-1:0]    cmd_data,
    output reg                     tx_done,
    output reg                     tx_error,
    input  wire                    flush_rx,
    output reg                     rx_valid,
    output reg                     rx_error,
    output reg                     rx_activity,
    output reg                     rx_frame_start,
    output reg  [7:0]              rx_cmd,
    output reg  [7:0]              rx_len,
    output reg  [MAX_DATA*8-1:0]    rx_data
);

    function integer bits_for;
        input integer value;
        integer rest;
        begin
            bits_for = 1;
            rest = value - 1;
            while (rest > 1) begin
                bits_for = bits_for + 1;
                rest = rest >> 1;
            end
        end
    endfunction

    localparam integer SAFE_BAUD = (BAUD > 0) ? BAUD : 1;
    localparam integer BIT_CYCLES = (CLK_HZ + SAFE_BAUD/2) / SAFE_BAUD;
    localparam integer HALF_CYCLES = BIT_CYCLES / 2;
    localparam integer BAUD_BITS = bits_for(BIT_CYCLES);
    localparam integer GAP_BITS = bits_for(RX_GAP_CYCLES);

    // synthesis translate_off
    initial begin
        if ((CLK_HZ <= 0) || (BAUD <= 0) || (BIT_CYCLES < 8) ||
            (MAX_DATA < 1) || (MAX_DATA > 255) || (RX_GAP_CYCLES < 1)) begin
            $display("DFR0534_LINK_BAD_PARAMETER");
            $finish;
        end
    end
    // synthesis translate_on

    reg tx_active;
    reg [9:0] tx_shift;
    reg [3:0] tx_bit;
    reg [8:0] tx_index;
    reg [BAUD_BITS-1:0] tx_count;
    reg [7:0] tx_cmd_hold;
    reg [7:0] tx_len_hold;
    reg [MAX_DATA*8-1:0] tx_data_hold;
    reg [7:0] tx_sum;
    reg [7:0] tx_next_byte;

    assign cmd_ready = rst_n && !tx_active;
    assign uart_tx = tx_active ? tx_shift[0] : 1'b1;

    always @* begin
        if (tx_index == 9'd0)
            tx_next_byte = tx_cmd_hold;
        else if (tx_index == 9'd1)
            tx_next_byte = tx_len_hold;
        else if (tx_index < ({1'b0, tx_len_hold} + 9'd2))
            tx_next_byte = tx_data_hold[7:0];
        else
            tx_next_byte = tx_sum;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_active <= 1'b0;
            tx_shift <= 10'h3ff;
            tx_bit <= 4'd0;
            tx_index <= 9'd0;
            tx_count <= {BAUD_BITS{1'b0}};
            tx_cmd_hold <= 8'd0;
            tx_len_hold <= 8'd0;
            tx_data_hold <= {MAX_DATA*8{1'b0}};
            tx_sum <= 8'd0;
            tx_done <= 1'b0;
            tx_error <= 1'b0;
        end else begin
            tx_done <= 1'b0;
            tx_error <= 1'b0;
            if (!tx_active) begin
                if (cmd_valid) begin
                    if (cmd_len > MAX_DATA) begin
                        tx_error <= 1'b1;
                    end else begin
                        tx_active <= 1'b1;
                        tx_shift <= {1'b1, 8'haa, 1'b0};
                        tx_bit <= 4'd0;
                        tx_index <= 9'd0;
                        tx_count <= BIT_CYCLES - 1;
                        tx_cmd_hold <= cmd;
                        tx_len_hold <= cmd_len;
                        tx_data_hold <= cmd_data;
                        tx_sum <= 8'haa;
                    end
                end
            end else if (tx_count != 0) begin
                tx_count <= tx_count - 1'b1;
            end else begin
                tx_count <= BIT_CYCLES - 1;
                if (tx_bit != 4'd9) begin
                    tx_shift <= {1'b1, tx_shift[9:1]};
                    tx_bit <= tx_bit + 1'b1;
                end else if (tx_index == ({1'b0, tx_len_hold} + 9'd3)) begin
                    // This edge is the END of the last full stop bit.
                    tx_active <= 1'b0;
                    tx_done <= 1'b1;
                end else begin
                    tx_shift <= {1'b1, tx_next_byte, 1'b0};
                    tx_bit <= 4'd0;
                    tx_index <= tx_index + 1'b1;
                    if (tx_index < ({1'b0, tx_len_hold} + 9'd2))
                        tx_sum <= tx_sum + tx_next_byte;
                    if ((tx_index >= 9'd2) &&
                        (tx_index < ({1'b0, tx_len_hold} + 9'd2)))
                        tx_data_hold <= tx_data_hold >> 8;
                end
            end
        end
    end

    // Only rx_sync reaches the UART state machine. Placement constraints for
    // this asynchronous input belong to the eventual physical integration.
    (* ASYNC_REG = "TRUE" *) reg rx_meta;
    (* ASYNC_REG = "TRUE" *) reg rx_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= uart_rx;
            rx_sync <= rx_meta;
        end
    end

    localparam [2:0] U_IDLE = 3'd0, U_START = 3'd1, U_DATA = 3'd2,
                     U_STOP = 3'd3, U_RECOVER = 3'd4;
    reg [2:0] uart_state;
    reg [BAUD_BITS-1:0] uart_count;
    reg [2:0] uart_bit;
    reg [7:0] uart_shift;
    reg [7:0] uart_byte;
    reg uart_byte_valid;
    reg uart_byte_error;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_state <= U_IDLE;
            uart_count <= {BAUD_BITS{1'b0}};
            uart_bit <= 3'd0;
            uart_shift <= 8'd0;
            uart_byte <= 8'd0;
            uart_byte_valid <= 1'b0;
            uart_byte_error <= 1'b0;
        end else begin
            uart_byte_valid <= 1'b0;
            uart_byte_error <= 1'b0;
            case (uart_state)
                U_IDLE: begin
                    if (!rx_sync) begin
                        uart_count <= HALF_CYCLES - 1;
                        uart_state <= U_START;
                    end
                end
                U_START: begin
                    if (uart_count != 0)
                        uart_count <= uart_count - 1'b1;
                    else if (!rx_sync) begin
                        uart_count <= BIT_CYCLES - 1;
                        uart_bit <= 3'd0;
                        uart_state <= U_DATA;
                    end else begin
                        // A short low pulse is not an accepted start bit.
                        uart_byte_error <= 1'b1;
                        uart_state <= U_IDLE;
                    end
                end
                U_DATA: begin
                    if (uart_count != 0)
                        uart_count <= uart_count - 1'b1;
                    else begin
                        uart_shift[uart_bit] <= rx_sync;
                        uart_count <= BIT_CYCLES - 1;
                        if (uart_bit == 3'd7)
                            uart_state <= U_STOP;
                        else
                            uart_bit <= uart_bit + 1'b1;
                    end
                end
                U_STOP: begin
                    if (uart_count != 0)
                        uart_count <= uart_count - 1'b1;
                    else if (rx_sync) begin
                        uart_byte <= uart_shift;
                        uart_byte_valid <= 1'b1;
                        uart_state <= U_IDLE;
                    end else begin
                        uart_byte_error <= 1'b1;
                        uart_count <= BIT_CYCLES - 1;
                        uart_state <= U_RECOVER;
                    end
                end
                U_RECOVER: begin
                    // After a break/bad stop, require a complete idle bit.
                    if (!rx_sync)
                        uart_count <= BIT_CYCLES - 1;
                    else if (uart_count != 0)
                        uart_count <= uart_count - 1'b1;
                    else
                        uart_state <= U_IDLE;
                end
                default: uart_state <= U_IDLE;
            endcase
        end
    end

    localparam [2:0] P_HEAD = 3'd0, P_CMD = 3'd1, P_LEN = 3'd2,
                     P_DATA = 3'd3, P_SUM = 3'd4, P_DROP = 3'd5;
    reg [2:0] parse_state;
    reg [GAP_BITS-1:0] gap_count;
    reg [7:0] parse_cmd;
    reg [7:0] parse_len;
    reg [7:0] parse_sum;
    reg [7:0] parse_index;
    reg [8:0] drop_left;
    reg [MAX_DATA*8-1:0] parse_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            parse_state <= P_HEAD;
            gap_count <= {GAP_BITS{1'b0}};
            parse_cmd <= 8'd0;
            parse_len <= 8'd0;
            parse_sum <= 8'd0;
            parse_index <= 8'd0;
            drop_left <= 9'd0;
            parse_data <= {MAX_DATA*8{1'b0}};
            rx_valid <= 1'b0;
            rx_error <= 1'b0;
            rx_activity <= 1'b0;
            rx_frame_start <= 1'b0;
            rx_cmd <= 8'd0;
            rx_len <= 8'd0;
            rx_data <= {MAX_DATA*8{1'b0}};
        end else begin
            rx_valid <= 1'b0;
            rx_error <= uart_byte_error;
            rx_activity <= uart_byte_valid || uart_byte_error;
            rx_frame_start <= 1'b0;
            // Flush discards only parser state. It never resets the UART,
            // suppresses activity, or promotes an incomplete frame to valid.
            if (flush_rx || uart_byte_error) begin
                parse_state <= P_HEAD;
                gap_count <= {GAP_BITS{1'b0}};
                parse_data <= {MAX_DATA*8{1'b0}};
                parse_index <= 8'd0;
                drop_left <= 9'd0;
            end else if (uart_byte_valid) begin
                gap_count <= {GAP_BITS{1'b0}};
                case (parse_state)
                    P_HEAD: begin
                        if (uart_byte == 8'haa) begin
                            parse_sum <= 8'haa;
                            parse_data <= {MAX_DATA*8{1'b0}};
                            parse_index <= 8'd0;
                            parse_state <= P_CMD;
                            rx_frame_start <= 1'b1;
                        end
                    end
                    P_CMD: begin
                        parse_cmd <= uart_byte;
                        parse_sum <= parse_sum + uart_byte;
                        parse_state <= P_LEN;
                    end
                    P_LEN: begin
                        parse_len <= uart_byte;
                        parse_sum <= parse_sum + uart_byte;
                        if (uart_byte > MAX_DATA) begin
                            rx_error <= 1'b1;
                            // Consume the declared data AND checksum. An AA
                            // inside an oversized payload is not a new frame.
                            drop_left <= {1'b0, uart_byte} + 9'd1;
                            parse_state <= P_DROP;
                        end else if (uart_byte == 0)
                            parse_state <= P_SUM;
                        else
                            parse_state <= P_DATA;
                    end
                    P_DATA: begin
                        parse_data[parse_index*8 +: 8] <= uart_byte;
                        parse_sum <= parse_sum + uart_byte;
                        parse_index <= parse_index + 1'b1;
                        if (parse_index == parse_len - 1'b1)
                            parse_state <= P_SUM;
                    end
                    P_SUM: begin
                        if (uart_byte == parse_sum) begin
                            rx_cmd <= parse_cmd;
                            rx_len <= parse_len;
                            rx_data <= parse_data;
                            rx_valid <= 1'b1;
                        end else
                            rx_error <= 1'b1;
                        parse_state <= P_HEAD;
                    end
                    P_DROP: begin
                        if (drop_left == 9'd1) begin
                            drop_left <= 9'd0;
                            parse_state <= P_HEAD;
                        end else
                            drop_left <= drop_left - 1'b1;
                    end
                    default: parse_state <= P_HEAD;
                endcase
            end else if (parse_state != P_HEAD) begin
                // Inter-byte timeout is measured from accepted UART bytes;
                // choose RX_GAP_CYCLES longer than a complete UART character.
                if (gap_count == RX_GAP_CYCLES - 1) begin
                    parse_state <= P_HEAD;
                    gap_count <= {GAP_BITS{1'b0}};
                    rx_error <= 1'b1;
                end else
                    gap_count <= gap_count + 1'b1;
            end else
                gap_count <= {GAP_BITS{1'b0}};
        end
    end
endmodule
