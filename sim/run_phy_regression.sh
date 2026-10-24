#!/usr/bin/env bash
# PHY-level regression against the EXACT RTL file list that ORFS synthesizes.
#
#   bash sim/run_phy_regression.sh
#
# - RTL list is parsed from config.mk (VERILOG_FILES), so simulation and
#   synthesis cannot silently diverge.
# - Writes per-test logs plus a sha256 manifest of every input to sim/logs/,
#   so each log can be tied to a specific source revision.
# - Exit code 0 only if every test compiles, exits 0, prints PASS, and prints
#   no line containing FAIL.
# Overrides: CONFIG_MK=path/to/config.mk  LOGDIR=...  BUILD=...
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

if [ -z "${CONFIG_MK:-}" ]; then
    for c in physical_design/config.mk synthesis/orfs/config.mk config.mk; do
        if [ -f "$c" ]; then CONFIG_MK=$c; break; fi
    done
fi
[ -n "${CONFIG_MK:-}" ] && [ -f "$CONFIG_MK" ] || { echo "config.mk not found; set CONFIG_MK=<path>" >&2; exit 2; }
command -v iverilog >/dev/null && command -v vvp >/dev/null || { echo "iverilog/vvp not on PATH" >&2; exit 2; }

LOGDIR=${LOGDIR:-$ROOT/sim/logs}
BUILD=${BUILD:-$ROOT/sim/build_phy}
mkdir -p "$LOGDIR" "$BUILD"

RTL=()
while IFS= read -r f; do RTL+=("$f"); done < <(grep -o 'rtl/[A-Za-z0-9_]*\.sv' "$CONFIG_MK")
[ "${#RTL[@]}" -gt 0 ] || { echo "no rtl/*.sv entries found in $CONFIG_MK" >&2; exit 2; }
for f in "${RTL[@]}"; do [ -f "$f" ] || { echo "missing RTL file listed in config.mk: $f" >&2; exit 2; }; done

CFGDIR=$(dirname "$CONFIG_MK")
{
    echo "# date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# $(iverilog -V 2>&1 | head -1)"
    echo "# config: $CONFIG_MK"
    sha256sum "${RTL[@]}" tb/*.sv "$CONFIG_MK"
    [ -f "$CFGDIR/constraint.sdc" ] && sha256sum "$CFGDIR/constraint.sdc"
} > "$LOGDIR/manifest.sha256"

TESTS="tb_integrated_top tb_repro_inflight_recovery tb_link_phy_integrated tb_link_phy_stress tb_integrated tb_blocks tb_ltssm"
fail=0
printf '%-26s %s\n' TEST RESULT
for tb in $TESTS; do
    clog="$LOGDIR/$tb.compile.log"; rlog="$LOGDIR/$tb.log"; res=PASS
    if ! iverilog -g2012 -Wall -Wno-timescale -s "$tb" -o "$BUILD/$tb" "${RTL[@]}" "tb/$tb.sv" >"$clog" 2>&1; then
        res="COMPILE_FAIL (see $clog)"
    else
        ( cd "$BUILD" && timeout 600 vvp "./$tb" ) >"$rlog" 2>&1; rc=$?
        if   [ $rc -ne 0 ];                 then res="FAIL (vvp exit $rc, see $rlog)"
        elif grep -q 'FAIL' "$rlog";        then res="FAIL (see $rlog)"
        elif ! grep -q 'PASS' "$rlog";      then res="FAIL (no PASS line, see $rlog)"
        fi
    fi
    [ "$res" = PASS ] || fail=1
    printf '%-26s %s\n' "$tb" "$res"
done
echo "manifest: $LOGDIR/manifest.sha256"
exit $fail
