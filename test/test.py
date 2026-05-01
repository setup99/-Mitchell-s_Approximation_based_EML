# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer


async def wait_cycles(dut, cycles: int = 1) -> None:
    for _ in range(cycles):
        await RisingEdge(dut.clk)


def q6_6_to_real(value: int) -> float:
    signed = value if value < 0x800 else value - 4096
    return signed / 64.0


def real_to_q6_6(value: float) -> int:
    scaled = int(round(value * 64.0)) & 0xFFF
    return scaled


def spi_vector(cs_n: int, sclk: int, mosi: int) -> int:
    return (cs_n << 2) | (sclk << 1) | (mosi << 0)


async def spi_xfer(dut, frame: int) -> int:
    """Transfer a 16-bit SPI frame and return the captured 16-bit response."""
    dut.uio_in.value = spi_vector(1, 0, 0)
    await wait_cycles(dut, 4)

    dut.uio_in.value = spi_vector(0, 0, 0)
    await wait_cycles(dut, 4)

    cap = 0
    for bit_idx in range(15, -1, -1):
        mosi = (frame >> bit_idx) & 1
        dut.uio_in.value = spi_vector(0, 0, mosi)
        await wait_cycles(dut, 3)

        miso = int(dut.uio_out.value) & 1
        cap = (cap << 1) | miso
        cocotb.log.info(f"spi_xfer bit={bit_idx} mosi={mosi} miso={miso} cap=0x{cap:04x}")

        dut.uio_in.value = spi_vector(0, 1, mosi)
        await wait_cycles(dut, 4)

        dut.uio_in.value = spi_vector(0, 0, mosi)
        await wait_cycles(dut, 4)

    dut.uio_in.value = spi_vector(1, 0, 0)
    await wait_cycles(dut, 4)
    cocotb.log.info(f"spi_xfer frame=0x{frame:04x} cap=0x{cap:04x}")
    return cap


async def write_reg(dut, addr: int, data: int) -> None:
    frame = (0 << 15) | (addr << 12) | (data & 0xFFF)
    await spi_xfer(dut, frame)


async def read_res(dut) -> tuple[int, bool]:
    frame = (1 << 15) | (3 << 12)
    raw = await spi_xfer(dut, frame)
    return raw & 0xFFF, bool((raw >> 12) & 1)


async def chk(dut, expected: float, tol: float) -> None:
    result, ovf = await read_res(dut)
    actual = q6_6_to_real(result)
    assert not ovf, f"Overflow asserted unexpectedly, raw={result:04x}"
    assert abs(actual - expected) <= tol, f"expected {expected:.4f}, got {actual:.4f}"


@cocotb.test()
async def test_eml_spi_full(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit='ns').start())

    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await Timer(200, unit='ns')
    dut.rst_n.value = 1
    await Timer(200, unit='ns')

    # [1] Feed-forward: eml(0,1) = 1.0
    await write_reg(dut, 1, real_to_q6_6(0.0))
    await write_reg(dut, 2, real_to_q6_6(1.0))
    await write_reg(dut, 0, 0b000000000100)
    await Timer(1000, unit='ns')
    await chk(dut, 1.0, 0.05)

    # [2] Exponential value: eml(1,1) ≈ e
    await write_reg(dut, 1, real_to_q6_6(1.0))
    await write_reg(dut, 2, real_to_q6_6(1.0))
    await write_reg(dut, 0, 0b000000000100)
    await Timer(1000, unit='ns')
    await chk(dut, 2.718, 0.20)

    # [3] Iteration mode 11 (cross-feedback)
    # Seed the feedback register with eml(0,1)=1.0 before iterating.
    await write_reg(dut, 1, real_to_q6_6(0.0))
    await write_reg(dut, 2, real_to_q6_6(1.0))
    await write_reg(dut, 0, 0b000000000100)
    await Timer(1000, unit='ns')
    await chk(dut, 1.0, 0.05)

    await write_reg(dut, 0, 0b000000000111)
    await Timer(500, unit='ns')
    result, ovf = await read_res(dut)
    first_val = q6_6_to_real(result)

    await write_reg(dut, 0, 0b000000000111)
    await Timer(500, unit='ns')
    result, ovf = await read_res(dut)
    second_val = q6_6_to_real(result)

    await write_reg(dut, 0, 0b000000000111)
    await Timer(500, unit='ns')
    result, ovf = await read_res(dut)
    third_val = q6_6_to_real(result)

    # [3] Saturation / overflow latch check
    assert third_val > 30.0 and ovf, f"Expected saturation & OVF latched, got {third_val:.4f}, ovf={ovf}"

    # [4] Edge case y=0 overflow
    await write_reg(dut, 1, real_to_q6_6(0.0))
    await write_reg(dut, 2, real_to_q6_6(0.0))
    await write_reg(dut, 0, 0b000000000100)
    await Timer(1000, unit='ns')
    result, ovf = await read_res(dut)
    assert ovf, "Expected overflow flag when y=0"
