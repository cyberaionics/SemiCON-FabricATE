`timescale 1ns/1ps
`default_nettype none
// Locks on presentation, including a stalled first beat. Unlocks on accepted LAST.
module packet_rr_arbiter(
    input wire clk, input wire rst_n,
    input wire [1:0] request,
    input wire beat_accepted, input wire selected_last,
    output wire selected
);
    reg locked, owner, next_priority;
    assign selected=locked ? owner :
        ((request==2'b11)?next_priority:(request[1]?1'b1:1'b0));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin locked<=0; owner<=0; next_priority<=0; end
        else if (request[selected]) begin
            if(beat_accepted && selected_last) begin
                locked<=0; next_priority<=~selected;
            end else begin locked<=1; owner<=selected; end
        end
    end
endmodule
`default_nettype wire
