#!/usr/bin/env python3
"""
gatesim.py - bit-parallel gate-level simulator and stuck-at fault simulator
for Yosys JSON netlists made of Yosys internal gate cells ($_AND_, $_MUX_, ...).

Bit-parallel idea
-----------------
The ALU has 13 input bits, so the complete input space is 2^13 = 8192
vectors. Every net is represented by ONE Python integer of 8192 bits: bit i
of that integer is the logic value of the net for input vector i. A gate is
then evaluated for all 8192 vectors with a single bitwise operation
(AND -> &, XOR -> ^, NOT -> ^MASK, ...). Exhaustive simulation of the whole
netlist is one pass over the gates in topological order, and a stuck-at fault
is simulated by overriding one net with all-0 or all-1.

Vector index encoding (identical to tb/tb_alu4_exhaustive.v):
    i = {op[3:0], a[3:0], b[3:0], cin}  ->  i = op<<9 | a<<5 | b<<1 | cin
"""
import json

NVEC = 1 << 13
MASK = (1 << NVEC) - 1

# static-CMOS transistor-count estimate per generic gate (used for area)
TRANSISTORS = {"$_NOT_": 2, "$_BUF_": 4, "$_NAND_": 4, "$_NOR_": 4, "$_AND_": 6,
               "$_OR_": 6, "$_ANDNOT_": 6, "$_ORNOT_": 6, "$_XOR_": 12,
               "$_XNOR_": 12, "$_MUX_": 12}

EVAL = {
    "$_BUF_":    lambda a: a[0],
    "$_NOT_":    lambda a: a[0] ^ MASK,
    "$_AND_":    lambda a: a[0] & a[1],
    "$_NAND_":   lambda a: (a[0] & a[1]) ^ MASK,
    "$_OR_":     lambda a: a[0] | a[1],
    "$_NOR_":    lambda a: (a[0] | a[1]) ^ MASK,
    "$_XOR_":    lambda a: a[0] ^ a[1],
    "$_XNOR_":   lambda a: a[0] ^ a[1] ^ MASK,
    "$_ANDNOT_": lambda a: a[0] & (a[1] ^ MASK),
    "$_ORNOT_":  lambda a: a[0] | (a[1] ^ MASK),
    "$_MUX_":    lambda a: (a[0] & (a[2] ^ MASK)) | (a[1] & a[2]),   # S ? B : A
}
PIN_ORDER = {"$_MUX_": ("A", "B", "S"), "$_NOT_": ("A",), "$_BUF_": ("A",)}


def _pattern(k):
    """integer whose bit i is bit k of the vector index i"""
    p, block = 0, (1 << (1 << k)) - 1          # 2^k ones
    period = 1 << (k + 1)
    for start in range(1 << k, NVEC, period):
        p |= block << start
    return p


INDEX_BITS = [_pattern(k) for k in range(13)]


def input_patterns():
    """port-name -> list of 8192-bit integers, LSB first"""
    return {"cin": [INDEX_BITS[0]],
            "b":   [INDEX_BITS[1 + j] for j in range(4)],
            "a":   [INDEX_BITS[5 + j] for j in range(4)],
            "op":  [INDEX_BITS[9 + j] for j in range(4)]}


def op_masks():
    """opcode -> 8192-bit mask of the vectors that use that opcode"""
    out = []
    for o in range(16):
        m = MASK
        for j in range(4):
            m &= INDEX_BITS[9 + j] if (o >> j) & 1 else INDEX_BITS[9 + j] ^ MASK
        out.append(m)
    return out


def reference_outputs():
    """Python reference model, returns port -> list of bit-pattern integers"""
    res = {"r": [0] * 4, "c": [0], "v": [0], "z": [0], "n": [0]}
    for i in range(NVEC):
        op, a, b, cin = i >> 9, (i >> 5) & 15, (i >> 1) & 15, i & 1
        sa, sb = a - 16 * (a > 7), b - 16 * (b > 7)
        c = v = 0
        if op <= 5:
            x, sx = [(a + b, sa + sb), (a + b + cin, sa + sb + cin), (a - b, sa - sb),
                     (a - b - cin, sa - sb - cin), (a + 1, sa + 1), (a - 1, sa - 1)][op]
            r = x & 15
            c = [a + b > 15, a + b + cin > 15, a >= b, a >= b + cin, a == 15, a != 0][op]
            v = not (-8 <= sx <= 7)
        else:
            r = {6: a & b, 7: a | b, 8: a ^ b, 9: ~(a | b) & 15, 10: ~a & 15,
                 11: (a << 1) & 15, 12: a >> 1, 13: (a >> 1) | (a & 8),
                 14: ((a << 1) | (a >> 3)) & 15, 15: (a >> 1) | ((a & 1) << 3)}[op]
            c = {11: a >> 3, 12: a & 1, 13: a & 1, 14: a >> 3, 15: a & 1}.get(op, 0)
        for j in range(4):
            if (r >> j) & 1: res["r"][j] |= 1 << i
        if c: res["c"][0] |= 1 << i
        if v: res["v"][0] |= 1 << i
        if r == 0: res["z"][0] |= 1 << i
        if r & 8: res["n"][0] |= 1 << i
    return res


class Netlist:
    def __init__(self, json_path):
        d = json.load(open(json_path))
        mods = d["modules"]
        top = [m for m in mods if mods[m].get("attributes", {}).get("top")]
        self.name = top[0] if top else list(mods)[0]
        m = mods[self.name]
        self.inputs, self.outputs = {}, {}
        for p, info in m["ports"].items():
            (self.inputs if info["direction"] == "input" else self.outputs)[p] = info["bits"]
        # preferred readable name for every net bit
        self.net_name = {}
        for nm, info in sorted(m["netnames"].items(), key=lambda kv: (kv[1].get("hide_name", 0), len(kv[0]))):
            for k, bit in enumerate(info["bits"]):
                if isinstance(bit, int) and bit not in self.net_name:
                    self.net_name[bit] = nm if len(info["bits"]) == 1 else f"{nm}[{k}]"
        raw = []
        for cname, c in m["cells"].items():
            t = c["type"]
            if t not in EVAL:
                raise ValueError(f"unsupported cell type {t} in {json_path}")
            pins = PIN_ORDER.get(t, ("A", "B"))
            raw.append((cname, t, [c["connections"][p][0] for p in pins], c["connections"]["Y"][0]))
        # topological order
        driven = {r[3]: r for r in raw}
        order, done, temp = [], set(), set()

        def visit(bit):
            if bit in done or bit not in driven:
                return
            if bit in temp:
                raise ValueError("combinational loop")
            temp.add(bit)
            for x in driven[bit][2]:
                if isinstance(x, int):
                    visit(x)
            temp.discard(bit); done.add(bit); order.append(driven[bit])

        import sys
        sys.setrecursionlimit(10000)
        for r in raw:
            visit(r[3])
        self.cells = order

    # ---------------------------------------------------------------- stats
    def stats(self):
        by = {}
        for _, t, _, _ in self.cells:
            by[t] = by.get(t, 0) + 1
        lvl = {}
        for _, t, ins, out in self.cells:
            lvl[out] = 1 + max([lvl.get(x, 0) for x in ins if isinstance(x, int)] + [0])
        depth = max([lvl.get(b, 0) for bits in self.outputs.values() for b in bits if isinstance(b, int)] + [0])
        return {"cells": len(self.cells),
                "transistors": sum(TRANSISTORS[t] * n for t, n in by.items()),
                "depth": depth,
                "by_type": dict(sorted(by.items()))}

    def cell_of(self, bit):
        for cname, t, ins, out in self.cells:
            if out == bit:
                return cname
        return None

    # ---------------------------------------------------------------- sites
    def fault_sites(self):
        """every non-constant net bit: primary-input bits + every gate output"""
        sites = []
        for p, bits in self.inputs.items():
            for b in bits:
                sites.append((b, "PI", f"{p}[{bits.index(b)}]" if len(bits) > 1 else p))
        for cname, t, ins, out in self.cells:
            sites.append((out, cname, self.net_name.get(out, f"n{out}")))
        return sites

    # ---------------------------------------------------------------- sim
    def simulate(self, fault=None):
        """fault = (bit, 0|1) or None. Returns output port -> list of ints"""
        val = {"0": 0, "1": MASK, "x": 0, "z": 0}
        pat = input_patterns()
        for p, bits in self.inputs.items():
            for k, b in enumerate(bits):
                val[b] = pat[p][k]
        fb, fv = (fault if fault else (None, None))
        if fb is not None and fb in val:
            val[fb] = MASK if fv else 0
        for _, t, ins, out in self.cells:
            if out == fb:
                val[out] = MASK if fv else 0
            else:
                val[out] = EVAL[t]([val[x] for x in ins])
        return {p: [val[b] for b in bits] for p, bits in self.outputs.items()}
