//---------------------------------------------------------------------------
// SD-FAT compile-time feature configuration
//
// Every feature is ON by default. Strip features (and their FPGA area) by
// defining the matching SDFAT_NO_* macro on the compiler command line, e.g.
//
//   yosys      read_verilog -DSDFAT_NO_CHECK -DSDFAT_NO_SPEED ...
//   iverilog   -DSDFAT_NO_CHECK
//   Makefiles  make SDFAT_FEATURES="-DSDFAT_NO_CHECK -DSDFAT_NO_SPEED"
//
// Features and their menu commands in the sd-fat-test project:
//
//   SDFAT_WRITE    sector write engine (CMD24) . . . . menu 4 (WRBLK1)
//   SDFAT_REWRITE  FAT surgeon: replace/create files .  menu 3 (COPY)
//   SDFAT_CHECK    cluster-chain validator . . . . . .  menu 5 (CHECK)
//   SDFAT_SPEED    IO speed tests + KB/s divider . . .  menu 6/7
//   SDFAT_FREESCAN FAT free-space scan . . . . . . . .  menu 1 (LIST info)
//
// The card reader (mount, LIST, DUMP - menu 1/2) is always present.
// Stripped commands answer "NOT IMPLEMENTED" on the console.
//
// SDFAT_NO_LFN is a separate RAW strip macro consumed DIRECTLY by
// sd_file_reader.v (it does not include this header): defined, it removes the
// VFAT long-filename parser (~1800 LUT+ALU) and matches files by 8.3 name
// only. Pass it the same way as the SDFAT_NO_* macros above (-DSDFAT_NO_LFN
// or a `define ahead of the compilation unit). Used by the Tang tape build.
//
// Dependencies are resolved here: REWRITE and SPEED need WRITE; SPEED
// needs REWRITE (it reallocates IO.DAT). Excluding a prerequisite
// excludes its dependents automatically.
//
// Ronny Hansen, 11-JUL-2026
//---------------------------------------------------------------------------
`ifndef SDFAT_FEATURES_VH
`define SDFAT_FEATURES_VH

`ifndef SDFAT_NO_WRITE
  `define SDFAT_WRITE
`endif

`ifdef SDFAT_WRITE
  `ifndef SDFAT_NO_REWRITE
    `define SDFAT_REWRITE
  `endif
  `ifndef SDFAT_NO_CHECK
    `define SDFAT_CHECK
  `endif
`endif

`ifdef SDFAT_REWRITE
  `ifndef SDFAT_NO_SPEED
    `define SDFAT_SPEED
  `endif
`endif

// LIST free-space scan: reads FAT sectors through the sd_writer engine's
// read path, so it needs the write engine (like CHECK). Stripped, LIST
// still prints CARD and VOL sizes but reports FREE N/A.
`ifdef SDFAT_WRITE
  `ifndef SDFAT_NO_FREESCAN
    `define SDFAT_FREESCAN
  `endif
`endif

// nd_storage multi-client facade (docs/nd-storage-design.md section 3).
// Needs the write engine both for the block write-through path and for
// the mount-time read path of the contiguity checker.
`ifdef SDFAT_WRITE
  `ifndef SDFAT_NO_STORAGE
    `define SDFAT_STORAGE
  `endif
`endif
`ifdef SDFAT_STORAGE
  // RETIRED AS A DEFAULT 07-AUG-2026: the storage engine walks the FAT
  // chain at runtime (nd_storage_engine.v F_RES states,
  // docs/nd-storage-design.md 2.2), so fragmented files are simply CORRECT
  // and there is nothing left for a mount-time contiguity gate to protect.
  // The checker remains available as a diagnostic build
  // (-DSDFAT_FORCE_STORAGE_CHECK - its testbenches build it that way);
  // nothing defines it by default, which also returns its logic to the
  // Tang budget (the tape+floppy+WD build was 114 cells over WITH it).
  `ifdef SDFAT_FORCE_STORAGE_CHECK
    `define SDFAT_STORAGE_CHECK
  `endif
`endif

`endif  // SDFAT_FEATURES_VH
