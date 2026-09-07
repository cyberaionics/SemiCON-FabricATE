#!/bin/sh
set -e
cd "$(dirname "$0")/.."
mkdir -p results
command -v yosys >/dev/null || { echo "yosys not found"; exit 1; }
yosys -s synthesis/run_yosys.ys 2>&1 | tee results/yosys_synthesis.log
