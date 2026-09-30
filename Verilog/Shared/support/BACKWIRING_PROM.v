/**************************************************************************
** BACK-WIRING PROM (installation number PROM)                          **
**                                                                       **
** The small PROM that sits on the ND-100/ND-120 BACKPLANE behind the    **
** CPU board's B-plug. It is NOT an I/O device: it is not reachable by   **
** IOX, not memory mapped, and not reachable by TRA/TRR. The only way to **
** read it is the VERSN instruction (opcode 140133 octal), which selects **
** the internal data bus source IDBS,INR (code 35 octal).                **
**                                                                       **
** Signal path (all citations are files in this repo):                   **
**   DECODE-GateArray/DGA/circuit/DECODE_DGA_IDBS.v:32                   **
**       RINRN  - "Read Installation Number from B-PLUG (RINR) IDBS=35"  **
**   CPU-BOARD-3202/circuit/ND3202D.v:83                                 **
**       input [7:0] INR_7_0 - under "BACKPLANE B-PLUG / FROM B plug"    **
**   CPU-BOARD-3202/circuit/ND3202D.v:89                                 **
**       output [3:0] PIL    - driven OUT to the same B-plug             **
**   CPU-BOARD-3202/circuit/IO_REG_41.v:189                              **
**       s_idb_7_0_inr_out = s_rinr_n ? 8'b0 : s_inr_7_0                 **
**   CPU-BOARD-3202/circuit/IO_37.v:295                                  **
**       5'o35: s_idb_mux = s_idb_15_0_reg_out;  // RINR                 **
**                                                                       **
** B-plug pin order of the 8 INR data bits, preserved from the original  **
** ND120_CORE.v comment on the .INR_7_0() connection:                    **
**       INR7..INR0 = B15, B4, B5, B17, B8, B7, B13, B6                  **
** and the PIL nibble that addresses this PROM:                          **
**       XPIL3=B-C8, PIL2=B-B12, PIL1=B-B10, PIL0=B-B9                   **
**                                                                       **
** ADDRESSING - INFERENCE, NOT READ FROM A SCHEMATIC.                    **
** No backplane schematic for the PROM decode was found in this repo or  **
** in NDInsight, and no dump of a real back-wiring PROM exists here      **
** either. That PIL[3:0] is the PROM's byte address is STRONG INFERENCE  **
** from three independent things:                                        **
**   1. the VERSN microcode does COMM,LDPIL (from A bits 8-11) and then  **
**      samples IDBS,INR - Code/Microcode/ND-120-DELILAH-L.LISTING.txt   **
**      lines 115-119;                                                   **
**   2. the CPU board drives PIL out to the B-plug and takes INR back    **
**      in from it (the paired signals above);                           **
**   3. SINTRAN's GCPUNR reads exactly 8 bytes by executing VERSN once   **
**      per interrupt level 0..7 - $ND_REPOS/NDInsight/SINTRAN/          **
**      NPL-SOURCE/NPL/PH-P2-OPPSTART.NPL:3534-3570.                     **
**                                                                       **
** MICROCODE TIMING NOTE (real hardware bug, both behaviours work):      **
** LDPIL has not settled when the very next microword samples IDBS,INR,  **
** so the CURRENT PIL is used instead of the just-loaded one. ND-120     **
** revision L inserts a COMM,SLOW microword between them to fix this     **
** (L.LISTING.txt:122, "L-ONLY WORD"); revision K (K.LISTING.txt:116-119)**
** and the ND-100/ND-110 do not have it. SINTRAN works around it         **
** unconditionally by running VERSN on levels 0..7, so this model is     **
** correct for both: it simply decodes whatever PIL nibble the CPU board **
** presents.                                                             **
**                                                                       **
** Byte layout that SINTRAN GCPUNR decodes (bytes 8-15 are never read):  **
**   0 (MSB) + 1 (LSB) : SYSNO   -> banner "CPU NUMBER"; -1 = absent     **
**   2 (MSB) + 3 (LSB) : HWINFO(2) system type -> "CPU TYPE"; -1 = absent**
**   4               : NLEGU number of legal users; 0377B = absent       **
**   5               : not used by SINTRAN (GCPUNR does INF2 SHZ -10)    **
**   6 + 7           : signature INF3, MUST be 52652B = 0x55AA           **
**   8..15           : unknown, SINTRAN never reads them                 **
** If the signature is wrong GCPUNR EXITs and every other byte is        **
** ignored, so bytes 6/7 are hardwired here and are NOT parameterised.   **
**                                                                       **
** Ronny Hansen                                                          **
***************************************************************************/

//! @title Back-wiring PROM (installation number), addressed by PIL[3:0]
//! @author Ronny Hansen

// Build-time values and their "not present" sentinels. Same `param + `define
// default` idiom SC2661_UART.v:139-144 uses for BOARD_CLK_FREQ /
// UART_BAUD_RATE, so a bitstream can fix them either by overriding the module
// parameter or by a -D on the toolchain command line.
`include "nd120_backwiring_defaults.vh"

module BACKWIRING_PROM #(
    parameter [15:0] SYSNO     = `ND120_SYSNO,      //! bytes 0/1 - CPU NUMBER   (16'hFFFF = absent)
    parameter [15:0] HWINFO2   = `ND120_HWINFO2,    //! bytes 2/3 - CPU TYPE     (16'hFFFF = absent)
    parameter [ 7:0] NLEGU     = `ND120_NLEGU,      //! byte 4    - legal users  (8'o377   = absent)
    parameter [ 7:0] INR_BYTE5 = `ND120_INR_BYTE5,  //! byte 5    - no known consumer
    parameter [ 7:0] INR_FILLER = `ND120_INR_FILLER //! bytes 8..15 - never read by SINTRAN
) (
    input  wire [3:0] PIL_3_0,  //! PROM byte address, driven out on the B-plug by the CPU board
    output reg  [7:0] INR_7_0   //! PROM data byte, read back over the B-plug (IDBS,INR = 35 octal)
);

  // Signature bytes 6/7 = 52652 octal = 21930 decimal = 0x55AA. NOT a
  // parameter on purpose: a wrong signature makes GCPUNR EXIT and disables
  // everything else in the PROM.
  localparam [7:0] SIGN_HI = 8'h55;  //! byte 6 - high byte of INF3
  localparam [7:0] SIGN_LO = 8'hAA;  //! byte 7 - low  byte of INF3

  // Pure combinational lookup. The CPU board already gates this with RINR_n
  // (IO_REG_41.v:189), so the PROM itself is always driving - exactly like the
  // real part sitting on the backplane with its output tied to the B-plug.
  always @(*) begin
    case (PIL_3_0)
      4'd0:    INR_7_0 = SYSNO[15:8];    // SYSNO   MSB
      4'd1:    INR_7_0 = SYSNO[7:0];     // SYSNO   LSB
      4'd2:    INR_7_0 = HWINFO2[15:8];  // HWINFO(2) MSB
      4'd3:    INR_7_0 = HWINFO2[7:0];   // HWINFO(2) LSB
      4'd4:    INR_7_0 = NLEGU;          // number of legal users
      4'd5:    INR_7_0 = INR_BYTE5;      // no known consumer
      4'd6:    INR_7_0 = SIGN_HI;        // signature, forced
      4'd7:    INR_7_0 = SIGN_LO;        // signature, forced
      default: INR_7_0 = INR_FILLER;     // bytes 8..15
    endcase
  end

endmodule
