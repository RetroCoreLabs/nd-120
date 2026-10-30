# Unit testbenches for the ND Winchester disc controller, 5 1/4 inch ST506
# (card 3041) and 8 inch (card 3038).
# (repo convention: sim/ next to the modules it tests)
#
# test-wd-iox - the IOX register / status / IDENT conformance matrix asserted
#   directly at the device IOX slave port (no BUS_SLAVE, no DMA backend):
#   the two-access memory address with its deliberately opposite read order,
#   ALL FOUR flip-flop reset conditions, the SINGLE-access word count that
#   distinguishes this card from the 15 MHz SMD, the block-address split,
#   the status constants, M4's relative step seek, M7, the address-mismatch
#   bound, and the section 4.1 interrupt / IDENT probe that TPE CONFIGURATION
#   uses to find the card.
#
# The same behaviour is cross-checked between the two C implementations
# (nd100x tests/wd_trace.c and the portable core's test/wd_trace.c walking a
# shared conformance sequence), so a divergence between RTL and C shows up
# here rather than on silicon.

# Shared include paths (Verilog/mk/iverilog.mk). Provides $(ND_INC),
# which covers SD-FAT/circuit - the controllers include
# nd_storage_status.vh from there.
VERILOG_ROOT = ../../..
include $(VERILOG_ROOT)/mk/iverilog.mk


IOX_SRCS = ../circuit/ND_WINCHESTER.v \
           nd_winchester_iox_tb.v

# test-wd-adapter: the Winchester BINDING of nd_storage_disc_adapter. There is
#   no nd_storage_wd_adapter.v: that adapter has nothing SMD-specific in it -
#   its CHS->LBA is driven by GEO_HEADS/GEO_SPT and its one hard assumption
#   (1024-byte sectors) holds for this card too. This bench proves the reuse
#   with Winchester geometry, and closes a real hole: the adapter's own bench
#   instantiates it twice and both times at the DEFAULT geometry, so the
#   parameterisation was never exercised.
AD_SRCS  = ../../../SD-FAT/circuit/nd_storage_disc_adapter.v \
           nd_winchester_adapter_tb.v

# test-wd-oracle: replay of the nd100x C model's own IOX trace for the
#   DISC-TEMA J02 "DU-DI-C" read that failed on silicon 05-AUG-2026. Holds
#   each IOX strobe for MANY card clocks, which is what the ND bus does and
#   what a 1-clock strobe hides, and requires iox_rdata to stay stable for
#   the whole access. Caught the level-vs-edge strobe bug in ND_WINCHESTER.v.
OR_SRCS  = ../circuit/ND_WINCHESTER.v \
           nd_winchester_oracle_tb.v

# RTZ observability: the guest must be able to SEE an operation running, not
# just see it finished. The oracle bench cannot catch this - it polls with
# zero latency and never exercises the M7 RTZ path.
RTZ_SRCS = ../circuit/ND_WINCHESTER.v \
           nd_winchester_rtz_tb.v

# test-wd-compare: M3 compare. The card reads the sector, DMA-reads the same
#   words back OUT of ND memory, compares them, and leaves the memory address
#   register ADVANCED by the word count. M3 used to share the do-nothing stub
#   with M2 and M5, which left that register where the guest had loaded it -
#   and SINTRAN reads it back after every operation.
CMP_SRCS = ../circuit/ND_WINCHESTER.v \
           nd_winchester_compare_tb.v

# test-wd-bus: the card behind the REAL ND_BUS_SLAVE. Every other bench
#   drives iox_rd/iox_wr directly, so the adapter that generates those
#   strobes on the board was never in the loop - and +0 is precisely the
#   register whose value depends on HOW MANY times the strobe fires.
BUS_SRCS = ../circuit/ND_WINCHESTER.v \
           ../../BUS-IF/circuit/ND_BUS_SLAVE.v \
           nd_winchester_bus_tb.v

# test-wd-storage: the WHOLE chain - ND_WINCHESTER -> nd_storage_disc_adapter
#   (client 6, Winchester geometry) -> nd_storage (mount + engine + Phase-4
#   cache) -> the behavioral SD card serving the real FAT16 image. Every
#   other Winchester bench fakes the backend, so the path from "the guest set
#   GO" to "bytes off the FAT volume" was never simulated - which is exactly
#   how a backend that answers done+no-error with a ZERO block stayed
#   invisible until it showed up on silicon (08-AUG-2026). Needs the shared
#   card image from ../../../SD-FAT/sim (make_storage_image.sh), which
#   carries WD0.IMG.
WD_STOR_COMMON = ../../../SD-FAT/circuit/nd_storage_devices.v \
                 ../../../SD-FAT/circuit/nds_sync.v \
                 ../../../SD-FAT/circuit/nd_storage_engine.v \
                 ../../../SD-FAT/circuit/nd_storage_mount.v \
                 ../../../SD-FAT/circuit/nd_storage_cache.v \
                 ../../../SD-FAT/circuit/nd_storage_fatchk.v \
                 ../../../SD-FAT/circuit/nd_storage.v \
                 ../../../SD-FAT/circuit/nd_storage_tape_adapter.v \
                 ../../../SD-FAT/circuit/nd_storage_floppy_adapter.v \
                 ../../../SD-FAT/circuit/nd_storage_disc_adapter.v \
                 ../../../SD-FAT/circuit/sd_file_reader.v \
                 ../../../SD-FAT/circuit/sd_writer.v \
                 ../../../SD-FAT/sim/nds_mem_model.v \
                 ../../../SD-FAT/sim/sd_card_model.v

STOR_SRCS = ../circuit/ND_WINCHESTER.v \
            ../../../SD-FAT/circuit/nd_storage_devices.v \
            ../../../SD-FAT/circuit/nds_sync.v \
            ../../../SD-FAT/circuit/nd_storage_engine.v \
            ../../../SD-FAT/circuit/nd_storage_mount.v \
            ../../../SD-FAT/circuit/nd_storage_cache.v \
            ../../../SD-FAT/circuit/nd_storage_fatchk.v \
            ../../../SD-FAT/circuit/nd_storage.v \
            ../../../SD-FAT/circuit/nd_storage_tape_adapter.v \
            ../../../SD-FAT/circuit/nd_storage_floppy_adapter.v \
            ../../../SD-FAT/circuit/nd_storage_disc_adapter.v \
            ../../../SD-FAT/circuit/sd_file_reader.v \
            ../../../SD-FAT/circuit/sd_writer.v \
            ../../../SD-FAT/sim/nds_mem_model.v \
            ../../../SD-FAT/sim/sd_card_model.v \
            nd_winchester_storage_tb.v

all: test

test: test-wd-iox test-wd-adapter test-wd-oracle test-wd-bus test-wd-storage \
      test-wd-wcsweep test-wd-dmapath \
      test-wd-storage-uncached test-wd-storage-sdram test-wd-rtz test-wd-decode \
      test-wd-compare test-wd-timing test-wd-format

nd_winchester_storage_tb.vvp: $(STOR_SRCS)
	$(IVERILOG) -g2005 $(ND_INC) -o $@ $(STOR_SRCS)

../../../SD-FAT/sim/nds_storage.img:
	../../../SD-FAT/sim/make_storage_image.sh

test-wd-storage: nd_winchester_storage_tb.vvp ../../../SD-FAT/sim/nds_storage.img
	$(VVP) nd_winchester_storage_tb.vvp | tee wd_storage_out.log
	@grep -q "TB_RESULT: PASS" wd_storage_out.log

# test-wd-storage-uncached: the SAME bench with the disc clients DIRECT
#   instead of cached (ND_STORAGE_DISCS_UNCACHED forces CACHE_MASK to 0).
#   Cached and direct take DIFFERENT paths through the engine - a cached
#   client goes through C_LOOK's tag lookup, a direct one jumps straight to
#   C_SEC_GO - and the read-modify-write for sub-block writes has to be right
#   on both. Running only the default build proves one of the two.
nd_winchester_storage_uncached_tb.vvp: $(STOR_SRCS)
	$(IVERILOG) -g2005 -DND_STORAGE_DISCS_UNCACHED $(ND_INC) -o $@ $(STOR_SRCS)

test-wd-storage-uncached: nd_winchester_storage_uncached_tb.vvp ../../../SD-FAT/sim/nds_storage.img
	$(VVP) nd_winchester_storage_uncached_tb.vvp | tee wd_storage_uncached_out.log
	@grep -q "TB_RESULT: PASS" wd_storage_uncached_out.log

.PHONY: test-wd-storage-uncached

# test-wd-storage-sdram: the SAME bench with the region served by the REAL
#   MEM_RAM_49_SDRAM (ND_SDRAM_PACK16 + ND_STORAGE_PORT) and the behavioral
#   SDRAM chip, instead of nds_mem_model. nd_storage and MEM_RAM_49_SDRAM
#   each had a passing bench but had never been COMPOSED - nd_storage's
#   benches all use nds_mem_model and the bridge's bench drives the device
#   port from a synthetic task - so a disagreement between the two mem-port
#   contracts would pass both and lose the data on the board.
SDRAM_STOR_SRCS = $(STOR_SRCS) \
                  ../../../fpga/tang-nano-20k/sdram-bridge/MEM_RAM_49_SDRAM.v \
                  ../../../fpga/tang-nano-20k/sdram-bridge/sdram18.v \
                  ../../../fpga/tang-nano-20k/sdram-test/sim/sdram_model.v

nd_winchester_storage_sdram_tb.vvp: $(SDRAM_STOR_SRCS)
	$(IVERILOG) -g2005 -DWD_TB_REAL_SDRAM -DND_SDRAM_PACK16 -DND_STORAGE_PORT \
	  $(ND_INC) -o $@ $(SDRAM_STOR_SRCS)

test-wd-storage-sdram: nd_winchester_storage_sdram_tb.vvp ../../../SD-FAT/sim/nds_storage.img
	$(VVP) nd_winchester_storage_sdram_tb.vvp | tee wd_storage_sdram_out.log
	@grep -q "TB_RESULT: PASS" wd_storage_sdram_out.log

nd_winchester_iox_tb.vvp: $(IOX_SRCS)
	$(IVERILOG) -g2005 $(ND_INC) -o $@ $(IOX_SRCS)

test-wd-iox: nd_winchester_iox_tb.vvp
	$(VVP) nd_winchester_iox_tb.vvp | tee wd_iox_out.log
	@grep -q "TB_RESULT: PASS" wd_iox_out.log

nd_winchester_adapter_tb.vvp: $(AD_SRCS)
	$(IVERILOG) -g2005 $(ND_INC) -o $@ $(AD_SRCS)

test-wd-adapter: nd_winchester_adapter_tb.vvp
	$(VVP) nd_winchester_adapter_tb.vvp | tee wd_adapter_out.log
	@grep -q "TB_RESULT: PASS" wd_adapter_out.log

clean:
	rm -f *.vvp *.log *.vcd *.fst

.PHONY: all test test-wd-iox test-wd-adapter clean

nd_winchester_oracle_tb.vvp: $(OR_SRCS)
	$(IVERILOG) -g2005 $(ND_INC) -o $@ $(OR_SRCS)

test-wd-oracle: nd_winchester_oracle_tb.vvp
	$(VVP) nd_winchester_oracle_tb.vvp | tee wd_oracle_out.log
	@grep -q "TB_RESULT: PASS" wd_oracle_out.log

.PHONY: test-wd-oracle

nd_winchester_rtz_tb.vvp: $(RTZ_SRCS)
	$(IVERILOG) -g2005 $(ND_INC) -o $@ $(RTZ_SRCS)

test-wd-rtz: nd_winchester_rtz_tb.vvp
	$(VVP) nd_winchester_rtz_tb.vvp | tee wd_rtz_out.log
	@grep -q "TB_RESULT: PASS" wd_rtz_out.log

.PHONY: test-wd-rtz

# test-wd-timing: real drive timing (FAST = 0). Seeks along the Micropolis
#   curve and transfers that end as their last sector passes the head, checked
#   against nd100x's own formulas (wd_seek_ticks, wd_transfer_ticks).
TIM_SRCS = ../circuit/ND_WINCHESTER.v \
           nd_winchester_timing_tb.v

nd_winchester_timing_tb.vvp: $(TIM_SRCS)
	$(IVERILOG) -g2005 $(ND_INC) -o $@ $(TIM_SRCS)

test-wd-timing: nd_winchester_timing_tb.vvp
	$(VVP) nd_winchester_timing_tb.vvp | tee wd_timing_out.log
	@grep -q "TB_RESULT: PASS" wd_timing_out.log

.PHONY: test-wd-timing

nd_winchester_compare_tb.vvp: $(CMP_SRCS)
	$(IVERILOG) -g2005 $(ND_INC) -o $@ $(CMP_SRCS)

test-wd-compare: nd_winchester_compare_tb.vvp
	$(VVP) nd_winchester_compare_tb.vvp | tee wd_compare_out.log
	@grep -q "TB_RESULT: PASS" wd_compare_out.log

.PHONY: test-wd-compare

# test-wd-format: Write Format (M5) data side, against nd100x
#   WD_OP_WRITE_FORMAT - the address fields DMA-read two words per sector
#   (at most one track), the memory address and word count moved on by them,
#   the out-of-drive address mismatch that ends later, and a failed field
#   read. The fields are not kept (nd100x BUGS.md W2; Verilog/TODO.md).
FMT_SRCS = ../circuit/ND_WINCHESTER.v \
           nd_winchester_format_tb.v

nd_winchester_format_tb.vvp: $(FMT_SRCS)
	$(IVERILOG) -g2005 $(ND_INC) -o $@ $(FMT_SRCS)

test-wd-format: nd_winchester_format_tb.vvp
	$(VVP) nd_winchester_format_tb.vvp | tee wd_format_out.log
	@grep -q "TB_RESULT: PASS" wd_format_out.log

.PHONY: test-wd-format

nd_winchester_bus_tb.vvp: $(BUS_SRCS)
	$(IVERILOG) -g2005 $(ND_INC) -o $@ $(BUS_SRCS)

test-wd-bus: nd_winchester_bus_tb.vvp
	$(VVP) nd_winchester_bus_tb.vvp | tee wd_bus_out.log
	@grep -q "TB_RESULT: PASS" wd_bus_out.log

.PHONY: test-wd-bus

# test-wd-wcsweep: word counts around every 1024-word boundary. 4608 (the
#   SINTRAN boot's count) is 4.5 sectors, and the chunk arithmetic truncates a
#   24-bit counter to 11 bits, so a remaining count of 1025 could ask for a
#   ZERO-word chunk. Backend always completes, so any failure here is the
#   controller's own arithmetic.
nd_winchester_wcsweep_tb.vvp: nd_winchester_wcsweep_tb.v ../circuit/ND_WINCHESTER.v
	$(IVERILOG) -g2005 $(ND_INC) -I../circuit -o $@ $^

test-wd-wcsweep: nd_winchester_wcsweep_tb.vvp
	$(VVP) nd_winchester_wcsweep_tb.vvp | tee wd_wcsweep_out.log
	@grep -q "TB_RESULT: PASS" wd_wcsweep_out.log

.PHONY: test-wd-wcsweep

# test-wd-dmapath: the ONLY Winchester bench with a REAL DMA path. Every other
#   one answers dma_req with dma_ack on the next clock and ties dma_busy to 0,
#   so ND_DMA_MASTER - which arbitrates for the ND-100 bus - was never
#   exercised with this card. Here the card drives the real master against a
#   BCU + memory model implementing BREQ/BAPR/BDAP/BDRY, with the real SD card
#   and SDRAM behind it.
DMAPATH_SRCS = ../circuit/ND_WINCHESTER.v \
               ../../DMA/circuit/ND_DMA_MASTER.v \
               $(WD_STOR_COMMON) \
               nd_winchester_dmapath_tb.v

nd_winchester_dmapath_tb.vvp: $(DMAPATH_SRCS)
	$(IVERILOG) -g2005 $(ND_INC) -I../circuit -o $@ $(DMAPATH_SRCS)

test-wd-dmapath: nd_winchester_dmapath_tb.vvp ../../../SD-FAT/sim/nds_storage.img
	$(VVP) nd_winchester_dmapath_tb.vvp | tee wd_dmapath_out.log
	@grep -q "TB_RESULT: PASS" wd_dmapath_out.log

.PHONY: test-wd-dmapath

# test-wd-decode: pure WIRING bench, complementary to test-wd-iox. All 65536
#   iox_addr values swept with the clock stopped (iox_sel must be 1 for
#   exactly o500..o507, and every foreign address must read 0 - the OR-bus
#   rule), the full read-mux offset map, and the IDENT daisy-chain over all
#   16 levels x grant_in x pending. ident_grant_out is not referenced by any
#   other Winchester bench, yet it is what lets the floppy (also level 11,
#   ident 021) ever be identified. A second DUT with IS_3038=1 covers the
#   card-identity strap on status b13. ND_WINCHESTER.v has no FPGA_FF_MODE
#   ifdef; the second build only proves the define changes nothing.
DEC_SRCS = ../circuit/ND_WINCHESTER.v \
           nd_winchester_decode_tb.v

nd_winchester_decode_tb.vvp: $(DEC_SRCS)
	$(IVERILOG) -g2012 $(ND_INC) -o $@ $(DEC_SRCS)

nd_winchester_decode_ff_tb.vvp: $(DEC_SRCS)
	$(IVERILOG) -g2012 -DFPGA_FF_MODE $(ND_INC) -o $@ $(DEC_SRCS)

test-wd-decode: nd_winchester_decode_tb.vvp nd_winchester_decode_ff_tb.vvp
	$(VVP) nd_winchester_decode_tb.vvp | tee wd_decode_out.log
	@grep -q "TB_RESULT: PASS" wd_decode_out.log
	$(VVP) nd_winchester_decode_ff_tb.vvp | tee wd_decode_ff_out.log
	@grep -q "TB_RESULT: PASS" wd_decode_ff_out.log

.PHONY: test-wd-decode

# Registered 27-AUG-2026 (orphans from the 18-AUG boot-hang campaign):
# test-wd-boothang - exact replay of the SINTRAN boot poll pattern that hung
#   (op 11, 060005 forever); self-checking, PASSES since the fix.
# test-wd-ticks - tick-cost instrumentation copy of the dmapath bench
#   (real ND_DMA_MASTER + full storage stack + card image).
BOOTHANG_SRCS = ../circuit/ND_WINCHESTER.v nd_winchester_boot_hang_tb.v
nd_winchester_boot_hang_tb.vvp: $(BOOTHANG_SRCS)
	$(IVERILOG) -g2012 $(ND_INC) -o $@ $(BOOTHANG_SRCS)
test-wd-boothang: nd_winchester_boot_hang_tb.vvp
	$(VVP) nd_winchester_boot_hang_tb.vvp | tee wd_boothang_out.log
	@grep -q "TB_RESULT: PASS" wd_boothang_out.log

WDTICKS_SRCS = ../circuit/ND_WINCHESTER.v \
               ../../DMA/circuit/ND_DMA_MASTER.v \
               $(WD_STOR_COMMON) \
               nd_winchester_ticks_tb.v
nd_winchester_ticks_tb.vvp: $(WDTICKS_SRCS)
	$(IVERILOG) -g2005 $(ND_INC) -I../circuit -o $@ $(WDTICKS_SRCS)
test-wd-ticks: nd_winchester_ticks_tb.vvp ../../../SD-FAT/sim/nds_storage.img
	$(VVP) nd_winchester_ticks_tb.vvp | tee wd_ticks_out.log
	@grep -q "TB_RESULT: PASS" wd_ticks_out.log
.PHONY: test-wd-boothang test-wd-ticks

# test-wd-fix: seven behaviours found by reading the RTL against the nd100x
#   oracle and ND-11.015.01 - range check on the head of the GO word, no
#   interrupt while active, test mode still range-checks, unit/head latched
#   at activation, device clear with an owed backend done, a zero-step seek's
#   delay, and the return-to-zero violation bit (b5). Each case fails on the
#   RTL as it was before the fixes.
FIX_SRCS = ../circuit/ND_WINCHESTER.v \
           nd_winchester_fix_tb.v

nd_winchester_fix_tb.vvp: $(FIX_SRCS)
	$(IVERILOG) -g2005 $(ND_INC) -o $@ $(FIX_SRCS)

test-wd-fix: nd_winchester_fix_tb.vvp
	$(VVP) nd_winchester_fix_tb.vvp | tee wd_fix_out.log
	@grep -q "TB_RESULT: PASS" wd_fix_out.log
.PHONY: test-wd-fix
