# PAL testbenches — Icarus Verilog
IVERILOG = iverilog
VERILOG_ROOT = ../..

PAL_44304E_tb: PAL_44304E_tb.v $(VERILOG_ROOT)/PAL/PAL_44304E.v
	$(IVERILOG) -g2012 -I$(VERILOG_ROOT)/Shared/logisim -I$(VERILOG_ROOT)/Shared/ndlib -I$(VERILOG_ROOT)/Shared/support -I$(VERILOG_ROOT)/PAL -o $@ $^

PAL_45008B_tb: PAL_45008B_tb.v $(VERILOG_ROOT)/PAL/PAL_45008B.v
	$(IVERILOG) -g2012 -I$(VERILOG_ROOT)/Shared/logisim -I$(VERILOG_ROOT)/Shared/ndlib -I$(VERILOG_ROOT)/Shared/support -I$(VERILOG_ROOT)/PAL -o $@ $^

PAL_44601B_tb: PAL_44601B_tb.v $(VERILOG_ROOT)/PAL/PAL_44601B.v
	$(IVERILOG) -g2012 -I$(VERILOG_ROOT)/Shared/logisim -I$(VERILOG_ROOT)/Shared/ndlib -I$(VERILOG_ROOT)/Shared/support -I$(VERILOG_ROOT)/PAL -o $@ $^

# PAL_44801A - the ND-100 bus arbiter (BARB). The CPU/DMA mutual-exclusion
# interlock that makes the bus "not interruptible" once allocated.
PAL_44801A_tb: PAL_44801A_tb.v $(VERILOG_ROOT)/PAL/PAL_44801A.v
	$(IVERILOG) -g2012 -I$(VERILOG_ROOT)/Shared/logisim -I$(VERILOG_ROOT)/Shared/ndlib -I$(VERILOG_ROOT)/Shared/support -I$(VERILOG_ROOT)/PAL -o $@ $^

# PAL_44306A - MMU control (21G, MMUCTL). Exhaustive 1024-vector sweep of all
# 10 inputs against a golden re-derived from the PALASM listing, plus named
# checks that pin the EIPL/EIPU asymmetry (EIPL's third term must NOT carry
# DOUBLE - the 29-JUL-2026 bug that left the PPN map RAM unwritten in REX
# mode, so every paged access ran in physical page 0).
PAL_44306A_SRCS = PAL_44306A_tb.v $(VERILOG_ROOT)/PAL/PAL_44306A.v

PAL_44306A_tb_bin: $(PAL_44306A_SRCS)
	$(IVERILOG) -g2012 -o $@ $(PAL_44306A_SRCS)

# Teeth build: corrupts the golden EIPL bit, so this binary MUST report FAIL.
PAL_44306A_teeth_tb_bin: $(PAL_44306A_SRCS)
	$(IVERILOG) -g2012 -DTEETH_TEST -o $@ $(PAL_44306A_SRCS)

test-pal44306a: PAL_44306A_tb_bin
	./PAL_44306A_tb_bin | tee pal44306a_result.tmp
	@grep -q "TB_RESULT: PASS" pal44306a_result.tmp && rm -f pal44306a_result.tmp

# PAL_44401B - bus cycle timing (BTIM). Generates EIOD (-> BIOXE), gated by
# CACT: the IOX strobe cannot fire unless the CPU is active on the bus.
PAL_44401B_tb: PAL_44401B_tb.v $(VERILOG_ROOT)/PAL/PAL_44401B.v
	$(IVERILOG) -g2012 -I$(VERILOG_ROOT)/Shared/logisim -I$(VERILOG_ROOT)/Shared/ndlib -I$(VERILOG_ROOT)/Shared/support -I$(VERILOG_ROOT)/PAL -o $@ $^

# _EN clock-enable equivalence testbenches: original PAL (posedge CLK on a
# registered level) vs PAL_xxx_EN USE_ENABLE=1 (posedge sysclk + enable),
# all outputs compared every cycle. FF_EN_equiv_tb pattern.
PAL_44402D_EN_equiv_tb: PAL_44402D_EN_equiv_tb.v $(VERILOG_ROOT)/PAL/PAL_44402D_EN.v $(VERILOG_ROOT)/PAL/PAL_44402D.v
	$(IVERILOG) -g2012 -I$(VERILOG_ROOT)/Shared/logisim -I$(VERILOG_ROOT)/Shared/ndlib -I$(VERILOG_ROOT)/Shared/support -I$(VERILOG_ROOT)/PAL -o $@ $^

PAL_44403C_EN_equiv_tb: PAL_44403C_EN_equiv_tb.v $(VERILOG_ROOT)/PAL/PAL_44403C_EN.v $(VERILOG_ROOT)/PAL/PAL_44403C.v
	$(IVERILOG) -g2012 -I$(VERILOG_ROOT)/Shared/logisim -I$(VERILOG_ROOT)/Shared/ndlib -I$(VERILOG_ROOT)/Shared/support -I$(VERILOG_ROOT)/PAL -o $@ $^

PAL_44404C_EN_equiv_tb: PAL_44404C_EN_equiv_tb.v $(VERILOG_ROOT)/PAL/PAL_44404C_EN.v $(VERILOG_ROOT)/PAL/PAL_44404C.v
	$(IVERILOG) -g2012 -I$(VERILOG_ROOT)/Shared/logisim -I$(VERILOG_ROOT)/Shared/ndlib -I$(VERILOG_ROOT)/Shared/support -I$(VERILOG_ROOT)/PAL -o $@ $^

PAL_44407A_EN_equiv_tb: PAL_44407A_EN_equiv_tb.v $(VERILOG_ROOT)/PAL/PAL_44407A_EN.v $(VERILOG_ROOT)/PAL/PAL_44407A.v
	$(IVERILOG) -g2012 -I$(VERILOG_ROOT)/Shared/logisim -I$(VERILOG_ROOT)/Shared/ndlib -I$(VERILOG_ROOT)/Shared/support -I$(VERILOG_ROOT)/PAL -o $@ $^

PAL_44408B_EN_equiv_tb: PAL_44408B_EN_equiv_tb.v $(VERILOG_ROOT)/PAL/PAL_44408B_EN.v $(VERILOG_ROOT)/PAL/PAL_44408B.v
	$(IVERILOG) -g2012 -I$(VERILOG_ROOT)/Shared/logisim -I$(VERILOG_ROOT)/Shared/ndlib -I$(VERILOG_ROOT)/Shared/support -I$(VERILOG_ROOT)/PAL -o $@ $^

PAL_44511A_EN_equiv_tb: PAL_44511A_EN_equiv_tb.v $(VERILOG_ROOT)/PAL/PAL_44511A_EN.v $(VERILOG_ROOT)/PAL/PAL_44511A.v
	$(IVERILOG) -g2012 -I$(VERILOG_ROOT)/Shared/logisim -I$(VERILOG_ROOT)/Shared/ndlib -I$(VERILOG_ROOT)/Shared/support -I$(VERILOG_ROOT)/PAL -o $@ $^

# Registered address-decode PALs (sheet 45) vs an independent PALASM-derived
# golden model: base PAL and its sysclk _D mirror side by side.
PAL_44445B_D_tb: PAL_44445B_D_tb.v $(VERILOG_ROOT)/PAL/PAL_44445B.v $(VERILOG_ROOT)/CPU-BOARD-3202/circuit/PAL_44445B_D.v
	$(IVERILOG) -g2012 -o $@ $^

PAL_44446B_D_tb: PAL_44446B_D_tb.v $(VERILOG_ROOT)/PAL/PAL_44446B.v $(VERILOG_ROOT)/CPU-BOARD-3202/circuit/PAL_44446B_D.v
	$(IVERILOG) -g2012 -o $@ $^

test-44445b-d: PAL_44445B_D_tb
	./PAL_44445B_D_tb

test-44446b-d: PAL_44446B_D_tb
	./PAL_44446B_D_tb

# The same two benches with the derived 2 MB board decode (ND120_ONBOARD_2MB,
# only the Azure build defines it): the upper 2 MB must not be local.
test-44445b-d-2mb: PAL_44445B_D_2MB_tb
	./PAL_44445B_D_2MB_tb

test-44446b-d-2mb: PAL_44446B_D_2MB_tb
	./PAL_44446B_D_2MB_tb

PAL_44445B_D_2MB_tb: PAL_44445B_D_tb.v $(VERILOG_ROOT)/PAL/PAL_44445B.v $(VERILOG_ROOT)/CPU-BOARD-3202/circuit/PAL_44445B_D.v
	$(IVERILOG) -g2012 -DND120_ONBOARD_2MB -o $@ $^

PAL_44446B_D_2MB_tb: PAL_44446B_D_tb.v $(VERILOG_ROOT)/PAL/PAL_44446B.v $(VERILOG_ROOT)/CPU-BOARD-3202/circuit/PAL_44446B_D.v
	$(IVERILOG) -g2012 -DND120_ONBOARD_2MB -o $@ $^

test-pal44304e: PAL_44304E_tb
	./PAL_44304E_tb

test-pal45008b: PAL_45008B_tb
	./PAL_45008B_tb

test-44601: PAL_44601B_tb
	./PAL_44601B_tb

test-pal44801a: PAL_44801A_tb
	./PAL_44801A_tb

test-pal44401b: PAL_44401B_tb
	./PAL_44401B_tb

test-44402d-en: PAL_44402D_EN_equiv_tb
	./PAL_44402D_EN_equiv_tb

test-44403c-en: PAL_44403C_EN_equiv_tb
	./PAL_44403C_EN_equiv_tb

test-44404c-en: PAL_44404C_EN_equiv_tb
	./PAL_44404C_EN_equiv_tb

test-44407a-en: PAL_44407A_EN_equiv_tb
	./PAL_44407A_EN_equiv_tb

test-44408b-en: PAL_44408B_EN_equiv_tb
	./PAL_44408B_EN_equiv_tb

test-44511a-en: PAL_44511A_EN_equiv_tb
	./PAL_44511A_EN_equiv_tb


# =============================================================================
# PALASM-golden testbenches for the PALs that had no coverage before 20-AUG-2026
#
# Each one builds its reference model from DesignDocuments/PAL-Code/SRC/<id>.txt
# - the original PALASM listing - and sweeps every input combination against it,
# forcing the state registers so the whole transition function is exercised and
# not only the reachable states. Every one is EXHAUSTIVE.
#
# They target the DEFAULT build (edge-triggered). Do NOT add
# -DUSE_TRANSPARENT_LATCHES or -DSKIP_WCS_LOAD to these.
# =============================================================================

PAL_44302B_tb: PAL_44302B_tb.v $(VERILOG_ROOT)/PAL/PAL_44302B.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_44303B_tb: PAL_44303B_tb.v $(VERILOG_ROOT)/PAL/PAL_44303B.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_44310D_tb: PAL_44310D_tb.v $(VERILOG_ROOT)/PAL/PAL_44310D.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_44402D_EN_tb: PAL_44402D_EN_tb.v $(VERILOG_ROOT)/PAL/PAL_44402D_EN.v $(VERILOG_ROOT)/PAL/PAL_44402D.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_44403C_EN_tb: PAL_44403C_EN_tb.v $(VERILOG_ROOT)/PAL/PAL_44403C_EN.v $(VERILOG_ROOT)/PAL/PAL_44403C.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_44404C_EN_tb: PAL_44404C_EN_tb.v $(VERILOG_ROOT)/PAL/PAL_44404C_EN.v $(VERILOG_ROOT)/PAL/PAL_44404C.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_44407A_EN_tb: PAL_44407A_EN_tb.v $(VERILOG_ROOT)/PAL/PAL_44407A_EN.v $(VERILOG_ROOT)/PAL/PAL_44407A.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_44408B_EN_tb: PAL_44408B_EN_tb.v $(VERILOG_ROOT)/PAL/PAL_44408B_EN.v $(VERILOG_ROOT)/PAL/PAL_44408B.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_44511A_EN_tb: PAL_44511A_EN_tb.v $(VERILOG_ROOT)/PAL/PAL_44511A_EN.v $(VERILOG_ROOT)/PAL/PAL_44511A.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_44803A_tb: PAL_44803A_tb.v $(VERILOG_ROOT)/PAL/PAL_44803A.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_44902A_tb: PAL_44902A_tb.v $(VERILOG_ROOT)/PAL/PAL_44902A.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_44904B_tb: PAL_44904B_tb.v $(VERILOG_ROOT)/PAL/PAL_44904B.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_45001B_tb: PAL_45001B_tb.v $(VERILOG_ROOT)/PAL/PAL_45001B.v
	$(IVERILOG) -g2005 -o $@ $^

PAL_45009B_tb: PAL_45009B_tb.v $(VERILOG_ROOT)/PAL/PAL_45009B.v
	$(IVERILOG) -g2005 -o $@ $^

test-pal44302b: PAL_44302B_tb
	./PAL_44302B_tb

test-pal44303b: PAL_44303B_tb
	./PAL_44303B_tb

test-pal44310d: PAL_44310D_tb
	./PAL_44310D_tb

test-pal44402d: PAL_44402D_EN_tb
	./PAL_44402D_EN_tb

test-pal44403c: PAL_44403C_EN_tb
	./PAL_44403C_EN_tb

test-pal44404c: PAL_44404C_EN_tb
	./PAL_44404C_EN_tb

test-pal44407a: PAL_44407A_EN_tb
	./PAL_44407A_EN_tb

test-pal44408b: PAL_44408B_EN_tb
	./PAL_44408B_EN_tb

test-pal44511a: PAL_44511A_EN_tb
	./PAL_44511A_EN_tb

test-pal44803a: PAL_44803A_tb
	./PAL_44803A_tb

test-pal44902a: PAL_44902A_tb
	./PAL_44902A_tb

test-pal44904b: PAL_44904B_tb
	./PAL_44904B_tb

test-pal45001b: PAL_45001B_tb
	./PAL_45001B_tb

test-pal45009b: PAL_45009B_tb
	./PAL_45009B_tb

PAL_GOLDEN_TESTS = test-pal44302b test-pal44303b test-pal44310d \
                   test-pal44402d test-pal44403c test-pal44404c \
                   test-pal44407a test-pal44408b test-pal44511a \
                   test-pal44803a test-pal44902a test-pal44904b \
                   test-pal45001b test-pal45009b

test-pal-golden: $(PAL_GOLDEN_TESTS)

# Holds every PAL_*.v to its PALASM listing at PAL/<id>/<id>.pds: no output
# may be driven that the listing does not define, and none may be dropped.
# Also reports which PALs have no listing at all. See PAL/PROVENANCE.md.
test-pal-provenance:
	python3 check_provenance.py

test-all: test-pal44304e test-pal45008b test-44601 test-pal44801a test-pal44401b test-pal44306a test-44402d-en test-44403c-en test-44404c-en test-44407a-en test-44408b-en test-44511a-en $(PAL_GOLDEN_TESTS) test-pal-provenance

clean:
	rm -f PAL_44306A_tb_bin PAL_44306A_teeth_tb_bin pal44306a_result.tmp
	rm -f PAL_44302B_tb PAL_44303B_tb PAL_44310D_tb PAL_44402D_EN_tb PAL_44403C_EN_tb PAL_44404C_EN_tb PAL_44407A_EN_tb PAL_44408B_EN_tb PAL_44511A_EN_tb PAL_44803A_tb PAL_44902A_tb PAL_44904B_tb PAL_45001B_tb PAL_45009B_tb
	rm -f PAL_44304E_tb PAL_45008B_tb PAL_44601B_tb PAL_44801A_tb PAL_44401B_tb PAL_44402D_EN_equiv_tb PAL_44403C_EN_equiv_tb PAL_44404C_EN_equiv_tb PAL_44407A_EN_equiv_tb PAL_44408B_EN_equiv_tb PAL_44511A_EN_equiv_tb *.vcd

.PHONY: test-pal-golden $(PAL_GOLDEN_TESTS)
.PHONY: test-pal44304e test-pal45008b test-44601 test-pal44801a test-pal44401b test-pal44306a test-44402d-en test-44403c-en test-44404c-en test-44407a-en test-44408b-en test-44511a-en test-all clean
