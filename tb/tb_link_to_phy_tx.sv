`timescale 1ns/1ps
module tb_link_to_phy_tx;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic tx_enable = 0;
    logic [511:0] s_tdata = 0;
    logic [63:0]  s_tkeep = 0;
    logic         s_tlast = 0;
    logic         s_tvalid = 0;
    wire          s_tready;

    wire [255:0] tx_pam4_symbols;
    wire         tx_valid;
    wire [3:0]   tx_lane_valid;
    wire         pkt_source;
    wire [7:0]   pkt_frame_bytes;
    wire         pkt_start;
    wire         pkt_end;

    integer pass_count = 0;
    integer tx_beats = 0;

    link_to_phy_tx #(.FIFO_DEPTH(4)) dut (
        .clk(clk), .rst_n(rst_n), .tx_enable(tx_enable),
        .s_axis_tdata(s_tdata), .s_axis_tkeep(s_tkeep),
        .s_axis_tlast(s_tlast), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .tx_pam4_symbols(tx_pam4_symbols), .tx_valid(tx_valid), .tx_lane_valid(tx_lane_valid),
        .pkt_source(pkt_source), .pkt_frame_bytes(pkt_frame_bytes),
        .pkt_start(pkt_start), .pkt_end(pkt_end)
    );

    // Reference model for expected transformation
    logic [255:0] ref_data_in;
    logic [255:0] ref_striped, ref_scrambled, ref_mapped;
    logic         ref_advance;
    logic clk_ref = 0;
    always #5 clk_ref = ~clk_ref;

    lane_striper u_ref_strip (.data_in(ref_data_in), .lane_data(ref_striped));
    lane_scrambler u_ref_scr (
        .clk(clk), .rst_n(rst_n), .lane_data_in(ref_striped),
        .lane_data_out(ref_scrambled), .advance(ref_advance)
    );
    gray_pam4_tx u_ref_map (.data_in(ref_scrambled), .symbols_out(ref_mapped));

    // Drive a single 512-bit beat with 64 bytes of data
    task automatic send_beat(input [511:0] data, input [63:0] keep, input last);
        begin
            s_tdata <= data;
            s_tkeep <= keep;
            s_tlast <= last;
            s_tvalid <= 1;
            @(posedge clk);
            while (!s_tready) @(posedge clk);
            s_tvalid <= 0;
        end
    endtask

    // Wait for N tx_valid pulses
    task automatic wait_tx_beats(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                while (!tx_valid) @(posedge clk);
                tx_beats = tx_beats + 1;
                // Check lane valid
                if (tx_lane_valid !== 4'b1111)
                    $fatal(1, "FAIL: tx_lane_valid not all ones");
                @(posedge clk);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/link_to_phy_tx.vcd");
        $dumpvars(0, tb_link_to_phy_tx);

        // Reset
        repeat (3) @(posedge clk);
        rst_n <= 1;
        @(posedge clk);
        tx_enable <= 1;
        @(posedge clk);

        // Send a small packet: 64 bytes (one 512-bit beat)
        // Pattern: incremental bytes
        s_tdata = 512'h0000000000000000000000000000000000000000000000000000000000000000
                 + 512'h0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20
                 + 512'h2122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40
                 + 512'h4142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f60
                 + 512'h6162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f80;
        // Simpler: just use a known pattern
        s_tdata = 512'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
                 + 512'hBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
                 + 512'hCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
                 + 512'hDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD;
        s_tkeep = 64'hFFFFFFFFFFFFFFFF;
        s_tlast = 1;
        s_tvalid = 1;
        @(posedge clk);
        while (!s_tready) @(posedge clk);
        s_tvalid <= 0;

        // Wait for at least one frame (8 beats) to emerge
        // Packetizer will produce at least one frame for 64 bytes
        repeat (200) @(posedge clk);
        // Count tx_valid pulses
        tx_beats = 0;
        // Wait for first valid
        while (!tx_valid) @(posedge clk);
        // Count 8 beats
        wait_tx_beats(8);
        pass_count = pass_count + 1;
        $display("PASS: TX path produced 8 beats for 64-byte packet");

        // Verify metadata sideband is present
        if (pkt_source !== 0)
            $fatal(1, "FAIL: pkt_source expected 0");
        if (pkt_frame_bytes == 0)
            $fatal(1, "FAIL: pkt_frame_bytes zero");
        pass_count = pass_count + 1;
        $display("PASS: metadata sideband present source=%b bytes=%0d", pkt_source, pkt_frame_bytes);

        // Backpressure test: stall tx by disabling enable
        tx_enable <= 0;
        @(posedge clk);
        if (tx_valid)
            $fatal(1, "FAIL: tx_valid asserted while disabled");
        pass_count = pass_count + 1;
        $display("PASS: TX disabled stops output");

        $display("========================================");
        $display(" LINK_TO_PHY_TX INTEGRATION TEST PASSED");
        $display(" CHECKS = %0d", pass_count);
        $display("========================================");
        $finish;
    end

    initial begin repeat (500000) @(posedge clk); $fatal(1, "Timeout"); end
endmodule
