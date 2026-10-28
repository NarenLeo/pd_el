
# Run: make       (RTL simulation with Icarus + cocotb)
#      make clean

SIM ?= icarus
TOPLEVEL_LANG ?= verilog

SRC_DIR = $(PWD)/../src

VERILOG_SOURCES = $(SRC_DIR)/project.v

TOPLEVEL = tt_um_cordic_iter

# cocotb 2.x uses COCOTB_TEST_MODULES
# cocotb 1.x uses MODULE
COCOTB_TEST_MODULES = test
MODULE = test

export PYTHONPATH := $(PWD)/model:$(PYTHONPATH)

include $(shell cocotb-config --makefiles)/Makefile.sim
