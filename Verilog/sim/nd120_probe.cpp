/**************************************************************************
** ND120_probe.cpp  -  Generic, scriptable Verilator PROBE engine        **
**                                                                       **
** ONE reusable simulation harness for the ND-120 CPU (VND120_TOP) that  **
** you point at ANY signal and ANY trigger AT RUNTIME, driven over a     **
** line protocol on stdin/stdout from nd120_probe.py.                    **
**                                                                       **
** Replaces the recompile-per-signal pattern of latch_ff_compare.cpp     **
** and the hardcoded post-trigger window of test_nd120.cpp with:         **
**   - runtime signal access by name (curated root-path REGISTRY floor   **
**     + optional VPI for arbitrary signals),                            **
**   - a runtime RULE engine: WHEN <bool-expr-over-signals> DO <actions>,**
**   - a PRE/POST ring-buffer CSV sink (pre-trigger history a store-     **
**     routing bug needs), and                                           **
**   - a trigger-windowed full-hierarchy FST (read by fst.py/vcd_extract)**
**                                                                       **
** REPORT-ONLY guardrail: this file NEVER edits RTL. It is a NEW sim     **
** harness built with --public-flat-rw --vpi (both non-invasive).        **
**                                                                       **
** Build (WSL only):  make probe USE_LATCHES=0     (see sim/Makefile)    **
** Reuses:  loadfile()/gb()/gw()/calc_parity() and proccess_bif_signal() **
**          engine from test_nd120.cpp / latch_ff_compare.cpp.           **
**                                                                       **
** Author: probe harness (2026-07-22).                                   **
***************************************************************************/

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <map>
#include <deque>
#include <functional>
#include <queue>

#include "VND120_TOP.h"
#include "VND120_TOP___024root.h"   // root-level struct: RAM arrays + public-flat signals
#include "verilated.h"
#include "verilated_fst_c.h"        // windowed full-hierarchy FST sink (same as test_nd120)

// VPI (Stage 2): resolve ARBITRARY signals by dotted name at runtime. Built with
// --vpi so vpi_handle_by_name / vpi_get_value are available. If the VPI layer
// cannot resolve a name we simply fall back to the direct-member REGISTRY and
// report the limitation honestly - VPI is a stretch, never a hard dependency.
#include "verilated_vpi.h"   // pulls in sv_vpi_user.h -> vpi_user.h (the VPI API)

#include "NDBus.h"
#include "NDDevices.h"

// ---- BPUN loader (identical format handling as test_nd120.cpp) --------------
typedef unsigned short ushort;
void loadfile(char *fn, int off, uint8_t *low_array, uint8_t *low_array9,
              uint8_t *high_array, uint8_t *high_array9);

static int gb(FILE *f) { int w; if (f == NULL) return 00; w = getc(f) & 0377; return w; }
static int gw(FILE *f) { int c = gb(f); return (c << 8) | gb(f); }

// Return 1 if the low 8 bits have EVEN parity (matches the RAM parity arrays).
static ushort calc_parity(uint16_t val)
{
    ushort parity = 0;
    for (int i = 0; i < 8; i++) { parity ^= (val & 1); val >>= 1; }
    return parity == 0 ? 1 : 0;
}

// BPUN backdoor loader - see the format comment block in test_nd120.cpp.
void loadfile(char *fn, int off, uint8_t *low_array, uint8_t *low_array9,
              uint8_t *high_array, uint8_t *high_array9)
{
    int B, C, E, F, H, I; int w, i; unsigned short s; FILE *f;
    (void)off; (void)B; (void)C; (void)I;
    if ((f = fopen(fn, "r")) == 0) { fprintf(stderr, "Unable to open file %s\n", fn); return; }
    // B/C section: optional octal start addresses, terminated by '!'
    for (B = C = 0; (w = gb(f) & 0177) != '!';) {
        switch (w) {
        case '\n': continue;
        case '\r': B = C, C = 0; break;
        case '0': case '1': case '2': case '3':
        case '4': case '5': case '6': case '7':
            C = (C << 3) | (w - '0'); break;
        default: B = C = 0;
        }
    }
    E = gw(f);                                  // load address (word index)
    F = gw(f);                                  // word count
    for (i = s = 0; i < F; i++) {
        int data16 = gw(f);
        low_array[E + i]  = data16 & 0xFF;      // low byte  -> b0_lo
        high_array[E + i] = (data16 >> 8) & 0xFF; // high byte -> b0_hi
        low_array9[E + i]  = calc_parity(low_array[E + i]);  // parity bit arrays
        high_array9[E + i] = calc_parity(high_array[E + i]);
        s += data16;
    }
    H = gw(f);                                  // checksum word
    if (H != s) fprintf(stderr, "Bad checksum: %06o != %06o\n", H, s);
    I = gw(f);                                  // action code (ignored - we run from cmd)
    fprintf(stderr, "loadfile: %s  load=%06o words=%06o\n", fn, E, F);
    fclose(f);
}

// ===========================================================================
//  GLOBAL SIM STATE
// ===========================================================================
static VND120_TOP *g_top = nullptr;
static long        g_globalTick = 0;            // full sysclk cycles since construction
static long        g_resetReleaseTick = 100;    // btn1 (sys_rst_n) raised at this tick
static vluint64_t  g_simTime = 0;               // FST timestamp (ps), advances only while dumping
static const vluint64_t g_timeStep = 5;

// ---- RAM backdoor pointers (word-indexed; hi<<8 | lo). Same paths test_nd120 uses.
static uint8_t *g_ram_lo, *g_ram_lo_p, *g_ram_hi, *g_ram_hi_p;

// ---- Windowed FST sink (created lazily on `capture fst <path>`) ------------
static VerilatedFstC *g_trace = nullptr;
static bool           g_fstEnabled = false;     // gated by rules (fst_on/fst_off)

// ---- CSV PRE/POST ring sink ------------------------------------------------
static FILE               *g_csvFile = nullptr;
static bool                g_csvHeaderWritten = false;
static std::vector<std::string> g_watch;        // ordered watched signal names
static std::deque<std::string>  g_ring;         // PRE history of formatted rows
static int                 g_pre  = 128;         // ring depth
static int                 g_post = 128;         // live rows written after a trigger
static int                 g_postRemaining = 0;  // countdown of live POST rows

// ---- UART console (optional; lets the driver double as a TPE driver) -------
static std::queue<char>    g_txq;               // chars queued by `send`
static std::string         g_console;           // accumulated emulated-terminal output
static int DELAY_FRAMES = 16;
static int HALF_DELAY_WAIT = 8;
static int txData=0, txDataBit=0, txEnabled=0, txTicks=0, txOnes=0;
static int rxData=0, rxDataBit=0, rxEnabled=0, rxTicks=0, rxOnes=0;
// Pseudo-signals: the CPU's most-recently emitted output byte and a 1-tick
// strobe on the tick it completes. Lets rules trigger per output character
// (e.g. capture microcode state when a corrupted byte is emitted). The char
// completes ~11*DELAY_FRAMES ticks AFTER the CPU wrote it, so pair TXSTROBE
// with a deep pre-ring (set pre) to look back at the store/load that produced it.
static int g_lastTxByte = 0;   // last fully-received output byte (0..255)
static int g_txStrobe   = 0;   // 1 on the single tick that byte completes

// ===========================================================================
//  SIGNAL REGISTRY  (Stage 1 guaranteed floor)  +  VPI  (Stage 2 stretch)
// ===========================================================================
// A signal read returns {value, width, ok}. Resolution order:
//   1) direct-member REGISTRY  - curated root-path readers, PROVEN to compile
//      (the latch_ff_compare pattern). This is the guaranteed floor.
//   2) VPI by dotted name      - arbitrary signals, resolved at runtime. If the
//      Verilator VPI layer cannot resolve it, we report ok=false (honest ERR).
struct SigVal { uint64_t val; int width; bool ok; };

struct RegEntry {
    int width;
    std::function<uint64_t()> read;   // captures g_top; reads a root-path member
    const char *vpiPath;              // dotted VPI path (documentation) - NOTE:
                                      // do NOT name this 'vpiName' - vpi_user.h
                                      // #defines vpiName to the integer 2.
    // Explicit ctors: map::operator[] needs a default ctor, and the `= {w, lambda,
    // str}` init needs a real ctor (aggregate init of the std::function member
    // from a lambda fails in braced-assignment context under gnu++14).
    RegEntry() : width(0), read(nullptr), vpiPath("") {}
    RegEntry(int w, std::function<uint64_t()> r, const char *v) : width(w), read(std::move(r)), vpiPath(v) {}
};
static std::map<std::string, RegEntry>   g_registry;   // friendly name -> reader
static std::map<std::string, std::vector<std::string>> g_groups; // group -> names
static std::map<std::string, std::string> g_alias;     // friendly -> dotted VPI path
static std::map<std::string, vpiHandle>   g_vpiCache;   // dotted name -> handle

// Convenience to read a root-flat member of a given C type as uint64_t.
#define RD(EXPR) ([]() -> uint64_t { return (uint64_t)(g_top->rootp->EXPR); })

static void buildRegistry()
{
    // ---- MIC group: microcode address / debug word. TOP-LEVEL PORTS -> always OK.
    g_registry["CSA_12_0"]    = { 13, RD(CSA_12_0),          "ND120_TOP.CSA_12_0" };
    g_registry["CSA"]         = { 13, RD(CSA_12_0),          "ND120_TOP.CSA_12_0" };
    g_registry["XMIC_DBG_15_0"] = { 16, RD(XMIC_DBG_15_0),   "ND120_TOP.XMIC_DBG_15_0" };
    g_registry["XMIC"]        = { 16, RD(XMIC_DBG_15_0),     "ND120_TOP.XMIC_DBG_15_0" };
    g_registry["led"]         = { 6,  RD(led),               "ND120_TOP.led" };

    // ---- Probe pseudo-signals: the CPU's emitted output byte + completion strobe.
    // Not RTL members - read from the UART-decode globals. Trigger per output char.
    g_registry["TXBYTE"]   = { 8, []() -> uint64_t { return (uint64_t)g_lastTxByte; }, "(probe)TXBYTE" };
    g_registry["TXSTROBE"] = { 1, []() -> uint64_t { return (uint64_t)g_txStrobe;   }, "(probe)TXSTROBE" };

    // ---- INTR group: interrupt-controller request/clear signals (IDENT-clear bug).
    // Path CORE.CPU_BOARD.CPU.PROC.CGA.DELILAH.INTR[.CNTLR...]. Member names verified
    // from the generated header. Decision tree: CLRQ[n] pulses but IREQ_N[n]==0
    // (source still driving) -> H1; CLRQ high only while MCLK=1 & req survives -> H2;
    // CLRQ never asserts on cmd-4 -> H3.
    g_registry["INTR_lreq"]   = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__IRQ__DOT__s_lreq_15_0),
                                  "INTR.CNTLR.IRQ.s_lreq_15_0" };
    g_registry["INTR_ireq_n"] = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__s_ireq_15_0_n),
                                  "INTR.s_ireq_15_0_n" };
    g_registry["INTR_clrq"]   = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__IRQ__DOT__s_clrq_15_0),
                                  "INTR.CNTLR.IRQ.s_clrq_15_0" };
    g_registry["INTR_mireq_n"]= { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__IRQ__DOT__s_mireq_15_0_n_out),
                                  "INTR.CNTLR.IRQ.s_mireq_15_0_n_out" };
    g_registry["INTR_empid_n"]= { 1,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__s_empid_n),
                                  "INTR.s_empid_n" };
    g_registry["INTR_fidbo"]  = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__s_fidbo_15_0),
                                  "INTR.s_fidbo_15_0" };
    g_registry["INTR_laa"]    = { 4,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__regLAA_3_0),
                                  "INTR.regLAA_3_0" };
    g_registry["INTR_hik"]    = { 1,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__CLR_CLEAR_CONTROL__DOT__s_hik),
                                  "INTR.CNTLR.CLR.s_hik" };
    g_registry["INTR_lok"]    = { 1,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__CLR_CLEAR_CONTROL__DOT__s_lok),
                                  "INTR.CNTLR.CLR.s_lok" };
    g_registry["INTR_j"]      = { 1,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__CLR_CLEAR_CONTROL__DOT__s_j),
                                  "INTR.CNTLR.CLR.s_j" };
    g_registry["INTR_mclk"]   = { 1,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__s_mclk),
                                  "INTR.s_mclk" };

    // ---- IOC / RTC group: the level-13 (BINT13) source. s_bint13_n =
    // ~(s_ioc_3 & s_ioc_0) (IO_REG_41). s_ioc_3=clock-int-generated (RTC trap),
    // s_ioc_0=enable-lvl13. SIOC_n = IOC-register write strobe. s_rtc/s_rtc_cnt =
    // the (sim-shortened, 8192/2048-cycle) free-running RTC tick + counter.
    g_registry["IOC_0"]   = { 1,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__REG_MODULE__DOT__s_ioc_0),
                              "IO.REG_MODULE.s_ioc_0" };
    g_registry["IOC_3"]   = { 1,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__REG_MODULE__DOT__s_ioc_3),
                              "IO.REG_MODULE.s_ioc_3" };
    g_registry["SIOC_n"]  = { 1,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__REG_MODULE__DOT__SIOC_n),
                              "IO.REG_MODULE.SIOC_n" };
    // ---- master clear: IOC bit 5 (EMCL_n), the CPU's MCL output, and the
    // bus master clear the I/O cards are reset by (ND120_CORE s_card_rst_n).
    // Read as model members: VPI did not resolve these, and its reads of
    // signals inside the device generate blocks did not follow the RTL.
    g_registry["EMCL_n"]   = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__REG_MODULE__DOT__s_emcl_n),
                               "IO.REG_MODULE.s_emcl_n" };
    // CORE.MCL is the bus MCL~ (ND3202D.v: MCL = ~s_mcl), so 0 = master clear active.
    g_registry["MCL_n"]    = { 1, RD(ND120_TOP__DOT__CORE__DOT__MCL), "CORE.MCL (bus MCL~)" };
    g_registry["CARD_RST_N"] = { 1, RD(ND120_TOP__DOT__CORE__DOT__s_card_rst_n),
                                 "CORE.s_card_rst_n" };
    g_registry["RTC"]     = { 1,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__POW__DOT__s_rtc),
                              "IO.DCD.DGA.POW.s_rtc" };
    g_registry["RTC_CNT"] = { 32, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__POW__DOT__s_rtc_cnt),
                              "IO.DCD.DGA.POW.s_rtc_cnt" };

    // ---- MMU group: CONFIRMED-present root members (seen in the root header) ----
    // Path fact (verified): CORE.CPU_BOARD.CPU.MMU  (extra CPU level vs the spec).
    g_registry["MMU.s_wmap_n"] = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__s_wmap_n),
                                   "ND120_TOP.CORE.CPU_BOARD.CPU.MMU.s_wmap_n" };
    g_registry["MMU.s_la_20_10"] = { 11, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__s_la_20_10),
                                     "ND120_TOP.CORE.CPU_BOARD.CPU.MMU.s_la_20_10" };
    g_registry["MMU.s_cyd"]    = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_cyd),
                                   "ND120_TOP.CORE.CPU_BOARD.s_cyd" };

    // ---- STORE / BUS group: proven-compiling BIF/MEM PAL nodes copied VERBATIM
    // from latch_ff_compare.cpp (those exact root paths are known to build+run). --
    g_registry["s_term_n"] = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_term_n),
                               "ND120_TOP.CORE.CPU_BOARD.s_term_n" };
    g_registry["s_maclk"]  = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_maclk),
                               "ND120_TOP.CORE.CPU_BOARD.s_maclk" };
    g_registry["EMD"]      = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__BIF__DOT__DPATH__DOT__LDBCTL__DOT__PAL_44302_ULBC1__DOT__EMD),
                               "ND120_TOP.CORE.CPU_BOARD.BIF.DPATH.LDBCTL.PAL_44302_ULBC1.EMD" };
    g_registry["CBWRITE"]  = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__BIF__DOT__DPATH__DOT__LDBCTL__DOT__PAL_44303_ULBC2__DOT__CBWRITE),
                               "ND120_TOP.CORE.CPU_BOARD.BIF.DPATH.LDBCTL.PAL_44303_ULBC2.CBWRITE" };
    g_registry["CMWRITE"]  = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__BIF__DOT__DPATH__DOT__LDBCTL__DOT__PAL_44303_ULBC2__DOT__CMWRITE),
                               "ND120_TOP.CORE.CPU_BOARD.BIF.DPATH.LDBCTL.PAL_44303_ULBC2.CMWRITE" };
    g_registry["BACT"]     = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__BIF__DOT__DPATH__DOT__LDBCTL__DOT__PAL_44304_ULBC3__DOT__BACT_reg),
                               "ND120_TOP.CORE.CPU_BOARD.BIF.DPATH.LDBCTL.PAL_44304_ULBC3.BACT" };
    g_registry["EBADR_n"]  = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__BIF__DOT__DPATH__DOT__LDBCTL__DOT__PAL_44304_ULBC3__DOT__EBADR_n_reg),
                               "ND120_TOP.CORE.CPU_BOARD.BIF.DPATH.LDBCTL.PAL_44304_ULBC3.EBADR_n" };
    g_registry["DAP"]      = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__BIF__DOT__BCTL__DOT__PAL_44401_UBTIM__DOT__DAP),
                               "ND120_TOP.CORE.CPU_BOARD.BIF.BCTL.PAL_44401_UBTIM.DAP" };
    g_registry["BLOCK"]    = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__BIF__DOT__BCTL__DOT__PAL_45001_UBPAR__DOT__BLOCK_reg),
                               "ND120_TOP.CORE.CPU_BOARD.BIF.BCTL.PAL_45001_UBPAR.BLOCK" };
    g_registry["RERR"]     = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__BIF__DOT__BCTL__DOT__PAL_45001_UBPAR__DOT__RERR_reg),
                               "ND120_TOP.CORE.CPU_BOARD.BIF.BCTL.PAL_45001_UBPAR.RERR" };
    g_registry["BDRY"]     = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__LBDIF__DOT__PAL_44310_ULBDIF__DOT__BDRY),
                               "ND120_TOP.CORE.CPU_BOARD.MEM.LBDIF.PAL_44310_ULBDIF.BDRY" };
    g_registry["DISB"]     = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__DATA__DOT__PAL_45008_UDATA__DOT__DISB_reg),
                               "ND120_TOP.CORE.CPU_BOARD.MEM.DATA.PAL_45008_UDATA.DISB" };
    g_registry["TST"]      = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__DATA__DOT__PAL_45008_UDATA__DOT__TST_reg),
                               "ND120_TOP.CORE.CPU_BOARD.MEM.DATA.PAL_45008_UDATA.TST" };
    g_registry["BLOCKL"]   = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__ERROR__DOT__PAL_45009_UERROR__DOT__BLOCKL_reg),
                               "ND120_TOP.CORE.CPU_BOARD.MEM.ERROR.PAL_45009_UERROR.BLOCKL" };

    // ---- MEM READ-PATH group (banner word-2 all-ones read bug, 2026-07-24) ----
    // Distinguish "wrong/unmapped address" from "bad data at the right address".
    // Members exist because the probe builds with --public-flat-rw. MEMRD_ADDR is
    // the un-multiplexed local-bus address MEM sees ([19:0] used); MEMRD_DATA is
    // the 16-bit fetched word MEM returns; RAM_IDX/RAM_Q are the sim-RAM read index
    // and its 18-bit read register (word = {RAM_Q[16:9], RAM_Q[7:0]}). All-ones
    // (0177777) on MEMRD_DATA at a mapped address = a real read fault.
    g_registry["MEMRD_ADDR"] = { 24, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__s_lbd_23_0_in),
                                 "ND120_TOP.CORE.CPU_BOARD.MEM.s_lbd_23_0_in" };
    g_registry["MEMRD_DATA"] = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__s_lbd_15_0_out),
                                 "ND120_TOP.CORE.CPU_BOARD.MEM.s_lbd_15_0_out" };
    g_registry["RAM_IDX"]    = { 20, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__RAM__DOT__idx0),
                                 "ND120_TOP.CORE.CPU_BOARD.MEM.RAM.idx0" };
    g_registry["RAM_Q"]      = { 18, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__RAM__DOT__q0),
                                 "ND120_TOP.CORE.CPU_BOARD.MEM.RAM.q0" };

    // ---- OUTPUT-PATH group (banner word-2 0x5255->0x7F7F datapath bug, 2026-07-24)
    // Trace where a correctly-fetched word turns into 0x7F on the way to the UART:
    // CD16 (fetched word into CGA) -> AREG/TREG (WRF regs) -> FIDBO (CPU IDB out) ->
    // CPUIDB (board CPU IDB) -> IOIDB8 (byte lane into IO/UART) -> THR (UART transmit
    // holding reg = the transmitted byte). Members exist under --public-flat-rw.
    g_registry["CD16"]   = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__s_cd_15_0),
                             "ND120_TOP.CORE.CPU_BOARD.CPU.PROC.CGA.DELILAH.s_cd_15_0" };
    g_registry["AREG"]   = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__A_REG_5__DOT__regFF),
                             "ND120_TOP...WRF.RBLOCK.A_REG_5.regFF" };
    g_registry["TREG"]   = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__T_REG_6__DOT__regFF),
                             "ND120_TOP...WRF.RBLOCK.T_REG_6.regFF" };
    g_registry["FIDBO"]  = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__s_FIDBO_15_0),
                             "ND120_TOP.CORE.CPU_BOARD.CPU.PROC.CGA.DELILAH.s_FIDBO_15_0" };
    g_registry["CPUIDB"] = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_cpu_idb_15_0_out),
                             "ND120_TOP.CORE.CPU_BOARD.s_cpu_idb_15_0_out" };
    g_registry["IOIDB8"] = { 8,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__s_idb_7_0_in),
                             "ND120_TOP.CORE.CPU_BOARD.IO.s_idb_7_0_in" };
    g_registry["THR"]    = { 8,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__regTransmitHoldingRegister),
                             "ND120_TOP.CORE.CPU_BOARD.IO.UART.CHIP_32H.regTransmitHoldingRegister" };
    // UART write cycle: THR <= UART_DIN when UART_CE_n==0 && UART_WR==1 && UART_ADDR==0.
    g_registry["UART_DIN"]  = { 8, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__s_data_in),
                                "ND120_TOP.CORE.CPU_BOARD.IO.UART.CHIP_32H.s_data_in" };
    g_registry["UART_ADDR"] = { 2, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__s_address),
                                "ND120_TOP.CORE.CPU_BOARD.IO.UART.CHIP_32H.s_address" };
    g_registry["UART_CE_n"] = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__s_ce_n),
                                "ND120_TOP.CORE.CPU_BOARD.IO.UART.CHIP_32H.s_ce_n" };
    g_registry["UART_WR"]   = { 1, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__s_read_n),
                                "ND120_TOP.CORE.CPU_BOARD.IO.UART.CHIP_32H.s_read_n" };
    // WRF register-file read-back wires (P,D,B,L,A,T,X) - find which holds 0xFFFF
    // for the word-2 char in the verifier's banner print. (2026-07-24)
    g_registry["RP"] = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg2_p_15_0), "WRF.RBLOCK.s_reg2_p_15_0" };
    g_registry["RD"] = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg1_d_15_0), "WRF.RBLOCK.s_reg1_d_15_0" };
    g_registry["RB"] = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg3_b_15_0), "WRF.RBLOCK.s_reg3_b_15_0" };
    g_registry["RL"] = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg4_l_15_0), "WRF.RBLOCK.s_reg4_l_15_0" };
    g_registry["RA"] = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg5_a_15_0), "WRF.RBLOCK.s_reg5_a_15_0" };
    g_registry["RT"] = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg6_t_15_0), "WRF.RBLOCK.s_reg6_t_15_0" };
    g_registry["RX"] = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg7_x_15_0), "WRF.RBLOCK.s_reg7_x_15_0" };
    // ALU Q register (effective-address A+Q at the LDT char-read; 2026-07-25)
    g_registry["QREG"] = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_QREG__DOT__s_q_15_0_out), "DELILAH.ALU.ALU_QREG.s_q_15_0_out" };
    // ALU Data-Bus Register (DBR) + its load-enable. CSA 0172 (IDBS,DBR PASSD)
    // forwards DBR onto the IDB; DBR itself is loaded from CD earlier when
    // LDDBRN is low. Capture both to find the cycle where word-2's char becomes
    // 0xFF in DBR (datapath-generated, NOT stored in RAM - fastscan proved that).
    g_registry["DBR"]    = { 16, RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_DBR__DOT__s_dbr_15_0_out), "DELILAH.ALU.ALU_DBR.s_dbr_15_0_out" };
    g_registry["LDDBRN"] = { 1,  RD(ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_lddbr_n), "DELILAH.ALU.s_lddbr_n" };

    // ---- VPI-ONLY aliases: signals NOT guaranteed as direct members (get
    // optimized/aliased without --public-flat-rw). Resolved via VPI at runtime;
    // if VPI can't see them the driver reports it honestly. --------------------
    g_alias["MMU.s_lshadow"] = "ND120_TOP.CORE.CPU_BOARD.CPU.MMU.s_lshadow";
    g_alias["MMU.s_epmap_n"] = "ND120_TOP.CORE.CPU_BOARD.CPU.MMU.s_epmap_n";
    g_alias["MMU.s_ept_n"]   = "ND120_TOP.CORE.CPU_BOARD.CPU.MMU.s_ept_n";
    g_alias["PON"]           = "ND120_TOP.CORE.CPU_BOARD.CPU.s_poni";
    g_alias["s_poni"]        = "ND120_TOP.CORE.CPU_BOARD.CPU.s_poni";

    // ---- GROUPS: convenience aliases resolved to a name list -----------------
    g_groups["MIC"]   = { "CSA_12_0", "XMIC_DBG_15_0" };
    g_groups["MMU"]   = { "MMU.s_wmap_n", "MMU.s_la_20_10", "MMU.s_cyd",
                          "MMU.s_lshadow", "MMU.s_epmap_n", "MMU.s_ept_n", "PON" };
    g_groups["STORE"] = { "s_maclk", "CBWRITE", "CMWRITE", "DISB", "TST",
                          "BLOCKL", "EBADR_n", "BDRY", "MMU.s_wmap_n", "MMU.s_la_20_10" };
    g_groups["BUS"]   = { "DAP", "BLOCK", "RERR", "BDRY", "BACT", "EBADR_n",
                          "EMD", "CBWRITE", "CMWRITE", "s_term_n" };
    g_groups["INTR"]  = { "INTR_lreq", "INTR_ireq_n", "INTR_clrq", "INTR_mireq_n",
                          "INTR_empid_n", "INTR_fidbo", "INTR_laa",
                          "INTR_hik", "INTR_lok", "INTR_j", "INTR_mclk", "CSA_12_0" };
    g_groups["IOCRTC"] = { "IOC_0", "IOC_3", "SIOC_n", "RTC", "RTC_CNT",
                           "INTR_ireq_n", "INTR_lreq", "CSA_12_0" };
    g_groups["BUSRD"]  = { "MEMRD_ADDR", "MEMRD_DATA", "RAM_IDX", "RAM_Q",
                           "CSA_12_0", "s_maclk", "BDRY" };
    g_groups["OUT"]    = { "CD16", "AREG", "TREG", "FIDBO", "CPUIDB", "IOIDB8",
                           "THR", "TXBYTE", "CSA_12_0" };
    g_groups["WRUART"] = { "UART_DIN", "UART_ADDR", "UART_CE_n", "UART_WR",
                           "IOIDB8", "CD16", "FIDBO", "THR", "CSA_12_0" };
    g_groups["WRREGS"] = { "UART_DIN", "UART_CE_n", "UART_WR", "UART_ADDR",
                           "FIDBO", "CD16", "RP", "RD", "RB", "RL", "RA", "RT", "RX",
                           "CSA_12_0" };
    // Trace the word-2 LOAD: memory read of the string word + the registers it
    // lands in, to see where 0x5255 becomes 0xFFFF (2026-07-24).
    g_groups["MEMLOAD"]= { "MEMRD_ADDR", "MEMRD_DATA", "CD16", "FIDBO",
                           "RA", "RT", "RD", "RB", "RX", "CSA_12_0" };
    // Per-char read effective-address: catch each char's source read address to see
    // where word-2 deviates (effective-address bug hypothesis, 2026-07-24).
    g_groups["SRCADDR"]= { "UART_DIN", "UART_CE_n", "UART_WR", "UART_ADDR",
                           "MEMRD_ADDR", "MEMRD_DATA", "RA", "CD16", "CSA_12_0" };
    // Effective-address-from-registers: A and Q at the LDT char-read, no DRAM mux.
    g_groups["EACOMP"] = { "UART_DIN", "UART_CE_n", "UART_WR", "UART_ADDR",
                           "RA", "QREG", "RB", "RX", "MEMRD_ADDR", "MEMRD_DATA",
                           "CD16", "CSA_12_0" };
    // Data-Bus-Register load trace: watch DBR + LDDBRN + CD across the per-char
    // window to catch the cycle DBR loads word-2's char as 0xFF vs a good char.
    g_groups["DBRLOAD"]= { "UART_DIN", "UART_CE_n", "UART_WR", "UART_ADDR",
                           "DBR", "LDDBRN", "CD16", "MEMRD_DATA", "QREG", "RA",
                           "CSA_12_0" };
    // WORD2: catch the packed banner word-2 read (051125=0x5255 'RU') into its
    // destination register during the 71M verifier print. 6t proved the char is
    // stored to scratch 03075 as 0377 and no byte-mask of 0x5255 gives 0xFF -> the
    // unpack register must hold 0xFFFF. This group watches DBR + all WRF regs +
    // MEMRD across the per-char unpack to find where 051125 becomes 0177777.
    g_groups["WORD2"]  = { "UART_DIN", "UART_CE_n", "UART_WR", "UART_ADDR",
                           "MEMRD_ADDR", "MEMRD_DATA", "CD16", "DBR", "QREG",
                           "RA", "RT", "RD", "RB", "RX", "CSA_12_0" };
    // WORD2W: WORD2 + memory write strobes, to catch the STORE to scratch cell
    // 03075 that puts 0377 there for word-index-2 chars (R,U). Trigger on the
    // 0377-char UART write with a large pre-window and find the 03075 store + the
    // read/op that produced 0377 (6t: char is read from 03075, faithful; packed
    // word 0x5255 never read live during print per WORD2b).
    g_groups["WORD2W"] = { "UART_DIN", "UART_CE_n", "UART_WR", "UART_ADDR",
                           "MEMRD_ADDR", "MEMRD_DATA", "CD16", "DBR",
                           "RA", "RT", "RD", "RB", "RX", "CBWRITE", "CMWRITE",
                           "CSA_12_0" };
}

// Try to resolve+read a signal by VPI dotted name. Returns ok=false if the VPI
// layer cannot see it (we then know to rely on the registry floor).
static bool vpiReadDotted(const std::string &dotted, uint64_t &out, int &width)
{
    vpiHandle h = nullptr;
    auto it = g_vpiCache.find(dotted);
    if (it != g_vpiCache.end()) {
        h = it->second;
    } else {
        // Verilator's VPI top scope naming can differ; try a few candidates.
        std::vector<std::string> cands = { dotted };
        if (dotted.rfind("ND120_TOP.", 0) == 0)
            cands.push_back("TOP." + dotted);                 // some builds prefix TOP.
        cands.push_back("TOP." + dotted);
        for (auto &c : cands) {
            h = vpi_handle_by_name((PLI_BYTE8 *)c.c_str(), NULL);
            if (h) break;
        }
        g_vpiCache[dotted] = h;   // cache even nullptr to avoid repeated lookups
    }
    if (!h) return false;
    width = (int)vpi_get(vpiSize, h);
    s_vpi_value v; v.format = vpiIntVal;
    vpi_get_value(h, &v);
    out = (uint32_t)v.value.integer;
    return true;
}

// Read a signal by friendly/dotted name. Registry first (floor), then VPI.
static SigVal readSignal(const std::string &name)
{
    auto rit = g_registry.find(name);
    if (rit != g_registry.end())
        return { rit->second.read(), rit->second.width, true };

    // Map friendly alias -> dotted VPI path if we have one, else use name as-is.
    std::string dotted = name;
    auto ait = g_alias.find(name);
    if (ait != g_alias.end()) dotted = ait->second;

    uint64_t v = 0; int w = 0;
    if (vpiReadDotted(dotted, v, w)) return { v, w, true };
    return { 0, 0, false };
}

// ===========================================================================
//  EXPRESSION PARSER  ->  AST  (rule conditions over ANY signal combination)
// ===========================================================================
// Grammar (low->high precedence):
//   or   := and   ('||' and)*
//   and  := cmp   ('&&' cmp)*
//   cmp  := unary (('=='|'!='|'<='|'>='|'<'|'>') unary)?
//   unary:= '!' unary | primary
//   prim := number | signal | '(' or ')'
//   signal := IDENT ['[' hi ':' lo ']']
//   number := 'o'[0-7]+ | '0x'[0-9a-f]+ | [0-9]+
struct Node {
    enum Kind { LIT, SIG, UNOP, BINOP } kind;
    int64_t     lit = 0;
    std::string sig;          // signal name (friendly or dotted)
    int         hi = -1, lo = -1; // optional bit-select
    std::string op;           // operator string for UNOP/BINOP
    Node *l = nullptr, *r = nullptr;
};

// Explicit node factories (avoid aggregate init: Node has default member
// initializers, so it is NOT an aggregate under C++14 - a braced init would
// fail to compile depending on the Verilator C++ standard).
static Node *newBin(const std::string &op, Node *l, Node *r) { Node *p=new Node(); p->kind=Node::BINOP; p->op=op; p->l=l; p->r=r; return p; }
static Node *newUn (const std::string &op, Node *c)          { Node *p=new Node(); p->kind=Node::UNOP;  p->op=op; p->l=c; return p; }
static Node *newLit(int64_t v)                               { Node *p=new Node(); p->kind=Node::LIT;   p->lit=v; return p; }
static Node *newSig(const std::string &nm, int hi, int lo)   { Node *p=new Node(); p->kind=Node::SIG;   p->sig=nm; p->hi=hi; p->lo=lo; return p; }

struct Parser {
    std::vector<std::string> toks;
    size_t pos = 0;
    std::vector<std::string> *refSigs = nullptr; // collect referenced signal names
    std::string err;

    bool ok() { return err.empty(); }
    const std::string &peek() { static std::string e; e.clear(); return pos < toks.size() ? toks[pos] : e; }
    std::string next() { return pos < toks.size() ? toks[pos++] : std::string(); }

    Node *parseOr() {
        Node *l = parseAnd();
        while (ok() && peek() == "||") { next(); Node *r = parseAnd(); l = newBin("||", l, r); }
        return l;
    }
    Node *parseAnd() {
        Node *l = parseCmp();
        while (ok() && peek() == "&&") { next(); Node *r = parseCmp(); l = newBin("&&", l, r); }
        return l;
    }
    Node *parseCmp() {
        Node *l = parseUnary();
        std::string o = peek();
        if (o=="=="||o=="!="||o=="<="||o==">="||o=="<"||o==">") {
            next(); Node *r = parseUnary(); return newBin(o, l, r);
        }
        return l;
    }
    Node *parseUnary() {
        if (peek() == "!") { next(); Node *c = parseUnary(); return newUn("!", c); }
        return parsePrim();
    }
    Node *parsePrim() {
        std::string t = peek();
        if (t == "(") { next(); Node *e = parseOr(); if (peek()==")") next(); else err="missing )"; return e; }
        if (t.empty()) { err = "unexpected end"; return newLit(0); }
        // number?
        char c0 = t[0];
        if ((c0>='0'&&c0<='9') || c0=='o') {
            next();
            int64_t v = 0;
            if (t[0]=='o')               v = strtoll(t.c_str()+1, nullptr, 8);
            else if (t.rfind("0x",0)==0) v = strtoll(t.c_str()+2, nullptr, 16);
            else                         v = strtoll(t.c_str(), nullptr, 10);
            return newLit(v);
        }
        // signal name (already tokenized WITH any [hi:lo])
        next();
        int hi=-1, lo=-1; std::string name = t;
        size_t br = t.find('[');
        if (br != std::string::npos) {
            name = t.substr(0, br);
            std::string range = t.substr(br+1, t.find(']',br)-br-1);
            size_t colon = range.find(':');
            if (colon != std::string::npos) { hi=atoi(range.substr(0,colon).c_str()); lo=atoi(range.substr(colon+1).c_str()); }
            else { hi = lo = atoi(range.c_str()); }
        }
        if (refSigs) refSigs->push_back(name);
        return newSig(name, hi, lo);
    }
};

// Tokenize an expression string. Signal identifiers keep an attached [hi:lo].
static std::vector<std::string> tokenize(const std::string &s)
{
    std::vector<std::string> out; size_t i = 0, n = s.size();
    while (i < n) {
        char c = s[i];
        if (isspace((unsigned char)c)) { i++; continue; }
        if (c=='&'&&i+1<n&&s[i+1]=='&') { out.push_back("&&"); i+=2; continue; }
        if (c=='|'&&i+1<n&&s[i+1]=='|') { out.push_back("||"); i+=2; continue; }
        if ((c=='='||c=='!'||c=='<'||c=='>') && i+1<n && s[i+1]=='=') { out.push_back(std::string()+c+"="); i+=2; continue; }
        if (c=='!'||c=='<'||c=='>'||c=='('||c==')') { out.push_back(std::string(1,c)); i++; continue; }
        // identifier (signal, may contain . _ digits) with optional [..], OR number
        if (isalnum((unsigned char)c) || c=='_' || c=='.') {
            size_t j = i;
            while (j<n && (isalnum((unsigned char)s[j])||s[j]=='_'||s[j]=='.')) j++;
            if (j<n && s[j]=='[') { size_t k = s.find(']', j); if (k!=std::string::npos) j = k+1; }
            out.push_back(s.substr(i, j-i)); i = j; continue;
        }
        i++; // skip anything unexpected
    }
    return out;
}

// Evaluate an AST node to an int64. Signal reads use readSignal() + bit-select.
static int64_t evalNode(Node *n, bool &ok)
{
    if (!n) return 0;
    switch (n->kind) {
    case Node::LIT: return n->lit;
    case Node::SIG: {
        SigVal s = readSignal(n->sig);
        if (!s.ok) { ok = false; return 0; }
        uint64_t v = s.val;
        if (n->hi >= 0) { int hi=n->hi, lo=n->lo; uint64_t mask = (hi-lo>=63)?~0ULL:((1ULL<<(hi-lo+1))-1); v = (v>>lo)&mask; }
        return (int64_t)v;
    }
    case Node::UNOP: return !evalNode(n->l, ok);
    case Node::BINOP: {
        int64_t a = evalNode(n->l, ok), b = evalNode(n->r, ok);
        const std::string &o = n->op;
        if (o=="&&") return a && b;
        if (o=="||") return a || b;
        if (o=="==") return a == b;
        if (o=="!=") return a != b;
        if (o=="<")  return a <  b;
        if (o=="<=") return a <= b;
        if (o==">")  return a >  b;
        if (o==">=") return a >= b;
        return 0;
    }
    }
    return 0;
}

// ===========================================================================
//  RULE ENGINE
// ===========================================================================
struct Rule {
    std::string name;
    std::string exprText;
    Node       *ast = nullptr;
    std::vector<std::string> refSigs;   // signals named in the condition (for LOG)
    std::vector<std::pair<std::string,std::string>> actions; // (action, arg)
    bool level = false;                 // level-triggered (default = rising edge)
    bool prev  = false;                 // previous condition state (edge detect)
};
static std::vector<Rule> g_rules;
static long g_eventId = 0;
static bool g_stopRequested = false;

// Format a CSV row (tick + each watched signal, octal) for the current state.
static std::string formatCsvRow()
{
    std::string row = std::to_string(g_globalTick);
    char buf[32];
    for (auto &nm : g_watch) {
        SigVal s = readSignal(nm);
        if (s.ok) snprintf(buf, sizeof buf, ",%llo", (unsigned long long)s.val);
        else      snprintf(buf, sizeof buf, ",?");
        row += buf;
    }
    return row;
}

// Flush the PRE ring to the CSV file and arm the POST live-write window.
static void csvTrigger()
{
    if (!g_csvFile) return;
    if (!g_csvHeaderWritten) {
        fprintf(g_csvFile, "tick");
        for (auto &nm : g_watch) fprintf(g_csvFile, ",%s", nm.c_str());
        fprintf(g_csvFile, "\n");
        g_csvHeaderWritten = true;
    }
    for (auto &r : g_ring) fprintf(g_csvFile, "%s\n", r.c_str());
    g_ring.clear();
    g_postRemaining = g_post;
    fflush(g_csvFile);
}

// Per-tick CSV sampler: keep a rolling PRE ring, or write live during POST.
static void sampleCsv()
{
    if (!g_csvFile || g_watch.empty()) return;
    std::string row = formatCsvRow();
    if (g_postRemaining > 0) {
        fprintf(g_csvFile, "%s\n", row.c_str());
        if (--g_postRemaining == 0) fflush(g_csvFile);
    } else {
        g_ring.push_back(row);
        while ((int)g_ring.size() > g_pre) g_ring.pop_front();
    }
}

// Execute a rule's actions when it fires. Returns true if a `stop` action ran.
static bool fireRule(Rule &r)
{
    bool stop = false;
    long id = ++g_eventId;
    for (auto &a : r.actions) {
        const std::string &act = a.first, &arg = a.second;
        if (act == "log") {
            printf("LOG rule=%s tick=%ld", r.name.c_str(), g_globalTick);
            if (!arg.empty()) printf(" msg=\"%s\"", arg.c_str());
            for (auto &sn : r.refSigs) { SigVal s = readSignal(sn); if (s.ok) printf(" %s=%llo", sn.c_str(), (unsigned long long)s.val); }
            printf("\n");
        } else if (act == "fst_on") {
            g_fstEnabled = true;  printf("LOG rule=%s tick=%ld fst=on\n",  r.name.c_str(), g_globalTick);
        } else if (act == "fst_off") {
            g_fstEnabled = false; printf("LOG rule=%s tick=%ld fst=off\n", r.name.c_str(), g_globalTick);
        } else if (act == "csv") {
            csvTrigger();
            printf("EVENT id=%ld trig=%s tick=%ld wrote=csv#rows=%d\n", id, r.name.c_str(), g_globalTick, g_pre + g_post);
        } else if (act == "event") {
            printf("EVENT id=%ld trig=%s tick=%ld\n", id, r.name.c_str(), g_globalTick);
        } else if (act == "mark") {
            if (g_csvFile) { fprintf(g_csvFile, "# MARK %s tick=%ld\n", arg.c_str(), g_globalTick); fflush(g_csvFile); }
            printf("EVENT id=%ld trig=%s tick=%ld mark=%s\n", id, r.name.c_str(), g_globalTick, arg.c_str());
        } else if (act == "stop") {
            stop = true; printf("EVENT id=%ld trig=%s tick=%ld stop=1\n", id, r.name.c_str(), g_globalTick);
        }
    }
    fflush(stdout);
    return stop;
}

// Evaluate every rule after the tick settles. Rising-edge unless `level`.
static bool evalRules()
{
    bool stop = false;
    for (auto &r : g_rules) {
        if (!r.ast) continue;
        bool ok = true;
        bool cond = evalNode(r.ast, ok) != 0;
        if (!ok) { r.prev = false; continue; }   // unresolved signal -> never fires
        bool fire = r.level ? cond : (cond && !r.prev);
        r.prev = cond;
        if (fire) stop = fireRule(r) || stop;
    }
    return stop;
}

// ===========================================================================
//  UART console (faithful bit timing from test_nd120.cpp), optional
// ===========================================================================
static void serviceUartTx()
{
    // INTER-CHARACTER PACING GAP - critical, do not remove.
    // MOPC (the ND console monitor) has NO RX FIFO: characters delivered
    // back-to-back are silently DROPPED. A fast-typed "1560&" then arrives
    // mangled - the "1560" digits are lost and only the bare "&" survives, so
    // the autoload runs from the ALD register (=400 => the PAPERTAPE device,
    // which is armed with INSTRUCTION-B.BPUN in NDDevices.cpp) instead of the
    // floppy at 1560. Symptom: the probe boots INSTRUCTION-B / ND-100/CX
    // instead of the real TPE Monitor. Fix mirrors runSim/Run120.cpp's
    // ND120_STDIN_GAP: hold each queued char until a gap has elapsed since the
    // previous one finished. Tunable via ND120_SEND_GAP (default 300000, in
    // serviceUartTx-call ticks - same time base as Run120's cnt gap).
    static long s_gap      = -1;         // -1 = not yet read from env
    static long s_gap_wait = 0;          // ticks remaining before the next char may start
    if (s_gap < 0) { const char *e = getenv("ND120_SEND_GAP"); s_gap = e ? atol(e) : 300000; }

    if (!txEnabled) {
        if (s_gap_wait > 0) { s_gap_wait--; return; }   // still waiting out the inter-char gap
        if (!g_txq.empty()) { txData = (int)g_txq.front(); g_txq.pop(); txEnabled = 1; txDataBit = 0; txTicks = 0; txOnes = 0; }
    }
    if (txEnabled) {
        if (txTicks > 0) { txTicks--; return; }
        switch (txDataBit) {
        case 0: txTicks = DELAY_FRAMES-1; g_top->uartRx = 0; break;            // start bit
        case 1: case 2: case 3: case 4: case 5: case 6: case 7:
            if (txData & 1) { g_top->uartRx = 1; txOnes++; } else g_top->uartRx = 0;
            txData >>= 1; txTicks = DELAY_FRAMES-1; break;
        case 8: g_top->uartRx = 0; txTicks = DELAY_FRAMES-1; break;            // parity slot
        case 9: case 10: txTicks = DELAY_FRAMES-1; g_top->uartRx = 1; break;   // stop bits
        case 11: txData = 0; txEnabled = 0; s_gap_wait = s_gap; break;         // char done: arm inter-char gap
        }
        txDataBit++;
    }
}

static void serviceUartRx()
{
    if ((g_top->uartTx == 0) && !rxEnabled) { rxEnabled = 1; rxDataBit = 0; rxData = 0; rxOnes = 0; rxTicks = HALF_DELAY_WAIT; }
    if (!rxEnabled) return;
    if (rxTicks > 0) { rxTicks--; return; }
    switch (rxDataBit) {
    case 0: rxTicks = DELAY_FRAMES; if (g_top->uartTx == 1) rxEnabled = 0; break;
    case 1: case 2: case 3: case 4: case 5: case 6: case 7:
        if (g_top->uartTx != 0) { rxOnes++; rxData |= (1 << (rxDataBit-1)); } rxTicks = DELAY_FRAMES; break;
    case 8: rxTicks = DELAY_FRAMES; break;
    case 9: case 10: rxTicks = DELAY_FRAMES; break;
    case 11:
        // Full character received: mirror to stderr and console buffer so the
        // Python driver's wait_console() can match on emulated terminal output.
        fputc((char)rxData, stderr); fflush(stderr);
        g_console.push_back((char)rxData);
        g_lastTxByte = (int)(unsigned char)rxData;   // expose for TXBYTE/TXSTROBE rules
        g_txStrobe = 1;                              // 1-tick pulse; cleared after evalRules
        rxData = 0; rxEnabled = 0; break;
    }
    rxDataBit++;
}

// ===========================================================================
//  ONE SIMULATION TICK  (mirrors test_nd120's half-clock structure exactly)
// ===========================================================================
static bool step()
{
    g_top->btn1 = (g_globalTick >= g_resetReleaseTick);   // sys_rst_n release schedule

    g_top->eval();
    g_top->sysclk = !g_top->sysclk;
    proccess_bif_signal(g_top);                            // reuse bus/UART engine
    serviceUartTx();
    if (g_fstEnabled && g_trace) { g_trace->dump(g_simTime); g_simTime += g_timeStep; }

    g_top->eval();
    g_top->sysclk = !g_top->sysclk;
    serviceUartRx();
    if (g_fstEnabled && g_trace) { g_trace->dump(g_simTime); g_simTime += g_timeStep; }

    sampleCsv();                                           // CSV ring/POST (settled)
    bool stop = evalRules();                               // rules (settled)
    g_txStrobe = 0;                                        // TXSTROBE is a 1-tick pulse
    g_globalTick++;
    return stop;
}

// ===========================================================================
//  COMMAND DISPATCH  (line protocol)
// ===========================================================================
static std::vector<std::string> splitWs(const std::string &s)
{
    std::vector<std::string> v; size_t i=0,n=s.size();
    while (i<n) { while (i<n && isspace((unsigned char)s[i])) i++; size_t j=i; while (j<n && !isspace((unsigned char)s[j])) j++; if (j>i) v.push_back(s.substr(i,j-i)); i=j; }
    return v;
}

// Extract a "quoted string" starting at position `from` in line; returns content.
static std::string extractQuoted(const std::string &line, size_t from, size_t &endOut)
{
    size_t q1 = line.find('"', from);
    if (q1 == std::string::npos) { endOut = from; return ""; }
    size_t q2 = line.find('"', q1+1);
    if (q2 == std::string::npos) { endOut = line.size(); return line.substr(q1+1); }
    endOut = q2+1;
    return line.substr(q1+1, q2-q1-1);
}

// Parse an action list like  log:"hi",fst_on,csv,stop  into (action,arg) pairs.
static std::vector<std::pair<std::string,std::string>> parseActions(const std::string &spec)
{
    std::vector<std::pair<std::string,std::string>> acts;
    size_t i=0, n=spec.size();
    while (i<n) {
        while (i<n && (spec[i]==','||isspace((unsigned char)spec[i]))) i++;
        size_t j=i; while (j<n && spec[j]!=',' && spec[j]!=':') j++;
        std::string a = spec.substr(i, j-i);
        std::string arg;
        if (j<n && spec[j]==':') {
            if (j+1<n && spec[j+1]=='"') { size_t e; arg = extractQuoted(spec, j, e); j = e; }
            else { size_t k=j+1; while (k<n && spec[k]!=',') k++; arg = spec.substr(j+1,k-j-1); j=k; }
        }
        if (!a.empty()) acts.push_back({a, arg});
        i = j;
    }
    return acts;
}

static Rule buildRule(const std::string &name, const std::string &exprText,
                      const std::vector<std::pair<std::string,std::string>> &acts, bool level)
{
    Rule r; r.name = name; r.exprText = exprText; r.actions = acts; r.level = level;
    Parser p; p.toks = tokenize(exprText); p.refSigs = &r.refSigs;
    r.ast = p.parseOr();
    if (!p.ok()) { r.ast = nullptr; }
    return r;
}

static void openFst(const std::string &path)
{
    if (!g_trace) {
        Verilated::traceEverOn(true);
        g_trace = new VerilatedFstC;
        g_top->trace(g_trace, 99);            // FULL hierarchy (windowed by fstEnabled)
        g_trace->open(path.c_str());
    }
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    g_top = new VND120_TOP;
    addDevices();                              // ND bus devices (reuse)
    buildRegistry();

    // RAM backdoor pointers (same paths as test_nd120.cpp).
    g_ram_lo   = &g_top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__RAM__DOT__b0_lo[0];
    g_ram_lo_p = &g_top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__RAM__DOT__b0_lo_p[0];
    g_ram_hi   = &g_top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__RAM__DOT__b0_hi[0];
    g_ram_hi_p = &g_top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__RAM__DOT__b0_hi_p[0];

    // Bus / interrupt input defaults (identical to test_nd120.cpp).
    g_top->btn1 = false; g_top->uartRx = 1;
    g_top->BD_23_0_n_IN = 0xFFFFFF;
    g_top->BREQ_n = 1; g_top->BINT10_n = 1; g_top->BINT11_n = 1; g_top->BINT12_n = 1;
    g_top->BINT13_n = 1; g_top->BINT15_n = 1; g_top->POWSENSE_n = 1;
    g_top->SEMRQ_n_IN = 1; g_top->BINPUT_n_IN = 1; g_top->BDAP_n_IN = 1;
    g_top->BDRY_n_IN = 1; g_top->BAPR_n_IN = 1; g_top->DEBUGFLAG = 0;

    printf("OK probe ready (build FF-mode default; registry=%zu groups=%zu)\n",
           g_registry.size(), g_groups.size());
    fflush(stdout);

    std::string line;
    char cbuf[4096];
    while (fgets(cbuf, sizeof cbuf, stdin)) {
        line.assign(cbuf);
        while (!line.empty() && (line.back()=='\n'||line.back()=='\r')) line.pop_back();
        auto tok = splitWs(line);
        if (tok.empty()) continue;
        const std::string &cmd = tok[0];

        if (cmd == "quit" || cmd == "exit") { printf("OK bye\n"); fflush(stdout); break; }

        else if (cmd == "load") {
            if (tok.size() < 2) { printf("ERR load needs <path>\n"); }
            else {
                char *fn = strdup(tok[1].c_str());
                loadfile(fn, 0, g_ram_lo, g_ram_lo_p, g_ram_hi, g_ram_hi_p);
                free(fn);
                printf("OK load %s\n", tok[1].c_str());
            }
        }
        else if (cmd == "deposit") {
            if (tok.size() < 3) { printf("ERR deposit <octal-addr> <octal-val>\n"); }
            else {
                long addr = strtol(tok[1].c_str(), nullptr, 8);
                long val  = strtol(tok[2].c_str(), nullptr, 8);
                g_ram_lo[addr] = val & 0xFF; g_ram_hi[addr] = (val>>8)&0xFF;
                g_ram_lo_p[addr] = calc_parity(g_ram_lo[addr]);
                g_ram_hi_p[addr] = calc_parity(g_ram_hi[addr]);
                printf("OK deposit %lo=%lo\n", addr, val);
            }
        }
        else if (cmd == "examine") {
            if (tok.size() < 2) { printf("ERR examine <octal-addr>\n"); }
            else {
                long addr = strtol(tok[1].c_str(), nullptr, 8);
                unsigned val = (g_ram_hi[addr] << 8) | g_ram_lo[addr];
                printf("VAL %lo %o\n", addr, val);
            }
        }
        else if (cmd == "scanseq") {
            // scanseq <hi-octal-bound> <w0> <w1> ... : C-side RAM scan (fast) for a
            // run of consecutive octal words; prints each match addr + next 4 words.
            if (tok.size() < 3) { printf("ERR scanseq <hi-oct> <w0> [w1..]\n"); }
            else {
                long hi = strtol(tok[1].c_str(), nullptr, 8);
                int nw = (int)tok.size() - 2;
                unsigned pat[16]; if (nw > 16) nw = 16;
                for (int i = 0; i < nw; i++) pat[i] = (unsigned)strtol(tok[2+i].c_str(), nullptr, 8);
                int hits = 0;
                for (long a = 0; a + nw + 4 < hi; a++) {
                    bool ok = true;
                    for (int i = 0; i < nw; i++) {
                        unsigned w = (g_ram_hi[a+i] << 8) | g_ram_lo[a+i];
                        if (w != pat[i]) { ok = false; break; }
                    }
                    if (ok) {
                        printf("HIT %lo next", a);
                        for (int i = 0; i < 5; i++)
                            printf(" %o", (g_ram_hi[a+nw+i] << 8) | g_ram_lo[a+nw+i]);
                        printf("\n");
                        if (++hits >= 8) break;
                    }
                }
                printf("OK scanseq hits=%d\n", hits);
            }
        }
        else if (cmd == "rtc") {
            // rtc [<20ms-cycles> [<5ms-cycles>]] - retune the simulation RTC period
            // at runtime. The boot is RTC-paced (OPCOM services one character per
            // RTC tick), so booting at the fast default and only then slowing the
            // clock is far cheaper than a slow build-time period. Omitting the
            // 5 ms value keeps the 4:1 ratio. No argument = report current values.
#ifdef ND120_RTC_RUNTIME
            // Only compiled when the RTL provides the writable period regs
            // (build with -DND120_RTC_RUNTIME alongside the matching RTL). Keeps
            // the probe buildable against unmodified RTL, where these members
            // do not exist.
            if (tok.size() >= 2) {
                unsigned long v20 = strtoul(tok[1].c_str(), nullptr, 10);
                unsigned long v5  = (tok.size() >= 3) ? strtoul(tok[2].c_str(), nullptr, 10) : (v20 / 4);
                g_top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__POW__DOT__s_rtc_20ms_var = (uint32_t)(v20 & 0x1FFFFF);
                g_top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__POW__DOT__s_rtc_5ms_var  = (uint32_t)(v5  & 0x1FFFFF);
            }
            printf("OK rtc 20ms=%u 5ms=%u\n",
                   (unsigned)g_top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__POW__DOT__s_rtc_20ms_var,
                   (unsigned)g_top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__POW__DOT__s_rtc_5ms_var);
#else
            (void)tok;
            printf("ERR rtc unsupported (build engine with -DND120_RTC_RUNTIME and matching RTL)\n");
#endif
        }
        else if (cmd == "get") {
            if (tok.size() < 2) { printf("ERR get <signal>\n"); }
            else {
                SigVal s = readSignal(tok[1]);
                if (s.ok) printf("VAL %s %llo\n", tok[1].c_str(), (unsigned long long)s.val);
                else      printf("ERR get %s unresolved (not in registry, VPI failed)\n", tok[1].c_str());
            }
        }
        else if (cmd == "watch") {
            if (tok.size() >= 2 && tok[1] == "clear") { g_watch.clear(); g_ring.clear(); g_csvHeaderWritten=false; printf("OK watch clear\n"); }
            else if (tok.size() >= 3 && tok[1] == "add") { g_watch.push_back(tok[2]); printf("OK watch add %s\n", tok[2].c_str()); }
            else if (tok.size() >= 3 && tok[1] == "group") {
                auto git = g_groups.find(tok[2]);
                if (git == g_groups.end()) printf("ERR unknown group %s\n", tok[2].c_str());
                else {
                    int added=0, missing=0;
                    for (auto &nm : git->second) { SigVal s = readSignal(nm); g_watch.push_back(nm); added++; if (!s.ok) missing++; }
                    printf("OK watch group %s added=%d unresolved=%d\n", tok[2].c_str(), added, missing);
                }
            }
            else printf("ERR watch <add sig | group NAME | clear>\n");
        }
        else if (cmd == "set") {
            if (tok.size() >= 3 && tok[1] == "pre")  { g_pre  = atoi(tok[2].c_str()); printf("OK set pre %d\n", g_pre); }
            else if (tok.size() >= 3 && tok[1] == "post") { g_post = atoi(tok[2].c_str()); printf("OK set post %d\n", g_post); }
            else printf("ERR set <pre|post> N\n");
        }
        else if (cmd == "capture" || cmd == "open") {
            // open <csv> == capture csv <csv>
            std::string kind, path;
            if (cmd == "open") { kind = "csv"; path = tok.size()>1?tok[1]:""; }
            else if (tok.size() >= 2) { kind = tok[1]; path = tok.size()>2?tok[2]:""; }
            if (kind == "csv") {
                if (g_csvFile) fclose(g_csvFile);
                g_csvFile = fopen(path.c_str(), "w"); g_csvHeaderWritten=false;
                if (g_csvFile) printf("OK capture csv %s\n", path.c_str()); else printf("ERR cannot open %s\n", path.c_str());
            } else if (kind == "fst") {
                openFst(path); printf("OK capture fst %s\n", path.c_str());
            } else if (kind == "off") {
                g_fstEnabled=false; if (g_csvFile){fclose(g_csvFile);g_csvFile=nullptr;} printf("OK capture off\n");
            } else printf("ERR capture <csv PATH | fst PATH | off>\n");
        }
        else if (cmd == "rule") {
            if (tok.size() >= 3 && tok[1] == "clear") {
                if (tok[2] == "all") { g_rules.clear(); printf("OK rule clear all\n"); }
                else { size_t before=g_rules.size(); std::vector<Rule> keep; for (auto &r:g_rules) if (r.name!=tok[2]) keep.push_back(r); g_rules=keep; printf("OK rule clear %s removed=%zu\n", tok[2].c_str(), before-g_rules.size()); }
            }
            else if (tok.size() >= 4 && tok[1] == "add") {
                // rule add <name> [level] when "<expr>" do <acts>
                std::string name = tok[2];
                bool level = (line.find(" level ") != std::string::npos);
                size_t wpos = line.find(" when ");
                size_t dpos = line.find(" do ");
                if (wpos==std::string::npos || dpos==std::string::npos) { printf("ERR rule add <name> when \"<expr>\" do <acts>\n"); }
                else {
                    size_t qend; std::string expr = extractQuoted(line, wpos, qend);
                    std::string actSpec = line.substr(dpos+4);
                    auto acts = parseActions(actSpec);
                    if (acts.empty()) acts.push_back({"event",""});
                    Rule r = buildRule(name, expr, acts, level);
                    if (!r.ast) printf("ERR rule %s: parse error in \"%s\"\n", name.c_str(), expr.c_str());
                    else { g_rules.push_back(r); printf("OK rule add %s (refs=%zu acts=%zu%s)\n", name.c_str(), r.refSigs.size(), acts.size(), level?" level":""); }
                }
            }
            else printf("ERR rule <add ...| clear NAME|all>\n");
        }
        else if (cmd == "run") {
            long ticks = tok.size()>1 ? strtol(tok[1].c_str(), nullptr, 10) : 1;
            g_stopRequested = false;
            long done=0;
            for (long k=0; k<ticks; k++) { if (step()) { g_stopRequested=true; done=k+1; break; } done=k+1; }
            printf("OK run ticks=%ld tick=%ld stop=%d\n", done, g_globalTick, g_stopRequested?1:0);
        }
        else if (cmd == "runto") {
            // runto "<expr>" [maxticks]  -> one-shot rule with event+stop
            size_t qend; std::string expr = extractQuoted(line, 5, qend);
            long maxt = 1000000;
            std::string rest = qend < line.size() ? line.substr(qend) : "";
            auto rtok = splitWs(rest);
            if (!rtok.empty()) maxt = strtol(rtok[0].c_str(), nullptr, 10);
            if (expr.empty()) { printf("ERR runto \"<expr>\" [maxticks]\n"); }
            else {
                std::vector<std::pair<std::string,std::string>> acts = {{"event",""},{"stop",""}};
                Rule r = buildRule("__runto__", expr, acts, false);
                if (!r.ast) { printf("ERR runto parse error\n"); }
                else {
                    g_rules.push_back(r);
                    long done=0; bool hit=false;
                    for (long k=0; k<maxt; k++) { if (step()) { hit=true; done=k+1; break; } done=k+1; }
                    // remove the temp rule
                    std::vector<Rule> keep; for (auto &rr:g_rules) if (rr.name!="__runto__") keep.push_back(rr); g_rules=keep;
                    printf("OK runto ticks=%ld tick=%ld hit=%d\n", done, g_globalTick, hit?1:0);
                }
            }
        }
        else if (cmd == "reset") {
            g_resetReleaseTick = g_globalTick + 100;   // pulse sys_rst_n low for 100 ticks
            printf("OK reset (release at tick %ld)\n", g_resetReleaseTick);
        }
        else if (cmd == "send") {
            // send <text...> (queue chars to UART TX). CR available as \r literal.
            size_t sp = line.find(' ');
            std::string txt = sp==std::string::npos ? "" : line.substr(sp+1);
            std::string out; for (size_t i=0;i<txt.size();i++){ if (txt[i]=='\\'&&i+1<txt.size()&&txt[i+1]=='r'){out.push_back('\r');i++;} else out.push_back(txt[i]); }
            for (char c : out) g_txq.push(c);
            printf("OK send %zu chars\n", out.size());
        }
        else if (cmd == "console") {
            // dump accumulated emulated-terminal output as a VAL line (length-prefixed)
            printf("VAL console len=%zu\n", g_console.size());
        }
        else if (cmd == "groups") {
            printf("OK groups");
            for (auto &g : g_groups) printf(" %s", g.first.c_str());
            printf("\n");
        }
        else if (cmd == "signals") {
            printf("OK signals");
            for (auto &s : g_registry) printf(" %s", s.first.c_str());
            for (auto &a : g_alias)    printf(" %s", a.first.c_str());
            printf("\n");
        }
        else {
            printf("ERR unknown command '%s'\n", cmd.c_str());
        }
        fflush(stdout);
    }

    if (g_trace) { g_trace->dump(g_simTime); g_simTime += g_timeStep; g_trace->close(); }
    if (g_csvFile) fclose(g_csvFile);
    g_top->final();
    delete g_top;
    return 0;
}
