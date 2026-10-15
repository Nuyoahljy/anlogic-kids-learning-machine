`timescale 1ns/1ps
// T-018: the slave and protocol scoreboard use pins only. The stimulus knows
// the documented parent-clock CE schedule; it never reads DUT internal state.
module tb_pixel14_i2c_ce;
    parameter integer CLK_DIV = 239;
    localparam integer HALF = CLK_DIV/2 + 1;
    localparam integer PERIOD = 2*HALF;
    localparam integer PARENT_NS = 42;
    localparam integer HALF_NS = HALF*PARENT_NS;
    reg clk=0;
    always #21 clk=!clk;
    reg rst_n=0, req=0, mode=1;
    reg [31:0] wr_data=0;
    reg [7:0] wr_count=4, rd_count=1;
    wire scl, busy, bus_error, sda_debug;
    wire [7:0] read_data;
    // Net rise/fall delays apply after open-drain resolution. The slave below
    // chooses its drive delay so the resolved data is valid 3450 ns after SCL
    // falls: 2450+1000 for release, 3150+300 for pull-low.
    tri1 #(1000,300) sda;
    reg slave_low=0, slave_reset=1;
    assign sda=slave_low ? 1'b0:1'bz;
    uii2c #(.WMEN_LEN(4),.RMEN_LEN(1),.CLK_DIV(CLK_DIV)) dut (
        .I_clk(clk),.I_rstn(rst_n),.O_iic_scl(scl),.IO_iic_sda(sda),
        .I_wr_data(wr_data),.I_wr_cnt(wr_count),.I_rd_cnt(rd_count),
        .O_rd_data(read_data),.I_iic_req(req),.I_iic_mode(mode),
        .O_iic_busy(busy),.O_iic_bus_error(bus_error),.IO_iic_sda_dg(sda_debug));

    localparam RX=0,ACK_SETUP=1,ACK_SAMPLE=2,ACK_RELEASE=3,
               TX=4,MASTER_ACK_SETUP=5,MASTER_ACK_SAMPLE=6,WAIT_END=7;
    integer errors=0, checks=0, test_done=0, checker_negative=0, injected=0;
    integer parent_cycles=0, cases=0, phase_cases=0, same_edge_cases=0;
    integer completed_transactions=0, abort_cases=0, stuck_cases=0;
    integer external_slave_clears=0, reset_assertions=0, reset_release_offsets=0;
    integer request_phase_coverage=0, same_edge_phase_coverage=0;
    integer starts=0, repeated_starts=0, stops=0, rx_bytes=0, tx_bytes=0;
    integer ack_count=0, master_nacks=0, busy_requests=0, payload_mutations=0;
    integer high_checks=0, low_checks=0, setup_checks=0, hold_checks=0;
    integer start_hold_checks=0, restart_setup_checks=0, stop_setup_checks=0;
    integer min_high_ns=2147483647, min_low_ns=2147483647;
    integer min_setup_ns=2147483647, min_hold_ns=2147483647;
    integer max_data_valid_ns=0, min_start_hold_ns=2147483647;
    integer min_restart_setup_ns=2147483647, min_stop_setup_ns=2147483647;
    integer min_bus_free_ns=2147483647, min_accept_cycles=9999,max_accept_cycles=0;
    integer slave_phase=RX, bit_count=0, byte_index=0, segment=0, generation=0;
    integer case_starts=0, case_stops=0, case_rx=0, case_ack=0, case_tx=0, case_nack=0;
    integer case_number=0, log_fd, loop_phase, edge_mode, abort_kind;
    reg active=0, reading=0, armed=0, verify_bus=0;
    reg [7:0] rx_shift=0, expected_read=8'ha5;
    reg [7:0] expected_write[0:3];
    reg [239:0] phase_seen=0, same_edge_seen=0;
    reg [41:0] release_seen=0;
    reg have_fall=0, have_rise=0, start_since_rise=0, have_stop=0;
    time last_fall=0,last_rise=0,last_sda_change=0,last_start=0,last_stop=0;

    always @(posedge clk) parent_cycles=parent_cycles+1;

    task check(input bit ok,input string label);
        checks=checks+1;
        if(!ok) begin
            errors=errors+1;
            if(errors<=60) $display("CE_CHECK_FAIL t=%0t case=%0d %s",$time,case_number,label);
        end
    endtask

    task stop_incomplete(input string label);
        check(0,label);
        $display("CE_INCOMPLETE case=%0d",case_number);
        $finish;
    endtask

    // The sensor receives no controller reset. Explicit slave_reset is only
    // an external fixture action, recorded when a controller abort leaves a
    // slave holding SDA low. Pending delayed drives are invalidated by it.
    always @(posedge slave_reset) begin
        generation=generation+1;
        slave_low=0;active=0;slave_phase=RX;bit_count=0;byte_index=0;
    end
    task drive_slave(input bit low);
        integer epoch;
        begin
            epoch=generation;
            if(low) #3150; else #2450;
            if(!slave_reset && epoch==generation) slave_low=low;
        end
    endtask

    always @(sda) last_sda_change=$time;
    always @(negedge sda) if(!slave_reset && scl===1'b1) begin
        if(verify_bus) begin
            check(armed,"START belongs to an armed transaction");
            if(active && case_starts!=0) begin
                check(case_starts==1 && case_rx==4 && case_ack==4,
                      "repeated START follows exactly four acknowledged write bytes");
                check($time-last_rise>=4700,"repeated START setup >= 4700 ns");
                restart_setup_checks=restart_setup_checks+1;
                if($time-last_rise<min_restart_setup_ns) min_restart_setup_ns=$time-last_rise;
            end else if(have_stop) begin
                check($time-last_stop>=4700,"bus free interval >= 4700 ns");
                if($time-last_stop<min_bus_free_ns) min_bus_free_ns=$time-last_stop;
            end
        end
        // After controller-only reset the pins can already be high, so there
        // need not have been a STOP edge. A fresh START still resets an I2C
        // slave's address decoder and may legally address a new write. The
        // first START of the independently prepared case is not its read phase.
        if(active) repeated_starts=repeated_starts+1;
        segment=case_starts==0 ? 0:1;
        starts=starts+1;case_starts=case_starts+1;
        active=1;slave_phase=RX;bit_count=0;byte_index=0;rx_shift=0;reading=0;
        last_start=$time;start_since_rise=1;
        $fdisplay(log_fd,"START,%0t,%0d,%0d",$time,case_number,segment);
    end
    always @(posedge sda) if(!slave_reset && scl===1'b1 && active) begin
        if(verify_bus) begin
            check(case_starts==2 && case_rx==5 && case_ack==5 && case_tx==1 && case_nack==1,
                  "STOP follows four writes, read address, one read byte, and master NACK");
            check(slave_phase==WAIT_END,"STOP occurs only after master NACK");
            check($time-last_rise>=4000,"STOP setup >= 4000 ns");
            stop_setup_checks=stop_setup_checks+1;
            if($time-last_rise<min_stop_setup_ns) min_stop_setup_ns=$time-last_rise;
        end
        stops=stops+1;case_stops=case_stops+1;active=0;
        have_stop=1;last_stop=$time;
        $fdisplay(log_fd,"STOP,%0t,%0d",$time,case_number);
    end
    // Any data edge while SCL is low is independently timed. Edges during
    // high are parsed as START/STOP and must satisfy the byte scoreboard.
    always @(sda) if(verify_bus && !slave_reset && active && scl===1'b0 && have_fall) begin
        hold_checks=hold_checks+1;
        check($time-last_fall>=300,"SDA change holds >= 300 ns after SCL falling edge");
        check($time-last_fall<=3450,"resolved SDA data valid <= 3450 ns after SCL fall");
        if($time-last_fall<min_hold_ns) min_hold_ns=$time-last_fall;
        if($time-last_fall>max_data_valid_ns) max_data_valid_ns=$time-last_fall;
    end

    always @(posedge scl) begin
        if(verify_bus && active && have_fall) begin
            low_checks=low_checks+1;
            check($time-last_fall==HALF_NS,"external SCL low pulse equals 120 parent clocks");
            if($time-last_fall<min_low_ns) min_low_ns=$time-last_fall;
            setup_checks=setup_checks+1;
            check(sda===1'b0 || sda===1'b1,"SDA resolved at SCL sampling edge");
            check($time-last_sda_change>=250,"SDA setup >= 250 ns at SCL rising edge");
            if($time-last_sda_change<min_setup_ns) min_setup_ns=$time-last_sda_change;
        end
        last_rise=$time;have_rise=1;start_since_rise=0;
        if(!slave_reset && active) case(slave_phase)
            RX: begin
                rx_shift={rx_shift[6:0],sda};bit_count=bit_count+1;
                if(bit_count==8) begin
                    rx_bytes=rx_bytes+1;case_rx=case_rx+1;
                    if(verify_bus) begin
                        if(segment==0) begin
                            check(byte_index<4,"write segment has no extra byte");
                            if(byte_index<4) check(rx_shift===expected_write[byte_index],"serialized write byte matches independent expected byte");
                        end else check(byte_index==0 && rx_shift===8'h6d,"repeated segment uses preserved read address 6d");
                    end
                    if(byte_index==0) reading=rx_shift[0];
                    $fdisplay(log_fd,"RX,%0t,%0d,%0d,%0d,%02h",$time,case_number,segment,byte_index,rx_shift);
                    byte_index=byte_index+1;slave_phase=ACK_SETUP;
                end
            end
            ACK_SAMPLE: begin
                if(verify_bus) check(sda===1'b0,"slave ACK pin is low");
                ack_count=ack_count+1;case_ack=case_ack+1;slave_phase=ACK_RELEASE;
            end
            TX: begin
                if(verify_bus) check(sda===expected_read[7-bit_count],"read data bit matches pin-only sensor source");
                bit_count=bit_count+1;
                if(bit_count==8) begin
                    tx_bytes=tx_bytes+1;case_tx=case_tx+1;slave_phase=MASTER_ACK_SETUP;
                    $fdisplay(log_fd,"TX,%0t,%0d,%02h",$time,case_number,expected_read);
                end
            end
            MASTER_ACK_SAMPLE: begin
                if(verify_bus) check(sda===1'b1,"single-byte read ends in master NACK");
                if(sda===1'b1) begin master_nacks=master_nacks+1;case_nack=case_nack+1;end
                slave_phase=WAIT_END;
            end
        endcase
    end
    always @(negedge scl) begin
        if(verify_bus && active) begin
            if(have_rise) begin
                high_checks=high_checks+1;
                check($time-last_rise==(start_since_rise ? 3*HALF_NS:HALF_NS),
                      "SCL high pulse is one half-period, or three across repeated START");
                if($time-last_rise<min_high_ns) min_high_ns=$time-last_rise;
            end
            if(last_start!=0 && $time-last_start<3*HALF_NS) begin
                start_hold_checks=start_hold_checks+1;
                check($time-last_start>=4000,"START hold >= 4000 ns");
                if($time-last_start<min_start_hold_ns) min_start_hold_ns=$time-last_start;
                last_start=0;
            end
        end
        last_fall=$time;have_fall=1;
        if(!slave_reset && active) case(slave_phase)
            ACK_SETUP: begin slave_phase=ACK_SAMPLE;drive_slave(1);end
            ACK_RELEASE: begin
                bit_count=0;
                if(reading) begin slave_phase=TX;drive_slave(!expected_read[7]);end
                else begin slave_phase=RX;rx_shift=0;drive_slave(0);end
            end
            TX: drive_slave(!expected_read[7-bit_count]);
            MASTER_ACK_SETUP: begin slave_phase=MASTER_ACK_SAMPLE;drive_slave(0);end
            WAIT_END: drive_slave(0);
        endcase
    end

    task assert_reset;
        begin
            verify_bus=0;armed=0;req=0;rst_n=0;reset_assertions=reset_assertions+1;
            #1;
            check(busy===0 && bus_error===0 && read_data===0 && scl===1,
                  "asynchronous assertion clears outputs without waiting for parent clock");
            have_rise=0;have_fall=0;last_start=0;
        end
    endtask
    task release_reset(input integer skew);
        begin
            repeat(3) @(negedge clk);
            #(skew);
            // Nonblocking release at the exact parent posedge has an explicit
            // meaning: that edge still samples reset asserted.
            if(skew==21) begin rst_n<=1;#0.001;end
            else rst_n=1;
            release_seen[skew]=1;
        end
    endtask
    task idle_reset(input integer skew);
        begin
            @(negedge clk);#7;assert_reset;
            #1100;check(sda===1 && slave_low===0,"idle reset leaves released SDA after net rise delay");
            release_reset(skew);
        end
    endtask
    task prepare_expected(input integer seed);
        begin
            case_number=case_number+1;cases=cases+1;
            case_starts=0;case_stops=0;case_rx=0;case_ack=0;case_tx=0;case_nack=0;
            expected_write[0]=8'h6c;
            expected_write[1]=(seed^8'h53)&255;
            expected_write[2]=(seed*73+19)&255;
            expected_write[3]=(seed*151+7)&255;
            expected_read=seed[0] ? 8'ha5:8'hee;
            have_rise=0;have_fall=0;last_start=0;
            verify_bus=1;armed=1;
        end
    endtask
    task launch_request(input integer request_phase,input integer same_edge);
        integer n, accepted_n, request_cycle, cycles_waited;
        begin
            n=PERIOD+2+request_phase;
            repeat(n-1) @(posedge clk);
            @(negedge clk);
            if(same_edge) begin
                @(posedge clk);
                wr_data<={expected_write[3],expected_write[2],expected_write[1],expected_write[0]};
                wr_count<=4;rd_count<=1;mode<=1;req<=1;
            end else begin
                wr_data={expected_write[3],expected_write[2],expected_write[1],expected_write[0]};
                wr_count=4;rd_count=1;mode=1;req=1;
                @(posedge clk);
            end
            #1;request_cycle=parent_cycles;cycles_waited=0;
            accepted_n=HALF+2;
            while(accepted_n<n+same_edge) accepted_n=accepted_n+PERIOD;
            while(!busy && cycles_waited<=PERIOD) begin @(posedge clk);#1;cycles_waited=cycles_waited+1;end
            if(!busy) stop_incomplete("request was not accepted within one CE period");
            check(parent_cycles-request_cycle==accepted_n-n,"request acceptance matches independent CE schedule, including same-edge NBA collision");
            if(cycles_waited<min_accept_cycles) min_accept_cycles=cycles_waited;
            if(cycles_waited>max_accept_cycles) max_accept_cycles=cycles_waited;
            @(negedge clk);req=0;
        end
    endtask
    task await_counter(input integer which_counter,input integer threshold);
        integer timeout_count,current_count;
        begin
            timeout_count=0;current_count=0;
            while(current_count<threshold && timeout_count<18000) begin
                @(negedge clk);timeout_count=timeout_count+1;
                case(which_counter)
                    0:current_count=case_starts;
                    1:current_count=case_ack;
                    2:current_count=case_rx;
                    3:current_count=case_tx;
                    default:current_count=case_nack;
                endcase
            end
            if(current_count<threshold) stop_incomplete("pin-only slave event timed out");
        end
    endtask
    task finish_transaction(input bit perturb);
        integer timeout_count, saved_starts, saved_stops;
        reg [7:0] held_read;
        begin
            if(perturb) begin
                // Mutate every captured field immediately after acceptance.
                wr_data=32'hdeadbeef;wr_count=1;rd_count=0;mode=0;
                payload_mutations=payload_mutations+1;
                repeat(40) @(negedge clk);
                req=1;busy_requests=busy_requests+1;
                repeat(PERIOD) @(negedge clk);
                check(busy===1,"early busy request remains inside original transaction");
                req=0;
                // This pulse spans the internal repeated-START handoff, but
                // is driven only from the fourth observed ACK on the pins.
                await_counter(1,4);
                wr_data=32'h01234567;wr_count=255;rd_count=255;mode=0;req=1;
                payload_mutations=payload_mutations+1;busy_requests=busy_requests+1;
                await_counter(0,2);
                repeat(20) @(negedge clk);req=0;
                check(busy===1,"repeated-START busy request does not replace captured transaction");
            end
            timeout_count=0;
            while(busy && timeout_count<18000) begin @(posedge clk);#1;timeout_count=timeout_count+1;end
            if(busy) stop_incomplete("transaction busy failed to complete");
            check(case_starts==2 && case_stops==1 && case_rx==5 && case_ack==5 && case_tx==1 && case_nack==1,
                  "complete transaction has exact pin-level framing and byte counts");
            check(bus_error===0,"ACKed transaction has no bus error");
            if(checker_negative && !injected) begin
                force read_data=8'h00;#1;injected=injected+1;
                check(read_data===expected_read,"completed read data (real output fault injected)");
                release read_data;#1;
            end else check(read_data===expected_read,"completed read data equals independent sensor byte");
            held_read=read_data;saved_starts=starts;saved_stops=stops;
            repeat(2*PERIOD) begin
                @(posedge clk);#1;
                check(read_data===held_read && busy===0 && bus_error===0,"readback and idle status hold after completion");
            end
            check(starts==saved_starts && stops==saved_stops,"busy-time requests do not queue an extra transaction");
            completed_transactions=completed_transactions+1;armed=0;verify_bus=0;
            $fdisplay(log_fd,"COMPLETE,%0t,%0d,%02h",$time,case_number,read_data);
        end
    endtask

    initial begin
        if(!$value$plusargs("CHECKER_NEGATIVE=%d",checker_negative)) checker_negative=0;
        log_fd=$fopen("ce-bus.csv","w");
        if(CLK_DIV!=239) stop_incomplete("qualification matrix is explicitly bound to CLK_DIV=239");
        #2000;slave_reset=0;
        // Complete 240-phase sweeps, with and without same-edge NBA inputs.
        for(edge_mode=0;edge_mode<2;edge_mode=edge_mode+1) begin
            for(loop_phase=0;loop_phase<PERIOD;loop_phase=loop_phase+1) begin
                idle_reset(loop_phase%42);
                prepare_expected(loop_phase+edge_mode*PERIOD);
                launch_request(loop_phase,edge_mode);
                finish_transaction(1);
                if(edge_mode) begin same_edge_seen[loop_phase]=1;same_edge_cases=same_edge_cases+1;end
                else begin phase_seen[loop_phase]=1;phase_cases=phase_cases+1;end
            end
            $display("CE_PHASE_SWEEP mode=%0d complete=%0d errors=%0d",edge_mode,completed_transactions,errors);
        end
        // Abort at eight observable locations. The sensor does not receive
        // master reset; blocked SDA requires an explicitly recorded external
        // sensor release, proving the absence of bus-clear support.
        for(abort_kind=0;abort_kind<8;abort_kind=abort_kind+1) begin
            idle_reset((abort_kind*5+1)%42);
            prepare_expected(700+abort_kind);
            launch_request((abort_kind*31)%PERIOD,abort_kind%2);
            case(abort_kind)
                0: begin await_counter(0,1);#731;end
                1: begin await_counter(2,1);#713;end
                2: begin await_counter(1,1);#713;end
                3: begin await_counter(1,4);#713;end
                4: begin await_counter(0,2);#713;end
                5: begin await_counter(1,5);repeat(3) @(posedge scl);#713;end
                6: begin await_counter(3,1);#713;end
                7: begin await_counter(4,1);#713;end
            endcase
            assert_reset;abort_cases=abort_cases+1;
            // Let a slow slave's already scheduled data change settle before
            // deciding whether an external device reset is needed.
            #5000;
            if(sda===1'b0) begin
                stuck_cases=stuck_cases+1;
                release_reset((abort_kind*7+2)%42);
                repeat(3*PERIOD) @(negedge clk);
                check(sda===0 && busy===0 && scl===1,"held-low slave remains blocked: controller has no bus-clear clocks");
                slave_reset=1;external_slave_clears=external_slave_clears+1;
                #1100;check(sda===1,"explicit external sensor release clears blocked SDA");
                slave_reset=0;
                idle_reset((abort_kind*3+4)%42);
            end else begin
                check(sda===1 && slave_low===0,"controller-only abort releases the bus; next START resets the address decoder");
                release_reset((abort_kind*3+4)%42);
            end
            prepare_expected(800+abort_kind);
            launch_request((abort_kind*37)%PERIOD,abort_kind%2);
            finish_transaction(1);
        end
        for(loop_phase=0;loop_phase<240;loop_phase=loop_phase+1) begin
            if(phase_seen[loop_phase]) request_phase_coverage=request_phase_coverage+1;
            if(same_edge_seen[loop_phase]) same_edge_phase_coverage=same_edge_phase_coverage+1;
        end
        for(loop_phase=0;loop_phase<42;loop_phase=loop_phase+1)
            if(release_seen[loop_phase]) reset_release_offsets=reset_release_offsets+1;
        check(request_phase_coverage==240 && same_edge_phase_coverage==240,"both request modes cover all 240 parent phases");
        check(reset_release_offsets==42,"reset releases cover all 42 nanosecond offsets including exact parent edge");
        check(completed_transactions==488 && abort_cases==8,"all phase and post-abort recovery transactions completed");
        check(stuck_cases>0 && external_slave_clears==stuck_cases,"blocked-slave recovery is explicit, counted, and never hidden");
        check(high_checks>0 && low_checks>0 && setup_checks>0 && hold_checks>0,
              "all external pin timing categories have actual coverage");
        test_done=1;
        $display("CE_RESULT errors=%0d checks=%0d completed=%0d phases=%0d same_edge=%0d aborts=%0d stuck=%0d setup_min_ns=%0d hold_min_ns=%0d",
                 errors,checks,completed_transactions,request_phase_coverage,same_edge_phase_coverage,abort_cases,stuck_cases,min_setup_ns,min_hold_ns);
        $fclose(log_fd);$finish;
    end
    initial begin #400000000;stop_incomplete("global 400 ms simulation watchdog");end
endmodule
