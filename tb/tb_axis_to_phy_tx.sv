`timescale 1ns/1ps
module tb_axis_to_phy_tx;
    // Clock / reset
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // DUT stimulus (AXI-Stream frame side)
    logic [255:0] s_tdata = '0;
    logic [31:0]  s_tkeep = '0;
    logic         s_tlast = 0;
    logic         s_tvalid = 0;
    wire          s_tready;
    logic         s_source = 0;
    logic [7:0]   s_frame_bytes = 0;
    logic         s_packet_start = 0;
    logic         s_packet_end = 0;

    // DUT observation (bare-beat side)
    wire [255:0] m_data;
    wire         m_valid;
    reg          m_ready = 1;
    wire [31:0]  m_tkeep;
    wire         m_source;
    wire [7:0]   m_frame_bytes;
    wire         m_packet_start;
    wire         m_packet_end;

    integer pass_count = 0;

    axis_to_phy_tx dut (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(s_tdata), .s_tkeep(s_tkeep), .s_tlast(s_tlast),
        .s_tvalid(s_tvalid), .s_tready(s_tready),
        .s_source(s_source), .s_frame_bytes(s_frame_bytes),
        .s_packet_start(s_packet_start), .s_packet_end(s_packet_end),
        .m_data(m_data), .m_valid(m_valid), .m_ready(m_ready),
        .m_tkeep(m_tkeep), .m_source(m_source), .m_frame_bytes(m_frame_bytes),
        .m_packet_start(m_packet_start), .m_packet_end(m_packet_end)
    );

    // Drive one complete 8-beat frame. Producer holds data until accepted.
    task automatic drive_frame(input [255:0] base, input src, input [7:0] fbytes,
                               input pstart, input pend);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                s_tdata <= base + i;
                s_tkeep <= 32'hffffffff;
                s_tlast <= (i == 7);
                s_tvalid <= 1;
                s_source <= src;
                s_frame_bytes <= fbytes;
                s_packet_start <= pstart;
                s_packet_end <= pend;
                @(posedge clk);
                while (!s_tready) @(posedge clk);
                s_tvalid <= 0;
            end
        end
    endtask

    // Collect 8 beats from the DUT output and verify data + metadata.
    // Runs concurrently with drive_frame (forked by the caller).
    task automatic collect_and_check(input [255:0] base, input src, input [7:0] fbytes,
                                     input pstart, input pend);
        integer i;
        reg [255:0] expected;
        begin
            for (i = 0; i < 8; i = i + 1) begin
                while (!m_valid) @(posedge clk);
                expected = base + i;
                if (m_data !== expected)
                    $fatal(1, "FAIL: beat %0d data mismatch expected=%h got=%h", i, expected, m_data);
                if (m_tkeep !== 32'hffffffff)
                    $fatal(1, "FAIL: beat %0d tkeep not all-ones", i);
                if (m_source !== src)
                    $fatal(1, "FAIL: beat %0d source mismatch expected=%b got=%b", i, src, m_source);
                if (m_frame_bytes !== fbytes)
                    $fatal(1, "FAIL: beat %0d frame_bytes mismatch expected=%0d got=%0d", i, fbytes, m_frame_bytes);
                if (m_packet_start !== pstart)
                    $fatal(1, "FAIL: beat %0d packet_start mismatch expected=%b got=%b", i, pstart, m_packet_start);
                if (m_packet_end !== pend)
                    $fatal(1, "FAIL: beat %0d packet_end mismatch expected=%b got=%b", i, pend, m_packet_end);
                @(posedge clk);
            end
            pass_count = pass_count + 1;
            $display("PASS: frame base=%h src=%b bytes=%0d start=%b end=%b", base, src, fbytes, pstart, pend);
        end
    endtask

    // Drive and collect a frame concurrently (register-slice pipeline).
    task automatic run_frame(input [255:0] base, input src, input [7:0] fbytes,
                             input pstart, input pend);
        begin
            fork
                drive_frame(base, src, fbytes, pstart, pend);
                collect_and_check(base, src, fbytes, pstart, pend);
            join
        end
    endtask

    // Backpressure test: hold m_ready low for 3 cycles mid-frame, verify data held.
    task automatic backpressure_test;
        reg [255:0] held_data;
        begin
            // Drive first beat.
            s_tdata <= 256'h1111; s_tkeep <= 32'hffffffff; s_tlast <= 0;
            s_tvalid <= 1; s_source <= 1; s_frame_bytes <= 8'd100;
            s_packet_start <= 1; s_packet_end <= 0;
            @(posedge clk);
            while (!s_tready) @(posedge clk);
            s_tvalid <= 0;
            // Wait for it to appear at output.
            while (!m_valid) @(posedge clk);
            held_data = m_data;
            // Stall the consumer immediately (blocking to affect next edge).
            m_ready = 0;
            @(posedge clk);
            // Check after the stall cycle.
            if (m_data !== held_data)
                $fatal(1, "FAIL: output data changed under backpressure");
            if (m_valid !== 1)
                $fatal(1, "FAIL: output valid dropped under backpressure");
            repeat (2) @(posedge clk);
            // Release and let it drain.
            m_ready = 1;
            @(posedge clk);
            pass_count = pass_count + 1;
            $display("PASS: backpressure held output stable");
        end
    endtask

    initial begin
        $dumpfile("sim/axis_to_phy_tx.vcd");
        $dumpvars(0, tb_axis_to_phy_tx);

        // Reset.
        repeat (3) @(posedge clk);
        rst_n <= 1;
        @(posedge clk);

        // Test 1: full frame, source 0, start packet.
        run_frame(256'h0001_0002_0003_0004_0005_0006_0007_0008, 0, 8'd200, 1, 0);

        // Test 2: full frame, source 1, end packet.
        run_frame(256'hA0B0_C0D0_E0F0_1234_5678_9ABC_DEF0_1111, 1, 8'd42, 0, 1);

        // Test 3: backpressure.
        backpressure_test();

        // Test 4: reset during a frame aborts cleanly.
        fork
            drive_frame(256'hDEAD_BEEF_CAFE_BABE_0000_0000_0000_0000, 0, 8'd10, 1, 0);
        join_none
        // Mid-frame reset.
        repeat (4) @(posedge clk);
        rst_n <= 0;
        repeat (3) @(posedge clk);
        rst_n <= 1;
        @(posedge clk);
        if (m_valid !== 0)
            $fatal(1, "FAIL: m_valid not cleared after reset");
        pass_count = pass_count + 1;
        $display("PASS: reset aborted in-flight beat");

        $display("========================================");
        $display(" AXIS_TO_PHY_TX UNIT TESTS PASSED");
        $display(" CHECKS = %0d", pass_count);
        $display("========================================");
        $finish;
    end

    initial begin repeat (300000) @(posedge clk); $fatal(1, "Timeout"); end
endmodule
