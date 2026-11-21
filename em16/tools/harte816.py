#!/usr/bin/env python3
"""Fetch the SingleStepTests 65816 vectors and convert them, with their bus
cycles, to the binary files em16 -harte816 reads.

  python3 -I harte816.py OUTDIR [NN.m ...]     default: all 512 files

Each OUTDIR/NN.m.bin (NN the opcode in hex, m e or n) is little-endian:

  count: u32, then per test
    initial, final: pc u16, s u16, p u8, a u16, x u16, y u16, dbr u8,
                    d u16, pbr u8, e u8
    ninit u16, nfinal u16, then the RAM of each: addr | value << 24, u32
    ncycles u16, then per cycle: addr | flags << 24, u32; value u8
      flags: 1 VDA, 2 VPA, 4 VPB, 8 write, 16 MLB, 32 no value, 64 no address
"""
import concurrent.futures, json, os, struct, sys, urllib.request

RAW = "https://raw.githubusercontent.com/SingleStepTests/65816/main/v1"


def convert(tests):
    out = bytearray(struct.pack("<I", len(tests)))
    for t in tests:
        for st in ("initial", "final"):
            s = t[st]
            out += struct.pack("<HHBHHHBHBB", s["pc"], s["s"], s["p"], s["a"], s["x"],
                               s["y"], s["dbr"], s["d"], s["pbr"], s["e"])
        ri, rf = t["initial"]["ram"], t["final"]["ram"]
        out += struct.pack("<HH", len(ri), len(rf))
        for a, v in ri + rf:
            out += struct.pack("<I", a | v << 24)
        cy = t["cycles"]
        out += struct.pack("<H", len(cy))
        for a, v, f in cy:
            fl = ((f[0] == "d") | (f[1] == "p") << 1 | (f[2] == "v") << 2 |
                  (f[3] == "w") << 3 | (f[7] == "l") << 4 | (v is None) << 5 | (a is None) << 6)
            out += struct.pack("<IB", (a or 0) | fl << 24, 0 if v is None else v)
    return out


def one(outdir, name):
    path = os.path.join(outdir, name + ".bin")
    if os.path.exists(path):
        return name, "kept"
    with urllib.request.urlopen(f"{RAW}/{name}.json") as r:
        tests = json.loads(r.read())
    data = convert(tests)
    with open(path + ".tmp", "wb") as f:
        f.write(data)
    os.rename(path + ".tmp", path)
    return name, len(tests)


def main():
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    names = sys.argv[2:] or [f"{op:02x}.{m}" for op in range(256) for m in "en"]
    with concurrent.futures.ThreadPoolExecutor(6) as ex:
        for name, n in ex.map(lambda n: one(outdir, n), names):
            print(name, n, flush=True)


if __name__ == "__main__":
    main()
