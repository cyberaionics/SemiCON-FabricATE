`timescale 1ns/1ps
module tb_blocks;
  logic [255:0] data_in, lane_data, roundtrip;
  logic [255:0] mapped, unmapped;
  logic clk=0, rst_n=0, advance=0;
  logic [255:0] scrambled, descrambled;

  always #5 clk=~clk;

  lane_striper u_s(.data_in(data_in), .lane_data(lane_data));
  lane_destriper u_d(.lane_data(lane_data), .data_out(roundtrip));
  gray_pam4_tx u_g(.data_in(data_in), .symbols_out(mapped));
  gray_pam4_rx u_r(.symbols_in(mapped), .data_out(unmapped));
  lane_scrambler tx_scr(.clk(clk),.rst_n(rst_n),.lane_data_in(data_in),.lane_data_out(scrambled),.advance(advance));
  lane_scrambler rx_scr(.clk(clk),.rst_n(rst_n),.lane_data_in(scrambled),.lane_data_out(descrambled),.advance(advance));

  initial begin
    $dumpfile("blocks.vcd"); $dumpvars(0,tb_blocks);

    data_in = 256'h0123456789ABCDEF_FEDCBA9876543210;
    #1;
    if(roundtrip !== data_in) $fatal(1,"FAIL: lane striping/destriping roundtrip");
    if(unmapped !== data_in) $fatal(1,"FAIL: Gray/PAM4 mapping inverse");
    $display("PASS: lane striping/destriping");
    $display("PASS: Gray/PAM4 mapping inverse");

    repeat(2) @(posedge clk); rst_n <= 1'b1;
    #1;
    if(descrambled !== data_in)
      $fatal(1,"FAIL: scrambler/descrambler roundtrip at seed state");
    @(posedge clk); advance <= 1'b1;
    @(posedge clk); advance <= 1'b0;
    data_in = 256'hAAAAAAAAAAAAAAAA_5555555555555555;
    #1;
    if(descrambled !== data_in)
      $fatal(1,"FAIL: scrambler/descrambler roundtrip after state advance");
    $display("PASS: per-lane scrambler/descrambler roundtrip");

    #1;
    if(roundtrip !== data_in || unmapped !== data_in) $fatal(1,"FAIL: second directed block test");
    $display("PASS: second directed block pattern");
    $display("ALL BLOCK-LEVEL TESTS PASSED");
    $finish;
  end
endmodule
