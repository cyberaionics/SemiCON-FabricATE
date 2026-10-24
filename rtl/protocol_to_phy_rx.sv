module protocol_to_phy_rx(
  input logic clk, input logic rst_n,
  input logic enable,
  input logic [255:0] rx_pam4_symbols, input logic rx_valid,
  output logic [255:0] m_data, output logic m_valid, input logic m_ready,
  output logic rx_ready
);
  logic [255:0] demapped, descrambled, destriped;
  logic [255:0] data_q;
  logic valid_q;
  logic ready_i;

  gray_pam4_rx u_map(.symbols_in(rx_pam4_symbols),.data_out(demapped));
  lane_scrambler u_descr(
    .clk(clk),.rst_n(rst_n),.lane_data_in(demapped),
    .lane_data_out(descrambled),.advance(rx_valid && ready_i)
  );
  lane_destriper u_destrip(.lane_data(descrambled),.data_out(destriped));

  assign ready_i = enable && (!valid_q || m_ready);
  assign rx_ready = ready_i;
  assign m_data = data_q;
  assign m_valid = valid_q && enable;

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin data_q<='0; valid_q<=1'b0; end
    else begin
      // Hold a received beat while RX is disabled; consume only when it is
      // actually presented (m_valid is gated by enable).
      if(rx_valid && ready_i) begin data_q<=destriped; valid_q<=1'b1; end
      else if(m_valid && m_ready) valid_q<=1'b0;
    end
  end
endmodule
