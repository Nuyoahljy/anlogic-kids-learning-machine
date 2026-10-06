`timescale 1ns/1ps
module tb_quiz_key_debounce;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0, key_async = 0;
    wire key_level, key_pulse;
    reg default_rst_n = 0, default_key_async = 0;
    wire default_level, default_pulse;
    integer checks = 0, errors = 0, presses = 0, default_presses = 0;
    integer default_cycles = 0;
    reg test_done = 0, fast_done = 0, default_done = 0;
    reg previous_pulse = 0;

    quiz_key_debounce #(.DEBOUNCE_CYCLES(4)) dut (
        .clk(clk), .rst_n(rst_n), .key_async(key_async),
        .key_level(key_level), .key_pulse(key_pulse)
    );
    quiz_key_debounce default_dut (
        .clk(clk), .rst_n(default_rst_n), .key_async(default_key_async),
        .key_level(default_level), .key_pulse(default_pulse)
    );

    task check(input bit condition, input string label_text);
        begin
            checks = checks + 1;
            if (!condition) begin
                errors = errors + 1;
                $display("FAIL key: %s at %0t", label_text, $time);
            end
        end
    endtask
    task drive(input bit value, input integer cycles);
        begin
            @(negedge clk); key_async = value;
            repeat (cycles) begin @(posedge clk); #1; end
        end
    endtask

    always @(posedge clk) begin
        #2;
        if (!rst_n) previous_pulse = 0;
        else begin
            check(!(key_pulse && previous_pulse), "pulse is one cycle");
            if (key_pulse) begin
                presses = presses + 1;
                check(key_level, "press implies qualified high level");
            end
            previous_pulse = key_pulse;
        end
        if (default_rst_n && default_pulse) default_presses = default_presses + 1;
    end

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        drive(0, 4);
        check(key_level === 0 && presses == 0, "reset idle");
        drive(1, 1); drive(0, 1); drive(1, 2); drive(0, 6);
        check(key_level === 0 && presses == 0, "short high bounces rejected");
        // Arbitrarily long bouncing without four consecutive high samples.
        repeat (8) begin drive(1, 3); drive(0, 2); end
        drive(0, 6);
        check(key_level === 0 && presses == 0, "long bounce train rejected");
        drive(1, 5);
        check(key_level === 0 && key_pulse === 0, "not accepted before 2 sync + 4 samples");
        @(posedge clk); #1;
        check(key_level === 1 && key_pulse === 1, "accepted exactly after qualification");
        drive(1, 25);
        check(key_level === 1 && presses == 1, "held key does not repeat");
        drive(0, 3); drive(1, 8);
        check(key_level === 1 && presses == 1, "short release cannot rearm");
        drive(0, 6);
        check(key_level === 0 && key_pulse === 0, "stable release has no press pulse");
        drive(1, 6); drive(1, 2);
        check(key_level === 1 && presses == 2, "second qualified press");
        drive(0, 6); drive(1, 3); drive(0, 3); drive(1, 3); drive(0, 7);
        check(key_level === 0 && presses == 2, "rapid reversal does not accumulate samples");
        @(negedge clk); rst_n = 0; key_async = 1;
        repeat (3) @(posedge clk);
        #1;
        check(key_level === 0 && key_pulse === 0, "reset while held clears outputs");
        @(negedge clk); rst_n = 1;
        repeat (5) @(posedge clk);
        #1;
        check(key_level === 0, "held at reset needs full debounce");
        @(posedge clk); #1;
        check(key_level === 1 && key_pulse === 1, "held at reset qualifies once");
        drive(1, 8);
        check(presses == 3, "reset-held press is unique");
        if ($test$plusargs("NEGATIVE"))
            check(presses == 4, "intentional wrong expected press count proves checker");
        fast_done = 1;
    end

    initial begin
        // This instance uses production defaults, not the accelerated parameter.
        repeat (3) @(negedge clk);
        default_rst_n = 1;
        default_key_async = 1;
        for (default_cycles = 1; default_cycles <= 1000001; default_cycles = default_cycles + 1) begin
            @(posedge clk); #1;
            if (default_level !== 0 || default_pulse !== 0) begin
                check(0, "default press occurred before 20 ms plus sync latency");
                default_cycles = 1000002;
            end
        end
        @(posedge clk); #1;
        check(default_level === 1 && default_pulse === 1, "default 1000000-sample boundary");
        repeat (4) @(posedge clk);
        #3;
        check(default_presses == 1 && default_pulse === 0, "default held key only one pulse");
        default_done = 1;
    end

    initial begin
        wait (fast_done && default_done);
        @(negedge clk);
        test_done = 1;
        $display("SUMMARY checks=%0d errors=%0d presses=%0d default_presses=%0d", checks, errors, presses, default_presses);
        $finish;
    end
    initial begin
        #25000000;
        $fatal(1, "key test watchdog timeout");
    end
endmodule
