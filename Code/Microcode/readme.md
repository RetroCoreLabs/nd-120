# ND-120/CX Microcode

The complete microcode of the Norsk Data ND-120 "DELILAH" CPU - as EPROM dumps,
as a 600 DPI scan of the original 1987 printed listing, and as **fully
reconstructed, compilable assembly source** recovered from that scan and proven
bit-for-bit against the silicon.

## The reconstructed source

| File | Version | What it is |
|------|---------|------------|
| [ND-120-DELILAH-K.LISTING.txt](ND-120-DELILAH-K.LISTING.txt) | K (oct 13) | The printed listing, re-typed from the scans - every line number, label, comment and instruction |
| [nd-120-delilah-K.uc](nd-120-delilah-K.uc) | K | The same source, compilable with the ND110Compile assembler |
| [ND-120-DELILAH-L.LISTING.txt](ND-120-DELILAH-L.LISTING.txt) | L (oct 14) | Version L, derived from K by applying ND's own changes |
| [nd-120-delilah-L-from-K.uc](nd-120-delilah-L-from-K.uc) | L | Compiles **bit-exact against the EPROM dump - all 4886 words** |

The printed listing is version **K**; the EPROMs in the machines are version
**L**, so `ND-120-DELILAH-L.LISTING.txt` is the listing to cite for what the
ROMs hold. Its second column is the octal control-store address (the WCS
address, LUA): for example MACL3 is at 002003 in the listing and at word
0o2003 in the PROM images. The L listing has no symbol index; for that, use the
scanned PDF below.

It took a long OCR-correction campaign (every suspect line verified against the
page scans) to get here, and the payoff is the full K->L diff: Norsk Data bumped
the version word, inserted **one** `COMM,SLOW` word in the CPU-init sequence,
removed the P/B/X register-read delay (an assembler token-table change - no
source lines touched), adjusted six condition-false sequencing specs, and made
four small operand fixes. **13 changed source lines in total, and every jump
label identical** - that is the entire difference between the two ROMs.

The reconstruction pipeline, gates and the full change-log live in the
ND120UC repo (external repository, not in this tree) (`docs/K-to-L-source-changes.md`).

## The EPROMs

The microcode is stored in two 32 KByte EPROMs, each holding 8 bits of a
16-bit word:

- [AM27256_45132L](AM27256_45132L.bin) - LO 8 bits (0-7)
- [AM27256_45133L](AM27256_45133L.bin) - HI 8 bits (8-15)

The 45132/45133 pair contains the 32-bit floating point code; the
45148/45149 pair contains the 48-bit floating point code.

Each 64-bit microcode word is built from 4 consecutive 16-bit reads:

| EPROM Address | Microcode bits |
|---------------|----------------|
| 0 | Bits 48-63 |
| 1 | Bits 32-47 |
| 2 | Bits 16-31 |
| 3 | Bits 0-15 |

The low byte of the word at octal address 020 is the microcode version:
oct 13 = K, oct 14 = L.

Careful: the C# example below and `gen_wcs_image.py` both put EPROM address 0
of a group in bits 0-15 and address 3 in bits 48-63 - the reverse of the table
above. `gen_wcs_image.py` names the four reads RF=0..3 (RF=0 -> bits 15:0,
PROM byte index = LUA*4 + RF), and the WCS images the boards run are built
that way.

## Files in this folder that the builds use

| File | What it is |
|------|------------|
| `AM27256_45132L.bin`, `AM27256_45133L.bin` | The raw EPROM dumps. The truth. |
| `AM27256_45133L.hex` | The HI EPROM as text for `$readmemh`. Same bytes as its `.bin`. |
| `AM27256_45132L.hex` | The LO EPROM as text for `$readmemh`. **Not the same as its `.bin`** - it carries the 002003 patch below. |
| `AM27256_45132L.hex.bak` | The LO EPROM as text, unpatched (same bytes as `AM27256_45132L.bin`). |
| `gen_wcs_image.py` | Builds a ready-loaded control-store (WCS) image from the two `.hex` files, so a build can skip the runtime PROM->WCS load. Writes `wcs/` (default) or `wcs-sim/` (`--sim`); both folders are git-ignored and made again by running the script. |
| `wcs/` | 33 files: `wcs_image.hex` (8192 x 64-bit words) and one nibble file per IDT6168A chip (`wcs_16C.hex` ... `wcs_31D.hex`). The board builds preload these. |
| `wcs-sim/` | The same, with the 002002 simulator patch applied (for `SKIP_WCS` simulation runs). |

Copies of the `.hex` files and of the WCS images sit next to the harnesses and
board builds that `$readmemh` them; `make test-microcode-sync` (in
`Verilog/tests/`) checks every copy against the variant its folder must hold.

### The two patched microwords (measured 28-SEP-2026 against the `.bin` files)

Neither patch changes the `.bin` dumps. Both are in the master-clear wait loop,
listing lines 5105-5123 of `ND-120-DELILAH-L.LISTING.txt`
(`% WAITING LOOP 0.5 - 1 SECOND`).

| Word (octal) | Listing | PROM byte | Raw | Patched | Where the patched byte is |
|---|---|---|---|---|---|
| 002003 (MACL3) | line 5121-5123, `MACL3: B,1 ... MACL4 CONDENABL` | `AM27256_45132L`, byte 0o10015 (RF=1) | 0o201 | 0o001 | `AM27256_45132L.hex` here (commit d6799aa, 07-DEC-2024, "Patched microcode address 002003 to disable waiting loop") and so in every copy made from it, **including `wcs/` and `Verilog/Shared/support/wcs_*.hex`, which the boards preload**. Only `AM27256_45132L.hex.bak` and `Verilog/CPU-BOARD-3202/circuit/BIF_BCTL_SYNC_8/sim/AM27256_45132L.hex` hold the raw byte. |
| 002002 (MACL+1) | line 5117-5119, `A,6 B,R1 ... IDBS,BMG` | `AM27256_45133L`, byte 0o10010 (RF=0) | 0o140 | 0o000 | Only the simulator copies of `AM27256_45133L.hex` (`Verilog/sim`, `runSim`, `dmaSim`, `ND-120-Yosys`; commit 895f360) and `gen_wcs_image.py --sim` (`wcs-sim/`). |

What each bit is, read from the ND110Compile token table (`ND120Tokens.cs`),
not from a simulation:

- 002003: the cleared bit is RF1 0o200, the `CONDENABL` bit (`CONDENABL` =
  RF1 0o002200; the 0o002000 part, DLY0, stays set). Without it, MACL3 takes
  its true spec `T,NEXT` to 002004 instead of entering the MACL4 loop.
- 002002: the cleared bits are RF0 0o060000, the A-operand `A,6` -> `A,0`. The
  bit-mask generator then loads R1 (the outer loop count) with 1 instead of 64.

## Reading the binary microcode in C#

C# code to read the microcode into a 64-bit wide array named `chip_microcode`:

```csharp
        byte[] LOBits = File.ReadAllBytes("AM27256_45132L.bin");
        byte[] HiBits = File.ReadAllBytes("AM27256_45133L.bin");


        ulong[] chip_microcode = new ulong[1024 * 64];
        int cnt = 0;
        for (int i = 0; i < HiBits.Length; i += 4)
        {
            ulong uc = 0;
            for (int b = 3; b >= 0; b--)
            {                
                ushort w = (ushort)(HiBits[b + i] << 8 | LOBits[b + i]);
                uc = uc << 16;
                uc |= (ushort)w;
            }



            string ucHex = $"{uc:X16}".PadLeft(16, '0');
            string addr = Convert.ToString(cnt, 8).PadLeft(6, '0');

            Console.WriteLine($"i={i}, uC[{addr}]: {ucHex}");
            chip_microcode[cnt++] = uc;
        }

        ushort version = (ushort)(chip_microcode[0x10] & 0xFF);
        Console.WriteLine($"Version is {Convert.ToString(version,8)}  (octal)");

```

## Documentation

- [ND-120 Mikroprogramlisting-L-ocr.pdf](ND-120%20Mikroprogramlisting-L-ocr.pdf)
  - the original printed listing (version K), 249 pages, scanned at 600 DPI.
  The source of truth the reconstruction was verified against. It also holds
  the symbol index (label -> address) that the re-typed listings leave out.
- [ND-06.031.1 EN ND-110 and ND-120 Microprogrammer's Guide](ND-06.031.1%20EN%20ND-110%20and%20ND-120%20Microprogrammer's%20Guide-Gandalf-OCR.pdf)
  - the reference for understanding the microcode word format and tokens.

## Schematic

Here you can see how the EPROMs were connected to the internal data bus (IDB):

![Schematic for EPROM](images/CPU_EPROM.png)

## EPROM on CPU board 3202

![CPU Board 3202 with EPROM](images/3202_microcode_EPROMS.png)
