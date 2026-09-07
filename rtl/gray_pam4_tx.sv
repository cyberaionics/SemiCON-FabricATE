module gray_pam4_tx(
  input  logic [255:0] data_in,
  output logic [255:0] symbols_out
);
  integer i;
  logic [1:0] b, g;
  always_comb begin
    symbols_out='0;
    for(i=0;i<128;i=i+1) begin
      b=data_in[i*2 +: 2];
      case(b)
        2'b00: g=2'b00;
        2'b01: g=2'b01;
        2'b10: g=2'b11;
        default: g=2'b10;
      endcase
      symbols_out[i*2 +: 2]=g;
    end
  end
endmodule
