`timescale 1ns/1ps
module tb_pixel310_awb_retrigger;
    reg clk=0,rst_n=0,switch_async=1,frame_start=0,base_enable=1;
    reg calibration_locked=0,calibration_failed=0;
    wire awb_enable,recalibration_busy,calibration_restart,trigger_pulse,switch_qualified;
    integer errors=0,triggers=0;

    always #5 clk=~clk;
    always @(posedge clk) if(trigger_pulse)triggers=triggers+1;

    pixel310_awb_retrigger #(.CLOCK_HZ(1000),.DEBOUNCE_MS(4)) dut(
        .clk(clk),.rst_n(rst_n),.switch_async(switch_async),
        .frame_start(frame_start),.base_enable(base_enable),
        .calibration_locked(calibration_locked),.calibration_failed(calibration_failed),
        .awb_enable(awb_enable),.recalibration_busy(recalibration_busy),
        .calibration_restart(calibration_restart),
        .trigger_pulse(trigger_pulse),.switch_qualified(switch_qualified));

    task check(input bit condition,input string message);
        if(!condition)begin errors=errors+1;$display("FAIL: %s at %0t",message,$time);end
    endtask
    task cycles(input integer n);repeat(n)@(posedge clk);endtask
    task sof;
        @(negedge clk);frame_start=1;#1;
        @(posedge clk);@(negedge clk);frame_start=0;#1;
    endtask

    initial begin
        cycles(3);rst_n=1;
        // Starting high must not trigger. A stable low release is required.
        cycles(9);check(triggers==0,"boot-high interlock");
        check(!recalibration_busy&&awb_enable,"boot-high idle");

        switch_async=0;cycles(9);check(!switch_qualified,"stable low qualified");
        // Sub-debounce chatter must not produce a request.
        switch_async=1;cycles(2);switch_async=0;cycles(2);
        switch_async=1;cycles(1);switch_async=0;cycles(6);
        check(triggers==0,"switch bounce ignored");

        switch_async=1;cycles(8);
        check(triggers==1,"first stable rising action");
        check(recalibration_busy&&awb_enable,"request waits for SOF");
        @(negedge clk);frame_start=1;#1;
        check(!awb_enable,"first SOF disables AWB");
        @(posedge clk);@(negedge clk);frame_start=0;#1;
        check(!awb_enable&&recalibration_busy,"whole reset frame disabled");
        cycles(5);check(!awb_enable,"disable persists until next SOF");
        @(negedge clk);frame_start=1;#1;
        check(!awb_enable,"following SOF still presents reset to calibration");
        check(calibration_restart,"second SOF asserts explicit restart");
        @(posedge clk);@(negedge clk);frame_start=0;#1;
        check(awb_enable&&recalibration_busy,"AWB restarts after second SOF edge");
        calibration_locked=1;cycles(2);
        check(recalibration_busy,"old lock cannot complete a new request");
        calibration_locked=0;cycles(2);
        check(recalibration_busy,"controller observes unlocked state before completion");
        calibration_locked=1;cycles(1);calibration_locked=0;cycles(1);
        check(awb_enable&&!recalibration_busy,"locked result completes request");

        cycles(12);check(triggers==1,"holding high does not retrigger");
        switch_async=0;cycles(8);check(!switch_qualified,"return low rearms");
        switch_async=1;cycles(8);check(triggers==2,"second rising action");
        sof();check(!awb_enable,"second action enters reset frame");
        sof();check(awb_enable&&recalibration_busy,"second action restarts after clean reset");
        cycles(1);check(recalibration_busy,"failed path first observes cleared state");
        calibration_failed=1;cycles(1);calibration_failed=0;cycles(1);
        check(awb_enable&&!recalibration_busy,"failed result completes request");

        // Base qualification still gates the generated enable.
        base_enable=0;cycles(2);check(!awb_enable,"base enable gating");
        base_enable=1;cycles(2);check(awb_enable,"base enable recovery");

        rst_n=0;cycles(2);rst_n=1;cycles(2);
        check(!recalibration_busy&&!trigger_pulse,"reset clears request state");
        $display("RESULT errors=%0d triggers=%0d",errors,triggers);
        if(errors==0)$display("PASS");else $fatal(1,"AWB retrigger test failed");
        $finish;
    end
endmodule
