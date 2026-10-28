# ReCORDIC: Reconfigurable CORDIC Accelerator

## How it works

ReCORDIC is a compact, iterative hardware accelerator for vector rotation and vectoring calculations. It uses shift, add and subtract operations to perform calculations that would otherwise require trigonometric functions, square roots or general-purpose multiplication.

The design supports two operating modes:

- **Rotation mode (`MODE = 0`):** Rotates an input vector \((x,y)\) by an angle \(\theta\), producing the rotated coordinates.
- **Vectoring mode (`MODE = 1`):** Calculates the magnitude and phase of an input vector. The magnitude is returned in `x`, the residual vertical component in `y` should approach zero, and the phase is returned in `z`.

The accelerator reuses a shared arithmetic datapath and executes one CORDIC iteration per clock cycle. The number of iterations is configurable from 5 to 12, allowing a trade-off between numerical accuracy and execution time. Optional gain compensation uses five shift-add steps to correct the scale factor introduced by the CORDIC algorithm.

The controller includes a pre-rotation step to support angles outside the basic CORDIC convergence range. A `BUSY` output indicates that a calculation is in progress, and `DONE` indicates that the result is available.

### Number formats

The input and output words are 16-bit values.

- **X and Y:** Signed Q3.13 fixed-point values. Convert a raw signed integer to a real value by dividing by 8192. The representable range is approximately −4 to +3.9999. Keep the input vector magnitude within the recommended range of 2.0 or less to reduce overflow risk.
- **Z:** A 16-bit angle representation in which \(180^\circ\) corresponds to 32768 units. Convert a signed raw angle value to degrees by multiplying by \(180/32768\).
- **Iteration selection:** `NSEL = ui_in[7:5]`. The number of iterations is \(N = 5 + NSEL\), giving 5–12 iterations.
- **Gain compensation:** `GAIN_COMP = ui_in[4]`. Set it to 1 to request gain compensation or 0 to leave the CORDIC gain in the result.

Without gain compensation, the X and Y coordinates are scaled by the CORDIC gain. With compensation enabled, the output should more closely match the expected mathematical result.

### Serial interface

The design uses the eight `ui` input pins and eight `uo` output pins.

| Pin | Signal | Function |
|---|---|---|
| `ui[0]` | SDI | Serial data input |
| `ui[1]` | SH_EN | Enables serial shifting while high |
| `ui[2]` | START | Rising edge starts a calculation |
| `ui[3]` | MODE | 0 = rotation, 1 = vectoring |
| `ui[4]` | GAIN_COMP | Enables gain compensation |
| `ui[7:5]` | NSEL | Selects 5–12 iterations |
| `uo[1]` | BUSY | High while the controller is processing |
| `uo[2]` | DONE | High when the result is available |
| `uo[7:4]` | Iteration counter | Debug indication of the current iteration |

The intended serial transfer uses a 48-bit chain containing X, Y and Z.

**Load:** Shift 48 bits into the chain, most-significant bit first, in the order `X[15:0]`, `Y[15:0]`, `Z[15:0]`. Hold `SH_EN` high during the transfer.

**Start:** Set `MODE`, `GAIN_COMP` and `NSEL`, then generate a rising edge on `START`. The controller latches these settings when the operation begins. Do not issue another start while `BUSY` is high.

**Wait:** Monitor `BUSY` until it returns low. The result is then intended to be available, and `DONE` indicates completion.

**Read:** The intended interface shifts the 48-bit result out most-significant bit first in the order X, Y and Z. New input data can be shifted in during the same 48-clock transfer.

The serial output and result readback logic must be implemented and verified in the RTL before this protocol can be used on hardware.

## How to test

1. Apply a clock and hold `rst_n` low to reset the controller.
2. Release reset by setting `rst_n` high.
3. Load the 48-bit input operands in the specified order.
4. Set the mode, gain-compensation option and iteration selection.
5. Pulse `START` and wait for `BUSY` to return low.
6. Read the result using the verified serial output protocol.
7. Convert the raw X and Y outputs by dividing by 8192. Convert the raw Z output to degrees using \(180/32768\).
8. Compare the result with the expected mathematical value. Repeat with different angles, vector quadrants, iteration counts and gain-compensation settings.

### Worked example: Rotate by 30°

The simulation uses an input vector of \((1,0)\) and a rotation angle of approximately \(30^\circ\). Gain compensation is enabled and 12 iterations are selected.

**Input values**

- X = 8192, representing 1.0
- Y = 0, representing 0.0
- Z = 5461, representing approximately \(29.9982^\circ\)
- Mode = rotation
- Gain compensation = enabled
- Iterations = 12

The expected result is:

\[
x'=1\cos(30^\circ)\approx0.866025
\]

\[
y'=1\sin(30^\circ)=0.500000
\]

**Simulation output**

| Quantity | Expected | Simulated |
|---|---:|---:|
| X | 0.866025 | 0.865723 |
| Y | 0.500000 | 0.500000 |
| Residual angle Z | Approximately 0° | −0.010986° |

The simulated coordinates are close to the expected values. The small differences are consistent with fixed-point quantization and finite iteration accuracy.

## External hardware

No external hardware is required for RTL simulation. The design uses the Tiny Tapeout digital input, output and clock/reset interfaces.

For physical testing, a compatible Tiny Tapeout carrier board and a means of driving the digital inputs and observing the outputs may be used. No PMOD, LED display, sensor or other external peripheral is required by the design itself.
