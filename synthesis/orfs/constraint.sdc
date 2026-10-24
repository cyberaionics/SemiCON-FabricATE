current_design integrated_link_phy_top

set clk_period 10.000
create_clock -name core_clk -period $clk_period [get_ports clk]

set_input_delay 2.0 -clock core_clk [get_ports {
  rst_n
  s0_axis_tdata*
  s0_axis_tkeep*
  s0_axis_tlast
  s0_axis_tvalid
  s1_axis_tdata*
  s1_axis_tkeep*
  s1_axis_tlast
  s1_axis_tvalid
  phy_rx_detected
  training_done
  link_width_ok
  lane_config_ok
  recovery_request
  phy_error
  disable_request
  hot_reset_request
  m_rx_ready
}]

set_output_delay 2.0 -clock core_clk [all_outputs]
