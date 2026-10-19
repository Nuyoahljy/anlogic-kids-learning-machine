// Task-local I2C master, derived from MiLianKe uii2c revision1.1 (2022).
// The vendor original remains unchanged in sc520-fixed-roi. The reference
// implementation is supplied for learning without a guarantee of correctness.
// T-018: all state now uses I_clk. Rise/fall are clock enables, not clocks.
// Requests may be accepted one bus period later than the old delta-cycle
// derived-clock simulation when req changes on the phase edge. Payload is
// captured once and held for the entire write/repeated-start/read operation.
module uii2c #(
    parameter integer WMEN_LEN=4,RMEN_LEN=1,CLK_DIV=239
) (
    input wire I_clk,I_rstn,
    output reg O_iic_scl,
    inout wire IO_iic_sda,
    input wire [WMEN_LEN*8-1:0] I_wr_data,
    input wire [7:0] I_wr_cnt,I_rd_cnt,
    output reg [RMEN_LEN*8-1:0] O_rd_data,
    input wire I_iic_req,I_iic_mode,
    output reg O_iic_busy,O_iic_bus_error,
    output wire IO_iic_sda_dg
);
    localparam integer HALF=CLK_DIV/2+1;
    localparam integer OFFSET=(HALF-1)-(HALF-1)/4;
    localparam integer CW=$clog2(HALF);
    localparam [2:0] IDLE=0,START=1,W_WAIT=2,W_ACK=3,R_WAIT=4,R_ACK=5,STOP1=6,STOP2=7;
    (* keep="true",async_reg="true" *) reg [1:0] reset_pipe=0;
    always @(posedge I_clk or negedge I_rstn)
        if(!I_rstn)reset_pipe<=0;else reset_pipe<={reset_pipe[0],1'b1};
    wire core_rstn=reset_pipe[1];
    (* keep="true",async_reg="true" *) reg sda_meta,sda_sync;
    always @(posedge I_clk or negedge core_rstn)
        if(!core_rstn)begin sda_meta<=1;sda_sync<=1;end
        else begin sda_meta<=IO_iic_sda;sda_sync<=sda_meta;end
    assign IO_iic_sda_dg=sda_sync;

    reg [CW-1:0] clkdiv;
    reg phase_high;
    wire phase_tick=clkdiv==HALF-1;
    wire rise_enable=phase_tick && !phase_high;
    wire fall_enable=phase_tick && phase_high;
    reg [2:0] state;
    reg [7:0] tx_byte,rx_byte,wcnt,rcnt;
    reg [2:0] bcnt;
    reg rd_req;
    reg [WMEN_LEN*8-1:0] transaction_data;
    reg [7:0] transaction_writes,transaction_reads;
    reg transaction_mode;
    wire scl_level=(state==IDLE || state==STOP1 || state==STOP2) ? 1'b1:phase_high;
    wire drive_low=state==START || state==STOP1 ||
        (state==R_ACK && rcnt!=transaction_reads) || (state==W_WAIT && !tx_byte[7]);
    assign IO_iic_sda=drive_low ? 1'b0:1'bz;

    always @(posedge I_clk or negedge core_rstn)begin
        if(!core_rstn)begin
            clkdiv<=0;phase_high<=0;O_iic_scl<=1;
            state<=IDLE;tx_byte<=8'hff;rx_byte<=0;wcnt<=0;rcnt<=0;bcnt<=0;rd_req<=0;
            transaction_data<=0;transaction_writes<=0;transaction_reads<=0;transaction_mode<=0;
            O_rd_data<=0;O_iic_busy<=0;O_iic_bus_error<=0;
        end else begin
            if(phase_tick)begin clkdiv<=0;phase_high<=!phase_high;end
            else clkdiv<=clkdiv+1'b1;
            if(clkdiv==OFFSET)O_iic_scl<=scl_level;
            if(fall_enable)begin
                if(state==R_WAIT)rx_byte<={rx_byte[6:0],sda_sync};
                else if(state==R_ACK && rcnt>0 && rcnt<=RMEN_LEN)
                    O_rd_data[(rcnt-1)*8+:8]<=rx_byte;
                else if(state==IDLE)rx_byte<=0;
                if(state==W_ACK && sda_sync)O_iic_bus_error<=1;
                else if(!I_iic_req)O_iic_bus_error<=0;
            end
            if(rise_enable)begin
                if(I_iic_req || rd_req || O_iic_bus_error)O_iic_busy<=1;
                else if(state==IDLE)O_iic_busy<=0;
                if(state==START || state==W_ACK)begin
                    tx_byte<=wcnt<WMEN_LEN ? transaction_data[wcnt*8+:8]:8'hff;
                    if(rd_req)tx_byte<={transaction_data[7:1],1'b1};
                end else if(state==W_WAIT)tx_byte<={tx_byte[6:0],1'b1};
                case(state)
                    IDLE:begin
                        if(I_iic_req || rd_req)begin
                            state<=START;
                            if(!rd_req)begin
                                transaction_data<=I_wr_data;transaction_writes<=I_wr_cnt;
                                transaction_reads<=I_rd_cnt;transaction_mode<=I_iic_mode;
                            end
                        end else begin wcnt<=0;rcnt<=0;end
                    end
                    START:begin bcnt<=7;state<=W_WAIT;end
                    W_WAIT:begin
                        if(bcnt!=0)bcnt<=bcnt-1'b1;
                        else begin wcnt<=wcnt+1'b1;state<=W_ACK;end
                    end
                    W_ACK:begin
                        if(wcnt<transaction_writes)begin bcnt<=7;state<=W_WAIT;end
                        else if(transaction_reads!=0)begin
                            if(!rd_req && transaction_mode)begin rd_req<=1;state<=IDLE;end
                            else state<=R_WAIT;
                            bcnt<=7;
                        end else state<=STOP1;
                    end
                    R_WAIT:begin
                        rd_req<=0;bcnt<=bcnt-1'b1;
                        if(bcnt==0)begin
                            rcnt<=rcnt<transaction_reads ? rcnt+1'b1:rcnt;
                            state<=R_ACK;
                        end
                    end
                    R_ACK:begin bcnt<=7;state<=rcnt<transaction_reads ? R_WAIT:STOP1;end
                    STOP1:begin rd_req<=0;state<=STOP2;end
                    STOP2:state<=IDLE;
                    default:begin state<=IDLE;O_iic_bus_error<=1;end
                endcase
            end
        end
    end
    // synthesis translate_off
    initial if(WMEN_LEN<1 || RMEN_LEN<1 || CLK_DIV<7 || CLK_DIV>65535)
        $fatal(1,"uii2c invalid dimensions/divider");
    // synthesis translate_on
endmodule
