`timescale 1ns/1ps
`default_nettype none
// Minimal end-to-end TX integration wrapper.
// Connects axis_link_tx (512-bit AXI-Stream packetizer) to protocol_to_phy_tx
// via axis_to_phy_tx register slice.
//
// Scope: TX only. RX path is not included. LTSSM enable is exposed as an input
// so the wrapper can be used standalone or under protocol_to_phy_top.
//
// Packet metadata (source, frame_bytes, packet_start/end) is preserved through
// axis_to_phy_tx but is not consumed by protocol_to_phy_tx. This is a known
// limitation documented below.
//
// Handshake:
//   axis_link_tx.m_axis_tvalid/tready <-> axis_to_phy_tx.s_tvalid/s_tready
//   axis_to_phy_tx.m_valid/m_ready <-> protocol_to_phy_tx.s_valid/s_ready
// No combinational loops; all paths are registered.
module link_to_phy_tx #(
    parameter integer FIFO_DEPTH = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tx_enable,

    // AXI-Stream ingress (single source for minimal integration; source 1 tied off)
    input  wire [511:0] s_axis_tdata,
    input  wire [63:0]  s_axis_tkeep,
    input  wire         s_axis_tlast,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,

    // PHY TX outputs
    output wire [255:0] tx_pam4_symbols,
    output wire         tx_valid,
    output wire [3:0]   tx_lane_valid,

    // Sideband metadata from packetizer, passed through for observability
    output wire         pkt_source,
    output wire [7:0]   pkt_frame_bytes,
    output wire         pkt_start,
    output wire         pkt_end
);
    // axis_link_tx internal signals
    wire [255:0] link_tdata;
    wire [31:0]  link_tkeep;
    wire         link_tlast;
    wire         link_tvalid;
    wire         link_tready;
    wire         link_source;
    wire [7:0]   link_frame_bytes;
    wire         link_packet_start;
    wire         link_packet_end;

    // Bridge signals
    wire [255:0] bridge_data;
    wire         bridge_valid;
    wire         bridge_ready;
    wire [31:0]  bridge_tkeep;
    wire         bridge_source;
    wire [7:0]   bridge_frame_bytes;
    wire         bridge_packet_start;
    wire         bridge_packet_end;

    // Instantiate axis_link_tx with source 1 tied off
    axis_link_tx #(.FIFO_DEPTH(FIFO_DEPTH)) u_link (
        .clk(clk), .rst_n(rst_n),
        .s0_axis_tdata(s_axis_tdata), .s0_axis_tkeep(s_axis_tkeep),
        .s0_axis_tlast(s_axis_tlast), .s0_axis_tvalid(s_axis_tvalid), .s0_axis_tready(s_axis_tready),
        .s1_axis_tdata(512'b0), .s1_axis_tkeep(64'b0),
        .s1_axis_tlast(1'b0), .s1_axis_tvalid(1'b0), .s1_axis_tready(),
        .m_axis_tdata(link_tdata), .m_axis_tkeep(link_tkeep),
        .m_axis_tlast(link_tlast), .m_axis_tvalid(link_tvalid), .m_axis_tready(link_tready),
        .m_axis_source(link_source), .m_frame_bytes(link_frame_bytes),
        .m_packet_start(link_packet_start), .m_packet_end(link_packet_end)
    );

    // Register slice bridge
    axis_to_phy_tx u_bridge (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(link_tdata), .s_tkeep(link_tkeep), .s_tlast(link_tlast),
        .s_tvalid(link_tvalid), .s_tready(link_tready),
        .s_source(link_source), .s_frame_bytes(link_frame_bytes),
        .s_packet_start(link_packet_start), .s_packet_end(link_packet_end),
        .m_data(bridge_data), .m_valid(bridge_valid), .m_ready(bridge_ready),
        .m_tkeep(bridge_tkeep), .m_source(bridge_source),
        .m_frame_bytes(bridge_frame_bytes),
        .m_packet_start(bridge_packet_start), .m_packet_end(bridge_packet_end)
    );

    // Protocol TX datapath
    protocol_to_phy_tx u_phy_tx (
        .clk(clk), .rst_n(rst_n), .enable(tx_enable),
        .s_data(bridge_data), .s_valid(bridge_valid), .s_ready(bridge_ready),
        .tx_pam4_symbols(tx_pam4_symbols), .tx_valid(tx_valid),
        .tx_lane_valid(tx_lane_valid)
    );

    // Expose metadata for testbench observability
    assign pkt_source       = bridge_source;
    assign pkt_frame_bytes  = bridge_frame_bytes;
    assign pkt_start        = bridge_packet_start;
    assign pkt_end          = bridge_packet_end;
endmodule
`default_nettype wire