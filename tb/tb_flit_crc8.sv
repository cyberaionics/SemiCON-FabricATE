`timescale 1ns/1ps
module tb_flit_crc8;
    `include "tb/crc_reference.svh"
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,clear=0,enable=0;
    reg [7:0] data=0;
    wire [63:0] crc;
    reg [1935:0] messages[0:31];
    reg [63:0] expected[0:31];
    reg [63:0] saved;
    reg [1999:0] frame,corrupted;
    integer v,i,errors,trial,j,detected=0;
    flit_crc8 dut(.clk(clk),.rst_n(rst_n),.clear(clear),.enable(enable),.data(data),.crc(crc));
    initial begin
        $readmemh("sim/build/crc_data.hex",messages);
        $readmemh("sim/build/crc_expected.hex",expected);
        repeat(2) @(negedge clk);rst_n=1;
        for(v=0;v<32;v=v+1) begin
            clear=1;enable=1;data=8'hff;
            @(negedge clk);
            if(crc!==0) $fatal(1,"Clear must take priority over enable");
            clear=0;enable=0;
            for(i=0;i<242;i=i+1) begin
                if(i%17==0) begin
                    saved=crc;data=~messages[v][i*8+:8];enable=0;
                    repeat(3) @(negedge clk);
                    if(crc!==saved) $fatal(1,"CRC changed without enable");
                end
                data=messages[v][i*8+:8];enable=1;
                @(negedge clk);enable=0;
            end
            if(crc!==expected[v]) $fatal(1,"CRC known-answer mismatch vector=%0d",v);
            frame={crc,messages[v]};
            if(!crc_valid(frame)) $fatal(1,"Clean codeword rejected");
            saved=crc;repeat(3) @(negedge clk);
            if(crc!==saved) $fatal(1,"Completed CRC was not held");
        end
        // One representative nonzero codeword: every data/parity bit individually.
        frame={expected[2],messages[2]};
        for(i=0;i<2000;i=i+1) begin
            corrupted=frame;corrupted[i]=~corrupted[i];
            if(crc_valid(corrupted)) $fatal(1,"Single-bit corruption escaped at %0d",i);
            detected=detected+1;
        end
        for(errors=1;errors<=8;errors=errors+1)
            for(trial=0;trial<16;trial=trial+1) begin
                corrupted=frame;
                for(j=0;j<errors;j=j+1)
                    corrupted[((trial*13+j*29)%250)*8+:8]=
                        corrupted[((trial*13+j*29)%250)*8+:8]^8'(j+trial+1);
                if(crc_valid(corrupted)) $fatal(1,"Multi-byte corruption escaped");
                detected=detected+1;
            end
        // Asynchronous reset aborts an in-progress computation.
        enable=1;data=8'hac;repeat(5) @(negedge clk);
        #2;rst_n=0;#1;if(crc!==0) $fatal(1,"Async CRC reset failed");
        @(negedge clk);enable=0;rst_n=1;
        @(negedge clk);if(crc!==0) $fatal(1,"Reset CRC reappeared");
        $display("PASS CRC: 32 vectors, enable gaps, clear/reset, %0d corrupted codewords rejected",detected);
        $finish;
    end
    initial begin repeat(30000) @(posedge clk);$fatal(1,"CRC timeout");end
endmodule
