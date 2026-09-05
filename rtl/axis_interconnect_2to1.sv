`timescale 1ns/1ps
`default_nettype none
module axis_interconnect_2to1 #(
    parameter integer DATA_WIDTH=512,
    parameter integer FIFO_DEPTH=4,
    parameter integer KEEP_WIDTH=DATA_WIDTH/8
)(
    input wire clk, input wire rst_n,
    input wire [DATA_WIDTH-1:0] s0_axis_tdata,
    input wire [KEEP_WIDTH-1:0] s0_axis_tkeep,
    input wire s0_axis_tlast, input wire s0_axis_tvalid,
    output wire s0_axis_tready,
    input wire [DATA_WIDTH-1:0] s1_axis_tdata,
    input wire [KEEP_WIDTH-1:0] s1_axis_tkeep,
    input wire s1_axis_tlast, input wire s1_axis_tvalid,
    output wire s1_axis_tready,
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire [KEEP_WIDTH-1:0] m_axis_tkeep,
    output wire m_axis_tlast, output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_source
);
    wire [DATA_WIDTH-1:0] d0,d1;
    wire [KEEP_WIDTH-1:0] k0,k1;
    wire l0,l1,v0,v1,r0,r1,sel,out_ready,sel_valid,sel_last;
    axis_fifo #(.DATA_WIDTH(DATA_WIDTH),.DEPTH(FIFO_DEPTH)) f0(
        .clk(clk),.rst_n(rst_n),.s_data(s0_axis_tdata),.s_keep(s0_axis_tkeep),
        .s_last(s0_axis_tlast),.s_source(1'b0),.s_valid(s0_axis_tvalid),.s_ready(s0_axis_tready),
        .m_data(d0),.m_keep(k0),.m_last(l0),.m_source(),.m_valid(v0),.m_ready(r0));
    axis_fifo #(.DATA_WIDTH(DATA_WIDTH),.DEPTH(FIFO_DEPTH)) f1(
        .clk(clk),.rst_n(rst_n),.s_data(s1_axis_tdata),.s_keep(s1_axis_tkeep),
        .s_last(s1_axis_tlast),.s_source(1'b1),.s_valid(s1_axis_tvalid),.s_ready(s1_axis_tready),
        .m_data(d1),.m_keep(k1),.m_last(l1),.m_source(),.m_valid(v1),.m_ready(r1));
    assign sel_valid=sel?v1:v0;
    assign sel_last=sel?l1:l0;
    assign r0=out_ready && !sel;
    assign r1=out_ready && sel;
    packet_rr_arbiter arb(.clk(clk),.rst_n(rst_n),.request({v1,v0}),
        .beat_accepted(sel_valid && out_ready),.selected_last(sel_last),.selected(sel));
    axis_fifo #(.DATA_WIDTH(DATA_WIDTH),.DEPTH(2)) output_fifo(
        .clk(clk),.rst_n(rst_n),.s_data(sel?d1:d0),.s_keep(sel?k1:k0),
        .s_last(sel_last),.s_source(sel),.s_valid(sel_valid),.s_ready(out_ready),
        .m_data(m_axis_tdata),.m_keep(m_axis_tkeep),.m_last(m_axis_tlast),
        .m_source(m_axis_source),.m_valid(m_axis_tvalid),.m_ready(m_axis_tready));
endmodule
`default_nettype wire
