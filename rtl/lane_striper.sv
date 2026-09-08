module lane_striper(
  input  logic [255:0] data_in,
  output logic [255:0] lane_data
);
  integer i;
  always_comb begin
    lane_data = '0;
    for (i=0; i<8; i=i+1) begin
      lane_data[i*8 +: 8]       = data_in[(4*i)*8 +: 8];
      lane_data[64+i*8 +: 8]    = data_in[(4*i+1)*8 +: 8];
      lane_data[128+i*8 +: 8]   = data_in[(4*i+2)*8 +: 8];
      lane_data[192+i*8 +: 8]   = data_in[(4*i+3)*8 +: 8];
    end
  end
endmodule
