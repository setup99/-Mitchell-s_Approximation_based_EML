# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# --- وظائف مساعدة للتعامل مع الأرقام الثابتة (Fixed Point Q6.6) ---

def q6_6_to_real(value: int) -> float:
    """تحويل القيمة من تنسيق Q6.6 إلى رقم حقيقي (float)."""
    signed = value if value < 0x800 else value - 4096
    return signed / 64.0


def real_to_q6_6(value: float) -> int:
    """تحويل رقم حقيقي إلى تنسيق Q6.6 (12-bit)."""
    scaled = int(round(value * 64.0)) & 0xFFF
    return scaled


# --- وظائف التحكم في SPI ---

def spi_vector(cs_n: int, sclk: int, mosi: int) -> int:
    """بناء ناقل الإدخال uio_in: CS=bit2, SCLK=bit1, MOSI=bit0."""
    return (cs_n << 2) | (sclk << 1) | (mosi << 0)


async def wait_cycles(dut, cycles: int = 1) -> None:
    for _ in range(cycles):
        await RisingEdge(dut.clk)


async def spi_xfer(dut, frame: int) -> int:
    """تبادل إطار 16-بت عبر SPI واستلام النتيجة."""
    cap = 0

    # التأكد من حالة البداية (CS_N High)
    dut.uio_in.value = spi_vector(1, 0, 0)
    await wait_cycles(dut, 5)

    # تفعيل الإرسال (CS_N Low)
    dut.uio_in.value = spi_vector(0, 0, 0)
    await wait_cycles(dut, 5)

    for bit_idx in range(15, -1, -1):
        mosi = (frame >> bit_idx) & 1

        # وضع البيانات على MOSI والانتظار قليلاً للاستقرار
        dut.uio_in.value = spi_vector(0, 0, mosi)
        await wait_cycles(dut, 4)

        # قراءة MISO من البت الأقل وزنًا (uio_out[0]) مع التعامل الآمن لقيم X/Z
        try:
            miso = int(dut.uio_out.value) & 1
        except ValueError:
            miso_str = str(dut.uio_out.value)
            miso_bit = miso_str[-1] if miso_str else '0'
            miso = int(miso_bit) if miso_bit in '01' else 0
        cap = (cap << 1) | miso

        # نبضة الساعة (Rising Edge)
        dut.uio_in.value = spi_vector(0, 1, mosi)
        await wait_cycles(dut, 8)

        # العودة للحالة المنخفضة (Falling Edge)
        dut.uio_in.value = spi_vector(0, 0, mosi)
        await wait_cycles(dut, 4)

    # إنهاء الإرسال (CS_N High)
    dut.uio_in.value = spi_vector(1, 0, 0)
    await wait_cycles(dut, 5)

    return cap


# --- وظائف سجلات التحكم ---

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


# --- الاختبار الرئيسي ---

@cocotb.test()
async def test_eml_spi_full(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit='ns').start())

    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = spi_vector(1, 0, 0)
    await Timer(1000, unit='ns')
    dut.rst_n.value = 1
    await Timer(1000, unit='ns')
    await wait_cycles(dut, 50)

    # [1] اختبار التغذية الأمامية: eml(0,1) = e^0 - ln(1) = 1.0
    await write_reg(dut, 1, real_to_q6_6(0.0))
    await write_reg(dut, 2, real_to_q6_6(1.0))
    await write_reg(dut, 0, 0b000000000100)
    await Timer(2000, unit='ns')
    await chk(dut, 1.0, 0.05)

    # [2] اختبار القيمة الأسية: eml(1,1) ≈ e^1 - ln(1) ≈ 2.718
    await write_reg(dut, 1, real_to_q6_6(1.0))
    await write_reg(dut, 2, real_to_q6_6(1.0))
    await write_reg(dut, 0, 0b000000000100)
    await Timer(2000, unit='ns')
    await chk(dut, 2.718, 0.20)

    # [3] وضع التغذية المرتدة (Iteration mode 11)
    await write_reg(dut, 1, real_to_q6_6(0.0))
    await write_reg(dut, 2, real_to_q6_6(1.0))
    await write_reg(dut, 0, 0b000000000100)
    await Timer(1000, unit='ns')

    for _ in range(3):
        await write_reg(dut, 0, 0b000000000111)
        await Timer(1000, unit='ns')

    result, ovf = await read_res(dut)
    final_val = q6_6_to_real(result)
    assert final_val > 30.0 or ovf, f"Expected saturation/OVF, got {final_val:.4f}, ovf={ovf}"

    # [4] حالة خاصة: Y=0 تؤدي لـ Overflow (بسبب اللوغاريتم)
    await write_reg(dut, 1, real_to_q6_6(0.0))
    await write_reg(dut, 2, real_to_q6_6(0.0))
    await write_reg(dut, 0, 0b000000000100)
    await Timer(1000, unit='ns')
    result, ovf = await read_res(dut)
    assert ovf, "Expected overflow flag when y=0"
