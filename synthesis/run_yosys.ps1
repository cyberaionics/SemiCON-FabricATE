$ErrorActionPreference="Stop"
Set-Location "$PSScriptRoot\.."
New-Item -ItemType Directory -Force results | Out-Null
if (-not (Get-Command yosys -ErrorAction SilentlyContinue)) { throw "yosys not found. Install Yosys and rerun this script." }
yosys -s synthesis\run_yosys.ys 2>&1 | Tee-Object results\yosys_synthesis.log
