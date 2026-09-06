`timescale 1ns/1ps
`default_nettype none
// Three interleaved ECC groups over 250 bytes, GF polynomial 0x11d.
// Caller clears, enables exactly 250 bytes in frame order, then samples fec.
module flit_fec6(
    input wire clk, input wire rst_n, input wire clear, input wire enable,
    input wire [7:0] data, output wire [47:0] fec
);
    reg [7:0] check0,check1,check2,parity0,parity1,parity2;
    reg [1:0] group_index;
    function automatic [7:0] alpha(input [7:0] value);
        alpha=(value<<1)^(value[7]?8'h1d:8'h00);
    endfunction
    // Groups 1 and 2 have 83 data bytes and one implicit trailing zero.
    // Low byte is frame byte 250: C1,C2,C0,P1,P2,P0.
    assign fec={parity0,parity2,parity1,check0,alpha(check2),alpha(check1)};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            check0<=0;check1<=0;check2<=0;
            parity0<=0;parity1<=0;parity2<=0;group_index<=0;
        end else if(clear) begin
            check0<=0;check1<=0;check2<=0;
            parity0<=0;parity1<=0;parity2<=0;group_index<=0;
        end else if(enable) begin
            case(group_index)
                0: begin check0<=alpha(check0^data);parity0<=parity0^data;end
                1: begin check1<=alpha(check1^data);parity1<=parity1^data;end
                2: begin check2<=alpha(check2^data);parity2<=parity2^data;end
                default: begin end
            endcase
            group_index<=group_index==2?2'b0:group_index+1'b1;
        end
    end
endmodule
`default_nettype wire
