# Floppy/Streamer controller 3106/3112 — verified register spec (ND-11.021.01)

Source (read directly, quoted): `NDInsight/SINTRAN/Devices/SCSI/ND-11.021.1 EN-Floppy
and Streamer Controller 3106 3112.md`. This file is the ground truth for aligning
`ND_FLOPPY_DMA.v`, nd100x `deviceFloppyDMA.{c,h}`, and RetroCore `NDBusFloppyDMA.cs`.

## KEY STRUCTURAL POINT: there are TWO different status words

The single most important thing the manual makes explicit — and which nd100x AND our
Verilog conflate into one register — is that the **hardware status register (read over
IOX) is NOT the same word as the "Status Word 1" written back into ND-100 memory.**
They have different bit-15 meanings and only ONE of them carries the numeric error code.

### §3.7 Hardware Status Word — returned by `IOX Devno+2` AND `IOX Devno+4`
Per §3.1 Note 1: *"Reading either status gives the same result. They are duplicated to
make it possible for microprograms in the ND-100 CPU to perform both Binary Format Load
and Mass Storage Load (1560x and 21560)."* So +2 and +4 return the SAME word:

| bit | meaning |
|----|---------|
| 0  | Not used |
| 1  | RFT / Interrupt Enabled |
| 2  | Device Active |
| 3  | Device Ready for Transfer |
| 4  | OR of Errors |
| 5  | Not Used |
| 6  | Streamer Active |
| 7  | Hard Error - DMA Transfer |
| 8-13 | (blank; 11 = Reserved) |
| 14 | Streamer interface |
| 15 | **Dual density controller** (this is the always-1 bit SINTRAN uses to detect the DMA/3112 controller) |

**There is NO numeric error code in the hardware status word.**

### §3.4 Status Word 1 — written back into the command block at CB+6 (memory)
| bit | meaning |
|----|---------|
| 0  | Not used |
| 1  | RFT / Interrupt enabled |
| 2  | Device active (same as hardware status word) |
| 3  | Device ready for transfer |
| 4  | Or of errors |
| 5  | Deleted record |
| 6  | Retry on controller |
| 7  | Hard-error |
| 8  | **Not used** |
| 9-14 | **Error code from controller** |
| 15 | **Not used** |

§3.9: *"These error codes are given in bits 9-15 of status word 1."* (The §3.4 table draws
the field as bits 9-14 with bit 15 "Not used"; §3.9 prose says 9-15. The discriminating
low bit is settled at **9** either way; bit 8 = Not used explicitly.)

**The numeric error code lives ONLY here (memory CB+6), NOT in the IOX register.**

## §3.5.2.2 Status Word 2 (Card 3112) — written back at CB+7 (memory), NOT an IOX register
| bit | meaning |
|----|---------|
| 1  | Bytes/Sector |
| 2  | Double sided |
| 3  | Double density |
| 4  | 5 1/4" Drive |
| 5  | Non standard (format read valid for READ FORMAT or error 12 format mismatch) |
| 6  | 96 tpi |
| 7  | Not used |
| 9  | Selected unit |
| 12 | Sector/track |
| 15 | Not used |

This is the "format word." It is delivered in **memory at CB+7**, reached by the driver
(`FDRI2`: `LDA 3COMF+7`). It is **not** what IOX +4 returns (IOX +4 = the hardware status
word, per §3.7 / §3.1 Note 1).

## §3.6 Hardware Control Word — `IOX Devno+3` (write)
| bit | meaning |
|----|---------|
| 1  | Enable interrupt on RFT |
| 2  | Activate Autoload |
| 3  | Test Mode |
| 4  | Device Clear |
| 5  | Enable Streamer |
| 8  | Fetch Command & Execute |

## §3.1 IOX map
| IOX | function |
|-----|----------|
| +0 | Read Data |
| +1 | Not used |
| +2 | Read Status (hardware status word, §3.7) |
| +3 | Load Control Word (§3.6) |
| +4 | Read Status (SAME as +2, §3.1 Note 1) |
| +5 | Load Pointer High (bit 16-23) |
| +6 | Not used |
| +7 | Load Pointer Low / Load Data |

`+0` Read Data: the manual gives NO idle constant. Documented only: after a bus/DMA hard
error, +0 holds status word 1 (driver reads +0 via `IOX 1560` on error). The "1" vs "0x0F"
values in both emulators are un-sourced TODO guesses.

## §3.9 Error codes (octal) — the real table
```
00 OK                     05 CRC error              06 Sector not found
07 Track not found        10 Format not found       11 Diskette defect (impossible to format)
12 Format mismatch        13 Illegal format specified
14 Single sided diskette inserted   15 Double sided diskette inserted
16 Write protected diskette/cartridge   17 Deleted record
20 Drive not ready        21 Controller busy on start
22 Lost data (over/underrun)   23 Track zero not detected
24 VCO frequency out of range  25 Microprogram out of range
26 Timeout                27 Undefined error        30 Track out of range
32 Compare error          33 Internal DMA errors
40 ND-100 bus error command fetch    41 ...status transfer    42 ...data transfer
43 Illegal command        44 Word count not zero    45 Illegal completion (cont. transf.)
46 Addr-reg error         50 No bootstrap found on diskette
51 Wrong bootstrap (old flo-mon)     53 Error during Autoload
60-67 streamer errors     70 PROM checksum   71 RAM error   72 CTC error
73 DMA CTRL error (self-test)   74 VCO error   75 Floppy controller error
76 Streamer data register error 77 ND-100 register error
(01-04, 31, 34-37, 47, 52, 54-57 = Not used)
```

## Applied

All of it is applied (July 2026): `ND_FLOPPY_DMA.v` returns the hardware
status word (`s_hwstat`) on IOX +2 and +4 and writes Status Word 1 (`s_sw1`,
error code in bits 9-14) at CB+6, with the octal error codes above; nd100x has
the same fix (nd100x commit efed8ae, "floppy DMA status words"). The +0 idle
value is still undocumented in the manual - left as it is, not invented.
