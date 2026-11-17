/****************************************************************************
** pc_storage_model - the PC program serving disk images, as a testbench   **
**                                                                         **
** Path: Verilog/fpga/azure-x930613/sim/pc_storage_model.v                 **
**                                                                         **
** Plays the PC side of nd_pcie_storage over its register bus, following   **
** the recipe in that module's header: poll PEND, pick a slot round-robin, **
** read LBA/BLKCNT, START, stream DATA words, END. It is the stand-in for  **
** the PC program (docs/00-plan.md, step V6) and is written so that the    **
** MiSTer storage testbench's checks can be reused unchanged: it has the   **
** same image array (img), the same mount/unmount tasks and the same        **
** counters (n_reads, n_writes, violations) as fpga/mister/sim/            **
** hps_io_model.v.                                                         **
**                                                                         **
** The file is bytes; DATA words are little-endian pairs, word w =         **
** {byte 2w+1, byte 2w}, which is how a PC reads a file into 16-bit words. **
**                                                                         **
** Rules the model CHECKS (each counts a violation):                       **
**   - the LBA must not change between the poll and START;                 **
**   - once START is written, the slot's request must be gone by the next  **
**     PEND read (nd_storage_hps drops it on the rising ack);              **
**   - the block must never answer with ERRS set.                          **
**                                                                         **
** The bus is used by ONE process only (the poll loop). Mount requests     **
** from the testbench are queued and carried out by that loop between      **
** polls, so two processes never drive the bus in the same cycle.          **
*****************************************************************************/
`timescale 1ns / 1ps
module pc_storage_model #(
    parameter integer VDNUM       = 5,
    parameter integer IMG_BYTES   = 65536,  // per slot
    parameter integer POLL_CYCLES = 40      // bus cycles between PEND polls
) (
    input  wire        clk,
    output reg  [8:0]  addr,
    output reg         wr,
    output reg  [31:0] wdata,
    output reg         rd,
    input  wire [31:0] rdata,
    input  wire        rvalid,
    output integer     n_reads,
    output integer     n_writes,
    output integer     violations
);
  localparam [8:0] PEND = 9'o004, XFER = 9'o010, DATA = 9'o014,
                   SIZE_LO = 9'o024, SIZE_HI = 9'o030, MOUNT = 9'o034,
                   ERRS = 9'o040, LBA0 = 9'o100, CNT0 = 9'o200;

  reg [7:0] img[0:VDNUM*IMG_BYTES-1];

  initial begin
    addr = 0; wr = 0; wdata = 0; rd = 0;
    n_reads = 0; n_writes = 0; violations = 0;
  end

  // ---- bus primitives (only the poll loop calls these) -------------------
  reg [31:0] rv;
  task bus_read(input [8:0] a);
    integer t;
    begin
      @(posedge clk); addr <= a; rd <= 1'b1;
      @(posedge clk); rd <= 1'b0;
      t = 0;
      while (!rvalid && t < 100) begin @(posedge clk); t = t + 1; end
      if (!rvalid) begin
        $display("PC MODEL: no rvalid for read of 0o%0o - VIOLATION", a);
        violations = violations + 1;
      end
      rv = rdata;
    end
  endtask
  task bus_write(input [8:0] a, input [31:0] d);
    begin
      @(posedge clk); addr <= a; wdata <= d; wr <= 1'b1;
      @(posedge clk); wr <= 1'b0;
    end
  endtask

  // ---- mount requests, queued for the poll loop ---------------------------
  reg        m_req = 0, m_done = 0;
  integer    m_slot;
  reg [31:0] m_size;
  reg        m_ro;
  task mount(input integer slot, input [31:0] sz, input readonly);
    begin
      m_slot = slot; m_size = sz; m_ro = readonly;
      m_req = 1;
      wait (m_done);
      m_req = 0;
      wait (!m_done);
      repeat (2) @(posedge clk);
    end
  endtask
  task unmount(input integer slot);
    begin
      mount(slot, 32'd0, 1'b1);
    end
  endtask

  // ---- the PC program's loop ----------------------------------------------
  integer    rrb, slot, i, nn, w, nwords;
  reg [31:0] pend, lba;
  reg [5:0]  bcnt;
  reg        is_wr;
  reg [31:0] base;
  initial rrb = 0;

  always begin
    repeat (POLL_CYCLES) @(posedge clk);

    if (m_req && !m_done) begin
      bus_write(SIZE_LO, m_size);
      bus_write(SIZE_HI, 32'd0);
      bus_write(MOUNT, {23'd0, m_ro, 4'd0, m_slot[3:0]});
      repeat (8) @(posedge clk);
      m_done = 1;
      wait (!m_req);
      m_done = 0;
    end

    bus_read(PEND);
    pend = rv;
    slot = -1;
    for (i = VDNUM - 1; i >= 0; i = i - 1) begin
      nn = i + rrb;
      if (nn >= VDNUM) nn = nn - VDNUM;
      if (pend[nn]) slot = nn;
    end
    rrb = (rrb == VDNUM - 1) ? 0 : rrb + 1;

    if (slot >= 0) begin
      is_wr = pend[16 + slot];
      bus_read(LBA0 + 4 * slot);  lba  = rv;
      bus_read(CNT0 + 4 * slot);  bcnt = rv[5:0];
      nwords = (bcnt + 1) * 256;
      base   = lba * 512;
      // a PC program takes a while; then check the request did not move
      repeat (POLL_CYCLES / 2) @(posedge clk);
      bus_read(LBA0 + 4 * slot);
      if (rv != lba) begin
        $display("PC MODEL: LBA changed between poll and START on slot %0d - VIOLATION", slot);
        violations = violations + 1;
      end
      bus_write(XFER, 32'h100 | slot);           // START
      bus_read(PEND);
      if (rv[slot]) begin
        $display("PC MODEL: request on slot %0d still up after START - VIOLATION", slot);
        violations = violations + 1;
      end
      if (!is_wr) begin
        for (w = 0; w < nwords; w = w + 1) begin
          if (base + 2 * w + 1 < IMG_BYTES)
            bus_write(DATA, {16'd0, img[slot*IMG_BYTES + base + 2*w + 1],
                                    img[slot*IMG_BYTES + base + 2*w]});
          else
            bus_write(DATA, 32'd0);
        end
        n_reads = n_reads + 1;
      end else begin
        for (w = 0; w < nwords; w = w + 1) begin
          bus_read(DATA);
          if (base + 2 * w + 1 < IMG_BYTES) begin
            img[slot*IMG_BYTES + base + 2*w]     = rv[7:0];
            img[slot*IMG_BYTES + base + 2*w + 1] = rv[15:8];
          end
        end
        n_writes = n_writes + 1;
      end
      bus_write(XFER, 32'h200);                  // END
      bus_read(ERRS);
      if (rv != 32'd0) begin
        $display("PC MODEL: ERRS = %0o after a transfer - VIOLATION", rv);
        violations = violations + 1;
      end
    end
  end
endmodule
