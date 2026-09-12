`timescale 1ns/1ps
module tb_ltssm;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic phy_rx_detected=0, training_done=0, link_width_ok=0, lane_config_ok=0;
  logic recovery_request=0, phy_error=0, disable_request=0, hot_reset_request=0;
  logic link_up,tx_enable,rx_enable,training_enable,recovery_active,state_changed;
  logic [5:0] state;
  ltssm dut(.*);
  initial begin
    $dumpfile("ltssm.vcd"); $dumpvars(0,tb_ltssm);
    repeat(3) @(posedge clk); rst_n<=1;
    @(posedge clk); phy_rx_detected<=1;
    @(posedge clk); training_done<=1; link_width_ok<=1; lane_config_ok<=1;
    repeat(15) @(posedge clk);
    if(!link_up) $fatal(1,"FAIL: LTSSM did not reach L0");
    if(tx_enable !== 1'b1 || rx_enable !== 1'b1) $fatal(1,"FAIL: L0 enables incorrect");
    $display("PASS: standalone LTSSM reached L0");
    recovery_request<=1; @(posedge clk); recovery_request<=0;
    @(posedge clk);
    if(recovery_active !== 1'b1 || tx_enable !== 1'b0) $fatal(1,"FAIL: Recovery controls");
    repeat(5) @(posedge clk);
    if(!link_up) $fatal(1,"FAIL: Recovery did not return L0");
    $display("PASS: standalone Recovery returned L0");
    disable_request<=1; repeat(2) @(posedge clk);
    if(state!==6'h20 || tx_enable!==1'b0) $fatal(1,"FAIL: Disabled state");
    disable_request<=0; repeat(2) @(posedge clk);
    if(state!==6'h00 && state!==6'h01) $fatal(1,"FAIL: Detect return");
    $display("PASS: standalone Disabled returned to Detect");
    $finish;
  end
endmodule
