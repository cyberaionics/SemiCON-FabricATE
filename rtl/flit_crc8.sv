`timescale 1ns/1ps
`default_nettype none
// Eight-byte RS CRC, GF(256), primitive polynomial 0x12b, roots alpha^1..8.
// Feed bytes in transmission order. Initial state zero, no final complement.
// crc[7:0] is CRC0 (constant coefficient). See docs/CRC.md for byte ordering.
module flit_crc8(
    input wire clk, input wire rst_n,
    input wire clear, input wire enable, input wire [7:0] data,
    output reg [63:0] crc
);
    function automatic [7:0] multiply(input [7:0] a,input [7:0] b);
        reg [7:0] x,y,result;
        integer i;
        begin
            x=a;y=b;result=0;
            for(i=0;i<8;i=i+1) begin
                if(y[0]) result=result^x;
                x=(x<<1)^(x[7]?8'h2b:8'h00);
                y=y>>1;
            end
            multiply=result;
        end
    endfunction
    wire [7:0] feedback=crc[63:56]^data;
    wire [63:0] correction={
        multiply(feedback,8'hd5),multiply(feedback,8'h68),
        multiply(feedback,8'hfe),multiply(feedback,8'hd5),
        multiply(feedback,8'h33),multiply(feedback,8'h41),
        multiply(feedback,8'h4d),multiply(feedback,8'h69)};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) crc<=0;
        else if(clear) crc<=0;
        else if(enable) crc<={crc[55:0],8'b0}^correction;
    end
endmodule
`default_nettype wire
