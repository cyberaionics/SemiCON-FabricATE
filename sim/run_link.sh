#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim/build
rtl=(rtl/axis_fifo.sv rtl/packet_rr_arbiter.sv rtl/axis_interconnect_2to1.sv rtl/flit_crc8.sv rtl/flit_fec6.sv rtl/axis_frame_packetizer.sv rtl/axis_link_tx.sv)
{
for config in '1 4' '0 4' '0 1' '0 3'; do
    read -r direct depth <<< "$config"
    iverilog -g2012 -Wall -s tb_link_tx -Ptb_link_tx.DIRECT="$direct" -Ptb_link_tx.DEPTH="$depth" -o sim/build/link "${rtl[@]}" tb/tb_link_tx.sv
    for seed in 12345 67890 314159; do
        vvp sim/build/link +SEED="$seed"
    done
done
vvp sim/build/link +SEED=12345 +VCD
} 2>&1 | tee sim/link_results.log
