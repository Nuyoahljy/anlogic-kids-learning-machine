module items30_question_bank(input wire [3:0] index,output reg [3:0] item);
    always @* case(index)
        0:item=1;1:item=10;2:item=2;3:item=11;
        4:item=3;5:item=12;6:item=13;7:item=14;
        default:item=0;
    endcase
endmodule
