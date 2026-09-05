`timescale 1ns/1ps
`default_nettype none
// Small synchronous FIFO. Asynchronous read intentionally favors portability.
// DEPTH >= 1; no combinational path from downstream READY to upstream READY.
module axis_fifo #(
    parameter integer DATA_WIDTH=512,
    parameter integer DEPTH=4,
    parameter integer KEEP_WIDTH=DATA_WIDTH/8
)(
    input wire clk, input wire rst_n,
    input wire [DATA_WIDTH-1:0] s_data,
    input wire [KEEP_WIDTH-1:0] s_keep,
    input wire s_last, input wire s_source,
    input wire s_valid, output wire s_ready,
    output wire [DATA_WIDTH-1:0] m_data,
    output wire [KEEP_WIDTH-1:0] m_keep,
    output wire m_last, output wire m_source,
    output wire m_valid, input wire m_ready
);
    localparam integer PW=(DEPTH<2)?1:$clog2(DEPTH);
    localparam integer CW=$clog2(DEPTH+1);
    localparam integer WIDTH=DATA_WIDTH+KEEP_WIDTH+2;
    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [PW-1:0] wr_ptr, rd_ptr;
    reg [CW-1:0] count;
    wire push=s_valid && s_ready;
    wire pop=m_valid && m_ready;
    assign s_ready=rst_n && (count<CW'(DEPTH));
    assign m_valid=rst_n && (count!=0);
    assign {m_source,m_last,m_keep,m_data}=m_valid?mem[rd_ptr]:{WIDTH{1'b0}};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr<=0; rd_ptr<=0; count<=0;
        end else begin
            if(push) begin
                mem[wr_ptr]<={s_source,s_last,s_keep,s_data};
                if(wr_ptr==PW'(DEPTH-1)) wr_ptr<=0; else wr_ptr<=wr_ptr+1'b1;
            end
            if(pop) begin
                if(rd_ptr==PW'(DEPTH-1)) rd_ptr<=0; else rd_ptr<=rd_ptr+1'b1;
            end
            case({push,pop})
                2'b10: count<=count+1'b1;
                2'b01: count<=count-1'b1;
                default: count<=count;
            endcase
        end
    end
endmodule
`default_nettype wire
