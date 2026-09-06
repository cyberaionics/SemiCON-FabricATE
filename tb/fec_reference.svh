// Independent weighted-sum oracle; GF(256) polynomial is 0x11d, not CRC's 0x12b.
function automatic [7:0] fec_multiply(input [7:0] a,input [7:0] b);
    integer product,i;
    begin
        product=0;
        for(i=0;i<8;i=i+1) if(b[i]) product=product^(int'(a)<<i);
        for(i=14;i>=8;i=i-1) if(product & (1<<i)) product=product^('h11d<<(i-8));
        fec_multiply=8'(product);
    end
endfunction
reg [7:0] fec_power[0:84];
initial begin: init_fec_reference
    fec_power[0]=1;
    for(integer i=1;i<=84;i=i+1) fec_power[i]=fec_multiply(fec_power[i-1],2);
end
function automatic [47:0] expected_fec(input [1999:0] bytes_in);
    reg [7:0] checks[0:2],parities[0:2];
    integer i,g;
    begin
        for(g=0;g<3;g=g+1) begin checks[g]=0;parities[g]=0;end
        for(i=0;i<250;i=i+1) begin
            g=i%3;
            checks[g]=checks[g]^fec_multiply(bytes_in[i*8+:8],fec_power[84-i/3]);
            parities[g]=parities[g]^bytes_in[i*8+:8];
        end
        expected_fec={parities[0],parities[2],parities[1],checks[0],checks[2],checks[1]};
    end
endfunction
