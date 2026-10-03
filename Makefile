# ============================================================
# Configuration
# ============================================================

TOP       := top
RTL       := rtl/top.v rtl/m_axis.v rtl/s_axis.v
TB        := sim/main.cpp

BUILD_DIR := obj_dir
EXEC      := $(BUILD_DIR)/V$(TOP)
# Nombre fijado por $$dumpfile en sim/top_tb.v
VCD       := top_tb.vcd

# Icarus
IV_TB     := sim/top_tb.v
IV_OUT    := sim/top_tb.vvp

# ============================================================
# Tools
# ============================================================

VERILATOR := verilator
IVERILOG  := iverilog
VVP       := vvp
GTKWAVE   := gtkwave

# ============================================================
# Verilator
# ============================================================

LINT_FLAGS := \
	-Wall \
	-Wno-WIDTHEXPAND \
	-Wno-UNUSEDSIGNAL \
	--top-module $(TOP)

VERILATOR_FLAGS := \
	--cc \
	--exe \
	--build \
	--trace \
	$(LINT_FLAGS) \
	--Mdir $(BUILD_DIR)

SDL_CFLAGS := $(shell sdl2-config --cflags)
SDL_LIBS   := $(shell sdl2-config --libs)

# ============================================================
# Targets
# ============================================================

all: $(EXEC)

$(EXEC): $(RTL) $(TB)
	$(VERILATOR) $(VERILATOR_FLAGS) \
		$(RTL) $(TB) \
		-CFLAGS "$(SDL_CFLAGS)" \
		-LDFLAGS "$(SDL_LIBS)"

run: $(EXEC)
	./$(EXEC)

# ---- Icarus: timing / protocolo ----

$(IV_OUT): $(RTL) $(IV_TB)
	$(IVERILOG) -g2012 -Wall -o $@ $(IV_TB) $(RTL)

sim-iv: $(IV_OUT)
	$(VVP) $(IV_OUT)

$(VCD): $(IV_OUT)
	$(VVP) $(IV_OUT)

wave: $(VCD)
	$(GTKWAVE) $(VCD) &

lint:
	$(VERILATOR) --lint-only $(LINT_FLAGS) $(RTL)

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(VCD) $(IV_OUT)

.PHONY: all run sim-iv wave lint clean