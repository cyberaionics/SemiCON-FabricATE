#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sim/build

echo "=== Integrated TX test ==="
iverilog -g2012 -Wall -o sim/build/link_to_phy_tx_tb rtl/axis_fifo.sv rtl/packet_rr_arbiter.sv rtl/axis_interconnect_2to1.sv rtl/axis_frame_packetizer.sv rtl/flit_crc8.sv rtl/flit_fec6.sv rtl/axis_link_tx.sv rtl/axis_to_phy_tx.sv rtl/lane_striper.sv rtl/lane_scrambler.sv rtl/gray_pam4_tx.sv rtl/protocol_to_phy_tx.sv rtl/link_to_phy_tx.sv tb/tb_link_to_phy_tx.sv
vvp sim/build/link_to_phy_tx_tb
echo "PASS: integrated TX test"

echo "=== Bridge unit test ==="
iverilog -g2012 -Wall -o sim/build/axis_to_phy_tx_tb rtl/axis_to_phy_tx.sv tb/tb_axis_to_phy_tx.sv
vvp sim/build/axis_to_phy_tx_tb
echo "PASS: bridge unit test"

echo "=== Full regression ==="
python3 sim/run_all.py
echo "PASS: full regression"

echo "=== Yosys synthesis ==="
yosys -s synthesis/check_link_to_phy.ys > sim/yosys_link_to_phy.log 2>&1
if grep -q "Found and reported 0 problems" sim/yosys_link_to_phy.log; then
  echo "PASS: Yosys synthesis clean"
else
  echo "FAIL: Yosys synthesis reported problems"
  exit 1
fi

echo "=== All checks passed ==="
exit 0
