$ErrorActionPreference="Stop"
Set-Location "$PSScriptRoot\.."
if (-not (Get-Command yosys -ErrorAction SilentlyContinue)) { throw "yosys not found. Install Yosys and rerun this script." }
yosys -l synthesis\phy_structural_results.log synthesis\run_yosys.ys
