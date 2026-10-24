`timescale 1ns/1ps
`default_nettype none

module integrated_link_phy_top #(
    parameter integer FIFO_DEPTH = 4
) (
    input  logic clk,
    input  logic rst_n,

    // AXI source 0
    input  logic [511:0] s0_axis_tdata,
    input  logic [63:0]  s0_axis_tkeep,
    input  logic         s0_axis_tlast,
    input  logic         s0_axis_tvalid,
    output logic         s0_axis_tready,

    // AXI source 1
    input  logic [511:0] s1_axis_tdata,
    input  logic [63:0]  s1_axis_tkeep,
    input  logic         s1_axis_tlast,
    input  logic         s1_axis_tvalid,
    output logic         s1_axis_tready,

    // PHY / link controls
    input logic phy_rx_detected,
    input logic training_done,
    input logic link_width_ok,
    input logic lane_config_ok,
    input logic recovery_request,
    input logic phy_error,
    input logic disable_request,
    input logic hot_reset_request,

    // Received data stream
    output logic [255:0] m_rx_data,
    output logic         m_rx_valid,
    input  logic         m_rx_ready,

    // Link status
    output logic         link_up,
    output logic [5:0]   ltssm_state
);

    // Interconnect + packetizer output
    wire [255:0] link_data;
    wire [31:0]  link_keep;
    wire         link_last;
    wire         link_valid;
    wire         link_ready;
    wire         link_source;
    wire [7:0]   frame_bytes;
    wire         packet_start;
    wire         packet_end;

    // Digital PHY signals
    wire [255:0] tx_symbols;
    wire         tx_valid;
    wire [3:0]   tx_lane_valid;
    wire [255:0] rx_symbols;

    wire         phy_tx_ready;
    wire         tx_enable;
    wire         rx_enable;
    wire         training_enable;
    wire         recovery_active;
    wire         ltssm_state_changed;

    axis_link_tx #(
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_link_tx (
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

    // Prototype digital loopback: no physical SerDes or channel modeled.
    assign rx_symbols = tx_symbols;

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

        .rx_pam4_symbols(rx_symbols),
        .rx_valid(tx_valid),

        .m_rx_data(m_rx_data),
        .m_rx_valid(m_rx_valid),
        .m_rx_ready(m_rx_ready),

        .link_up(link_up),
        .tx_enable(tx_enable),
        .rx_enable(rx_enable),
        .training_enable(training_enable),
        .recovery_active(recovery_active),
        .ltssm_state(ltssm_state),
        .ltssm_state_changed(ltssm_state_changed)
    );

    assign link_ready = phy_tx_ready;

endmodule

`default_nettype wire
