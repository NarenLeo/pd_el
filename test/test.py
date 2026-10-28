import math
import random

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

from cordic_model import cordic, busy_cycles, s16, M16, to_q, angle_to_z


def ui(sdi=0, sh=0, start=0, mode=0, comp=0, nsel=0):
    return sdi | (sh << 1) | (start << 2) | (mode << 3) | (comp << 4) | (nsel << 5)


async def reset(dut):
    cocotb.start_soon(Clock(dut.clk, 10, "ns").start())
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)


async def shift48(dut, tx, cfg):
    """Shift 48 bits in (MSB first) while reading 48 bits out."""
    rx = 0
    for k in range(47, -1, -1):
        dut.ui_in.value = ui(sdi=(tx >> k) & 1, sh=1, **cfg)
        await Timer(1, "ns")
        rx |= (int(dut.uo_out.value) & 1) << k
        await RisingEdge(dut.clk)
    dut.ui_in.value = ui(**cfg)
    return rx


async def run(dut, mode, comp, nsel, x, y, z):
    """Load operands, start, wait for completion, read results. Returns (x, y, z, busy_cycles)."""
    cfg = dict(mode=mode, comp=comp, nsel=nsel)
    await shift48(dut, ((x & M16) << 32) | ((y & M16) << 16) | (z & M16), cfg)
    dut.ui_in.value = ui(start=1, **cfg)
    await RisingEdge(dut.clk)
    dut.ui_in.value = ui(**cfg)
    await Timer(1, "ns")
    cycles = 0
    while (int(dut.uo_out.value) >> 1) & 1:          # busy
        await RisingEdge(dut.clk)
        await Timer(1, "ns")
        cycles += 1
    assert (int(dut.uo_out.value) >> 2) & 1, "done flag not set"
    rx = await shift48(dut, 0, cfg)
    return (rx >> 32) & M16, (rx >> 16) & M16, rx & M16, cycles


@cocotb.test()
async def test_bit_exact_vs_model(dut):
    """RTL must match the Python golden model exactly (raw integers), all modes and N."""
    await reset(dut)
    rnd = random.Random(1234)
    n_tests = 0
    for mode in (0, 1):
        for comp in (0, 1):
            for nsel in range(8):
                for _ in range(12):
                    x = rnd.randint(-9830, 9830)           # |v| <= ~1.2*sqrt2
                    y = rnd.randint(-9830, 9830)
                    z = 0 if mode else rnd.randint(0, M16)
                    got = await run(dut, mode, comp, nsel, x, y, z)
                    exp = cordic(x, y, z, mode, comp, nsel)
                    assert got[:3] == exp, (
                        f"mismatch mode={mode} comp={comp} N={5+nsel} in=({x},{y},{z}) "
                        f"rtl={got[:3]} model={exp}")
                    assert got[3] == busy_cycles(comp, nsel), f"latency {got[3]}"
                    n_tests += 1
    dut._log.info(f"{n_tests} random cases bit-exact")


@cocotb.test()
async def test_accuracy_vs_float(dut):
    """Compare against floating-point math for N=12, compensation on."""
    await reset(dut)
    rnd = random.Random(7)
    worst_rot = worst_mag = worst_ph = 0.0
    for _ in range(100):
        xr, yr = rnd.uniform(-1.2, 1.2), rnd.uniform(-1.2, 1.2)
        th = rnd.uniform(-math.pi, math.pi * 0.9999)
        x, y, z = to_q(xr), to_q(yr), int(th / math.pi * 32768) & M16
        ox, oy, _, _ = await run(dut, 0, 1, 7, x, y, z)
        t = s16(z) / 32768 * math.pi
        ex = s16(x) * math.cos(t) - s16(y) * math.sin(t)
        ey = s16(x) * math.sin(t) + s16(y) * math.cos(t)
        worst_rot = max(worst_rot, abs(s16(ox) - ex), abs(s16(oy) - ey))

        if math.hypot(xr, yr) >= 0.25:
            mx, my, mz, _ = await run(dut, 1, 1, 7, x, y, 0)
            worst_mag = max(worst_mag, abs(s16(mx) - math.hypot(s16(x), s16(y))))
            ez = math.atan2(s16(y), s16(x)) / math.pi * 32768
            d = (s16(mz) - ez + 32768) % 65536 - 32768
            worst_ph = max(worst_ph, abs(d))
    dut._log.info(f"worst error (LSB): rotation {worst_rot:.1f}, magnitude {worst_mag:.1f}, phase {worst_ph:.1f}")
    assert worst_rot < 20 and worst_mag < 20 and worst_ph < 40


@cocotb.test()
async def test_corner_cases(dut):
    """Axis rotations, pi pre-rotation, vectoring on the negative x axis."""
    await reset(dut)
    one = 8192
    for deg, ex, ey in [(90, 0, one), (-90, 0, -one), (180, -one, 0), (0, one, 0), (135, -5793, 5793)]:
        ox, oy, _, _ = await run(dut, 0, 1, 7, one, 0, angle_to_z(deg))
        assert abs(s16(ox) - ex) <= 8 and abs(s16(oy) - ey) <= 8, (deg, s16(ox), s16(oy))
    mx, my, mz, _ = await run(dut, 1, 1, 7, -one & M16, 0, 0)
    d = (s16(mz) - 32768 + 32768) % 65536 - 32768        # phase error vs +pi, wrapped
    assert abs(s16(mx) - one) <= 8 and abs(d) <= 16, (s16(mx), s16(mz))

