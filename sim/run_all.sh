#!/bin/sh
set -e
cd "$(dirname "$0")/.."
mkdir -p results
RTL="rtl/pcie6_phy_pkg.sv rtl/pcie6_ltssm.sv rtl/pcie6_lane_striper.sv rtl/pcie6_lane_destriper.sv rtl/pcie6_lane_scrambler.sv rtl/pcie6_gray_pam4_tx.sv rtl/pcie6_gray_pam4_rx.sv rtl/pcie6_protocol_to_phy_tx.sv rtl/pcie6_protocol_to_phy_rx.sv rtl/stage1_protocol_to_phy_top.sv"
iverilog -g2012 -o results/stage1_integrated_sim $RTL tb/tb_stage1_integrated.sv
vvp results/stage1_integrated_sim | tee results/integrated_sim.log
iverilog -g2012 -o results/stage1_blocks_sim $RTL tb/tb_pcie6_blocks.sv
vvp results/stage1_blocks_sim | tee results/blocks_sim.log
iverilog -g2012 -o results/stage1_ltssm_sim rtl/pcie6_ltssm.sv tb/tb_pcie6_ltssm.sv
vvp results/stage1_ltssm_sim | tee results/ltssm_sim.log
