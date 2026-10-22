# SemiCON Stage 2 Release Candidate Audit — 2026-10-22

## Summary
Integrated TX datapath is connected via `link_to_phy_tx`. End-to-end test passes. Yosys synthesizes integrated top-level with zero problems. No RTL changes made during validation.

## Checks

### 1. Git status and diff
- **Status:** PASS
- Branch `master` up to date with `origin/master`.
- Untracked files: `sim/regression_runner.sh`, `sim/yosys_link_to_phy.log`. No uncommitted changes to RTL.
- Last commit `8174052` adds `axis_to_phy_tx.sv`, `link_to_phy_tx.sv`, synthesis scripts, testbenches.

### 2. Canonical integrated TX top-level and dependencies
- **Status:** PASS
- Top-level: `rtl/link_to_phy_tx.sv`
- Dependencies:
  - `rtl/axis_fifo.sv`, `rtl/packet_rr_arbiter.sv`, `rtl/axis_interconnect_2to1.sv`
  - `rtl/axis_frame_packetizer.sv`, `rtl/flit_crc8.sv`, `rtl/flit_fec6.sv`, `rtl/axis_link_tx.sv`
  - `rtl/axis_to_phy_tx.sv`
  - `rtl/lane_striper.sv`, `rtl/lane_scrambler.sv`, `rtl/gray_pam4_tx.sv`
  - `rtl/protocol_to_phy_tx.sv`
- Synthesis script: `synthesis/check_link_to_phy.ys` lists all files.

### 3. End-to-end testbench and regression command
- **Status:** PASS
- End-to-end testbench: `tb/tb_link_to_phy_tx.sv`
- Regression runner: `sim/regression_runner.sh` and `python3 sim/run_all.py`
- Clean build command recorded and exit codes captured.

### 4. End-to-end test run
- **Status:** PASS
- Command:
  ```
  iverilog -g2012 -Wall -o sim/build/link_to_phy_tx_tb rtl/axis_fifo.sv rtl/packet_rr_arbiter.sv rtl/axis_interconnect_2to1.sv rtl/axis_frame_packetizer.sv rtl/flit_crc8.sv rtl/flit_fec6.sv rtl/axis_link_tx.sv rtl/axis_to_phy_tx.sv rtl/lane_striper.sv rtl/lane_scrambler.sv rtl/gray_pam4_tx.sv rtl/protocol_to_phy_tx.sv rtl/link_to_phy_tx.sv tb/tb_link_to_phy_tx.sv
  vvp sim/build/link_to_phy_tx_tb
  ```
- Exit code: 0
- Results:
  - PASS: TX path produced 8 beats for 64-byte packet
  - PASS: metadata sideband present source=0 bytes=64
  - PASS: TX disabled stops output
  - CHECKS = 3

### 5. Relevant unit tests
- **Status:** PASS
- Bridge unit test `tb/tb_axis_to_phy_tx.sv`: PASS, CHECKS = 4
- Full regression `python3 sim/run_all.py`: exit 0, all PASS
- PHY tests: `tb_integrated` PASS 113 checks, `tb_blocks` PASS, `tb_ltssm` PASS

### 6. Yosys synthesis on integrated top
- **Status:** PASS
- Command: `yosys -s synthesis/check_link_to_phy.ys`
- Exit code: 0
- `Found and reported 0 problems`
- Warnings: 3 unique messages, 5 total
  - `Warning: Replacing memory \mem with list of registers. See rtl/axis_fifo.sv:36`
  - `Warning: Replacing memory \lfsr_q with list of registers. See rtl/lane_scrambler.sv:54`
  - `Warning: Replacing memory \lfsr_d with list of registers. See rtl/lane_scrambler.sv:48`
- Cell stats:
  - `axis_to_phy_tx`: 305 cells
  - `axis_link_tx`: 21839 cells
  - `axis_interconnect_2to1`: 582 cells
  - No latches inferred.

### 7. Synthesis warnings / issues
- **Status:** PASS
- `lane_scrambler` warnings are synthesis representation changes only. Unpacked arrays `lfsr_q`/`lfsr_d` replaced with register lists. Functionally correct; all tests pass.
- Icarus `sorry: constant selects in always_* processes` warnings are simulation-only, no functional impact.

### 8. Testbench coverage
- **Status:** PASS
- Data correctness: 8 beats produced for 64-byte packet, metadata sideband checked.
- Packet handling: frame bytes, source, packet start/end observed.
- Backpressure: bridge holds data under stall; `tx_enable` gating stops output.
- Reset/idle: reset clears valid, `tx_enable` de-assert stops output.

### 9. Documentation accuracy
- **Status:** PASS with update
- README updated to list `axis_to_phy_tx.sv`, `link_to_phy_tx.sv`, `tb_axis_to_phy_tx.sv`, `tb_link_to_phy_tx.sv`.
- README Stage 2 description updated to note wiring via `link_to_phy_tx`.
- No claim of PCIe compliance, timing closure, or physical area.

### 10. Clean build reproducibility
- **Status:** PASS
- Clean build from repository files succeeds with `iverilog -g2012` and `vvp`.
- Regression runner reproduces results.

## Highest-priority release blocker
**None.** All critical checks PASS. No reproducible functional failure found.

## Remaining bugs and limitations
- `protocol_to_phy_tx` has no frame awareness; metadata sidebands preserved but not consumed.
- RX path not integrated; TX-only.
- Throughput limited by `protocol_to_phy_tx` one-cycle bubble.
- No PCIe 6.0 compliance claimed; Stage 1 prototype framing.
- Metadata not used by PHY; downstream checker must retain it.

## Recommendation
Proceed directly to packaging. Next recommended action: create `rtl/link_to_phy_top.sv` wrapping `axis_link_tx → axis_to_phy_tx → protocol_to_phy_top` for full LTSSM-gated end-to-end, and add narrow loopback testbench.

## Evidence files
- `sim/build/link_to_phy_tx_run.log`
- `sim/regression_clean.log`
- `sim/yosys_link_to_phy_clean.log`
- `reports/release_candidate_audit.md` (this file)
