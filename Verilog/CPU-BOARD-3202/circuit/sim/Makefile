# Testbenches for CPU-BOARD-3202 circuit modules.
IVERILOG = iverilog
CIRCUIT  = ..
PAL      = ../../../PAL

# Exhaustive validation of CYC_TERM_D (TERM next-state mirror) vs PAL_44601B.
CYC_TERM_D_tb: CYC_TERM_D_tb.v $(CIRCUIT)/CYC_TERM_D.v $(PAL)/PAL_44601B.v
	$(IVERILOG) -g2012 -o $@ $^

test-cyctermd: CYC_TERM_D_tb
	./CYC_TERM_D_tb

# Exhaustive validation of CYC_CC_D (CC next-state mirror) vs PAL_44601B.
CYC_CC_D_tb: CYC_CC_D_tb.v $(CIRCUIT)/CYC_CC_D.v $(PAL)/PAL_44601B.v
	$(IVERILOG) -g2012 -o $@ $^

test-ccd: CYC_CC_D_tb
	./CYC_CC_D_tb

# MEM_ADDR_44 address-latch regression (BCGNT50 grant window + LBD
# address-then-data multiplex; catches level-enable capture bugs).
SUPPORT = ../../../Shared/support
MEM_ADDR_44_tb: MEM_ADDR_44_tb.v $(CIRCUIT)/MEM_ADDR_44.v $(SUPPORT)/AM29C821.v $(SUPPORT)/AM29861A.v
	$(IVERILOG) -g2012 -o $@ $^

test-memaddr: MEM_ADDR_44_tb
	./MEM_ADDR_44_tb | tee memaddr_out.log
	@grep -q "TB_RESULT: PASS" memaddr_out.log

# Address + RAM chain: full write/readback over the measured DRAM protocol
# through MEM_ADDR_44 -> MEM_RAM_49 (SIP1M9 FPGA BRAM path, ramSize=3).
MEM_CHAIN_tb: MEM_CHAIN_tb.v $(CIRCUIT)/MEM_ADDR_44.v $(CIRCUIT)/MEM_RAM_49.v $(SUPPORT)/AM29C821.v $(SUPPORT)/AM29861A.v $(SUPPORT)/SIP1M9.v
	$(IVERILOG) -g2012 -o $@ $^

test-memchain: MEM_CHAIN_tb
	./MEM_CHAIN_tb | tee memchain_out.log
	@grep -q "TB_RESULT: PASS" memchain_out.log

# Same chain against the other sheet-49 backends (shared interface,
# different internals): FPGA block-RAM and the Verilator zero-delay model.
MEM_CHAIN_BLOCKRAM_tb: MEM_CHAIN_tb.v $(CIRCUIT)/MEM_ADDR_44.v $(CIRCUIT)/MEM_RAM_49_BLOCKRAM.v $(SUPPORT)/AM29C821.v $(SUPPORT)/AM29861A.v
	$(IVERILOG) -g2012 -DCHAIN_USE_BLOCKRAM -o $@ $^

test-memchain-blockram: MEM_CHAIN_BLOCKRAM_tb
	./MEM_CHAIN_BLOCKRAM_tb | tee memchain_br_out.log
	@grep -q "TB_RESULT: PASS" memchain_br_out.log

MEM_CHAIN_SIM_tb: MEM_CHAIN_tb.v $(CIRCUIT)/MEM_ADDR_44.v $(CIRCUIT)/MEM_RAM_49_SIM.v $(SUPPORT)/AM29C821.v $(SUPPORT)/AM29861A.v
	$(IVERILOG) -g2012 -DCHAIN_USE_SIM -o $@ $^

test-memchain-sim: MEM_CHAIN_SIM_tb
	./MEM_CHAIN_SIM_tb | tee memchain_sim_out.log
	@grep -q "TB_RESULT: PASS" memchain_sim_out.log

test-all: test-cyctermd test-ccd test-memaddr test-memchain test-memchain-blockram test-memchain-sim

clean:
	rm -f CYC_TERM_D_tb CYC_CC_D_tb MEM_ADDR_44_tb MEM_CHAIN_tb MEM_CHAIN_BLOCKRAM_tb MEM_CHAIN_SIM_tb *.vcd *_out.log
	rm -f MEM_RAM_49_SIM_PARITY_tb_p0 MEM_RAM_49_SIM_PARITY_tb_p1 MEM_ERROR_47_tb_bin *_result.tmp
	rm -f CPU_MMU_PT_29_shadow_rmw_tb_bin CPU_MMU_PT_29_shadow_rmw_async_tb_bin
	rm -f CPU_MMU_24_shadow_tb_bin CPU_MMU_24_shadow_async_tb_bin
	# NB: CPU_CYCLE_TIMELINE.golden is a checked-in reference, NOT an artefact - never delete it here
	rm -f CPU_CYCLE_TIMELINE_tb CPU_CS_RWCS_CYCLE_tb CPU_CS_TCV_20_tb cycle_timeline_out.trace cycle_timeline.diff

.PHONY: test-cyctermd test-ccd test-memaddr test-memchain test-all clean \
        test-cs-rwcs-cycle test-cycle-timeline golden-cycle-timeline test-cs-tcv

# MEM_RAM_49_BLOCKRAM: block-RAM sheet-49 backend, measured DRAM protocol
test-blockram: MEM_RAM_49_BLOCKRAM_tb
	./MEM_RAM_49_BLOCKRAM_tb | tee blockram_result.tmp
	@grep -q "TB_RESULT: PASS" blockram_result.tmp && rm -f blockram_result.tmp MEM_RAM_49_BLOCKRAM_tb.vcd

MEM_RAM_49_BLOCKRAM_tb: MEM_RAM_49_BLOCKRAM_tb.v $(CIRCUIT)/MEM_RAM_49_BLOCKRAM.v
	$(IVERILOG) -g2012 -o $@ MEM_RAM_49_BLOCKRAM_tb.v $(CIRCUIT)/MEM_RAM_49_BLOCKRAM.v

# Address-SPACE integrity gate (24-AUG-2026 LIST-FILE-NAMES runaway): the
# backend must span the full 64K-word logical space. Built at the size the
# Nexys build ships (ND120_BLOCKRAM_ADDR_BITS=16 - keep in step with
# fpga/nexys4ddr/build.tcl); any ADDR_BITS < 16 fails the contract check,
# and the 16-bit address-bit walk catches dropped/swapped/truncated bits.
# Teeth proven: -DND120_BLOCKRAM_ADDR_BITS=15 fails loudly.
test-blockram-space: MEM_RAM_49_BLOCKRAM_SPACE_tb
	./MEM_RAM_49_BLOCKRAM_SPACE_tb | tee blockram_space_result.tmp
	@grep -q "TB_RESULT: PASS" blockram_space_result.tmp && rm -f blockram_space_result.tmp MEM_RAM_49_BLOCKRAM_SPACE_tb.vcd

MEM_RAM_49_BLOCKRAM_SPACE_tb: MEM_RAM_49_BLOCKRAM_SPACE_tb.v $(CIRCUIT)/MEM_RAM_49_BLOCKRAM.v
	$(IVERILOG) -g2012 -DND120_BLOCKRAM_ADDR_BITS=16 -o $@ MEM_RAM_49_BLOCKRAM_SPACE_tb.v $(CIRCUIT)/MEM_RAM_49_BLOCKRAM.v

# The same gate at the MiSTer's array shape: three bank slots instead of
# four (ND120_BLOCKRAM_BANK_SLOTS=3, nd120.qsf). All three banks must still
# be there at 64K words each - a slot count that dropped a bank would fail.
test-blockram-space-3banks: MEM_RAM_49_BLOCKRAM_SPACE3_tb
	./MEM_RAM_49_BLOCKRAM_SPACE3_tb | tee blockram_space3_result.tmp
	@grep -q "TB_RESULT: PASS" blockram_space3_result.tmp && rm -f blockram_space3_result.tmp MEM_RAM_49_BLOCKRAM_SPACE_tb.vcd

MEM_RAM_49_BLOCKRAM_SPACE3_tb: MEM_RAM_49_BLOCKRAM_SPACE_tb.v $(CIRCUIT)/MEM_RAM_49_BLOCKRAM.v
	$(IVERILOG) -g2012 -DND120_BLOCKRAM_ADDR_BITS=16 -DND120_BLOCKRAM_BANK_SLOTS=3 -o $@ MEM_RAM_49_BLOCKRAM_SPACE_tb.v $(CIRCUIT)/MEM_RAM_49_BLOCKRAM.v

# ERRFA evidence probe (ND120_ERRFA_PROBE in MEM_RAM_49_BLOCKRAM.v): the
# five save-cell writes 0o4347-0o4353 must come back verbatim as the
# "EF X T A D L" octal console line, and the TX must stay SILENT until the
# L save (an early-firing probe garbles the live console). Fast-sim gap
# and baud via the ND120_ERRFA_* overrides.
test-blockram-errfa: MEM_RAM_49_BLOCKRAM_ERRFA_tb
	./MEM_RAM_49_BLOCKRAM_ERRFA_tb | tee blockram_errfa_result.tmp
	@grep -q "TB_RESULT: PASS" blockram_errfa_result.tmp && rm -f blockram_errfa_result.tmp

MEM_RAM_49_BLOCKRAM_ERRFA_tb: MEM_RAM_49_BLOCKRAM_ERRFA_tb.v $(CIRCUIT)/MEM_RAM_49_BLOCKRAM.v
	$(IVERILOG) -g2012 -DND120_ERRFA_PROBE -DND120_ERRFA_BAUD_DIV=16 -DND120_ERRFA_GAP_BITS=18 -DND120_ERRFA_RWAIT_BITS=13 -o $@ MEM_RAM_49_BLOCKRAM_ERRFA_tb.v $(CIRCUIT)/MEM_RAM_49_BLOCKRAM.v

# BIF datapath sheets: run the same vectors in latch mode (plain) and FF
# mode (-DFPGA_FF_MODE, the P1c-2/P1d sysclk edge-captures). Both must pass.
BIF_SUPPORT = ../../../Shared/support

test-cdlbd: BIF_DPATH_CDLBD_11_tb BIF_DPATH_CDLBD_11_ff_tb
	./BIF_DPATH_CDLBD_11_tb    | tee cdlbd_result.tmp
	@grep -q "TB_RESULT: PASS" cdlbd_result.tmp
	./BIF_DPATH_CDLBD_11_ff_tb | tee cdlbd_result.tmp
	@grep -q "TB_RESULT: PASS" cdlbd_result.tmp && rm -f cdlbd_result.tmp BIF_DPATH_CDLBD_11_tb.vcd

BIF_DPATH_CDLBD_11_tb: BIF_DPATH_CDLBD_11_tb.v $(CIRCUIT)/BIF_DPATH_CDLBD_11.v $(BIF_SUPPORT)/TTL_74646.v
	$(IVERILOG) -g2012 -o $@ $^

BIF_DPATH_CDLBD_11_ff_tb: BIF_DPATH_CDLBD_11_tb.v $(CIRCUIT)/BIF_DPATH_CDLBD_11.v $(BIF_SUPPORT)/TTL_74646.v
	$(IVERILOG) -g2012 -DFPGA_FF_MODE -o $@ $^

test-bdlbd: BIF_DPATH_BDLBD_10_tb BIF_DPATH_BDLBD_10_ff_tb
	./BIF_DPATH_BDLBD_10_tb    | tee bdlbd_result.tmp
	@grep -q "TB_RESULT: PASS" bdlbd_result.tmp
	./BIF_DPATH_BDLBD_10_ff_tb | tee bdlbd_result.tmp
	@grep -q "TB_RESULT: PASS" bdlbd_result.tmp && rm -f bdlbd_result.tmp BIF_DPATH_BDLBD_10_tb.vcd

BIF_DPATH_BDLBD_10_tb: BIF_DPATH_BDLBD_10_tb.v $(CIRCUIT)/BIF_DPATH_BDLBD_10.v $(BIF_SUPPORT)/TTL_74648.v
	$(IVERILOG) -g2012 -o $@ $^

BIF_DPATH_BDLBD_10_ff_tb: BIF_DPATH_BDLBD_10_tb.v $(CIRCUIT)/BIF_DPATH_BDLBD_10.v $(BIF_SUPPORT)/TTL_74648.v
	$(IVERILOG) -g2012 -DFPGA_FF_MODE -o $@ $^

# MEM_DATA_46: parity transceivers + PAL_45008B, latch and FF modes
LOGISIM = ../../../Shared/logisim
MEMDATA_SRCS = MEM_DATA_46_tb.v $(CIRCUIT)/MEM_DATA_46.v $(BIF_SUPPORT)/AM29833A.v $(PAL)/PAL_45008B.v $(LOGISIM)/NOR_GATE.v $(LOGISIM)/J_K_FLIPFLOP.v

test-memdata: MEM_DATA_46_tb_bin MEM_DATA_46_ff_tb_bin
	./MEM_DATA_46_tb_bin    | tee memdata_result.tmp
	@grep -q "TB_RESULT: PASS" memdata_result.tmp
	./MEM_DATA_46_ff_tb_bin | tee memdata_result.tmp
	@grep -q "TB_RESULT: PASS" memdata_result.tmp && rm -f memdata_result.tmp MEM_DATA_46_tb.vcd

MEM_DATA_46_tb_bin: $(MEMDATA_SRCS)
	$(IVERILOG) -g2012 -o $@ $(MEMDATA_SRCS)

MEM_DATA_46_ff_tb_bin: $(MEMDATA_SRCS)
	$(IVERILOG) -g2012 -DFPGA_FF_MODE -o $@ $(MEMDATA_SRCS)

# CYC_36 clock-enable alignment (P2 foundation): EN pulse <=> pa-clock rise
CYCEN_SRCS = CYC_36_enables_tb.v $(CIRCUIT)/CYC_36.v $(CIRCUIT)/CYC_TERM_D.v $(CIRCUIT)/CYC_CC_D.v $(PAL)/PAL_44601B.v $(PAL)/PAL_44307C.v $(PAL)/PAL_44403C.v $(PAL)/PAL_44404C.v $(PAL)/PAL_44403C_EN.v $(PAL)/PAL_44404C_EN.v

test-cycen: CYC_36_enables_tb
	./CYC_36_enables_tb | tee cycen_result.tmp
	@grep -q "TB_RESULT: PASS" cycen_result.tmp && rm -f cycen_result.tmp CYC_36_enables_tb.vcd

CYC_36_enables_tb: $(CYCEN_SRCS)
	$(IVERILOG) -g2012 -DFPGA_FF_MODE -o $@ $(CYCEN_SRCS)

# CPU_CS_ACAL_17 LUA transparent-latch (Tang 06000 boot-hang root cause, 19-JUL).
# Compiled in FPGA mode (NO VERILATOR_SIM) so it exercises the FIXED `else`
# branch: LUA must track CSA with ZERO latency when MACLK=1. Fails on the old
# 1-cycle-lag FF, passes on the transparent-latch fix.
ACAL_SRCS = CPU_CS_ACAL_17_tb.v $(CIRCUIT)/CPU_CS_ACAL_17.v

test-acal: CPU_CS_ACAL_17_tb
	./CPU_CS_ACAL_17_tb | tee acal_result.tmp
	@grep -q "TB_RESULT: PASS" acal_result.tmp && rm -f acal_result.tmp

CPU_CS_ACAL_17_tb: $(ACAL_SRCS)
	$(IVERILOG) -g2012 -DFPGA_FF_MODE -o $@ $(ACAL_SRCS)

# MEM_RAM_49_SIM parity: write a deliberately-bad parity bit, read it back.
# Runs BOTH packing modes and asserts the mode-correct behaviour:
#   PACK16=0 -> stored parity read back, CORR_n=0 (bad parity DETECTED).
#   PACK16=1 -> ND_SDRAM_PACK16 (the shipped sim default) RECOMPUTES parity on
#               read, so the bad bit is discarded and CORR_n=1 (ABSORBED). This
#               is why a parity/ECCR override no longer fires and memory is
#               classified Mpm5 not Local. See docs/nd120-parity-analysis.md.
test-memparity: MEM_RAM_49_SIM_PARITY_tb_p0 MEM_RAM_49_SIM_PARITY_tb_p1
	./MEM_RAM_49_SIM_PARITY_tb_p0 | tee memparity_result.tmp
	@grep -q "TB_RESULT: PASS" memparity_result.tmp
	./MEM_RAM_49_SIM_PARITY_tb_p1 | tee memparity_result.tmp
	@grep -q "TB_RESULT: PASS" memparity_result.tmp && rm -f memparity_result.tmp

MEM_RAM_49_SIM_PARITY_tb_p0: MEM_RAM_49_SIM_PARITY_tb.v $(CIRCUIT)/MEM_RAM_49_SIM.v
	$(IVERILOG) -g2012 -o $@ $^

MEM_RAM_49_SIM_PARITY_tb_p1: MEM_RAM_49_SIM_PARITY_tb.v $(CIRCUIT)/MEM_RAM_49_SIM.v
	$(IVERILOG) -g2012 -DND_SDRAM_PACK16 -o $@ $^

# MEM_ERROR_47: PES/PEA error status+address capture on a local parity error
# (PAL_45009B strobes SPESL/SPEAL, 74374 latches). Proves the error datapath
# encodes the fields TPE reads via TRA PES / TRA PEA.
MEMERROR_SRCS = MEM_ERROR_47_tb.v $(CIRCUIT)/MEM_ERROR_47.v $(BIF_SUPPORT)/TTL_74374.v $(PAL)/PAL_45009B.v

test-memerror: MEM_ERROR_47_tb_bin
	./MEM_ERROR_47_tb_bin | tee memerror_result.tmp
	@grep -q "TB_RESULT: PASS" memerror_result.tmp && rm -f memerror_result.tmp MEM_ERROR_47_tb.vcd

MEM_ERROR_47_tb_bin: $(MEMERROR_SRCS)
	$(IVERILOG) -g2012 -o $@ $(MEMERROR_SRCS)

# CPU_MMU_PT_29 DETERMINISTIC REPLAY of the REAL captured VPN-63 paging setup.
# Vectors come from sim/tpe_paging.csv (probe capture of INSTRUCTION-B's MMS-II
# bring-up): PPN[o77]=o77, PT[o77]=162000 identity map for the 177777 top page.
# Regression guard that the shadow/PT block RAM returns that translation through
# its 1-clock sync-read latency. See the tb header for the honest scope.
MMUPT_SUPPORT = ../../../Shared/support
MMUPT_REPLAY_SRCS = CPU_MMU_PT_29_replay_tb.v $(CIRCUIT)/CPU_MMU_PT_29.v \
                    $(MMUPT_SUPPORT)/TMM2018D_25.v $(MMUPT_SUPPORT)/IMS1403_25.v

CPU_MMU_PT_29_replay_tb: $(MMUPT_REPLAY_SRCS)
	$(IVERILOG) -g2012 -o $@ $(MMUPT_REPLAY_SRCS)

test-mmupt-replay: CPU_MMU_PT_29_replay_tb
	./CPU_MMU_PT_29_replay_tb | tee mmupt_replay_result.tmp
	@grep -q "TB_RESULT: PASS" mmupt_replay_result.tmp && rm -f mmupt_replay_result.tmp

# CPU_MMU_PT_29 directed write/readback + read-latency characterisation
# (sync vs async shadow-RAM read; see the tb header). Same sources as the
# replay tb, different stimulus.
MMUPT_SRCS = CPU_MMU_PT_29_tb.v $(CIRCUIT)/CPU_MMU_PT_29.v \
             $(MMUPT_SUPPORT)/TMM2018D_25.v $(MMUPT_SUPPORT)/IMS1403_25.v

CPU_MMU_PT_29_tb_bin: $(MMUPT_SRCS)
	$(IVERILOG) -g2012 -o $@ $(MMUPT_SRCS)

test-mmupt: CPU_MMU_PT_29_tb_bin
	./CPU_MMU_PT_29_tb_bin | tee mmupt_result.tmp
	@grep -q "TB_RESULT: PASS" mmupt_result.tmp && rm -f mmupt_result.tmp

# CPU_MMU_PT_29 CACHE INHIBIT BIT (WCINH_n). The gate on the whole cache -
# CHIP_20G -> WCINH_n -> EWC -> WCA -> CWR -> CUP - and it had no coverage
# whatsoever until 28-AUG-2026, while CACHE-120-A00 was failing on hardware
# with "Cache not updated (Use of limit registers)".
WCINH_SRCS = CPU_MMU_PT_29_wcinh_tb.v $(CIRCUIT)/CPU_MMU_PT_29.v              $(MMUPT_SUPPORT)/TMM2018D_25.v $(MMUPT_SUPPORT)/IMS1403_25.v

CPU_MMU_PT_29_wcinh_tb_bin: $(WCINH_SRCS)
	$(IVERILOG) -g2012 -o $@ $(WCINH_SRCS)

test-mmu-wcinh: CPU_MMU_PT_29_wcinh_tb_bin
	./CPU_MMU_PT_29_wcinh_tb_bin | tee wcinh_result.tmp
	@grep -q "TB_RESULT: PASS" wcinh_result.tmp && rm -f wcinh_result.tmp

# CPU_MMU_PT_29 SHADOW-MEMORY read-modify-write bench: the PT STATUS bank
# (EPT_n) that had no coverage at all, bank shifting over PT_number*64+vpn,
# the shared-WMAP_n bank isolation, and the trap handler's read/modify/
# write-back of a PTE at three read->write distances (0 = back-to-back).
# TWO BUILDS from one source, because the shadow RAM read model is the
# centre of the investigation:
#   plain            - TMM2018D_25 synchronous block RAM, 1-clock read
#   -DTMM_ASYNC_READ - the faithful async SRAM read of the real chip, 0-clock
# Expectations that differ are written per model with `ifdef, so BOTH must
# pass - a bench that only passes in one mode is not a regression gate.
MMUPT_RMW_SRCS = CPU_MMU_PT_29_shadow_rmw_tb.v $(CIRCUIT)/CPU_MMU_PT_29.v \
                 $(MMUPT_SUPPORT)/TMM2018D_25.v $(MMUPT_SUPPORT)/IMS1403_25.v

test-mmupt-rmw: CPU_MMU_PT_29_shadow_rmw_tb_bin CPU_MMU_PT_29_shadow_rmw_async_tb_bin
	./CPU_MMU_PT_29_shadow_rmw_tb_bin | tee mmupt_rmw_result.tmp
	@grep -q "TB_RESULT: PASS" mmupt_rmw_result.tmp
	./CPU_MMU_PT_29_shadow_rmw_async_tb_bin | tee mmupt_rmw_result.tmp
	@grep -q "TB_RESULT: PASS" mmupt_rmw_result.tmp && rm -f mmupt_rmw_result.tmp

CPU_MMU_PT_29_shadow_rmw_tb_bin: $(MMUPT_RMW_SRCS)
	$(IVERILOG) -g2012 -o $@ $(MMUPT_RMW_SRCS)

CPU_MMU_PT_29_shadow_rmw_async_tb_bin: $(MMUPT_RMW_SRCS)
	$(IVERILOG) -g2012 -DTMM_ASYNC_READ -o $@ $(MMUPT_RMW_SRCS)

# CPU_MMU_24 (MMU TOP SHEET) shadow write STROBE + BUS wiring bench.
# Sheet 29 proves the shadow RAM stores and returns entries; this one takes
# the layer above it - the single WMAP_n strobe (LSHADOW & WRITE & CYD), the
# PTIDB/PPNX transceiver merges onto the PT and PPN buses, and PAL_44306A -
# acting on the real RAM chips. Includes a 256-combination structural sweep
# proving no write strobe can ever coincide with a disabled transceiver
# (the raw-IDB merge question at CPU_MMU_24.v:216).
# TWO BUILDS from one source, same reason as test-mmupt-rmw:
#   plain            - TMM2018D_25 synchronous block RAM, 1-clock read
#   -DTMM_ASYNC_READ - the faithful async SRAM read of the real chip, 0-clock
MMU24_SRCS = CPU_MMU_24_shadow_tb.v $(CIRCUIT)/CPU_MMU_24.v \
             $(CIRCUIT)/CPU_MMU_PT_29.v $(CIRCUIT)/CPU_MMU_CACHE_25.v \
             $(CIRCUIT)/CPU_MMU_CSR_26.v $(CIRCUIT)/CPU_MMU_HIT_27.v \
             $(CIRCUIT)/CPU_MMU_PPNX_28.v $(CIRCUIT)/CPU_MMU_PTIDB_30.v \
             $(PAL)/PAL_44306A.v $(PAL)/PAL_44402D.v $(PAL)/PAL_44402D_EN.v \
             $(MMUPT_SUPPORT)/TMM2018D_25.v $(MMUPT_SUPPORT)/IMS1403_25.v \
             $(MMUPT_SUPPORT)/Am9150.v

test-mmu24-shadow: CPU_MMU_24_shadow_tb_bin CPU_MMU_24_shadow_async_tb_bin
	./CPU_MMU_24_shadow_tb_bin | tee mmu24_shadow_result.tmp
	@grep -q "TB_RESULT: PASS" mmu24_shadow_result.tmp
	./CPU_MMU_24_shadow_async_tb_bin | tee mmu24_shadow_result.tmp
	@grep -q "TB_RESULT: PASS" mmu24_shadow_result.tmp && rm -f mmu24_shadow_result.tmp

CPU_MMU_24_shadow_tb_bin: $(MMU24_SRCS)
	$(IVERILOG) -g2012 -o $@ $(MMU24_SRCS)

CPU_MMU_24_shadow_async_tb_bin: $(MMU24_SRCS)
	$(IVERILOG) -g2012 -DTMM_ASYNC_READ -o $@ $(MMU24_SRCS)

# --- ALL 2048 page-table entries: write, read back, translate -------------
# Sweeps every index (32 page tables x 64 VPNs), both banks, REX and SEX,
# plus a fault-and-fix cycle. The existing shadow benches verify the protocol
# but touch ~30 distinct indexes; this one catches an entry that never lands -
# the PAL_44306A EIPL failure mode, where the STATUS bank looked perfect while
# the PPN map was never written. Two builds, both must pass.
MMU24ALL_SRCS = CPU_MMU_24_allentries_tb.v $(CIRCUIT)/CPU_MMU_24.v \
             $(CIRCUIT)/CPU_MMU_PT_29.v $(CIRCUIT)/CPU_MMU_CACHE_25.v \
             $(CIRCUIT)/CPU_MMU_CSR_26.v $(CIRCUIT)/CPU_MMU_HIT_27.v \
             $(CIRCUIT)/CPU_MMU_PPNX_28.v $(CIRCUIT)/CPU_MMU_PTIDB_30.v \
             $(PAL)/PAL_44306A.v $(PAL)/PAL_44402D.v $(PAL)/PAL_44402D_EN.v \
             $(MMUPT_SUPPORT)/TMM2018D_25.v $(MMUPT_SUPPORT)/IMS1403_25.v \
             $(MMUPT_SUPPORT)/Am9150.v

test-mmu24-allentries: CPU_MMU_24_allentries_tb_bin CPU_MMU_24_allentries_async_tb_bin
	./CPU_MMU_24_allentries_tb_bin | tee mmu24_all_result.tmp
	@grep -q "TB_RESULT: PASS" mmu24_all_result.tmp
	./CPU_MMU_24_allentries_async_tb_bin | tee mmu24_all_result.tmp
	@grep -q "TB_RESULT: PASS" mmu24_all_result.tmp && rm -f mmu24_all_result.tmp

CPU_MMU_24_allentries_tb_bin: $(MMU24ALL_SRCS)
	$(IVERILOG) -g2012 -o $@ $(MMU24ALL_SRCS)

CPU_MMU_24_allentries_async_tb_bin: $(MMU24ALL_SRCS)
	$(IVERILOG) -g2012 -DTMM_ASYNC_READ -o $@ $(MMU24ALL_SRCS)

.PHONY: test-memparity test-memerror test-mmupt-replay test-mmupt test-mmupt-rmw \
        test-mmu24-shadow

# CPU_STOC_35: IDB->CD gate. Exhaustive 2*65536 sweep; STOC_n high must
# drive CD to 0 (FPGA tri-state convention, no Z inside the fabric).
STOC_SRCS = CPU_STOC_35_tb.v $(CIRCUIT)/CPU_STOC_35.v

CPU_STOC_35_tb_bin: $(STOC_SRCS)
	$(IVERILOG) -g2012 -o $@ $(STOC_SRCS)

test-stoc: CPU_STOC_35_tb_bin
	./CPU_STOC_35_tb_bin | tee stoc_result.tmp
	@grep -q "TB_RESULT: PASS" stoc_result.tmp && rm -f stoc_result.tmp

.PHONY: test-stoc

# MEM_RAM_49_DDR2 (Nexys 4 DDR main-memory backend): protocol replay with
# a random-latency behavioral DDR2 port model. Covers hit timing (no hold),
# miss stretch (MEM_HOLD freeze emulated in the driver), write-through
# ordering, the 22-AUG alias map incl. the 64K-word boundary, the absent
# bank, parity regeneration, and 4000 random accesses vs a reference model.
DDR2RAM_SRCS = MEM_RAM_49_DDR2_tb.v ../../../fpga/nexys4ddr/ddr2/MEM_RAM_49_DDR2.v

test-ddr2ram: MEM_RAM_49_DDR2_tb_bin
	./MEM_RAM_49_DDR2_tb_bin | tee ddr2ram_result.tmp
	@grep -q "TB_RESULT: PASS" ddr2ram_result.tmp && rm -f ddr2ram_result.tmp

# nd_ddr2_arb: fairness under a one-client stream, watchdog on a dead
# port (sticky dbg_stuck, grant held, nothing invented), orphan-response
# flag. Teeth: the pre-25-AUG strict-A arbiter fails all three.
test-ddr2arb: ND_DDR2_ARB_tb_bin
	./ND_DDR2_ARB_tb_bin | tee ddr2arb_result.tmp
	@grep -q "TB_RESULT: PASS" ddr2arb_result.tmp && rm -f ddr2arb_result.tmp

ND_DDR2_ARB_tb_bin: ND_DDR2_ARB_tb.v ../../../fpga/nexys4ddr/ddr2/nd_ddr2_arb.v
	$(IVERILOG) -g2012 -o $@ ND_DDR2_ARB_tb.v ../../../fpga/nexys4ddr/ddr2/nd_ddr2_arb.v

MEM_RAM_49_DDR2_tb_bin: $(DDR2RAM_SRCS)
	$(IVERILOG) -g2012 -o $@ $(DDR2RAM_SRCS)

# Chain-level DDR2 freeze gate: the REAL MEM_RAMC_50 PALs (with HOLD) +
# MEM_LBDIF_48 + MEM_ADDR_44 + MEM_RAM_49_DDR2. Reads checked at the real
# RDATA strobe; grant must stay active and RAS/CAS stand still during every
# freeze; BDRY only after the stretched phases; refresh never holds.
CHAINDDR2_SRCS = MEM_CHAIN_DDR2_tb.v $(CIRCUIT)/MEM_RAMC_50.v $(CIRCUIT)/MEM_LBDIF_48.v \
	$(CIRCUIT)/MEM_ADDR_44.v ../../../fpga/nexys4ddr/ddr2/MEM_RAM_49_DDR2.v \
	$(PAL)/PAL_44803A.v $(PAL)/PAL_44902A.v $(PAL)/PAL_44310D.v \
	$(SUPPORT)/AM29C821.v $(SUPPORT)/AM29861A.v

test-memchain-ddr2: MEM_CHAIN_DDR2_tb_bin
	./MEM_CHAIN_DDR2_tb_bin | tee chainddr2_result.tmp
	@grep -q "TB_RESULT: PASS" chainddr2_result.tmp && rm -f chainddr2_result.tmp

MEM_CHAIN_DDR2_tb_bin: $(CHAINDDR2_SRCS)
	$(IVERILOG) -g2012 -o $@ $(CHAINDDR2_SRCS)

# MEM_RAMC_50: RAM arbiter (PAL_44803A) + RAM control state machine
# (PAL_44902A) vs an independent Python model (gen_ramc_golden.py):
# directed grant walks + one-hot invariant + LFSR checksum.
RAMC_SRCS = MEM_RAMC_50_tb.v $(CIRCUIT)/MEM_RAMC_50.v $(PAL)/PAL_44803A.v $(PAL)/PAL_44902A.v

test-ramc: MEM_RAMC_50_tb_bin
	./MEM_RAMC_50_tb_bin | tee ramc_result.tmp
	@grep -q "TB_RESULT: PASS" ramc_result.tmp && rm -f ramc_result.tmp

MEM_RAMC_50_tb_bin: $(RAMC_SRCS)
	$(IVERILOG) -g2012 -o $@ $(RAMC_SRCS)

# MEM_LBDIF_48: AM29C821 delay chains + PAL_44310D. Runs BOTH BDRY
# branches: plain = edge-FF (FPGA), -DUSE_TRANSPARENT_LATCHES = latch
# (original hardware). Per-mode golden tables from gen_lbdif_golden.py.
LBDIF_SRCS = MEM_LBDIF_48_tb.v $(CIRCUIT)/MEM_LBDIF_48.v $(SUPPORT)/AM29C821.v $(PAL)/PAL_44310D.v

test-lbdif: MEM_LBDIF_48_ff_tb_bin MEM_LBDIF_48_lm_tb_bin
	./MEM_LBDIF_48_ff_tb_bin | tee lbdif_result.tmp
	@grep -q "TB_RESULT: PASS" lbdif_result.tmp
	./MEM_LBDIF_48_lm_tb_bin | tee lbdif_result.tmp
	@grep -q "TB_RESULT: PASS" lbdif_result.tmp && rm -f lbdif_result.tmp

MEM_LBDIF_48_ff_tb_bin: $(LBDIF_SRCS)
	$(IVERILOG) -g2012 -o $@ $(LBDIF_SRCS)

MEM_LBDIF_48_lm_tb_bin: $(LBDIF_SRCS)
	$(IVERILOG) -g2012 -DUSE_TRANSPARENT_LATCHES -o $@ $(LBDIF_SRCS)

# IO_PANCAL_40: panel/calendar stub contract (68705 + RTC unimplemented):
# exhaustive {EPANS,FUL_n,VAL} x PA sweep + one-shot 74374 capture pin.
PANCAL_SRCS = IO_PANCAL_40_tb.v $(CIRCUIT)/IO_PANCAL_40.v $(SUPPORT)/TTL_74374.v $(SUPPORT)/TTL_74244.v

test-pancal: IO_PANCAL_40_tb_bin
	./IO_PANCAL_40_tb_bin | tee pancal_result.tmp
	@grep -q "TB_RESULT: PASS" pancal_result.tmp && rm -f pancal_result.tmp

IO_PANCAL_40_tb_bin: $(PANCAL_SRCS)
	$(IVERILOG) -g2012 -o $@ $(PANCAL_SRCS)

# IO_PANCAL_40 + ND120_PANEL_CLOCK: the MC68705/MM58274 clock path
# (PANCAL_68705_CLOCK) driven through a real FIFO_8BIT and the DGA IDBS
# VAL/RIWR handshake - TRR PANC write/read of the 4-byte time, wrap,
# text-command drain, missing-byte recovery, CLEAR_n. Two builds:
# latch mode (FIFO on CLK) and FPGA_FF_MODE (FIFO on sysclk + CLK_EN).
# BOARD_CLK_FREQ=2048000 makes the STAT4 hold 4096 sysclk, the panel
# "second" is 2000 sysclk.
PANCAL_CLOCK_SRCS = IO_PANCAL_40_clock_tb.v $(CIRCUIT)/IO_PANCAL_40.v $(CIRCUIT)/PANCAL_68705_CLOCK.v 	$(SUPPORT)/TTL_74374.v $(SUPPORT)/TTL_74244.v $(SUPPORT)/FIFO_8BIT.v
PANCAL_CLOCK_DEFS = -DND120_PANEL_CLOCK -DBOARD_CLK_FREQ=2048000 -DND120_PANEL_CLOCK_TICK_CYCLES=2000

test-pancal-clock: IO_PANCAL_40_clock_tb_bin
	./IO_PANCAL_40_clock_tb_bin | tee pancal_clock_result.tmp
	@grep -q "TB_RESULT: PASS" pancal_clock_result.tmp && rm -f pancal_clock_result.tmp

test-pancal-clock-ff: IO_PANCAL_40_clock_ff_tb_bin
	./IO_PANCAL_40_clock_ff_tb_bin | tee pancal_clock_ff_result.tmp
	@grep -q "TB_RESULT: PASS" pancal_clock_ff_result.tmp && rm -f pancal_clock_ff_result.tmp

IO_PANCAL_40_clock_tb_bin: $(PANCAL_CLOCK_SRCS)
	$(IVERILOG) -g2012 $(PANCAL_CLOCK_DEFS) -o $@ $(PANCAL_CLOCK_SRCS)

IO_PANCAL_40_clock_ff_tb_bin: $(PANCAL_CLOCK_SRCS)
	$(IVERILOG) -g2012 $(PANCAL_CLOCK_DEFS) -DFPGA_FF_MODE -o $@ $(PANCAL_CLOCK_SRCS)

# CPU_MMU_CACHE_25: cache sheet incl. the 26-JUL HIT-gate on CD_15_0_OUT
# (banner word-2 stale-line fix). Three builds: gated (default), the
# -DND120_CACHE_DRIVE_UNGATED escape hatch (raw schematic drive), and
# -DFPGA_FF_MODE (UCLK_EN capture). The stale-line checks are the teeth:
# an ungated assign in the normal build FAILS them.
MMUCACHE_SRCS = CPU_MMU_CACHE_25_tb.v $(CIRCUIT)/CPU_MMU_CACHE_25.v $(SUPPORT)/TMM2018D_25.v $(SUPPORT)/Am9150.v $(PAL)/PAL_44402D_EN.v $(PAL)/PAL_44402D.v

test-mmucache: CPU_MMU_CACHE_25_tb_bin CPU_MMU_CACHE_25_ug_tb_bin CPU_MMU_CACHE_25_ff_tb_bin
	./CPU_MMU_CACHE_25_tb_bin | tee mmucache_result.tmp
	@grep -q "TB_RESULT: PASS" mmucache_result.tmp
	./CPU_MMU_CACHE_25_ug_tb_bin | tee mmucache_result.tmp
	@grep -q "TB_RESULT: PASS" mmucache_result.tmp
	./CPU_MMU_CACHE_25_ff_tb_bin | tee mmucache_result.tmp
	@grep -q "TB_RESULT: PASS" mmucache_result.tmp && rm -f mmucache_result.tmp

CPU_MMU_CACHE_25_tb_bin: $(MMUCACHE_SRCS)
	$(IVERILOG) -g2012 -o $@ $(MMUCACHE_SRCS)

CPU_MMU_CACHE_25_ug_tb_bin: $(MMUCACHE_SRCS)
	$(IVERILOG) -g2012 -DND120_CACHE_DRIVE_UNGATED -o $@ $(MMUCACHE_SRCS)

CPU_MMU_CACHE_25_ff_tb_bin: $(MMUCACHE_SRCS)
	$(IVERILOG) -g2012 -DFPGA_FF_MODE -o $@ $(MMUCACHE_SRCS)

# CACHE SUBSYSTEM COHERENCE: CACHE_25 + HIT_27 + the CPU_MMU_24 glue, with
# a bench-side memory and DMA master. Real tag/used-bit driven hits: cold
# miss/refill/hit, data-read used bit, CPU write update, FMISS/WCINH/LSHADOW
# refill blocks - plus two DOCUMENTED DEFECTS the bench demonstrates
# (KNOWN-DEFECT lines): DMA writes never invalidate a cached line, and
# CCLR_n does not clear the Am9150 used-bit array (reset is a no-op in the
# model). PASS = behaviour verified WITH the defects present; fixing the
# RTL flips those checks and this bench must then be updated.
MMUCACHE_DMA_SRCS = CPU_MMU_CACHE_DMA_tb.v $(CIRCUIT)/CPU_MMU_CACHE_25.v $(CIRCUIT)/CPU_MMU_HIT_27.v $(SUPPORT)/TMM2018D_25.v $(SUPPORT)/Am9150.v $(PAL)/PAL_44402D_EN.v $(PAL)/PAL_44402D.v $(PAL)/PAL_44511A_EN.v $(PAL)/PAL_44511A.v

test-mmucache-dma: CPU_MMU_CACHE_DMA_tb_bin CPU_MMU_CACHE_DMA_ff_tb_bin
	./CPU_MMU_CACHE_DMA_tb_bin | tee mmucache_dma_result.tmp
	@grep -q "TB_RESULT: PASS" mmucache_dma_result.tmp
	./CPU_MMU_CACHE_DMA_ff_tb_bin | tee mmucache_dma_result.tmp
	@grep -q "TB_RESULT: PASS" mmucache_dma_result.tmp && rm -f mmucache_dma_result.tmp

CPU_MMU_CACHE_DMA_tb_bin: $(MMUCACHE_DMA_SRCS)
	$(IVERILOG) -g2012 -o $@ $(MMUCACHE_DMA_SRCS)

CPU_MMU_CACHE_DMA_ff_tb_bin: $(MMUCACHE_DMA_SRCS)
	$(IVERILOG) -g2012 -DFPGA_FF_MODE -o $@ $(MMUCACHE_DMA_SRCS)

# BIF_BCTL_SYNC_8: two AM29C821 delay-tap registers (25/50/75ns) + PD1/PD3
# comb output kills. The netlist has NO ifdef branches (AM29C821 default
# USE_SYSCLK=0 posedge-CK, as on the board), so ONE build is the complete
# meaningful mode set.
BIFSYNC_SRCS = BIF_BCTL_SYNC_8_tb.v $(CIRCUIT)/BIF_BCTL_SYNC_8.v $(SUPPORT)/AM29C821.v

test-bifsync: BIF_BCTL_SYNC_8_tb_bin
	./BIF_BCTL_SYNC_8_tb_bin | tee bifsync_result.tmp
	@grep -q "TB_RESULT: PASS" bifsync_result.tmp && rm -f bifsync_result.tmp

BIF_BCTL_SYNC_8_tb_bin: $(BIFSYNC_SRCS)
	$(IVERILOG) -g2012 -o $@ $(BIFSYNC_SRCS)

.PHONY: test-bifsync

# BIF_DPATH_LDBCTL_12: the three LBC PALs (44303B/44302B/44304E) incl. the
# sheet-level BACT_n feedback. Both PAL state branches: plain = posedge-OSC
# FF (FPGA), -DUSE_TRANSPARENT_LATCHES = transparent latch (original hw).
LDBCTL_SRCS = BIF_DPATH_LDBCTL_12_tb.v $(CIRCUIT)/BIF_DPATH_LDBCTL_12.v \
              $(PAL)/PAL_44303B.v $(PAL)/PAL_44302B.v $(PAL)/PAL_44304E.v

test-ldbctl: BIF_DPATH_LDBCTL_12_ff_tb_bin BIF_DPATH_LDBCTL_12_lm_tb_bin
	./BIF_DPATH_LDBCTL_12_ff_tb_bin | tee ldbctl_result.tmp
	@grep -q "TB_RESULT: PASS" ldbctl_result.tmp
	./BIF_DPATH_LDBCTL_12_lm_tb_bin | tee ldbctl_result.tmp
	@grep -q "TB_RESULT: PASS" ldbctl_result.tmp && rm -f ldbctl_result.tmp

BIF_DPATH_LDBCTL_12_ff_tb_bin: $(LDBCTL_SRCS)
	$(IVERILOG) -g2012 -o $@ $(LDBCTL_SRCS)

BIF_DPATH_LDBCTL_12_lm_tb_bin: $(LDBCTL_SRCS)
	$(IVERILOG) -g2012 -DUSE_TRANSPARENT_LATCHES -o $@ $(LDBCTL_SRCS)

.PHONY: test-ldbctl

# BIF_DPATH_PESPEA_13: PEA/PES error registers (4x TTL_74534), the sheet in
# the silicon-validated PES/SPEA path (PAGING 11/11). Both strobe branches:
# plain = capture on the strobe's own posedge, -DFPGA_FF_MODE = USE_SYSCLK=2
# sysclk-sampled strobe rise.
PESPEA_SRCS = BIF_DPATH_PESPEA_13_tb.v $(CIRCUIT)/BIF_DPATH_PESPEA_13.v $(SUPPORT)/TTL_74534.v

test-pespea: BIF_DPATH_PESPEA_13_tb_bin BIF_DPATH_PESPEA_13_ff_tb_bin
	./BIF_DPATH_PESPEA_13_tb_bin | tee pespea_result.tmp
	@grep -q "TB_RESULT: PASS" pespea_result.tmp
	./BIF_DPATH_PESPEA_13_ff_tb_bin | tee pespea_result.tmp
	@grep -q "TB_RESULT: PASS" pespea_result.tmp && rm -f pespea_result.tmp

BIF_DPATH_PESPEA_13_tb_bin: $(PESPEA_SRCS)
	$(IVERILOG) -g2012 -o $@ $(PESPEA_SRCS)

BIF_DPATH_PESPEA_13_ff_tb_bin: $(PESPEA_SRCS)
	$(IVERILOG) -g2012 -DFPGA_FF_MODE -o $@ $(PESPEA_SRCS)

.PHONY: test-pespea

# MEM_ADEC_45: the REAL sheet-45 DUT (base PALs 44445B/44446B/44904B +
# D_FLIPFLOP request/grant flags; FF mode swaps in the _D PAL mirrors and
# the sysclk edge-detect flags). Replaces the inline-model-only coverage of
# CPU-BOARD-3202/sim/reqgnt_equiv_tb.v. Both builds, same stimulus/counts.
ADEC_SRCS = MEM_ADEC_45_tb.v $(CIRCUIT)/MEM_ADEC_45.v \
            $(CIRCUIT)/PAL_44445B_D.v $(CIRCUIT)/PAL_44446B_D.v \
            $(PAL)/PAL_44445B.v $(PAL)/PAL_44446B.v $(PAL)/PAL_44904B.v \
            $(LOGISIM)/D_FLIPFLOP.v

test-adec: MEM_ADEC_45_tb_bin MEM_ADEC_45_ff_tb_bin
	./MEM_ADEC_45_tb_bin | tee adec_result.tmp
	@grep -q "TB_RESULT: PASS" adec_result.tmp
	./MEM_ADEC_45_ff_tb_bin | tee adec_result.tmp
	@grep -q "TB_RESULT: PASS" adec_result.tmp && rm -f adec_result.tmp

MEM_ADEC_45_tb_bin: $(ADEC_SRCS)
	$(IVERILOG) -g2012 -o $@ $(ADEC_SRCS)

MEM_ADEC_45_ff_tb_bin: $(ADEC_SRCS)
	$(IVERILOG) -g2012 -DFPGA_FF_MODE -o $@ $(ADEC_SRCS)

.PHONY: test-adec

clean-tier3:
	rm -f MEM_RAMC_50_tb_bin MEM_LBDIF_48_ff_tb_bin MEM_LBDIF_48_lm_tb_bin
	rm -f IO_PANCAL_40_tb_bin CPU_MMU_CACHE_25_tb_bin
	rm -f IO_PANCAL_40_clock_tb_bin IO_PANCAL_40_clock_ff_tb_bin
	rm -f CPU_MMU_CACHE_25_ug_tb_bin CPU_MMU_CACHE_25_ff_tb_bin

.PHONY: test-ramc test-lbdif test-pancal test-pancal-clock test-pancal-clock-ff test-mmucache clean-tier3

# Control-store readback (the TRA CS / TRA 17 path SINTRAN's microcode-revision
# test uses). Isolates the hardware half: RWCS command decode (PAL_44408B),
# the ECSL read window (PAL_44305D), the CS transceiver slice select, and
# writable-control-store storage/readback at defined addresses.
SUPPORT_CS = ../../../Shared/support
CPU_CS_RWCS_tb: CPU_CS_RWCS_tb.v $(CIRCUIT)/CPU_CS_TCV_20.v $(CIRCUIT)/CPU_CS_WCS_21_22.v $(SUPPORT_CS)/IDT6168A_20.v $(PAL)/PAL_44305D.v $(PAL)/PAL_44408B.v
	$(IVERILOG) -g2012 -o $@ $^

test-cs-rwcs: CPU_CS_RWCS_tb
	./CPU_CS_RWCS_tb | tee cs_rwcs_out.log
	@grep -q "TB_RESULT: PASS" cs_rwcs_out.log

# Same readback path, but over a WHOLE RWCS microcycle driven by the real
# cycle state machine (PAL_44601B) and clock PAL (PAL_44307C). Pins the
# deadline the static bench above cannot see: the addressed control-store
# word must still be on the IDB at the TERM edge, because ALUCLK - the only
# clock that writes the A register - fires there and nothing latches the
# word in between.
CPU_CS_RWCS_CYCLE_tb: CPU_CS_RWCS_CYCLE_tb.v $(CIRCUIT)/CPU_CS_16.v \
                      $(CIRCUIT)/CPU_CS_ACAL_17.v $(CIRCUIT)/CPU_CS_CTL_18.v \
                      $(CIRCUIT)/CPU_CS_PROM_19.v $(CIRCUIT)/CPU_CS_TCV_20.v \
                      $(CIRCUIT)/CPU_CS_WCS_21_22.v $(SUPPORT_CS)/IDT6168A_20.v \
                      $(SUPPORT_CS)/TTL_74139.v \
                      $(PAL)/PAL_44305D.v $(PAL)/PAL_44307C.v $(PAL)/PAL_44601B.v
	$(IVERILOG) -g2012 -o $@ $^

test-cs-rwcs-cycle: CPU_CS_RWCS_CYCLE_tb
	./CPU_CS_RWCS_CYCLE_tb | tee cs_rwcs_cycle_out.log
	@grep -q "TB_RESULT: PASS" cs_rwcs_cycle_out.log


# ---------------------------------------------------------------------------
# Sheet 20 CS transceivers: the 74PCT373 capture on ECSL~'s falling edge.
# This capture was MISSING and was the root cause of TRA CS returning 000000.
# Checks 4 and 5 in the tb change the source data under a closed latch, so a
# pass-through implementation fails loudly. See CPU_CS_TCV_20.v.
# ---------------------------------------------------------------------------
CPU_CS_TCV_20_tb: CPU_CS_TCV_20_tb.v $(CIRCUIT)/CPU_CS_TCV_20.v
	$(IVERILOG) -g2012 -o $@ $^

test-cs-tcv: CPU_CS_TCV_20_tb
	./CPU_CS_TCV_20_tb | tee cs_tcv_out.log
	@grep -q "TB_RESULT: PASS" cs_tcv_out.log

# ---------------------------------------------------------------------------
# Microcycle timeline observatory + golden gate.
#
# Walks one microcycle of each kind (NORMAL/SHORT/SLOW/FETCH/FORM/TRAP/RWCS/
# LCS/BRK) through the real PAL_44601B + PAL_44307C + PAL_44305D and prints
# every derived clock and strobe per cycle state. Answers "when does <strobe>
# fire in a <kind> cycle" in a second instead of a full-machine boot.
#
# The timeline is diffed against CPU_CYCLE_TIMELINE.golden, so a clock
# refactor or an edited PAL cannot silently move an edge. If the diff is
# expected, regenerate with `make golden-cycle-timeline` - deliberately, after
# justifying the change against the drawings, never to turn a red test green.
# ---------------------------------------------------------------------------
CPU_CYCLE_TIMELINE_tb: CPU_CYCLE_TIMELINE_tb.v \
                       $(PAL)/PAL_44305D.v $(PAL)/PAL_44307C.v $(PAL)/PAL_44601B.v
	$(IVERILOG) -g2012 -o $@ $^

test-cycle-timeline: CPU_CYCLE_TIMELINE_tb
	@./CPU_CYCLE_TIMELINE_tb > cycle_timeline_out.log 2>&1 || true
	@cat cycle_timeline_out.log
	@grep -vE '^TB_RESULT:|\$$finish called at' cycle_timeline_out.log > cycle_timeline_out.trace
	@if ! diff -u CPU_CYCLE_TIMELINE.golden cycle_timeline_out.trace > cycle_timeline.diff; then \
	    echo ""; \
	    echo "TIMELINE CHANGED - a microcycle edge moved. Diff:"; \
	    cat cycle_timeline.diff; \
	    echo ""; \
	    echo "TB_RESULT: FAIL timeline differs from CPU_CYCLE_TIMELINE.golden"; \
	    exit 1; \
	fi
	@grep -q "TB_RESULT: PASS" cycle_timeline_out.log
	@echo "TB_RESULT: PASS (timeline matches golden)"

golden-cycle-timeline: CPU_CYCLE_TIMELINE_tb
	@./CPU_CYCLE_TIMELINE_tb 2>&1 | grep -v '^TB_RESULT:' > CPU_CYCLE_TIMELINE.golden
	@echo "regenerated CPU_CYCLE_TIMELINE.golden - review the diff before committing"

# ---------------------------------------------------------------------------
# Committed access to a ZERO page-table entry must dispatch the page-fault
# trap (hypothesis H1 of PLAN-zero-read-nonresident-page.md, git 043c460, unit level).
# Wires the REAL chain: cycle PALs (44601B+44307C) + TMM2018D PT status RAM +
# CGA_TRAP_BRKDET + CGA_TRAP_TVGEN(_P2) + CGA_MIC_IPOS, with the board's real
# BRK/TRAP feedback. FETCH/READ/WRITE against PTe=0 must each force
# MA = trap vector 0001 at the mid-cycle MACLK trap-vector strobe; a fully
# resident entry (permits+WIP+PGU set) must not trap. Runs in latch mode and
# FPGA_FF_MODE.
# ---------------------------------------------------------------------------
PGF_SRCS = PGF_COMMITTED_ACCESS_tb.v \
           $(PAL)/PAL_44601B.v $(PAL)/PAL_44307C.v \
           $(SUPPORT)/TMM2018D_25.v \
           ../../../DELILAH-CPU/CGA_TRAP/circuit/CGA_TRAP_BRKDET.v \
           ../../../DELILAH-CPU/CGA_TRAP/circuit/CGA_TRAP_TVGEN.v \
           ../../../DELILAH-CPU/CGA_TRAP/circuit/CGA_TRAP_TVGEN_P2.v \
           ../../../DELILAH-CPU/CGA_MIC/circuit/CGA_MIC_IPOS.v \
           ../../../Shared/logisim/NAND_GATE.v \
           ../../../Shared/logisim/NAND_GATE_3_INPUTS.v \
           ../../../Shared/logisim/NAND_GATE_4_INPUTS.v \
           ../../../Shared/logisim/NAND_GATE_5_INPUTS.v \
           ../../../Shared/logisim/NAND_GATE_6_INPUTS.v \
           ../../../Shared/logisim/AND_GATE.v \
           ../../../Shared/logisim/AND_GATE_3_INPUTS.v \
           ../../../Shared/logisim/AND_GATE_4_INPUTS.v \
           ../../../Shared/logisim/NOR_GATE.v \
           ../../../Shared/logisim/NOR_GATE_3_INPUTS.v \
           ../../../Shared/logisim/OR_GATE_3_INPUTS.v \
           ../../../Shared/logisim/OR_GATE_4_INPUTS.v \
           ../../../Shared/logisim/OR_GATE_5_INPUTS.v \
           ../../../Shared/logisim/OR_GATE_8_INPUTS.v \
           ../../../Shared/logisim/Multiplexer_4.v \
           ../../../Shared/logisim/D_FLIPFLOP.v \
           ../../../Shared/ndlib/A02.v \
           ../../../Shared/ndlib/D_FLIPFLOP_EN.v

PGF_COMMITTED_ACCESS_tb_bin: $(PGF_SRCS)
	$(IVERILOG) -g2012 -o $@ $(PGF_SRCS)

PGF_COMMITTED_ACCESS_ff_tb_bin: $(PGF_SRCS)
	$(IVERILOG) -g2012 -DFPGA_FF_MODE -o $@ $(PGF_SRCS)

test-pgf-committed: PGF_COMMITTED_ACCESS_tb_bin
	./PGF_COMMITTED_ACCESS_tb_bin | tee pgf_committed_out.log
	@grep -q "TB_RESULT: PASS" pgf_committed_out.log

test-pgf-committed-ff: PGF_COMMITTED_ACCESS_ff_tb_bin
	./PGF_COMMITTED_ACCESS_ff_tb_bin | tee pgf_committed_ff_out.log
	@grep -q "TB_RESULT: PASS" pgf_committed_ff_out.log

# ---------------------------------------------------------------------------
# BD -> MEMORY BANK DECODE (24-AUG-2026 regression guard, ND3202D.v:533).
#
# The five bits that select the memory bank were tapped from what the BOARD
# DRIVES onto the bus instead of what the bus CARRIES, so every incoming DMA
# write decoded to BANK0 and SINTRAN's segment load landed one bank below the
# page the MMU resolved. This drives a physical address on the real
# BD_23_0_n_IN port and reads the decode tap through a hierarchical reference,
# so the WIRING is checked rather than a copy of the expression.
#
# It elaborates the whole board, so it needs the same -y library set and the
# SDRAM backend defines the Tang build uses. Verified 24-AUG-2026 to FAIL
# (4 of 5 checks) against the old line and PASS against the fix.
#
# This CANNOT be a Verilator boot test: MEM_RAM_49_SIM.v provides all three
# banks, so a misdirected bank still finds memory and the boot succeeds.
BDBANK_DEFS = -DMAIN_RAM_SDRAM -DND_SDRAM_PACK16
BDBANK_LIBS = -y $(CIRCUIT) \
              -y ../../../DELILAH-CPU/CGA/circuit \
              -y ../../../DELILAH-CPU/CGA_ALU/circuit \
              -y ../../../DELILAH-CPU/CGA_DCD/circuit \
              -y ../../../DELILAH-CPU/CGA_IDBCTL/circuit \
              -y ../../../DELILAH-CPU/CGA_INTR/circuit \
              -y ../../../DELILAH-CPU/CGA_MAC/circuit \
              -y ../../../DELILAH-CPU/CGA_MIC/circuit \
              -y ../../../DELILAH-CPU/CGA_TESTMUX/circuit \
              -y ../../../DELILAH-CPU/CGA_TRAP/circuit \
              -y ../../../DELILAH-CPU/CGA_WRF/circuit \
              -y ../../../DECODE-GateArray/DGA/circuit \
              -y $(PAL) \
              -y ../../../Shared/logisim \
              -y ../../../Shared/ndlib \
              -y ../../../Shared/support \
              -y ../../../fpga/tang-nano-20k/sdram-bridge \
              -I ../../../Shared/support -I ../../../SD-FAT/circuit

BD_BANK_DECODE_tb.vvp: BD_BANK_DECODE_tb.v $(CIRCUIT)/ND3202D.v
	$(IVERILOG) -g2012 $(BDBANK_DEFS) $(BDBANK_LIBS) -o $@ BD_BANK_DECODE_tb.v

test-bdbank: BD_BANK_DECODE_tb.vvp
	vvp $< | tee bdbank_out.log
	@grep -q "TB_RESULT: PASS" bdbank_out.log

# ---------------------------------------------------------------------------
# CPU_MMU_PPNX_28: the PPN <-> IDB transceivers of sheet 28 - 10B (IDB15..8 /
# PPN25..18, /G = EIPU_n), 9B (IDB7..0 / PPN17..10, /G = EIPL_n), shared
# DIR = ESTOF_n, plus 8B (74LS244, /G = EIPUR_n) forcing PPN25..19 to 0 and
# passing IDB8 to PPN18. The bench asserts what the drawing shows: two
# INDEPENDENT byte enables, one direction, and a disabled driver that puts 0
# on the bus (the house no-z convention, see Shared/support/TTL_74245.v).
#
# HISTORY: when written this bench failed 570 of its 784 checks. The sheet's
# IDB and PPN outputs carried no enable term at all and defaulted to a copy of
# the corresponding input, so the sheet drove both buses on every cycle -
# including the ones where DIR pointed the other way. The output assignments
# are now gated per byte from the drawing, and the bench is green and
# registered.
#
# Run:  make test-mmuppnx
# ---------------------------------------------------------------------------
MMUPPNX_SRCS = CPU_MMU_PPNX_28_tb.v $(CIRCUIT)/CPU_MMU_PPNX_28.v

CPU_MMU_PPNX_28_tb_bin: $(MMUPPNX_SRCS)
	$(IVERILOG) -g2012 -o $@ $(MMUPPNX_SRCS)

test-mmuppnx: CPU_MMU_PPNX_28_tb_bin
	./CPU_MMU_PPNX_28_tb_bin | tee mmuppnx_result.tmp
	@grep -q "TB_RESULT: PASS" mmuppnx_result.tmp && rm -f mmuppnx_result.tmp

.PHONY: test-mmuppnx

# ---------------------------------------------------------------------------
# test-mmucache-nocache - the -DND120_NO_CACHE contract.
#
# The Tang Nano 20K cannot hold this design with the cache present once the
# hit comparator on sheets 27/24 is correct (before the fix it compared six
# wrong bits against a signal that is zero on every mapped access, so the
# synthesiser deleted most of the cache path as dead logic). ND120_NO_CACHE
# omits the five cache memories and the used-bit PAL, forces the board's real
# SW1 cache-off position, and must therefore REPORT the cache as disabled.
#
# The normal test-mmucache builds necessarily FAIL against a build with no
# cache in it - that is a different machine, not a regression - so the
# cache-off contract gets its own bench.
# ---------------------------------------------------------------------------
MMUCACHE_NC_SRCS = CPU_MMU_CACHE_25_nocache_tb.v $(CIRCUIT)/CPU_MMU_CACHE_25.v \
                   $(SUPPORT)/TMM2018D_25.v $(SUPPORT)/Am9150.v \
                   $(PAL)/PAL_44402D_EN.v $(PAL)/PAL_44402D.v

CPU_MMU_CACHE_25_nocache_tb_bin: $(MMUCACHE_NC_SRCS)
	$(IVERILOG) -g2012 -DND120_NO_CACHE -o $@ $(MMUCACHE_NC_SRCS)

test-mmucache-nocache: CPU_MMU_CACHE_25_nocache_tb_bin
	./CPU_MMU_CACHE_25_nocache_tb_bin | tee mmucache_nc_result.tmp
	@grep -q "TB_RESULT: PASS" mmucache_nc_result.tmp && rm -f mmucache_nc_result.tmp

.PHONY: test-mmucache-nocache

# test-pt-stale: PT status RAM (TMM2018D sync BRAM) wired to the real
# trap-vector generator. Registered 27-AUG-2026 as a CONTRACT-PINNING
# regression (was the ERRFATAL-era stale-read demo): lead=0 access sees the
# STALE entry (TVEC 3) by construction - that is WHY the trap is consumed at
# the mid-cycle MACLK strobe - and one sysclk of lead suffices (TVEC 1).
PTSTALE_SRCS = PT_stale_read_tvec_tb.v \
               ../../../DELILAH-CPU/CGA_TRAP/circuit/CGA_TRAP_TVGEN.v \
               ../../../Shared/support/TMM2018D_25.v
PT_stale_read_tvec_tb_bin: $(PTSTALE_SRCS)
	$(IVERILOG) -g2012 -y ../../../Shared/logisim -y ../../../Shared/ndlib \
	  -y ../../../Shared/support -y ../../../DELILAH-CPU/CGA_TRAP/circuit \
	  -o $@ $(PTSTALE_SRCS)
test-pt-stale: PT_stale_read_tvec_tb_bin
	vvp PT_stale_read_tvec_tb_bin | tee pt_stale_out.log
	@grep -q "TB_RESULT: PASS" pt_stale_out.log
.PHONY: test-pt-stale

# test-cycstretch: CYCFSM strobe contract under a stretched memory grant.
# Rewritten 27-AUG-2026 as a CONTRACT-PINNING regression (the old bench's 41
# "failures" were its own artifacts - inverted CYD/UCLK polarity, a count
# window that grew with the stretch, WAIT1/WAIT2 tied 0 which bypasses the
# wait states, and no TERM anchor). Pinned: a delayed grant stretches state d,
# a held grant stretches state e; CYD (HIGH, d..f) and EORF (LOW, d) ELONGATE
# with the stretch but every strobe rises exactly ONCE per machine cycle -
# the single-edge invariant is the corruption-relevant property, measured
# harmless on silicon 27-AUG (overlap probe 0/0, trap never fired).
CYC_STRETCH_STROBES_tb_bin: CYC_STRETCH_STROBES_tb.v $(PAL)/PAL_44601B.v $(PAL)/PAL_44307C.v
	$(IVERILOG) -g2012 -o $@ CYC_STRETCH_STROBES_tb.v $(PAL)/PAL_44601B.v $(PAL)/PAL_44307C.v
test-cycstretch: CYC_STRETCH_STROBES_tb_bin
	./CYC_STRETCH_STROBES_tb_bin | tee cycstretch_out.log
	@grep -q "TB_RESULT: PASS" cycstretch_out.log
.PHONY: test-cycstretch
