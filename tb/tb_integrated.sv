`timescale 1ns/1ps
module tb_integrated;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;

  logic phy_rx_detected=0, training_done=0, link_width_ok=0, lane_config_ok=0;
  logic recovery_request=0, phy_error=0, disable_request=0, hot_reset_request=0;
  logic [255:0] s_tx_data='0;
  logic s_tx_valid=0, s_tx_ready;
  logic [255:0] tx_pam4_symbols;
  logic tx_valid;
  logic [3:0] tx_lane_valid;
  logic [255:0] rx_pam4_symbols;
  logic rx_valid;
  logic inject_symbol_error=0;
  logic [255:0] symbol_error_mask=256'd0;
  logic [255:0] m_rx_data;
  logic m_rx_valid;
  logic m_rx_ready=1;
  logic link_up, tx_enable, rx_enable, training_enable, recovery_active;
  logic [5:0] ltssm_state;
  logic ltssm_state_changed;
  integer pass_count=0;

  protocol_to_phy_top dut(.*);

  // Ideal digital PHY loopback. Optional fault injection corrupts the
  // received symbol bus without changing the RTL datapath itself.
  assign rx_pam4_symbols = tx_pam4_symbols ^
                           (inject_symbol_error ? symbol_error_mask : 256'd0);
  assign rx_valid = tx_valid;

  localparam [5:0] DETECT_QUIET=6'h00, DETECT_ACTIVE=6'h01,
                   POLLING_ACTIVE=6'h02, POLLING_CONFIGURATION=6'h04,
                   CONFIG_LINKWIDTH_START=6'h05, CONFIG_LINKWIDTH_ACCEPT=6'h06,
                   CONFIG_LANENUM_WAIT=6'h08, CONFIG_LANENUM_ACCEPT=6'h07,
                   CONFIG_COMPLETE=6'h09, CONFIG_IDLE=6'h0A, L0=6'h10,
                   RECOVERY=6'h0B, DISABLED=6'h20, HOT_RESET=6'h27;

  // Safety properties checked every clock. These are deliberately written as
  // procedural assertions so they run on standard Icarus Verilog -g2012.
  always @(posedge clk) begin
    if (rst_n) begin
      if (ltssm_state != L0 && tx_enable)
        $fatal(1,"ASSERT FAIL: tx_enable asserted outside L0 (state=%h)",ltssm_state);
      if (link_up !== (ltssm_state == L0))
        $fatal(1,"ASSERT FAIL: link_up inconsistent with LTSSM state");
      if (recovery_active !== (ltssm_state == RECOVERY))
        $fatal(1,"ASSERT FAIL: recovery_active inconsistent with LTSSM state");
      if (tx_valid && !tx_enable)
        $fatal(1,"ASSERT FAIL: tx_valid asserted while TX disabled");
      if (tx_valid && tx_lane_valid !== 4'b1111)
        $fatal(1,"ASSERT FAIL: not all four lanes marked valid during TX");
    end
  end

  task automatic wait_l0;
    integer k;
    begin
      for(k=0;k<80;k=k+1) begin
        @(posedge clk);
        if(link_up) disable wait_l0;
      end
      $fatal(1,"FAIL: LTSSM did not reach L0");
    end
  endtask

  task automatic send_and_check(input [255:0] pattern);
    integer k;
    begin
      while(!s_tx_ready) @(posedge clk);
      s_tx_data <= pattern;
      s_tx_valid <= 1'b1;
      @(posedge clk);
      while(!s_tx_ready) @(posedge clk);
      s_tx_valid <= 1'b0;
      for(k=0;k<30;k=k+1) begin
        @(posedge clk);
        if(m_rx_valid) begin
          if(m_rx_data !== pattern)
            $fatal(1,"FAIL: loopback mismatch expected=%h got=%h",pattern,m_rx_data);
          pass_count = pass_count + 1;
          disable send_and_check;
        end
      end
      $fatal(1,"FAIL: no RX response");
    end
  endtask

  task automatic send_with_backpressure(input [255:0] pattern);
    integer k;
    begin
      m_rx_ready <= 1'b0;
      while(!s_tx_ready) @(posedge clk);
      s_tx_data <= pattern;
      s_tx_valid <= 1'b1;
      @(posedge clk);
      s_tx_valid <= 1'b0;
      for(k=0;k<15;k=k+1) begin
        @(posedge clk);
        if(m_rx_valid) disable send_with_backpressure;
      end
      $fatal(1,"FAIL: RX did not present data under backpressure");
    end
  endtask

  task automatic check_backpressure_held(input [255:0] pattern);
    begin
      if(m_rx_valid !== 1'b1 || m_rx_data !== pattern)
        $fatal(1,"FAIL: RX result not held under backpressure");
      repeat(3) @(posedge clk);
      if(m_rx_valid !== 1'b1 || m_rx_data !== pattern)
        $fatal(1,"FAIL: RX data changed/cleared while stalled");
      m_rx_ready <= 1'b1;
      // Allow the DUT's nonblocking state update to take effect before
      // checking m_rx_valid. At posedge clk, the testbench and DUT execute
      // in the same simulation time slot; the DUT clears valid_q in the NBA
      // region, so checking immediately at the posedge sees the old value.
      @(posedge clk);
      #1;
      if(m_rx_valid !== 1'b0)
        $fatal(1,"FAIL: RX valid did not clear after consumer ready");
      pass_count = pass_count + 1;
      $display("PASS: RX backpressure/ready handling");
    end
  endtask

  task automatic send_corrupted_and_check(input [255:0] pattern);
    integer k;
    begin
      symbol_error_mask <= 256'd0;
      symbol_error_mask[1:0] <= 2'b01;
      inject_symbol_error <= 1'b1;
      while(!s_tx_ready) @(posedge clk);
      s_tx_data <= pattern;
      s_tx_valid <= 1'b1;
      @(posedge clk);
      s_tx_valid <= 1'b0;
      for(k=0;k<30;k=k+1) begin
        @(posedge clk);
        if(m_rx_valid) begin
          if(m_rx_data === pattern)
            $fatal(1,"FAIL: injected symbol corruption was not visible at RX");
          inject_symbol_error <= 1'b0;
          symbol_error_mask <= 256'd0;
          pass_count = pass_count + 1;
          $display("PASS: injected PAM4 symbol corruption propagated to RX");
          disable send_corrupted_and_check;
        end
      end
      inject_symbol_error <= 1'b0;
      symbol_error_mask <= 256'd0;
      $fatal(1,"FAIL: no RX response for corrupted-symbol test");
    end
  endtask

  task automatic trigger_phy_error_recovery;
    begin
      @(posedge clk); phy_error <= 1'b1;
      @(posedge clk); phy_error <= 1'b0;
      repeat(1) @(posedge clk);
      if(recovery_active !== 1'b1) $fatal(1,"FAIL: phy_error did not enter Recovery");
      if(tx_enable !== 1'b0) $fatal(1,"FAIL: TX remained enabled after phy_error");
      if(link_up !== 1'b0) $fatal(1,"FAIL: link_up remained asserted in Recovery");
      wait_l0;
      pass_count = pass_count + 1;
      $display("PASS: phy_error triggered Recovery and returned to L0");
    end
  endtask

  task automatic random_stress(input integer n);
    integer k;
    reg [255:0] pattern;
    begin
      for(k=0;k<n;k=k+1) begin
        pattern = {$urandom,$urandom,$urandom,$urandom,$urandom,$urandom,$urandom,$urandom};
        send_and_check(pattern);
      end
      $display("PASS: %0d randomized end-to-end transactions",n);
    end
  endtask

  initial begin
    $dumpfile("integrated.vcd");
    $dumpvars(0,tb_integrated);

    // Reset and invalid configuration.
    repeat(3) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk); phy_rx_detected <= 1'b1;
    @(posedge clk); training_done <= 1'b1; lane_config_ok <= 1'b1;
    repeat(8) @(posedge clk);
    if(link_up !== 1'b0) $fatal(1,"FAIL: invalid link width incorrectly reached L0");
    if(tx_enable !== 1'b0) $fatal(1,"FAIL: TX enabled with invalid link width");
    $display("PASS: invalid link-width condition blocked L0");

    // Complete configuration.
    @(posedge clk); link_width_ok <= 1'b1;
    wait_l0;
    $display("PASS: LTSSM reached L0");

    // Directed data patterns.
    send_and_check(256'h0123456789ABCDEF_FEDCBA9876543210);
    send_and_check(256'hAAAAAAAAAAAAAAAA_5555555555555555);
    send_and_check(256'h0000000000000000_FFFFFFFFFFFFFFFF);
    send_and_check(256'h13579BDF2468ACE0_0ECA8642FDB97531);
    $display("PASS: directed TX -> 4-lane PHY -> RX loopback cases");

    // Backpressure.
    send_with_backpressure(256'h55AA_0F0F_F0F0_A5A5_1234_5678_9ABC_DEF0);
    check_backpressure_held(256'h55AA_0F0F_F0F0_A5A5_1234_5678_9ABC_DEF0);

    // Error visibility through the symbol interface.
    send_corrupted_and_check(256'h1122334455667788_99AABBCCDDEEFF00);

    // Explicit Recovery request.
    @(posedge clk); recovery_request <= 1'b1;
    @(posedge clk); recovery_request <= 1'b0;
    repeat(1) @(posedge clk);
    if(recovery_active !== 1'b1) $fatal(1,"FAIL: Recovery not entered");
    if(tx_enable !== 1'b0) $fatal(1,"FAIL: TX remained enabled in Recovery");
    wait_l0;
    pass_count = pass_count + 1;
    $display("PASS: Recovery request returned to L0");
    send_and_check(256'hCAFED00D_12345678_89ABCDEF_0BADF00D);

    // PHY error path.
    trigger_phy_error_recovery;
    send_and_check(256'hDEADBEEFCAFEBABE_1122334455667788);

    // Randomized stress.
    random_stress(100);

    // Disable -> Detect.
    @(posedge clk); disable_request <= 1'b1;
    repeat(2) @(posedge clk);
    if(ltssm_state !== DISABLED) $fatal(1,"FAIL: Disabled state not reached");
    if(tx_enable !== 1'b0) $fatal(1,"FAIL: TX enabled in Disabled state");
    disable_request <= 1'b0;
    repeat(2) @(posedge clk);
    if(ltssm_state !== DETECT_QUIET && ltssm_state !== DETECT_ACTIVE)
      $fatal(1,"FAIL: Disabled did not return toward Detect");
    pass_count = pass_count + 1;
    $display("PASS: Disabled returned to Detect");

    // Retrain after disable.
    repeat(1) @(posedge clk);
    phy_rx_detected <= 1'b1;
    training_done <= 1'b1;
    link_width_ok <= 1'b1;
    lane_config_ok <= 1'b1;
    wait_l0;
    send_and_check(256'hFACE1234_56789ABC_DEF00123_456789AB_CDEF0123_456789AB_CDEF0123_456789AB);
    $display("PASS: retrained link transferred data");

    // Hot reset.
    @(posedge clk); hot_reset_request <= 1'b1;
    repeat(2) @(posedge clk);
    if(ltssm_state !== HOT_RESET) $fatal(1,"FAIL: Hot Reset state not reached");
    if(tx_enable !== 1'b0) $fatal(1,"FAIL: TX enabled during Hot Reset");
    hot_reset_request <= 1'b0;
    repeat(2) @(posedge clk);
    if(ltssm_state !== DETECT_QUIET && ltssm_state !== DETECT_ACTIVE)
      $fatal(1,"FAIL: Hot Reset did not return toward Detect");
    pass_count = pass_count + 1;
    $display("PASS: Hot Reset returned toward Detect");

    $display("========================================");
    $display(" ALL INTEGRATED STAGE 1 TESTS PASSED");
    $display(" CHECKS/TRANSACTIONS COUNT = %0d",pass_count);
    $display("========================================");
    $finish;
  end
endmodule
