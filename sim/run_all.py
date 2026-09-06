"""Run existing and packetizer regressions with Icarus (Python 3, no packages)."""
from pathlib import Path
import os
import shutil
import subprocess
from crc_vectors import generate_vectors
from fec_vectors import generate_fec_vectors, verify_correction

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
local_bin = ROOT / '.tools' / 'mingw64' / 'bin'
if local_bin.exists():
    os.environ['PATH'] = str(local_bin) + os.pathsep + os.environ.get('PATH', '')
    # Optional DLL dependencies from an existing Windows MSYS2 installation.
    msys_bin = Path('C:/msys64/mingw64/bin')
    if msys_bin.exists():
        os.environ['PATH'] += os.pathsep + str(msys_bin)
compiler, runtime = shutil.which('iverilog'), shutil.which('vvp')
if not compiler or not runtime:
    raise SystemExit('Install Icarus Verilog and put iverilog and vvp on PATH.')
build = ROOT / 'sim' / 'build'
build.mkdir(exist_ok=True)
base = ['rtl/axis_fifo.sv', 'rtl/packet_rr_arbiter.sv', 'rtl/axis_interconnect_2to1.sv']
link = base + ['rtl/flit_crc8.sv', 'rtl/flit_fec6.sv', 'rtl/axis_frame_packetizer.sv', 'rtl/axis_link_tx.sv']


def compile_tb(name, top, sources, parameters=()):
    binary = build / name
    command = [compiler, '-g2012', '-Wall', '-s', top, '-o', str(binary)]
    command += [f'-P{top}.{key}={value}' for key, value in parameters]
    command += sources
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (build / f'{name}_compile.log').write_text(result.stdout)
    if result.returncode:
        raise SystemExit(f'Compilation failed ({result.returncode}):\n{result.stdout}')
    return binary


def simulate(binary, log, *args):
    result = subprocess.run([runtime, str(binary), *args], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    print(result.stdout, end='')
    log.write(result.stdout)
    log.flush()
    if result.returncode or 'PASS ' not in result.stdout:
        raise SystemExit(f'Simulation failed: {binary.name}, exit={result.returncode}')


with (ROOT / 'sim' / 'fec_results.log').open('w') as log:
    log.write(generate_fec_vectors())
    binary = compile_tb('fec_icarus', 'tb_flit_fec6', ['rtl/flit_fec6.sv', 'tb/tb_flit_fec6.sv'])
    simulate(binary, log)
    correction_result = verify_correction()
    (ROOT / 'sim' / 'fec_correction_results.log').write_text(correction_result)
    print(correction_result, end='')

with (ROOT / 'sim' / 'crc_results.log').open('w') as log:
    log.write(generate_vectors())
    binary = compile_tb('crc_icarus', 'tb_flit_crc8', ['rtl/flit_crc8.sv', 'tb/tb_flit_crc8.sv'])
    simulate(binary, log)

with (ROOT / 'sim' / 'icarus_results.log').open('w') as log:
    binary = compile_tb('arb_icarus', 'tb_arbiter', [base[1], 'tb/tb_arbiter.sv'])
    simulate(binary, log)
    for width, depth in [(512, 4), (512, 1), (64, 3)]:
        binary = compile_tb(f'interconnect_{width}_{depth}', 'tb_interconnect',
                            base + ['tb/tb_interconnect.sv'], [('DW', width), ('DEPTH', depth)])
        for seed in [12345, 67890, 314159]:
            simulate(binary, log, f'+SEED={seed}')

with (ROOT / 'sim' / 'link_results.log').open('w') as log:
    for direct, depth in [(1, 4), (0, 4), (0, 1), (0, 3)]:
        binary = compile_tb(f'link_{direct}_{depth}', 'tb_link_tx', link + ['tb/tb_link_tx.sv'],
                            [('DIRECT', direct), ('DEPTH', depth)])
        for seed in [12345, 67890, 314159]:
            simulate(binary, log, f'+SEED={seed}')
    simulate(build / 'link_0_4', log, '+SEED=12345', '+VCD')
