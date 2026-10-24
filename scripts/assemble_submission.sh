#!/usr/bin/env bash
# Assemble the submission repository.
#   Run from the repo root AFTER extracting the overlay archive:
#       bash scripts/assemble_submission.sh
#
# It stops (without changing anything) if the fixed RTL is not in place or if
# anything other than the two fixed files differs from the RTL ORFS used.
# It never runs git, and only deletes files that are exact duplicates or empty.
#
# Overrides (env vars): C=<container name>  ORFS_RTL=<folder ORFS read RTL from>
#                       ORFS_CFG=<folder with config.mk + constraint.sdc>
set -u
C=${C:-upbeat_kowalevski}
ORFS_RTL=${ORFS_RTL:-/mnt/c/rtl}
ORFS_CFG=${ORFS_CFG:-/mnt/c/synthesis/orfs}
FLOW=/OpenROAD-flow-scripts/flow
RUN=nangate45/integrated_link_phy_top/base
TX_SHA=5597dc1457fa9297f5fb817b37fb79fc0f987437fdf29f3ad0f4991549f3f883
RX_SHA=f9736e9bd8a7367bfdb3c160008504ac540f5075ad632a46f0fb285c9f522daa
warn() { echo "WARN: $*"; }
stop() { echo "STOP: $*" >&2; exit 1; }

[ -d rtl ] && [ -d tb ] && [ -d sim ] || stop "run from the repo root (needs rtl/ tb/ sim/)"
[ -d "$ORFS_RTL" ] || stop "ORFS RTL folder not found: $ORFS_RTL (set ORFS_RTL=...)"
[ -f "$ORFS_CFG/config.mk" ] && [ -f "$ORFS_CFG/constraint.sdc" ] || stop "config.mk / constraint.sdc not found in $ORFS_CFG (set ORFS_CFG=...)"

echo "== 1. fixed RTL in place?"
[ "$(sha256sum rtl/protocol_to_phy_tx.sv | cut -d' ' -f1)" = "$TX_SHA" ] || stop "rtl/protocol_to_phy_tx.sv is not the fixed version"
[ "$(sha256sum rtl/protocol_to_phy_rx.sv | cut -d' ' -f1)" = "$RX_SHA" ] || stop "rtl/protocol_to_phy_rx.sv is not the fixed version"
echo "   ok"

echo "== 2. what differs from the RTL ORFS synthesized?"
d=$(diff -rq "$ORFS_RTL" rtl)
echo "$d" | sed 's/^/   /'
diffs=$(echo "$d" | grep ' differ$' | sed -E 's#^Files .*/([^/ ]+) and .* differ$#\1#' | sort | tr '\n' ' ')
[ "$diffs" = "protocol_to_phy_rx.sv protocol_to_phy_tx.sv " ] || stop "expected exactly protocol_to_phy_rx.sv and protocol_to_phy_tx.sv to differ, got: '$diffs'"
echo "$d" | grep -q '^Only in' && warn "some files exist in only one folder (listed above); confirm that is intended"
echo "   ok: exactly the two fixed files differ"

echo "== 3. provenance files"
mkdir -p docs physical_design/diagnostics
(cd "$ORFS_RTL" && sha256sum ./*.sv) > docs/routed_run_rtl_sha256.txt
: > docs/rtl_changes_since_routed_run.patch
for f in protocol_to_phy_tx.sv protocol_to_phy_rx.sv; do
    diff -u --label "routed_run/$f" --label "rtl/$f" "$ORFS_RTL/$f" "rtl/$f" >> docs/rtl_changes_since_routed_run.patch
done
echo "   wrote docs/routed_run_rtl_sha256.txt and docs/rtl_changes_since_routed_run.patch"

echo "== 4. flow inputs -> physical_design/"
cp "$ORFS_CFG/config.mk" "$ORFS_CFG/constraint.sdc" physical_design/
for f in config.mk constraint.sdc; do
    if [ -f "$f" ]; then
        if cmp -s "$f" "physical_design/$f"; then rm "$f"; echo "   removed identical root copy of $f"
        else mv "$f" "physical_design/$f.repo_copy"; warn "root $f differed from the ORFS one; kept as physical_design/$f.repo_copy"; fi
    fi
done
for f in cap_diag2.tcl cap_diag2.log; do
    if [ -f "$f" ]; then cp "$f" physical_design/diagnostics/ && echo "   copied $f"; else warn "$f not found in $(pwd); copy it to physical_design/diagnostics/ yourself"; fi
done

echo "== 5. logs / reports from the base run (container: $C)"
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$C"; then
    for k in logs reports; do
        if [ -n "$(ls -A "physical_design/$k" 2>/dev/null)" ]; then echo "   physical_design/$k already populated; skipping"
        else
            rmdir "physical_design/$k" 2>/dev/null
            docker cp "$C:$FLOW/$k/$RUN" "physical_design/$k" >/dev/null 2>&1 \
                && [ -n "$(ls -A "physical_design/$k" 2>/dev/null)" ] && echo "   copied $k" || warn "could not copy $k from the container"
        fi
    done
    echo "   result files in the container (add the GDS only if it is small; see sizes):"
    docker exec "$C" ls -la "$FLOW/results/$RUN" 2>/dev/null | grep -E 'gds|\.v$|\.odb' | sed 's/^/     /'
else
    warn "container '$C' is not running; skipped. Re-run after 'docker start $C', or copy logs/reports by hand."
fi

echo "== 6. tidy exact duplicates / empty logs"
[ -f sim/run_all_crc.sh ] && cmp -s sim/run_all.sh sim/run_all_crc.sh && rm sim/run_all_crc.sh && echo "   removed duplicate sim/run_all_crc.sh"
[ -f sim/verilator_results.log ] && [ ! -s sim/verilator_results.log ] && rm sim/verilator_results.log && echo "   removed empty sim/verilator_results.log"

echo "== 7. regenerate simulation evidence from the final RTL"
rc=0
bash sim/run_phy_regression.sh || rc=1
bash sim/run_recovery_sweep.sh || rc=1
if python3 sim/run_all.py > sim/logs/run_all_console.log 2>&1; then echo "run_all.py: OK (console log: sim/logs/run_all_console.log)"
else echo "run_all.py: FAILED (see sim/logs/run_all_console.log)"; rc=1; fi
echo "   logs NOT rewritten by the runs above are stale (pre-fix). Delete them, except keep"
echo "   crc_matrix_results.log / fec_reference_results.log if you want the Appendix evidence:"
find sim -maxdepth 1 -name '*.log' ! -newer sim/logs/manifest.sha256 | sed 's/^/     /'

echo "== 8. final checks"
echo "   files over 50 MB (should be none):"; find . -type f -size +50M -not -path './.git/*' | sed 's/^/     /'
echo "   personal strings in text files (should be none):"
grep -rIl -i -E 'debad|C:\\Users|/Users/' --exclude=assemble_submission.sh --exclude-dir=.git --exclude-dir=build --exclude-dir=build_phy --exclude-dir=__pycache__ . | sed 's/^/     /'
echo
[ $rc -eq 0 ] && echo "ALL TESTS PASSED. Next: git init (or clone), git add -A, review 'git status', commit, push." \
              || echo "SOMETHING FAILED above - fix before committing."
exit $rc
