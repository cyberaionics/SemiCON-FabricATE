"""Independent weighted-sum FEC oracle and encoder verification vectors."""
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parents[1]


def multiply(a, b):
    p = 0
    for i in range(8):
        if b & (1 << i):
            p ^= a << i
    for i in range(14, 7, -1):
        if p & (1 << i):
            p ^= 0x11D << (i - 8)
    return p


POWERS = [1]
for _ in range(255):
    POWERS.append(multiply(POWERS[-1], 2))
WEIGHTED = [[multiply(d, POWERS[84-i]) for d in range(256)] for i in range(84)]


def parity(data):
    assert len(data) == 250
    checks, parities = [0]*3, [0]*3
    for index, value in enumerate(data):
        group, position = index % 3, index // 3
        checks[group] ^= WEIGHTED[position][value]
        parities[group] ^= value
    return bytes([checks[1], checks[2], checks[0], parities[1], parities[2], parities[0]])


def generate_fec_vectors():
    rng = random.Random(0xFEC250)
    vectors = [bytes(250), bytes([255]*250), bytes(range(250))]
    vectors += [rng.randbytes(250) for _ in range(29)]
    for bit in range(2000):
        data = bytearray(250)
        data[bit//8] = 1 << (bit % 8)
        vectors.append(bytes(data))
    output = ROOT / 'sim' / 'build'
    output.mkdir(exist_ok=True)
    (output/'fec_data.hex').write_text(''.join(data[::-1].hex()+'\n' for data in vectors))
    (output/'fec_expected.hex').write_text(''.join(parity(data)[::-1].hex()+'\n' for data in vectors))
    return f'PASS generated {len(vectors)} FEC vectors including all 2000 input basis bits\n'


def correct_reference(frame):
    """Verification-only decoder: at most one erroneous byte per ECC group."""
    result = bytearray(frame)
    calculated = parity(result[:250])
    for group in range(3):
        slot = (group + 2) % 3
        check_error = result[250+slot] ^ calculated[slot]
        parity_error = result[253+slot] ^ calculated[3+slot]
        if check_error == 0 and parity_error == 0:
            continue
        if parity_error == 0:
            result[250+slot] ^= check_error
        elif check_error == 0:
            result[253+slot] ^= parity_error
        else:
            for position in range(84 if group == 0 else 83):
                if WEIGHTED[position][parity_error] == check_error:
                    result[position*3+group] ^= parity_error
                    break
            else:
                raise ValueError('Syndrome does not identify a transmitted byte')
    if parity(result[:250]) != result[250:]:
        raise ValueError('Nonzero syndrome after correction')
    return bytes(result)


def verify_correction():
    data = bytes((i*73+19) % 256 for i in range(250))
    clean = data + parity(data)
    checked = 0
    for position in range(256):
        for bit in range(8):
            damaged = bytearray(clean)
            damaged[position] ^= 1 << bit
            assert correct_reference(damaged) == clean
            checked += 1
    for start in range(254):
        damaged = bytearray(clean)
        for delta in range(3):
            damaged[start+delta] ^= 0xA5 + delta
        assert correct_reference(damaged) == clean
        checked += 1
    return f'PASS verification-only decoder restored {checked} injected-error frames (2048 bit flips, 254 three-byte bursts)\n'


if __name__ == '__main__':
    print(generate_fec_vectors(), end='')
    result = verify_correction()
    (ROOT/'sim'/'fec_correction_results.log').write_text(result)
    print(result, end='')
