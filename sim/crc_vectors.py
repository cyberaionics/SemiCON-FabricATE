"""Independent polynomial-division oracle; optionally verify Appendix K matrix."""
from pathlib import Path
import argparse
import hashlib
import random

ROOT = Path(__file__).resolve().parents[1]


def multiply(a, b):
    product = 0
    for bit in range(8):
        if b & (1 << bit):
            product ^= a << bit
    for bit in range(14, 7, -1):
        if product & (1 << bit):
            product ^= 0x12B << (bit - 8)
    return product


def generator():
    coefficients = [1]
    alpha = 1
    for _ in range(8):
        alpha = multiply(alpha, 2)
        result = [0] * (len(coefficients) + 1)
        for i, coefficient in enumerate(coefficients):
            result[i] ^= coefficient
            result[i + 1] ^= multiply(coefficient, alpha)
        coefficients = result
    return coefficients


GENERATOR = generator()
PRODUCTS = [[multiply(a, g) for g in GENERATOR] for a in range(256)]


def parity(data):
    # Divide the full message polynomial times x^8, rather than an LFSR update.
    dividend = list(data) + [0] * 8
    for i in range(len(data)):
        products = PRODUCTS[dividend[i]]
        for j in range(9):
            dividend[i + j] ^= products[j]
    return bytes(dividend[-8:])  # r7..r0, opposite wire-byte order


def generate_vectors(matrix=None):
    output = ROOT / 'sim' / 'build'
    output.mkdir(exist_ok=True)
    rng = random.Random(0xC8C242)
    vectors = [bytes(242), bytes([255] * 242), bytes(range(242)),
               bytes([128]) + bytes(241), bytes(241) + bytes([128])]
    vectors += [rng.randbytes(242) for _ in range(27)]
    (output / 'crc_data.hex').write_text(''.join(
        f'{int.from_bytes(data, "little"):0484x}\n' for data in vectors))
    (output / 'crc_expected.hex').write_text(''.join(
        parity(data).hex() + '\n' for data in vectors))
    report = [f'PASS generated {len(vectors)} independent CRC vectors',
              'Generator (x^8 through constant): ' + bytes(GENERATOR).hex(' ')]
    if matrix:
        raw = Path(matrix).read_bytes()
        rows = [bytes.fromhex(line) for line in raw.decode().splitlines() if line.strip()]
        assert len(rows) == 1936 and all(len(row) == 8 for row in rows)
        for row, expected in enumerate(rows):
            data = bytearray(242)
            data[241 - row // 8] = 1 << (7 - row % 8)
            assert parity(data) == expected, f'Appendix K mismatch at row {row}'
        report += ['PASS all 1936 single-bit inputs match Appendix K generator matrix',
                   'Matrix SHA256: ' + hashlib.sha256(raw).hexdigest()]
    return '\n'.join(report) + '\n'


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--matrix', type=Path)
    args = parser.parse_args()
    result = generate_vectors(args.matrix)
    print(result, end='')
    if args.matrix:
        (ROOT / 'sim' / 'crc_matrix_results.log').write_text(result)
