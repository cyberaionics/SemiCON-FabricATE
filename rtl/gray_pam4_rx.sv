module gray_pam4_rx(
  input  logic [255:0] symbols_in,
  output logic [255:0] data_out
);
  integer i;
  logic [1:0] g, b;
  always_comb begin
    data_out='0;
    for(i=0;i<128;i=i+1) begin
      g=symbols_in[i*2 +: 2];
      case(g)
        2'b00: b=2'b00;
        2'b01: b=2'b01;
        2'b11: b=2'b10;
        default: b=2'b11;
      endcase
      data_out[i*2 +: 2]=b;
    end
  end
endmodule
