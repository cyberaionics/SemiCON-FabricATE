#!/usr/bin/env sh
# Run every testbench and generate sim/link_tx.vcd from any working directory.
set -eu
script_dir=${0%/*}
if [ "$script_dir" = "$0" ]; then script_dir=.; fi
project_root=$(CDPATH= cd -P "$script_dir/.." && pwd)
cd "$project_root"

# PYTHON may specify an interpreter executable, including a path with spaces.
if [ -n "${PYTHON:-}" ]; then
    exec "$PYTHON" sim/run_all.py "$@"
fi
if command -v python3 >/dev/null 2>&1; then
    exec python3 sim/run_all.py "$@"
fi
if command -v python >/dev/null 2>&1; then
    exec python sim/run_all.py "$@"
fi
if command -v py >/dev/null 2>&1; then
    exec py -3 sim/run_all.py "$@"
fi
printf '%s\n' 'Python 3.9+ is required. Install it or set PYTHON to its executable path.' >&2
exit 127
