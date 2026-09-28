/**************************************************************************
** CPU_MMU_PT_29  DETERMINISTIC REPLAY testbench                          **
**                                                                       **
** Source of the vectors: REAL ND-120 RTL capture, NOT hand-invented.    **
**   Captured 22-JUL-2026 by the sim/ PROBE (obj_dir_probe_floppy) while  **
**   the real INSTRUCTION-B verify program (`1560&` autoload of           **
**   runSim/FLOPPY1.IMG) set up MEMORY MANAGEMENT II paging. The exact    **
**   MMU shadow-write cycles were logged to sim/tpe_paging.csv (rule      **
**   s_wmap_n==0). This tb replays the captured EPMAP_n/EPT_n/WMAP_n/LA/  **
**   PPN/PT signals for the TOP logical page (VPN 63 = logical page o77 = **
**   addresses 0177400-0177777, i.e. the page that holds 177777) plus a   **
**   CONTROL page (o76), then reads the shadow RAM back and asserts the   **
**   translation it returns.                                             **
**                                                                       **
** GROUND TRUTH from tpe_paging.csv (octal), the two shadow writes that   **
** populate VPN 63's map entry (both marked `top` by the probe rule):     **
**   tick 12098080: la=77 EPMAP_n=1 EPT_n=0 WMAP_n=0  PT_in =162000       **
**                  -> writes the PT (protection) table  PT[77]  = 162000 **
**   tick 12098088: la=77 EPMAP_n=0 EPT_n=1 WMAP_n=0  PPN_in= 77          **
**                  -> writes the PPN (phys-page) table  PPN[77] = 77      **
**   PON went high LATER, at tick 12129409 (setup-then-enable).           **
**   The whole segment 0 (pages o0..o77) is an IDENTITY map (page N->PPN N)**
**   with PT word 162000; page o100 starts a new segment (->PPN 0).       **
**                                                                       **
** WHAT THIS PROVES (and what it does NOT):                               **
**   * PROVES: the shadow/PT RAM (CPU_MMU_PT_29, TMM2018D_25 sync block    **
**     RAM) faithfully STORES and RETURNS the top-page translation        **
**     PPN[o77]=o77 / PT[o77]=162000 through its 1-clock registered-read   **
**     latency. This is a GOOD-BEHAVIOUR regression guard for the memory   **
**     note nd120-mmu-shadow-ram ("shadow RAM WORKS; 177777->0 is upstream **
**     of main RAM").                                                     **
**   * DOES NOT reproduce the 177777 store-routing bug: INSTRUCTION-B's    **
**     MEMORY-REFERENCE area PASSES 400/400 vs ND-110 golden              **
**     (tests/instruction-verify/CAMPAIGN-STATUS.md), so this workload is  **
**     NOT the failing one. The failing case is the ND-120/CX TPE-MON      **
**     INSTCTION diagnostic - a separate capture (see the retired         **
**     sim/HANDOFF-csharp-paging-capture.md, summarised in HISTORY.md).   **
**     This tb encodes the CORRECT shadow-RAM routing so a future         **
**     regression there is caught.                                        **
**                                                                       **
** Read model (TMM2018D_25.v line 67, SYNC): !CS_n & W_n => data_out_reg  **
**   <= array[ADDR]; D_OUT registered. So a read needs the address        **
**   presented, then >=1 posedge, then D_OUT is valid. Mirrors the        **
**   sibling CPU_MMU_PT_29_tb.v latency-characterisation task.            **
**                                                                       **
** Prints TB_RESULT: PASS/FAIL.                                          **
***************************************************************************/
`timescale 1ns / 1ps

module CPU_MMU_PT_29_replay_tb;

  reg         sysclk;
  reg         sys_rst_n;
  reg  [10:0] LA_20_10;
  reg         EPMAP_n;   // PPN chip select (active low) - captured value replayed
  reg         EPT_n;     // PT  chip select (active low) - captured value replayed
  reg         WCLIM_n;   // PPN-hi 1-bit RAM write (unused here; hold inactive)
  reg         WMAP_n;    // shared write strobe (active low)
  reg  [15:0] PPN_25_10_IN;
  reg  [15:0] PT_15_0_IN;

  wire [15:0] PPN_25_10_OUT;
  wire [15:0] PT_15_0_OUT;
  wire        WCINH_n;

  integer errors = 0;
  integer checks = 0;

  CPU_MMU_PT_29 DUT (
      .sysclk       (sysclk),
      .sys_rst_n    (sys_rst_n),
      .LA_20_10     (LA_20_10),
      .EPMAP_n      (EPMAP_n),
      .EPT_n        (EPT_n),
      .WCLIM_n      (WCLIM_n),
      .WMAP_n       (WMAP_n),
      .PPN_25_10_IN (PPN_25_10_IN),
      .PPN_25_10_OUT(PPN_25_10_OUT),
      .PT_15_0_IN   (PT_15_0_IN),
      .PT_15_0_OUT  (PT_15_0_OUT),
      .WCINH_n      (WCINH_n)
  );

  // 100 MHz clock
  initial sysclk = 0;
  always #5 sysclk = ~sysclk;

  // ---- Replay ONE captured shadow write exactly as the real MMU drove it.
  //      The captured cycle asserts one chip-select (EPMAP_n=0 -> PPN table,
  //      EPT_n=0 -> PT table) with WMAP_n=0. Stimulus on negedge so it is
  //      stable at the sampling posedge (same anti-race discipline as the
  //      sibling tb, proven with a control RAM there).
  task replay_write(input [10:0] page,
                    input        epmap_n, input ept_n,
                    input [15:0] ppn_in,  input [15:0] pt_in);
    begin
      @(negedge sysclk);
      LA_20_10     = page;
      EPMAP_n      = epmap_n;
      EPT_n        = ept_n;
      PPN_25_10_IN = ppn_in;
      PT_15_0_IN   = pt_in;
      WMAP_n       = 1'b0;     // write
      @(posedge sysclk);       // TMM2018D writes array[page] here
      @(negedge sysclk);
      WMAP_n       = 1'b1;     // release AFTER the edge
      EPMAP_n      = 1'b1;
      EPT_n        = 1'b1;
    end
  endtask

  // ---- Read the PPN table (select PPN chips: EPMAP_n=0, EPT_n=1, WMAP_n=1).
  //      Allow the 1-clock registered-read latency of the sync block RAM.
  task ppn_read(input [10:0] page, output [15:0] got);
    begin
      @(negedge sysclk);
      LA_20_10 = page;
      EPMAP_n  = 1'b0;   // select PPN
      EPT_n    = 1'b1;
      WMAP_n   = 1'b1;   // read
      @(posedge sysclk); // data_out_reg <= array[page]
      @(posedge sysclk); // (extra clock of slack; covers 1..2-clock latency)
      #1;
      got      = PPN_25_10_OUT;
      @(negedge sysclk); EPMAP_n = 1'b1;
    end
  endtask

  // ---- Read the PT table (select PT chips: EPT_n=0, EPMAP_n=1, WMAP_n=1).
  task pt_read(input [10:0] page, output [15:0] got);
    begin
      @(negedge sysclk);
      LA_20_10 = page;
      EPT_n    = 1'b0;   // select PT
      EPMAP_n  = 1'b1;
      WMAP_n   = 1'b1;   // read
      @(posedge sysclk);
      @(posedge sysclk);
      #1;
      got      = PT_15_0_OUT;
      @(negedge sysclk); EPT_n = 1'b1;
    end
  endtask

  task check_eq(input [15:0] got, input [15:0] exp, input [255:0] msg);
    begin
      checks = checks + 1;
      if (got !== exp) begin
        $display("  FAIL: %0s  got=%06o expected=%06o", msg, got, exp);
        errors = errors + 1;
      end else begin
        $display("  ok  : %0s = %06o", msg, got);
      end
    end
  endtask

  reg [15:0] gppn77, gpt77, gppn76;

  initial begin
    sys_rst_n    = 0;
    LA_20_10     = 0;
    EPMAP_n      = 1;
    EPT_n        = 1;
    WCLIM_n      = 1;
    WMAP_n       = 1;
    PPN_25_10_IN = 0;
    PT_15_0_IN   = 0;
    repeat (4) @(posedge sysclk);
    sys_rst_n = 1;
    repeat (2) @(posedge sysclk);

    // ================================================================== //
    //  REPLAY the REAL captured VPN-63 (page o77) map-setup writes.       //
    //  Order and signal polarity exactly as logged in tpe_paging.csv.     //
    // ================================================================== //
    // 1) PT-table write  : EPMAP_n=1, EPT_n=0, PT_in=162000  -> PT[77]     //
    replay_write(11'o77, /*epmap_n*/1'b1, /*ept_n*/1'b0, /*ppn*/16'o0, /*pt*/16'o162000);
    // 2) PPN-table write : EPMAP_n=0, EPT_n=1, PPN_in=77     -> PPN[77]     //
    replay_write(11'o77, /*epmap_n*/1'b0, /*ept_n*/1'b1, /*ppn*/16'o77, /*pt*/16'o0);

    // CONTROL page o76 (also identity in segment 0): PPN[76]=76, PT[76]=162000.
    replay_write(11'o76, 1'b1, 1'b0, 16'o0,  16'o162000);
    replay_write(11'o76, 1'b0, 1'b1, 16'o76, 16'o0);

    // ================================================================== //
    //  READ BACK through the sync block RAM and assert the translation.   //
    // ================================================================== //
    ppn_read(11'o77, gppn77);
    pt_read (11'o77, gpt77);
    ppn_read(11'o76, gppn76);

    $display("[replay] VPN63(o77): PPN=%06o PT=%06o | CONTROL o76: PPN=%06o",
             gppn77, gpt77, gppn76);

    // Top-page translation must be the identity mapping the real MMU wrote.
    check_eq(gppn77, 16'o77,     "PPN[o77] (VPN63 top-page phys page)");
    check_eq(gpt77,  16'o162000, "PT[o77]  (VPN63 protection word)");
    // Control must be its own distinct value (no aliasing to the top page).
    check_eq(gppn76, 16'o76,     "PPN[o76] control phys page");
    check_eq((gppn77 == gppn76) ? 16'o1 : 16'o0, 16'o0,
             "top-page and control PPN are DISTINCT (no alias)");

    if (errors == 0)
      $display("TB_RESULT: PASS (%0d checks) - shadow RAM returns the REAL captured VPN63 map",
               checks);
    else
      $display("TB_RESULT: FAIL (%0d errors / %0d checks)", errors, checks);
    $finish;
  end

  // Watchdog
  initial begin
    #200000;
    $display("TB_RESULT: TIMEOUT");
    $finish;
  end

endmodule
