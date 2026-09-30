# UPDATE NEXT 3 LINES PR TEST PROGRAM
TOP_FILE = CGA_MAC
TEST_PROGRAM = test_mac.cpp
TEST_FOLDER = ${TOP_FILE}

SUPPRESS_FLAGS = -Wno-PINCONNECTEMPTY -Wno-UNUSED -Wno-UNDRIVEN -Wno-WIDTH -Wno-LATCH

# This is the path to the root of the verilog directory
VERILOG_ROOT = ../../..

SHARED_COMPONENTS = -y ${VERILOG_ROOT}/Shared/ndlib -y ${VERILOG_ROOT}/Shared/logisim -y ${VERILOG_ROOT}/Shared/support

DELILAH_ROOT = ${VERILOG_ROOT}/DELILAH-CPU
COMPONENT_ROOT = ${DELILAH_ROOT}/${TEST_FOLDER}/circuit

VERILATOR_FLAGS = --trace -Wall --cc ${COMPONENT_ROOT}/${TOP_FILE}.v --exe ${TEST_PROGRAM} $(SUPPRESS_FLAGS)  

CGA_COMPONENTS = --I${COMPONENT_ROOT} -I${DELILAH_ROOT}/CGA_ALU/circuit -I${DELILAH_ROOT}/CGA_DCD/circuit -I${DELILAH_ROOT}/CGA_IDBCTL/circuit -I${DELILAH_ROOT}/CGA_INTR/circuit -I${DELILAH_ROOT}/CGA_MAC/circuit -I${DELILAH_ROOT}/CGA_MIC/circuit -I${DELILAH_ROOT}/CGA_TESTMUX/circuit -I${DELILAH_ROOT}/CGA_TRAP/circuit -I${DELILAH_ROOT}/CGA_WRF/circuit
VERILATOR_DIRS = -I${COMPONENT_ROOT} ${SHARED_COMPONENTS} $(CGA_COMPONENTS)

VERILATOR = verilator

# Specify C++ source files here
CPP_SOURCES = ${TEST_PROGRAM}

# Default target
all: test_mac run gtk

test_mac: $(CPP_SOURCES)
	$(VERILATOR) $(VERILATOR_FLAGS) $(VERILATOR_DIRS)
	cd obj_dir && make -f VCGA_MAC.mk VCGA_MAC

# --- iverilog gate-level testbenches (self-checking, TB_RESULT: PASS) --------
# Generic rule: `make iv-<MODULE>` compiles+runs <MODULE>_tb.v against the gate
# netlists (Shared libs + circuit/ resolved via -y). Registered per-tb in
# tests/run_all_tests.sh.
IV_LIB = -y ${VERILOG_ROOT}/Shared/logisim -y ${VERILOG_ROOT}/Shared/support -y ${VERILOG_ROOT}/Shared/ndlib
iv-%:
	iverilog -g2012 $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_$* $*_tb.v && vvp -N /tmp/ndtb_$*

# --- CGA_MAC_DECODE exhaustive decode verification, BOTH build modes ---------
# 512-combination sweep vs a golden table + SPT/SAPT mutual-exclusion invariant
# (the Issue-C GATES_5 regression tooth) + the MCLK-registered LLDEXM/LLDSEG/
# LLDPCR strobes. Run twice: default latch/CP mode, then FPGA_FF_MODE
# (MCLK_EN-gated sysclk capture). Registered in tests/run_all_tests.sh; a FAIL
# line in either run fails the suite.
test-decode:
	iverilog -g2012 $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_decode CGA_MAC_DECODE_tb.v && vvp -N /tmp/ndtb_mac_decode
	iverilog -g2012 -DFPGA_FF_MODE $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_decode_ff CGA_MAC_DECODE_tb.v && vvp -N /tmp/ndtb_mac_decode_ff

# --- CGA_MAC_FASTADD exhaustive adder verification, BOTH build modes --------
# Directed edge vectors + per-stage exhaustive sweeps (low adder 64K, high
# adder 64K with carry=0 and 64K with carry=1) + 4096 fixed-seed LFSR vectors,
# all vs an independent 16-bit-sum model. Pure comb module; both build modes
# run for campaign uniformity. Registered in tests/run_all_tests.sh.
test-fastadd:
	iverilog -g2012 $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_fastadd CGA_MAC_FASTADD_tb.v && vvp -N /tmp/ndtb_mac_fastadd
	iverilog -g2012 -DFPGA_FF_MODE $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_fastadd_ff CGA_MAC_FASTADD_tb.v && vvp -N /tmp/ndtb_mac_fastadd_ff

# --- CGA_MAC_ADD address-adder verification, BOTH build modes ---------------
# 4-way PRP source selector (A02 AOI + bubbled OR = OR-merge of selected
# registers) + CDS sign-extension of CD[7:0] + FASTADD 16-bit sum, all vs an
# independent behavioral golden model. Layers: exhaustive 32-combo control
# sweep x 18 directed data tuples, per-bit carry corners x each single-select
# mode, exhaustive CDS low-byte sweep with 3 ignored high bytes, 120000
# fixed-seed random vectors. Pure comb module; both build modes run for
# campaign uniformity. Registered in tests/run_all_tests.sh.
test-mac-add:
	iverilog -g2012 $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_add CGA_MAC_ADD_tb.v && vvp -N /tmp/ndtb_mac_add
	iverilog -g2012 -DFPGA_FF_MODE $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_add_ff CGA_MAC_ADD_tb.v && vvp -N /tmp/ndtb_mac_add_ff

# --- CGA_MAC_PTSEL exhaustive verification, BOTH build modes ----------------
# All 32 {q,SPTN,SAPT,PONI,PTM} combinational SELPTN combos vs a golden table
# + directed JK set/clear/hold/toggle sequences (toggle = the Issue-C hazard;
# upstream DECODE fix guarantees J,K never both 1 in practice) + preset
# dominance + hold-without-clock. Run twice: latch/CP mode, then FPGA_FF_MODE
# (MCLK_EN-gated sysclk capture). Registered in tests/run_all_tests.sh.
test-ptsel:
	iverilog -g2012 $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_ptsel CGA_MAC_PTSEL_tb.v && vvp -N /tmp/ndtb_mac_ptsel
	iverilog -g2012 -DFPGA_FF_MODE $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_ptsel_ff CGA_MAC_PTSEL_tb.v && vvp -N /tmp/ndtb_mac_ptsel_ff

# --- CGA_MAC_SEGPT family, ALL THREE latch builds ---------------------------
# The SEGPT registers are built from the L4/L8 latch primitives, whose
# behavior switches on USE_TRANSPARENT_LATCHES (true level latch) vs default
# (mux + posedge-sysclk FF). Each target runs three builds: plain,
# -DFPGA_FF_MODE (campaign uniformity; L4/L8 do not reference it) and
# -DUSE_TRANSPARENT_LATCHES. Golden tables from an independent Python gate
# model (kept outside the repo, see tb headers). Registered in
# tests/run_all_tests.sh; a FAIL line in any run fails the suite.
SEGPT_MODES = "" "-DFPGA_FF_MODE" "-DUSE_TRANSPARENT_LATCHES"

# Segment register: 256-value transparent sweep + SEGZN golden table +
# directed load/hold + enable gating.
test-segpt-seg:
	for m in $(SEGPT_MODES); do \
	  iverilog -g2012 $$m $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_segpt_seg CGA_MAC_SEGPT_SEG_tb.v && vvp -N /tmp/ndtb_segpt_seg || exit 1; \
	done

# XPT block: exhaustive 8x2 latched sweep vs golden table + transparency,
# hold and enable gating.
test-segpt-xpt:
	for m in $(SEGPT_MODES); do \
	  iverilog -g2012 $$m $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_segpt_xpt CGA_MAC_SEGPT_XPT_tb.v && vvp -N /tmp/ndtb_segpt_xpt || exit 1; \
	done

# PCR register: exhaustive 64K transparent sweep vs the bit-mapping (PIL
# field 6:3 forced 0) + 32 LFSR literal loads + corners + enable gating.
test-segpt-pcr:
	for m in $(SEGPT_MODES); do \
	  iverilog -g2012 $$m $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_segpt_pcr CGA_MAC_SEGPT_PCR_tb.v && vvp -N /tmp/ndtb_segpt_pcr || exit 1; \
	done

# SEGPT parent integration: MCLK inversion polarity, 260-vector load sweep
# of all three registers, per-register load independence, MCLK=1 blocking,
# transparency polarity.
test-segpt:
	for m in $(SEGPT_MODES); do \
	  iverilog -g2012 $$m $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_segpt CGA_MAC_SEGPT_tb.v && vvp -N /tmp/ndtb_segpt || exit 1; \
	done

# --- CGA_MAC_APOS_INC exhaustive incrementer verification, single build -----
# All 65536 LCA values vs an independent bitwise ripple model + running
# checksum vs the Python-generator constant + directed carry-boundary
# corners. Pure comb (the active RTL instantiates no library primitives),
# so one build covers all modes. Registered in tests/run_all_tests.sh.
test-apos-inc:
	iverilog -g2012 $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_apos_inc CGA_MAC_APOS_INC_tb.v && vvp -N /tmp/ndtb_mac_apos_inc

# --- CGA_MAC_APOS_CALCA latch/register/decode verification, THREE builds ----
# 64K transparent MCA sweep + checksum, exhaustive 1024-address load sweep
# of the LCA register path with ECCR (IOX 100115) decode both ECCRHIN
# polarities, 32 LFSR + 4 corner load/hold vectors, MCLK gating. Uses L8
# (USE_TRANSPARENT_LATCHES) and R81_EN (FPGA_FF_MODE), so all three builds
# run. Registered in tests/run_all_tests.sh; a FAIL in any run fails the
# suite.
test-apos-calca:
	for m in $(SEGPT_MODES); do \
	  iverilog -g2012 $$m $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_apos_calca CGA_MAC_APOS_CALCA_tb.v && vvp -N /tmp/ndtb_mac_apos_calca || exit 1; \
	done

# --- CGA_MAC_AP09 ICA selector + CALCA + incrementer, THREE builds ----------
# Wired-OR ICA source mux (A02 AOI + bubbled OR3 + NLCA NAND gating) vs a
# behavioral golden model, NLCA = LCA+1, MCA latch transparency/hold, LCA
# register loads, ECCR (IOX 100115) decode both ECCRHIN polarities, 4000
# fixed-seed xorshift soak with 1000 full load events. Uses L8 latches
# (USE_TRANSPARENT_LATCHES) and R81_EN (FPGA_FF_MODE), so all three builds
# run. Registered in tests/run_all_tests.sh; a FAIL in any run fails the
# suite.
test-mac-ap09:
	for m in $(SEGPT_MODES); do \
	  iverilog -g2012 $$m $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_ap09 CGA_MAC_AP09_tb.v && vvp -N /tmp/ndtb_mac_ap09 || exit 1; \
	done

# --- CGA_MAC_LASEL exhaustive shadow/select verification, BOTH build modes --
# All 2^19 combinational input combos vs a Python-cross-checked compact
# model + running checksum, plus LSHADOW (MCLK-clocked FF) capture/hold.
# MEMORY_24 is a D_FLIPFLOP_EN, so plain and -DFPGA_FF_MODE both run; no
# L4/L8 latches, so USE_TRANSPARENT_LATCHES does not apply. Registered in
# tests/run_all_tests.sh.
test-lasel:
	iverilog -g2012 $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_lasel CGA_MAC_LASEL_tb.v && vvp -N /tmp/ndtb_mac_lasel
	iverilog -g2012 -DFPGA_FF_MODE $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_lasel_ff CGA_MAC_LASEL_tb.v && vvp -N /tmp/ndtb_mac_lasel_ff

# --- CGA_MAC_LA1025 logical-address block, THREE builds ---------------------
# Wired-OR LA23-10 source merge (SEG/PCR/XPT/ICA products via A02 AOI +
# bubbled OR, NAND pairs registered through inverting R81 outputs) vs a
# behavioral golden model, plus the ECCRHIN LA[15:10]==100000 decode.
# Layers: exhaustive 2048-combo control sweep x 4 distinct-constant tuples,
# walking-1/0 per data input per select, ECCRHIN directed hits/near-misses
# through all three ICA paths, register hold, 4000 fixed-seed soak. Only
# R81_EN registers (no L4/L8), so plain and USE_TRANSPARENT_LATCHES builds
# are identical; all three run for family uniformity. Registered in
# tests/run_all_tests.sh; a FAIL line in any run fails the suite.
test-mac-la1025:
	for m in $(SEGPT_MODES); do \
	  iverilog -g2012 $$m $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_la1025 CGA_MAC_LA1025_tb.v && vvp -N /tmp/ndtb_mac_la1025 || exit 1; \
	done

clean:
	rm -rf obj_dir

run: test_mac
	./obj_dir/VCGA_MAC

gtk: run	
	gtkwave waveform.vcd cga_mac.gtkw &

.PHONY: all clean

# --- CGA_MAC cycle-accurate REPLAY against a live boot capture -------------
# Replays every CGA_MAC input, cycle by cycle, exactly as captured from a real
# Winchester boot by the ND120_MAC_CAPTURE probe (ND120_TOP.v), and checks the
# module's outputs against what the full machine produced on those same cycles.
#
# Chasing: the indirect `JPL I *14` at 000465 lands at 144162 instead of 144163
# once in 15 executions, with L CORRECT and only bit 0 of P wrong. CGA_MAC owns
# the address arithmetic (NLCA_15_0 = the "+1", PCR_15_0 = P), so if a latch or
# flip-flop clocking difference is dropping the increment this reproduces it in
# isolation - and if it PASSES, CGA_MAC is innocent and the fault is in what
# drives it.
#
# Needs maccap_vectors.txt, built from the capture dump:
#   python3 maccap_to_vectors.py <capture-dump.log>
# NOTE: each make recipe line is its own shell, so the "no vectors" guard must
# wrap the whole thing in ONE shell - an `exit 0` on its own line would only end
# that line and the tb would run anyway (and fail) with no capture present.
test-mac-replay:
	@if [ ! -s maccap_vectors.txt ]; then \
	   echo "TB_RESULT: SKIP - no maccap_vectors.txt (MAC capture has not triggered yet)"; \
	 else \
	   iverilog -g2012 $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_replay CGA_MAC_replay_tb.v && vvp -N /tmp/ndtb_mac_replay && \
	   iverilog -g2012 -DFPGA_FF_MODE $(IV_LIB) -y ${COMPONENT_ROOT} -o /tmp/ndtb_mac_replay_ff CGA_MAC_replay_tb.v && vvp -N /tmp/ndtb_mac_replay_ff; \
	 fi
