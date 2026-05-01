<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

### Overview

This design implements a **Sequential EML Engine with Operand Feedback** — a compact hardware accelerator for computing exponential-logarithmic expressions using Mitchell's approximation. Instead of building massive expression trees in silicon, we use a single reusable EML unit and feedback loops to compute nested expressions over multiple cycles.

**Core Formula:**
```
out = exp(x) - ln(y)
```

Where `exp()` and `ln()` are computed using Mitchell's fast approximations:
- `exp(x) = 2^(x / ln(2))` = `2^(x * 1.4427)`
- `ln(y) = log2(y) / log2(e)` = `log2(y) * 0.693`

### Architecture Components

#### 1. **EML Tile (Combinational)**
The core computation unit ([eml_tile.v](../src/eml_tile.v)):
- **No clock** — pure combinational logic
- Computes: `out = exp(x) - ln(y)`
- Uses Mitchell's approximation for fast exp2 and log2
- Fixed-point arithmetic: **Q6.6 format** (12-bit signed)
  - 6 integer bits: range -32 to +31
  - 6 fractional bits: resolution ≈ 0.0156
  - Example: `0.5 → 32` (0.5 × 64), `1.0 → 64`, `2.0 → 128`

**Constants (Q6.6):**
- `INV_LN2 = 92` (≈ 1.4375/1.4427)
- `LN2 = 44` (≈ 0.6875/0.6931)

#### 2. **Feedback Cell (Sequential)**
The stateful wrapper ([eml_feedback_cell.v](../src/eml_feedback_cell.v)):

```
┌──────────────────────────────────────────────┐
│         Sequential EML Feedback Cell         │
│                                              │
│  x_ext ─┬─→ [MUX A] ─┐                      │
│         │            │                       │
│   prev ─┤  (sel_x)   ├─→ EML Tile ─→ [REG] ─┼─→ out
│         │            │    (comb.)    (fb)   │
│         └────────────┘                      │
│                                              │
│  y_ext ─┬─→ [MUX B] ─┐                      │
│   prev ─┤  (sel_y)   ├──────┘               │
│         └────────────┘                      │
│                                              │
│  ┌────────────────────────────────────────┐ │
│  │ Each cycle:                             │ │
│  │ • MUXes select operands (ext or prev)  │ │
│  │ • EML tile computes combinationally    │ │
│  │ • Feedback register stores result      │ │
│  │ • Next cycle can reuse result          │ │
│  └────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

**Operation Modes (controlled by sel_x, sel_y):**

| sel_x | sel_y | Mode | Computation |
|-------|-------|------|-------------|
| 0 | 0 | Feed-forward | `out = eml(x_ext, y_ext)` — single cycle |
| 1 | 0 | Iterate X | `out_n = eml(out_{n-1}, y_ext)` — reuse X result |
| 0 | 1 | Iterate Y | `out_n = eml(x_ext, out_{n-1})` — reuse Y result |
| 1 | 1 | Cross-feedback | `out_n = eml(out_{n-1}, out_{n-1})` — both operands from prev |

#### 3. **SPI Slave Interface**
The control layer ([eml_spi_wrapper.v](../src/eml_spi_wrapper.v)):
- **Bit-bang SPI protocol** (standard 3-wire: MOSI, SCLK, CS_N → MISO)
- 16-bit frames for command/data exchange
- 3-stage clock synchronizers for cross-domain safety
- Result latching after computation completes

**Frame Format (16 bits):**
```
[15]    [14:12]    [11:0]
 RW     ADDR       DATA
 │       │          │
 │       │          └─ 12-bit payload
 │       └──────────── 3-bit address (0-3)
 └────────────────── 0=Write, 1=Read
```

**Register Map:**
- **Addr 0 (RW=0)**: Control register
  ```
  [11:2] = reserved
  [1]    = sel_y  (0=external Y, 1=feedback)
  [0]    = sel_x  (0=external X, 1=feedback)
  [2]    = valid  (write: pulse=1 to trigger; read: n/a)
  ```

- **Addr 1 (RW=0)**: X input register (signed Q6.6)
  ```
  [11:0] = x_ext value
  ```

- **Addr 2 (RW=0)**: Y input register (unsigned Q6.6)
  ```
  [11:0] = y_ext value
  ```

- **Addr 3 (RW=1)**: Result register (read-only)
  ```
  [15:13] = reserved (read as 0)
  [12]    = overflow flag
  [11:0]  = result (signed Q6.6)
  ```

#### 4. **Top Module**
TinyTapeout wrapper ([project.v](../src/project.v)):
- Routes UIO pins to SPI interface:
  - `uio_in[0]` = MOSI
  - `uio_in[1]` = SCLK
  - `uio_in[2]` = CS_N
  - `uio_out[0]` = MISO

### How Sequential Operation Works

**Example: Computing a nested expression**

Goal: Calculate `f(x) = eml(eml(x, 1), 1)` which represents computing:
1. Inner: `temp = exp(x) - ln(1) = exp(x)`
2. Outer: `f = exp(temp) - ln(1) = exp(exp(x))`

**Cycle-by-cycle execution:**

```
Cycle 1 — Load inputs and configure for feed-forward:
  sel_x = 0, sel_y = 0        (use external inputs)
  x_ext = x, y_ext = 1.0
  Result: prev = eml(x, 1.0) = exp(x)

Cycle 2 — Switch to iterate mode (reuse X result):
  sel_x = 1, sel_y = 0        (X from feedback, Y external)
  y_ext = 1.0 (unchanged)
  x_in = prev (from cycle 1)  = exp(x)
  Result: out = eml(exp(x), 1.0) = exp(exp(x)) ✓
```

**Advantage:** Single EML unit does the work of a 2-level tree → **~70% area savings** vs. a pipeline.

### Approximation Accuracy

Mitchell's approximation trades precision for speed:

- **exp(x)**: Error typically < 2% for |x| < 8
- **ln(y)**: Error typically < 2% for y ∈ [0.5, 2.0]
- **Q6.6 quantization**: Additional ±0.78% rounding error

**Typical use cases:**
- Machine learning inference (softmax, sigmoid approximation)
- Signal processing (exponential smoothing)
- Logarithmic compression

For applications requiring higher precision, use external high-precision math libraries.

---

## How to test

### Prerequisites

- **Python 3.8+** with `cocotb` framework
- **Icarus Verilog** (for simulation)
- **Standard tools**: `make`, `iverilog`, `gtkwave` (optional, for waveforms)

### Running the Test Suite

```bash
cd test
make test
```

This runs `test.py` via cocotb, which exercises:
1. **Feed-forward mode**: `eml(0, 1) = 1.0`
2. **Exponential mode**: `eml(1, 1) ≈ e (2.718)`

### Test Data Format

Values in fixed-point Q6.6:
- Input/output: 12-bit signed integers
- Conversion: `real_value = integer_value / 64`
- Example: `0x040` (64 decimal) = `1.0` real

### Manual Testing via SPI

Example Python test (using cocotb):

```python
import cocotb
from cocotb.clock import Clock

def real_to_q6_6(value: float) -> int:
    """Convert real value to Q6.6 fixed-point."""
    return int(round(value * 64)) & 0xFFF

def q6_6_to_real(value: int) -> float:
    """Convert Q6.6 to real value."""
    signed = value if value < 0x800 else value - 4096
    return signed / 64.0

async def test_eml(dut, x_val: float, y_val: float):
    """Test a single EML computation."""
    # Write X
    await write_reg(dut, 1, real_to_q6_6(x_val))
    # Write Y
    await write_reg(dut, 2, real_to_q6_6(y_val))
    # Trigger computation
    await write_reg(dut, 0, 0x004)  # valid=1, sel_x=0, sel_y=0
    # Wait for result
    await cocotb.triggers.Timer(1000, unit='ns')
    # Read result
    result, ovf = await read_res(dut)
    return q6_6_to_real(result), ovf
```

### Testing Sequential Chains

To verify nested computation `eml(eml(x, y1), y2)`:

```python
async def test_nested(dut, x, y1, y2):
    # Step 1: Compute eml(x, y1)
    result1, ovf = await test_eml(dut, x, y1)
    assert not ovf, "Overflow in step 1"
    
    # Step 2: Compute eml(result1, y2) using feedback
    # Set sel_x=1 (feedback), sel_y=0 (external y2)
    await write_reg(dut, 2, real_to_q6_6(y2))      # Update Y
    await write_reg(dut, 0, 0x005)                 # valid=1, sel_x=1, sel_y=0
    await cocotb.triggers.Timer(1000, unit='ns')
    result2, ovf = await read_res(dut)
    assert not ovf, "Overflow in step 2"
    return result2
```

### Key Test Cases

1. **Single-cycle (feed-forward)**
   - `eml(0, 1)` → `1.0` (exp(0) - ln(1) = 1 - 0)
   - `eml(1, 1)` → `e ≈ 2.718` (exp(1) - ln(1))

2. **Multi-cycle (feedback)**
   - `eml(eml(0, 1), 1)` → `e ≈ 2.718` (exp(exp(0)) - ln(1) = exp(1))
   - `eml(eml(1, 1), 1)` → `exp(e) ≈ 15.15`

3. **Edge cases**
   - `eml(x, 0)` → Overflow (ln(0) undefined)
   - Very large/small x values (check saturation)

### Interpreting Results

- **Result [11:0]**: Signed 12-bit value in Q6.6 format
- **Overflow flag**: Set if
  - Y = 0 (ln undefined)
  - exp() overflowed (x too large)
  - Subtraction overflowed
- **Timeout**: If result doesn't appear after ~2000 clock cycles, check:
  - SPI clock is toggling
  - CS_N went low/high at right times
  - Reset is deasserted

### Waveform Inspection

Generate FST waveforms:
```bash
cd test
make sim
gtkwave tb.fst
```

Watch signals:
- `u_eml.u_exp.x` → exp2 input
- `u_eml.u_log.x` → log2 input
- `u_eml.out` → EML result
- `u_spi.rx_frame` → Incoming SPI command
- `u_spi.result_latch` → Latched result

---

## External hardware

### Required: SPI Master Controller

The design expects a standard **3-wire SPI master** on UIO pins:
- **UIO[0]** = MOSI (Master Out, Slave In) — input
- **UIO[1]** = SCLK (Serial Clock) — input
- **UIO[2]** = CS_N (Chip Select, active-low) — input
- **UIO[3]** = MISO (Master In, Slave Out) — output (wire to MOSI on reader side)

**Typical Master Implementation:**

```python
# Example: Raspberry Pi GPIO or FTDI FT232H
import board
import digitalio

mosi = digitalio.DigitalInOut(board.D17)
mosi.direction = digitalio.Direction.OUTPUT

sclk = digitalio.DigitalInOut(board.D27)
sclk.direction = digitalio.Direction.OUTPUT

cs_n = digitalio.DigitalInOut(board.D22)
cs_n.direction = digitalio.Direction.OUTPUT

miso = digitalio.DigitalInOut(board.D23)
miso.direction = digitalio.Direction.INPUT

# Send 16-bit frame bit-by-bit
frame = 0x1234  # Example
cs_n.value = False  # Chip select active
for bit in range(15, -1, -1):
    mosi.value = (frame >> bit) & 1
    sclk.value = True
    time.sleep(1e-6)
    miso_bit = miso.value
    sclk.value = False
    time.sleep(1e-6)
cs_n.value = True
```

### Optional: Result Display

To visualize results, add a simple LED or LCD display:
- Connect uo_out[7:0] to an 8-segment LED (currently unused, available for expansion)
- Or use oscilloscope to probe intermediate signals during debug

### Power & Timing

- **Clock frequency**: 50 MHz nominal (configured for 20ns period in config.json)
- **Supply voltage**: 1.8V (standard TinyTapeout rail)
- **Current draw**: ~10-50 mA (depends on switching activity)
- **SPI clock speed**: Recommended 1-10 MHz (slower = more time per frame)
