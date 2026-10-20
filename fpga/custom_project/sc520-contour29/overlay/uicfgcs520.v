`timescale 1ns / 1ps

module uicfgcs520 #(
    parameter integer CLK_DIV = 16'd239,
    parameter integer RESET_WAIT_CYCLES = 119048,
    parameter integer TRANSACTION_TIMEOUT_CYCLES = 238096
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_ae_req,
    input  wire [15:0] I_ae,
    input  wire [15:0] I_ag,
    output wire        O_cam_scl,
    inout  wire        IO_cam_sda,
    output reg         O_cfg_done,
    output reg         O_ae_cfg_done,
    output reg  [15:0] O_sensor_id,
    output reg         O_sensor_id_ok,
    output reg         O_iic_error,
    output wire [31:0] O_iic_diagnostic
);
    localparam [7:0] CAM_ID = 8'h6c;
    localparam [3:0] PH_IDH = 4'd1, PH_IDL = 4'd2, PH_INIT = 4'd3, PH_AE = 4'd4;
    localparam [3:0] ST_SETUP = 4'd0, ST_REQUEST = 4'd1, ST_WAIT_BUSY = 4'd2,
        ST_WAIT_DONE = 4'd3, ST_SETTLE = 4'd4, ST_FINISH = 4'd5,
        ST_CHECK_ID = 4'd6, ST_IDLE = 4'd7, ST_RETRY_WAIT = 4'd8,
        ST_RESET_WAIT = 4'd9, ST_ERROR = 4'd10;
    localparam integer WAIT_WIDTH = RESET_WAIT_CYCLES > 1 ? $clog2(RESET_WAIT_CYCLES) : 1;
    localparam integer AGE_WIDTH = TRANSACTION_TIMEOUT_CYCLES > 1 ?
        $clog2(TRANSACTION_TIMEOUT_CYCLES) : 1;

    reg [3:0] state,phase,attempt;
    reg iic_req,iic_mode,ae_table_active,transaction_error;
    reg [7:0] wr_cnt,rd_cnt;
    reg [31:0] wr_data;
    reg [8:0] reg_index;
    reg [15:0] ae_snapshot,ag_snapshot,transaction_reg;
    reg [WAIT_WIDTH-1:0] wait_count;
    reg [AGE_WIDTH-1:0] transaction_age;
    reg [1:0] settle_count;
    wire iic_busy,iic_bus_error;
    wire [7:0] rd_data;
    (* keep = "true", async_reg = "true" *) reg busy_meta,busy_sync,error_meta,error_sync;
    reg [7:0] failure_count;
    reg [3:0] last_failure_phase,last_failure_attempt;
    reg [15:0] last_failure_reg;

    wire [23:0] init_reg_data,ae_reg_data,gain_value;
    wire [8:0] init_reg_size,ae_reg_size;
    wire [23:0] selected_reg_data = ae_table_active ? ae_reg_data : init_reg_data;
    wire transaction_active = state == ST_WAIT_BUSY || state == ST_WAIT_DONE ||
        state == ST_SETTLE || state == ST_FINISH;
    assign O_iic_diagnostic = {failure_count,last_failure_phase,last_failure_attempt,last_failure_reg};

    // Vendor status is generated on opposite edges of its divided SCL clock.
    // Keep a transaction-local error until busy has ended and both chains settle.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            busy_meta <= 0; busy_sync <= 0; error_meta <= 0; error_sync <= 0;
        end else begin
            busy_meta <= iic_busy; busy_sync <= busy_meta;
            error_meta <= iic_bus_error; error_sync <= error_meta;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state <= ST_SETUP; phase <= PH_IDH; attempt <= 1;
            iic_req <= 0; iic_mode <= 1; ae_table_active <= 0; transaction_error <= 0;
            wr_cnt <= 3; rd_cnt <= 1; wr_data <= 0; reg_index <= 0;
            ae_snapshot <= 0; ag_snapshot <= 0; transaction_reg <= 0;
            wait_count <= 0; transaction_age <= 0; settle_count <= 0;
            O_cfg_done <= 0; O_ae_cfg_done <= 0; O_sensor_id <= 0;
            O_sensor_id_ok <= 0; O_iic_error <= 0;
            failure_count <= 0; last_failure_phase <= 0;
            last_failure_attempt <= 0; last_failure_reg <= 0;
        end else begin
            if (transaction_active && error_sync) begin
                transaction_error <= 1;
                O_iic_error <= 1;
            end
            if (transaction_active)
                transaction_age <= transaction_age + 1'b1;

            if (transaction_active && transaction_age >= TRANSACTION_TIMEOUT_CYCLES - 1) begin
                iic_req <= 0;
                O_cfg_done <= 0; O_ae_cfg_done <= 0; O_iic_error <= 1;
                if (failure_count != 8'hff) failure_count <= failure_count + 1'b1;
                last_failure_phase <= 4'd6;
                last_failure_attempt <= attempt;
                last_failure_reg <= transaction_reg;
                state <= ST_ERROR;
            end else begin
                case (state)
                    ST_SETUP: begin
                        iic_req <= 0;
                        transaction_error <= 0;
                        if (phase == PH_IDH || phase == PH_IDL) begin
                            transaction_reg <= phase == PH_IDH ? 16'h3107 : 16'h3108;
                            wr_data <= phase == PH_IDH ? {8'h00,8'h07,8'h31,CAM_ID} :
                                {8'h00,8'h08,8'h31,CAM_ID};
                            wr_cnt <= 3; rd_cnt <= 1; iic_mode <= 1;
                        end else begin
                            transaction_reg <= selected_reg_data[23:8];
                            wr_data <= {selected_reg_data[7:0],selected_reg_data[15:8],
                                selected_reg_data[23:16],CAM_ID};
                            wr_cnt <= 4; rd_cnt <= 0; iic_mode <= 0;
                        end
                        state <= ST_REQUEST;
                    end
                    ST_REQUEST: begin
                        iic_req <= 1;
                        transaction_age <= 0;
                        state <= ST_WAIT_BUSY;
                    end
                    ST_WAIT_BUSY: if (busy_sync) begin
                        iic_req <= 0;
                        state <= ST_WAIT_DONE;
                    end
                    ST_WAIT_DONE: if (!busy_sync) begin
                        settle_count <= 0;
                        state <= ST_SETTLE;
                    end
                    ST_SETTLE: begin
                        if (busy_sync) begin
                            settle_count <= 0;
                            state <= ST_WAIT_DONE;
                        end else if (settle_count == 2) begin
                            state <= ST_FINISH;
                        end else begin
                            settle_count <= settle_count + 1'b1;
                        end
                    end
                    ST_FINISH: begin
                        // Include the live synchronized error in this decision:
                        // a same-cycle first error is not yet in the sticky FF.
                        if (transaction_error || error_sync) begin
                            O_iic_error <= 1;
                            if (failure_count != 8'hff) failure_count <= failure_count + 1'b1;
                            last_failure_phase <= phase;
                            last_failure_attempt <= attempt;
                            last_failure_reg <= transaction_reg;
                            if (attempt < 3) begin
                                attempt <= attempt + 1'b1;
                                wait_count <= 0;
                                state <= ST_RETRY_WAIT;
                            end else begin
                                O_cfg_done <= 0; O_ae_cfg_done <= 0;
                                state <= ST_ERROR;
                            end
                        end else begin
                            case (phase)
                                PH_IDH: begin
                                    O_sensor_id[15:8] <= rd_data;
                                    phase <= PH_IDL; attempt <= 1; state <= ST_SETUP;
                                end
                                PH_IDL: begin
                                    O_sensor_id[7:0] <= rd_data;
                                    state <= ST_CHECK_ID;
                                end
                                PH_INIT,PH_AE: begin
                                    reg_index <= reg_index + 1'b1;
                                    attempt <= 1;
                                    if (phase == PH_INIT && reg_index == 0) begin
                                        wait_count <= 0;
                                        state <= ST_RESET_WAIT;
                                    end else begin
                                        state <= ST_IDLE;
                                    end
                                end
                                default: begin
                                    O_cfg_done <= 0; O_ae_cfg_done <= 0; O_iic_error <= 1;
                                    state <= ST_ERROR;
                                end
                            endcase
                        end
                    end
                    ST_CHECK_ID: begin
                        if (O_sensor_id == 16'hee4b || O_sensor_id == 16'h9e4b) begin
                            O_sensor_id_ok <= 1;
                            reg_index <= 0; ae_table_active <= 0;
                            phase <= PH_INIT; attempt <= 1; state <= ST_IDLE;
                        end else begin
                            O_iic_error <= 1;
                            O_cfg_done <= 0; O_ae_cfg_done <= 0;
                            if (failure_count != 8'hff) failure_count <= failure_count + 1'b1;
                            last_failure_phase <= 4'd5;
                            last_failure_attempt <= attempt;
                            last_failure_reg <= transaction_reg;
                            state <= ST_ERROR;
                        end
                    end
                    ST_IDLE: begin
                        if (!O_cfg_done) begin
                            if (reg_index == init_reg_size) begin
                                O_cfg_done <= 1; O_ae_cfg_done <= 1; O_iic_error <= 0;
                            end else begin
                                phase <= PH_INIT;
                                state <= ST_SETUP;
                            end
                        end else if (ae_table_active) begin
                            if (reg_index == ae_reg_size) begin
                                ae_table_active <= 0;
                                O_ae_cfg_done <= 1; O_iic_error <= 0;
                            end else begin
                                phase <= PH_AE;
                                state <= ST_SETUP;
                            end
                        end else if (I_ae_req) begin
                            ae_snapshot <= I_ae; ag_snapshot <= I_ag;
                            ae_table_active <= 1; O_ae_cfg_done <= 0;
                            reg_index <= 0; phase <= PH_AE; attempt <= 1;
                        end
                    end
                    ST_RETRY_WAIT,ST_RESET_WAIT: begin
                        if (wait_count >= RESET_WAIT_CYCLES - 1) begin
                            state <= state == ST_RETRY_WAIT ? ST_SETUP : ST_IDLE;
                        end else begin
                            wait_count <= wait_count + 1'b1;
                        end
                    end
                    ST_ERROR: begin
                        iic_req <= 0;
                        O_cfg_done <= 0; O_ae_cfg_done <= 0; O_iic_error <= 1;
                    end
                    default: begin
                        iic_req <= 0;
                        O_cfg_done <= 0; O_ae_cfg_done <= 0; O_iic_error <= 1;
                        state <= ST_ERROR;
                    end
                endcase
            end
        end
    end

    uii2c #(.WMEN_LEN(4),.RMEN_LEN(1),.CLK_DIV(CLK_DIV)) u_i2c (
        .I_clk(I_clk),.I_rstn(I_rst_n),.O_iic_scl(O_cam_scl),.IO_iic_sda(IO_cam_sda),
        .I_wr_data(wr_data),.I_wr_cnt(wr_cnt),.O_rd_data(rd_data),.I_rd_cnt(rd_cnt),
        .I_iic_req(iic_req),.I_iic_mode(iic_mode),.O_iic_busy(iic_busy),
        .O_iic_bus_error(iic_bus_error),.IO_iic_sda_dg()
    );
    uics520reg_720p60 u_init_regs (
        .REG_INDEX(reg_index),.REG_DATA(init_reg_data),.REG_SIZE(init_reg_size)
    );
    SC520GainTbl u_gain (.I_AG(ag_snapshot),.O(gain_value));
    uics520regAE u_ae_regs (
        .REG_INDEX(reg_index),.REG_DATA(ae_reg_data),.REG_SIZE(ae_reg_size),
        .I_AE(ae_snapshot),.I_AG(gain_value)
    );

    // synthesis translate_off
    initial if (CLK_DIV < 3 || RESET_WAIT_CYCLES < 1 || TRANSACTION_TIMEOUT_CYCLES < 8)
        $fatal(1,"uicfgcs520 invalid timing parameters");
    // synthesis translate_on
endmodule
