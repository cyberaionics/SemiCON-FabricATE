`timescale 1ns/1ps
`default_nettype none
// Boundary register slice: 256-bit AXI-Stream frame output of axis_link_tx
// (axis_frame_packetizer) to the bare 256-bit beat interface of protocol_to_phy_tx.
//
// The packetizer emits exactly eight 256-bit transfers per prototype frame and
// repeats frame metadata (source, frame_bytes, packet_start, packet_end) on every
// transfer. protocol_to_phy_tx has no concept of frames or metadata; it accepts one
// 256-bit block per handshake and presents tx_valid one cycle later with a one-cycle
// bubble between accepted beats.
//
// This module is a pure skid register: it never combines or reorders beats, never
// drops metadata, and exposes the frame metadata on sideband outputs so a top level
// or checker can still observe packet boundaries downstream of protocol_to_phy_tx.
//
// Handshake contract (AXI-Stream register slice):
//   * s_tready is combinational: asserted when the slice is empty or the downstream
//     consumer is draining. It never depends combinationally on s_tvalid.
//   * Data and all metadata are held stable while the slice is full and stalled.
//   * Reset aborts the in-flight beat; the packetizer is reset at the same time.
module axis_to_phy_tx(
    input  wire        clk,
    input  wire        rst_n,

    // From axis_link_tx / axis_frame_packetizer (256-bit AXI-Stream frame output).
    input  wire [255:0] s_tdata,
    input  wire [31:0]  s_tkeep,
    input  wire         s_tlast,
    input  wire         s_tvalid,
    output wire         s_tready,
    input  wire         s_source,
    input  wire [7:0]   s_frame_bytes,
    input  wire         s_packet_start,
    input  wire         s_packet_end,

    // To protocol_to_phy_tx (bare 256-bit beat interface).
    output wire [255:0] m_data,
    output wire         m_valid,
    input  wire         m_ready,

    // Frame metadata sideband, aligned to m_data/m_valid. Meaningful only while
    // m_valid is asserted; repeated on every transfer of the frame.
    output wire [31:0]  m_tkeep,
    output wire         m_source,
    output wire [7:0]   m_frame_bytes,
    output wire         m_packet_start,
    output wire         m_packet_end
);
    reg               valid_q;
    reg [255:0]       data_q;
    reg [31:0]        keep_q;
    reg               last_q;
    reg               source_q;
    reg [7:0]         frame_bytes_q;
    reg               packet_start_q;
    reg               packet_end_q;

    // Accept a new beat when the slice is empty, or when the downstream consumer
    // is draining this beat in the same cycle. No combinational loop: s_tready
    // depends on valid_q and m_ready, never on s_tvalid.
    assign s_tready = !valid_q || m_ready;

    assign m_data         = data_q;
    assign m_valid        = valid_q;
    assign m_tkeep        = keep_q;
    assign m_source       = source_q;
    assign m_frame_bytes  = frame_bytes_q;
    assign m_packet_start = packet_start_q;
    assign m_packet_end   = packet_end_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_q <= 1'b0;
        end else if (s_tvalid && s_tready) begin
            // Upstream fires: load the new beat, including all metadata.
            data_q         <= s_tdata;
            keep_q         <= s_tkeep;
            last_q         <= s_tlast;
            source_q       <= s_source;
            frame_bytes_q  <= s_frame_bytes;
            packet_start_q <= s_packet_start;
            packet_end_q   <= s_packet_end;
            valid_q        <= 1'b1;
        end else if (m_ready) begin
            // Downstream drained and no new beat arrived: release the slice.
            valid_q <= 1'b0;
        end
    end
endmodule
`default_nettype wire