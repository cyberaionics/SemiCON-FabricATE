#!/usr/bin/env bash
# 64-case sweep: 4 events x 8 injection points x {no stall, RX stall}.
#   bash sim/run_recovery_sweep.sh
# Exit 0 only if every case delivers all beats intact with LFSRs in sync.
# Hold violations (m_rx_valid withdrawn during Disabled/Hot Reset while the
# consumer is stalled) are reported but do not fail the sweep.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
CONFIG_MK=${CONFIG_MK:-}
if [ -z "$CONFIG_MK" ]; then for c in physical_design/config.mk synthesis/orfs/config.mk config.mk; do [ -f "$c" ] && CONFIG_MK=$c && break; done; fi
[ -f "${CONFIG_MK:-/nonexistent}" ] || { echo "config.mk not found; set CONFIG_MK=<path>" >&2; exit 2; }
BUILD=${BUILD:-$ROOT/sim/build_phy}; LOGDIR=${LOGDIR:-$ROOT/sim/logs}; mkdir -p "$BUILD" "$LOGDIR"
RTL=(); while IFS= read -r f; do RTL+=("$f"); done < <(grep -o 'rtl/[A-Za-z0-9_]*\.sv' "$CONFIG_MK")
ok=0; bad=0; hold=0; : > "$LOGDIR/recovery_sweep.log"
for ev in 0 1 2 3; do for at in 1 2 3 4 5 6 7 8; do for st in 0 1; do
  iverilog -g2012 -Wno-timescale -s tb_recovery_sweep -Ptb_recovery_sweep.EVENT=$ev -Ptb_recovery_sweep.AT=$at -Ptb_recovery_sweep.STALL=$st \
      -o "$BUILD/sweep" "${RTL[@]}" tb/tb_recovery_sweep.sv >/dev/null 2>&1 || { echo "compile failed" >&2; exit 2; }
  line=$(cd "$BUILD" && timeout 120 vvp ./sweep 2>&1 | grep -E '^SWEEP' | head -1)
  echo "${line:-SWEEP ev=$ev at=$at stall=$st NO_RESULT}" >> "$LOGDIR/recovery_sweep.log"
  case "$line" in
    *DATA_OK*) ok=$((ok+1)); case "$line" in *hold_viol=0*) ;; *) hold=$((hold+1));; esac;;
    *) bad=$((bad+1));;
  esac
done; done; done
echo "recovery sweep: DATA_OK=$ok DATA_BAD=$bad (of 64); cases with hold violations: $hold"
echo "details: $LOGDIR/recovery_sweep.log"
[ $bad -eq 0 ]
