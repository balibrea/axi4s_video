# ============================================================
# Configuration
# ============================================================

TOP       := top
RTL       := top.v m_axis.v s_axis.v
TB        := main.cpp

BUILD_DIR := obj_dir
EXEC      := $(BUILD_DIR)/V$(TOP)
VCD       := waveform.vcd

# Icarus
IV_TB     := tb_top.v
IV_OUT    := tb_top.vvp

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

VERILATOR_FLAGS := \
	--cc \
	--exe \
	--build \
	--trace \
	-Wall \
	-Wno-WIDTHEXPAND \
	-Wno-UNUSEDSIGNAL \
	--Mdir $(BUILD_DIR) \
	--top-module $(TOP)

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

wave: sim-iv
	$(GTKWAVE) $(VCD) &

lint:
	$(VERILATOR) --lint-only -Wall --top-module $(TOP) $(RTL)

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(VCD) $(IV_OUT)

.PHONY: all run sim-iv wave lint clean