module protocol_to_phy_tx(
  input logic clk, input logic rst_n,
  input logic enable,
  input logic [255:0] s_data, input logic s_valid, output logic s_ready,
  output logic [255:0] tx_pam4_symbols, output logic tx_valid,
  input logic tx_ready,
  output logic [3:0] tx_lane_valid
);
  logic [255:0] striped, scrambled, mapped;
  logic [255:0] data_q;
  logic valid_q;
  lane_striper u_strip(.data_in(s_data),.lane_data(striped));
  lane_scrambler u_scr(
    .clk(clk),.rst_n(rst_n),.lane_data_in(striped),
    .lane_data_out(scrambled),.advance(s_valid && s_ready)
  );
  gray_pam4_tx u_map(.data_in(scrambled),.symbols_out(mapped));

  assign s_ready = enable && (!valid_q || tx_ready);
  assign tx_valid = valid_q && enable;
  assign tx_lane_valid = {4{tx_valid}};
  assign tx_pam4_symbols = data_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin data_q<='0; valid_q<=1'b0; end
    else begin
      // A beat accepted from the source has already advanced the scrambler.
      // Hold it while TX is disabled (e.g. Recovery) instead of dropping it,
      // otherwise the RX descrambler never sees it and desynchronizes.
      // s_ready includes enable, so nothing is accepted or replaced while
      // disabled; tx_valid is gated by enable so nothing is sent either.
      if(s_ready) begin
        if(s_valid) begin
          data_q <= mapped;
          valid_q <= 1'b1;
        end else begin
          valid_q <= 1'b0;
        end
      end
    end
  end
endmodule
