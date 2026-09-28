/**************************************************************************
** ND120 SIMULATOR                                                       **
**                                                                       **
** Steps the Verilator TOP module                                        **
** Handles console I/O                                                   **
** Connects to Bus Interface devices                                     **
**                                                                       **
** Can load INITIAL BPUN directly into memory                            **
**                                                                       **
** Last reviewed: 22-MAR-2024                                            **
** Ronny Hansen                                                          **
***************************************************************************/

// Run SIMULATOR
// Runs the FPGA CPU in the console and lets you do console input and output via keyboard

// #define DO_TRACE
#include <iostream>
#include <vector>
#include <random>
#include <ctime>
#include <string>
#include <map>
#include <cstring>

#include <unistd.h>
#include <termios.h>
#include <fcntl.h>

#include "VND120_TOP.h"
#include "VND120_TOP___024root.h" // Root-level details for updating RAM directly
#include "verilated.h"

#ifdef DO_TRACE
#include <verilated_vcd_c.h>
#endif

#include "NDBus.h"
#include "NDDevices.h"
#include "NDConsoleScript.h"   // runtime OPCOM script override (ND120_SCRIPT / ND120_SCRIPT_FILE)

// Save the original terminal settings
struct termios orig_termios;

// BPUN load file logic
void loadfile(char *fn, int off, uint8_t *low_array, uint8_t *low_array9, uint8_t *high_array, uint8_t *high_array9);

// Function to restore terminal settings
void restore_terminal()
{
	tcsetattr(STDIN_FILENO, TCSANOW, &orig_termios);
}
// Function to set terminal to non-blocking mode
void set_nonblocking_terminal()
{
	struct termios new_termios;

	// Get the current terminal settings
	tcgetattr(STDIN_FILENO, &orig_termios);
	// Register a cleanup function to restore the settings on exit
	atexit(restore_terminal);

	new_termios = orig_termios;

	// Disable canonical mode and echo
	new_termios.c_lflag &= ~(ICANON | ECHO);

	// Apply the new terminal settings
	tcsetattr(STDIN_FILENO, TCSANOW, &new_termios);

	// Set the file descriptor to non-blocking mode
	int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
	fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
}

// Array of descriptions corresponding to each LED flag
const char *LED_DESCRIPTION[6] = {
	"CPU Red LED",				   // CPU_RED (1 << 0)
	"CPU Green LED",			   // CPU_GREEN (1 << 1)
	"Parity Error LED (LED4 Red)", // LED4_RED_PARITY_ERROR (1 << 2)
	"CPU Grant Indicator LED",	   // LED_CPU_GRANT_INDICATOR (1 << 3)
	"Bus Grant Indicator LED",	   // LED_BUS_GRANT_INDICATOR (1 << 4)
	"MMU LED1"					   // MMU_LED1 (1 << 5)
};

// Led contains the bits with current state, changed contains bits for which led changed state
void DumpLedInfo(uint8_t led, uint8_t changed)
{
	bool first = true;
	for (int i = 0; i < 6; ++i)
	{ // There are 6 LED signals
		int flag = 1 << i;

		if (changed & flag)
		{							// Check if this LED's state has changed
			bool isOn = led & flag; // Determine if it's now ON or OFF
			std::cout << (first ? "" : ", ") << LED_DESCRIPTION[i]
					  << " changed from " << (isOn ? "OFF to ON" : "ON to OFF");
			first = false;
		}
	}
	if (!first)
	{
		std::cout << std::endl; // Print a newline if any changes were printed
	}
}

#define MAX_SIM_TIME 20
vluint64_t sim_time = 0;
vluint64_t time_step = 5;

int DELAY_FRAMES = 16;					   // 16 frames
int HALF_DELAY_WAIT = (DELAY_FRAMES >> 1); // Equivalent to DELAY_FRAMES / 2

// --- FF-vs-latch divergence instrumentation (build with EXTRA_CFLAGS) ---
// -DSCRIPT_INPUT : after the boot '#' prompt, auto-inject a scripted command
// -DTRACE_CSA    : log CSA_12_0 changes (post-boot) to csa_trace.csv
// -DTRACE_CSA_BOOT : the same, but from cycle 0 - includes the boot itself,
//                    which is what you want when comparing against a board
//                    that never finishes booting
static int g_boot_done_cnt = 0;    // cnt when first '#' output (0 = not yet)
// Interactive stdin pacing (see the read() gate in the main loop): the sim
// runs much slower than wall time, so typed or piped chars pile up in the
// stdin buffer and would reach the console UART back-to-back. MOPC has no
// RX FIFO and drops them - a fast-typed "1560&" arrives mangled and the
// boot goes to a garbage address. Feed at most one char per gap instead.
static long g_stdin_next_cnt = 0;  // don't consume the next stdin char before this cnt
static long g_stdin_gap = 300000;  // min cnt between stdin chars (ND120_STDIN_GAP)
static long g_max_cnt = 0;         // 0 = run forever; ND120_MAX_CNT bounds a test run
// After a '&' boot command the loaded program owns the console, but it
// only reads the UART once it is up - chars typed during the load are
// lost (no RX FIFO anywhere). A human waits for the program's greeting
// before typing; the injectors do the same: after '&', hold input until
// a full output line has arrived AND the console has been quiet a while.
static long g_last_rx_cnt = 0;     // cnt of the most recent console output char
static long g_rx_lf_total = 0;     // total newlines seen on console output
static long g_lf_at_mark = -1;     // g_rx_lf_total when '&' was sent (-1 = not waiting)
static long g_amp_settle = 3000000; // quiet time required after the greeting (ND120_AMP_SETTLE)
// Macro-instruction boundaries seen by the ND120_TRACE_VERIFY detector,
// counted UNCONDITIONALLY (before arming, PIL filtering or the 400 cap) so a
// candidate MIPS tap can be checked against it edge for edge. See the
// ND120_COUNT_CFETCH probe.
static unsigned long long g_macro_boundaries = 0;
// CFETCH rising edges (ND120_COUNT_CFETCH), plus a snapshot of both counters
// taken the moment ND120_TRACE_VERIFY arms. The honest comparison is the
// WINDOW from arming onward: before arming the machine is loading microcode
// and running self-test, where "macro instruction" is not a meaningful unit.
static unsigned long long g_cfetch_rises = 0;
static unsigned long long g_arm_cfetch = 0, g_arm_macro = 0;
static int g_arm_taken = 0;
// Candidate MIPS taps measured side by side in one run (31-AUG-2026). The
// event we actually want is "the instruction register takes a new opcode":
// CGA_ALU_GPR loads GPR from CD_15_0, which the MUX41P selects when
// GPRC[1:0] == 01 (D1 = CD_15_0, CGA_ALU_GPR.v:110-118), captured on the
// ALUCLK_EN enable pulse. CFETCH was measured DEAD (its FF holds its own Q
// and only reloads through the scan path on BRK), so it is kept here only
// as the control that proves the harness sees a real difference.
// The losing candidates (g_gprload, g_cfetch2 and their armed/repeat
// counters) were removed 31-AUG-2026 once XGPRLOAD_DBG was settled as the
// tap. They read ALU-internal aliases Verilator collapses, which broke the
// build outright; s_debug_cfetch_dbg is the routed signal the panel sees.
#if defined(TRACE_CSA) || defined(TRACE_CSA_BOOT)
static FILE *g_csa_fp = nullptr;
static unsigned g_last_csa = 0xFFFFu;
#endif
#ifdef SCRIPT_INPUT
#ifdef SCRIPT_CMD_20
#define SCRIPT_CMD "20!\r"              // -DSCRIPT_CMD_20 avoids quoting through make/verilator
#endif
#ifdef SCRIPT_CMD_CRS
#define SCRIPT_CMD "\r\r\r\r\r\r\r\r"   // -DSCRIPT_CMD_CRS: 8 Enters; each re-echoes the '#' prompt via MOPC (console-output repro)
#endif
#ifdef SCRIPT_CMD_EXAM
#define SCRIPT_CMD "20/\r"              // -DSCRIPT_CMD_EXAM: memory examine; prints a multi-char octal value (output-burst repro)
#endif
#ifdef SCRIPT_CMD_TAPE400
// -DSCRIPT_CMD_TAPE400: boot from the papertape device 400 (octal) via the
// microcode binary loader - the general bus IOX path. Loads the BPUN the
// tape device serves (INSTRUCTION-B.BPUN). Works with both the C papertape
// model and the Verilog device (VERILOG_TAPE=1); the outputs must match.
#define SCRIPT_CMD "400$"
#endif
#ifdef SCRIPT_CMD_FBOOT
// -DSCRIPT_CMD_FBOOT: boot from the floppy at device 1560 (octal) via
// the microcode mass-storage loader ('&' = device boot at the OPCOM
// prompt, as opposed to '$' = BPUN tape load).
#define SCRIPT_CMD "1560&"
#endif
#ifdef SCRIPT_CMD_FBOOTHELP
// -DSCRIPT_CMD_FBOOTHELP: boot the floppy test program from 1560 and
// then type 'help' at ITS prompt (not OPCOM's - after '&' the loaded
// program owns the console).
#define SCRIPT_CMD "1560&help\r"
#endif
#ifdef SCRIPT_CMD_FBOOTCFG
// -DSCRIPT_CMD_FBOOTCFG: boot the floppy test program (TPE Monitor) from
// 1560, then drive its configure tool: 'config' <enter>, 'run' <enter>.
// The injector holds after '&' until the boot completes, then types the
// rest at the loaded program's prompt.
#define SCRIPT_CMD "1560&config\rrun\r"
#endif
#ifdef SCRIPT_CMD_SBOOT
// -DSCRIPT_CMD_SBOOT: boot from the SMD disk at device 1540 (octal)
// via the microcode mass-storage loader.
#define SCRIPT_CMD "1540&"
#endif
#ifdef SCRIPT_CMD_BINLOAD
// -DSCRIPT_CMD_BINLOAD: activate the console serial binary loader; the
// raw BPUN bytes then come from ND120_BINLOAD_FILE (see below).
#define SCRIPT_CMD "300$"
#endif
#ifdef SCRIPT_CMD_GOLDEN
// -DSCRIPT_CMD_GOLDEN: the clock-enable refactor validation sequence
// (docs/plan-fix-unconstrained-clocks.md gate 3): examine 22, deposit
// 054321, re-examine (readback must show 054321), then run from 0 and 20.
#define SCRIPT_CMD "22/054321\r22/\r0!\r20!\r"
#endif
#ifdef SCRIPT_CMD_DMAXCHECK
// -DSCRIPT_CMD_DMAXCHECK: type OPCOM deposits of known octal words into
// low memory (word addresses 1000-1002), the CPU-path writer for the
// ND120_DMA_XCHECK cross-check gate. Values MUST match g_dmax_val[].
#define SCRIPT_CMD "1000/054321\r1001/012345\r1002/077777\r"
#endif
#ifndef SCRIPT_CMD
#define SCRIPT_CMD "0!\r"               // override with -DSCRIPT_CMD='"20!\r"'
#endif
// Resolve the console script at RUN TIME: ND120_SCRIPT (inline, \r-escaped) or
// ND120_SCRIPT_FILE override the compiled-in SCRIPT_CMD default. Lets any test
// drive OPCOM (deposit/examine/boot/...) with no rebuild and no -DSCRIPT_CMD
// quoting/PCH breakage. See simDevices/NDConsoleScript.h.
static const char *g_script = nd_console_script_resolve(SCRIPT_CMD);  // command to run once OPCOM is up
static int g_script_idx = 0;
static int g_next_inject_cnt = 0;          // gate: don't send next char until this cnt
// ND120_BINLOAD_FILE: after the script, stream this file's RAW bytes into
// the console UART (300$ serial binary loader experiments).
// ND120_BINLOAD_SETTLE / ND120_BINLOAD_GAP: cnt delays before / between bytes.

#if defined(ND120_VERILOG_DEVICES) && defined(SCRIPT_INPUT)
// ND120_DMA_TEST=<octal addr>:<count> - full-RTL DMA gate: after boot,
// the Verilog ND_DMA_MASTER inside ND120_TOP DMA-writes a pattern into
// RAM through the REAL bus arbiter (PAL_44801A) while the CPU is live
// (true cycle steal), verifies the RAM arrays directly, then DMA-reads
// everything back. Verdict line: "[dmatest] RESULT: PASS/FAIL".
static int g_dmat_state = 0;        // 0=off 1=wait-boot 2=write 3=read 4=done
static unsigned g_dmat_addr0 = 0;
static int g_dmat_count = 0, g_dmat_idx = 0, g_dmat_fail = 0;
static int g_dmat_reqhold = 0;
static int g_dmat_gapleft = 0;
static long g_dmat_guard = 0;

static inline unsigned short dmat_pattern(unsigned a)
{
	return (unsigned short)(052525u ^ a ^ (a << 7));
}

static void dma_test_tick(VND120_TOP *top, long cnt,
                          unsigned char *ram_lo, unsigned char *ram_hi)
{
	if (g_dmat_state == 0 || g_dmat_state == 4)
		return;

	if (g_dmat_state == 1)
	{
		if (g_boot_done_cnt != 0 && cnt > g_boot_done_cnt + 3000000)
		{
			printf("[dmatest] starting: %d words at %06o\n",
			       g_dmat_count, g_dmat_addr0);
			g_dmat_state = 2;
			g_dmat_idx = 0;
		}
		return;
	}

	// finish the one-clock request pulse first
	if (g_dmat_reqhold > 0)
	{
		if (--g_dmat_reqhold == 0)
			top->DMA_REQ = 0;
		return;
	}

	if (top->DMA_ACK)
	{
		if (top->DMA_ERR)
		{
			printf("[dmatest] transfer error at idx %d\n", g_dmat_idx);
			g_dmat_fail++;
		}
		if (g_dmat_state == 3)
		{
			unsigned short want = dmat_pattern(g_dmat_addr0 + g_dmat_idx);
			if (top->DMA_RDATA != want)
			{
				printf("[dmatest] readback mismatch @%06o got %06o want %06o\n",
				       g_dmat_addr0 + g_dmat_idx, top->DMA_RDATA, want);
				g_dmat_fail++;
			}
		}
		g_dmat_idx++;
		g_dmat_guard = 0;
		if (const char *g = getenv("ND120_DMA_GAP"))
			g_dmat_gapleft = atoi(g);
		if (g_dmat_idx >= g_dmat_count)
		{
			if (g_dmat_state == 2)
			{
				// write pass done: check the RAM arrays directly before
				// trusting the readback path
				for (int k = 0; k < g_dmat_count; k++)
				{
					unsigned a = g_dmat_addr0 + k;
					unsigned short got =
					    (unsigned short)((ram_hi[a] << 8) | ram_lo[a]);
					if (got != dmat_pattern(a))
					{
						printf("[dmatest] RAM array mismatch @%06o got %06o want %06o\n",
						       a, got, dmat_pattern(a));
						g_dmat_fail++;
					}
				}
				printf("[dmatest] write pass done, RAM verified, reading back\n");
				g_dmat_state = 3;
				g_dmat_idx = 0;
			}
			else
			{
				g_dmat_state = 4;
				printf("[dmatest] RESULT: %s\n", g_dmat_fail ? "FAIL" : "PASS");
				return;
			}
		}
		// fall through to issue the next word
	}
	else if (top->DMA_BUSY)
	{
		// bus-window trace of the first read word (ND120_DMA_TRACE=1)
		if (g_dmat_state == 3 && getenv("ND120_DMA_TRACE") && g_dmat_idx == atoi(getenv("ND120_DMA_TRACE")))
		{
			static unsigned prev_sig = 0xFFFFFFFF;
			static int trace_lines = 0;
			unsigned sig = ((unsigned)top->BDRY_n_OUT << 26) |
			               ((unsigned)top->BMEM_n << 25) |
			               ((unsigned)top->OUTGRANT_n << 24) |
			               (top->BD_23_0_n_OUT & 0xFFFFFF);
			if (sig != prev_sig && trace_lines < 300)
			{
				printf("[dmatrace] cnt=%d bdry=%d bmem=%d grant=%d bd_out=%06o (~=%06o)\n",
				       cnt, (int)top->BDRY_n_OUT, (int)top->BMEM_n,
				       (int)top->OUTGRANT_n,
				       (unsigned)(top->BD_23_0_n_OUT & 0xFFFFFF),
				       (unsigned)(~top->BD_23_0_n_OUT & 0xFFFFFF));
				prev_sig = sig;
				trace_lines++;
			}
		}
		if (++g_dmat_guard > 8000000)
		{
			printf("[dmatest] HANG waiting for the bus\n");
			printf("[dmatest] RESULT: FAIL\n");
			g_dmat_state = 4;
		}
		return;
	}

	// inter-word recovery gap (ND120_DMA_GAP half-ticks, default 0)
	if (g_dmat_gapleft > 0)
	{
		g_dmat_gapleft--;
		return;
	}

	// issue the next transfer
	top->DMA_WR = (g_dmat_state == 2);
	top->DMA_ADDR = g_dmat_addr0 + g_dmat_idx;
	top->DMA_WDATA = dmat_pattern(g_dmat_addr0 + g_dmat_idx);
	top->DMA_REQ = 1;
	g_dmat_reqhold = 2;
	g_dmat_guard = 1;
}

// ND120_DMA_XCHECK=1 - OPCOM<->DMA cross-check gate. The independent
// writer here is the CPU itself: the -DSCRIPT_CMD_DMAXCHECK script types
// OPCOM deposits ("A/V<CR>") that write known octal words to low memory
// through the normal CPU/MOPC store path. After the deposits settle, the
// Verilog ND_DMA_MASTER DMA-reads those same word addresses over the bus
// and asserts it sees exactly what OPCOM wrote - proving the DMA path and
// the CPU path address one and the same memory. The table below MUST
// match the deposits in SCRIPT_CMD_DMAXCHECK (both octal, word addresses).
// Verdict line: "[dmaxcheck] RESULT: PASS/FAIL".
static const unsigned g_dmax_addr[3] = { 001000u, 001001u, 001002u };
static const unsigned short g_dmax_val[3] = { 0054321u, 0012345u, 0077777u };
static const int g_dmax_count = 3;
static int g_dmax_state = 0;     // 0=off 1=wait-deposits 2=read 3=done
static int g_dmax_idx = 0, g_dmax_fail = 0;
static int g_dmax_reqhold = 0;
static long g_dmax_guard = 0;
static long g_dmax_start_cnt = 0; // cnt when the deposits were seen drained

static void dma_xcheck_tick(VND120_TOP *top, long cnt,
                            unsigned char *ram_lo, unsigned char *ram_hi)
{
	if (g_dmax_state == 0 || g_dmax_state == 3)
		return;
	// Never drive the DMA client ports at the same time as dma_test_tick
	// (the two gates are armed by different env vars, but be explicit).
	if (g_dmat_state != 0)
		return;

	if (g_dmax_state == 1)
	{
		// wait until the OPCOM deposit script has been fully typed in and
		// the last store has had time to land + MOPC to go quiet
		if (g_boot_done_cnt != 0 && g_script[g_script_idx] == '\0')
		{
			if (g_dmax_start_cnt == 0)
				g_dmax_start_cnt = cnt;
			if (cnt > g_dmax_start_cnt + 3000000)
			{
				printf("[dmaxcheck] deposits settled, DMA-reading %d words\n",
				       g_dmax_count);
				g_dmax_state = 2;
				g_dmax_idx = 0;
			}
		}
		return;
	}

	if (g_dmax_reqhold > 0)
	{
		if (--g_dmax_reqhold == 0)
			top->DMA_REQ = 0;
		return;
	}

	if (top->DMA_ACK)
	{
		unsigned a = g_dmax_addr[g_dmax_idx];
		unsigned short want = g_dmax_val[g_dmax_idx];
		unsigned short ram = (unsigned short)((ram_hi[a] << 8) | ram_lo[a]);
		if (top->DMA_ERR)
		{
			printf("[dmaxcheck] DMA error reading @%06o\n", a);
			g_dmax_fail++;
		}
		// the deposited value must be in the RAM array (proves OPCOM/CPU
		// wrote memory) AND the DMA read must return it (proves DMA read
		// the same word)
		if (ram != want)
		{
			printf("[dmaxcheck] OPCOM deposit missing @%06o: RAM %06o want %06o\n",
			       a, ram, want);
			g_dmax_fail++;
		}
		if (top->DMA_RDATA != want)
		{
			printf("[dmaxcheck] DMA readback mismatch @%06o got %06o want %06o (RAM %06o)\n",
			       a, top->DMA_RDATA, want, ram);
			g_dmax_fail++;
		}
		else
		{
			printf("[dmaxcheck] @%06o OPCOM=%06o DMA=%06o OK\n",
			       a, want, top->DMA_RDATA);
		}
		g_dmax_idx++;
		g_dmax_guard = 0;
		if (g_dmax_idx >= g_dmax_count)
		{
			g_dmax_state = 3;
			printf("[dmaxcheck] RESULT: %s\n", g_dmax_fail ? "FAIL" : "PASS");
			return;
		}
		// fall through to issue the next read
	}
	else if (top->DMA_BUSY)
	{
		if (++g_dmax_guard > 8000000)
		{
			printf("[dmaxcheck] HANG waiting for the bus\n");
			printf("[dmaxcheck] RESULT: FAIL\n");
			g_dmax_state = 3;
		}
		return;
	}

	// issue the next DMA read of an OPCOM-deposited word
	top->DMA_WR = 0;
	top->DMA_ADDR = g_dmax_addr[g_dmax_idx];
	top->DMA_REQ = 1;
	g_dmax_reqhold = 2;
	g_dmax_guard = 1;
}
#endif

static int g_ldirv_last = 0;
static unsigned g_termx_logged = 0;
static FILE *g_binf = nullptr;
static long g_bin_gap = 100000;
static long g_bin_settle = 2000000;
static int g_bin_state = 0;   // 0=idle 1=settling 2=streaming 3=done
static long g_bin_sent = 0;
#endif

int txData = 0;
int txDataBit = 0;
int txEnabled = 0;
int txTicks = 0;
int txOnes = 0;

int rxData = 0;
int rxDataBit = 0;
int rxEnabled = 0;
int rxTicks = 0;
int rxOnes = 0;
// Console injector framing: 7 data bits + parity-space + 2 stop (matches the
// 7E2 the boot microcode programs into the SC2661 - fine for OPCOM ASCII).
// tx8n1=1 switches to 8N1 for the 300$ binary load stream, where BPUN bytes
// use the full 8 bits (set when the ND120_BINLOAD_FILE stream opens).
int tx8n1 = 0;

int main(int argc, char **argv)
{

	set_nonblocking_terminal();

	Verilated::commandArgs(argc, argv);
	VND120_TOP *top = new VND120_TOP;

	addDevices();

	uint8_t led = 0;
	uint8_t new_led = 0;

	// Load data
	// Access MEM->RAM fields via rootp
#ifdef ND120_SIM_BLOCKRAM_RAM
	// MAIN_RAM_BLOCKRAM builds MEM_RAM_49_BLOCKRAM instead of the sim RAM, so
	// the b0_lo/b0_hi arrays below do not exist and the harness will not link.
	// Every use of them is a DEBUG SHORTCUT (BPUN pre-deposit, the DMA test,
	// and a dump) - none is needed to boot, which happens from the PROM/SD
	// path. Backing them with scratch arrays keeps those call sites compiling
	// without special-casing each one.
	//
	// Added 01-SEP-2026 so the simulator can be run in the MiSTer's EXACT
	// configuration. Without the same memory backend the comparison is not
	// like-for-like: the cycle controller's CC state is driven by the memory
	// handshake, so a different backend can change CC and TERM all by itself.
	static uint8_t ram_low[1 << 22], ram_low_9[1 << 22];
	static uint8_t ram_high[1 << 22], ram_high_9[1 << 22];
#else
	auto &ram_low = top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__RAM__DOT__b0_lo;
	auto &ram_low_9 = top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__RAM__DOT__b0_lo_p;

	auto &ram_high = top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__RAM__DOT__b0_hi;
	auto &ram_high_9 = top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__MEM__DOT__RAM__DOT__b0_hi_p;
#endif

	// DEBUG PRE-DEPOSIT of a BPUN straight into the RAM arrays, bypassing the
	// CPU entirely. This is a debug shortcut, NOT how the machine works.
	//
	// It MUST NOT run under SD_STORAGE (14-JUL-2026, caught by Ronny): the
	// default DEBUG.BPUN is BYTE-IDENTICAL to INSTRUCTION-B.BPUN (same
	// sha256, both 46566 bytes), so pre-depositing it puts the very program
	// the '400$' tape boot is supposed to fetch into memory BEFORE the boot
	// runs. The console banner then proves nothing about the tape: the boot
	// would print it whether or not a single byte came off the card. Any
	// "boots from SD" claim measured with this on is contaminated.
	//
	// Under ND120_SD_STORAGE the card supplies the program, so the pre-deposit
	// is OFF unless a file is named explicitly on the command line. Pass one
	// (or set ND120_PRELOAD_BPUN=file) when you WANT the shortcut.
	//
	// SAME RULE FOR THE FLOPPY (19-JUL-2026, caught by Ronny): when a diskette
	// is mounted (ND120_FLOPPY_IMG set, i.e. `make run-floppy`) the CPU is
	// supposed to load the program itself with '1560&'. Pre-depositing
	// DEBUG.BPUN there put INSTRUCTION-B in RAM before the boot ran, so the
	// floppy boot proved nothing - exactly the contamination the SD_STORAGE
	// guard above exists to prevent. A mounted boot medium => no default
	// pre-deposit. Force one anyway with argv[1] or ND120_PRELOAD_BPUN.
	const char *env_preload = getenv("ND120_PRELOAD_BPUN");
	const char *env_floppy  = getenv("ND120_FLOPPY_IMG");      // Verilog-floppy diskette
	const char *env_fcore   = getenv("ND120_FLOPPYCORE_IMG");  // NDDeviceCore C-floppy diskette
	const bool floppy_mounted =
	    (env_floppy != NULL && env_floppy[0] != '\0') ||
	    (env_fcore  != NULL && env_fcore[0]  != '\0');
	// ND120_PRELOAD_BPUN set-but-EMPTY = explicitly NO pre-deposit (overrides
	// the legacy default), so any boot gate can force an empty RAM regardless
	// of build flags.
	const bool preload_none = (env_preload != NULL && env_preload[0] == '\0');
	char *filename = NULL;
	if (argc > 1)
		filename = argv[1];
	else if (env_preload != NULL && env_preload[0] != '\0')
		filename = strdup(env_preload);
#ifndef ND120_SD_STORAGE
	else if (!floppy_mounted && !preload_none)
		filename = strdup("DEBUG.BPUN");  // legacy default (C tape, no SD, no floppy)
#endif

	if (filename != NULL) {
		printf("[ND120] BPUN pre-deposit into RAM: %s (debug shortcut - the CPU\n"
		       "        did NOT load this; a tape/floppy boot of the same file proves nothing)\n",
		       filename);
		loadfile(filename, 0, &ram_low[0], &ram_low_9[0], &ram_high[0], &ram_high_9[0]);
	} else if (floppy_mounted) {
		printf("[ND120] no BPUN pre-deposit: RAM starts empty, '1560&' must load the\n"
		       "        program off the diskette itself (%s)\n",
		       (env_floppy != NULL && env_floppy[0] != '\0') ? env_floppy : env_fcore);
	} else {
		printf("[ND120] no BPUN pre-deposit: RAM starts empty, '400$' must load the\n"
		       "        program off the SD card itself\n");
	}

	// LED bits
	//!   0=CPU RED
	//!   1=CPU GREEN
	//!   2=LED4_RED_PARITY_ERROR
	//!   3=LED_CPU_GRANT_INDICATOR
	//!   4=LED_BUS_GRANT_INDICATOR
	//!   5=LED1 from MMU

	top->btn1 = false; // sys_rst_n = 0
	top->uartRx = 1;   // MARK

	// Default values for BUS INTERFACE (BIF) input
	top->BD_23_0_n_IN = 0xFFFFFF; // Default to pulled-high
	top->BREQ_n = 1;
	top->BINT10_n = 1;
	top->BINT11_n = 1;
	top->BINT12_n = 1;
	top->BINT13_n = 1;
	top->BINT15_n = 1;
	top->POWSENSE_n = 1;

	// Bus signaling defaults (off)
	top->SEMRQ_n_IN = 1;
	top->BINPUT_n_IN = 1;
	top->BDAP_n_IN = 1;
	// top->BPERR_n = 1; // BUS PARITY ERROR (disabled  TOP module)
	top->BDRY_n_IN = 1;
	top->BAPR_n_IN = 1;

#if defined(ND120_VERILOG_DEVICES) && defined(SCRIPT_INPUT)
	top->DMA_REQ = 0;
	top->DMA_WR = 0;
	top->DMA_ADDR = 0;
	top->DMA_WDATA = 0;
	if (const char *e = getenv("ND120_DMA_TEST"))
	{
		if (sscanf(e, "%o:%d", &g_dmat_addr0, &g_dmat_count) == 2 &&
		    g_dmat_count > 0)
		{
			g_dmat_state = 1;
			printf("[dmatest] armed: %d words at %06o\n",
			       g_dmat_count, g_dmat_addr0);
		}
	}
	if (getenv("ND120_DMA_XCHECK") && g_dmat_state == 0)
	{
		g_dmax_state = 1;
		printf("[dmaxcheck] armed: %d OPCOM-deposited words\n", g_dmax_count);
	}
#endif

	long cnt = 0;
#if defined(TRACE_CSA) || defined(TRACE_CSA_BOOT)
	g_csa_fp = fopen("csa_trace.csv", "w");
#endif
#ifdef TRACE_MIC
	// Deep half-clock trace of the MIC address pipeline in a cnt window.
	// Build with e.g. -DTRACE_MIC -DTRACE_MIC_START=12345 -DTRACE_MIC_END=12999
#ifndef TRACE_MIC_START
#define TRACE_MIC_START 0
#endif
#ifndef TRACE_MIC_END
#define TRACE_MIC_END 0x7FFFFFFF
#endif
	FILE *g_mic_fp = fopen("mic_trace.csv", "w");
	fprintf(g_mic_fp, "cnt,sysclk,csa,csbits,regREP,regIW,muxsel,term,cc\n");
#endif
	if (const char *e = getenv("ND120_STDIN_GAP")) g_stdin_gap = atol(e);
	if (const char *e = getenv("ND120_MAX_CNT")) g_max_cnt = atol(e);
	if (const char *e = getenv("ND120_AMP_SETTLE")) g_amp_settle = atol(e);

	while (true)
	{
		cnt++;

		if (g_max_cnt > 0 && cnt > g_max_cnt)
		{
			printf("\n[harness] ND120_MAX_CNT reached, stopping\n");
			break;
		}

		if (cnt == 100)
		{
			top->btn1 = true; // sys_rst_n = 1 // disable reset
		}

		top->eval();
		top->sysclk = !top->sysclk;

		proccess_bif_signal(top);
#if defined(ND120_VERILOG_DEVICES) && defined(SCRIPT_INPUT)
		dma_test_tick(top, cnt, &ram_low[0], &ram_high[0]);
		dma_xcheck_tick(top, cnt, &ram_low[0], &ram_high[0]);
#endif

#ifdef TRACE_MIC
		if (g_mic_fp && cnt >= TRACE_MIC_START && cnt <= TRACE_MIC_END)
		{
			fprintf(g_mic_fp, "%d,%d,%o,%016llx,%o,%o,%d,%d,%d%d%d%d\n",
				cnt,
				(int)top->sysclk,
				(unsigned)top->CSA_12_0,
				(unsigned long long)top->rootp->ND120_TOP__DOT__CORE__DOT__s_csbits,
				(unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__MIC_MASEL__DOT__regREP,
				(unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__MIC_MASEL__DOT__regIW,
				(int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__MIC_MASEL__DOT__s_mux_selector,
				(int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__TERM_reg,
				(int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC3_reg,
				(int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC2_reg,
				(int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC1_reg,
				(int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC0_reg);
		}
		if (g_mic_fp && cnt > TRACE_MIC_END)
		{
			fclose(g_mic_fp);
			g_mic_fp = nullptr;
			printf("\n[instrumented] TRACE_MIC window done, stopping\n");
			break;
		}
#endif

#ifdef ND120_COUNT_STERR
			// Count entries into the MACL self-test error routine (STERR,
			// CSA octal 2156) across the WHOLE run (the self-test runs
			// before the '#' prompt, outside the TRACE_CSA window). Each
			// failing self-test check jumps here; 0 visits = clean pass.
			// The WCS load streams every address 0..8177 linearly, so CSA
			// passes 2156 once during loading - only count EXECUTION
			// visits, i.e. after the loader leaves the linear walk (the
			// first time CSA jumps back to 0 after having been past 2156).
			{
				static unsigned sterr_last_csa = 0xFFFFu, sterr_hits = 0;
				static int sterr_reported = 0, sterr_exec = 0;
				unsigned csa_now = (unsigned)top->CSA_12_0;
				if (!sterr_exec && sterr_last_csa > 02156u && sterr_last_csa != 0xFFFFu && csa_now < 02000u)
					sterr_exec = 1;
				if (sterr_exec && csa_now == 02156u && sterr_last_csa != 02156u)
				{
					sterr_hits++;
					printf("[sterr] hit %u at cnt=%d\n", sterr_hits, cnt);
				}
				sterr_last_csa = csa_now;
				if (!sterr_reported && g_boot_done_cnt != 0)
				{
					printf("[sterr] boot complete: %u STERR visits during self-test\n", sterr_hits);
					fflush(stdout);
					sterr_reported = 1;
				}
			}
#endif

#ifdef ND120_PROBE_VEC17
			// Tang masked-level-10 root-cause probe (non-invasive; no RTL change).
			// The measured silicon failure is a trap dispatch to the MACRO-INTERRUPT
			// vector (microcode CS 000017 = "17/ % MACRO INTERRUPT", PIC,RVECT ->
			// MACRI) which reads the PIC vector; an EMPTY claim reads 0, and the
			// ITSRV table maps entry 0 -> level 10. This probe does NOT assume the
			// claim is empty - it MEASURES the full claim picture at every entry to
			// CS 000017, and dumps the preceding PAN/IRQ/INTRQN history so any
			// INTRQN lag (INTRQN=1 while PAN=0 and IRQ=0) is visible directly.
			//   IRQ    = live maskable claim (HIRQ|LIRQ, mask+enable gated)
			//   IREQ_n = per-level latched requests, active low (all 1 = none)
			//   MIREQ  = masked requests
			//   PICV   = vector the RVECT read would return
			//   PAN_n  = panel/RTC request into INTRQN (active low)
			//   INTRQN = registered ~(PAN|IRQ), active low (0 = a dispatch is armed)
			{
				auto rp = top->rootp;
				// --- rolling history ring (every half-sysclk) ---
				static const int RN = 64;
				static int   h_cnt[RN];
				static unsigned h_csa[RN];
				static int   h_pann[RN], h_irq[RN], h_intrqn[RN], h_pil[RN];
				static int   h_head = 0, h_init = 0;
				if (!h_init) { for (int k=0;k<RN;k++){h_cnt[k]=0;h_csa[k]=0;h_pann[k]=1;h_irq[k]=0;h_intrqn[k]=1;h_pil[k]=0;} h_init=1; }
				int pann   = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__s_pan_n;
				int irq    = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__s_irq;
				int intrqn = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__s_intrq_n;
				int pil    = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__sx_pil_3_0_out;
				unsigned csa = (unsigned)top->CSA_12_0;
				h_head = (h_head + 1) % RN;
				h_cnt[h_head]=cnt; h_csa[h_head]=csa; h_pann[h_head]=pann;
				h_irq[h_head]=irq; h_intrqn[h_head]=intrqn; h_pil[h_head]=pil;

				// --- trigger 2 (the ACTUAL silicon signature): PIL switches from 0
				// to a nonzero level. On silicon PIL 0->10 with nothing enabled is
				// the wedge. Dump the same claim picture + history so we can see the
				// cause state at the instant of a level switch, whatever path it took.
				{
					static int pil_last = -1, pil_prints = 0;
					if (pil_last == 0 && pil != 0 && pil_prints < 40)
					{
						unsigned ireq_n = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_ireq_15_0_n;
						unsigned mireq  = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_mireq_15_0;
						unsigned picv   = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__s_picv_2_0_out;
						int empty = (irq == 0) && ((ireq_n & 0xFFFFu) == 0xFFFFu);
						printf("[PILSW]%s cnt=%d 0->%d csa=%05o IRQ=%d ireq_n=%06o mireq=%06o picv=%o pann=%d intrqn=%d\n",
							empty ? " EMPTY-CLAIM" : "", cnt, pil, csa, irq, ireq_n, mireq, picv, pann, intrqn);
						printf("        history (cnt csa pan_n irq intrqn pil):\n");
						for (int k=1;k<=RN;k++){ int idx=(h_head+k)%RN;
							printf("        %d %05o p%d i%d n%d L%d\n", h_cnt[idx], h_csa[idx], h_pann[idx], h_irq[idx], h_intrqn[idx], h_pil[idx]); }
						fflush(stdout); pil_prints++;
						if (pil_prints == 40) { printf("[PILSW] capture done\n"); fflush(stdout); }
					}
					pil_last = pil;
				}

				// --- trigger 1: entry into the macro-interrupt vector CS 000017 ---
				static unsigned v_last_csa = 0xFFFFu;
				static int v_prints = 0;
				if (csa == 000017u && v_last_csa != 000017u && v_prints < 80)
				{
					unsigned ireq_n = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_ireq_15_0_n;
					unsigned mireq  = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_mireq_15_0;
					unsigned picv   = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__s_picv_2_0_out;
					unsigned pics   = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__s_pics_2_0_out;
					unsigned pmask  = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_picmask_15_0_out;
					int empty = (irq == 0) && ((ireq_n & 0xFFFFu) == 0xFFFFu);
					printf("[vec17]%s cnt=%d pil=%d IRQ=%d ireq_n=%06o mireq=%06o picv=%o pics=%o pann=%d intrqn=%d pmask=%06o\n",
						empty ? " EMPTY-CLAIM" : "", cnt, pil, irq, ireq_n, mireq, picv, pics, pann, intrqn, pmask);
					// dump the ring oldest->newest so the INTRQN/PAN/IRQ lag is visible
					printf("        history (cnt csa pan_n irq intrqn pil):\n");
					for (int k=1;k<=RN;k++){
						int idx=(h_head+k)%RN;
						printf("        %d %05o p%d i%d n%d L%d\n",
							h_cnt[idx], h_csa[idx], h_pann[idx], h_irq[idx], h_intrqn[idx], h_pil[idx]);
					}
					fflush(stdout);
					v_prints++;
					if (v_prints == 80) { printf("[vec17] capture done\n"); fflush(stdout); }
				}
				v_last_csa = csa;
			}
#endif

#ifdef ND120_PROBE_STSCHG
			// BFILL STS-corruption probe (BYTE-STRING, July 2026; analysis in git history):
			// change-triggered log of the hardware STS register (CGA_ALU_STS
			// output s_sts_15_0) with the executing CSA, the CSTS load code,
			// LDPILN and FIDBO. Armed at the first visit to BFILL (CSA 01333)
			// so the earlier boot/self-test churn stays silent; capped prints.
			// The first log line where an 0x2A byte enters STS names the
			// corrupting microword and load path. --public-flat-rw build.
			{
				static int armed = 0, prints = 0;
				static long stschg_min = -1;
				static unsigned sts_last = 0xFFFFFFFFu;
				auto rp = top->rootp;
				unsigned csa = (unsigned)top->CSA_12_0;
				// CSA 01333 is also visited during boot/self-test, so gate
				// arming on ND120_STSCHG_MIN (cycle count; find the target
				// area's entry cnt from a first coarse run).
				if (stschg_min < 0) {
					const char *e = getenv("ND120_STSCHG_MIN");
					stschg_min = e ? atol(e) : 0;
				}
				if (!armed && cnt >= stschg_min && csa == 01333u)
					{ armed = 1; printf("[stschg] armed at cnt=%d (BFILL executing)\n", cnt); }
				unsigned sts = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_sts_15_0;
				if (armed && sts != sts_last && prints < 20000)
				{
					printf("[stschg] cnt=%d csa=%05o sts=%06o<-%06o csts=%d ldpiln=%d fidbo=%06o\n",
						cnt, csa, sts, sts_last,
						(int)(rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_csts_1_0 & 3),
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_ldpil_n,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_fidbo_15_0_out);
					if (++prints == 20000) { printf("[stschg] print cap reached\n"); fflush(stdout); }
				}
				sts_last = sts;
			}
#endif

			// Cache-inhibit map write probe (ND120_WCLIM_TRACE=1, run-time, no
			// rebuild). Context: docs/CACHE-STATUS.md. On the
			// Nexys the ILA showed the inhibit RAM (CPU_MMU_PT_29 CHIP_20G, an
			// IMS1403 16Kx1) IS written - 69 WCLIM_n strobes in one window -
			// yet WCINH_n reads "inhibited" for ~90% of accesses, and the
			// cache is inert. The open question there was WHAT is written and
			// WHERE. This prints, for every sysclk edge on which the RAM sees
			// W_n low, the RAM's own address/data input (s_ims_ppn_25_10_in:
			// PPN23-10 is the address, PPN25 the data bit), the IDB word the
			// page number is supposed to come from (PAL 44306A: EIPU = EIPL =
			// WCHIM, "pass page number to be inhibited from IDB"), the PPNX
			// transceiver's output onto the PPN bus, and the DGA's WCHIM /
			// EORF / ESTOF, so a mis-steered address or a stuck data bit is
			// visible directly. At the end of each write burst it counts the
			// map: how many of the 16384 pages hold 1 (WCINH_n high = cache
			// ALLOWED) vs 0 (inhibited).
			//
			// Signal names: Verilator folds the plain alias wires in
			// CPU_MMU_24 (s_wchim_n, s_eorf_n, s_eipu_n ...) even under
			// --public-flat-rw, so the sources used are the ones that survive:
			// the DGA's A188 flop (Q3 = WCHIM_n), COMM's s_erof (= ~EORF_n),
			// the board-level s_estof_n, and CPU_15's s_mmu_idb_15_0_in.
			{
				static int wt_on = -1, wt_prints = 0;
				static long wt_burst = 0, wt_total = 0;
				static unsigned wt_last_key = 0xFFFFFFFFu;
				static long wt_last_write_cnt = 0;
				if (wt_on < 0) wt_on = getenv("ND120_WCLIM_TRACE") ? 1 : 0;
				if (wt_on)
				{
					auto rp = top->rootp;
					int wclim_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__s_wclim_n;
					// NOTE: the probes in this loop are evaluated once per sysclk
					// period, always with top->sysclk == 1 (a "sysclk == 0" gate
					// here is never true - it hid every write on the first run).
					if (!wclim_n)
					{
						// clock is low: these are the values the RAM will
						// latch at the coming posedge (IMS1403_25.v:62)
						unsigned ram  = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__PT__DOT__s_ims_ppn_25_10_in & 0xFFFFu;
						unsigned idb  = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_mmu_idb_15_0_in & 0xFFFFu;
						unsigned pxi  = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__s_ppnx_ppn_25_10_in & 0xFFFFu;
						unsigned pxo  = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__s_ppnx_ppn_25_10_out & 0xFFFFu;
						unsigned pto  = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__s_pt_ppn_25_10_out & 0xFFFFu;
						unsigned preg = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__PPNX__DOT__PPN_reg & 0xFFFFu;
						int estof_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_estof_n;
						int wchim_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__COMM__DOT__A188__DOT__gen_enable__DOT__MEMORY_4__DOT__gen_enable__DOT__q_r;
						int eorf    = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__COMM__DOT__s_erof;
						unsigned key = ram ^ (idb << 16);
						wt_burst++; wt_total++;
						// one line per distinct (ram input, idb) inside a
						// strobe, so a multi-cycle strobe does not flood
						if (key != wt_last_key && wt_prints < 60000)
						{
							printf("[wclim] cnt=%d csa=%05o page=%05o data=%d idb=%06o | ram_in=%06o pxi=%06o pxo=%06o pto=%06o ppn_reg=%06o estof_n=%d wchim_n=%d eorf_n=%d\n",
								cnt, (unsigned)top->CSA_12_0, ram & 0x3FFFu, (ram >> 15) & 1u, idb,
								ram, pxi, pxo, pto, preg, estof_n, wchim_n, !eorf);
							if (++wt_prints == 60000) printf("[wclim] print cap reached\n");
						}
						wt_last_key = key;
						wt_last_write_cnt = cnt;
					}
					if (wclim_n) wt_last_key = 0xFFFFFFFFu;
					// WCHIM itself, before the EORF gate: WCLIM_n = WCHIM_n | EORF_n
					// (CPU_MMU_24.v:321). If the DGA raises WCHIM but the two never
					// overlap, the map is never written - the same shape as the
					// TRR PANC bug that kept panel commands out of the FIFO.
					{
						static int wh_prev = 1, wh_prints = 0;
						int wchim_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__COMM__DOT__A188__DOT__gen_enable__DOT__MEMORY_4__DOT__gen_enable__DOT__q_r;
						int eorf    = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__COMM__DOT__s_erof;
						if (wchim_n != wh_prev)
						{
							if (wh_prints < 400)
								printf("[wchim] cnt=%d csa=%05o wchim_n %d->%d eorf_n=%d wclim_n=%d\n",
									cnt, (unsigned)top->CSA_12_0, wh_prev, wchim_n, !eorf, wclim_n);
							if (++wh_prints == 400) printf("[wchim] print cap reached\n");
							wh_prev = wchim_n;
						}
					}
					// burst-end report: no strobe for 20000 cycles after >0 writes
					if (wt_burst > 0 && cnt > wt_last_write_cnt + 20000)
					{
						long ones = 0, zeros = 0;
						for (int i = 0; i < 16384; i++)
						{
							if (rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__PT__DOT__CHIP_20G__DOT__ims_memory_array[i]) ones++; else zeros++;
						}
						printf("[wclim] burst end at cnt=%d: %ld write-cycles this burst, %ld total; map now: %ld pages=1 (cache allowed), %ld pages=0 (inhibited)\n",
							cnt, wt_burst, wt_total, ones, zeros);
						fflush(stdout);
						wt_burst = 0;
					}
				}
			}

			// Inhibit-limits golden-timeline probe (ND120_INHIBIT_TRACE=1,
			// run-time). Written 30-AUG-2026 to capture a PASSING Verilator
			// run of CACHE-1X0-A00 test 3 ("Inhibit limits") for comparison
			// against the Nexys, where the same test hangs at P=124563B.
			// Four captures, all octal, each with its own print cap:
			//   [inh] CCLR   - every falling edge of CCLR_n (TRR CCLR, code
			//                  010): cnt, CSA, P and A at that instant.
			//   [inh] sweep  - the inhibit-map programming done by TRR LCIL
			//                  (011) / UCIL (012): the microcode sweeps the
			//                  16Kx1 inhibit RAM via WCLIM_n one page per
			//                  strobe (microwords 02045/02046 etc.), so the
			//                  burst IS the limit programming. Logged as a
			//                  start line (P, A when the first strobe lands)
			//                  and an end line with the min..max page range
			//                  written per data value plus the whole-map
			//                  count and the map's inhibited (=0) range.
			//   [inh] acc    - sampled proof of behaviour: at each cycle-
			//                  controller TERM with a memory request, the
			//                  access is classed by the inhibit map bit of
			//                  its PPN x cache HIT; the first few lines of
			//                  each class after every sweep are printed and
			//                  all four classes are counted. "inh=0 hit=1"
			//                  lines after the limits are set would be the
			//                  smoking gun (inhibited access served by
			//                  cache); their absence plus "inh=1 hit=1"
			//                  lines is the pass evidence.
			//   [inh] pc     - THE key artifact: every change of P while P
			//                  is inside 124400..125000 (octal), with CSA,
			//                  PIL, HIT, BRK_n, MREQ and the map bit of the
			//                  current PPN - plus an explicit exit line
			//                  naming the P it left to. This is the window
			//                  the Nexys spins in at 124563.
			// P and A are read from the WRF flops directly (the flat aliases
			// fold; the flops survive a build without --public-flat-rw, same
			// trick as the [live] probe).
#ifndef ND120_NO_CACHE // probe reads cache internals a CACHE=0 build compiles out
			{
				static int it_on = -1;
				if (it_on < 0) it_on = getenv("ND120_INHIBIT_TRACE") ? 1 : 0;
				if (it_on)
				{
					auto rp = top->rootp;
					unsigned it_p = (((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__P_REG_2__DOT__L_PR_8_15__DOT__reg8bit & 0xFFu) << 8)
					              | ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__P_REG_2__DOT__L_PR_7_0__DOT__reg8bit & 0xFFu);
					unsigned it_a = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__A_REG_5__DOT__regFF & 0xFFFFu;
					unsigned it_csa = (unsigned)top->CSA_12_0;
					// PIL = STS bits 11..8 (sx_pil_3_0_out is folded in this
					// build; the ALU's STS word survives)
					int it_pil = (int)((rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_sts_15_0 >> 8) & 0xFu);

					// --- [inh] CCLR: TRR CCLR (function code 010) ---
					{
						static int cc_prev = 1, cc_prints = 0;
						int cclr_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__s_cclr_n;
						if (!cclr_n && cc_prev && cc_prints < 200)
						{
							printf("[inh] CCLR cnt=%ld csa=%05o P=%06o A=%06o\n", cnt, it_csa, it_p, it_a);
							fflush(stdout);
							if (++cc_prints == 200) printf("[inh] CCLR print cap reached\n");
						}
						cc_prev = cclr_n;
					}

					// --- [inh] sweep: inhibit-RAM write bursts (TRR LCIL/UCIL) ---
					static long it_sweeps = 0;   // completed sweeps; resets the acc sampler
					{
						static long sw_writes = 0, sw_last_cnt = 0, sw_start_cnt = 0;
						static unsigned sw_pmin[2] = {0xFFFFu, 0xFFFFu}, sw_pmax[2] = {0, 0};
						static long sw_ndata[2] = {0, 0};
						static unsigned sw_prev_page = 0xFFFFu;
						static int sw_prints = 0;
						int wclim_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__s_wclim_n;
						if (!wclim_n)
						{
							unsigned ram = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__PT__DOT__s_ims_ppn_25_10_in & 0xFFFFu;
							unsigned page = ram & 0x3FFFu;
							unsigned d = (ram >> 15) & 1u;
							if (sw_writes == 0)
							{
								sw_start_cnt = cnt;
								sw_pmin[0] = sw_pmin[1] = 0xFFFFu; sw_pmax[0] = sw_pmax[1] = 0;
								sw_ndata[0] = sw_ndata[1] = 0;
								if (sw_prints < 400)
									printf("[inh] sweep start cnt=%ld csa=%05o P=%06o A=%06o first page=%05o data=%u\n",
										cnt, it_csa, it_p, it_a, page, d);
							}
							// count each page once per strobe (a strobe spans clocks)
							if (page != sw_prev_page)
							{
								sw_writes++;
								if (page < sw_pmin[d]) sw_pmin[d] = page;
								if (page > sw_pmax[d]) sw_pmax[d] = page;
								sw_ndata[d]++;
								sw_prev_page = page;
							}
							sw_last_cnt = cnt;
						}
						else
							sw_prev_page = 0xFFFFu;
						if (sw_writes > 0 && cnt > sw_last_cnt + 20000)
						{
							// burst over: report what got programmed and the map state
							long ones = 0, zeros = 0;
							unsigned zmin = 0xFFFFu, zmax = 0;
							for (unsigned i = 0; i < 16384; i++)
							{
								if (rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__PT__DOT__CHIP_20G__DOT__ims_memory_array[i]) ones++;
								else { zeros++; if (i < zmin) zmin = i; if (i > zmax) zmax = i; }
							}
							if (sw_prints < 400)
							{
								printf("[inh] sweep end cnt=%ld (start %ld): %ld pages written | data=0 (inhibit): %ld pages %05o..%05o | data=1 (allow): %ld pages %05o..%05o | map: %ld inhibited (%05o..%05o), %ld allowed\n",
									cnt, sw_start_cnt, sw_writes,
									sw_ndata[0], sw_ndata[0] ? sw_pmin[0] : 0, sw_ndata[0] ? sw_pmax[0] : 0,
									sw_ndata[1], sw_ndata[1] ? sw_pmin[1] : 0, sw_ndata[1] ? sw_pmax[1] : 0,
									zeros, zeros ? zmin : 0, zeros ? zmax : 0, ones);
								fflush(stdout);
								if (++sw_prints == 400) printf("[inh] sweep print cap reached\n");
							}
							sw_writes = 0;
							it_sweeps++;
						}
					}

					// --- [inh] acc: sampled hit/miss vs inhibit-map class ---
					{
						static int ac_prev_term = 0;
						static long ac_seen_sweep = -1;
						static long ac_class_n[4];        // [inh<<1 | hit]
						static int ac_class_prints[4];
						static int ac_sum_prints = 0;
						static long ac_next_sum = 0;
						int term = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__TERM_reg;
						int mreq = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__s_csmreq;
						if (ac_seen_sweep != it_sweeps)
						{
							// fresh limits: reopen the per-class sample budget
							ac_seen_sweep = it_sweeps;
							ac_class_prints[0] = ac_class_prints[1] = ac_class_prints[2] = ac_class_prints[3] = 0;
						}
						if (term && !ac_prev_term && mreq)
						{
							unsigned ppn = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_ppn_23_10 & 0x3FFFu;
							int hit = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_hit;
							int allow = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__PT__DOT__CHIP_20G__DOT__ims_memory_array[ppn]; // 1 = cache allowed, 0 = inhibited
							int cls = ((allow ? 0 : 2) | (hit ? 1 : 0));
							ac_class_n[cls]++;
							if (it_sweeps > 0 && ac_class_prints[cls] < 12)
							{
								static const char *nm[4] = {"allow-miss", "ALLOW-HIT ", "inhib-miss", "INHIB-HIT!"};
								printf("[inh] acc %s cnt=%ld csa=%05o P=%06o ppn=%05o hit=%d allow=%d\n",
									nm[cls], cnt, it_csa, it_p, ppn, hit, allow);
								ac_class_prints[cls]++;
							}
						}
						ac_prev_term = term;
						if (cnt >= ac_next_sum && ac_sum_prints < 400)
						{
							ac_next_sum = cnt + 50000000;
							printf("[inh] acc summary cnt=%ld sweeps=%ld | allow-miss=%ld allow-hit=%ld inhib-miss=%ld inhib-hit=%ld\n",
								cnt, it_sweeps, ac_class_n[0], ac_class_n[1], ac_class_n[2], ac_class_n[3]);
							fflush(stdout);
							ac_sum_prints++;
						}
					}

					// --- [inh] pc: P-change trace inside 124400..125000 octal ---
					{
						static unsigned pc_prev_p = 0xFFFFFFFFu;
						static int pc_inside = 0;
						static long pc_prints = 0, pc_exit_prints = 0;
						const unsigned PC_LO = 0124400u, PC_HI = 0125000u;
						if (it_p != pc_prev_p)
						{
							int in = (it_p >= PC_LO && it_p <= PC_HI);
							if (in && pc_prints < 60000)
							{
								unsigned ppn = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_ppn_23_10 & 0x3FFFu;
								printf("[inh] pc cnt=%ld P=%06o csa=%05o pil=%02o hit=%d brk_n=%d mreq=%d allow=%d ppn=%05o A=%06o\n",
									cnt, it_p, it_csa, it_pil,
									(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_hit,
									(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_brk_n,
									(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__s_csmreq,
									(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__PT__DOT__CHIP_20G__DOT__ims_memory_array[ppn],
									ppn, it_a);
								if (++pc_prints == 60000) { printf("[inh] pc print cap reached\n"); fflush(stdout); }
							}
							if (!in && pc_inside && pc_exit_prints < 2000)
							{
								printf("[inh] pc EXIT cnt=%ld window left to P=%06o (csa=%05o pil=%02o A=%06o)\n",
									cnt, it_p, it_csa, it_pil, it_a);
								fflush(stdout);
								pc_exit_prints++;
							}
							pc_inside = in;
							pc_prev_p = it_p;
						}
					}

					// --- [inh] fx: per-cycle fetch-source detail inside the
					// window. The board hangs on the FETCH of 124563 - the
					// first newly-cacheable instruction fetch after TRR LCIL
					// raises the lower limit past the code's own page (52) -
					// so the question the golden run must answer is: on that
					// fetch, hit or miss, what tag/data sit in the cache
					// line at that index, and which bus supplied the word.
					// One line per cycle-controller TERM rise while P is in
					// the window: the cache line at CA (tag chips 16F/20F,
					// data chips 23F/24F, used/valid from 21F), the HIT
					// chain, the inhibit-map bit, and both CD buses (cache
					// contribution vs what the CPU received). fetch=1 marks
					// instruction-fetch cycles (CGA DCD CFETCH flop).
					{
						static int fx_prev_term = 0;
						static long fx_prints = 0;
						static long fx_n[2][2];        // [P==124563?0:1][hit] fetch counters
						static long fx_next_sum = 0;
						static int fx_sum_prints = 0;
						int term = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__TERM_reg;
						int in_win = (it_p >= 0124400u && it_p <= 0125000u);
						if (term && !fx_prev_term && in_win)
						{
							unsigned ca   = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x7FFu;
							unsigned ppn  = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_ppn_23_10 & 0x3FFFu;
							int hit   = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_hit;
							int fetch = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__DCD__DOT__s_cfetchff_q;
							unsigned tag = ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_16F__DOT__g_async__DOT__tmm_memory_array[ca] << 8)
							             |  (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_20F__DOT__g_async__DOT__tmm_memory_array[ca];
							unsigned dat = ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_23F__DOT__g_async__DOT__tmm_memory_array[ca] << 8)
							             |  (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_24F__DOT__g_async__DOT__tmm_memory_array[ca];
							unsigned uidx = ca & 0x3FFu;
							unsigned umem = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_21F__DOT__am_memory_array[uidx] & 0xFu;
							unsigned uval = ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_21F__DOT__valid[uidx >> 5] >> (uidx & 31u)) & 1u;
							int allow = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__PT__DOT__CHIP_20G__DOT__ims_memory_array[ppn];
							if (fetch && it_p == 0124563u) fx_n[0][hit ? 1 : 0]++;
							if (fetch && it_p == 0124564u) fx_n[1][hit ? 1 : 0]++;
							if (fx_prints < 120000)
							{
								printf("[inh] fx cnt=%ld P=%06o csa=%05o fetch=%d ca=%04o ppn=%05o allow=%d hit=%d h0n=%d h1n=%d ihit=%d | tag=%06o dat=%06o used=%x uval=%d | cd_cache=%06o cd_cpu=%06o mreq=%d A=%06o\n",
									cnt, it_p, it_csa, fetch, ca, ppn, allow, hit,
									(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__MMU_HIT__DOT__HIT0n_reg,
									(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__MMU_HIT__DOT__HIT1n_reg,
									(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__PAL_44402_UBITS__DOT__gen_enable__DOT__IHIT_reg,
									tag, dat, umem, uval,
									(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_mmu_cd_15_0_in & 0xFFFFu,
									(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_proc_cd_15_0_in & 0xFFFFu,
									(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__s_csmreq,
									it_a);
								if (++fx_prints == 120000) { printf("[inh] fx print cap reached\n"); fflush(stdout); }
							}
						}
						fx_prev_term = term;
						if (cnt >= fx_next_sum && fx_sum_prints < 400)
						{
							fx_next_sum = cnt + 50000000;
							printf("[inh] fx summary cnt=%ld | fetch@124563: hit=%ld miss=%ld | fetch@124564: hit=%ld miss=%ld\n",
								cnt, fx_n[0][1], fx_n[0][0], fx_n[1][1], fx_n[1][0]);
							fflush(stdout);
							fx_sum_prints++;
						}
					}
				}
			}
#endif // ND120_NO_CACHE (end of the ND120_INHIBIT_TRACE probe)

			// Liveness probe (ND120_LIVE_TRACE=<cycles>, run-time). Every
			// <cycles> evals print the P register, CSA, and the P range
			// seen since the last line - enough to tell "halted", "tight
			// loop", "waiting at a prompt" and "running a long job" apart
			// without a rebuild. Written 29-AUG-2026 when CACHE-1X0-A00 sat
			// at its "Initialize memory : >" prompt ignoring every keystroke.
			{
				static long lv_every = -1, lv_next = 0;
				static unsigned lv_pmin = 0xFFFFu, lv_pmax = 0, lv_pchg = 0, lv_plast = 0xFFFFFFFFu;
				if (lv_every < 0) { const char *e = getenv("ND120_LIVE_TRACE"); lv_every = e ? atol(e) : 0; }
				if (lv_every > 0)
				{
					auto rp = top->rootp;
					// the two latched halves of P survive a build without
					// --public-flat-rw (the flat s_reg2_p_15_0 alias does not, and
					// --public-flat-rw makes the whole sim ~4x slower)
					unsigned p = (((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__P_REG_2__DOT__L_PR_8_15__DOT__reg8bit & 0xFFu) << 8)
					           | ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__P_REG_2__DOT__L_PR_7_0__DOT__reg8bit & 0xFFu);
					if (p != lv_plast) { lv_pchg++; lv_plast = p; }
					if (p < lv_pmin) lv_pmin = p;
					if (p > lv_pmax) lv_pmax = p;
					if (cnt >= lv_next)
					{
						lv_next = cnt + lv_every;
						printf("[live] cnt=%d csa=%05o P=%06o | P range %06o..%06o, %u changes\n",
							cnt, (unsigned)top->CSA_12_0, p, lv_pmin, lv_pmax, lv_pchg);
						// console UART (2661, CHIP_32H) as the CPU sees it: does a
						// received byte sit unread (RxRDY), is the receiver even on
						// NOTE 31-AUG-2026: this used to print
						// regReceiveHoldingRegister. Commit 8111c7e ("uart: add a
						// 16-byte RX FIFO") deleted that register - the CPU now
						// reads s_rx_fifo[s_rx_rptr], and the byte still shifting
						// in lives in regRxShift - so the old name no longer
						// compiled at all and runSim could not be built. Printing
						// the shift register plus both FIFO pointers says more than
						// the single register ever did: rptr != wptr means a byte
						// is waiting for the CPU.
						printf("[live]   uart status=%02x rxshift=%02x rptr=%02u wptr=%02u mode=%02x cmd=%02x rxEnabled=%d txEnabled=%d rxState=%d\n",
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__regStatusRegister & 0xFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__regRxShift & 0xFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__s_rx_rptr & 0x1Fu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__s_rx_wptr & 0x1Fu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__regModeRegister & 0xFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__regCommandRegister & 0xFFu,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__cmd_rxEnabled,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__cmd_txEnabled,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__rxState);
						fflush(stdout);
						lv_pmin = 0xFFFFu; lv_pmax = 0; lv_pchg = 0;
					}
				}
			}

			// CSA watch (ND120_CSA_WATCH="1071,2046,3713" - octal, run-time).
			// Prints every visit to the listed microword addresses. Written
			// 29-AUG-2026 to find out whether the three PROM microwords that
			// carry the WCHIM command (COMM=021, MIS=00 at 01071, 02046 and
			// 03713 - found by scanning AM27256_4513{2,3}L.hex) are ever
			// executed, after WCHIM_n was seen never to move.
			{
				static int cw_init = 0, cw_n = 0, cw_prints = 0;
				static unsigned cw_addr[16];
				static unsigned cw_prev_csa = 0xFFFFu;
				if (!cw_init)
				{
					cw_init = 1;
					if (const char *e = getenv("ND120_CSA_WATCH"))
					{
						const char *s = e;
						while (*s && cw_n < 16)
						{
							char *end;
							unsigned v = (unsigned)strtoul(s, &end, 8);
							if (end == s) break;
							cw_addr[cw_n++] = v;
							s = end;
							while (*s == ',' || *s == ' ') s++;
						}
					}
				}
				if (cw_n > 0)
				{
					unsigned csa = (unsigned)top->CSA_12_0;
					auto rp = top->rootp;
					// what the DGA decode actually sees: the microword's COMM and
					// MIS fields, the CYC's LCS (1 = control store still LOADING;
					// the DGA gates every COMM decode with LCS_n), and the A188
					// flop Q3 that IS WCHIM_n
					unsigned long long cs = (unsigned long long)rp->ND120_TOP__DOT__CORE__DOT__s_csbits;
					int lcs     = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44403_UCYIN0__DOT__gen_enable__DOT__LCS;
					int wchim_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__COMM__DOT__A188__DOT__gen_enable__DOT__MEMORY_4__DOT__gen_enable__DOT__q_r;
					static int cw_lcs_prev = -1;
					if (lcs != cw_lcs_prev)
					{
						printf("[csawatch] cnt=%d LCS %d->%d (csa=%05o)\n", cnt, cw_lcs_prev, lcs, csa);
						cw_lcs_prev = lcs;
					}
					if (csa != cw_prev_csa)
					{
						for (int i = 0; i < cw_n; i++)
							if (csa == cw_addr[i] && cw_prints < 200)
							{
								printf("[csawatch] cnt=%d csa=%05o (from %05o) comm=%02o mis=%d lcs=%d wchim_n=%d\n",
									cnt, csa, cw_prev_csa, (unsigned)((cs >> 32) & 0x1f), (unsigned)((cs >> 42) & 3), lcs, wchim_n);
								if (++cw_prints == 200) printf("[csawatch] print cap reached\n");
							}
						cw_prev_csa = csa;
					}
				}
			}

			// Cycle-controller window dump (ND120_CYC_WINDOW="<from>:<to>" in
			// cnt, run-time). Every eval inside the window prints the CYC FSM
			// state (PAL_44601 CC3..CC0 / TERM), the DGA's SHORT and EROF, the
			// WCHIM_n / WCLIM_n pair and the CSA - to see which cycle states a
			// given microword actually walks through. Written 29-AUG-2026 for
			// the inhibit-map sweep at microwords 02045/02046: WCLIM_n =
			// WCHIM_n | EORF_n and EORF is the 44307C "misc write pulse" of
			// state d only, so a cycle that terminates before d never writes.
			{
				static long cy_from = -1, cy_to = -1;
				if (cy_from < 0)
				{
					cy_from = 0; cy_to = 0;
					if (const char *e = getenv("ND120_CYC_WINDOW"))
					{
						cy_from = atol(e);
						const char *c = strchr(e, ':');
						cy_to = c ? atol(c + 1) : cy_from + 200;
					}
				}
				if (cy_to > 0 && cnt >= cy_from && cnt <= cy_to)
				{
					auto rp = top->rootp;
					printf("[cyc] cnt=%d clk=%d csa=%05o CC=%d%d%d%d TERM=%d short_n=%d erof=%d wchim_n=%d wclim_n=%d\n",
						cnt, (int)top->sysclk, (unsigned)top->CSA_12_0,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC3_reg,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC2_reg,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC1_reg,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC0_reg,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__TERM_reg,
						(int)!rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__COMM__DOT__A214__DOT__gen_enable__DOT__MEMORY_2__DOT__gen_enable__DOT__q_r,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__COMM__DOT__s_erof,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__COMM__DOT__A188__DOT__gen_enable__DOT__MEMORY_4__DOT__gen_enable__DOT__q_r,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__s_wclim_n);
				}
			}

#ifndef ND120_NO_CACHE // these three probes read cache internals a CACHE=0 build compiles out
			// Cache write chain probe (ND120_CACHE_TRACE=1, run-time). CACHE-1X0-A00
			// test 2 fails in Verilator exactly as on the board (29-AUG-2026) while
			// the inhibit map is proven correct, so the fault is downstream of
			// WCINH_n:  EWC = BRK_n & CON & WCINH_n  ->  PAL 44402D WCA  ->
			// PAL 44511A CWR = MREQ*WCA  ->  /CUP := /CWR*MREQ.  This prints every
			// transition of WCA (as the 44511 sees it), CWR, CWR_hold and CUP_n,
			// with MREQ, CYD, BRK_n, IHIT, the HIT comparators and WCINH_n, and a
			// count line every 50M cycles so a chain that never moves is visible
			// as zeros rather than as silence.
			{
				static int ct_on = -1, ct_prints = 0;
				static int ct_wca = -1, ct_cwr = -1, ct_cup = -1, ct_hold = -1;
				static long ct_next = 0, n_wca = 0, n_cwr = 0, n_cup0 = 0, n_mreq = 0, n_wcinh1 = 0, n_cyd = 0;
				if (ct_on < 0) ct_on = getenv("ND120_CACHE_TRACE") ? 1 : 0;
				if (ct_on)
				{
					auto rp = top->rootp;
					#define CT_ROOT ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__
					int wca   = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CMDDEC__DOT__PAL_44511_ULEV0__DOT__gen_enable__DOT__WCA;
					int cwr   = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_cwr;
					int hold  = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CMDDEC__DOT__PAL_44511_ULEV0__DOT__gen_enable__DOT__CWR_hold;
					int cup_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CMDDEC__DOT__PAL_44511_ULEV0__DOT__gen_enable__DOT__CUP_n_reg;
					int mreq  = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__s_csmreq;
					int cyd   = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_cyd;
					int brk_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_brk_n;
					int ihit  = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__PAL_44402_UBITS__DOT__gen_enable__DOT__IHIT_reg;
					int hit0n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__MMU_HIT__DOT__HIT0n_reg;
					int hit1n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__MMU_HIT__DOT__HIT1n_reg;
					int wcinh_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__PT__DOT__CHIP_20G__DOT__data_out;  // s_wcinh_n itself is folded; this is the RAM output it comes from
					if (wca) n_wca++;
					if (cwr) n_cwr++;
					if (!cup_n) n_cup0++;
					if (mreq) n_mreq++;
					if (wcinh_n) n_wcinh1++;
					if (cyd) n_cyd++;
					if ((wca != ct_wca || cwr != ct_cwr || cup_n != ct_cup || hold != ct_hold) && ct_prints < 600)
					{
						printf("[cache] cnt=%d csa=%05o wca=%d cwr=%d hold=%d cup_n=%d | mreq=%d cyd=%d brk_n=%d ihit=%d hit0n=%d hit1n=%d wcinh_n=%d\n",
							cnt, (unsigned)top->CSA_12_0, wca, cwr, hold, cup_n, mreq, cyd, brk_n, ihit, hit0n, hit1n, wcinh_n);
						if (++ct_prints == 600) printf("[cache] print cap reached\n");
					}
					ct_wca = wca; ct_cwr = cwr; ct_cup = cup_n; ct_hold = hold;
					if (cnt >= ct_next)
					{
						ct_next = cnt + 50000000;
						printf("[cache] summary cnt=%d: wca=%ld cwr=%ld cup_low=%ld mreq=%ld wcinh_high=%ld cyd=%ld (eval counts)\n",
							cnt, n_wca, n_cwr, n_cup0, n_mreq, n_wcinh1, n_cyd);
						fflush(stdout);
					}
				}
			}

			// Cache window dump (ND120_CACHE_WIN="<nth WCA rise>:<evals>", run-time).
			// From the n-th rising edge of WCA on, print every eval for <evals>
			// evals: cycle state, CSA, cache address CA, the physical page PPN
			// on the bus, the tag the tag RAMs read back (16F/20F), the data the
			// data RAMs read back (23F/24F), the used bits (21F), the two HIT
			// comparators, WCA/CWR/CUP and the CD bus into the MMU and into the
			// CPU. Written 29-AUG-2026 for the second cache fault: after the CUP
			// fix, CACHE-1X0-A00 test 2 still says hits return memory data and
			// reads do not fill the cache, then crashes on an illegal
			// instruction - so a write-then-read of one line has to be seen.
			{
				static long cw_nth = -1, cw_left = 0, cw_seen = 0, cw_at_from = 0, cw_at_to = 0;
				static int cw_prev_wca = 0;
				static long cw_ppn = 0; static int cw_wr = 0;
				if (cw_nth < 0)
				{
					cw_nth = 0;
					if (const char *e = getenv("ND120_CACHE_WIN"))
					{
						cw_nth = atol(e);
						const char *c = strchr(e, ':');
						cw_left = c ? atol(c + 1) : 400;
						if (cw_nth <= 0) cw_nth = 1;
					}
					// ND120_CWIN_AT="<from>:<to>" - the same dump for a cnt window.
					// (Counts are NOT reproducible between runs: the typing times on
					// the console fifo shift them. Prefer the WCA-count trigger.)
					if (const char *e = getenv("ND120_CWIN_AT"))
					{
						cw_at_from = atol(e);
						const char *c = strchr(e, ':');
						cw_at_to = c ? atol(c + 1) : cw_at_from + 200;
						if (cw_nth == 0) { cw_nth = 1; cw_left = 0; }
					}
					// ND120_CWIN_PPN=<octal page>: count only WCAs on that page;
					// ND120_CWIN_WRITE=1: only WCAs during a WRITE cycle (DGA A160 Q3).
					if (const char *e = getenv("ND120_CWIN_PPN")) cw_ppn = strtol(e, nullptr, 8);
					cw_wr = getenv("ND120_CWIN_WRITE") ? 1 : 0;
				}
				if (cw_nth > 0)
				{
					auto rp = top->rootp;
					int wca = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CMDDEC__DOT__PAL_44511_ULEV0__DOT__gen_enable__DOT__WCA;
					int cw_ok = 1;
					if (cw_ppn > 0 && ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_ppn_23_10 & 0x3FFFu) != (unsigned)cw_ppn) cw_ok = 0;
					if (cw_wr && !(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__COMM__DOT__A160__DOT__gen_enable__DOT__MEMORY_4__DOT__gen_enable__DOT__q_r) cw_ok = 0;
					if (wca && !cw_prev_wca && cw_ok) cw_seen++;
					cw_prev_wca = wca;
					int cw_in_at = (cw_at_to > 0 && cnt >= cw_at_from && cnt <= cw_at_to);
					if (cw_in_at) cw_left = 1;
					if (cw_seen >= cw_nth && cw_left > 0)
					{
						cw_left--;
						unsigned tag = ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_16F__DOT__g_async__DOT__tmm_memory_array[(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x7FFu] << 8)
						             |  (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_20F__DOT__g_async__DOT__tmm_memory_array[(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x7FFu];
						unsigned dat = ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_23F__DOT__g_async__DOT__tmm_memory_array[(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x7FFu] << 8)
						             |  (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_24F__DOT__g_async__DOT__tmm_memory_array[(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x7FFu];
						printf("[cwin] cnt=%d csa=%05o CC=%d%d%d%d T=%d | ca=%04o ppn=%05o la=%05o | tag=%06o dat=%06o used=%x hit0n=%d hit1n=%d ihit=%d | wca=%d cwr=%d cup_n=%d mreq=%d cyd=%d brk_n=%d lsh=%d | cd_mmu=%06o cd_cpu=%06o | ca10q=%d ca10rst=%d uclk=%d write=%d | sweep=%d nubi_reg=%d nubd_reg=%d used_mem=%x cclr_n=%d\n",
							cnt, (unsigned)top->CSA_12_0,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC3_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC2_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC1_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC0_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__TERM_reg,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x7FFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_ppn_23_10 & 0x3FFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_la_23_10 & 0x3FFFu,
							tag, dat,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_21F__DOT__data4bit & 0xFu,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__MMU_HIT__DOT__HIT0n_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__MMU_HIT__DOT__HIT1n_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__PAL_44402_UBITS__DOT__gen_enable__DOT__IHIT_reg,
							wca,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_cwr,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CMDDEC__DOT__PAL_44511_ULEV0__DOT__gen_enable__DOT__CUP_n_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__s_csmreq,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_cyd,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_brk_n,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44404_UCYIN1__DOT__gen_enable__DOT__DLSHADOW_reg,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_mmu_cd_15_0_in & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_proc_cd_15_0_in & 0xFFFFu,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__COMM__DOT__MEMORY_63__DOT__gen_enable_arst__DOT__q_r,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__COMM__DOT____Vcellinp__MEMORY_63__reset,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__uclk_pa,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__DCD__DOT__DGA__DOT__COMM__DOT__A160__DOT__gen_enable__DOT__MEMORY_4__DOT__gen_enable__DOT__q_r,
							0 /* sweep_active: gone, Am9150 clears in one clock since 29-AUG-2026 */,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__PAL_44402_UBITS__DOT__gen_enable__DOT__NUBI_n_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__PAL_44402_UBITS__DOT__gen_enable__DOT__NUBD_n_reg,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_21F__DOT__am_memory_array[(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x3FFu] & 0xFu,
							0 /* reset_n_d: gone with the sweep */);
						if (cw_left == 0 && !cw_in_at) { printf("[cwin] window done\n"); fflush(stdout); }
						if (cw_in_at && cnt == cw_at_to) { printf("[cwin] window done\n"); fflush(stdout); }
					}
				}
			}

			// Per-cycle cache log for one physical page (ND120_CACHE_PPN=<octal>,
			// run-time). One line per cycle-controller TERM (T=1) whose PPN is
			// that page, plus one per WCA rise: CA, tag/data read back, used
			// bits, both HIT comparators, whether WCA/MREQ were seen during the
			// cycle, and the CD bus at the end. Written 29-AUG-2026 to follow
			// the CACHE-1X0-A00 test's own lines (it works in page 60) through
			// write -> read-back, which the 1500-eval window is too short for.
			{
				static long cp_ppn = -1, cp_prints = 0;
				static int cp_wca_seen = 0, cp_mreq_seen = 0, cp_prev_wca = 0, cp_prev_t = 0;
				if (cp_ppn < 0) { const char *e = getenv("ND120_CACHE_PPN"); cp_ppn = e ? strtol(e, nullptr, 8) : 0; if (!e) cp_ppn = 0; }
				if (cp_ppn > 0 && cp_prints < 30000)
				{
					auto rp = top->rootp;
					int wca  = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CMDDEC__DOT__PAL_44511_ULEV0__DOT__gen_enable__DOT__WCA;
					int mreq = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__s_csmreq;
					int term = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__TERM_reg;
					unsigned ppn = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_ppn_23_10 & 0x3FFFu;
					if (wca) cp_wca_seen = 1;
					if (mreq) cp_mreq_seen = 1;
					int wca_rise = wca && !cp_prev_wca;
					int t_rise = term && !cp_prev_t;
					cp_prev_wca = wca; cp_prev_t = term;
					// Skip the inhibit-map sweeps (microwords 01071/02046 walk every
					// page number across the PPN bus) and quiet misses: keep every
					// WCA, and every TERM where something in the cache matched.
					unsigned cp_csa = (unsigned)top->CSA_12_0;
					int cp_sweep = (cp_csa == 01070u || cp_csa == 01071u || cp_csa == 02045u || cp_csa == 02046u || cp_csa == 03712u || cp_csa == 03713u);
					int cp_h0 = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__MMU_HIT__DOT__HIT0n_reg;
					unsigned cp_used = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_21F__DOT__data4bit & 0xFu;
					int cp_interesting = wca_rise || cp_h0 == 0 || cp_used != 0;
					// 29-AUG-2026 late: also every clock of the WCA pulse (the Am9150
					// writes on every posedge while /W is low), with the RAM's real
					// contents (array + valid, NOT the one-clock-stale data4bit copy)
					// for the index CA[9:0], the PAL's data into it, and the PAL inputs
					// that decide those bits (PD2 = its output enable, DT, RT).
					if ((wca_rise || t_rise || wca) && ppn == (unsigned)cp_ppn && !cp_sweep && (cp_interesting || wca))
					{
						unsigned uidx = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x3FFu;
						unsigned umem = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_21F__DOT__am_memory_array[uidx] & 0xFu;
						unsigned uval = ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_21F__DOT__valid[uidx >> 5] >> (uidx & 31u)) & 1u;
						unsigned tag = ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_16F__DOT__g_async__DOT__tmm_memory_array[(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x7FFu] << 8)
						             |  (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_20F__DOT__g_async__DOT__tmm_memory_array[(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x7FFu];
						unsigned dat = ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_23F__DOT__g_async__DOT__tmm_memory_array[(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x7FFu] << 8)
						             |  (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_24F__DOT__g_async__DOT__tmm_memory_array[(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x7FFu];
						printf("[cpg] cnt=%d %s csa=%05o ca=%04o ppn=%05o tag=%06o dat=%06o used=%x hit0n=%d hit1n=%d ihit=%d | wca_in_cycle=%d mreq_in_cycle=%d cup_n=%d brk_n=%d lsh=%d | cd_mmu=%06o cd_cpu=%06o | umem=%x uval=%d din=%x pd2=%d dt_n=%d rt_n=%d nubi_reg=%d nubd_reg=%d we_n=%d cclr_n=%d\n",
							cnt, wca_rise ? "WCA " : (t_rise ? "TERM" : "wca-"), (unsigned)top->CSA_12_0,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x7FFu, ppn, tag, dat,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_21F__DOT__data4bit & 0xFu,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__MMU_HIT__DOT__HIT0n_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__MMU_HIT__DOT__HIT1n_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__PAL_44402_UBITS__DOT__gen_enable__DOT__IHIT_reg,
							cp_wca_seen, cp_mreq_seen,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CMDDEC__DOT__PAL_44511_ULEV0__DOT__gen_enable__DOT__CUP_n_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_brk_n,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44404_UCYIN1__DOT__gen_enable__DOT__DLSHADOW_reg,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_mmu_cd_15_0_in & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_proc_cd_15_0_in & 0xFFFFu,
							umem, uval,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__s_21f_in & 0xFu,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__s_pd2,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__s_dt_n,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__s_rt_n,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__PAL_44402_UBITS__DOT__gen_enable__DOT__NUBI_n_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__PAL_44402_UBITS__DOT__gen_enable__DOT__NUBD_n_reg,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__s_wca_n,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__s_cclr_n);
						if (++cp_prints == 30000) { printf("[cpg] print cap reached\n"); fflush(stdout); }
					}
					// ND120_CACHE_PPN_DT=1 (29-AUG-2026, 23:00): per-CLOCK dump of every
					// DATA cycle (DT_n low) and every WCA pulse on the page - the HIT
					// chain exactly as the cycle FSM sees it, clock by clock. Run 17
					// showed the test's read with every HIT ingredient present at TERM
					// (tags match, used bit set and valid, RT and DT) and the memory
					// word delivered anyway; this shows when inside the cycle HIT was
					// low, and which input made it low.
					static int  cp_dt_mode = -1;
					static long cp_dt_prints = 0;
					if (cp_dt_mode < 0) cp_dt_mode = getenv("ND120_CACHE_PPN_DT") ? 1 : 0;
					if (cp_dt_mode)
					{
						int cc = ((int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC3_reg << 3)
						       | ((int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC2_reg << 2)
						       | ((int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC1_reg << 1)
						       |  (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC0_reg;
						int dt_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__s_dt_n;
						if (ppn == (unsigned)cp_ppn && (cc != 0 || term || mreq || wca) && (!dt_n || wca) && cp_dt_prints < 100000)
						{
							unsigned ca = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_ca_10_0 & 0x7FFu;
							unsigned uidx = ca & 0x3FFu;
							unsigned tag = ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_16F__DOT__g_async__DOT__tmm_memory_array[ca] << 8)
							             |  (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_20F__DOT__g_async__DOT__tmm_memory_array[ca];
							unsigned dat = ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_23F__DOT__g_async__DOT__tmm_memory_array[ca] << 8)
							             |  (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_24F__DOT__g_async__DOT__tmm_memory_array[ca];
							printf("[cdt] cnt=%d csa=%05o CC=%x T=%d U=%d cyd=%d mreq=%d | ca=%04o ppn=%05o | hit=%d h0n=%d h1n=%d oubi=%d oubd=%d rt_n=%d dt_n=%d cwr=%d cwrh=%d brk_n=%d we_n=%d pd2=%d ihit=%d | umem=%x uval=%d tag=%06o dat=%06o | cd_mmu=%06o cd_cpu=%06o\n",
								cnt, (unsigned)top->CSA_12_0, cc, term,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__uclk_pa,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_cyd, mreq,
								ca, ppn,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_hit,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__MMU_HIT__DOT__HIT0n_reg,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__MMU_HIT__DOT__HIT1n_reg,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT____Vcellinp__PAL_44402_UBITS__OUBI,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT____Vcellinp__PAL_44402_UBITS__OUBD,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__s_rt_n, dt_n,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_cwr,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CMDDEC__DOT__PAL_44511_ULEV0__DOT__gen_enable__DOT__CWR_hold,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_brk_n,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__s_wca_n,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__s_pd2,
								(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__PAL_44402_UBITS__DOT__gen_enable__DOT__IHIT_reg,
								(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_21F__DOT__am_memory_array[uidx] & 0xFu,
								(int)(((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__MMU__DOT__CACHE__DOT__CHIP_21F__DOT__valid[uidx >> 5] >> (uidx & 31u)) & 1u),
								tag, dat,
								(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_mmu_cd_15_0_in & 0xFFFFu,
								(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_proc_cd_15_0_in & 0xFFFFu);
							if (++cp_dt_prints == 100000) { printf("[cdt] print cap reached\n"); fflush(stdout); }
						}
					}
					if (t_rise) { cp_wca_seen = 0; cp_mreq_seen = 0; }
				}
			}
#endif // ND120_NO_CACHE (end of ND120_CACHE_TRACE / ND120_CACHE_WIN / ND120_CACHE_PPN probes)

			// MAP counter (ND120_COUNT_MAP=1, 30-AUG-2026). One falling edge
			// of MAP_n = one macro instruction dispatched - the last
			// microinstruction of every macro instruction runs MAP, cache
			// hit or miss. The panel's mips_counter counts this exact
			// event on the Nexys (it counted FETCH before, and a warm
			// cache starved it to 00.00). Validation: run together with
			// ND120_TRACE_VERIFY - the trace writes ONE LINE per macro
			// instruction, so trace lines and MAP edges over the same
			// window must agree.
			{
				static int mc_on = -1;
				if (mc_on < 0) mc_on = getenv("ND120_COUNT_MAP") ? 1 : 0;
				if (mc_on)
				{
					static unsigned char      mc_prev = 1;
					static unsigned long long mc_edges = 0;
					static long               mc_next = 50000000;
					unsigned char m = (unsigned char)top->rootp->ND120_TOP__DOT__s_debug_map_n;
					if (mc_prev && !m) mc_edges++;
					mc_prev = m;
					if (cnt >= mc_next)
					{
						printf("[map] cnt=%d edges=%llu\n", cnt, mc_edges);
						mc_next += 50000000;
					}
				}
			}

			// CFETCH counter (ND120_COUNT_CFETCH=1, 31-AUG-2026). CFETCH is the
			// CGA_DCD-registered "command fetch" strobe - it rises once when the
			// decoder takes a new macro instruction, so unlike DEBUG_FETCH (a
			// memory-cycle qualifier, which a warm cache starved to 00.00) and
			// MAP_n (a board net gated by FORM and the cycle state) it does not
			// depend on where the fetch came from. This is the THIRD tap tried for
			// the panel MIPS field; the first two were flashed without a sim proof
			// and both read 00.00. THE RULE: no tap goes to the board until its
			// edge count here agrees with the instruction count that
			// ND120_TRACE_VERIFY writes over the same window.
			{
				static int cf_on = -1;
				if (cf_on < 0) cf_on = getenv("ND120_COUNT_CFETCH") ? 1 : 0;
				if (cf_on)
				{
					static unsigned char cf_prev = 0;
					static long          cf_next = 10000000;   // report every 10M clocks
					unsigned char f = (unsigned char)top->rootp->ND120_TOP__DOT__s_debug_cfetch_dbg;
					// s_debug_cfetch_dbg is the TOP-LEVEL routed wire (ND120_TOP ->
					// CORE -> ND3202D -> CPU_15 -> PROC -> CGA), i.e. exactly the
					// signal the FPGA panel counter would see - not an internal
					// probe. After the 31-AUG re-point it carries the GPR<-CD
					// strobe. It is a one-clock enable product, so count it HIGH,
					// the same way the panel's edge detector will.
					if (f) g_cfetch_rises++;
					// REMOVED 31-AUG-2026: the side-by-side "candidate tap"
					// probe that recomputed the GPR<-CD load from ALU internals
					// (s_gprc_2_0, s_aluclk_en_i, s_cd_15_0) and counted the CGA
					// s_cfetch net. That search is over - the winning tap is
					// XGPRLOAD_DBG, and s_debug_cfetch_dbg above already carries
					// it as a routed top-level wire, which is what the FPGA panel
					// counter actually sees. The internals it read are pure
					// combinational aliases that Verilator collapses, so the code
					// no longer compiled at all and runSim could not be built.
					cf_prev = f;
					if (cnt >= cf_next)
					{
						unsigned long long wc = g_cfetch_rises - g_arm_cfetch;
						unsigned long long wm = g_macro_boundaries - g_arm_macro;
						printf("[cfetch] cnt=%d rises=%llu macro=%llu | armed=%d window: cfetch=%llu macro=%llu ratio=%.4f\n",
						    cnt, g_cfetch_rises, g_macro_boundaries, g_arm_taken,
						    wc, wm, wm ? (double)wc / (double)wm : 0.0);
						fflush(stdout);
						cf_next += 10000000;
					}
				}
			}

			// ND120_WCS_RD=1 (30-AUG-2026): per-CLOCK dump of every RWCS
			// (read/write control store) microinstruction - CACHE-1X0-A00 test 1
			// reads the upper 1K of the WCS back OR-ed with a constant (board:
			// 163400 on bits 63:48). Shows the cycle state, the bank enables, the
			// addresses, BOTH banks' outputs (the WCS output is their wired-OR),
			// and the TCV capture, so the clock where the wrong bank still
			// drives can be read off directly.
			{
				static int  wr_mode = -1;
				static long wr_prints = 0;
				static int  wr_prev_rwcs = 0;
				if (wr_mode < 0) wr_mode = getenv("ND120_WCS_RD") ? 1 : 0;
				if (wr_mode && wr_prints < 400000)
				{
					auto rp = top->rootp;
					int rwcs = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CMDDEC__DOT__PAL_44408B_VEXFIX__DOT__gen_enable__DOT__RWCS_int;
					int cc = ((int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC3_reg << 3)
					       | ((int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC2_reg << 2)
					       | ((int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC1_reg << 1)
					       |  (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__CC0_reg;
					unsigned wr_uua = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__s_uua & 0xFFFu;
					if ((rwcs || wr_prev_rwcs) && wr_uua >= 07000u && wr_uua <= 07003u)
					{
						unsigned long long lo = (unsigned long long)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__WCS__DOT__s_lua_csbits_out;
						unsigned long long up = (unsigned long long)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__WCS__DOT__s_uua_csbits_out;
						printf("[wcs] cnt=%d csa=%05o CC=%x T=%d rwcs=%d ewca=%d | elow_n=%d eupp_n=%d lua=%05o uua=%04o | lo63_48=%06o up63_48=%06o lo15_0=%06o up15_0=%06o ce16C=%d ce16D=%d | ecsl_d=%d idbout=%06o cap=%06o wcstb_n=%d | idb: cs=%06o mmu=%06o proc=%06o board=%06o bif=%06o mem=%06o io_reg=%06o io_uart=%06o io_pan=%06o -> proc_in=%06o | cswan=%d%d rf=%d ew_n=%x\n",
							cnt, (unsigned)top->CSA_12_0, cc,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__PAL_44601_UCYCFSM__DOT__TERM_reg,
							rwcs,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__MIC_IPOS__DOT__s_ewca,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__s_elow_n,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__s_eupp_n,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__ACAL__DOT__s_lua & 0x1FFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__s_uua & 0xFFFu,
							(unsigned)((lo >> 48) & 0xFFFFull), (unsigned)((up >> 48) & 0xFFFFull),
							(unsigned)(lo & 0xFFFFull), (unsigned)(up & 0xFFFFull),
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__WCS__DOT__CHIP_16C__DOT__regCE_n,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__WCS__DOT__CHIP_16D__DOT__regCE_n,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__TCV__DOT__r_ecsl_n_d,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__TCV__DOT__regIDB_out & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__TCV__DOT__r_cs_capture & 0xFFFFu,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__CTL__DOT__s_wcstb_n,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_cs_IDB_15_0_out & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_mmu_idb_15_0_out & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_proc_IDB_15_0_out & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_cpu_idb_15_0_in & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_bif_idb_15_0_out & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__s_mem_idb_15_0_out & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__s_idb_15_0_reg_out & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__s_idb_15_0_uart_out & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__s_idb_15_0_pancal_out & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_proc_IDB_15_0_in & 0xFFFFu,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__MIC_INCOUNT__DOT__MEMORY_7__DOT__gen_enable_arst__DOT__q_r,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__MIC_INCOUNT__DOT__MEMORY_6__DOT__gen_enable_arst__DOT__q_r,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__s_rf_1_0 & 3u,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__s_ew_3_0_n & 0xFu);
						if (++wr_prints == 400000) { printf("[wcs] print cap reached\n"); fflush(stdout); }
					}
					wr_prev_rwcs = rwcs;
				}
			}

			// Control-store read-back probe (ND120_WCS_TRACE=1, run-time). CACHE-1X0-A00
			// test 1 (upper 1K of the WCS = the microinstruction cache store) reads
			// back every 16-bit group as expected | 0xE700 in groups 0, 1 and 3 on
			// the Nexys (29-AUG-2026). CPU_CS_WCS_21_22.v merges the lower and the
			// upper bank with a wired-OR, and IDT6168A_20.v gates each chip's output
			// with a REGISTERED copy of CE_n, so a bank keeps driving its last word
			// for one sysclk after it is deselected. This prints, at every falling
			// edge of ECSL_n (the TCV capture edge), the two bank enables, the two
			// bank outputs, the word the TCV selects and what it captured.
			{
				static int ws_on = -1, ws_prints = 0, ws_prev_ecsl = 1;
				if (ws_on < 0) ws_on = getenv("ND120_WCS_TRACE") ? 1 : 0;
				if (ws_on && ws_prints < 3000)
				{
					auto rp = top->rootp;
					int ecsl_d = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__TCV__DOT__r_ecsl_n_d;
					// r_ecsl_n_d is ECSL_n one sysclk late: a 1->0 step on it means
					// the capture edge was the previous eval; print this eval's
					// state too (the captured value is now in r_cs_capture).
					if (ws_prev_ecsl && !ecsl_d)
					{
						unsigned long long lo = (unsigned long long)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__WCS__DOT__s_lua_csbits_out;
						unsigned long long up = (unsigned long long)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__WCS__DOT__s_uua_csbits_out;
						printf("[wcs] cnt=%d csa=%05o lua=%05o uua=%04o elow_n=%d eupp_n=%d ew_n=%x | lower=%016llx upper=%016llx | sel=%06o captured=%06o\n",
							cnt, (unsigned)top->CSA_12_0,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__ACAL__DOT__s_lua & 0x1FFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__s_uua & 0xFFFu,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__s_elow_n,
							(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__s_eupp_n,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__s_ew_3_0_n & 0xFu,
							lo, up,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__TCV__DOT__regIDB_out & 0xFFFFu,
							(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__CS__DOT__TCV__DOT__r_cs_capture & 0xFFFFu);
						if (++ws_prints == 3000) printf("[wcs] print cap reached\n");
					}
					ws_prev_ecsl = ecsl_d;
				}
			}

#ifdef ND120_PROBE_MPYPHASE
			// Fine-grained phase capture around the MPY CONDENABL branch:
			// log every eval for a window starting at the post-boot COND word
			// (csa 04431), to see when s_zf changes vs ALUCLK/MCLK/MACLK and what
			// the CSEL latch (s_cond_n) samples. Reveals the correct pipeline phase.
			{
				static int cap = 0, passes = 0;
				auto rp = top->rootp;
				unsigned csa = (unsigned)top->CSA_12_0;
				if (cap == 0 && csa == 04431u && cnt > 300000 && passes < 12) { cap = 60; passes++; }
				if (cap > 0)
				{
					printf("[ph] cnt=%d csa=%05o r5=%06o q=%06o rb=%06o rli=%d alui6=%d alusts=%06o a=%06o b=%06o f=%06o csts=%d%d aluclk=%d mclk_en=%d\n",
						cnt, csa,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg13_r5_15_0,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_q_15_0,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_rb_15_0_out,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_rli_out,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_alui6,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_sts_15_0,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_a_15_0,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_b_15_0,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_f_15_0,
						(int)((rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_csts_1_0 >> 1) & 1),
						(int)(rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_csts_1_0 & 1),
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__s_aluclk,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CYC__DOT__MCLK_EN);
					if (--cap == 0 && passes >= 12) { printf("[ph] done\n"); fflush(stdout); }
				}
			}
#endif

#ifdef ND120_PROBE_RUNIDENT
			// RUN-area hang probe: on every OUTIDENT fall (CPU asking the bus
			// which device interrupts), dump the interrupt-request picture:
			// the CGA INTR request vector (IREQ, active low, bit=level), the
			// C-model bus interrupt input (BINT12_n), the Verilog-device
			// interrupt lines (s_dev_bint1x_n) and the raw ident address.
			// --public-flat-rw build.
			{
				static int oi_last = 1, oi_prints = 0;
				int oi = (int)top->OUTIDENT_n;
				if (!oi && oi_last && oi_prints < 60)
				{
					auto rp = top->rootp;
					printf("[ridnt] cnt=%d bd=%06o ireq_n=%06o bint{10,11,12,13}_n=%d%d%d%d\n",
						cnt,
						(unsigned)((~top->BD_23_0_n_OUT) & 0xFFFF),
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_ireq_15_0_n,
						(int)top->BINT10_n,
						(int)top->BINT11_n,
						(int)top->BINT12_n,
						(int)top->BINT13_n);
					oi_prints++;
					if (oi_prints == 60) { printf("[ridnt] capture done\n"); fflush(stdout); }
				}
				oi_last = oi;
			}
			// B2 (vector->IIC decode probe): during the INT14 internal-interrupt
			// the microcode's AIIC status-fence scan (PIC,LOSTS writes decreasing
			// fences, COND,IRQ finds the threshold) computes the IIC. INT14=hivec6
			// must give IIC 13 but we get IIC 11 (=hivec4). Dump the scan: does
			// HISTAT track the fence the microcode writes, and does the comparator
			// (HIVGES) flip at the right fence for hivec=6? Tight cnt window keeps
			// output bounded (the INT14 scan is ~cnt 17.384-17.389M).
			{
				auto rp = top->rootp;
				static unsigned scan_csa_last = 0xFFFF; static int scan_prints = 0;
				unsigned csa = (unsigned)top->CSA_12_0;
				if (cnt > 17380000 && csa >= 00670u && csa <= 00752u && csa != scan_csa_last && scan_prints < 300) {
					auto RD=[&](const char*){};(void)RD;
					unsigned histat=(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__VECGEN__DOT__CMP__DOT__s_histat_2_0;
					unsigned lostat=(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__VECGEN__DOT__CMP__DOT__s_lostat_2_0;
					unsigned hivec=(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__IRGEL__DOT__s_hivec_2_0;
					unsigned lovec=(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__IRGEL__DOT__s_lovec_2_0;
					int hivges=(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__VECGEN__DOT__CMP__DOT__s_hivges_out;
					int lovges=(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__VECGEN__DOT__CMP__DOT__s_lovges_out;
					unsigned hisin=(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__VECGEN__DOT__STAT__DOT__s_hisin_2_0;
					unsigned pics=(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__s_pics_2_0_out;
					unsigned picv=(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__s_picv_2_0_out;
					unsigned fidbo=(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__VECGEN__DOT__s_fidbo_2_0;
					int fidbo3=(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__VECGEN__DOT__s_fidbo3;
					int fidbo4=(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__VECGEN__DOT__s_fidbo4;
					unsigned areg=(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_a_15_0;
					unsigned pmask=(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_picmask_15_0_out;
					printf("[scan] cnt=%d csa=%05o histat=%o lostat=%o hivec=%o lovec=%o hivges=%d lovges=%d hisin=%o fidbo=%o hige=%d loge=%d pics=%o picv=%o A=%06o pmask=%06o\n",
						cnt, csa, histat, lostat, hivec, lovec, hivges, lovges, hisin, fidbo, fidbo3, fidbo4, pics, picv, areg, pmask);
					fflush(stdout); scan_prints++;
				}
				scan_csa_last = csa;
			}
			// Continuous edge log for the level-12 request chain: log every
			// TRANSITION of IREQ bit2 (live level-12 request into the INTR),
			// the RQBIT_2 latch (latched PID12), and its CLRQ_2 clear pulse.
			{
				static int q2_last = -1, i2_last = -1, c2_last = -1;
				static int tr_prints = 0;
				auto rp = top->rootp;
				int i2 = (int)((rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_ireq_15_0_n >> 2) & 1);
				int q2 = (int)((rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_mireq_15_0 >> 2) & 1);
				int c2 = (int)((rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_clrq_15_0 >> 2) & 1);
				if (cnt > 16000000 && (i2 != i2_last || q2 != q2_last || c2 != c2_last) && tr_prints < 300)
				{
					printf("[r12] cnt=%d ireq2_n=%d mireq2=%d clrq2=%d\n", cnt, i2, q2, c2);
					tr_prints++;
					if (tr_prints == 300) { printf("[r12] capture done\n"); fflush(stdout); }
				}
				i2_last = i2; q2_last = q2; c2_last = c2;
			}
			// Storm-clear probe: during the level-14 storm window, log every
			// TRANSITION of CLRQ bits 10/14, the HIK/LOK clear strobes with
			// their HX/LX bit codes, the latched IOXERR/bit14 requests and
			// the raw IOXERR input - shows whether the vector-read clear
			// (RVECT -> X-decode -> CLRQ) ever fires and where it points.
			{
				static unsigned last_sig = 0xFFFFFFFFu;
				static int sc_prints = 0;
				auto rp = top->rootp;
				unsigned clrq = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_clrq_15_0;
				unsigned mireq = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_mireq_15_0;
				int hik = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_hik;
				int lok = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_lok;
				unsigned hx = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_hx_2_0;
				unsigned lx = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_lx_2_0;
				int ioxe_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__s_ioxerr_n;
				unsigned sig = ((clrq & 0x4400u) << 8) ^ (hik << 7) ^ (lok << 6) ^ (hx << 3) ^ lx ^ ((mireq & 0x4400u) >> 1) ^ (ioxe_n << 15);
				if (cnt > 17300000 && sig != last_sig && sc_prints < 200)
				{
					printf("[sclr] cnt=%d csa=%05o clrq=%06o mireq_n=%06o hik=%d lok=%d hx=%o lx=%o ioxerr_n=%d\n",
						cnt, (unsigned)top->CSA_12_0, clrq, mireq, hik, lok, hx, lx, ioxe_n);
					sc_prints++;
					if (sc_prints == 200) { printf("[sclr] done\n"); fflush(stdout); }
				}
				last_sig = sig;
			}
			// PIL tracker + key-CSA counters during the storm: log every PIL
			// change; count EXT14 dispatches (csa 03756), TAIIC entries
			// (csa 03665) and MACRI (csa 00054) visits.
			{
				static int pil_last = -1, pil_prints = 0;
				static unsigned n_ext14 = 0, n_taiic = 0, n_macri = 0;
				static unsigned csa_last = 0xFFFF;
				static int cnt_reported = 0;
				auto rp = top->rootp;
				unsigned csa = (unsigned)top->CSA_12_0;
				int pil = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__sx_pil_3_0_out;
				if (csa != csa_last)
				{
					if (csa == 03756u) n_ext14++;
					if (csa == 03665u) n_taiic++;
					if (csa == 00054u) n_macri++;
				}
				csa_last = csa;
				if (cnt > 17000000 && pil != pil_last && pil_prints < 100)
				{
					printf("[pil] cnt=%d csa=%05o PIL=%d ext14=%u taiic=%u macri=%u\n",
						cnt, csa, pil, n_ext14, n_taiic, n_macri);
					pil_prints++;
				}
				pil_last = pil;
				if (!cnt_reported && cnt >= 18500000)
				{
					printf("[pil] FINAL counters: ext14=%u taiic=%u macri=%u PIL=%d\n", n_ext14, n_taiic, n_macri, pil);
					fflush(stdout);
					cnt_reported = 1;
				}
			}
			// IRGEL once-only-gate tracker: log every transition of the HI/LO
			// group request enables (HIENABN/LIENABN - the "dispatch once,
			// re-arm on command" gates), the group requests (HIRQ/LIRQ) and
			// detect lines, from the working startup EXT14s into the storm.
			{
				static unsigned ig_last = 0xFFFFFFFFu;
				static int ig_prints = 0;
				auto rp = top->rootp;
				int hien_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__IRGEL__DOT__s_hienab_n;
				int lien_n = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__IRGEL__DOT__s_lienab_n;
				int hirq = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__IRGEL__DOT__s_hirq;
				int lirq = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__IRGEL__DOT__s_lirq;
				int hidet = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__IRGEL__DOT__s_hidet;
				unsigned histat = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__VECGEN__DOT__s_histat_2_0;
				unsigned lostat = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__VECGEN__DOT__s_lostat_2_0;
				unsigned hivec = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_hivec_2_0;
				unsigned ig = (hien_n << 4) | (lien_n << 3) | (hirq << 2) | (lirq << 1) | hidet;
				ig = (ig << 12) | (histat << 9) | (lostat << 6) | (hivec << 3)
					| ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_hif << 2)
					| ((unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_hipassall << 1)
					| (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_hivges;
				if (cnt > 17370000 && ig != ig_last && ig_prints < 300)
				{
					printf("[irgel] cnt=%d csa=%05o hien_n=%d lien_n=%d hirq=%d lirq=%d hidet=%d histat=%o lostat=%o hivec=%o hif=%d hipass=%d hivges=%d\n",
						cnt, (unsigned)top->CSA_12_0, hien_n, lien_n, hirq, lirq, hidet, histat, lostat, hivec,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_hif,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_hipassall,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__INTR__DOT__CNTLR__DOT__s_hivges);
					ig_prints++;
					if (ig_prints == 300) { printf("[irgel] done\n"); fflush(stdout); }
				}
				ig_last = ig;
			}
#endif

#ifdef ND120_PROBE_SHIFT
			// Shift serial-input probe: whenever the microword runs with
			// CSALUM=11 (shift-loop mode: SSEL taken from the instruction bits
			// captured in ALU_CONTR MEMORY_46/47), log the whole serial-input
			// selection chain. Also log every LDIRV rise with the CD bus so we
			// can see what MEMORY_46/47 actually captured. --public-flat-rw.
			{
				static int shift_prints = 0, ldirv_prints = 0;
				static int ldirv_last = 0;
				auto rp = top->rootp;
				int ld = (int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__s_ldirv;
				unsigned cdnow = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__s_cd_15_0;
				if (cnt > 1500000 && ld != ldirv_last && ((cdnow >> 9) & 3u) != 0 && ldirv_prints < 200)
				{
					printf("[shp-ir] cnt=%d LDIRV %s cd=%06o alu_cd109=%d%d m46=%d m47=%d\n", cnt, ld ? "rise" : "fall", cdnow,
						(int)((rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_cd_10_9 >> 1) & 1),
						(int)(rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_cd_10_9 & 1),
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_memory46_q,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_memory47_q);
					ldirv_prints++;
				}
				ldirv_last = ld;
				unsigned alum = (unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_csalum_1_0;
				if (cnt > 1500000 && alum == 3u && shift_prints < 400)
				{
					printf("[shp] cnt=%d csa=%05o m46=%d m47=%d ssel=%d%d rri=%d rli=%d qli=%d sts7=%d f=%06o q=%06o alui6=%d aluclk=%d\n",
						cnt, (unsigned)top->CSA_12_0,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_memory46_q,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_memory47_q,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_ssel1,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_ssel0,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_rri_out,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_rli_out,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_qli_out,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_sts7,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_f_15_0,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_q_15_0,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_CONTR__DOT__s_alui6,
						(int)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__s_aluclk);
					shift_prints++;
					if (shift_prints == 400) { printf("[shp] capture done\n"); fflush(stdout); }
				}
			}
#endif

#ifdef ND120_PROBE_MPY
			// Probe MPY result/overflow microcode (DELILAH CSA 004425-004435,
			// MPY2..MPY3). 004433 = "SET DYN. & STAT. OVF." (loads R4=60); 004434
			// MPY3 ORs R4 into STS via STS,LO. Shows if the overflow branch is
			// taken and the resulting STS. --public-flat-rw build.
			{
				static unsigned mpy_last_csa = 0xFFFFu;
				unsigned csa = (unsigned)top->CSA_12_0;
				if (csa != mpy_last_csa && csa >= 004425u && csa <= 004435u)
				{
					auto rp = top->rootp;
					static int mpy_prints = 0;
					printf("[mpy] cnt=%d csa=%04o STS=%06o R4=%06o R5=%06o\n",
						cnt, csa,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg8_sts_15_0,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg12_r4_15_0,
						(unsigned)rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg13_r5_15_0);
					if (++mpy_prints >= 600) { printf("[mpy] captured 600 samples, exiting\n"); fflush(stdout); exit(0); }
				}
				mpy_last_csa = csa;
			}
#endif

#ifdef ND120_PROBE_MIC
		// requires a --public-flat-rw verilator build (see docs/serial-binload-300.md)
		{
			// probe: log every LDIRV rise (with CD + resulting IR) and
			// the dispatch inputs whenever TERMX (CSA 0511) executes
			int ld = (int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__s_ldirv;
			if (ld && !g_ldirv_last)
				printf("[probe] cnt=%d LDIRV rise: cd=%06o ir_6_0=%03o\n", cnt,
				    (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__s_cd_15_0,
				    (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__s_ir_6_0);
			g_ldirv_last = ld;
			{
				// ring buffer: full MUX34P input/select/output window
				#define RB 16
				static struct { int cnt; unsigned csa, ir, laa, csb, jmp, q, idb, aport, din, f; int mis0, vectn; } rb[RB];
				static int rbi = 0, dump_after = 0;
				rb[rbi].cnt   = cnt;
				rb[rbi].csa   = (unsigned)top->CSA_12_0;
				rb[rbi].ir    = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__s_ir_6_0 & 017;
				rb[rbi].laa   = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__s_laa_3_0_out;
				rb[rbi].csb   = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__s_csbit_3_0;
				rb[rbi].jmp   = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__MIC_MASEL__DOT__s_jmp_3_0;
				rb[rbi].q     = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__ALU_QREG__DOT__REG_Q_LO__DOT__gen_enable__DOT__q_r;
				rb[rbi].mis0  = (int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__s_csmis0;
				rb[rbi].vectn = (int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__s_csvect_n;
				rb[rbi].idb   = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__s_xfidbi_15_0;
				rb[rbi].aport = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_a_15_0;
				rb[rbi].din   = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_d_15_0;
				rb[rbi].f     = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_f_15_0;
				int hit = ((top->CSA_12_0 == 0511 || top->CSA_12_0 == 02310 || top->CSA_12_0 == 0503) && g_termx_logged < 6 && g_bin_state == 2);
				if (hit) g_termx_logged++;
				if (hit || dump_after > 0)
				{
					if (hit)
					{
						printf("[mux34p] ---- window (trigger csa=%04o) ----\n", (unsigned)top->CSA_12_0);
						for (int k = RB - 5; k < RB; k++)
						{
							int j = (rbi + 1 + k) % RB;
							printf("[mux34p] cnt=%d csa=%04o IR=%02o LAA=%02o CSB=%02o m0=%d vn=%d JMP=%02o Q=%03o IDB=%06o A=%06o D=%06o F=%06o\n",
							    rb[j].cnt, rb[j].csa, rb[j].ir, rb[j].laa, rb[j].csb,
							    rb[j].mis0, rb[j].vectn, rb[j].jmp, rb[j].q,
							    rb[j].idb, rb[j].aport, rb[j].din, rb[j].f);
						}
						dump_after = 4;
					}
					else
					{
						printf("[mux34p] cnt=%d csa=%04o IR=%02o LAA=%02o CSB=%02o m0=%d vn=%d JMP=%02o Q=%03o IDB=%06o A=%06o D=%06o F=%06o\n",
						    rb[rbi].cnt, rb[rbi].csa, rb[rbi].ir, rb[rbi].laa, rb[rbi].csb,
						    rb[rbi].mis0, rb[rbi].vectn, rb[rbi].jmp, rb[rbi].q,
						    rb[rbi].idb, rb[rbi].aport, rb[rbi].din, rb[rbi].f);
						dump_after--;
					}
				}
				rbi = (rbi + 1) % RB;
						}
		}
#endif

#ifdef ND120_PROBE_IOR
		// IDB read race probe: watch the I/O-read strobes (EIOR_n / CEUART_n)
		// and what the CPU-side bus actually carries while they are active.
		// BAUDS (boot, reads IDBS,IOR) is the always-available repro.
		{
			static struct {
				int cnt; unsigned csa; int clk, eior, ceu, ru;
				unsigned ylatch, iorout, uartout, fidbi, alud;
			} pring[32];
			static int pri = 0, pactive = 0, ptail = 0, pevents = 0;
			pring[pri].cnt     = cnt;
			pring[pri].csa     = (unsigned)top->CSA_12_0;
			pring[pri].clk     = (int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__s_clk;
			pring[pri].eior    = (int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__s_eiorn_n;
			pring[pri].ceu     = (int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__s_ceuart_n;
			pring[pri].ru      = (int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__s_ruart_n;
			pring[pri].ylatch  = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_33G__DOT__Y_Latch;
			pring[pri].iorout  = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__s_io_idb_15_0_out;
			pring[pri].uartout = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__s_uart_idb_7_0_out;
			pring[pri].fidbi   = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__s_xfidbi_15_0;
			pring[pri].alud    = (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_d_15_0;
			// trigger: UART READ strobes only (CE + READ both active).
			// Boot-time IOR-word reads (EIOR_n) were probed first and WORK.
			static int plines = 0; // per-event line budget (log-size guard)
			int strobe = (!pring[pri].ceu && !pring[pri].ru);
			if (strobe && !pactive && pevents < 20)
			{
				pevents++;
				printf("[iorprobe] ---- event %d: strobe asserts (csa=%04o) ----\n",
				    pevents, pring[pri].csa);
				for (int k = 32 - 8; k <= 32; k++)
				{
					int j = (pri + k) % 32;
					printf("[iorprobe] cnt=%d csa=%04o clk=%d eior=%d ceu=%d ru=%d ylatch=%03o iorout=%06o uartout=%03o fidbi=%06o alud=%06o\n",
					    pring[j].cnt, pring[j].csa, pring[j].clk,
					    pring[j].eior, pring[j].ceu, pring[j].ru,
					    pring[j].ylatch, pring[j].iorout, pring[j].uartout,
					    pring[j].fidbi, pring[j].alud);
				}
				ptail = 0;
				plines = 0;
			}
			else if (pactive && pevents <= 20)
			{
				if ((strobe || ptail < 24) && plines++ < 300)
				{
					printf("[iorprobe] cnt=%d csa=%04o clk=%d eior=%d ceu=%d ru=%d ylatch=%03o iorout=%06o uartout=%03o fidbi=%06o alud=%06o\n",
					    pring[pri].cnt, pring[pri].csa, pring[pri].clk,
					    pring[pri].eior, pring[pri].ceu, pring[pri].ru,
					    pring[pri].ylatch, pring[pri].iorout, pring[pri].uartout,
					    pring[pri].fidbi, pring[pri].alud);
					ptail = strobe ? 0 : ptail + 1;
				}
			}
			pactive = strobe || (pactive && ptail < 24);
			pri = (pri + 1) % 32;
		}
#endif
#ifdef ND120_TRACE_VERIFY
		// Golden-format instruction trace (tests/instruction-verify/):
		// one section per macro instruction (addr, opcode, PIL, full register
		// state at fetch), micro rows = csar + symbol + changed registers.
		// Needs a --public-flat-rw build. Env:
		//   ND120_TVERIFY_OUT  - output .md (default trace_verify.md)
		//   ND120_TVERIFY_SYMS - nd120_symbols.tsv from gen_nd120_syms.py
		//   ND120_TVERIFY_MAX  - macro instructions after arming (default 400)
		{
			static FILE *tv_fp = nullptr;
			static int tv_init = 0, tv_prev_clk = 0, tv_have_prev = 0;
			static int tv_armed = 0, tv_done = 0, tv_count = 0, tv_max = 400;
			static long tv_skipped = 0;
			// Arming: default = first macro instruction on a test level
			// (PIL 1-9), matching the golden RUN trace. The 14 area traces
			// arm on the first fetch from the test-code region (a PIL-0
			// address); to match that window exactly, pass the golden's own
			// first-section fetch address in ND120_TVERIFY_ARM_ADDR (octal)
			// and we arm when that address is fetched.
			static long tv_arm_addr = -1;
			static unsigned tv_prev_csa = 0xFFFF;
			// watched register order matches the golden trace header
			static const char *tv_names[19] = {
				"A", "D", "T", "X", "B", "L", "P", "STS",
				"R1", "R2", "R3", "R4", "R5", "R6", "R7",
				"Q", "F", "GPR", "LC"};
			static unsigned tv_prev_v[19];
			static std::map<unsigned, std::pair<std::string, std::string>> tv_syms;
			if (!tv_init)
			{
				tv_init = 1;
				const char *of = getenv("ND120_TVERIFY_OUT");
				tv_fp = fopen(of ? of : "trace_verify.md", "w");
				if (const char *e = getenv("ND120_TVERIFY_MAX")) tv_max = atoi(e);
				if (const char *e = getenv("ND120_TVERIFY_ARM_ADDR"))
					tv_arm_addr = strtol(e, nullptr, 8);
				if (const char *sf = getenv("ND120_TVERIFY_SYMS"))
				{
					FILE *f = fopen(sf, "r");
					char buf[512];
					while (f && fgets(buf, sizeof buf, f))
					{
						unsigned a;
						char sym[64] = "", src[400] = "";
						char *t1 = strchr(buf, '\t');
						if (!t1) continue;
						*t1 = 0;
						a = (unsigned)strtoul(buf, nullptr, 8);
						char *t2 = strchr(t1 + 1, '\t');
						if (t2)
						{
							*t2 = 0;
							snprintf(sym, sizeof sym, "%s", t1 + 1);
							snprintf(src, sizeof src, "%s", t2 + 1);
							char *nl = strchr(src, '\n');
							if (nl) *nl = 0;
						}
						tv_syms[a] = {sym, src};
					}
					if (f) fclose(f);
				}
				if (tv_fp)
					fprintf(tv_fp, "# INSTRUCTION-VERIFY trace - ND-120 RTL (runSim)\n\n"
						"- Emitted by ND120_TRACE_VERIFY; same format as the ND-110 golden traces.\n"
						"- All values OCTAL. Micro symbol column = DELILAH listing labels.\n\n");
			}
			int tv_clk = (int)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__s_clk;
			if (tv_fp && !tv_done && tv_clk && !tv_prev_clk)
			{
				// sample the watched set at this CLK rise
				unsigned v[19];
				auto *rp = top->rootp;
				v[0]  = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg5_a_15_0;
				v[1]  = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg1_d_15_0;
				v[2]  = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg6_t_15_0;
				v[3]  = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg7_x_15_0;
				v[4]  = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg3_b_15_0;
				v[5]  = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg4_l_15_0;
				v[6]  = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg2_p_15_0;
				v[7]  = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg8_sts_15_0;
				v[8]  = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg9_r1_15_0;
				v[9]  = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg10_r2_15_0;
				v[10] = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg11_r3_15_0;
				v[11] = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg12_r4_15_0;
				v[12] = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg13_r5_15_0;
				v[13] = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg14_r6_15_0;
				v[14] = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__WRF__DOT__RBLOCK__DOT__s_reg15_r7_15_0;
				v[15] = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_q_15_0;
				v[16] = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_f_15_0;
				v[17] = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__ALU__DOT__s_grp_15_0;
				v[18] = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__MIC__DOT__loop_counter;
				unsigned pil = rp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__CPU__DOT__PROC__DOT__CGA__DOT__DELILAH__DOT__sx_pil_3_0_out;
				unsigned csa = (unsigned)top->CSA_12_0;
				// macro boundary detection. Two architectural signatures:
				// (a) an instruction FETCH commits P and GPR together in one
				//     microcycle (shift ops change GPR alone, jumps/level
				//     restores change P alone, EXR loads GPR alone);
				// (b) dispatches through csa 0 (level switch, EXR'd
				//     instruction) enter the new instruction without (a).
				// Both rules can only coincide on the SAME edge (handled by
				// the single condition); one-word instructions legitimately
				// produce boundaries on consecutive edges - never suppress.
				// GPR must hold a real opcode: skip-bumps and panel-service
				// entries pass these rules with GPR momentarily 0 (no
				// golden trace contains a genuine 000000 opcode).
				int tv_boundary = tv_have_prev && v[17] != 0 &&
				    ((v[6] != tv_prev_v[6] && v[17] != tv_prev_v[17]) ||
				     (tv_prev_csa == 0 && csa != 0));
				if (tv_have_prev)
				{
					if (tv_boundary)
					{
						g_macro_boundaries++;   // every boundary, unfiltered
						if (!tv_armed)
						{
							if (tv_arm_addr >= 0)
							{
								// arm at golden's first fetch address (P-1)
								if (((v[6] - 1) & 0xFFFF) == (unsigned)tv_arm_addr)
									tv_armed = 1;
							}
							else if (pil >= 1 && pil <= 9)
								tv_armed = 1;
							// freeze the MIPS-tap comparison window at arming
							if (tv_armed && !g_arm_taken)
							{
								g_arm_taken  = 1;
								g_arm_cfetch = g_cfetch_rises;
								g_arm_macro  = g_macro_boundaries;
								printf("[cfetch] ARMED at cnt=%d (cfetch=%llu macro=%llu before arming)\n",
								    cnt, g_cfetch_rises, g_macro_boundaries);
								fflush(stdout);
							}
						}
						if (!tv_armed)
							tv_skipped++;
						else if (pil >= 10)
						{
							// interrupt/stress level (clock 13, dummy-output 14,
							// IOX-error 12): golden logs only test levels
							// (PIL 0-9), so don't count/log toward the 400 window.
						}
						else if (++tv_count > tv_max)
						{
							fprintf(tv_fp, "\n## Run summary\n\n- Preamble skipped: %ld\n- Detailed: %d (cap)\n",
								tv_skipped, tv_max);
							fclose(tv_fp);
							tv_done = 1;
							printf("\n[tverify] %d instructions traced, done\n", tv_max);
							{
								unsigned long long wc = g_cfetch_rises - g_arm_cfetch;
								unsigned long long wm = g_macro_boundaries - g_arm_macro;
								// The [gprld] / [cfetch2] verdicts that used to
								// print here compared three candidate MIPS taps
								// against the golden instruction count. That
								// search finished - XGPRLOAD_DBG won, and
								// s_debug_cfetch_dbg below carries it - so the
								// losing candidates and their ALU-internal reads
								// were removed on 31-AUG-2026.
								printf("[cfetch] VERDICT over the traced window: cfetch rises=%llu, "
								       "macro boundaries=%llu, ratio=%.4f -> %s\n",
								    wc, wm, wm ? (double)wc / (double)wm : 0.0,
								    (wc == wm) ? "EXACT 1:1 - tap is valid for the MIPS counter"
								               : "MISMATCH - do NOT flash this tap");
								fflush(stdout);
							}
							// Trace complete and flushed - exit instead of
							// spinning to ND120_MAX_CNT (which just pegs a CPU
							// core). Set ND120_TVERIFY_NOEXIT=1 to keep running.
							if (!getenv("ND120_TVERIFY_NOEXIT"))
							{
								fflush(stdout);
								exit(0);
							}
						}
						else
						{
							fprintf(tv_fp, "\n### #%d  `%06o : %06o`  PIL=%u\n",
								tv_count, (v[6] - 1) & 0xFFFF, v[17], pil);
							fprintf(tv_fp, "`A=%06o D=%06o T=%06o X=%06o B=%06o L=%06o "
								"P=%06o STS=%06o R1=%06o R2=%06o R3=%06o R4=%06o "
								"R5=%06o R6=%06o R7=%06o Q=%06o F=%06o GPR=%06o LC=%06o`\n\n",
								v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7],
								v[8], v[9], v[10], v[11], v[12], v[13], v[14],
								v[15], v[16], v[17], v[18]);
							fprintf(tv_fp, "| csar | symbol | changed | microcode |\n|---|---|---|---|\n");
						}
					}
					else if (tv_armed && !tv_done && tv_count >= 1)
					{
						// micro row for the word that just executed (tv_prev_csa)
						char chg[512] = "";
						int cl = 0;
						for (int r = 0; r < 19; r++)
							if (v[r] != tv_prev_v[r])
								cl += snprintf(chg + cl, sizeof(chg) - cl, "%s%s=%06o",
									cl ? " " : "", tv_names[r], v[r]);
						auto it = tv_syms.find(tv_prev_csa);
						fprintf(tv_fp, "| %06o | %s | %s | `%s` |\n",
							tv_prev_csa,
							it != tv_syms.end() ? it->second.first.c_str() : "",
							cl ? chg : "-",
							it != tv_syms.end() ? it->second.second.c_str() : "");
					}
				}
				memcpy(tv_prev_v, v, sizeof v);
				tv_prev_csa = csa;
				tv_have_prev = 1;
			}
			tv_prev_clk = tv_clk;
		}
#endif
#ifdef TRACE_CSA_BOOT
		// CSA from cycle 0, i.e. THROUGH the boot the plain TRACE_CSA gate
		// deliberately skips. Added 31-AUG-2026: the MiSTer board was found
		// spinning in the interrupt-check microcode (CHKIT/PICFM/PICF2) and
		// never reaching OPCOM, so the question became what a machine that
		// DOES boot goes through at the same point - which is exactly the
		// window the post-boot gate throws away.
		if (g_csa_fp && top->CSA_12_0 != g_last_csa)
		{
			fprintf(g_csa_fp, "%ld,%o\n", cnt, (unsigned)top->CSA_12_0);
			// The PIE read at microcode 001011, whose value decides the
			// 001013 branch. The MiSTer board falls through there while this
			// sim jumps to NOTI2, so the two values are worth comparing
			// directly. Printed, not logged, because it happens ONCE.
			// 01011 is a C OCTAL literal = the microcode address 001011.
			// Written 0521 first, which is octal 521 - a different address
			// entirely, and the probe silently never fired.
			(void)0;
			g_last_csa = top->CSA_12_0;
		}
		// THE SAME WINDOW THE BOARD CAPTURES, in the same format.
		//
		// nd120_csa_trace.v on MiSTer arms on microcode 002026 and then records
		// (CSA, FIDBO) pairs on each address CHANGE, printing them as
		// "csa:fidbo". Producing an identical dump here means the two can be
		// diffed line for line.
		//
		// This exists because comparing a single sample from each side gave a
		// FALSE result once already: the board latched one microinstruction
		// earlier than this harness printed, so a value the working machine
		// also produces looked like a divergence. Compare windows, not points.
		// ALUCLK_EN pulses per CPU clock - the ratio the board reports as
		// PE/CK. Counting, not sampling: the enables are one-cycle pulses and
		// a sampled comparison of them is phase-sensitive (see the FIDBO
		// lesson in the MiSTer skill). Two machines running the same microcode
		// must step the cycle controller the same number of times.
		{
			// This probe point runs ONCE PER SYSCLK PERIOD, always with
			// top->sysclk == 1 (see the note at the RAM probe below), so each
			// execution IS one CPU clock - no edge detection needed, and an
			// edge detect here would never fire.
			static unsigned long long s_alu = 0, s_clk = 0;
			s_clk++;
			if ((top->DEBUG_CYC_OUT >> 10) & 1) s_alu++;
			if (s_clk == 65536ULL)
				printf("[rate] clk_cpu=%llu ALUCLK_EN=%llu ratio=%.4f\n",
				       s_clk, s_alu, (double)s_alu / (double)s_clk);
		}
		{
			static int  s_armed = 0;
			static int  s_n     = 0;
			static unsigned s_prev = 0xFFFFu;
			unsigned csa_now = (unsigned)top->CSA_12_0;

			if (!s_armed && csa_now == 02026) s_armed = 1;
			// PER-CLOCK, matching nd120_csa_trace.v's PER_CLOCK=1 on the board.
			// One entry per CPU clock, so a cycle lasting N clocks occupies N
			// entries and its LENGTH is readable straight off the dump. The
			// board terminates 1.89x as many cycles as this machine over
			// identical microcode; this shows which cycles are short.
			// ND120_TRACE_CSA_LAG: print the PREVIOUS csa beside the current
			// aux. The board's RTL records both at posedge clk_cpu (pre-edge
			// values); this harness reads them after eval() with sysclk high
			// (post-edge). For a registered signal that is a one-clock offset,
			// so if lagging csa here reproduces the board's window exactly,
			// the "board advances CSA one clock late" reading is a PROBE
			// artifact and not a hardware difference.
			static unsigned s_csa_lag = 0;
			unsigned csa_show = csa_now;
#ifdef ND120_TRACE_CSA_LAG
			csa_show = s_csa_lag;
#endif
			s_csa_lag = csa_now;
			if (s_armed && s_n < 64)
			{
				// {cycle-controller inputs, condition lines} - the SAME 13-bit
				// word the board records as `aux`. The condition lines alone
				// showed the board missing TERM at 001007 and CC0 at 001020;
				// the cycle inputs say WHICH input drives the CC state apart.
				printf("%05o:%06o ", csa_show,
				       (((unsigned)top->DEBUG_CYC_OUT & 0x7FFu) << 5) |
				       ((unsigned)top->DEBUG_CC_TERM_OUT & 0x1Fu));
				if ((++s_n % 4) == 0) printf("\n");
				s_prev = csa_now;
			}
		}
#endif
#if defined(TRACE_CSA) || defined(SCRIPT_INPUT)
		if (g_boot_done_cnt != 0)
		{
#ifdef TRACE_CSA
			if (g_csa_fp && top->CSA_12_0 != g_last_csa)
			{
				fprintf(g_csa_fp, "%d,%o,%llo\n", cnt, (unsigned)top->CSA_12_0,
				    (unsigned long long)top->rootp->ND120_TOP__DOT__CORE__DOT__s_csbits);
				g_last_csa = top->CSA_12_0;
			}
#endif
			// post-boot cycle budget: NO default cap - the runner runs forever
			// unless a budget is EXPLICITLY given on the command line via
			// ND120_SCRIPT_BUDGET (=cycles to run after boot). Unset => no limit.
			static long s_script_budget = -1;   // -1 = not yet read
			if (s_script_budget == -1)
			{
				const char *e = getenv("ND120_SCRIPT_BUDGET");
				s_script_budget = e ? atol(e) : 0;   // 0 => run forever
			}
			if (s_script_budget > 0 && cnt > g_boot_done_cnt + 200000 + s_script_budget)
			{
#ifdef TRACE_CSA
				if (g_csa_fp) { fclose(g_csa_fp); g_csa_fp = nullptr; }
#endif
				printf("\n[instrumented] cycle budget reached, stopping\n");
				break;
			}
		}
#endif

		new_led = top->led ^ 0x3F; // bits are negated, active low
		// if (new_led != led)
		if (false)
		{
			uint8_t changed = new_led ^ led; // identify changed leds

			changed &= ~(1 << 4 | 1 << 3); // dont log cpu & bus grant

			// printf("LED changed to 0x%2X\r\n", new_led);
			led = new_led;
			DumpLedInfo(led, changed);
		}

		/*************************** TRANSMIT UART DATA *************************************/

		if (!txEnabled)
		{
			char ch;
			ssize_t n = 0;
#ifdef SCRIPT_INPUT
			// After boot ('#' seen) + settle, feed the scripted command instead of stdin
			if (g_boot_done_cnt != 0 && cnt > g_boot_done_cnt + 1000000 && cnt > g_next_inject_cnt && g_script[g_script_idx] != '\0' &&
			    (g_lf_at_mark < 0 || (g_rx_lf_total > g_lf_at_mark && cnt > g_last_rx_cnt + g_amp_settle)))
			{
				ch = g_script[g_script_idx++];
				n = 1;
				// '&' hands the console to the booted program: hold the
				// rest of the script until it has printed a line and gone
				// quiet (a human waits for the greeting before typing)
				g_lf_at_mark = (ch == '&' || ch == '$') ? g_rx_lf_total : -1;
				if (getenv("ND120_SCRIPT_DEBUG"))
					printf("[script] sent %02x '%c' at cnt %d\r\n",
					       ch, (ch >= ' ' ? ch : '.'), cnt);
				{
					// inter-char gap so the reader keeps up (OPCOM or a
					// booted program); ND120_SCRIPT_GAP overrides
					long gap = 300000;
					if (const char *g = getenv("ND120_SCRIPT_GAP"))
						gap = atol(g);
					g_next_inject_cnt = cnt + gap;
				}
			}
			else if (g_boot_done_cnt != 0 && g_script[g_script_idx] == '\0' &&
			    g_bin_state != 3 && getenv("ND120_BINLOAD_FILE") != nullptr &&
			    cnt > g_next_inject_cnt)
			{
				if (g_bin_state == 0)
				{
					if (const char *e = getenv("ND120_BINLOAD_GAP")) g_bin_gap = atol(e);
					if (const char *e = getenv("ND120_BINLOAD_SETTLE")) g_bin_settle = atol(e);
					g_binf = fopen(getenv("ND120_BINLOAD_FILE"), "rb");
					if (!g_binf) { printf("[binload] cannot open file\n"); g_bin_state = 3; }
					else {
						printf("[binload] settling %ld cnt after script\n", g_bin_settle);
						g_next_inject_cnt = cnt + g_bin_settle;
						g_bin_state = 1;
						tx8n1 = 1;  // BPUN bytes are 8-bit: switch injector to 8N1
						printf("[binload] injector -> 8N1\n");
					}
				}
				else
				{
					int c = fgetc(g_binf);
					if (c == EOF) {
						fclose(g_binf); g_binf = nullptr;
						printf("[binload] streamed %ld bytes (gap=%ld cnt)\n", g_bin_sent, g_bin_gap);
						g_bin_state = 3;
					} else {
						if (g_bin_state == 1) { printf("[binload] streaming...\n"); g_bin_state = 2; }
#ifdef ND120_PROBE_MIC
					if ((g_bin_sent % 8) == 0)
						printf("[binload] byte %ld: uart status=%02x\n",
						    g_bin_sent,
						    (unsigned)top->rootp->ND120_TOP__DOT__CORE__DOT__CPU_BOARD__DOT__IO__DOT__UART__DOT__CHIP_32H__DOT__regStatusRegister);
#endif
						ch = (char)c;
						n = 1;
						g_bin_sent++;
						g_next_inject_cnt = cnt + g_bin_gap;
					}
				}
			}
			else
#endif
			// Read a character from stdin. A real keyboard (tty) is read
			// DIRECTLY - human typing is naturally paced and any delay
			// here just feels like lag. Pacing applies only to PIPED
			// input (tests, paste-style feeds), where all chars arrive
			// at once and would hit MOPC (no RX FIFO) back-to-back:
			// hold until the boot '#' prompt, one char per g_stdin_gap,
			// and after '&' hold until the booted program's greeting.
			{
				static const int s_stdin_tty = isatty(STDIN_FILENO);
				if (s_stdin_tty)
				{
					n = read(STDIN_FILENO, &ch, 1);
				}
				else if (g_boot_done_cnt != 0 && cnt > g_boot_done_cnt + 1000000 &&
				    cnt > g_stdin_next_cnt &&
				    (g_lf_at_mark < 0 || (g_rx_lf_total > g_lf_at_mark && cnt > g_last_rx_cnt + g_amp_settle)))
				{
					n = read(STDIN_FILENO, &ch, 1);
					if (n > 0)
					{
						if (getenv("ND120_STDIN_DEBUG"))
							printf("[stdin] sent %02x '%c' at cnt %d\n", (unsigned char)ch, (ch >= ' ' ? ch : '.'), cnt);
						g_stdin_next_cnt = cnt + g_stdin_gap;
						// after '&' hold further input until the booted
						// program has printed its greeting and gone quiet
						g_lf_at_mark = (ch == '&' || ch == '$') ? g_rx_lf_total : -1;
					}
				}
			}

			if (n > 0)
			{
				// printf("You pressed: %x\n", ch);

				txData = (int)ch;
				txEnabled = true;
				txDataBit = 0;
				txTicks = 0;
				txOnes = 0;
			}
		}

		if (txEnabled)
		{
			if (txTicks > 0)
			{
				txTicks--;
			}
			else
			{
				switch (txDataBit)
				{
				case 0:
					txTicks = DELAY_FRAMES - 1; // Start bit
					top->uartRx = 0;
					txOnes = 0;
					if (txData == 0x0a)
						txData = 0x0d; // LF, not CR
					// printf("TX[%02X] %c\r\n", txData, txData);
					break;
				case 1:
				case 2:
				case 3:
				case 4:
				case 5:
				case 6:
				case 7:
					if ((txData & 0x01) != 0)
					{
						top->uartRx = 1;
						txOnes++;
					}
					else
					{
						top->uartRx = 0;
					}
					txData >>= 1;
					txTicks = DELAY_FRAMES - 1;
					break;
				case 8: // Parity slot (7E2 console) / 8th data bit (8N1 binload)
					if (tx8n1)
					{
						top->uartRx = (txData & 0x01) ? 1 : 0;
						txData >>= 1;
					}
					else
					{
						top->uartRx = 0;
						// Calculate even parity: set top->uartRx to 1 if txOnes is odd, 0 if even
						// top->uartRx = (txOnes % 2) ? 0 : 1; // Even parity calculation
					}
					txTicks = DELAY_FRAMES - 1;
					break;
				case 9:				 // stop bit
					top->uartRx = 1; // MARK!
					txTicks = DELAY_FRAMES - 1;
					break;
				case 10:			 // 2nd stop bit (7E2) / frame ends after 1 stop (8N1)
					if (tx8n1)
					{
						txData = 0;
						txEnabled = false;
						break;
					}
					top->uartRx = 1; // MARK!
					txTicks = DELAY_FRAMES - 1;
					break;
				case 11:
					txData = 0;
					txEnabled = false;
					break;
				}

				// printf("TX[%d] %d\r\n", txDataBit, top->uartRx);

				txDataBit++;
			}
		}

		/*************************** RECEIEVE UART DATA *************************************/

		// Receive data ?
		if ((top->uartTx == 0) && (!rxEnabled))
		{
			rxEnabled = true;
			rxDataBit = 0;
			rxData = 0;
			rxOnes = 0;
			rxTicks = HALF_DELAY_WAIT;
		}

		if (rxEnabled)
		{
			if (rxTicks > 0)
			{
				rxTicks--;
			}
			else
			{
				// printf("RX[%d] %d\r\n", rxDataBit, top->uartTx);

				switch (rxDataBit)
				{
				case 0:
					rxTicks = DELAY_FRAMES;
					if (top->uartTx == 1)
					{
						rxEnabled = false;
					}
					break;
				case 1:
				case 2:
				case 3:
				case 4:
				case 5:
				case 6:
				case 7:
					if (top->uartTx != 0)
					{
						rxOnes++; // for parity check
						rxData |= (1 << (rxDataBit - 1));
					}
					rxTicks = DELAY_FRAMES - 1;
					break;
				case 8: // Parity
					rxTicks = DELAY_FRAMES - 1;
					break;
				case 9:	 // stop bits
				case 10: // stop bits
					rxTicks = DELAY_FRAMES - 1;
					break;
				case 11:
					// printf("Received 0x%02X '%c'\r\n", rxData, rxData);
					printf("%c", rxData);
					g_last_rx_cnt = cnt;
					if (rxData == '\r' || rxData == '\n') g_rx_lf_total++;
					fflush(stdout);
					if (rxData == '#' && g_boot_done_cnt == 0) g_boot_done_cnt = cnt;

					rxData = 0;
					rxEnabled = false;
					break;
				}
				rxDataBit++;
			}
		}

		// sim_time += time_step; // Increment simulation time

		top->eval();
		top->sysclk = !top->sysclk;

		// sim_time += time_step; // Increment simulation time
	}

#ifdef DO_TRACE

	// Add a few clock cycles
	m_trace->dump(sim_time);
	sim_time += time_step; // Increment simulation time
	m_trace->dump(sim_time);
	sim_time += time_step; // Increment simulation time

	m_trace->close();
#endif

	// Available in interactive builds too (the stdin-path boot test uses it)
	if (const char *e = getenv("ND120_BINLOAD_CHECK")) {
		unsigned a0 = 0; int nw = 0;
		if (sscanf(e, "%o:%d", &a0, &nw) == 2) {
			printf("[binload] RAM check @%06o:", a0);
			for (int k = 0; k < nw; k++)
				printf(" %06o",
				    ((unsigned)ram_high[a0 + k] << 8) | ram_low[a0 + k]);
			printf("\n");
		}
	}
	delete top;
	return 0;
}

/****************************** BPUN **********************/

static int mlp;

static int
gb(FILE *f)
{
	int w;

	if (f == NULL)
		return 00;

	w = getc(f) & 0377;
	return w;
}

static int
gw(FILE *f)
{
	int c = gb(f);
	return (c << 8) | gb(f);
}

// Return 1 if 8 bit parity is EVEN
ushort calc_parity(uint16_t val)
{
	ushort parity = 0;

	for (int i = 0; i < 8; i++)
	{
		parity ^= (val & 1);
		val >>= 1;
	}
	return parity == 0 ? 1 : 0; // Even parity returns 1, odd returns 0
}

/*
 * Bootable (BPUN) tape format.
 * Disks can use it as well with a max of 64 words data.  In this case
 * the bytes are stored in the LSB of the words from beginning of disk.
 * 1kw block should be read at address 0 in memory.
 *
 * A bootable tape consists of nine segments, named A-I.
 *
 * A - Any chars not including '!'
 * B - (optional) octal number terminated by CR (LF ignored).
 * C - (optional) octal number terminated by '!'.
 * D - A '!' delimeter
 * E - Block start address (in memory), two byte, MSB first.
 * F - Word count in G section, two byte, MSB first.
 * G - Words as counted in F section.
 * H - Checksum of G section, one word.
 * I - Action code.  If non-zero, start at address in B, otherwise nothing.
 */

void loadfile(char *fn, int off, uint8_t *low_array, uint8_t *low_array9, uint8_t *high_array, uint8_t *high_array9)
{
	int B, C, E, F, H, I;
	int w, i, rv;
	unsigned short s;
	FILE *f;

	if ((f = fopen(fn, "r")) == 0)
	{
		printf("Unable to open file %s\r\n", fn);
		return;
	}

#if 0
	rv = SCPE_OK;
	if (sim_switches & SWMASK('D')) {	/* read file from disk */
		mlp = 0;
		for (i = 0; i < 1024; i++) {
			/* images have MSB first */
			s = (getc(f) & 0377) << 8;
			s |= getc(f) & 0377;
			pwrmem(i, s, PM_CPU);
		}
		f = NULL;
	}
#endif

	/* read B/C section */
	for (B = C = 0; (w = gb(f) & 0177) != '!';)
	{
		switch (w)
		{
		case '\n':
			continue;
		case '\r':
			B = C, C = 0;
			break;
		case '0':
		case '1':
		case '2':
		case '3':
		case '4':
		case '5':
		case '6':
		case '7':
			C = (C << 3) | (w - '0');
			break;
		default:
			B = C = 0;
		}
	}

	printf("B address    %06o\n", B);
	printf("C address    %06o\n", C);
	//	regP = B;
	printf("Load address %06o\n", E = gw(f));
	printf("Word count   %06o\n", F = gw(f));
	for (i = s = 0; i < F; i++)
	{
		int data16 = gw(f);
		low_array[E + i] = data16 & 0xFF;
		high_array[E + i] = (data16 >> 8) & 0xFF;

		low_array9[E + i] = calc_parity(low_array[E + i]);
		high_array9[E + i] = calc_parity(high_array[E + i]);

		s += data16;
	}
	printf("Checksum     %06o\n", H = gw(f));
	if (H != s)
		printf("Bad checksum: %06o != %06o\n", H, s);
	printf("Execute	     %06o\n", I = gw(f));
	printf("Words read   %06o\n", i);
	//	ald = 0300;	/* from tape reader */
	//	return rv;
	fclose(f);
}
