// I0309: every card-only question has a member of the five-card catalog.
module pixel309_question_bank #(
    parameter integer SHAPE_ENABLE=1
)(input wire [3:0] index,output reg [3:0] item);
    always @* begin
        if(SHAPE_ENABLE)begin
            case(index)
                0:item=1;1:item=10;2:item=2;3:item=11;
                4:item=3;5:item=12;6:item=13;7:item=14;
                default:item=0;
            endcase
        end else begin
            case(index)
                0:item=10;1:item=11;2:item=12;3:item=13;4:item=14;
                default:item=0;
            endcase
        end
    end
endmodule
