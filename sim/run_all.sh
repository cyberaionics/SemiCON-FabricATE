#!/bin/sh
# Protocol-to-PHY (Stage 2) simulation regression.
# For the original interconnect/CRC/FEC regression, use `python sim/run_all.py`.
set -e
cd "$(dirname "$0")/.."
mkdir -p sim/build
RTL="rtl/phy_pkg.sv rtl/ltssm.sv rtl/lane_striper.sv rtl/lane_destriper.sv rtl/lane_scrambler.sv rtl/gray_pam4_tx.sv rtl/gray_pam4_rx.sv rtl/protocol_to_phy_tx.sv rtl/protocol_to_phy_rx.sv rtl/protocol_to_phy_top.sv"
iverilog -g2012 -o sim/build/phy_integrated_sim $RTL tb/tb_integrated.sv
vvp sim/build/phy_integrated_sim | tee sim/phy_integrated_results.log
iverilog -g2012 -o sim/build/phy_blocks_sim $RTL tb/tb_blocks.sv
vvp sim/build/phy_blocks_sim | tee sim/phy_blocks_results.log
iverilog -g2012 -o sim/build/phy_ltssm_sim rtl/ltssm.sv tb/tb_ltssm.sv
vvp sim/build/phy_ltssm_sim | tee sim/phy_ltssm_results.log
