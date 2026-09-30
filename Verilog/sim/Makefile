VERILATOR = verilator

SUPPRESS_FLAGS = -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-UNUSED -Wno-UNDRIVEN -Wno-WIDTH -Wno-EOFNEWLINE -Wno-LATCH -Wno-SYNCASYNCNET

# USE_LATCHES: Set to 1 (default) for transparent latch behavior (original hardware).
#              Set to 0 for edge-triggered flip-flop behavior (FPGA mode).
USE_LATCHES ?= 1

# VERILATOR_SIM is always defined for Verilator builds (enables bus ports, fast UART, sim RAM size).
# USE_LATCHES controls latch vs FF behavior independently.
SIM_DEFINES = -DVERILATOR_SIM
ifeq ($(USE_LATCHES),0)
  # Add FPGA_FF_MODE to override latch behavior while keeping VERILATOR_SIM for bus ports
  SIM_DEFINES += -DFPGA_FF_MODE
endif

# CACHE: Set to 1 (default) to build the CPU cache (today's behavior).
#        Set to 0 to compile it out (-DND120_NO_CACHE, CPU_MMU_CACHE_25.v):
#        omits the five cache memories + used-bit PAL, forces hit=0, and the
#        machine reports the cache as disabled - matches the Tang FPGA build.
CACHE ?= 1
ifeq ($(CACHE),0)
  SIM_DEFINES += -DND120_NO_CACHE
endif

# SKIP_WCS: pre-load the WCS and skip the microcode load phase (docs/skip-wcs-load.md).
# Requires the 32 wcs_*.hex files in this dir - the SIM variant:
#   cd Code/Microcode && python3 gen_wcs_image.py --sim && cp wcs-sim/wcs_*.hex ../../Verilog/sim/
# (patched word 0o2002, equal to this dir's AM27256_45133L.hex; the boards
# preload the raw word - decided 02-SEP-2026, see tests/microcode_sync.py).
# CPP_DEFINES also forwards the flag to the C++ testbench so it can trace from
# tick 0 (no load phase to skip).
# PANEL_CLOCK=1: emulate the MC68705/MM58274 clock path (IO_PANCAL_40.v ->
# PANCAL_68705_CLOCK.v) so TRR PANC / TRA PANS can set and read the hardware
# clock. Off by default so the golden traces/console are unchanged.
PANEL_CLOCK ?= 0
ifeq ($(PANEL_CLOCK),1)
  SIM_DEFINES += -DND120_PANEL_CLOCK
endif

CPP_DEFINES =
ifeq ($(SKIP_WCS),1)
  SIM_DEFINES += -DSKIP_WCS_LOAD
  CPP_DEFINES += -DSKIP_WCS_LOAD
endif

# BLOCKRAM: run the FPGA boards' own main-memory backend
# (MEM_RAM_49_BLOCKRAM) instead of the 6 MB behavioural sim RAM, so a board
# that will not boot can be REPRODUCED here rather than guessed at. Words per
# bank = 2**BLOCKRAM_BITS; the MiSTer build ships 15, Nexys's bramram
# variant used 16, and the RTL default of 12 is the Basys3 minimum.
#
#   make run SKIP_WCS=1 USE_LATCHES=0 BLOCKRAM=1
#   make run SKIP_WCS=1 USE_LATCHES=0 BLOCKRAM=1 BLOCKRAM_BITS=16
#
# Added 31-AUG-2026 - the MiSTer board would not reach an OPCOM prompt while
# this same sim did, and the memory backend was the biggest untested
# difference between them.
# UART_FRAMES: clocks per UART bit, handed to BOTH the RTL and the C++
# harness so the two agree. Unset = the RTL's fast sim UART (16 clocks/bit,
# hardcoded under VERILATOR_SIM) and the harness's matching default.
#
# Set it to the real board figure - 20 MHz / 115200 = 173 - to exercise
# ACTUAL console timing. Nothing else can: with the fast UART the sim reaches
# an OPCOM prompt while a board at real baud may not, and if only one half is
# changed the harness decodes the other's bit rate as garbage, which looks
# like a CPU fault (both traps hit on 31-AUG-2026).
#
#   make run SKIP_WCS=1 USE_LATCHES=0 BLOCKRAM=1 UART_FRAMES=173
ifneq ($(UART_FRAMES),)
  SIM_DEFINES += -DND120_UART_DELAY_FRAMES=$(UART_FRAMES)
  CPP_DEFINES += -DND120_UART_DELAY_FRAMES=$(UART_FRAMES)
endif

BLOCKRAM_BITS ?= 15
ifeq ($(BLOCKRAM),1)
  SIM_DEFINES += -DMAIN_RAM_BLOCKRAM -DND120_BLOCKRAM_ADDR_BITS=$(BLOCKRAM_BITS)
  CPP_DEFINES += -DND120_SIM_BLOCKRAM
endif

VERILATOR_FLAGS = --trace-fst -Wall --cc ../ND120_TOP.v  $(SUPPRESS_FLAGS) $(SIM_DEFINES)

#TOP_3202D_COMPONENTS = --I../circuit -I../../Shared/logisim   -I../../Shared/ndlib  -I../../Shared/support
TOP_3202D_COMPONENTS =  -I../Shared/logisim   -I../Shared/ndlib  -I../Shared/support -I../CPU-BOARD-3202/circuit

CGA_COMPONENTS = -I../DELILAH-CPU/CGA_ALU/circuit -I../DELILAH-CPU/CGA_DCD/circuit -I../DELILAH-CPU/CGA_IDBCTL/circuit -I../DELILAH-CPU/CGA_INTR/circuit -I../DELILAH-CPU/CGA_MAC/circuit -I../DELILAH-CPU/CGA_MIC/circuit -I../DELILAH-CPU/CGA_TESTMUX/circuit -I../DELILAH-CPU/CGA_TRAP/circuit -I../DELILAH-CPU/CGA_WRF/circuit -I../DELILAH-CPU/CGA/circuit
DGA_COMPONENTS = -I../DECODE-GateArray/DGA/circuit

#SHARED_COMPONENTS =  -I../circuit -y ../../Shared/ndlib -y ../../Shared/logisim --I../../Shared/gates-tmp # (was shared/gates - dir never existed)   --I../../PAL

# -I.. = the Verilog root, where ND120_CORE.v (instantiated by ND120_TOP.v) lives
VERILATOR_DIRS = -I.. $(TOP_3202D_COMPONENTS) $(CGA_COMPONENTS) $(DGA_COMPONENTS) -I../PAL
# Specify C++ source files here
CPP_SOURCES = test_nd120.cpp ../simDevices/NDDevices.cpp ../simDevices/NDBus.cpp

# Default target
all: test_nd120 run gtk

test_nd120: $(CPP_SOURCES)
	$(VERILATOR) $(VERILATOR_FLAGS) $(VERILATOR_DIRS) --exe $(CPP_SOURCES)  -CFLAGS "$(VERILATOR_DIRS)  -I../../simDevices $(CPP_DEFINES)"
	cd obj_dir && make -f VND120_TOP.mk VND120_TOP

clean:
	rm -rf obj_dir obj_dir_latch obj_dir_ff

# ---------------------------------------------------------------------------
# LOG SIZE CAP - enforced here, not remembered.
#
# "any log file you create are not allowed to excced 1GB" had to be stated in
# THREE separate sessions. A sim run that prints per-tick can fill a drive in
# minutes. ND120_LOG_CAP is a hard ceiling applied to any redirected run;
# override it deliberately (e.g. ND120_LOG_CAP=10G) for a campaign capture -
# 10 GB is the standing allowance for the oracle/campaign logs in
# $ND120_ORACLE_DIR.
ND120_LOG_CAP ?= 1G

run: test_nd120
	./obj_dir/VND120_TOP

# run-log: same run, but tee'd to a file that CANNOT exceed the cap.
# head -c closes the pipe at the limit, so the run stops writing rather than
# filling the disk. Use this whenever the output is being kept.
run-log: test_nd120
	@echo "[log cap $(ND120_LOG_CAP) -> $(or $(LOG),run.log)]"
	./obj_dir/VND120_TOP 2>&1 | head -c $(ND120_LOG_CAP) | tee $(or $(LOG),run.log)
	@sz=$$(du -h $(or $(LOG),run.log) | cut -f1); echo "[log $$sz]"; \
	 if [ "$$(stat -c%s $(or $(LOG),run.log))" -ge "$$(numfmt --from=iec $(ND120_LOG_CAP))" ]; then \
	   echo "WARNING: log hit the $(ND120_LOG_CAP) cap and was TRUNCATED - the run"; \
	   echo "         may have continued past what the file shows."; \
	 fi

gtk: run
	# FST format: compressed, indexed, much faster to load than VCD
	gtkwave waveform.fst top_3202d.gtkw &

# --- Latch vs FF comparison targets ---
COMPARE_SOURCES = latch_ff_compare.cpp ../simDevices/NDDevices.cpp ../simDevices/NDBus.cpp
COMPARE_VFLAGS = -Wall --cc ../ND120_TOP.v $(SUPPRESS_FLAGS) -Wno-SYNCASYNCNET

compare_latch: latch_ff_compare.cpp
	$(VERILATOR) $(COMPARE_VFLAGS) -DVERILATOR_SIM $(VERILATOR_DIRS) --exe $(COMPARE_SOURCES) -CFLAGS "$(VERILATOR_DIRS) -I../../simDevices" --Mdir obj_dir_latch
	cd obj_dir_latch && make -f VND120_TOP.mk VND120_TOP
	./obj_dir_latch/VND120_TOP > trace_latch.csv
	@echo "=== Latch trace written to trace_latch.csv ==="

compare_ff: latch_ff_compare.cpp
	$(VERILATOR) $(COMPARE_VFLAGS) -DVERILATOR_SIM -DFPGA_FF_MODE $(VERILATOR_DIRS) --exe $(COMPARE_SOURCES) -CFLAGS "$(VERILATOR_DIRS) -I../../simDevices" --Mdir obj_dir_ff
	cd obj_dir_ff && make -f VND120_TOP.mk VND120_TOP
	./obj_dir_ff/VND120_TOP > trace_ff.csv
	@echo "=== FF trace written to trace_ff.csv ==="

compare: compare_latch compare_ff
	@echo "=== Comparing latch vs FF traces ==="
	@diff trace_latch.csv trace_ff.csv > trace_diff.txt 2>&1 && echo "IDENTICAL - no divergence!" || (echo "DIVERGENCE FOUND - see trace_diff.txt" && head -20 trace_diff.txt)

# --- Generic scriptable PROBE (nd120_probe.cpp + nd120_probe.py) ---
# ADDITIVE target: a NEW reusable harness with runtime signal access, a rule
# engine, a PRE/POST CSV ring and a trigger-windowed FST. Built with
# --public-flat-rw (expose internal wires) and --vpi (resolve arbitrary signals
# by name at runtime). Both flags are NON-INVASIVE - no RTL is edited.
#   make probe                 # FF mode default (USE_LATCHES=0) for investigations
# NOTE: default USE_LATCHES for the probe is 0 (FF mode = shipped path).
PROBE_SOURCES = nd120_probe.cpp ../simDevices/NDDevices.cpp ../simDevices/NDBus.cpp
PROBE_DEFINES = -DVERILATOR_SIM
ifneq ($(USE_LATCHES),1)
  # Probe defaults to FF mode unless the caller explicitly sets USE_LATCHES=1.
  PROBE_DEFINES += -DFPGA_FF_MODE
endif
ifeq ($(PANEL_CLOCK),1)
  PROBE_DEFINES += -DND120_PANEL_CLOCK
endif

probe: nd120_probe.cpp
	$(VERILATOR) --trace-fst --vpi -Wall --cc ../ND120_TOP.v $(SUPPRESS_FLAGS) $(PROBE_DEFINES) --public-flat-rw $(VERILATOR_DIRS) --exe $(PROBE_SOURCES) -CFLAGS "$(VERILATOR_DIRS) -I../../simDevices" --Mdir obj_dir_probe
	cd obj_dir_probe && make -f VND120_TOP.mk VND120_TOP
	@echo "=== probe engine built: obj_dir_probe/VND120_TOP ==="

# --- PROBE variant WITH the Verilog ND bus devices + floppy (TPE boot) -------
# ADDITIVE target: same generic scriptable probe engine, but built so the
# `1560&` MOPC autoload boots TPE from a mounted floppy image - mirroring the
# proven runSim `test-floppy-stdin` recipe (VERILOG_TAPE=1 SD_STORAGE=0):
#   * -DND120_VERILOG_DEVICES to VERILATOR  -> instantiates the Verilog floppy
#     core inside ND120_TOP so IOX 1560-1567 is answered in-RTL (enables 1560&).
#   * -DND120_VERILOG_DEVICES to the C++    -> NDBus.cpp's process_verilog_floppy()
#     path compiles and serves the image named by env ND120_FLOPPY_IMG.
#   * NOT defining ND120_SD_STORAGE (SD_STORAGE=0) -> the floppy bytes come from
#     the host file (ND120_FLOPPY_IMG), not the in-RTL SD-FAT stack.
# Built into its OWN Mdir (obj_dir_probe_floppy) so it never clobbers `probe`.
# Run the engine (from Verilog/sim) with:  ND120_FLOPPY_IMG=../runSim/FLOPPY1.IMG ./obj_dir_probe_floppy/VND120_TOP
#   make probe-floppy            # FF mode default (USE_LATCHES=0), Verilog floppy on
PROBE_FLOPPY_DEFINES = $(PROBE_DEFINES) -DND120_VERILOG_DEVICES
# The Verilog ND bus device modules (ND_TAPE_400/ND_FLOPPY_DMA/ND_DMA_MASTER/
# ND_SMD) and their SD-FAT helpers live outside the CPU tree - add their include
# dirs so Verilator can find the modules that ND120_VERILOG_DEVICES instantiates.
# Mirrors runSim/Makefile's BUSDEV_COMPONENTS + SDFAT_COMPONENTS. SD_STORAGE=0
# here, so the -v SD-FAT files are NOT needed (the floppy is served from the host
# file via NDBus.cpp), only the -I search paths.
BUSDEV_COMPONENTS = -I../ND-BUS-DEVICES/BUS-IF/circuit -I../ND-BUS-DEVICES/TAPE-400/circuit -I../ND-BUS-DEVICES/DMA/circuit -I../ND-BUS-DEVICES/FLOPPY/circuit -I../ND-BUS-DEVICES/FLOPPY-DMA/circuit -I../ND-BUS-DEVICES/SMD/circuit
SDFAT_COMPONENTS  = -I../SD-FAT/circuit -I../SD-FAT/sim
PROBE_FLOPPY_DIRS = $(VERILATOR_DIRS) $(BUSDEV_COMPONENTS) $(SDFAT_COMPONENTS)

probe-floppy: nd120_probe.cpp
	$(VERILATOR) --trace-fst --vpi -Wall --cc ../ND120_TOP.v $(SUPPRESS_FLAGS) $(PROBE_FLOPPY_DEFINES) --public-flat-rw $(PROBE_FLOPPY_DIRS) --exe $(PROBE_SOURCES) -CFLAGS "$(VERILATOR_DIRS) -I../../simDevices -DND120_VERILOG_DEVICES" --Mdir obj_dir_probe_floppy
	cd obj_dir_probe_floppy && make -f VND120_TOP.mk VND120_TOP
	@echo "=== probe-floppy engine built: obj_dir_probe_floppy/VND120_TOP (mount ND120_FLOPPY_IMG) ==="

# --- PROBE variant WITH the WINCHESTER disc (ST506/8 inch card at IOX 500) ----
# ADDITIVE target, own Mdir - never clobbers probe / probe-floppy.
#
# WHY: the Winchester seam (WDISK_*/WDBUF_*) has been a port on ND120_TOP since
# the card was written, but the card was never once built into a Verilator run
# with the real CPU - WINCHESTER was missing from BUSDEV_COMPONENTS in BOTH
# harnesses, and simDevices/NDBus.cpp had a server for the SMD seam and none for
# this one, so WDISK_DONE sat tied low and no transfer could ever complete. The
# card therefore went from iverilog unit benches straight to the Tang, where the
# only instrument is a 128-entry IOX ring dumped over a UART.
#
#   * -DND120_VERILOG_DEVICES  -> the Verilog bus device chain (as probe-floppy)
#   * -DND120_INCLUDE_WD       -> opts IOX 500-507 in. NOT default: 500 is the
#                                 CDC cartridge disc's block, so the Winchester
#                                 must only appear when asked for.
#   * WINCHESTER/circuit on the include path so Verilator can find ND_WINCHESTER
#
# The disc image is chosen at RUN time by env ND120_WD_IMG (no default - without
# it every operation reports an error, like a drive with no pack). Set
# ND120_WD_TRACE=1 for a per-operation START/REQ log.
#   make probe-wd            # FF mode default (USE_LATCHES=0)
# EXTRA_WD_DEFINES: pass-through for one-off diagnostic defines, e.g.
#   make probe-wd USE_LATCHES=0 EXTRA_WD_DEFINES=-DND120_DEV_DELAY_TICKS=216000
# to make the disc completion delay cycle-identical to the Tang (27 MHz)
# instead of the sim's 100 MHz fallback.
EXTRA_WD_DEFINES ?=
PROBE_WD_DEFINES = $(PROBE_FLOPPY_DEFINES) -DND120_INCLUDE_WD $(EXTRA_WD_DEFINES)
PROBE_WD_DIRS    = $(PROBE_FLOPPY_DIRS) -I../ND-BUS-DEVICES/WINCHESTER/circuit

probe-wd: nd120_probe.cpp
	$(VERILATOR) --trace-fst --vpi -Wall --cc ../ND120_TOP.v $(SUPPRESS_FLAGS) $(PROBE_WD_DEFINES) --public-flat-rw $(PROBE_WD_DIRS) --exe $(PROBE_SOURCES) -CFLAGS "$(VERILATOR_DIRS) -I../../simDevices -DND120_VERILOG_DEVICES -DND120_RTC_RUNTIME" --Mdir obj_dir_probe_wd
	cd obj_dir_probe_wd && make -f VND120_TOP.mk VND120_TOP
	@echo "=== probe-wd engine built: obj_dir_probe_wd/VND120_TOP (set ND120_WD_IMG) ==="

# --- PROBE variant: WINCHESTER SERVED THROUGH THE REAL SD-FAT STACK ----------
# ADDITIVE target, own Mdir - never clobbers probe / probe-floppy / probe-wd.
#
# WHY: `probe-wd` above boots SINTRAN with the disc image handed to the C file
# server in simDevices/NDBus.cpp - one fread per block. That means the storage
# RTL the Tang actually runs is NOT in the path at all:
#
#     sd_card_ctrl -> sd_file_reader (FAT mount + root scan)
#       -> nd_storage_engine -> nd_storage_cache (Phase-4 block cache)
#         -> nd_storage_disc_adapter -> ND_WINCHESTER
#
# None of it executes, so no defect in it can show up in simulation - it can
# only show up on silicon, where the instrument is a 128-entry IOX ring over a
# UART. The storage testbenches do drive that chain, but against a 16384-byte
# stand-in WD0.IMG (SD-FAT/sim/make_storage_image.sh, WD_BYTES=16384) with a
# hand-written access pattern. A real image is ~75 MB and SINTRAN's pattern is
# nothing like a testbench's. This target closes that gap: same CPU, same
# boot, but every disc block travels the full SD/FAT/cache path off a
# simulated FAT card.
#
#   * everything probe-wd sets, plus
#   * -DND120_SD_STORAGE   -> the sim-only sd_card_model + nds_mem_model
#   * -DND120_SD_WD        -> nd_storage client 6 = WD0.IMG (CACHED, CACHE_MASK
#                             bit 6) answers WDISK_*; NDBus.cpp's C file server
#                             stands down (same guard style as the tape)
#   * -DND120_SD_CARD_IMG  -> the card image (SD_CARD_IMG below)
#   * -DND120_SD_CARD_BYTES-> sd_card_model slurps the card into a byte array at
#                             time 0; sectors past MAX_BYTES read back 0xFF, so
#                             this MUST be >= the card file. make_wd_card.sh
#                             prints the right value as CARD_BYTES=<n>.
#   * --timing             -> sd_card_model drives the SD bus from tasks with
#                             @(negedge sd_clk) (as runSim's SD_STORAGE=1 does)
#   * -v nds_sync.v / sd_file_reader.v -> both hold modules whose names differ
#                             from the filename, so -I alone cannot find them
#
# BUILD THE CARD FIRST - the Winchester image lives outside the repo, so its
# path must be given explicitly (no default; the script refuses to guess):
#
#   ../SD-FAT/sim/make_wd_card.sh /path/to/WD0.IMG
#   make probe-wd-sd SD_CARD_BYTES=<the CARD_BYTES it printed>
#   ./obj_dir_probe_wd_sd/VND120_TOP
#
# Note there is NO ND120_WD_IMG here: the image is a file ON the card now, and
# the FAT reader finds it by name. To compare the two backends on one boot,
# run probe-wd and probe-wd-sd with the same image and diff the traces - any
# difference is the storage stack, since the CPU build is otherwise identical.
SD_CARD_IMG   ?= ../SD-FAT/sim/nd_wd_card.img
SD_CARD_BYTES ?= 100663296
# Scoped to this build only, so the CPU sources keep their full -Wall. All four
# are pre-existing and benign in the SD-FAT stack; runSim/Makefile and
# SD-FAT/sim/Makefile suppress exactly the same set:
#   PINMISSING    BY DESIGN - nd_storage instantiates sd_writer without the
#                 4-bit ports; unconnected use_4bit = the proven 1-bit engine
#   DECLFILENAME  nds_sync.v / sd_file_reader.v hold >1 module (see -v above)
#   BLKSEQ        blocking assigns in the card MODEL's sequential tasks
#   TIMESCALEMOD  the SD-FAT sources carry a timescale, the CPU ones do not
SDFAT_SUPPRESS = -Wno-PINMISSING -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-TIMESCALEMOD
SDFAT_VFILES   = -v ../SD-FAT/circuit/nds_sync.v -v ../SD-FAT/circuit/sd_file_reader.v
PROBE_WD_SD_DEFINES = $(PROBE_WD_DEFINES) -DND120_SD_STORAGE -DND120_SD_WD \
                      -DND120_SD_CARD_IMG='"$(SD_CARD_IMG)"' \
                      -DND120_SD_CARD_BYTES=$(SD_CARD_BYTES)

probe-wd-sd: nd120_probe.cpp
	@if [ ! -f "$(SD_CARD_IMG)" ]; then \
	  echo "probe-wd-sd: card image $(SD_CARD_IMG) does not exist." >&2; \
	  echo "probe-wd-sd: build it first, e.g." >&2; \
	  echo "    ../SD-FAT/sim/make_wd_card.sh /path/to/WD0.IMG" >&2; \
	  echo "probe-wd-sd: it is NOT auto-built - only you know which Winchester image to use." >&2; \
	  exit 1; \
	fi
	@sz=$$(stat -c%s "$(SD_CARD_IMG)"); \
	if [ "$$sz" -gt "$(SD_CARD_BYTES)" ]; then \
	  echo "probe-wd-sd: $(SD_CARD_IMG) is $$sz bytes but SD_CARD_BYTES=$(SD_CARD_BYTES)." >&2; \
	  echo "probe-wd-sd: sd_card_model would read every sector past that back as 0xFF." >&2; \
	  echo "probe-wd-sd: rebuild with SD_CARD_BYTES=$$sz (make_wd_card.sh prints it as CARD_BYTES=)." >&2; \
	  exit 1; \
	fi
	$(VERILATOR) --trace-fst --vpi -Wall --cc ../ND120_TOP.v $(SUPPRESS_FLAGS) $(SDFAT_SUPPRESS) --timing $(PROBE_WD_SD_DEFINES) --public-flat-rw $(PROBE_WD_DIRS) $(SDFAT_VFILES) --exe $(PROBE_SOURCES) -CFLAGS "$(VERILATOR_DIRS) -I../../simDevices -DND120_VERILOG_DEVICES -DND120_RTC_RUNTIME -DND120_SD_STORAGE -DND120_SD_WD -std=gnu++20 -fcoroutines" --Mdir obj_dir_probe_wd_sd
	cd obj_dir_probe_wd_sd && make -f VND120_TOP.mk VND120_TOP
	@echo "=== probe-wd-sd engine built: obj_dir_probe_wd_sd/VND120_TOP ==="
	@echo "=== disc served by the SD-FAT stack off $(SD_CARD_IMG) (no ND120_WD_IMG) ==="

# --- PROBE variant with the PORTABLE C FLOPPY CORE (real TPE-MON boot) --------
# ADDITIVE target: mirrors runSim's `run-tpe` device config
#   make compile VERILOG_TAPE=0 SD_STORAGE=0 DEVICECORE=1 DEVICECORE_FLOPPY=1
# i.e. the RTL has NO Verilog bus devices (VERILOG_TAPE=0 -> plain ND120_TOP),
# and the floppy at IOX 1560-1567 is served by the PORTABLE C99 core
# (NDDeviceCore nd_floppy_dma) via the C bus master (NDCoreShim). The Verilog
# floppy is documented to mis-serve real diskettes; the C core is the backend
# that boots the real ND-120/CX "TPE Monitor B01" from runSim/FLOPPY1.IMG.
# The probe engine's reused addDevices() calls addDevicesCore() under
# -DND120_DEVICECORE, and proccess_bif_signal() ticks the C bus master under
# -DND120_DEVICECORE_BUSMASTER, so no engine change is needed.
# Image is chosen at RUN time by env ND120_FLOPPYCORE_IMG (NOT ND120_FLOPPY_IMG).
# Built into its OWN Mdir so it never clobbers probe / probe-floppy.
#   make probe-floppycore        # FF mode default (USE_LATCHES=0)
NDDEVICECORE_DIR ?= $(abspath ../ND-BUS-DEVICES/portable)
# DEVICECORE source set for DEVICECORE=1 DEVICECORE_FLOPPY=1 (=> BUSMASTER=1),
# transcribed from runSim/Makefile so the two builds stay in lock-step.
DEVICECORE_SOURCES = \
  $(NDDEVICECORE_DIR)/src/nd_device.c \
  $(NDDEVICECORE_DIR)/src/nd_char.c \
  $(NDDEVICECORE_DIR)/src/nd_lineprinter.c \
  ../simDevices/NDDeviceCoreAdapter.cpp \
  ../simDevices/NDCoreCharBackend.cpp \
  ../simDevices/NDCoreTrace.cpp \
  $(NDDEVICECORE_DIR)/src/nd_trace.c \
  $(NDDEVICECORE_DIR)/src/nd_dma.c \
  $(NDDEVICECORE_DIR)/src/nd_storage.c \
  $(NDDEVICECORE_DIR)/src/nd_floppy_dma.c \
  ../simDevices/NDCoreBlockBackend.cpp \
  ../simDevices/NDCoreShim.cpp
DEVICECORE_CDEFS = -DND120_DEVICECORE -DND120_DEVICECORE_FLOPPY -DND120_DEVICECORE_BUSMASTER -I$(NDDEVICECORE_DIR)/include
PROBE_FC_SOURCES = $(PROBE_SOURCES) $(DEVICECORE_SOURCES)

probe-floppycore: nd120_probe.cpp
	$(VERILATOR) --trace-fst --vpi -Wall --cc ../ND120_TOP.v $(SUPPRESS_FLAGS) $(PROBE_DEFINES) --public-flat-rw $(VERILATOR_DIRS) --exe $(PROBE_FC_SOURCES) -CFLAGS "$(VERILATOR_DIRS) -I../../simDevices $(DEVICECORE_CDEFS)" --Mdir obj_dir_probe_floppycore
	cd obj_dir_probe_floppycore && make -f VND120_TOP.mk VND120_TOP
	@echo "=== probe-floppycore engine built: obj_dir_probe_floppycore/VND120_TOP (set ND120_FLOPPYCORE_IMG) ==="

.PHONY: all clean probe probe-floppy probe-wd probe-floppycore compare compare_latch compare_ff
