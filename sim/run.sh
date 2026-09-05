#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim/build
command -v iverilog >/dev/null || { echo 'Install Icarus Verilog (iverilog and vvp) first.'; exit 1; }
rtl=(rtl/axis_fifo.sv rtl/packet_rr_arbiter.sv rtl/axis_interconnect_2to1.sv)
{
iverilog -g2012 -Wall -s tb_arbiter -o sim/build/arb rtl/packet_rr_arbiter.sv tb/tb_arbiter.sv
vvp sim/build/arb
for config in '512 4' '512 1' '64 3'; do
    read -r width depth <<< "$config"
    iverilog -g2012 -Wall -s tb_interconnect -Ptb_interconnect.DW="$width" -Ptb_interconnect.DEPTH="$depth" -o sim/build/test "${rtl[@]}" tb/tb_interconnect.sv
    for seed in 12345 67890 314159; do
        vvp sim/build/test +SEED="$seed"
    done
done
# One reproducible default-width waveform.
iverilog -g2012 -s tb_interconnect -o sim/build/default "${rtl[@]}" tb/tb_interconnect.sv
vvp sim/build/default +SEED=12345 +VCD
} 2>&1 | tee sim/results.log
