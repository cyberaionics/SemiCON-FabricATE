`timescale 1ns/1ps
`default_nettype none
module axis_link_tx #(parameter integer FIFO_DEPTH=4)(
    input wire clk, input wire rst_n,
    input wire [511:0] s0_axis_tdata, input wire [63:0] s0_axis_tkeep,
    input wire s0_axis_tlast, input wire s0_axis_tvalid, output wire s0_axis_tready,
    input wire [511:0] s1_axis_tdata, input wire [63:0] s1_axis_tkeep,
    input wire s1_axis_tlast, input wire s1_axis_tvalid, output wire s1_axis_tready,
    output wire [255:0] m_axis_tdata, output wire [31:0] m_axis_tkeep,
    output wire m_axis_tlast, output wire m_axis_tvalid, input wire m_axis_tready,
    output wire m_axis_source, output wire [7:0] m_frame_bytes,
    output wire m_packet_start, output wire m_packet_end
);
    wire [511:0] data;
    wire [63:0] keep;
    wire last, valid, ready, source;
    axis_interconnect_2to1 #(.DATA_WIDTH(512),.FIFO_DEPTH(FIFO_DEPTH)) switch_inst(
        .clk(clk),.rst_n(rst_n),
        .s0_axis_tdata(s0_axis_tdata),.s0_axis_tkeep(s0_axis_tkeep),
        .s0_axis_tlast(s0_axis_tlast),.s0_axis_tvalid(s0_axis_tvalid),.s0_axis_tready(s0_axis_tready),
        .s1_axis_tdata(s1_axis_tdata),.s1_axis_tkeep(s1_axis_tkeep),
        .s1_axis_tlast(s1_axis_tlast),.s1_axis_tvalid(s1_axis_tvalid),.s1_axis_tready(s1_axis_tready),
        .m_axis_tdata(data),.m_axis_tkeep(keep),.m_axis_tlast(last),
        .m_axis_tvalid(valid),.m_axis_tready(ready),.m_axis_source(source));
    axis_frame_packetizer packetizer(
        .clk(clk),.rst_n(rst_n),.s_axis_tdata(data),.s_axis_tkeep(keep),
        .s_axis_tlast(last),.s_axis_tvalid(valid),.s_axis_tready(ready),.s_axis_source(source),
        .m_axis_tdata(m_axis_tdata),.m_axis_tkeep(m_axis_tkeep),
        .m_axis_tlast(m_axis_tlast),.m_axis_tvalid(m_axis_tvalid),.m_axis_tready(m_axis_tready),
        .m_axis_source(m_axis_source),.m_frame_bytes(m_frame_bytes),
        .m_packet_start(m_packet_start),.m_packet_end(m_packet_end));
endmodule
`default_nettype wire
