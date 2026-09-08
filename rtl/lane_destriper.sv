module lane_destriper(
  input  logic [255:0] lane_data,
  output logic [255:0] data_out
);
  integer i;
  always_comb begin
    data_out = '0;
    for (i=0; i<8; i=i+1) begin
      data_out[(4*i)*8 +: 8]   = lane_data[i*8 +: 8];
      data_out[(4*i+1)*8 +: 8] = lane_data[64+i*8 +: 8];
      data_out[(4*i+2)*8 +: 8] = lane_data[128+i*8 +: 8];
      data_out[(4*i+3)*8 +: 8] = lane_data[192+i*8 +: 8];
    end
  end
endmodule
