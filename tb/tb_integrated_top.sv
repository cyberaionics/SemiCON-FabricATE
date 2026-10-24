`timescale 1ns/1ps
`default_nettype none

// Exercises integrated_link_phy_top itself -- the module that config.mk takes
// through ORFS (DESIGN_NAME) -- rather than a hand-wired copy of its contents.
//
// Scope (what this does and does not show):
//   * Three 16-byte packets: source 0, source 1, source 0 (both inputs used).
//   * Packet 1 runs with m_rx_ready=1; packets 2-3 run with pseudo-random RX
//     backpressure (~50% duty) and are sent back-to-back.
//   * Frame-side signals (KEEP/TLAST/metadata/source) are observed through
//     hierarchical probes of dut.*, because the top does not export them.
//   * RX data is compared against what the TX side presented at the PHY input.
//     This is a loopback self-consistency test, NOT a check of frame contents
//     against a CRC/FEC reference (see tb_link_tx / crc / fec tests for that).
//   * Not covered: LTSSM transitions during traffic, corrupted symbols.
module tb_integrated_top;

    localparam integer NPKT   = 3;
    localparam integer NBEATS = NPKT * 8;

    logic clk   = 0;
    logic rst_n = 0;

    logic [511:0] s0_axis_tdata = '0;
    logic [63:0]  s0_axis_tkeep = '0;
    logic         s0_axis_tlast = 0;
    logic         s0_axis_tvalid = 0;
    wire          s0_axis_tready;

    logic [511:0] s1_axis_tdata = '0;
    logic [63:0]  s1_axis_tkeep = '0;
    logic         s1_axis_tlast = 0;
    logic         s1_axis_tvalid = 0;
    wire          s1_axis_tready;

    logic phy_rx_detected   = 1;
    logic training_done     = 1;
    logic link_width_ok     = 1;
    logic lane_config_ok    = 1;
    logic recovery_request  = 0;
    logic phy_error         = 0;
    logic disable_request   = 0;
    logic hot_reset_request = 0;

    wire [255:0] m_rx_data;
    wire         m_rx_valid;
    logic        m_rx_ready = 1;
    wire         link_up;
    wire [5:0]   ltssm_state;

    integrated_link_phy_top #(.FIFO_DEPTH(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .s0_axis_tdata(s0_axis_tdata), .s0_axis_tkeep(s0_axis_tkeep),
        .s0_axis_tlast(s0_axis_tlast), .s0_axis_tvalid(s0_axis_tvalid),
        .s0_axis_tready(s0_axis_tready),
        .s1_axis_tdata(s1_axis_tdata), .s1_axis_tkeep(s1_axis_tkeep),
        .s1_axis_tlast(s1_axis_tlast), .s1_axis_tvalid(s1_axis_tvalid),
        .s1_axis_tready(s1_axis_tready),
        .phy_rx_detected(phy_rx_detected), .training_done(training_done),
        .link_width_ok(link_width_ok), .lane_config_ok(lane_config_ok),
        .recovery_request(recovery_request), .phy_error(phy_error),
        .disable_request(disable_request), .hot_reset_request(hot_reset_request),
        .m_rx_data(m_rx_data), .m_rx_valid(m_rx_valid), .m_rx_ready(m_rx_ready),
        .link_up(link_up), .ltssm_state(ltssm_state)
    );

    // Hierarchical probes of the frame-side interface inside the DUT.
    wire [255:0] link_data   = dut.link_data;
    wire [31:0]  link_keep   = dut.link_keep;
    wire         link_last   = dut.link_last;
    wire         link_valid  = dut.link_valid;
    wire         link_ready  = dut.link_ready;
    wire         link_source = dut.link_source;
    wire [7:0]   frame_bytes = dut.frame_bytes;
    wire         packet_start = dut.packet_start;
    wire         packet_end   = dut.packet_end;

    always #5 clk = ~clk;

    // ---- RX backpressure generator (deterministic 16-bit LFSR) ----------
    logic        stall_enable = 0;
    logic [15:0] lfsr = 16'hACE1;
    always @(negedge clk) begin
        lfsr       <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        m_rx_ready <= stall_enable ? lfsr[0] : 1'b1;
    end

    // ---- Scoreboard -----------------------------------------------------
    logic [255:0] expected     [0:NBEATS-1];
    logic         expected_src [0:NBEATS-1];
    integer accepted = 0, received = 0, errors = 0, cycles = 0, stalled_cycles = 0;

    logic         prev_stalled = 0;
    logic [255:0] prev_data    = '0;

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;

            if (link_valid && link_ready) begin
                if (accepted < NBEATS) begin
                    expected[accepted]     = link_data;
                    expected_src[accepted] = link_source;
                    if (link_keep !== 32'hffff_ffff) begin
                        $display("FAIL: KEEP mismatch on frame beat %0d", accepted);
                        errors = errors + 1;
                    end
                    if (link_last !== ((accepted % 8) == 7)) begin
                        $display("FAIL: TLAST mismatch on frame beat %0d", accepted);
                        errors = errors + 1;
                    end
                    if (frame_bytes !== 8'd16) begin
                        $display("FAIL: frame_bytes=%0d expected 16 (beat %0d)", frame_bytes, accepted);
                        errors = errors + 1;
                    end
                    if (packet_start !== 1'b1 || packet_end !== 1'b1) begin
                        $display("FAIL: packet start/end metadata incorrect (beat %0d)", accepted);
                        errors = errors + 1;
                    end
                    // packet order: 0 -> src0, 1 -> src1, 2 -> src0
                    if (link_source !== ((accepted / 8) == 1)) begin
                        $display("FAIL: source tag wrong on beat %0d (got %b)", accepted, link_source);
                        errors = errors + 1;
                    end
                    accepted = accepted + 1;
                end else begin
                    $display("FAIL: more than %0d frame beats emitted", NBEATS);
                    errors = errors + 1;
                end
            end

            if (m_rx_valid && m_rx_ready) begin
                if (received >= accepted) begin
                    $display("FAIL: RX beat %0d appeared before TX beat was recorded", received);
                    errors = errors + 1;
                end else if (m_rx_data !== expected[received]) begin
                    $display("FAIL: RX data mismatch at beat %0d", received);
                    $display("      expected = %064h", expected[received]);
                    $display("      received = %064h", m_rx_data);
                    errors = errors + 1;
                end
                received = received + 1;
            end

            // RX output must hold valid and data stable while stalled.
            if (prev_stalled && !(m_rx_valid && m_rx_data === prev_data)) begin
                $display("FAIL: RX output dropped/changed while m_rx_ready was low");
                errors = errors + 1;
            end
            prev_stalled = m_rx_valid && !m_rx_ready;
            prev_data    = m_rx_data;
            if (m_rx_valid && !m_rx_ready) stalled_cycles = stalled_cycles + 1;

            if (cycles > 20000) begin
                $display("FAIL: timeout accepted=%0d received=%0d link_up=%b", accepted, received, link_up);
                $fatal(1, "tb_integrated_top timed out");
            end
        end
    end

    // ---- Stimulus -------------------------------------------------------
    task automatic send_packet(input integer src, input [7:0] base);
        integer n;
        begin
            @(negedge clk);
            for (n = 0; n < 16; n = n + 1) begin
                if (src == 0) s0_axis_tdata[n*8 +: 8] = base + n[7:0];
                else          s1_axis_tdata[n*8 +: 8] = base + n[7:0];
            end
            if (src == 0) begin
                s0_axis_tkeep = 64'h0000_0000_0000_ffff; s0_axis_tlast = 1; s0_axis_tvalid = 1;
                do @(posedge clk); while (!s0_axis_tready);
                @(negedge clk);
                s0_axis_tvalid = 0; s0_axis_tlast = 0; s0_axis_tkeep = 0; s0_axis_tdata = 0;
            end else begin
                s1_axis_tkeep = 64'h0000_0000_0000_ffff; s1_axis_tlast = 1; s1_axis_tvalid = 1;
                do @(posedge clk); while (!s1_axis_tready);
                @(negedge clk);
                s1_axis_tvalid = 0; s1_axis_tlast = 0; s1_axis_tkeep = 0; s1_axis_tdata = 0;
            end
        end
    endtask

    initial begin
        $display("=== integrated_link_phy_top end-to-end test ===");
        repeat (5) @(negedge clk);
        rst_n = 1;
        wait (link_up === 1'b1);
        repeat (3) @(negedge clk);
        $display("PASS: link reached L0 / link_up asserted");

        send_packet(0, 8'h01);              // packet 0, source 0, no stall
        wait (received == 8);
        repeat (2) @(negedge clk);

        stall_enable = 1;                   // packets 1-2 under RX backpressure
        send_packet(1, 8'h81);
        send_packet(0, 8'hC1);
        wait (received == NBEATS);
        repeat (4) @(negedge clk);

        if (accepted != NBEATS) begin
            $display("FAIL: expected %0d TX beats, got %0d", NBEATS, accepted);
            errors = errors + 1;
        end
        if (received != NBEATS) begin
            $display("FAIL: expected %0d RX beats, got %0d", NBEATS, received);
            errors = errors + 1;
        end
        if (stalled_cycles == 0) begin
            $display("FAIL: backpressure never exercised (test is vacuous)");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: %0d beats (3 packets, both sources) matched through top-level loopback", NBEATS);
            $display("PASS: RX backpressure exercised (%0d stalled cycles), no beat lost or reordered", stalled_cycles);
            $display("ALL integrated_link_phy_top TESTS PASSED");
            $finish;
        end else begin
            $fatal(1, "tb_integrated_top failed with %0d error(s)", errors);
        end
    end

endmodule

`default_nettype wire
