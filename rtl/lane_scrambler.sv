module lane_scrambler(
  input  logic clk,
  input  logic rst_n,
  input  logic [255:0] lane_data_in,
  output logic [255:0] lane_data_out,
  input  logic advance
);
  logic [22:0] lfsr_q [0:3];
  logic [22:0] lfsr_d [0:3];
  integer l;

  function automatic [22:0] lfsr_next(input [22:0] s);
    reg [22:0] n;
    begin
      n[0]=s[22]; n[1]=s[0]; n[2]=s[1]^s[22]; n[3]=s[2];
      n[4]=s[3]; n[5]=s[4]^s[22]; n[6]=s[5]; n[7]=s[6];
      n[8]=s[7]^s[22]; n[9]=s[8]; n[10]=s[9]; n[11]=s[10];
      n[12]=s[11]; n[13]=s[12]; n[14]=s[13]; n[15]=s[14];
      n[16]=s[15]^s[22]; n[17]=s[16]; n[18]=s[17]; n[19]=s[18];
      n[20]=s[19]; n[21]=s[20]^s[22]; n[22]=s[21];
      lfsr_next=n;
    end
  endfunction

  // Icarus Verilog does not support output arguments on functions (only on
  // tasks), so the scrambled word and the LFSR's next state are packed into
  // a single return value {y, sn} and unpacked by the caller instead.
  function automatic [86:0] scramble_word(input [63:0] d, input [22:0] s);
    reg [63:0] y;
    reg [22:0] st;
    integer k;
    begin
      y='0; st=s;
      for(k=0;k<64;k=k+1) begin
        y[k]=d[k]^st[22];
        st=lfsr_next(st);
      end
      scramble_word={y, st};
    end
  endfunction

  always_comb begin
    lane_data_out='0;
    for(l=0;l<4;l=l+1) begin
      logic [86:0] scr_result;
      scr_result = scramble_word(lane_data_in[l*64 +: 64], lfsr_q[l]);
      lane_data_out[l*64 +: 64] = scr_result[86:23];
      lfsr_d[l]                 = scr_result[22:0];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      lfsr_q[0] <= 23'h1DBFBC;
      lfsr_q[1] <= 23'h0607BB;
      lfsr_q[2] <= 23'h1EC760;
      lfsr_q[3] <= 23'h18C0DB;
    end else if(advance) begin
      for(l=0;l<4;l=l+1) lfsr_q[l] <= lfsr_d[l];
    end
  end
endmodule
