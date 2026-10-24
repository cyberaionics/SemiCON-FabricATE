`timescale 1ns/1ps
`default_nettype none

module tb_link_phy_stress;

    logic clk = 0;
    logic rst_n = 0;

    logic [511:0] s0_data = 0;
    logic [63:0]  s0_keep = 0;
    logic         s0_last = 0;
    logic         s0_valid = 0;
    wire          s0_ready;

    logic [511:0] s1_data = 0;
    logic [63:0]  s1_keep = 0;
    logic         s1_last = 0;
    logic         s1_valid = 0;
    wire          s1_ready;

    wire [255:0] link_data;
    wire [31:0]  link_keep;
    wire         link_last;
    wire         link_valid;
    wire         link_ready;
    wire         link_source;
    wire [7:0]   frame_bytes;
    wire         packet_start;
    wire         packet_end;

    logic phy_rx_detected = 1;
    logic training_done = 1;
    logic link_width_ok = 1;
    logic lane_config_ok = 1;
    logic recovery_request = 0;
    logic phy_error = 0;
    logic disable_request = 0;
    logic hot_reset_request = 0;

    wire [255:0] tx_symbols;
    wire         tx_valid;
    wire [3:0]   tx_lane_valid;

    wire [255:0] rx_data;
    wire         rx_valid;
    logic        rx_ready = 1;

    wire phy_tx_ready;
    wire link_up;
    wire tx_enable, rx_enable, training_enable, recovery_active;
    wire [5:0] ltssm_state;
    wire ltssm_state_changed;

    // 3 packets, each short enough to fit into one frame.
    localparam integer PACKETS = 3;
    logic [255:0] expected [0:23];

    integer sent_beats = 0;
    integer received_beats = 0;
    integer errors = 0;
    integer cycles = 0;
    integer i, j;

    always #5 clk = ~clk;

    axis_link_tx u_link_tx (
        .clk(clk), .rst_n(rst_n),
        .s0_axis_tdata(s0_data), .s0_axis_tkeep(s0_keep),
        .s0_axis_tlast(s0_last), .s0_axis_tvalid(s0_valid),
        .s0_axis_tready(s0_ready),
        .s1_axis_tdata(s1_data), .s1_axis_tkeep(s1_keep),
        .s1_axis_tlast(s1_last), .s1_axis_tvalid(s1_valid),
        .s1_axis_tready(s1_ready),
        .m_axis_tdata(link_data), .m_axis_tkeep(link_keep),
        .m_axis_tlast(link_last), .m_axis_tvalid(link_valid),
        .m_axis_tready(link_ready), .m_axis_source(link_source),
        .m_frame_bytes(frame_bytes), .m_packet_start(packet_start),
        .m_packet_end(packet_end)
    );

    protocol_to_phy_top u_phy (
        .clk(clk), .rst_n(rst_n),
        .phy_rx_detected(phy_rx_detected),
        .training_done(training_done),
        .link_width_ok(link_width_ok),
        .lane_config_ok(lane_config_ok),
        .recovery_request(recovery_request),
        .phy_error(phy_error),
        .disable_request(disable_request),
        .hot_reset_request(hot_reset_request),
        .s_tx_data(link_data), .s_tx_valid(link_valid),
        .s_tx_ready(phy_tx_ready),
        .tx_pam4_symbols(tx_symbols), .tx_valid(tx_valid),
        .tx_lane_valid(tx_lane_valid),
        .rx_pam4_symbols(tx_symbols), .rx_valid(tx_valid),
        .m_rx_data(rx_data), .m_rx_valid(rx_valid),
        .m_rx_ready(rx_ready),
        .link_up(link_up), .tx_enable(tx_enable),
        .rx_enable(rx_enable), .training_enable(training_enable),
        .recovery_active(recovery_active),
        .ltssm_state(ltssm_state),
        .ltssm_state_changed(ltssm_state_changed)
    );

    assign link_ready = phy_tx_ready;

    // Collect the exact frame beats accepted by the PHY transmitter.
    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;

            if (link_valid && link_ready) begin
                if (sent_beats < 24) begin
                    expected[sent_beats] = link_data;
                    sent_beats = sent_beats + 1;
                end else begin
                    $display("FAIL: unexpected extra transmitted beat");
                    errors = errors + 1;
                end

                if (link_keep !== 32'hffff_ffff) begin
                    $display("FAIL: invalid output KEEP");
                    errors = errors + 1;
                end
            end

            if (rx_valid && rx_ready) begin
                if (received_beats >= sent_beats) begin
                    $display("FAIL: RX beat without matching expected beat");
                    errors = errors + 1;
                end else if (rx_data !== expected[received_beats]) begin
                    $display("FAIL: data mismatch on received beat %0d",
                             received_beats);
                    errors = errors + 1;
                end
                received_beats = received_beats + 1;
            end

            if (cycles > 60000)
                $fatal(1, "FAIL: simulation timeout sent=%0d received=%0d",
                       sent_beats, received_beats);
        end
    end

    // Send one 16-byte packet on the selected input.
    task automatic send_packet(input integer source, input integer seed);
        reg [511:0] data_word;
        reg [63:0] keep_word;
        integer k;
        begin
            data_word = 0;
            keep_word = 0;

            for (k = 0; k < 16; k = k + 1) begin
                data_word[k*8 +: 8] = (seed + k) & 8'hff;
                keep_word[k] = 1'b1;
            end

            @(negedge clk);
            if (source == 0) begin
                s0_data = data_word;
                s0_keep = keep_word;
                s0_last = 1;
                s0_valid = 1;
            end else begin
                s1_data = data_word;
                s1_keep = keep_word;
                s1_last = 1;
                s1_valid = 1;
            end

            // Keep the input stable until its handshake.
            if (source == 0) begin
                do @(posedge clk); while (s0_ready !== 1'b1);
                @(negedge clk);
                s0_valid = 0;
                s0_last = 0;
                s0_keep = 0;
                s0_data = 0;
            end else begin
                do @(posedge clk); while (s1_ready !== 1'b1);
                @(negedge clk);
                s1_valid = 0;
                s1_last = 0;
                s1_keep = 0;
                s1_data = 0;
            end
        end
    endtask

    initial begin
        $display("=== Link TX + PHY stress test ===");

        repeat (5) @(negedge clk);
        rst_n = 1;

        wait (link_up === 1'b1);
        repeat (2) @(negedge clk);
        $display("PASS: link reached L0");

        // Three packets, alternating input sources.
        send_packet(0, 8'h10);
        send_packet(1, 8'h40);
        send_packet(0, 8'h70);

        wait (received_beats == 24);
        repeat (3) @(negedge clk);

        if (sent_beats != 24 || received_beats != 24) begin
            $display("FAIL: expected 24 beats, sent=%0d received=%0d",
                     sent_beats, received_beats);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: three packets sent through both input sources");
            $display("PASS: all 24 frame beats matched through PHY loopback");
            $display("ALL LINK-to-PHY STRESS TESTS PASSED");
            $finish;
        end else begin
            $fatal(1, "Stress test failed with %0d error(s)", errors);
        end
    end

endmodule

`default_nettype wire
