# Shared/support unit tests (iverilog)
# Run:  make test-uart      (SC2661 TX-flag timing)
#       make test-ram       (SIP1M9 ramSize=3 synchronous BRAM: write/read + no-alias)
#       make test-am29833a  (AM29833A USE_SYSCLK=0 vs =2 equivalence)
#       make test-inrprom   (BACKWIRING_PROM: PIL-addressed installation number)
#       make clean

IVERILOG = iverilog
VVP      = vvp
INCDIRS  = -I.. -I../../ndlib -I../../logisim

.PHONY: test-uart test-uart-txint test-uart-txabort test-uart-rxoverrun test-ram test-am29833a test-am29833a-parity test-am29c821 test-inrprom clean

# Back-wiring PROM (installation number), addressed by PIL 3:0.
# -I.. also gives iverilog the include path for nd120_backwiring_defaults.vh.
test-inrprom: BACKWIRING_PROM_tb
	$(VVP) BACKWIRING_PROM_tb | tee inrprom_result.tmp
	@grep -q "TB_RESULT: PASS" inrprom_result.tmp && rm -f inrprom_result.tmp BACKWIRING_PROM_tb.vcd

BACKWIRING_PROM_tb: BACKWIRING_PROM_tb.v ../BACKWIRING_PROM.v ../nd120_backwiring_defaults.vh
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) BACKWIRING_PROM_tb.v ../BACKWIRING_PROM.v

TTL_74245_tb: TTL_74245_tb.v ../TTL_74245.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_74245_tb.v ../TTL_74245.v

# Exhaustive: all 262,144 input combinations. Guards the 20-AUG-2026 removal
# of the shared 'internalBus' helper, which was functionally invisible but
# structurally closed a combinational loop on the FIDB bus.
test-74245: TTL_74245_tb
	$(VVP) TTL_74245_tb | tee ttl74245_result.tmp
	@grep -q "TB_RESULT: PASS" ttl74245_result.tmp && rm -f ttl74245_result.tmp

test-am29833a: AM29833A_equiv_tb
	$(VVP) AM29833A_equiv_tb | tee am29833a_result.tmp
	@grep -q "TB_RESULT: PASS" am29833a_result.tmp && rm -f am29833a_result.tmp

test-am29c821: AM29C821_equiv_tb
	$(VVP) AM29C821_equiv_tb | tee am29c821_result.tmp
	@grep -q "TB_RESULT: PASS" am29c821_result.tmp && rm -f am29c821_result.tmp AM29C821_equiv_tb.vcd

AM29C821_equiv_tb: AM29C821_equiv_tb.v ../AM29C821.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) AM29C821_equiv_tb.v ../AM29C821.v

AM29833A_equiv_tb: AM29833A_equiv_tb.v ../AM29833A.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) AM29833A_equiv_tb.v ../AM29833A.v

# Parity CONVENTION gate: the value every memory backend regenerates (~^data)
# must be the one this chip calls correct, and the inverted bit must always
# fault. Protects the "parity is computed, never stored" policy.
test-am29833a-parity: AM29833A_parity_regen_tb
	$(VVP) AM29833A_parity_regen_tb | tee am29833a_par_result.tmp
	@grep -q "TB_RESULT: PASS" am29833a_par_result.tmp && rm -f am29833a_par_result.tmp

AM29833A_parity_regen_tb: AM29833A_parity_regen_tb.v ../AM29833A.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) AM29833A_parity_regen_tb.v ../AM29833A.v

test-uart: SC2661_UART_tb
	$(VVP) SC2661_UART_tb

# TX abort-on-command-write regression (24-AUG-2026, Nexys LFN campaign):
# a command write with TxEN=0 must not chop the character in flight and
# must not strand a THR character written during the disable window.
test-uart-txabort: SC2661_TX_ABORT_tb
	$(VVP) SC2661_TX_ABORT_tb | tee txabort_result.tmp
	@grep -q "TB_RESULT: PASS" txabort_result.tmp && rm -f txabort_result.tmp

SC2661_TX_ABORT_tb: SC2661_TX_ABORT_tb.v ../SC2661_UART.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) SC2661_TX_ABORT_tb.v ../SC2661_UART.v

# TX-interrupt re-fire regression (25-AUG-2026, RUN dummy-output flood):
# BINT10 is level-sensitive (IOC2 & TBMT), so TBMT must drop the same cycle
# the CPU writes THR or the level-10 interrupt handler re-fires and floods
# the console. FAILS against the pre-fix SC2661 (1-cycle re-fire window).
test-uart-txint: SC2661_TXINT_tb
	$(VVP) SC2661_TXINT_tb | tee txint_result.tmp
	@grep -q "TB_RESULT: PASS" txint_result.tmp && rm -f txint_result.tmp SC2661_TXINT_tb.vcd

SC2661_TXINT_tb: SC2661_TXINT_tb.v ../SC2661_UART.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) SC2661_TXINT_tb.v ../SC2661_UART.v

SC2661_UART_tb: SC2661_UART_tb.v ../SC2661_UART.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) SC2661_UART_tb.v ../SC2661_UART.v

test-ram: SIP1M9_bram_tb
	$(VVP) SIP1M9_bram_tb

SIP1M9_bram_tb: SIP1M9_bram_tb.v ../SIP1M9.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) SIP1M9_bram_tb.v ../SIP1M9.v

# RX overrun regression (31-AUG-2026, PED keyboard-input investigation):
# a new start bit used to clear regReceiveHoldingRegister immediately and
# shift the new byte into it live, so a CPU read landing mid-shift got a
# torn value matching neither byte. Back-to-back characters with zero gap
# (local loopback) must leave RHR holding the LAST byte clean, with the
# Overrun flag set - never a torn value.
test-uart-rxoverrun: SC2661_RX_OVERRUN_tb
	$(VVP) SC2661_RX_OVERRUN_tb | tee rxoverrun_result.tmp
	@grep -q "TB_RESULT: PASS" rxoverrun_result.tmp && rm -f rxoverrun_result.tmp

SC2661_RX_OVERRUN_tb: SC2661_RX_OVERRUN_tb.v ../SC2661_UART.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) SC2661_RX_OVERRUN_tb.v ../SC2661_UART.v

clean:
	rm -f SC2661_UART_tb SIP1M9_bram_tb SC2661_RX_OVERRUN_tb *.vcd

# P1c-2/P1d/P3: TTL_74646/74648 strobe-clock edge-capture equivalence
test-7464x: TTL_7464x_equiv_tb
	$(VVP) TTL_7464x_equiv_tb | tee t7464x_result.tmp
	@grep -q "TB_RESULT: PASS" t7464x_result.tmp && rm -f t7464x_result.tmp TTL_7464x_equiv_tb.vcd

TTL_7464x_equiv_tb: TTL_7464x_equiv_tb.v ../TTL_74646.v ../TTL_74648.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_7464x_equiv_tb.v ../TTL_74646.v ../TTL_74648.v

# P2 wrappers: SCAN_FF_EN / D_FLIPFLOP_EN / R81_EN mode equivalence
NDLIB = ../../ndlib
LOGISIM2 = ../../logisim
test-ffen: FF_EN_equiv_tb
	$(VVP) FF_EN_equiv_tb | tee ffen_result.tmp
	@grep -q "TB_RESULT: PASS" ffen_result.tmp && rm -f ffen_result.tmp FF_EN_equiv_tb.vcd

FF_EN_equiv_tb: FF_EN_equiv_tb.v $(NDLIB)/SCAN_FF_EN.v $(NDLIB)/D_FLIPFLOP_EN.v $(NDLIB)/R81_EN.v $(NDLIB)/R41P_EN.v $(NDLIB)/SCAN_FF.v $(NDLIB)/R81.v $(NDLIB)/R41P.v $(LOGISIM2)/D_FLIPFLOP.v
	$(IVERILOG) -g2012 -o $@ $^

# P2 wrappers: remaining ndlib _EN mode-equivalence tbs
# (base modules and gate primitives resolved via -y from ndlib/logisim;
#  F924's base module lives in the DGA tree, listed explicitly)
DGACIRC = ../../../DECODE-GateArray/DGA/circuit

test-scanrst-en: SCAN_WITH_RESET_N_EN_equiv_tb
	$(VVP) SCAN_WITH_RESET_N_EN_equiv_tb | tee scanrst_result.tmp
	@grep -q "TB_RESULT: PASS" scanrst_result.tmp && rm -f scanrst_result.tmp SCAN_WITH_RESET_N_EN_equiv_tb.vcd

SCAN_WITH_RESET_N_EN_equiv_tb: SCAN_WITH_RESET_N_EN_equiv_tb.v $(NDLIB)/SCAN_WITH_RESET_N_EN.v $(NDLIB)/SCAN_WITH_RESET_N.v $(LOGISIM2)/D_FLIPFLOP.v
	$(IVERILOG) -g2012 -o $@ SCAN_WITH_RESET_N_EN_equiv_tb.v -y $(NDLIB) -y $(LOGISIM2)

test-scanset-en: SCAN_WITH_SET_N_EN_equiv_tb
	$(VVP) SCAN_WITH_SET_N_EN_equiv_tb | tee scanset_result.tmp
	@grep -q "TB_RESULT: PASS" scanset_result.tmp && rm -f scanset_result.tmp SCAN_WITH_SET_N_EN_equiv_tb.vcd

SCAN_WITH_SET_N_EN_equiv_tb: SCAN_WITH_SET_N_EN_equiv_tb.v $(NDLIB)/SCAN_WITH_SET_N_EN.v $(NDLIB)/SCAN_WITH_SET_N.v $(LOGISIM2)/D_FLIPFLOP.v
	$(IVERILOG) -g2012 -o $@ SCAN_WITH_SET_N_EN_equiv_tb.v -y $(NDLIB) -y $(LOGISIM2)

test-sr44-en: SR44_EN_equiv_tb
	$(VVP) SR44_EN_equiv_tb | tee sr44_result.tmp
	@grep -q "TB_RESULT: PASS" sr44_result.tmp && rm -f sr44_result.tmp SR44_EN_equiv_tb.vcd

SR44_EN_equiv_tb: SR44_EN_equiv_tb.v $(NDLIB)/SR44_EN.v $(NDLIB)/SR44.v $(LOGISIM2)/D_FLIPFLOP.v $(LOGISIM2)/Multiplexer_2.v
	$(IVERILOG) -g2012 -o $@ SR44_EN_equiv_tb.v -y $(NDLIB) -y $(LOGISIM2)

test-m169c-en: M169C_EN_equiv_tb
	$(VVP) M169C_EN_equiv_tb | tee m169c_result.tmp
	@grep -q "TB_RESULT: PASS" m169c_result.tmp && rm -f m169c_result.tmp M169C_EN_equiv_tb.vcd

M169C_EN_equiv_tb: M169C_EN_equiv_tb.v $(NDLIB)/M169C_EN.v $(NDLIB)/M169C.v $(NDLIB)/D_FLIPFLOP_EN.v $(LOGISIM2)/D_FLIPFLOP.v
	$(IVERILOG) -g2012 -o $@ M169C_EN_equiv_tb.v -y $(NDLIB) -y $(LOGISIM2)

test-f924-en: F924_EN_equiv_tb
	$(VVP) F924_EN_equiv_tb | tee f924_result.tmp
	@grep -q "TB_RESULT: PASS" f924_result.tmp && rm -f f924_result.tmp F924_EN_equiv_tb.vcd

F924_EN_equiv_tb: F924_EN_equiv_tb.v $(NDLIB)/F924_EN.v $(DGACIRC)/F924.v $(NDLIB)/D_FLIPFLOP_EN.v $(LOGISIM2)/D_FLIPFLOP.v
	$(IVERILOG) -g2012 -o $@ F924_EN_equiv_tb.v $(DGACIRC)/F924.v -y $(NDLIB) -y $(LOGISIM2)

# FIFO_8BIT: write/read order, mid-stream reset, full/empty flags,
# write-when-full drop, read-when-empty zero (moved from FIFO_8BIT_TB/).
test-fifo: FIFO_tb
	$(VVP) FIFO_tb | tee fifo_result.tmp
	@grep -q "TB_RESULT: PASS" fifo_result.tmp && rm -f fifo_result.tmp

FIFO_tb: FIFO_tb.v ../FIFO_8BIT.v
	$(IVERILOG) -g2012 -o $@ FIFO_tb.v ../FIFO_8BIT.v

# IDT6168A_20 4Kx4 sync-BRAM SRAM model: write/readback, 1-clock read
# latency, CE_n/WE_n output masking, write-first forwarding (moved from
# IDT6168A_20_TB/).
test-idt6168a: IDT6168A_20_tb
	$(VVP) IDT6168A_20_tb | tee idt6168a_result.tmp
	@grep -q "TB_RESULT: PASS" idt6168a_result.tmp && rm -f idt6168a_result.tmp IDT6168A_20_tb.vcd

IDT6168A_20_tb: IDT6168A_20_tb.v ../IDT6168A_20.v
	$(IVERILOG) -g2012 -o $@ IDT6168A_20_tb.v ../IDT6168A_20.v

.PHONY: test-fifo test-idt6168a

###############################################################################
# TTL / AMD support-chip functional testbenches (20-AUG-2026)
#
# One target per part. Every one of these is self-checking and prints
# "TB_RESULT: PASS" or "TB_RESULT: FAIL"; the recipe greps for PASS so a
# silent failure cannot be mistaken for a pass. The .vcd each one writes is
# a SHORT documentation window (the exhaustive sweeps run with $dumpoff), so
# it is kept, not deleted - it is the committed timing diagram for the part.
###############################################################################

# --- combinational parts -----------------------------------------------------

# 74139 dual 2-to-4 decoder: all 64 input combinations, both halves at once,
# plus the half-to-half independence check.
test-74139: TTL_74139_tb
	$(VVP) TTL_74139_tb | tee t74139_result.tmp
	@grep -q "TB_RESULT: PASS" t74139_result.tmp && rm -f t74139_result.tmp

TTL_74139_tb: TTL_74139_tb.v ../TTL_74139.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_74139_tb.v ../TTL_74139.v

# 74241 octal buffer, ASYMMETRIC enables (G1_n active low, G2 active high):
# all 1024 combinations + the disabled-drives-ZERO rule on both halves.
test-74241: TTL_74241_tb
	$(VVP) TTL_74241_tb | tee t74241_result.tmp
	@grep -q "TB_RESULT: PASS" t74241_result.tmp && rm -f t74241_result.tmp

TTL_74241_tb: TTL_74241_tb.v ../TTL_74241.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_74241_tb.v ../TTL_74241.v

# 74244 octal buffer, both halves active-low enable: all 1024 combinations
# + the disabled-drives-ZERO rule.
test-74244: TTL_74244_tb
	$(VVP) TTL_74244_tb | tee t74244_result.tmp
	@grep -q "TB_RESULT: PASS" t74244_result.tmp && rm -f t74244_result.tmp

TTL_74244_tb: TTL_74244_tb.v ../TTL_74244.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_74244_tb.v ../TTL_74244.v

# 74373 octal transparent latch: transparent-follow, hold, and OC_n masking
# in BOTH the transparent and the holding state (256 values through each).
test-74373: TTL_74373_tb
	$(VVP) TTL_74373_tb | tee t74373_result.tmp
	@grep -q "TB_RESULT: PASS" t74373_result.tmp && rm -f t74373_result.tmp

TTL_74373_tb: TTL_74373_tb.v ../TTL_74373.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_74373_tb.v ../TTL_74373.v

# 74521 8-bit identity comparator: all 131,072 combinations. Also pins down
# what E_n=1 does HERE (AB_n forced to 0, the ASSERTED level) - a genuine
# departure from the real 74521, which forces the output inactive/high.
test-74521: TTL_74521_tb
	$(VVP) TTL_74521_tb | tee t74521_result.tmp
	@grep -q "TB_RESULT: PASS" t74521_result.tmp && rm -f t74521_result.tmp

TTL_74521_tb: TTL_74521_tb.v ../TTL_74521.v $(LOGISIM2)/Comparator.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_74521_tb.v ../TTL_74521.v $(LOGISIM2)/Comparator.v

# --- clocked parts -----------------------------------------------------------

# 74273 octal FF with clear, in BOTH USE_SYSCLK modes (0 = posedge CLK,
# 2 = sysclk-sampled rising-edge capture). NOTE: unlike the real 74273 the
# clear here is NOT asynchronous - the tb pins down what this RTL does.
test-74273: TTL_74273_tb
	$(VVP) TTL_74273_tb | tee t74273_result.tmp
	@grep -q "TB_RESULT: PASS" t74273_result.tmp && rm -f t74273_result.tmp

TTL_74273_tb: TTL_74273_tb.v ../TTL_74273.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_74273_tb.v ../TTL_74273.v

# 74374 octal FF with OE_n. This RTL does NOT clock on CK: it detects the CK
# rise against sysclk, so the capture lands one sysclk later. That timing is
# what the tb asserts.
test-74374: TTL_74374_tb
	$(VVP) TTL_74374_tb | tee t74374_result.tmp
	@grep -q "TB_RESULT: PASS" t74374_result.tmp && rm -f t74374_result.tmp

TTL_74374_tb: TTL_74374_tb.v ../TTL_74374.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_74374_tb.v ../TTL_74374.v

# 74393 4-stage ripple counter: all 16 states + the wrap, async active-HIGH
# reset, and the named check that it does NOT advance on the wrong CLK edge
# (that check is load-bearing - the exhaustive sweep alone cannot see it).
test-74393: TTL_74393_tb
	$(VVP) TTL_74393_tb | tee t74393_result.tmp
	@grep -q "TB_RESULT: PASS" t74393_result.tmp && rm -f t74393_result.tmp

TTL_74393_tb: TTL_74393_tb.v ../TTL_74393.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_74393_tb.v ../TTL_74393.v

# 74534 octal FF with INVERTING outputs, both USE_SYSCLK modes; all 256 D
# values must come out as ~D, and OE_n must force 0 even when ~D is all-ones.
test-74534: TTL_74534_tb
	$(VVP) TTL_74534_tb | tee t74534_result.tmp
	@grep -q "TB_RESULT: PASS" t74534_result.tmp && rm -f t74534_result.tmp

TTL_74534_tb: TTL_74534_tb.v ../TTL_74534.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_74534_tb.v ../TTL_74534.v

# AM29841 10-bit latch in all THREE behaviours: transparent latch (the real
# part), posedge-LE (the DEFAULT build), and sysclk+EN capture.
test-am29841: AM29841_tb
	$(VVP) AM29841_tb | tee am29841_result.tmp
	@grep -q "TB_RESULT: PASS" am29841_result.tmp && rm -f am29841_result.tmp

AM29841_tb: AM29841_tb.v ../AM29841.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) AM29841_tb.v ../AM29841.v

# AM29861A 10-bit transceiver: all 4 enable states, and the transceiver rule
# that matters on the FIDB bus - the far-side input must NOT reach the near-
# side output (the same property the 74245 gate guards).
test-am29861a: AM29861A_tb
	$(VVP) AM29861A_tb | tee am29861a_result.tmp
	@grep -q "TB_RESULT: PASS" am29861a_result.tmp && rm -f am29861a_result.tmp

AM29861A_tb: AM29861A_tb.v ../AM29861A.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) AM29861A_tb.v ../AM29861A.v

.PHONY: test-74139 test-74241 test-74244 test-74373 test-74521 \
        test-74273 test-74374 test-74393 test-74534 test-am29841 test-am29861a

# --- bus transceivers with registers ------------------------------------------

# 74646 (non-inverting) and 74648 (INVERTING) full FUNCTIONAL truth table:
# all 16 states of {DIR, OE_n, SAB, SBA} crossed with data patterns, the
# stored-vs-real-time select, and - the property that matters on this bus -
# the far-side input must NOT reach the near-side output in either direction.
# (TTL_7464x_equiv_tb.v is the separate USE_SYSCLK MODE test; these two are
# the function test, at the default posedge-CLKAB/CLKBA parameters.)
test-74646-func: TTL_74646_func_tb
	$(VVP) TTL_74646_func_tb | tee t74646f_result.tmp
	@grep -q "TB_RESULT: PASS" t74646f_result.tmp && rm -f t74646f_result.tmp

TTL_74646_func_tb: TTL_74646_func_tb.v ../TTL_74646.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_74646_func_tb.v ../TTL_74646.v

test-74648-func: TTL_74648_func_tb
	$(VVP) TTL_74648_func_tb | tee t74648f_result.tmp
	@grep -q "TB_RESULT: PASS" t74648f_result.tmp && rm -f t74648f_result.tmp

TTL_74648_func_tb: TTL_74648_func_tb.v ../TTL_74648.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TTL_74648_func_tb.v ../TTL_74648.v

# --- SRAM models --------------------------------------------------------------
# Exhaustive is impossible for these, so each one covers address 0, the MAX
# address, a spread of arbitrary addresses, no-aliasing, read-during-write,
# and every output-masking term forcing 0.

# Am9150 1024x4 (MMU cache CHIP_21F), ASYNCHRONOUS read path.
test-am9150: Am9150_tb
	$(VVP) Am9150_tb | tee am9150_result.tmp
	@grep -q "TB_RESULT: PASS" am9150_result.tmp && rm -f am9150_result.tmp

Am9150_tb: Am9150_tb.v ../Am9150.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) Am9150_tb.v ../Am9150.v

# Am9150_w_clock: same part with a REGISTERED output (read latency differs).
test-am9150-clk: Am9150_w_clock_tb
	$(VVP) Am9150_w_clock_tb | tee am9150c_result.tmp
	@grep -q "TB_RESULT: PASS" am9150c_result.tmp && rm -f am9150c_result.tmp

Am9150_w_clock_tb: Am9150_w_clock_tb.v ../Am9150_with_clk.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) Am9150_w_clock_tb.v ../Am9150_with_clk.v

# IMS1403_25 16K x 1 static RAM.
test-ims1403: IMS1403_25_tb
	$(VVP) IMS1403_25_tb | tee ims1403_result.tmp
	@grep -q "TB_RESULT: PASS" ims1403_result.tmp && rm -f ims1403_result.tmp

IMS1403_25_tb: IMS1403_25_tb.v ../IMS1403_25.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) IMS1403_25_tb.v ../IMS1403_25.v

# TMM2018D_25 2K x 8 (cache tags + page tables). BOTH read models are gated:
# the default SYNCHRONOUS BRAM model, and the TMM_ASYNC_READ model that
# restores the real part's asynchronous read.
test-tmm2018d: TMM2018D_25_tb TMM2018D_25_async_tb
	$(VVP) TMM2018D_25_tb | tee tmm_result.tmp
	@grep -q "TB_RESULT: PASS" tmm_result.tmp
	$(VVP) TMM2018D_25_async_tb | tee tmm_async_result.tmp
	@grep -q "TB_RESULT: PASS" tmm_async_result.tmp && rm -f tmm_result.tmp tmm_async_result.tmp

TMM2018D_25_tb: TMM2018D_25_tb.v ../TMM2018D_25.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) TMM2018D_25_tb.v ../TMM2018D_25.v

TMM2018D_25_async_tb: TMM2018D_25_tb.v ../TMM2018D_25.v
	$(IVERILOG) -g2012 -DTMM_ASYNC_READ -o $@ $(INCDIRS) TMM2018D_25_tb.v ../TMM2018D_25.v

# --- board debug display ------------------------------------------------------

# SevenSegDebug: all 16 hex patterns checked AND proved mutually distinct
# (that is what catches a copy-paste slip in the decode table), one-hot anode,
# and each anode position selecting the right nibble of the 16-bit value.
test-sevenseg: SevenSegDebug_tb
	$(VVP) SevenSegDebug_tb | tee sevenseg_result.tmp
	@grep -q "TB_RESULT: PASS" sevenseg_result.tmp && rm -f sevenseg_result.tmp

SevenSegDebug_tb: SevenSegDebug_tb.v ../SevenSegDebug.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) SevenSegDebug_tb.v ../SevenSegDebug.v

.PHONY: test-74646-func test-74648-func test-am9150 test-am9150-clk \
        test-ims1403 test-tmm2018d test-sevenseg

# AM29C821 FUNCTIONAL gate (absolute values), complementing the mode-vs-mode
# test-am29c821 above. That one compares the three USE_SYSCLK modes against
# EACH OTHER and never asserts an expected value, so a fault present in all
# three at once - a dropped OE_n mask, an inverted output - passes it
# silently. This one checks each mode against a reference model: all 1024 D
# values enabled and disabled, plus the hold and mode-behaviour checks.
test-am29c821-func: AM29C821_func_tb
	$(VVP) AM29C821_func_tb | tee am29c821f_result.tmp
	@grep -q "TB_RESULT: PASS" am29c821f_result.tmp && rm -f am29c821f_result.tmp

AM29C821_func_tb: AM29C821_func_tb.v ../AM29C821.v
	$(IVERILOG) -g2012 -o $@ $(INCDIRS) AM29C821_func_tb.v ../AM29C821.v

.PHONY: test-am29c821-func

###############################################################################
# The Quartus RAM arm (QUARTUS_RAM_INFER) vs the plain-Verilog reference model.
#
# Only the MiSTer build compiles `ifdef QUARTUS_RAM_INFER` in IDT6168A_20.v
# (the WCS) and MEM_RAM_49_BLOCKRAM.v (main memory) - every other toolchain
# takes the plain model - so a difference there is invisible to normal
# simulation and shows up only as a board that will not boot. That is what
# happened on 01-SEP-2026 with the arm's predecessor, an altsyncram
# megafunction: outdata_reg_a="CLOCK0" gave the WCS a TWO-clock read
# (altsyncram registers the address too), the microsequencer ran a step
# behind the cycle controller, and a nested T,RETURN popped the wrong address.
# The megafunction arm was deleted the same day; this gate is what keeps its
# replacement honest.
###############################################################################
#
# This target runs the WCS pair (IDT6168A_20_equiv_tb). The main-memory pair
# (MEM_RAM_49_BLOCKRAM_equiv_tb) runs from its own directory:
# CPU-BOARD-3202/circuit/sim, make test-mem-ram-equiv. Each arm must pass its
# own self-check as well as match the other arm.
.PHONY: test-quartus-ram-equiv
test-quartus-ram-equiv: IDT6168A_20_equiv_tb.v ../IDT6168A_20.v
	./run_quartus_ram_equiv.sh wcs | tee quartus_ram_equiv_result.tmp
	@grep -q "^TB_RESULT: PASS" quartus_ram_equiv_result.tmp && rm -f quartus_ram_equiv_result.tmp
