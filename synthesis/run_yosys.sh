#!/usr/bin/env sh
set -eu
script_dir=${0%/*}
if [ "$script_dir" = "$0" ]; then script_dir=.; fi
cd "$script_dir/.."
if [ -n "${PYTHON:-}" ]; then exec "$PYTHON" synthesis/run_yosys.py; fi
if command -v python3 >/dev/null 2>&1; then exec python3 synthesis/run_yosys.py; fi
if command -v python >/dev/null 2>&1; then exec python synthesis/run_yosys.py; fi
exec py -3 synthesis/run_yosys.py
