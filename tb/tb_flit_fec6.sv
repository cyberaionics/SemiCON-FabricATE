`timescale 1ns/1ps
module tb_flit_fec6;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,clear=0,enable=0;
    reg [7:0] data=0;
    wire [47:0] fec;
    reg [1999:0] messages[0:2031];
    reg [47:0] expected[0:2031];
    reg [47:0] saved;
    integer v,i;
    flit_fec6 dut(.clk(clk),.rst_n(rst_n),.clear(clear),.enable(enable),.data(data),.fec(fec));
    initial begin
        $readmemh("sim/build/fec_data.hex",messages);
        $readmemh("sim/build/fec_expected.hex",expected);
        repeat(2) @(negedge clk);rst_n=1;
        for(v=0;v<2032;v=v+1) begin
            clear=1;enable=1;data=8'hff;
            @(negedge clk);if(fec!==0) $fatal(1,"FEC clear priority failed");
            clear=0;
            for(i=0;i<250;i=i+1) begin
                if(v<32 && i%17==0) begin
                    enable=0;saved=fec;data=8'hac;
                    repeat(3) @(negedge clk);
                    if(fec!==saved) $fatal(1,"FEC changed without enable");
                end
                enable=1;data=messages[v][i*8+:8];
                @(negedge clk);enable=0;
            end
            if(fec!==expected[v]) $fatal(1,"FEC mismatch vector=%0d",v);
            saved=fec;repeat(2) @(negedge clk);
            if(fec!==saved) $fatal(1,"FEC hold failed");
        end
        // Reset from each possible next group position, then restart a full frame.
        for(v=0;v<3;v=v+1) begin
            clear=1;@(negedge clk);clear=0;enable=1;data=8'hfe;
            repeat(v+1) @(negedge clk);
            #2;rst_n=0;#1;if(fec!==0) $fatal(1,"FEC async reset failed");
            @(negedge clk);enable=0;rst_n=1;
            for(i=0;i<250;i=i+1) begin
                data=messages[2][i*8+:8];enable=1;
                @(negedge clk);enable=0;
            end
            if(fec!==expected[2]) $fatal(1,"FEC restart failed");
        end
        $display("PASS FEC: 2032 vectors, all 2000 basis bits, enable gaps, clear priority, 3 reset positions");
        $finish;
    end
    initial begin repeat(600000) @(posedge clk);$fatal(1,"FEC timeout");end
endmodule
