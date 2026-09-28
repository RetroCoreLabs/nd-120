# SD card setup for the sd-fat-test board

What to put on the microSD card, and how. Applies to the sd-fat-test
menu build (LIST/DUMP/COPY/WRBLK1/CHECK/speed tests). One file is
required; everything else the board creates by itself.

## 1. Format

FAT16 and FAT32 both work (FAT32 fully supported, any first-cluster
location). Cards up to SDHC (<= 32 GB) are supported; exFAT (the
factory format of most SDXC > 32 GB cards) is NOT - reformat those as
FAT32.

A FRESH format is recommended: newly copied files on a fresh volume are
contiguous, which is what the in-place write features (COPY, WRBLK1,
speed tests) rely on. Menu 5 (CHECK) verifies every file's cluster
chain if you want proof.

Linux / WSL (whole card as one volume, no partition table needed):

    sudo mkfs.vfat -F 32 -n ND120 /dev/sdX        # or -F 16 for FAT16
    # (replace sdX with the card device; check with lsblk first!)

Windows: right-click the card drive -> Format -> FAT32, quick format
is fine.

A partitioned card (the usual factory layout with one partition) also
works - the mount logic follows the MBR to the partition. Format the
partition FAT32 the same way (mkfs.vfat /dev/sdX1).

## 2. The one required file: BOOT.BPUN

Copy any BPUN program image to the ROOT directory named exactly
BOOT.BPUN:

    # Linux, with mtools (no mounting needed):
    mcopy -i /dev/sdX Verilog/runSim/INSTRUCTION-B.BPUN ::BOOT.BPUN

    # or mounted / Windows: plain file copy + rename to BOOT.BPUN

Good first payloads from the repo (any BPUN works):

| File | Size | Note |
|---|---|---|
| Verilog/runSim/INSTRUCTION-B.BPUN | 46566 B | the standard test tape |
| Verilog/runSim/RTC.BPUN | 2342 B | small; menu 4 (WRBLK1) will refuse it - see below |
| Verilog/runSim/TPE-MON-100-B00.BPUN | 56182 B | monitor tape |

Rules for the file:
- ROOT directory (subdirectories are not searched).
- Plain file attributes (not read-only, not hidden).
- Long or 8.3 name both fine - the lookup is case-insensitive.
- Maximum 64 KB reaches the dump buffer; larger files are dumped
  truncated (with a message) but everything else still works.
- Menu 4 (write pattern to 1-kiloword block 1) requires the file to be
  at least 4096 bytes, otherwise it refuses with BLOCK OUT OF RANGE -
  that is a safety check, not an error in your setup.

## 3. Files you do NOT need to create

| File | Created by | Purpose |
|---|---|---|
| TEST.TXT | menu 3 (COPY) | copy target; created or replaced automatically |
| IO.DAT | menu 6 (write speed) | 2 MB speed-test file; created/reallocated automatically |

If old versions of these exist they are reused/replaced in place -
also fine.

## 4. Optional: anything else

Other files and directories on the card are harmless and show up in
LIST (menu 1) with size, date, first cluster, and <DIR> markers. The
board never touches anything except BOOT.BPUN (read-only), TEST.TXT
and IO.DAT.

## 5. Quick sanity sequence after inserting the card

    1   LIST     - card mounts, files visible
    5   CHECK    - every cluster chain OK
    2   DUMP     - BOOT.BPUN bytes (compare against xxd on the PC)
    3   COPY     - creates/overwrites TEST.TXT; LIST shows the new size
    6 then 7     - write then read speed (IO.DAT created automatically)

Console: 9600 8N1 on the BL616 USB serial (/dev/ttyUSB1 under WSL);
if the TangNano20K /> prompt of the BL616 answers instead of the menu,
type `choose uart` once. H prints the help. S1/S2 = full reset.

## 6. The ND-120 device file set

This test board needs only the files above. The full ND-120 builds use a
fixed set of root-directory file names, one per emulated device (`TAPE.BPUN`,
`FLOPPY1.IMG`, `WD0.IMG`, ...); the table is in
`Verilog/docs/nd-storage-design.md` ("Card file set"), and the board
quickstarts (`Verilog/fpga/QUICKSTART-*.md`) say which image to copy.
