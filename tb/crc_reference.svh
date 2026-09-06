// Independent verification arithmetic: log/antilog lookup and root evaluation.
// Does not use DUT generator coefficients or its feedback recurrence.
integer gf_log[0:255];
reg [7:0] gf_exp[0:509];
initial begin: init_reference_field
    integer v,i;
    v=1;gf_log[0]=0;
    for(i=0;i<255;i=i+1) begin
        gf_exp[i]=8'(v);gf_log[v]=i;
        v=v<<1;if(v&256) v=v^'h12b;
    end
    for(i=255;i<510;i=i+1) gf_exp[i]=gf_exp[i-255];
end
function automatic [7:0] ref_multiply(input [7:0] a,input [7:0] b);
    ref_multiply=(a==0 || b==0)?8'b0:gf_exp[gf_log[a]+gf_log[b]];
endfunction
function automatic crc_valid(input [1999:0] frame);
    integer root,i;
    reg [7:0] syndrome;
    begin
        crc_valid=1;
        for(root=1;root<=8;root=root+1) begin
            syndrome=0;
            for(i=0;i<242;i=i+1)
                syndrome=ref_multiply(syndrome,gf_exp[root])^frame[i*8+:8];
            // Wire carries r0 first; polynomial evaluation needs r7 first.
            for(i=249;i>=242;i=i-1)
                syndrome=ref_multiply(syndrome,gf_exp[root])^frame[i*8+:8];
            if(syndrome!==0) crc_valid=0;
        end
    end
endfunction
