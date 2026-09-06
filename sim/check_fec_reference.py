"""Optional comparison with user-supplied PCIe Appendix J encoder files."""
from pathlib import Path
import argparse
import os
import re
import shutil
import subprocess
from fec_vectors import generate_fec_vectors

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
parser = argparse.ArgumentParser()
parser.add_argument('reference_directory', type=Path)
args = parser.parse_args()
generate_fec_vectors()
build = ROOT/'sim'/'build'/'fec_reference'
build.mkdir(exist_ok=True)
for name in ['ecc_250to256_encoder.sv', 'ecc_84to86_encoder.sv']:
    shutil.copyfile(args.reference_directory/name, build/name)
# Icarus does not support this unpacked localparam assignment pattern.
# Preserve every lookup value; change only the declaration to constant wires.
raw = (args.reference_directory/'alpha_powers.vh').read_text()
values = re.findall(r"8'h([0-9a-fA-F]{2})", raw.split('};', 1)[0])
if len(values) != 256:
    raise SystemExit('Expected the reference descending [255:0] alpha table.')
(build/'alpha_powers.vh').write_text(
    'wire [7:0] i_to_alpha_power_i[255:0];\n' + ''.join(
        f"assign i_to_alpha_power_i[{255-i}]=8'h{v};\n" for i,v in enumerate(values)))
(build/'test.sv').write_text('''
module test;
reg [1999:0] input_frame;
wire [7:0] data_in[249:0];
wire [7:0] data_out[255:0];
reg [1999:0] messages[0:2031];
reg [47:0] expected[0:2031];
genvar b;
generate for(b=0;b<250;b=b+1) begin
assign data_in[b]=input_frame[b*8+:8];
end endgenerate
ecc_250to256_encoder reference_encoder(data_in,data_out);
initial begin
    $readmemh("sim/build/fec_data.hex",messages);
    $readmemh("sim/build/fec_expected.hex",expected);
    for(integer v=0;v<2032;v=v+1) begin
        input_frame=messages[v];#1;
        for(integer i=0;i<250;i=i+1)
            if(data_out[i]!==messages[v][i*8+:8]) $fatal(1,"Reference changed data");
        for(integer i=0;i<6;i=i+1)
            if(data_out[250+i]!==expected[v][i*8+:8])
                $fatal(1,"Reference mismatch vector=%0d byte=%0d",v,i);
    end
    $display("PASS Appendix J reference encoder matches all 2032 FEC vectors");
    $finish;
end
endmodule
''')
local_bin=ROOT/'.tools'/'mingw64'/'bin'
if local_bin.exists():
    os.environ['PATH']=str(local_bin)+os.pathsep+os.environ.get('PATH','')
    os.environ['PATH']+=os.pathsep+'C:/msys64/mingw64/bin'
binary=build/'test'
result=subprocess.run(['iverilog','-g2012','-s','test','-I',str(build),'-o',str(binary),
    str(build/'test.sv'), str(build/'ecc_250to256_encoder.sv'), str(build/'ecc_84to86_encoder.sv')],
    capture_output=True,text=True,timeout=60)
(build/'compile.log').write_text(result.stdout+result.stderr)
if result.returncode:
    raise SystemExit(result.stdout+result.stderr)
result=subprocess.run(['vvp',str(binary)],capture_output=True,text=True,timeout=60)
if result.returncode or 'PASS ' not in result.stdout:
    raise SystemExit(result.stdout+result.stderr)
report=result.stdout+'Reference compatibility change: constant alpha table declaration only.\n'
(ROOT/'sim'/'fec_reference_results.log').write_text(report)
print(report,end='')
