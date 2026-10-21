#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

echo "=== SemiCON Yosys Synthesis ==="
echo "Repository: $REPO_ROOT"
yosys -V

echo
echo "=== Running main synthesis flow ==="
yosys -s synthesis/run_yosys.ys

echo
echo "=== Synthesis completed successfully ==="

