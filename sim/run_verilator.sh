#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim/build
VERILATOR=${VERILATOR:-verilator}
rtl=(rtl/axis_fifo.sv rtl/packet_rr_arbiter.sv rtl/axis_interconnect_2to1.sv)
{
"$VERILATOR" --binary --timing --trace -Wno-fatal --top-module tb_arbiter --Mdir sim/build/arb_v rtl/packet_rr_arbiter.sv tb/tb_arbiter.sv >sim/build/arb_compile.log 2>&1
sim/build/arb_v/Vtb_arbiter
for config in '512 4' '512 1' '64 3'; do
    read -r width depth <<< "$config"
    dir="sim/build/v_${width}_${depth}"
    "$VERILATOR" --binary --timing --trace -Wno-fatal --top-module tb_interconnect -GDW="$width" -GDEPTH="$depth" --Mdir "$dir" "${rtl[@]}" tb/tb_interconnect.sv >"${dir}_compile.log" 2>&1
    for seed in 12345 67890 314159; do
        "$dir/Vtb_interconnect" +SEED="$seed"
    done
done
sim/build/v_512_4/Vtb_interconnect +SEED=12345 +VCD
} 2>&1 | tee sim/verilator_results.log
