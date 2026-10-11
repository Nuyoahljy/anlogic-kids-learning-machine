// Task-local 14-item question order. This is the sole RTL item-order table.
// Control semantics derived from the read-only four-key reference:
// E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-fixed-roi/
// fpga/custom_project/sc520-board-keys/user_source/hdl_source/quiz/quiz_control.v
// Reference SHA256: CD41CB3FBD5F5B698CFE1A5AA7E8FB699F91929112EED97B3D9AF724662B8DD0
module items14_question_bank (
    input wire [3:0] index,
    output reg [3:0] item
);
    always @* begin
        case (index)
            4'd0:  item = 4'd1;
            4'd1:  item = 4'd10;
            4'd2:  item = 4'd2;
            4'd3:  item = 4'd11;
            4'd4:  item = 4'd3;
            4'd5:  item = 4'd12;
            4'd6:  item = 4'd4;
            4'd7:  item = 4'd13;
            4'd8:  item = 4'd5;
            4'd9:  item = 4'd14;
            4'd10: item = 4'd6;
            4'd11: item = 4'd7;
            4'd12: item = 4'd8;
            4'd13: item = 4'd9;
            default: item = 4'd0;
        endcase
    end
endmodule
