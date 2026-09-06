`timescale 1ns/1ps
`default_nettype none
// Stage 1 prototype: application bytes, NOT encoded PCIe TLPs.
// Byte-serial collector trades throughput for small, straightforward control.
module axis_frame_packetizer(
    input wire clk, input wire rst_n,
    input wire [511:0] s_axis_tdata,
    input wire [63:0] s_axis_tkeep,
    input wire s_axis_tlast, input wire s_axis_tvalid,
    output wire s_axis_tready, input wire s_axis_source,
    output wire [255:0] m_axis_tdata,
    output wire [31:0] m_axis_tkeep,
    output wire m_axis_tlast, output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire m_axis_source,
    output wire [7:0] m_frame_bytes,
    output wire m_packet_start, output wire m_packet_end
);
    localparam [2:0] COLLECT=0, SCAN=1, FINISH=2, CRC=3, FEC=4, EMIT=5;
    reg [2:0] state;
    reg [511:0] beat_data;
    reg [63:0] beat_keep;
    reg beat_last;
    reg [5:0] lane;
    reg [1887:0] payload;
    reg [7:0] byte_count;
    reg [2:0] out_beat;
    reg source, packet_active, first_frame, final_frame;
    reg [7:0] crc_index;
    reg [7:0] fec_index;
    wire [1935:0] protected_data={48'b0,payload};
    wire [63:0] crc;
    flit_crc8 crc_engine(.clk(clk),.rst_n(rst_n),
        .clear(state!=CRC && state!=FEC && state!=EMIT),.enable(state==CRC),
        .data(protected_data[crc_index*8 +: 8]),.crc(crc));
    wire [1999:0] fec_data={crc,protected_data};
    wire [47:0] fec;
    flit_fec6 fec_engine(.clk(clk),.rst_n(rst_n),
        .clear(state!=FEC && state!=EMIT),.enable(state==FEC),
        .data(fec_data[fec_index*8+:8]),.fec(fec));
    wire [2047:0] frame_data={fec,fec_data};
    assign s_axis_tready=rst_n && state==COLLECT;
    assign m_axis_tvalid=rst_n && state==EMIT;
    assign m_axis_tdata=m_axis_tvalid ? frame_data[out_beat*256 +: 256] : 256'b0;
    assign m_axis_tkeep=m_axis_tvalid ? 32'hffffffff : 32'b0;
    assign m_axis_tlast=m_axis_tvalid && out_beat==7;
    assign m_axis_source=source;
    assign m_frame_bytes=byte_count;
    assign m_packet_start=first_frame;
    assign m_packet_end=final_frame;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=COLLECT; beat_data<=0; beat_keep<=0; beat_last<=0;
            lane<=0; payload<=0; byte_count<=0; out_beat<=0;crc_index<=0;fec_index<=0;
            source<=0; packet_active<=0; first_frame<=1; final_frame<=0;
        end else begin
            case(state)
                COLLECT: if(s_axis_tvalid) begin
                    beat_data<=s_axis_tdata; beat_keep<=s_axis_tkeep;
                    beat_last<=s_axis_tlast; lane<=0; state<=SCAN;
                    if(!packet_active) begin
                        source<=s_axis_source; packet_active<=1;
                    end
                end
                SCAN: begin
                    // Retain a full frame until another valid byte or packet end.
                    // This avoids an extra empty frame at exact multiples of 236.
                    if(beat_keep[lane] && byte_count==236) begin
                        final_frame<=0; out_beat<=0;crc_index<=0;state<=CRC;
                    end else begin
                        if(beat_keep[lane]) begin
                            payload[byte_count*8 +: 8]<=beat_data[lane*8 +: 8];
                            byte_count<=byte_count+1'b1;
                        end
                        if(lane==63) state<=FINISH;
                        else lane<=lane+1'b1;
                    end
                end
                FINISH: begin
                    if(beat_last) begin
                        final_frame<=1; out_beat<=0;crc_index<=0;state<=CRC;
                    end else state<=COLLECT;
                end
                CRC: begin
                    if(crc_index==241) begin state<=FEC;fec_index<=0;end
                    else crc_index<=crc_index+1'b1;
                end
                FEC: begin
                    if(fec_index==249) state<=EMIT;
                    else fec_index<=fec_index+1'b1;
                end
                EMIT: if(m_axis_tready) begin
                    if(out_beat==7) begin
                        payload<=0; byte_count<=0; out_beat<=0;
                        if(final_frame) begin
                            state<=COLLECT; packet_active<=0;
                            first_frame<=1; final_frame<=0;
                        end else begin
                            state<=SCAN; first_frame<=0;
                        end
                    end else out_beat<=out_beat+1'b1;
                end
                default: state<=COLLECT;
            endcase
        end
    end
endmodule
`default_nettype wire
