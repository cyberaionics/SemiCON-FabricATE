`timescale 1ns/1ps
module tb_arbiter;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0;reg [1:0] request=0;reg accept=0,last=0;wire selected;
    packet_rr_arbiter dut(clk,rst_n,request,accept,last,selected);
    task step(input [1:0] req,input a,input l,input expected);
        begin
            @(negedge clk); request=req;accept=a;last=l;
            #1;if(selected!==expected) $fatal(1,"Arbiter selection incorrect");
            @(posedge clk);#1;
        end
    endtask
    initial begin
        repeat(2) @(negedge clk);rst_n=1;
        step(2'b10,0,0,1); // First beat presented but blocked: lock source 1.
        step(2'b11,0,1,1); // Other source arrives; unaccepted LAST must not unlock.
        step(2'b11,1,0,1);
        step(2'b01,0,0,1); // Owner has a gap; do not steal its packet.
        step(2'b11,1,1,1);
        step(2'b11,1,1,0);
        step(2'b11,1,1,1);
        step(2'b11,1,1,0);
        @(negedge clk);rst_n=0;request=0;accept=0;
        @(negedge clk);rst_n=1;
        step(2'b11,1,1,0);
        $display("PASS arbiter: stalled first/final beat, owner gap, round robin, reset");$finish;
    end
endmodule
