# AXI-Stream-to-Link Prototype with a PCIe 6.0-inspired Digital PHY

A student RTL-to-GDS project (Yosys + OpenROAD/ORFS, Nangate45).
**This is not a PCIe 6.0 compliant design.** The 256-byte frame
(236 B payload region, 6 B reserved, 8 B CRC, 6 B FEC) is a prototype format
and does not carry PCIe TLPs. There is no SerDes or physical channel: the
"link" is a digital TX-to-RX loopback inside `integrated_link_phy_top`.

## Repository layout
    rtl/               18 SystemVerilog files (integrated_link_phy_top is the physical-design top)
    tb/                testbenches and reference oracles
    sim/               run scripts; regenerated logs in sim/logs/
    physical_design/   config.mk, constraint.sdc, reports/, diagnostics/ (and GDS or release link)
    docs/              cap_violation_analysis.md, rtl_changes_since_routed_run.patch,
                       routed_run_rtl_sha256.txt

## Reproduce the simulation results
Requires Icarus Verilog 12 and bash (Linux/WSL/Git Bash).

    bash sim/run_phy_regression.sh   # 7 PHY-level tests; hashes in sim/logs/manifest.sha256
    bash sim/run_recovery_sweep.sh   # 64 LTSSM-event/timing/backpressure cases
    python3 sim/run_all.py           # CRC, FEC, arbiter, interconnect, link-TX (many seeds/configs)

The PHY regression builds from the exact RTL list in `physical_design/config.mk`
and includes `tb_integrated_top`, which instantiates `integrated_link_phy_top`
itself. Note: some CRC/FEC logs mention comparison against "Appendix J/K"
reference files that are supplied by the user and are **not** in this
repository; those particular comparisons cannot be reproduced from the repo.

## What the tests do and do not show
- Shown: data-path round trip (stripe, scramble, PAM4 map, demap, descramble,
  destripe) through the top; LTSSM reaching L0; RX backpressure without beat
  loss; recovery/disable/hot-reset events with a frame in flight (64 cases).
- CRC and FEC are checked against independent references at the TX encoder.
- Not shown: the RX has no CRC check or FEC decode in RTL, and framing
  metadata (KEEP/TLAST/packet start/end) is not carried across the PHY
  boundary. Loopback verifies raw 256-bit beats only.
- No RTL-vs-post-route gate-level simulation has been run.

## RTL vs the routed result (read this)
**The routed results in `physical_design/` were produced from the RTL *before*
the in-flight-recovery fix.** Two files differ between that run and the RTL in
`rtl/`: `protocol_to_phy_tx.sv` and `protocol_to_phy_rx.sv`
(see `docs/rtl_changes_since_routed_run.patch`; hashes of the routed run's RTL
are in `docs/routed_run_rtl_sha256.txt`). The fixed RTL passes all simulation
tests above but has **not** been through synthesis or place-and-route.

Pre-fix routed result (clock 10 ns): detailed routing 0 DRC violations; worst
setup slack +5.67 ns, minimum period 4.33 ns; area 98,707 um^2 at about 41%
utilization.

## Known limitations (read before relying on any number)
1. **Max-capacitance:** the routed result ends with 9 max-capacitance
   violations (worst -9.36 fF; 25.33 limit vs 34.69 fF on an AOI21_X1). They
   are long single-load nets (about 80-215 um) on minimum-size drivers.
   Extraction gives higher wire capacitance than the placement estimate on the
   five nets compared. Details and an untested candidate fix:
   `docs/cap_violation_analysis.md`. The violations were **not** fixed.
2. **IR drop:** the reported worst-case VDD drop of 0.347 V (31.5%) is not
   explained. Average drop is 14.8 mV (1.3%), so the worst case looks like a
   localized outlier or analysis-setup artifact. Not validated; do not cite it
   as either a pass or a real defect.
3. **Timing constraints are idealized** (no input drive/output load model, no
   clock uncertainty). The 4.33 ns minimum period is not a signoff number.
4. Total power of 0.597 W was reported with default activity assumptions and
   has not been validated.
5. **Handshake nit:** if the link is deliberately torn down (Disabled/Hot
   Reset) while the consumer is stalled, `m_rx_valid` is withdrawn before the
   beat is accepted. Data is retained and delivered intact after retraining
   (6 of 64 sweep cases flag it).
6. A beat held through Disabled/Hot Reset is delivered after retraining
   rather than flushed.

## Fixed bug (for reviewers)
Before the fix, a link event (e.g. `phy_error`) while a frame was in flight
dropped one beat and permanently desynchronized the RX scrambler
(8 beats accepted, 7 received, 4 corrupted; in a 64-case sweep, 60 failed).
Fixed by holding the in-flight beat while disabled. Regression:
`tb_repro_inflight_recovery`, `tb_recovery_sweep`.
