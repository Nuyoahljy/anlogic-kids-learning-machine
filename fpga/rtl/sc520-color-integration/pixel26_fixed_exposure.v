// Exactly one grouped AE/AG write after sensor initialization, rearmed by reset.
// Keys remain owned by the application and cannot change field calibration.
module pixel26_fixed_exposure(
    input wire I_clk,I_rst,input wire [3:0] I_btn,
    input wire I_ae_cfg_done,I_cam_cfg_done,
    output reg O_ae_req,output wire [15:0] O_ae,O_ag,output reg O_applied
);
    reg sent,saw_busy;
    assign O_ae=16'd1800;
    assign O_ag=16'd144;
    always @(posedge I_clk or posedge I_rst)
        if(I_rst)begin sent<=0;O_ae_req<=0;saw_busy<=0;O_applied<=0;end
        else begin
            O_ae_req<=0;
            if(!sent && I_cam_cfg_done && I_ae_cfg_done)begin sent<=1;O_ae_req<=1;end
            if(sent && !I_ae_cfg_done)saw_busy<=1;
            if(sent && saw_busy && I_ae_cfg_done && I_cam_cfg_done)O_applied<=1;
        end
endmodule
