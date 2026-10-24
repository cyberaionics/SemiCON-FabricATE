`timescale 1ns/1ps
`default_nettype none

// Recovery sweep: one 8-beat frame in flight, then one LTSSM-disturbing event
// injected after beat AT is accepted, with or without RX backpressure.
//   EVENT: 0=phy_error  1=recovery_request  2=disable_request  3=hot_reset_request
// PASS criterion (data integrity): all 8 beats delivered intact and the TX/RX
// scrambler LFSRs match afterwards.  Separately counts hold violations
// (m_rx_valid withdrawn while stalled); see README "Known limitations".
// Run all 64 combinations with: bash sim/run_recovery_sweep.sh
module tb_recovery_sweep #(parameter EVENT = 0, parameter AT = 3, parameter STALL = 0);


    localparam integer NPKT   = 1;
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
    integer accepted = 0, received = 0, errors = 0, cycles = 0, stalled_cycles = 0, hold_viol = 0;

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
                $display("NOTE: m_rx_valid/data changed while m_rx_ready was low (link teardown)");
                hold_viol = hold_viol + 1;
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


    function automatic lfsr_sync;
        input dummy;
        begin
            lfsr_sync = (dut.u_phy.u_tx.u_scr.lfsr_q[0] === dut.u_phy.u_rx.u_descr.lfsr_q[0]) &&
                        (dut.u_phy.u_tx.u_scr.lfsr_q[1] === dut.u_phy.u_rx.u_descr.lfsr_q[1]) &&
                        (dut.u_phy.u_tx.u_scr.lfsr_q[2] === dut.u_phy.u_rx.u_descr.lfsr_q[2]) &&
                        (dut.u_phy.u_tx.u_scr.lfsr_q[3] === dut.u_phy.u_rx.u_descr.lfsr_q[3]);
        end
    endfunction

    initial begin
        stall_enable = STALL;
        repeat (5) @(negedge clk); rst_n = 1;
        wait (link_up === 1'b1); repeat (3) @(negedge clk);
        send_packet(0, 8'h01);
        wait (accepted == AT);
        @(negedge clk);
        case (EVENT)
            0: begin phy_error = 1;         @(negedge clk); phy_error = 0; end
            1: begin recovery_request = 1;  @(negedge clk); recovery_request = 0; end
            2: begin disable_request = 1;   repeat (4) @(negedge clk); disable_request = 0; end
            3: begin hot_reset_request = 1; repeat (4) @(negedge clk); hot_reset_request = 0; end
        endcase
        repeat (60) @(negedge clk);
        wait (link_up === 1'b1);
        repeat (300) @(negedge clk);
        if (accepted == 8 && received == 8 && errors == 0 && lfsr_sync(1'b0))
            $display("SWEEP ev=%0d at=%0d stall=%0d DATA_OK hold_viol=%0d", EVENT, AT, STALL, hold_viol);
        else
            $display("SWEEP ev=%0d at=%0d stall=%0d DATA_BAD acc=%0d rcv=%0d err=%0d lfsr_sync=%b",
                     EVENT, AT, STALL, accepted, received, errors, lfsr_sync(1'b0));
        $finish;
    end
endmodule
`default_nettype wire
