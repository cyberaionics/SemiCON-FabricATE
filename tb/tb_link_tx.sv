`timescale 1ns/1ps
module tb_link_tx;
    `include "tb/crc_reference.svh"
    `include "tb/fec_reference.svh"
    parameter integer DIRECT=0;
    parameter integer DEPTH=4;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0;
    reg [511:0] sd[0:1]; reg [63:0] sk[0:1];
    reg [1:0] sl=0,sv=0; wire [1:0] sr;
    wire [255:0] md; wire [31:0] mk;
    wire ml,mv,ms,ps,pe; wire [7:0] nb;
    reg mr=0, checking=0, random_ready=0;
    integer seed=12345;
    reg [31:0] rng;
    generate if(DIRECT) begin
        assign sr[1]=0;
        axis_frame_packetizer dut(.clk(clk),.rst_n(rst_n),
            .s_axis_tdata(sd[0]),.s_axis_tkeep(sk[0]),.s_axis_tlast(sl[0]),
            .s_axis_tvalid(sv[0]),.s_axis_tready(sr[0]),.s_axis_source(1'b0),
            .m_axis_tdata(md),.m_axis_tkeep(mk),.m_axis_tlast(ml),
            .m_axis_tvalid(mv),.m_axis_tready(mr),.m_axis_source(ms),
            .m_frame_bytes(nb),.m_packet_start(ps),.m_packet_end(pe));
    end else begin
        axis_link_tx #(.FIFO_DEPTH(DEPTH)) dut(.clk(clk),.rst_n(rst_n),
            .s0_axis_tdata(sd[0]),.s0_axis_tkeep(sk[0]),.s0_axis_tlast(sl[0]),
            .s0_axis_tvalid(sv[0]),.s0_axis_tready(sr[0]),
            .s1_axis_tdata(sd[1]),.s1_axis_tkeep(sk[1]),.s1_axis_tlast(sl[1]),
            .s1_axis_tvalid(sv[1]),.s1_axis_tready(sr[1]),
            .m_axis_tdata(md),.m_axis_tkeep(mk),.m_axis_tlast(ml),
            .m_axis_tvalid(mv),.m_axis_tready(mr),.m_axis_source(ms),
            .m_frame_bytes(nb),.m_packet_start(ps),.m_packet_end(pe));
    end endgenerate
    localparam integer PACKETS=40;
    integer lengths[0:1][0:PACKETS-1];
    integer pkt[0:1], offset[0:1];
    integer beat=0,frames=0,done_packets=0,stalls=0,stall_mask=0;
    integer s,p,b,n,pos,expected_count,frame_source;
    reg [7:0] expected_byte;
    reg stalled=0;
    reg in_packet=0, packet_owner;
    reg [299:0] held;
    reg [2047:0] received_frame;
    function [7:0] value(input integer src,input integer packet,input integer idx);
        value=8'(src*83+packet*29+idx*7+(idx>>8));
    endfunction
    function integer size_for(input integer packet);
        case(packet)
            0:size_for=0; 1:size_for=1; 2:size_for=31; 3:size_for=32;
            4:size_for=33; 5:size_for=63; 6:size_for=64; 7:size_for=65;
            8:size_for=235; 9:size_for=236; 10:size_for=237;
            11:size_for=472; 12:size_for=473; 13:size_for=2048;
            default:size_for=(packet*137+seed)%1500;
        endcase
    endfunction
    task automatic send_beat(input integer src,input [511:0] data,
                             input [63:0] keep,input last);
        begin
            @(negedge clk); sd[src]=data;sk[src]=keep;sl[src]=last;sv[src]=1;
            @(posedge clk); while(!sr[src]) @(posedge clk);
            @(negedge clk); sv[src]=0;
        end
    endtask
    task automatic producer(input integer src);
        integer packet,idx,j,gap;
        reg [511:0] data;
        reg [63:0] keep;
        begin
            for(packet=0;packet<PACKETS;packet=packet+1) begin
                idx=0;
                // Null non-final beats must not generate frames or payload bytes.
                if(packet%4==0) send_beat(src,512'hdeadbeef,0,0);
                while(idx<lengths[src][packet]) begin
                    data='1;keep=0;
                    for(j=0;j<64;j=j+1) begin
                        if(idx<lengths[src][packet] && (packet%3!=0 || j%3!=1)) begin
                            data[j*8+:8]=value(src,packet,idx);keep[j]=1;idx=idx+1;
                        end
                    end
                    send_beat(src,data,keep,idx==lengths[src][packet] && packet%2==0);
                    gap=(idx+packet+src)%5;
                    repeat(gap) @(negedge clk);
                end
                if(lengths[src][packet]==0 || packet%2!=0)
                    send_beat(src,512'hbad,0,1);
            end
        end
    endtask
    always @(negedge clk) if(random_ready) begin
        rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
        mr=(rng%4!=0);
    end
    // Oracle uses complete application packets, independently of DUT buffering.
    always @(posedge clk) begin
        if(!rst_n) stalled=0;
        else if(checking) begin
            if(stalled && (!mv || {md,mk,ml,ms,nb,ps,pe}!==held))
                $fatal(1,"Output or metadata changed under backpressure");
            stalled=mv && !mr; held={md,mk,ml,ms,nb,ps,pe};
            if(mv && !mr) begin stalls=stalls+1;stall_mask=stall_mask | (1<<beat);end
            if(mv && mr) begin
                s=ms;
                if(in_packet && ms!==packet_owner) $fatal(1,"Packet interleaved across frames");
                if(pkt[s]>=PACKETS) $fatal(1,"Unexpected extra frame");
                if(beat==0) frame_source=s;
                if(s!=frame_source) $fatal(1,"Source changed inside frame");
                n=lengths[s][pkt[s]]-offset[s];
                expected_count=n>236?236:n;
                if(nb!==8'(expected_count) || ps!==(offset[s]==0) || pe!==(n<=236))
                    $fatal(1,"Frame metadata mismatch src=%0d packet=%0d offset=%0d",s,pkt[s],offset[s]);
                if(mk!==32'hffffffff || ml!==(beat==7)) $fatal(1,"Frame beat framing mismatch");
                for(b=0;b<32;b=b+1) begin
                    pos=beat*32+b;
                    expected_byte=pos<expected_count?value(s,pkt[s],offset[s]+pos):8'b0;
                    if(pos<242 && md[b*8+:8]!==expected_byte)
                        $fatal(1,"Byte mismatch src=%0d packet=%0d frame byte=%0d",s,pkt[s],pos);
                end
                received_frame[beat*256+:256]=md;
                if(beat==7) begin
                    if(!crc_valid(received_frame[1999:0])) $fatal(1,"Frame CRC mismatch");
                    if(received_frame[2047:2000]!==expected_fec(received_frame[1999:0]))
                        $fatal(1,"Frame FEC mismatch");
                    frames=frames+1;beat=0;
                    in_packet=(n>236);packet_owner=ms;
                    if(n<=236) begin pkt[s]=pkt[s]+1;offset[s]=0;done_packets=done_packets+1;end
                    else offset[s]=offset[s]+236;
                end else beat=beat+1;
            end
        end
    end
    task reset_all;
        begin
            @(negedge clk);rst_n=0;sv=0;mr=0;
            repeat(3) @(negedge clk);
            if(mv!==0 || sr!==0) $fatal(1,"Reset outputs not quiescent");
            rst_n=1;
        end
    endtask
    initial begin
        if($value$plusargs("SEED=%d",seed)) begin end
        rng=32'(seed);
        // Interface-level evidence avoids dumping large internal frame registers.
        if($test$plusargs("VCD")) begin $dumpfile("sim/link_tx.vcd");$dumpvars(1,tb_link_tx);end
        sd[0]=0;sd[1]=0;sk[0]=0;sk[1]=0;
        for(integer src=0;src<2;src=src+1) begin
            pkt[src]=0;offset[src]=0;
            for(integer packet=0;packet<PACKETS;packet=packet+1) lengths[src][packet]=size_for(packet);
        end
        reset_all();
        send_beat(0,'1,'1,0);
        repeat(100) @(negedge clk);
        reset_all(); // Discard a partially collected packet.
        send_beat(0,'1,'1,1);
        repeat(100) @(negedge clk);
        if(mv) $fatal(1,"CRC reset scenario missed computation window");
        reset_all(); // Discard a frame during CRC computation.
        send_beat(0,'1,'1,1);
        repeat(400) @(negedge clk);
        if(mv) $fatal(1,"FEC reset scenario missed computation window");
        reset_all(); // Discard a frame during FEC computation.
        send_beat(0,'1,'1,1);
        wait(mv);repeat(4) @(negedge clk);
        reset_all(); // Discard a frame stalled on its first beat.
        send_beat(0,'1,'1,1);
        wait(mv);@(negedge clk);mr=1;
        repeat(4) @(posedge clk);
        @(negedge clk);mr=0;
        reset_all(); // Discard a partially transmitted frame.
        checking=1;random_ready=1;
        fork
            producer(0);
            begin if(!DIRECT) producer(1); end
        join
        wait(done_packets==(DIRECT?PACKETS:2*PACKETS));
        repeat(100) @(negedge clk);
        if(mv || beat!=0 || stalls==0 || stall_mask!=255) $fatal(1,"Drain/stall coverage failure");
        $display("PASS link DIRECT=%0d DEPTH=%0d seed=%0d packets=%0d frames=%0d stalls=%0d stall_mask=%0h",DIRECT,DEPTH,seed,done_packets,frames,stalls,stall_mask);
        $finish;
    end
    initial begin repeat(300000) @(posedge clk);$fatal(1,"Timeout");end
endmodule
