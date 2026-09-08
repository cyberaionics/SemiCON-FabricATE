module protocol_to_phy_top(
  input logic clk, input logic rst_n,

  input logic phy_rx_detected,
  input logic training_done,
  input logic link_width_ok,
  input logic lane_config_ok,
  input logic recovery_request,
  input logic phy_error,
  input logic disable_request,
  input logic hot_reset_request,

  input logic [255:0] s_tx_data,
  input logic s_tx_valid,
  output logic s_tx_ready,

  output logic [255:0] tx_pam4_symbols,
  output logic tx_valid,
  output logic [3:0] tx_lane_valid,

  input logic [255:0] rx_pam4_symbols,
  input logic rx_valid,

  output logic [255:0] m_rx_data,
  output logic m_rx_valid,
  input logic m_rx_ready,

  output logic link_up,
  output logic tx_enable,
  output logic rx_enable,
  output logic training_enable,
  output logic recovery_active,
  output logic [5:0] ltssm_state,
  output logic ltssm_state_changed
);
  ltssm u_ltssm(
    .clk(clk), .rst_n(rst_n),
    .phy_rx_detected(phy_rx_detected),
    .training_done(training_done),
    .link_width_ok(link_width_ok),
    .lane_config_ok(lane_config_ok),
    .recovery_request(recovery_request),
    .phy_error(phy_error),
    .disable_request(disable_request),
    .hot_reset_request(hot_reset_request),
    .link_up(link_up),
    .tx_enable(tx_enable),
    .rx_enable(rx_enable),
    .training_enable(training_enable),
    .recovery_active(recovery_active),
    .state(ltssm_state),
    .state_changed(ltssm_state_changed)
  );

  protocol_to_phy_tx u_tx(
    .clk(clk), .rst_n(rst_n), .enable(tx_enable),
    .s_data(s_tx_data), .s_valid(s_tx_valid), .s_ready(s_tx_ready),
    .tx_pam4_symbols(tx_pam4_symbols), .tx_valid(tx_valid),
    .tx_lane_valid(tx_lane_valid)
  );

  protocol_to_phy_rx u_rx(
    .clk(clk), .rst_n(rst_n), .enable(rx_enable),
    .rx_pam4_symbols(rx_pam4_symbols), .rx_valid(rx_valid),
    .m_data(m_rx_data), .m_valid(m_rx_valid), .m_ready(m_rx_ready)
  );
endmodule
