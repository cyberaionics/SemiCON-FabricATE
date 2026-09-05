`timescale 1ns/1ps
module tb_interconnect;
    parameter integer DW=512;
    parameter integer DEPTH=4;
    localparam integer KW=DW/8, N=600;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg [DW-1:0] sd[0:1]; reg [KW-1:0] sk[0:1];
    reg [1:0] sl=0,sv=0;
    wire [1:0] sr;
    wire [DW-1:0] md; wire [KW-1:0] mk;
    wire ml,mv,ms; reg mr=0;
    axis_interconnect_2to1 #(.DATA_WIDTH(DW),.FIFO_DEPTH(DEPTH)) dut(
        .clk(clk),.rst_n(rst_n),
        .s0_axis_tdata(sd[0]),.s0_axis_tkeep(sk[0]),.s0_axis_tlast(sl[0]),.s0_axis_tvalid(sv[0]),.s0_axis_tready(sr[0]),
        .s1_axis_tdata(sd[1]),.s1_axis_tkeep(sk[1]),.s1_axis_tlast(sl[1]),.s1_axis_tvalid(sv[1]),.s1_axis_tready(sr[1]),
        .m_axis_tdata(md),.m_axis_tkeep(mk),.m_axis_tlast(ml),.m_axis_tvalid(mv),.m_axis_tready(mr),.m_axis_source(ms));
    reg [DW-1:0] qd[0:1][0:4095];
    reg [KW-1:0] qk[0:1][0:4095];
    reg ql[0:1][0:4095];
    integer wr[0:1],rd[0:1],sent[0:1];
    integer i,j,cycle,epoch,received,stalls,simultaneous,partials,gaps;
    reg in_packet,packet_source,was_stalled;
    reg [DW+KW+1:0] held;
    reg [31:0] rng=32'h1974abcd;
    integer seed_arg;
    function [31:0] rand_next(input [31:0] x);
        reg [31:0] t;
        begin t=x^(x<<13); t=t^(t>>17); rand_next=t^(t<<5); end
    endfunction
    task make_beat(input integer s,input integer n);
        integer b;
        begin
            for(b=0;b<KW;b=b+1) sd[s][8*b+:8]=8'(n*13+s*71+b*7+epoch*19);
            // Packets of 1, 2, 5 beats repeat; deliberately creates input gaps.
            sl[s]=(n%8==0 || n%8==2 || n%8==7);
            sk[s]={KW{1'b1}};
            if(sl[s]) sk[s]=({KW{1'b1}} >> (n%KW));
        end
    endtask
    // Independent per-input scoreboards compare every data bit, KEEP, LAST, source.
    always @(posedge clk) begin
        if(!rst_n) begin
            for(integer s=0;s<2;s=s+1) begin wr[s]=0; rd[s]=0; end
            in_packet=0; was_stalled=0; received=0;
        end else begin
            if(was_stalled && (!mv || {ms,ml,mk,md}!==held))
                $fatal(1,"Output changed during stall");
            was_stalled=mv && !mr; held={ms,ml,mk,md};
            for(integer s=0;s<2;s=s+1) begin
                if(sv[s] && sr[s]) begin
                    qd[s][wr[s]]=sd[s]; qk[s][wr[s]]=sk[s]; ql[s][wr[s]]=sl[s]; wr[s]=wr[s]+1;
                end
                if(sv[s] && !sr[s]) stalls=stalls+1;
            end
            if(sv==2'b11 && sr==2'b11) simultaneous=simultaneous+1;
            if(mv && mr) begin
                if(rd[ms]>=wr[ms]) $fatal(1,"Unexpected/duplicate output");
                if(md!==qd[ms][rd[ms]] || mk!==qk[ms][rd[ms]] || ml!==ql[ms][rd[ms]])
                    $fatal(1,"Scoreboard mismatch source=%0d beat=%0d",ms,rd[ms]);
                if(in_packet && ms!=packet_source) $fatal(1,"Packet interleaved");
                packet_source=ms; in_packet=!ml;
                if(ml && mk!={KW{1'b1}}) partials=partials+1;
                rd[ms]=rd[ms]+1; received=received+1;
            end
            if(in_packet && !mv) gaps=gaps+1;
        end
    end
    initial begin
        if($value$plusargs("SEED=%d",seed_arg)) rng=seed_arg;
        if($test$plusargs("VCD")) begin $dumpfile("sim/interconnect.vcd"); $dumpvars(0,tb_interconnect); end
        stalls=0; simultaneous=0; partials=0; gaps=0;
        sd[0]=0;sd[1]=0;sk[0]=0;sk[1]=0;
        // First epoch fills the pipeline with downstream blocked, then resets it.
        for(epoch=0;epoch<2;epoch=epoch+1) begin
            @(negedge clk); rst_n=0;sv=0;mr=0;
            repeat(3) @(negedge clk);
            if(mv!==0 || sr!==0) $fatal(1,"Reset outputs not quiescent");
            rst_n=1;sent[0]=0;sent[1]=0;cycle=0;
            while((epoch==0 && cycle<40) || (epoch==1 && received<2*N)) begin
                for(i=0;i<2;i=i+1) begin
                    if(!sv[i]) begin
                        rng=rand_next(rng);
                        if(sent[i]<N && (rng%4!=0 || cycle<12)) begin
                            make_beat(i,sent[i]);sv[i]=1;
                        end
                    end
                end
                rng=rand_next(rng);
                mr=(epoch==1 && cycle>=30 && cycle%97<70 && rng%4!=0);
                @(posedge clk);
                // Capture handshakes before DUT nonblocking updates.
                for(i=0;i<2;i=i+1) if(sv[i] && sr[i]) sent[i]=sent[i]+1;
                begin : accepted_block
                    reg [1:0] accepted;
                    accepted=sv & sr;
                    @(negedge clk);
                    sv=sv & ~accepted;
                end
                cycle=cycle+1;
                if(cycle>20000) $fatal(1,"Timeout: potential deadlock/loss");
            end
            if(epoch==0 && wr[0]+wr[1]==0) $fatal(1,"Reset test never buffered data");
        end
        sv=0;mr=1;
        repeat(12) @(negedge clk);
        if(mv || rd[0]!=N || rd[1]!=N || in_packet) $fatal(1,"Drain failure");
        if(stalls==0 || simultaneous==0 || partials==0) $fatal(1,"Missing coverage");
        $display("PASS DW=%0d DEPTH=%0d received=%0d stalls=%0d simultaneous=%0d partials=%0d packet_gap_cycles=%0d",DW,DEPTH,received,stalls,simultaneous,partials,gaps);
        $finish;
    end
endmodule
