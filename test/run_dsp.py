
from pathlib import Path
import os

from cocotb_tools.runner import get_runner

ROOT = Path(__file__).resolve().parents[1]

# Make our Python golden model importable
os.environ["PYTHONPATH"] = (
    str(ROOT / "test")
    + os.pathsep
    + os.environ.get("PYTHONPATH", "")
)

runner = get_runner("icarus")

runner.build(
    sources=[
        ROOT / "src" / "project.v",
        ROOT / "src" / "cordic_serial.v",
        ROOT / "src" / "dsp_fir_iir.v",
    ],
    hdl_toplevel="tt_um_cordic_iter",
    build_dir=ROOT / "sim_build",
    always=True,
    timescale=("1ns", "1ps"),
    waves=True,
)



runner.test(
    hdl_toplevel="tt_um_cordic_iter",
    test_module="test_dsp_only",
    waves=True,
)