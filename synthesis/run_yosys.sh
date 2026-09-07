#!/bin/sh
set -e
cd "$(dirname "$0")/.."
command -v yosys >/dev/null || { echo "yosys not found"; exit 1; }
yosys -l synthesis/phy_structural_results.log synthesis/run_yosys.ys
