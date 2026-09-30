VERILATOR = verilator

SUPPRESS_FLAGS = -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-UNUSED -Wno-UNDRIVEN -Wno-WIDTH -Wno-EOFNEWLINE -Wno-LATCH -Wno-SYNCASYNCNET

# USE_LATCHES: 0 (edge-triggered flip-flop behavior) is the default and is what
#              every build here uses. We do not use latches any more - the
#              transparent-latch path is legacy. USE_LATCHES=1 stays reachable
#              from the command line ONLY as a one-off debug escape hatch; no
#              target in this file may pass it to a sub-make.
USE_LATCHES ?= 0

# Enable larger RAM (1MB) for Verilator simulation instead of FPGA's 4KB
# EXTRA_VDEFINES: extra Verilog-side defines, e.g.
#   EXTRA_VDEFINES="-DRTC_REAL_PERIOD -DBOARD_CLK_FREQ=16666667"
# to run the DGA real-time clock at the true FPGA period (OPCOM pacing repro).
SIM_DEFINES = -DVERILATOR_SIM $(EXTRA_VDEFINES)
ifeq ($(USE_LATCHES),0)
  SIM_DEFINES += -DFPGA_FF_MODE
endif

# CACHE: Set to 1 (default) to build the CPU cache (today's behavior).
#        Set to 0 to compile it out (-DND120_NO_CACHE, CPU_MMU_CACHE_25.v):
#        omits the five cache memories + used-bit PAL, forces hit=0, and the
#        machine reports the cache as disabled - matches the Tang FPGA build.
#        The define is ALSO forwarded to the C++ harness: Run120.cpp's cache
#        probes ([inh], ND120_CACHE_TRACE/WIN/PPN) dereference cache-internal
#        Verilator signals that a no-cache build compiles out, so those probe
#        blocks are #ifndef ND120_NO_CACHE in Run120.cpp.
#        'override' for the same reason VERILOG_TAPE uses it: EXTRA_CFLAGS is
#        usually given on the make command line, which beats plain +=.
CACHE ?= 1
ifeq ($(CACHE),0)
  SIM_DEFINES += -DND120_NO_CACHE
  override EXTRA_CFLAGS += -DND120_NO_CACHE
endif

# PANEL_CLOCK=1: emulate the MC68705/MM58274 clock path (IO_PANCAL_40.v ->
# PANCAL_68705_CLOCK.v) so TRR PANC / TRA PANS can set and read the hardware
# clock. Off by default so the golden traces/console are unchanged.
PANEL_CLOCK ?= 0
ifeq ($(PANEL_CLOCK),1)
  SIM_DEFINES += -DND120_PANEL_CLOCK
endif


# Packed-memory contract (default ON, matching the Tang build): parity is
# never read from storage, MEM_RAM_49_SIM recomputes it from the data on
# every read. Set PACK16=0 to model classic stored-parity DRAM.
# See docs/nd120-parity-analysis.md.
PACK16 ?= 1
ifeq ($(PACK16),1)
  SIM_DEFINES += -DND_SDRAM_PACK16
endif

# SKIP_WCS: Set to 1 to pre-load the WCS and skip the microcode load phase.
#           Requires the 32 wcs_*.hex files in this dir - the SIM variant
#           (gen_wcs_image.py --sim -> Code/Microcode/wcs-sim/, copy here).
#           See docs/skip-wcs-load.md.
ifeq ($(SKIP_WCS),1)
  SIM_DEFINES += -DSKIP_WCS_LOAD
endif

# VERILOG_TAPE: THE DEFAULT (1). Every build - `make compile`, `make run`,
#               everything - uses the real Verilog device stack: ND_BUS_SLAVE +
#               ND_TAPE_400 inside ND120_TOP, fed by the SD-FAT RTL reading a
#               simulated SD card (the SAME RTL that runs on Tang).
#               VERILOG_TAPE=0 is the ONLY way to pull in the legacy C papertape
#               model (../simDevices), the ONE target that does so is `make
#               run-c`, and a C build SCREAMS a banner so it is never silent.
VERILOG_TAPE ?= 1
ifeq ($(VERILOG_TAPE),1)
  SIM_DEFINES += -DND120_VERILOG_DEVICES
  # 'override' is required: EXTRA_CFLAGS is usually given on the make
  # command line, and a plain += on a command-line variable is silently
  # ignored - which would compile the C harness WITHOUT the define
  # (leaving the C papertape registered and the Verilog device starved).
  override EXTRA_CFLAGS += -DND120_VERILOG_DEVICES

# SD_STORAGE=1 (DEFAULT, Ronny 14-JUL-2026): the Verilog tape device is fed by
#            the REAL SD-FAT stack reading a simulated SD card - the same RTL
#            that runs on Tang - instead of the C file server in NDBus.cpp.
#            The card must carry BOOT.BPUN; build it with
#            ../SD-FAT/sim/make_boot_card.sh (SD_CARD_IMG points at it).
#            Implies TIMING=1: sd_card_model.v drives the SD bus from tasks.
# SD_STORAGE=0 falls back to the C tape file server (process_verilog_tape).
#            Both paths must build and pass - the C models also back the
#            sim/ latch-vs-FF trace goldens.
  SD_STORAGE  ?= 1
  # The default card is a build artefact: .gitignore excludes SD-FAT/sim/*.img,
  # so a fresh clone has no card and the 'card' target below builds it.
  SD_CARD_IMG_DEFAULT := ../SD-FAT/sim/nd_boot_card.img
  SD_CARD_IMG ?= $(SD_CARD_IMG_DEFAULT)
  ifeq ($(SD_STORAGE),1)
    SD_CARD_NEEDED := 1
    SIM_DEFINES += -DND120_SD_STORAGE -DND120_SD_CARD_IMG='"$(SD_CARD_IMG)"'
    override EXTRA_CFLAGS += -DND120_SD_STORAGE
    TIMING := 1
    # Suppressions scoped to the SD_STORAGE build ONLY, so the CPU sources keep
    # their full -Wall. All four are pre-existing and benign in the SD-FAT
    # stack, and SD-FAT/sim/Makefile already suppresses them there:
    #   PINMISSING    BY DESIGN - nd_storage instantiates sd_writer without the
    #                 4-bit ports; unconnected use_4bit = the proven 1-bit engine
    #   DECLFILENAME  nds_sync.v / sd_file_reader.v hold >1 module (see -v above)
    #   BLKSEQ        blocking assigns in the card MODEL's sequential tasks
    #   TIMESCALEMOD  the SD-FAT sources carry a timescale, the CPU ones do not
    SDFAT_SUPPRESS = -Wno-PINMISSING -Wno-DECLFILENAME -Wno-BLKSEQ -Wno-TIMESCALEMOD
  endif
else
  # VERILOG_TAPE=0: the legacy C papertape model (../simDevices). This is the
  # ONLY non-default path; `compile` screams a banner so a C build is never
  # mistaken for the real Verilog ND_TAPE_400 / SD path.
  CMODEL := 1
endif

# TIMING=1  compile with Verilator --timing (event controls / delays).
#           Needed by the Verilog SD card model (sd_card_model.v drives the
#           SD bus from tasks with @(negedge sd_clk)), i.e. by SD_STORAGE.
#           It changes Verilator's scheduler for the WHOLE build, so it is a
#           variable and the golden gates must be re-proven under it.
TIMING ?= 0
ifeq ($(TIMING),1)
  TIMING_FLAGS = --timing
  override EXTRA_CFLAGS += -std=gnu++20 -fcoroutines
else
  TIMING_FLAGS =
endif

VERILATOR_FLAGS = --trace -Wall --cc ../ND120_TOP.v $(SUPPRESS_FLAGS) $(SDFAT_SUPPRESS) $(TIMING_FLAGS) $(SIM_DEFINES)

#TOP_3202D_COMPONENTS = -I../circuit -I../../Shared/logisim   -I../../Shared/ndlib  -I../../Shared/support
TOP_3202D_COMPONENTS =  -I../Shared/logisim   -I../Shared/ndlib  -I../Shared/support -I../CPU-BOARD-3202/circuit

CGA_COMPONENTS = -I../DELILAH-CPU/CGA_ALU/circuit -I../DELILAH-CPU/CGA_DCD/circuit -I../DELILAH-CPU/CGA_IDBCTL/circuit -I../DELILAH-CPU/CGA_INTR/circuit -I../DELILAH-CPU/CGA_MAC/circuit -I../DELILAH-CPU/CGA_MIC/circuit -I../DELILAH-CPU/CGA_TESTMUX/circuit -I../DELILAH-CPU/CGA_TRAP/circuit -I../DELILAH-CPU/CGA_WRF/circuit -I../DELILAH-CPU/CGA/circuit
DGA_COMPONENTS = -I../DECODE-GateArray/DGA/circuit

#SHARED_COMPONENTS =  -I../circuit -y ../../Shared/ndlib -y ../../Shared/logisim -I../../Shared/gates-tmp # (was shared/gates - dir never existed)   -I../../PAL

BUSDEV_COMPONENTS = -I../ND-BUS-DEVICES/BUS-IF/circuit -I../ND-BUS-DEVICES/TAPE-400/circuit -I../ND-BUS-DEVICES/DMA/circuit -I../ND-BUS-DEVICES/FLOPPY/circuit -I../ND-BUS-DEVICES/FLOPPY-DMA/circuit -I../ND-BUS-DEVICES/SMD/circuit
# SD-FAT stack (SD_STORAGE): circuit/ = the real RTL, sim/ = sd_card_model +
# nds_mem_model, the two SIM-ONLY models ND120_TOP instantiates under
# ND120_SD_STORAGE. Without these -I dirs Verilator cannot find nd_storage.
SDFAT_COMPONENTS = -I../SD-FAT/circuit -I../SD-FAT/sim
# LIBRARY files: -I resolves a module by FILENAME, and these two hold modules
# whose names differ from their file, so -I alone cannot find them:
#   nds_sync.v       -> nds_sync_pulse, nds_sync_level
#   sd_file_reader.v -> sd_card_ctrl (alongside sd_file_reader)
# Kept OUT of VERILATOR_DIRS on purpose: that variable is also handed to g++
# via -CFLAGS, which would try to LINK these .v files.
# Only fed to Verilator when SD_STORAGE=1: parsing them otherwise would drag
# their (suppressed-only-there) DECLFILENAME warnings into the C-path build.
ifeq ($(SD_STORAGE),1)
  SDFAT_VFILES = -v ../SD-FAT/circuit/nds_sync.v -v ../SD-FAT/circuit/sd_file_reader.v
endif

# -I.. = the Verilog root, where ND120_CORE.v (instantiated by ND120_TOP.v) lives
VERILATOR_DIRS = -I.. $(TOP_3202D_COMPONENTS) $(CGA_COMPONENTS) $(DGA_COMPONENTS) $(BUSDEV_COMPONENTS) $(SDFAT_COMPONENTS) -I../PAL
# Specify C++ source files here
CPP_SOURCES = Run120.cpp ../simDevices/NDDevices.cpp ../simDevices/NDBus.cpp ../simDevices/NDConsoleScript.cpp

# DEVICECORE=1 - the NDDeviceCore RTL EQUIVALENCE GATE (default 0 = OFF, the
#            default build is byte-for-byte unaffected). Compiles the PORTABLE
#            C99 device cores from ../../../NDDeviceCore - the SAME .c files
#            that run in the RP2350 NDModulE firmware - into this harness and
#            registers them with the DeviceManager through
#            ../simDevices/NDDeviceCoreAdapter.cpp, so the REAL ND-120 CPU +
#            bus RTL drives them. See docs/rtl-gate-plan.md and the
#            `test-democore` target in the top-level Verilog/Makefile.
#            NDDEVICECORE_DIR overrides the library location.
DEVICECORE ?= 0
# The portable C cores live in the git SUBMODULE at
# Verilog/ND-BUS-DEVICES/portable (github.com/HackerCorpLabs/NDDeviceCore).
# This Makefile runs from Verilog/runSim, so the submodule is two dirs up +
# over. Still `?=`-overridable: point it at a working copy for iterating on
# NDDeviceCore itself, e.g. NDDEVICECORE_DIR=$ND_REPOS/NDDeviceCore.
NDDEVICECORE_DIR ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../ND-BUS-DEVICES/portable)
ifeq ($(DEVICECORE),1)
  # Character-device axis only (no DMA / no memory backdoor): the device
  # contract, the char seam and the line printer core.
  DEVICECORE_SOURCES = $(NDDEVICECORE_DIR)/src/nd_device.c \
                       $(NDDEVICECORE_DIR)/src/nd_char.c \
                       $(NDDEVICECORE_DIR)/src/nd_lineprinter.c \
                       ../simDevices/NDDeviceCoreAdapter.cpp \
                       ../simDevices/NDCoreCharBackend.cpp
  DEVICECORE_INC = -I$(NDDEVICECORE_DIR)/include
  # 'override' for the same reason VERILOG_TAPE uses it: EXTRA_CFLAGS usually
  # arrives on the command line, where a plain += is silently ignored.
  # The structured trace seam (nd_trace) + this harness's printf sink for it.
  DEVICECORE_SOURCES += ../simDevices/NDCoreTrace.cpp \
                        $(NDDEVICECORE_DIR)/src/nd_trace.c

  # The DMA + block-storage engines belong to the BASE core library, not to the
  # floppy option: NDDeviceCoreAdapter::Tick() pumps them unconditionally, so a
  # tape-only build fails to LINK without them. They are inert when no block
  # device is registered (the adapter is passed null and never ticks them).
  DEVICECORE_SOURCES += $(NDDEVICECORE_DIR)/src/nd_dma.c \
                        $(NDDEVICECORE_DIR)/src/nd_storage.c

  override EXTRA_CFLAGS += -DND120_DEVICECORE $(DEVICECORE_INC)

  # DEVICECORE_FLOPPY=1 additionally registers the portable nd_floppy_dma at
  # IOX 1560-1567 (ident 021, level 11) so the CPU's `1560&` autoload - and a
  # plain OPCOM `IO/` poke - land on OUR C core. Build it with VERILOG_TAPE=0
  # so no Verilog floppy shares the window. See the `test-floppy-core*`
  # targets in the top-level Verilog/Makefile.
  ifeq ($(DEVICECORE_FLOPPY),1)
    # HARD STOP, not a comment: with VERILOG_TAPE=1 the Verilog floppy core is
    # instantiated inside ND120_TOP and ALSO answers 1560-1567. Two devices on
    # one window race on every IOX cycle, and the C++-side Claims() guard
    # cannot help - the Verilog device is not registered with DeviceManager at
    # all. The failure would look like intermittent wrong data, not an error.
    ifneq ($(VERILOG_TAPE),0)
      $(error DEVICECORE_FLOPPY=1 requires VERILOG_TAPE=0 - otherwise the Verilog \
floppy also drives IOX 1560-1567 and the two cores race. Rebuild with VERILOG_TAPE=0.)
    endif
    DEVICECORE_SOURCES += $(NDDEVICECORE_DIR)/src/nd_floppy_dma.c \
                          ../simDevices/NDCoreBlockBackend.cpp
    override EXTRA_CFLAGS += -DND120_DEVICECORE_FLOPPY
    # The floppy is a DMA device, so it needs the C bus master.
    DEVICECORE_BUSMASTER := 1
  endif

  # DEVICECORE_DEMODMA=1 registers the portable nd_demo_dma at IOX 0500-0503
  # (ident 077, level 11). This is the DMA PIPE-CLEANER: it exists precisely so
  # the bus master can be debugged with no disk geometry, no BPUN and no boot
  # path in the way. Prove DMA here FIRST, then point it at the floppy.
  ifeq ($(DEVICECORE_DEMODMA),1)
    ifneq ($(VERILOG_TAPE),0)
      $(error DEVICECORE_DEMODMA=1 requires VERILOG_TAPE=0 - a Verilog DMA master \
would also arbitrate for the bus. Rebuild with VERILOG_TAPE=0.)
    endif
    DEVICECORE_SOURCES += $(NDDEVICECORE_DIR)/src/nd_demo_dma.c
    override EXTRA_CFLAGS += -DND120_DEVICECORE_DEMODMA
    DEVICECORE_BUSMASTER := 1
  endif

  # The C bus master itself - pulled in by any DMA-capable core above. It
  # drives the RAW ND120_TOP bus ports (BREQ/BAPR/BDAP/BINPUT/BD) against the
  # real arbiter and real RAM, because ND_DMA_MASTER.v is NOT elaborated in a
  # DEVICECORE build and its client ports do not exist on ND120_TOP.
  ifeq ($(DEVICECORE_BUSMASTER),1)
    DEVICECORE_SOURCES += ../simDevices/NDCoreShim.cpp
    override EXTRA_CFLAGS += -DND120_DEVICECORE_BUSMASTER
  endif

  # DEVICECORE_TAPE=1 registers the portable nd_tape400 at IOX 0400-0403
  # (ident 02, level 12) so the CPU's `400$` BPUN loader reads OUR C core.
  # Image from ND120_TAPECORE_IMG, default BOOT.BPUN.
  ifeq ($(DEVICECORE_TAPE),1)
    ifneq ($(VERILOG_TAPE),0)
      $(error DEVICECORE_TAPE=1 requires VERILOG_TAPE=0 - otherwise the Verilog \
ND_TAPE_400 also drives IOX 0400-0403 and the two cores race. Rebuild with VERILOG_TAPE=0.)
    endif
    DEVICECORE_SOURCES += $(NDDEVICECORE_DIR)/src/nd_tape400.c \
                          ../simDevices/NDCoreTapeBackend.cpp
    override EXTRA_CFLAGS += -DND120_DEVICECORE_TAPE
  endif

  # Appended LAST so every conditional addition above is included.
  CPP_SOURCES += $(DEVICECORE_SOURCES)
endif

# Default target
all: compile run gtk

help:
	@echo "runSim - full CPU simulation (microcode load + self-test + OPCOM console)"
	@echo ""
	@echo "Targets:"
	@echo "  make compile      build the simulator - DEFAULT = the real Verilog"
	@echo "                    device stack (ND_TAPE_400) fed by the SD-FAT RTL"
	@echo "                    over a simulated SD card. NO C code. (Tang's path.)"
	@echo "  make run          compile + run interactively (OPCOM on stdin/stdout)"
	@echo "                    with the Verilog device stack fed by the real"
	@echo "                    SD-FAT RTL reading a simulated SD card"
	@echo "                    (= VERILOG_TAPE=1 SD_STORAGE=1)"
	@echo "  make run-config   boot CONFIGURATIO-C08.BPUN off the card (device"
	@echo "                    configuration; type RUN at its prompt to probe the"
	@echo "                    machine - says if floppy/SMD/tape are detected)"
	@echo "  make run-fs       boot FILSYS-INV-Q04.BPUN off the card (file-system"
	@echo "                    investigator; looks INTO a floppy or SMD image)"
	@echo "  make run-c        THE ONE C-MODEL TARGET. Legacy C papertape/device"
	@echo "                    models in ../simDevices (= VERILOG_TAPE=0). Prints a"
	@echo "                    loud banner so a C build is never silent. Only for"
	@echo "                    legacy comparison - normal work uses 'make run'."
	@echo "  make run-floppy   Verilog-device build (DMA floppy at 1560) + run with"
	@echo "                    a bootable diskette image; type 1560& at the '#'"
	@echo "                    prompt to boot it - the loaded program then owns the"
	@echo "                    console (type help etc. at ITS prompt)"
	@echo ""
	@echo "  --- NDDeviceCore C-core interactive runs (the code the Pico runs) ---"
	@echo "  make run-tpe      Boot the TPE Monitor diskette (TPE_IMG=FLOPPY1.IMG)"
	@echo "                    through the PORTABLE C floppy core. PURE MANUAL - no"
	@echo "                    scripted keys; YOU type 1560& to boot and drive it."
	@echo "                    SLOW: wait a few minutes for '==TPE42=>'. The 'clock"
	@echo "                    is not updated' msg is EXPECTED (no 6805 panel)."
	@echo "                    REUSES an up-to-date binary; after editing source use:"
	@echo "  make run-tpe-rebuild  force a clean floppy-core recompile, then run."
	@echo "  make run-tpe-auto Same boot, UNATTENDED/scripted (auto-types 1560&"
	@echo "                    config<CR>run<CR>) - the only target that injects keys."
	@echo "  make run-rtc      Pre-deposit RTC.BPUN (RTC_BPUN=) + start at octal 20 -"
	@echo "                    a standalone 20ms level-13 clock diagnostic."
	@echo "  make run-tpe-trace  Like run-tpe (manual) + ND120_CORE_TRACE=1: prints"
	@echo "                    every floppy IOX / DMA / storage op ([ndcore] lines)"
	@echo "                    so you can see what TPE sends the floppy and gets back."
	@echo "  make clean        remove obj_dir (do this when switching build flags)"
	@echo ""
	@echo "Variables:"
	@echo "  USE_LATCHES=1     legacy transparent-latch mode - debug only, never"
	@echo "                    for normal work. Default 0 = the edge-triggered"
	@echo "                    flip-flop behavior every build here uses."
	@echo "  VERILOG_TAPE=1    replace the C papertape/floppy models with the Verilog"
	@echo "                    device stack inside ND120_TOP (tape-400 + DMA floppy"
	@echo "                    at 1560 + SMD at 1540)"
	@echo "  SD_STORAGE=1      (DEFAULT when VERILOG_TAPE=1) feed the tape from the"
	@echo "                    REAL Verilog SD-FAT stack reading a simulated SD"
	@echo "                    card - the same RTL that runs on Tang. The card"
	@echo "                    carries BOOT.BPUN and is built automatically by"
	@echo "                    'make run' if absent (target: card, script:"
	@echo "                    ../SD-FAT/sim/make_boot_card.sh)."
	@echo "                    Implies TIMING=1 (the card model drives the SD bus"
	@echo "                    from tasks). 400\$$ then boots BOOT.BPUN off the card."
	@echo "  SD_STORAGE=0      fall back to the C tape file server in NDBus.cpp"
	@echo "                    (process_verilog_tape, reads INSTRUCTION-B.BPUN"
	@echo "                    directly). Both paths must build and pass."
	@echo "  SD_CARD_IMG=path  card image for SD_STORAGE"
	@echo "                    (default ../SD-FAT/sim/nd_boot_card.img, auto-built)"
	@echo "                    A card given here is never auto-built - if it is"
	@echo "                    missing, that is an error."
	@echo "  TIMING=1          Verilator --timing (event controls). Forced on by"
	@echo "                    SD_STORAGE=1; measured behaviour-neutral and free"
	@echo "                    (console byte-identical to golden, same runtime)."
	@echo "  FLOPPY_IMG=path   diskette image for run-floppy (default: the 210523I01"
	@echo "                    test-program diskette in ND-BUS-DEVICES/testdata)"
	@echo "  SKIP_WCS=1        preload the WCS, skip the microcode load phase"
	@echo ""
	@echo "  TPE_IMG=path      diskette for run-tpe / run-tpe-auto (default FLOPPY1.IMG)"
	@echo "  RTC_BPUN=path     program for run-rtc (default RTC.BPUN)"
	@echo ""
	@echo "Environment at run time:"
	@echo "  ND120_FLOPPY_IMG  floppy image file (what run-floppy sets for you)"
	@echo "  ND120_FLOPPYCORE_IMG  diskette for the C floppy core (run-tpe sets it)"
	@echo "  ND120_SMD_IMG     SMD disk-0 image file (no default = drive not ready)"
	@echo ""
	@echo "Run limits are OPT-IN, command line ONLY (never a default cap):"
	@echo "  ND120_MAX_CNT=N       stop after N total cycles"
	@echo "  ND120_SCRIPT_BUDGET=N stop N cycles after boot (script/interactive builds)"
	@echo "  unset => run FOREVER until Ctrl-C"
	@echo ""
	@echo "System gates live in the top-level Verilog/Makefile: make test,"
	@echo "test-full, test-tape, test-dma-rtl, test-floppy-boot, test-smd-boot."
	@echo "See runSim/README.md for the full story."

.PHONY: help

# Build-flags stamp: make does not rebuild C++ objects when only -D flags
# change, so switching VERILOG_TAPE / USE_LATCHES / EXTRA_CFLAGS between
# builds would silently link stale harness objects (e.g. NDBus.o still
# registering the C devices next to the Verilog ones). If the flag set
# differs from the last build, wipe obj_dir first.
BUILD_FLAGS = $(SIM_DEFINES) | $(EXTRA_CFLAGS)
FLAGS_STAMP = obj_dir/.buildflags

compile: $(CPP_SOURCES)
ifeq ($(CMODEL),1)
	@printf '\n'
	@printf '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
	@printf '!!!!  BUILDING WITH THE C PAPERTAPE MODEL  (VERILOG_TAPE=0)     !!!!\n'
	@printf '!!!!  THIS IS **NOT** THE REAL VERILOG ND_TAPE_400 / SD PATH.   !!!!\n'
	@printf '!!!!  The Verilog-over-SD device stack is the DEFAULT           !!!!\n'
	@printf '!!!!  (plain `make compile` / `make run`).  This C build comes  !!!!\n'
	@printf '!!!!  ONLY from `make run-c` and exists for legacy comparison.  !!!!\n'
	@printf '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n'
	@printf '\n'
endif
	@if [ -d obj_dir ] && [ "`cat $(FLAGS_STAMP) 2>/dev/null`" != "$(BUILD_FLAGS)" ]; then \
	  echo "Build flags changed (or unknown) since last build - cleaning obj_dir"; \
	  rm -rf obj_dir; \
	fi
	$(VERILATOR) $(VERILATOR_FLAGS) $(VERILATOR_DIRS) $(SDFAT_VFILES) --exe $(CPP_SOURCES)  -CFLAGS "$(VERILATOR_DIRS)  -I../../simDevices $(EXTRA_CFLAGS)"
	@echo "$(BUILD_FLAGS)" > $(FLAGS_STAMP)
	cd obj_dir && make -f VND120_TOP.mk VND120_TOP

clean:
	rm -rf obj_dir

# Make sure the SD card image exists before a SD_STORAGE=1 run - without it
# sd_card_model.v aborts at time 0 ("FATAL cannot open image") and nothing
# boots. The default card is gitignored, so a fresh clone always lands here.
# A hand-supplied SD_CARD_IMG is never auto-built: we do not know what it is
# meant to contain, so a missing one is an error, not something to invent.
.PHONY: card
card:
ifeq ($(SD_CARD_NEEDED),1)
	@if [ ! -f "$(SD_CARD_IMG)" ]; then \
	  if [ "$(SD_CARD_IMG)" = "$(SD_CARD_IMG_DEFAULT)" ]; then \
	    echo "card: $(SD_CARD_IMG) missing - building it"; \
	    ../SD-FAT/sim/make_boot_card.sh; \
	  else \
	    echo "card: SD_CARD_IMG=$(SD_CARD_IMG) does not exist (not auto-built:" >&2; \
	    echo "      only the default card is generated, by make_boot_card.sh)" >&2; \
	    exit 1; \
	  fi; \
	fi
endif

# run   = the Verilog device stack fed by the real SD-FAT RTL reading a
#         simulated SD card (the same RTL that runs on Tang).
# run-c = the C device models in ../simDevices (NDBus.cpp file servers).
# Both recurse so the flag set is fixed here rather than left to the caller;
# the .buildflags stamp in 'compile' wipes obj_dir when you switch between them.
run:
	$(MAKE) run-sim VERILOG_TAPE=1 SD_STORAGE=1

run-c:
	$(MAKE) run-sim VERILOG_TAPE=0

run-sim: compile card
	ND120_FLOPPY_IMG=$(FLOPPY_IMG) ./obj_dir/VND120_TOP

# ---- other programs on the boot card -------------------------------------
# Same '400$' tape boot, different BOOT.BPUN. Each program gets its OWN card
# image so they never clobber each other and switching back does not rebuild.
# The BPUNs are committed here - these targets never read a BPUN folder
# outside the repository.
#
#   run-config  CONFIGURATIO-C08.BPUN - device configuration. Type RUN at its
#               prompt to make it probe the machine: this is what says whether
#               the floppy / SMD / tape controllers are detected correctly.
#   run-fs      FILSYS-INV-Q04.BPUN - file-system investigator. Looks INTO a
#               disk image (floppy or SMD), so it validates that we can read
#               those images at all.
#
# Card size note: make_boot_card.sh refuses anything over 65536 bytes (SLOT0 =
# 32 blocks x 2048). CONFIGURATIO-C08 = 47052, FILSYS-INV-Q04 = 50870 - both fit.
CONFIG_BPUN = CONFIGURATIO-C08.BPUN
FS_BPUN     = FILSYS-INV-Q04.BPUN

run-config:
	../SD-FAT/sim/make_boot_card.sh ../../runSim/$(CONFIG_BPUN) nd_config_card.img
	$(MAKE) run-sim VERILOG_TAPE=1 SD_STORAGE=1 \
	        SD_CARD_IMG=../SD-FAT/sim/nd_config_card.img

run-fs:
	../SD-FAT/sim/make_boot_card.sh ../../runSim/$(FS_BPUN) nd_fs_card.img
	$(MAKE) run-sim VERILOG_TAPE=1 SD_STORAGE=1 \
	        SD_CARD_IMG=../SD-FAT/sim/nd_fs_card.img

# Interactive floppy-boot session: Verilog device build (DMA floppy at
# 1560) with a bootable diskette image behind it. At the '#' prompt
# type 1560& - the BPUN loader boots the diskette's program, which
# then owns the console (type help etc. at ITS prompt).
# Override the image with: make run-floppy FLOPPY_IMG=path/to.img
FLOPPY_IMG ?= ../ND-BUS-DEVICES/testdata/210523I01-XX-01D.img

# Floppy boot: Verilog device stack (DMA floppy at 1560) with the diskette
# served from ND120_FLOPPY_IMG by the C++ backend (process_verilog_floppy).
# SD_STORAGE=0 is REQUIRED: the floppy file server is gated `#ifndef
# ND120_SD_STORAGE` (NDBus.cpp), so with SD_STORAGE=1 the image is never served
# and 1560& hangs. No SD card / no tape path here.
#
# The FILE-SYSTEM INVESTIGATOR is pre-deposited into RAM (Ronny 20-JUL-2026):
# `20!` starts it and it inspects the MOUNTED diskette through the floppy
# device - that is the point of this target. It deliberately does NOT preload
# INSTRUCTION-VERIFY (DEBUG.BPUN). A floppy-BOOT validation (`1560&` must load
# the program itself) needs an EMPTY RAM: use the test-floppy-boot gate, or run
# the binary with ND120_PRELOAD_BPUN= (empty) explicitly.
run-floppy:
	$(MAKE) compile VERILOG_TAPE=1 SD_STORAGE=0
	ND120_PRELOAD_BPUN=$(FS_BPUN) ND120_FLOPPY_IMG=$(FLOPPY_IMG) ./obj_dir/VND120_TOP

# ---- NDDeviceCore C-core interactive runs (the portable RP2350 device cores) --
# These build the PORTABLE C device cores (VERILOG_TAPE=0, DEVICECORE=1) and boot
# a real image THROUGH them, so you exercise the SAME .c code the Pico runs. No
# cycle cap - they run until you Ctrl-C. To cap a run, pass a limit on the command
# line ONLY: ND120_SCRIPT_BUDGET=N (cycles after boot) or ND120_MAX_CNT=N.
#
#   run-tpe       Boot the TPE Monitor diskette (TPE_IMG) through the C floppy
#                 core - PURE MANUAL, NO scripted keypresses. YOU type '1560&' at
#                 the '#' prompt to boot, then drive the whole session yourself.
#                 TPE is SLOW (its panel-clock probe runs ~a few minutes before
#                 '==TPE42=>'). The 'clock is not updated' message is EXPECTED
#                 (the MM58274/MC68705 calendar panel is an RTL stub, IO_PANCAL_40).
#   run-tpe-auto  Same boot but UNATTENDED / scripted: auto-types
#                 '1560&config<CR>run<CR>' (the ONLY target that injects keys).
#   run-rtc       Pre-deposit the RTC.BPUN clock diagnostic and start it at octal
#                 20 - a standalone check of the 20ms level-13 clock (prints
#                 'CLOCK TEST NORD-100' + an 'A' liveness stream when healthy).
# Override the image/program with e.g. `make run-tpe TPE_IMG=path/to.img`.
TPE_IMG  ?= FLOPPY1.IMG
RTC_BPUN ?= RTC.BPUN

# run-tpe REUSES an existing clean floppy-core binary instead of re-running
# Verilator every time: it only (re)builds when obj_dir/VND120_TOP is missing or
# was built with different flags (e.g. an injector/-DSCRIPT_INPUT build, or a
# non-floppy build). It does NOT detect SOURCE edits - after changing .c/.v code
# run `make run-tpe-rebuild` to force a fresh compile.
run-tpe:
	@if [ -x obj_dir/VND120_TOP ] && grep -q ND120_DEVICECORE_FLOPPY obj_dir/.buildflags 2>/dev/null && ! grep -q SCRIPT_INPUT obj_dir/.buildflags 2>/dev/null; then \
	  echo "==> run-tpe: reusing obj_dir/VND120_TOP (run 'make run-tpe-rebuild' after editing source)"; \
	else \
	  echo "==> run-tpe: building the clean floppy-core binary (no injector)"; \
	  $(MAKE) compile VERILOG_TAPE=0 SD_STORAGE=0 DEVICECORE=1 DEVICECORE_FLOPPY=1; \
	fi
	ND120_FLOPPYCORE_IMG=$(TPE_IMG) ./obj_dir/VND120_TOP

# Force a clean floppy-core recompile then run (use after editing source).
run-tpe-rebuild:
	$(MAKE) compile VERILOG_TAPE=0 SD_STORAGE=0 DEVICECORE=1 DEVICECORE_FLOPPY=1
	ND120_FLOPPYCORE_IMG=$(TPE_IMG) ./obj_dir/VND120_TOP

run-tpe-auto:
	$(MAKE) compile VERILOG_TAPE=0 SD_STORAGE=0 DEVICECORE=1 DEVICECORE_FLOPPY=1 \
	        EXTRA_CFLAGS="-DSCRIPT_INPUT -DSCRIPT_CMD_FBOOTCFG"
	ND120_FLOPPYCORE_IMG=$(TPE_IMG) ./obj_dir/VND120_TOP

run-rtc:
	$(MAKE) compile VERILOG_TAPE=1 SD_STORAGE=0 \
	        EXTRA_CFLAGS="-DSCRIPT_INPUT -DSCRIPT_CMD_20"
	ND120_PRELOAD_BPUN=$(RTC_BPUN) ./obj_dir/VND120_TOP

# run-tpe-trace: identical to run-tpe (PURE MANUAL, you type 1560&) but with the
# NDDeviceCore floppy trace ON (ND120_CORE_TRACE=1). Every IOX read/write, the
# decoded FLP-COMMAND (func / drive / LBA / word count), FLP-PHASE (media byte
# position, bytes/sector) and STORAGE submit/done (position, bytes moved) prints
# as [ndcore] lines, interleaved with the console. Use it to see EXACTLY what TPE
# sends the floppy and what comes back (e.g. why LIST-FILES / LOAD-PROGRAM report
# OUTSIDE DEVICE LIMITS - does TPE even issue a floppy command, or reject first?).
run-tpe-trace:
	@if [ -x obj_dir/VND120_TOP ] && grep -q ND120_DEVICECORE_FLOPPY obj_dir/.buildflags 2>/dev/null && ! grep -q SCRIPT_INPUT obj_dir/.buildflags 2>/dev/null; then \
	  echo "==> run-tpe-trace: reusing obj_dir/VND120_TOP"; \
	else \
	  $(MAKE) compile VERILOG_TAPE=0 SD_STORAGE=0 DEVICECORE=1 DEVICECORE_FLOPPY=1; \
	fi
	ND120_FLOPPYCORE_IMG=$(TPE_IMG) ND120_CORE_TRACE=1 ./obj_dir/VND120_TOP


.PHONY: all clean run run-c run-sim run-floppy run-tpe run-tpe-rebuild run-tpe-auto run-rtc run-tpe-trace
