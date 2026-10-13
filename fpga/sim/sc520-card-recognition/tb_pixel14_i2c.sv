`timescale 1ns/1ps
module tb_pixel14_i2c;
    parameter integer CLK_DIV = 23;
    reg clk = 0;
    always #21 clk = !clk;
    reg rst_n = 1;
    reg ae_req = 0;
    reg [15:0] ae_value = 16'h1234, ag_value = 16'd16;
    wire scl;
    tri1 sda;
    reg pull_low = 0;
    assign sda = pull_low ? 1'b0 : 1'bz;
    wire cfg_done, ae_done, id_ok, iic_error;
    wire [15:0] sensor_id;
    wire [31:0] diagnostic;
    uicfgcs520 #(.CLK_DIV(CLK_DIV)
`ifdef I2C_TIMEOUT_PROBE
        ,.TRANSACTION_TIMEOUT_CYCLES(64)
`endif
    ) dut (
        .I_clk(clk), .I_rst_n(rst_n), .I_ae_req(ae_req),
        .I_ae(ae_value), .I_ag(ag_value), .O_cam_scl(scl),
        .IO_cam_sda(sda), .O_cfg_done(cfg_done), .O_ae_cfg_done(ae_done),
        .O_sensor_id(sensor_id), .O_sensor_id_ok(id_ok), .O_iic_error(iic_error)
`ifdef I2C_CANDIDATE
        ,.O_iic_diagnostic(diagnostic)
`endif
    );

    localparam RX = 0, ACK_SETUP = 1, ACK_SAMPLE = 2,
               ACK_RELEASE = 3, TX = 4, MASTER_ACK_SETUP = 5,
               MASTER_ACK_SAMPLE = 6, WAIT_END = 7;
    localparam integer FAULT_OBSERVE_CYCLES = 3 * 119048 + 8 * 64 * (CLK_DIV + 1);
    integer errors = 0, checks = 0, test_done = 0;
    integer mode = 0, expect_recovery = 0, phase = RX;
    integer bit_count = 0, byte_index = 0;
    integer rx_bytes = 0, tx_bytes = 0, ack_count = 0, nack_count = 0;
    integer starts = 0, stops = 0, master_nacks = 0, write_count = 0;
    integer init_writes = 0, ae_writes = 0, injected = 0;
    integer sticky_seen = 0, cycle_count = 0, reset_cycle = 0;
    integer reset_gap_cycles = 0, accepted_writes = 0, log_fd;
    integer expected_cursor = 0;
    integer checker_negative = 0, nack_cycle = 0, retry_gap_cycles = 0;
    integer errors_while_incomplete = 0, premature_clear = 0;
    integer fault_stop_cycle = 0;
    reg active = 0, selected = 0, reading = 0, reject_segment = 0;
    reg want_ack = 0, pending_write = 0, ae_table_seen = 0;
    reg [7:0] shift = 0, tx_value = 0, pending_value = 0;
    reg [15:0] reg_addr = 0;
    reg [23:0] expected_init [0:164];
    reg [23:0] expected_ae [0:7];
    reg [23:0] expected_value;

    task check(input bit ok, input string label);
        checks = checks + 1;
        if (!ok) begin
            errors = errors + 1;
            $display("I2C_CHECK_FAIL t=%0t %s", $time, label);
        end
    endtask

    function [7:0] sensor_byte(input [15:0] address);
        case (address)
            16'h3107: sensor_byte = mode == 8 ? 8'h12 : (mode == 9 ? 8'h9e : 8'hee);
            16'h3108: sensor_byte = 8'h4b;
            default: sensor_byte = 8'hff;
        endcase
    endfunction

    task receive_byte(input [7:0] value);
        rx_bytes = rx_bytes + 1;
        pending_write = 0;
        if (byte_index == 0) begin
            selected = (value == 8'h6c || value == 8'h6d);
            reading = value[0];
            reject_segment = 0;
            check(selected, "device address must be 6c/6d");
        end else if (selected && !reading && !reject_segment) begin
            case (byte_index)
                1: reg_addr[15:8] = value;
                2: reg_addr[7:0] = value;
                3: begin pending_write = 1; pending_value = value; end
                default: check(0, "unexpected extra write byte");
            endcase
        end
        want_ack = selected && !reject_segment;
        if ((!injected || mode == 5 || mode == 6 || mode == 7) &&
            (((mode == 1 || mode == 4 || mode == 5) && byte_index == 0 && value == 8'h6c) ||
            ((mode == 2 || mode == 6) && pending_write && reg_addr == 16'h36e9 && value == 8'h80) ||
            ((mode == 3 || mode == 7) && pending_write && ae_table_seen && reg_addr == 16'h3e01))) begin
            want_ack = 0;
            injected = injected + 1;
            if (nack_cycle != 0) begin
                retry_gap_cycles = cycle_count - nack_cycle;
                if (expect_recovery) check(retry_gap_cycles >= 119048,"failed transaction retry backoff");
            end
            nack_cycle = cycle_count;
            if ((mode == 4 || mode == 5) && byte_index == 0) reject_segment = 1;
            $display("I2C_INJECT_NACK mode=%0d byte=%0d reg=%04h data=%02h", mode, byte_index, reg_addr, value);
        end
        $fdisplay(log_fd,"RX,%0t,%0d,%02h,%04h,%0d",$time,byte_index,value,reg_addr,want_ack);
        byte_index = byte_index + 1;
    endtask

    task finish_write;
        write_count = write_count + 1;
        if (want_ack) accepted_writes = accepted_writes + 1;
        if (reg_addr == 16'h3812 && pending_value == 8'h00) ae_table_seen = 1;
        if (!ae_table_seen) begin
            init_writes = init_writes + 1;
            if (expected_cursor < 165) begin
                expected_value = expected_init[expected_cursor];
                check({reg_addr,pending_value} == expected_value, "serialized init table entry");
            end else check(0,"too many initialization writes");
            if (want_ack || !expect_recovery) expected_cursor = expected_cursor + 1;
        end else begin
            ae_writes = ae_writes + 1;
            if (expected_cursor < 8) begin
                expected_value = expected_ae[expected_cursor];
                check({reg_addr,pending_value} == expected_value, "serialized exposure table entry");
            end else check(0,"too many exposure writes");
            if (want_ack || !expect_recovery) expected_cursor = expected_cursor + 1;
        end
        if (reg_addr == 16'h0103 && pending_value == 8'h01 && want_ack)
            reset_cycle = cycle_count;
        if (reg_addr == 16'h36e9 && pending_value == 8'h80 && reset_gap_cycles == 0) begin
            reset_gap_cycles = cycle_count - reset_cycle;
            check(reset_gap_cycles >= 119048, "soft reset hold is at least 119048 source clocks");
        end
        $fdisplay(log_fd,"WRITE,%0t,%04h,%02h,%0d",$time,reg_addr,pending_value,want_ack);
    endtask

    always @(posedge clk) begin
        cycle_count = cycle_count + 1;
        if (rst_n && iic_error) begin
            sticky_seen = 1;
            if (!cfg_done || !ae_done) errors_while_incomplete = errors_while_incomplete + 1;
        end
        if (rst_n && expect_recovery && sticky_seen && !iic_error &&
            (((mode == 1 || mode == 2 || mode == 4) && !cfg_done) ||
             (mode == 3 && !ae_done))) premature_clear = 1;
    end

    // The slave only observes pins. No DUT state controls ACK or read data.
    always @(negedge sda) if (rst_n && scl === 1'b1) begin
        if (expect_recovery && fault_stop_cycle != 0) begin
            retry_gap_cycles = cycle_count - fault_stop_cycle;
            check(retry_gap_cycles >= 119048,"retry START follows full source-clock backoff");
            fault_stop_cycle = 0;
        end
        starts = starts + 1;
        active = 1;
        phase = RX;
        bit_count = 0;
        byte_index = 0;
        shift = 0;
        selected = 0;
        reading = 0;
        reject_segment = 0;
        $fdisplay(log_fd,"START,%0t",$time);
    end
    always @(posedge sda) if (rst_n && scl === 1'b1) begin
        stops = stops + 1;
        active = 0;
        if (expect_recovery && nack_cycle != 0) begin
            fault_stop_cycle = cycle_count;
            nack_cycle = 0;
        end
        $fdisplay(log_fd,"STOP,%0t",$time);
    end

    always @(posedge scl) if (rst_n && active) begin
        case (phase)
            RX: begin
                shift = {shift[6:0],sda};
                bit_count = bit_count + 1;
                if (bit_count == 8) begin
                    receive_byte(shift);
                    phase = ACK_SETUP;
                end
            end
            ACK_SAMPLE: begin
                check(sda === (want_ack ? 1'b0 : 1'b1), "slave ACK pin level");
                if (want_ack) ack_count = ack_count + 1;
                else nack_count = nack_count + 1;
                if (pending_write) finish_write;
                phase = ACK_RELEASE;
            end
            TX: begin
                check(sda === tx_value[7-bit_count], "sensor read bit on SCL rising edge");
                bit_count = bit_count + 1;
                if (bit_count == 8) begin
                    tx_bytes = tx_bytes + 1;
                    $fdisplay(log_fd,"TX,%0t,%04h,%02h",$time,reg_addr,tx_value);
                    phase = MASTER_ACK_SETUP;
                end
            end
            MASTER_ACK_SAMPLE: begin
                check(sda === 1'b1, "one-byte sensor read must end with master NACK");
                if (sda === 1'b1) master_nacks = master_nacks + 1;
                phase = WAIT_END;
            end
        endcase
    end

    always @(negedge scl) if (rst_n && active) begin
        case (phase)
            ACK_SETUP: begin pull_low = want_ack; phase = ACK_SAMPLE; end
            ACK_RELEASE: begin
                pull_low = 0;
                bit_count = 0;
                if (reading && selected && want_ack) begin
                    tx_value = sensor_byte(reg_addr);
                    pull_low = !tx_value[7];
                    phase = TX;
                end else begin phase = RX; shift = 0; end
            end
            TX: pull_low = !tx_value[7-bit_count];
            MASTER_ACK_SETUP: begin pull_low = 0; phase = MASTER_ACK_SAMPLE; end
            WAIT_END: pull_low = 0;
        endcase
    end

    initial begin
        if (!$value$plusargs("MODE=%d",mode)) mode = 0;
        if (!$value$plusargs("EXPECT_RECOVERY=%d",expect_recovery)) expect_recovery = 0;
        if (!$value$plusargs("CHECKER_NEGATIVE=%d",checker_negative)) checker_negative = 0;
        log_fd = $fopen("bus.csv","w");
        $readmemh("expected-init.mem",expected_init);
        if (checker_negative) expected_init[10] = expected_init[10] ^ 24'h000001;
        expected_ae[0]=24'h381200; expected_ae[1]=24'h3e0001;
        expected_ae[2]=24'h3e0123; expected_ae[3]=24'h3e0240;
        expected_ae[4]=24'h3e0900; expected_ae[5]=24'h3e0600;
        expected_ae[6]=24'h3e0780; expected_ae[7]=24'h381230;
        rst_n = 0;
        repeat (12) @(negedge clk);
        rst_n = 1;
        if (mode == 5 || mode == 6 || mode == 8 || mode == 11) begin
            repeat (FAULT_OBSERVE_CYCLES) @(negedge clk);
            check(cfg_done === 1'b0 && ae_done === 1'b0 && iic_error === 1'b1,"candidate fatal fault blocks configuration");
            if (mode == 5) begin
                check(injected == 3 && init_writes == 0 && tx_bytes == 3,"permanent address rejection stops after three attempts");
                check(diagnostic === 32'h03133107,"ID retry-exhaustion diagnostic");
            end else if (mode == 6) begin
                check(injected == 3 && init_writes == 4 && expected_cursor == 1,"permanent init NACK does not advance failed register");
                check(diagnostic === 32'h033336e9,"initialization retry-exhaustion diagnostic");
            end else if (mode == 8) begin
                check(sensor_id === 16'h124b && id_ok === 1'b0 && init_writes == 0,"wrong ID is rejected before initialization");
                check(diagnostic === 32'h01513108,"wrong-ID diagnostic");
            end else begin
                check(init_writes == 0,"deadline fault sends no initialization");
                check(diagnostic === 32'h01613107,"timeout diagnostic");
            end
        end else if (mode == 4 && !expect_recovery) begin
            repeat (12000) @(negedge clk);
            check(injected == 1,"ID-address NACK injected");
            check(iic_error === 1'b1,"legacy ID NACK remains sticky");
            check(cfg_done === 1'b0 && id_ok === 1'b0,"legacy rejected ID blocks configuration");
            check(sensor_id === 16'hff4b,"legacy proceeds to low ID after rejected high-ID address");
            check(tx_bytes == 2 && init_writes == 0,"legacy issues both reads and no init table");
        end else begin
            wait(cfg_done === 1'b1);
            repeat (24) @(negedge clk);
            $display("I2C_INIT_COMPLETE mode=%0d id=%04h sticky=%0d writes=%0d",mode,sensor_id,iic_error,init_writes);
            check(sensor_id === (mode == 9 ? 16'h9e4b : 16'hee4b) && id_ok === 1'b1,"complete correct sensor ID");
            check(expected_cursor == 165,"entire 165-entry init table observed");
            check(master_nacks >= 2,"both ID reads end in normal master NACK");
            expected_cursor = 0;
            ae_req = 1;
            @(negedge clk);
            ae_req = 0;
            if (mode == 10) begin ae_value = 16'habcd; ag_value = 16'd176; end
            wait(ae_done === 1'b0);
            if (mode == 7) begin
                repeat (FAULT_OBSERVE_CYCLES) @(negedge clk);
                check(cfg_done === 1'b0 && ae_done === 1'b0 && iic_error === 1'b1,"permanent AE fault fails closed");
                check(injected == 3 && ae_writes == 5 && expected_cursor == 2,"permanent AE NACK does not advance failed register");
                check(diagnostic === 32'h03433e01,"AE retry-exhaustion diagnostic");
            end else begin
                wait(ae_done === 1'b1);
                repeat (48) @(negedge clk);
                check(expected_cursor == 8,"entire eight-entry AE table observed");
            end
            if (mode == 0 || mode == 9 || mode == 10) begin
                check(injected == 0 && nack_count == 0,"all slave bytes acknowledged");
                check(iic_error === 1'b0 && sticky_seen == 0,"healthy read final NACK is not a bus error");
                check(rx_bytes == 700 && tx_bytes == 2,"complete expected byte counts");
            end else if (expect_recovery && mode != 7) begin
                check(injected == 1,"requested transient fault injected");
                check(iic_error === 1'b0,"transient fault recovered without sticky fatal error");
                check(errors_while_incomplete > 0,"active fault is visible while retrying");
                check(premature_clear == 0,"fault clears only after the entire table completes");
                if (mode == 1 || mode == 4) check(diagnostic === 32'h01113107,"recovered ID diagnostic persists");
                else if (mode == 2) check(diagnostic === 32'h013136e9,"recovered init diagnostic persists");
                else if (mode == 3) check(diagnostic === 32'h01413e01,"recovered AE diagnostic persists");
            end else if (!expect_recovery) begin
                check(injected == 1 && nack_count == 1,"exactly one write NACK injected");
                check(iic_error === 1'b1 && sticky_seen == 1,"legacy write NACK remains sticky after later success");
                check(init_writes == 165 && ae_writes == 8,"legacy advances table after a NACK");
            end
        end
        test_done = 1;
        $display("I2C_RESULT errors=%0d checks=%0d mode=%0d rx=%0d tx=%0d ack=%0d nack=%0d master_nack=%0d init=%0d ae=%0d cfg=%0d error=%0d gap=%0d",errors,checks,mode,rx_bytes,tx_bytes,ack_count,nack_count,master_nacks,init_writes,ae_writes,cfg_done,iic_error,reset_gap_cycles);
        $fclose(log_fd);
        $finish;
    end
    initial begin
        #100000000;
        check(0,"configuration watchdog");
        $display("I2C_TIMEOUT cfg=%b id=%h starts=%0d rx=%0d tx=%0d",cfg_done,sensor_id,starts,rx_bytes,tx_bytes);
        $fclose(log_fd);
        $finish;
    end
endmodule
