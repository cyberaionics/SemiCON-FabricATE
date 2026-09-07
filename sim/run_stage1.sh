#!/bin/sh
set -e
cd "$(dirname "$0")/../rtl"
iverilog -g2012 -o ../results/stage1_integrated_sim pcie6_phy_pkg.sv pcie6_ltssm.sv pcie6_lane_striper.sv pcie6_lane_destriper.sv pcie6_lane_scrambler.sv pcie6_gray_pam4_tx.sv pcie6_gray_pam4_rx.sv pcie6_protocol_to_phy_tx.sv pcie6_protocol_to_phy_rx.sv stage1_protocol_to_phy_top.sv ../tb/tb_stage1_integrated.sv
vvp ../results/stage1_integrated_sim
