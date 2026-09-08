# Protocol-to-PHY (Stage 2) simulation regression.
# For the original interconnect/CRC/FEC regression, use `python sim/run_all.py`.
$ErrorActionPreference="Stop"
Set-Location "$PSScriptRoot\.."
New-Item -ItemType Directory -Force sim\build | Out-Null
$rtl = @(
 "rtl\phy_pkg.sv","rtl\ltssm.sv","rtl\lane_striper.sv",
 "rtl\lane_destriper.sv","rtl\lane_scrambler.sv",
 "rtl\gray_pam4_tx.sv","rtl\gray_pam4_rx.sv",
 "rtl\protocol_to_phy_tx.sv","rtl\protocol_to_phy_rx.sv",
 "rtl\protocol_to_phy_top.sv"
)
& iverilog -g2012 -o sim\build\phy_integrated_sim @rtl tb\tb_integrated.sv
& vvp sim\build\phy_integrated_sim | Tee-Object sim\phy_integrated_results.log
& iverilog -g2012 -o sim\build\phy_blocks_sim @rtl tb\tb_blocks.sv
& vvp sim\build\phy_blocks_sim | Tee-Object sim\phy_blocks_results.log
& iverilog -g2012 -o sim\build\phy_ltssm_sim rtl\ltssm.sv tb\tb_ltssm.sv
& vvp sim\build\phy_ltssm_sim | Tee-Object sim\phy_ltssm_results.log
Write-Host "Protocol-to-PHY simulation targets completed. VCD files are generated in the working directory where each VVP is launched."
