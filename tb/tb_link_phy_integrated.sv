`timescale 1ns/1ps
`default_nettype none

module tb_link_phy_integrated;

    logic clk = 0;
    logic rst_n = 0;

    // AXI input: source 0
    logic [511:0] s0_axis_tdata = '0;
    logic [63:0]  s0_axis_tkeep = '0;
    logic         s0_axis_tlast = 0;
    logic         s0_axis_tvalid = 0;
    wire          s0_axis_tready;

    // AXI input: source 1 (unused in this first test)
    logic [511:0] s1_axis_tdata = '0;
    logic [63:0]  s1_axis_tkeep = '0;
    logic         s1_axis_tlast = 0;
    logic         s1_axis_tvalid = 0;
    wire          s1_axis_tready;

    // Packetizer / link-transmit output
    wire [255:0] link_data;
    wire [31:0]  link_keep;
    wire         link_last;
    wire         link_valid;
    wire         link_ready;
    wire         link_source;
    wire [7:0]   frame_bytes;
    wire         packet_start;
    wire         packet_end;

    // PHY control inputs
    logic phy_rx_detected = 1;
    logic training_done = 1;
    logic link_width_ok = 1;
    logic lane_config_ok = 1;
    logic recovery_request = 0;
    logic phy_error = 0;
    logic disable_request = 0;
    logic hot_reset_request = 0;

    // PHY transmit / receive signals
    wire [255:0] tx_symbols;
    wire         tx_valid;
    wire [3:0]   tx_lane_valid;

    wire [255:0] rx_data;
    wire         rx_valid;
    logic        rx_ready = 1;

    wire         phy_tx_ready;
    wire         link_up;
    wire         tx_enable;
    wire         rx_enable;
    wire         training_enable;
    wire         recovery_active;
    wire [5:0]   ltssm_state;
    wire         ltssm_state_changed;

    // Scoreboard: expected frame beats captured from axis_link_tx.
    logic [255:0] expected [0:7];
    integer accepted = 0;
    integer received = 0;
    integer errors = 0;
    integer cycles = 0;
    integer i;

    always #5 clk = ~clk;

    // Existing two-input AXI interconnect + packetizer + CRC/FEC transmitter.
    axis_link_tx u_link_tx (
        .clk(clk),
        .rst_n(rst_n),

        .s0_axis_tdata(s0_axis_tdata),
        .s0_axis_tkeep(s0_axis_tkeep),
        .s0_axis_tlast(s0_axis_tlast),
        .s0_axis_tvalid(s0_axis_tvalid),
        .s0_axis_tready(s0_axis_tready),

        .s1_axis_tdata(s1_axis_tdata),
        .s1_axis_tkeep(s1_axis_tkeep),
        .s1_axis_tlast(s1_axis_tlast),
        .s1_axis_tvalid(s1_axis_tvalid),
        .s1_axis_tready(s1_axis_tready),

        .m_axis_tdata(link_data),
        .m_axis_tkeep(link_keep),
        .m_axis_tlast(link_last),
        .m_axis_tvalid(link_valid),
        .m_axis_tready(link_ready),
        .m_axis_source(link_source),
        .m_frame_bytes(frame_bytes),
        .m_packet_start(packet_start),
        .m_packet_end(packet_end)
    );

    // Existing digital PHY, with ideal symbol-level loopback.
    protocol_to_phy_top u_phy (
        .clk(clk),
        .rst_n(rst_n),

        .phy_rx_detected(phy_rx_detected),
        .training_done(training_done),
        .link_width_ok(link_width_ok),
        .lane_config_ok(lane_config_ok),
        .recovery_request(recovery_request),
        .phy_error(phy_error),
        .disable_request(disable_request),
        .hot_reset_request(hot_reset_request),

        .s_tx_data(link_data),
        .s_tx_valid(link_valid),
        .s_tx_ready(phy_tx_ready),

        .tx_pam4_symbols(tx_symbols),
        .tx_valid(tx_valid),
        .tx_lane_valid(tx_lane_valid),

        .rx_pam4_symbols(tx_symbols),
        .rx_valid(tx_valid),

        .m_rx_data(rx_data),
        .m_rx_valid(rx_valid),
        .m_rx_ready(rx_ready),

        .link_up(link_up),
        .tx_enable(tx_enable),
        .rx_enable(rx_enable),
        .training_enable(training_enable),
        .recovery_active(recovery_active),
        .ltssm_state(ltssm_state),
        .ltssm_state_changed(ltssm_state_changed)
    );

    // Connect the PHY's input-ready signal back to the packetizer output.
    assign link_ready = phy_tx_ready;

    // Capture accepted link-frame beats and compare the received data.
    // Sampling at the rising edge observes values before nonblocking updates.
    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;

            if (link_valid && link_ready) begin
                if (accepted < 8) begin
                    expected[accepted] = link_data;

                    if (link_keep !== 32'hffff_ffff) begin
                        $display("FAIL: KEEP mismatch on frame beat %0d", accepted);
                        errors = errors + 1;
                    end

                    if (link_last !== (accepted == 7)) begin
                        $display("FAIL: TLAST mismatch on frame beat %0d", accepted);
                        errors = errors + 1;
                    end

                    if (frame_bytes !== 8'd16) begin
                        $display("FAIL: frame_bytes=%0d, expected 16", frame_bytes);
                        errors = errors + 1;
                    end

                    if (packet_start !== 1'b1 || packet_end !== 1'b1) begin
                        $display("FAIL: packet start/end metadata incorrect");
                        errors = errors + 1;
                    end

                    accepted = accepted + 1;
                end else begin
                    $display("FAIL: more than eight frame beats emitted");
                    errors = errors + 1;
                end
            end

            if (rx_valid && rx_ready) begin
                if (received >= accepted) begin
                    $display("FAIL: received data before expected beat was recorded");
                    errors = errors + 1;
                end else if (rx_data !== expected[received]) begin
                    $display("FAIL: RX data mismatch at beat %0d", received);
                    $display("      expected = %064h", expected[received]);
                    $display("      received = %064h", rx_data);
                    errors = errors + 1;
                end

                received = received + 1;
            end

            if (cycles > 20000) begin
                $display("FAIL: timeout. accepted=%0d received=%0d link_up=%b",
                         accepted, received, link_up);
                $fatal(1, "Integration test timed out");
            end
        end
    end

    initial begin
        $display("=== Link TX to digital PHY integration test ===");

        // Reset all connected RTL together.
        repeat (5) @(negedge clk);
        rst_n = 1;

        // Wait for the LTSSM to bring the link up.
        wait (link_up === 1'b1);
        repeat (3) @(negedge clk);

        $display("PASS: link reached L0 / link_up asserted");

        // Send one 16-byte application packet through source 0.
        // Bytes are stored in increasing TDATA lane order.
        for (i = 0; i < 16; i = i + 1)
            s0_axis_tdata[i*8 +: 8] = i + 1;

        s0_axis_tkeep = 64'h0000_0000_0000_ffff;
        s0_axis_tlast = 1;
        s0_axis_tvalid = 1;

        // Hold VALID and payload until the input handshake occurs.
        do @(posedge clk); while (!s0_axis_tready);

        @(negedge clk);
        s0_axis_tvalid = 0;
        s0_axis_tlast = 0;
        s0_axis_tkeep = 0;
        s0_axis_tdata = 0;

        // Wait for the complete eight-beat frame to emerge from the receiver.
        wait (received == 8);
        repeat (2) @(negedge clk);

        if (accepted != 8) begin
            $display("FAIL: expected 8 transmitted frame beats, got %0d", accepted);
            errors = errors + 1;
        end

        if (received != 8) begin
            $display("FAIL: expected 8 received beats, got %0d", received);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: all eight 256-bit frame beats survived PHY loopback");
            $display("PASS: frame length, KEEP, TLAST, and packet metadata checked");
            $display("ALL LINK-to-PHY INTEGRATION TESTS PASSED");
            $finish;
        end else begin
            $fatal(1, "Integration test failed with %0d error(s)", errors);
        end
    end

endmodule

`default_nettype wire
