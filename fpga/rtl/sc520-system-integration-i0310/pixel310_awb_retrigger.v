// Debounce SW4 and request one frame-boundary AWB restart per 0->1 action.
module pixel310_awb_retrigger #(
    parameter integer CLOCK_HZ = 103520000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst_n,
    input  wire switch_async,
    input  wire frame_start,
    input  wire base_enable,
    input  wire calibration_locked,
    input  wire calibration_failed,
    output wire awb_enable,
    output wire recalibration_busy,
    output reg  trigger_pulse,
    output reg  switch_qualified
);
    localparam integer DEBOUNCE_CYCLES = (CLOCK_HZ / 1000) * DEBOUNCE_MS;
    localparam integer COUNT_W = DEBOUNCE_CYCLES <= 1 ? 1 : $clog2(DEBOUNCE_CYCLES);

    (* async_reg="true", keep="true", preserve="true" *) reg switch_meta, switch_sync;
    reg candidate, qualified_valid, armed;
    reg pending, reset_frame, waiting_for_result;
    reg [COUNT_W-1:0] stable_count;

    assign recalibration_busy = pending || reset_frame || waiting_for_result;

    // The first SOF sees enable low. It remains low during that frame, then
    // returns high on the following SOF so calibration restarts cleanly.
    assign awb_enable = base_enable &&
                        !(pending && frame_start) &&
                        !(reset_frame && !frame_start);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            switch_meta <= 1'b0;
            switch_sync <= 1'b0;
            candidate <= 1'b0;
            qualified_valid <= 1'b0;
            switch_qualified <= 1'b0;
            stable_count <= {COUNT_W{1'b0}};
            armed <= 1'b0;
            pending <= 1'b0;
            reset_frame <= 1'b0;
            waiting_for_result <= 1'b0;
            trigger_pulse <= 1'b0;
        end else begin
            switch_meta <= switch_async;
            switch_sync <= switch_meta;
            trigger_pulse <= 1'b0;

            if(!qualified_valid) begin
                if(switch_sync != candidate) begin
                    candidate <= switch_sync;
                    stable_count <= {COUNT_W{1'b0}};
                end else if(DEBOUNCE_CYCLES <= 1 || stable_count == DEBOUNCE_CYCLES-1) begin
                    switch_qualified <= candidate;
                    qualified_valid <= 1'b1;
                    stable_count <= {COUNT_W{1'b0}};
                    if(!candidate) armed <= 1'b1;
                end else begin
                    stable_count <= stable_count + 1'b1;
                end
            end else if(switch_sync != candidate) begin
                candidate <= switch_sync;
                stable_count <= {COUNT_W{1'b0}};
            end else if(candidate != switch_qualified) begin
                if(DEBOUNCE_CYCLES <= 1 || stable_count == DEBOUNCE_CYCLES-1) begin
                    switch_qualified <= candidate;
                    stable_count <= {COUNT_W{1'b0}};
                    if(!candidate) begin
                        armed <= 1'b1;
                    end else if(armed) begin
                        armed <= 1'b0;
                        pending <= 1'b1;
                        trigger_pulse <= 1'b1;
                    end
                end else begin
                    stable_count <= stable_count + 1'b1;
                end
            end else begin
                stable_count <= {COUNT_W{1'b0}};
            end

            if(pending && frame_start) begin
                pending <= 1'b0;
                reset_frame <= 1'b1;
            end else if(reset_frame && frame_start) begin
                reset_frame <= 1'b0;
                waiting_for_result <= 1'b1;
            end else if(waiting_for_result && (calibration_locked || calibration_failed)) begin
                waiting_for_result <= 1'b0;
            end
        end
    end
endmodule
