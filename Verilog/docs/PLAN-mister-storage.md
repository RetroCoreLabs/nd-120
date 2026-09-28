# PLAN - MiSTer storage: floppy, Winchester and paper tape from OSD-mounted files

> Living plan, outstanding work only. Started 01-SEP-2026.

Phases 1-3 are built and recorded: the backend `fpga/mister/rtl/nd_storage_hps.v`
(`make test-storage-hps`), the device aggregator
`fpga/mister/rtl/nd_storage_mister_devices.v` (`make test-storage-devices`),
and the five OSD slots in `nd120.sv` (`fpga/mister/docs/04-core-config-menu.md`,
`05-devices-block-char.md`, `build-defines.md` section 6). Slot map: 0 floppy 0,
1 floppy 1, 2 WD0, 3 WD1, 4 tape. On the board SINTRAN III boots from an
OSD-mounted WD0 at the `&` prompt, with 4 MB main memory in the DE10-Nano
SDRAM (`fpga/mister/README.md`, 02-SEP-2026). Also measured on the board: `400$`
from the tape slot loads FILSYS (the tape path and the byte order are right),
and FILSYS LIST-USERS reads FLOPPY-DISC-1 and DISC-74MB-1 (WD0) correctly.

## Next

The Phase 4 board checks below. Every build and flash on Ronny's go.

## Phase 4 - board

Not recorded as done anywhere; still open until someone runs them.

- [ ] `1560&`: floppy boot from slot 0. Then drive 1 from slot 1.
- [ ] Winchester: read known sectors with OPCOM and compare bytes against the
      Verilator run (`ND120_WD_IMG`, same CHS->LBA); write a sector, unmount,
      verify the file changed on the Linux side.
- [ ] Unmount/remount while idle; a mount while a request is pending.
- [ ] `fpga/mister/nd120.sdc` has no SDRAM pin constraints (neither has the
      Tang nor the PDP2011 port). At the present clocks the margins are wide,
      but if the board misbehaves that is the first thing to add.

Board facts for these checks:

- The working default mount is the MGL: `load_core
  /media/fat/ND120-storage-test.mgl` mounts floppy 0, floppy 1, WD0 and the
  tape. The framework automount (`/media/fat/games/ND120/boot2.vhd` -> slot 2)
  did NOT attach anything for this core (measured 02-SEP-2026 with the
  `ND120_STORAGE_PROBE` console probe: `MNT=00000`), so `boot2.vhd` was
  removed.
- Typing OPCOM commands over ssh does NOT work yet: a `/dev/uinput` keyboard
  (`mister_type.py`, on the board in the games folder) is registered by the
  kernel but neither the console nor the F12 OSD react. Until that is solved
  the `400$` / `1560&` / OPCOM steps need Ronny at the keyboard while the
  screenshots are pulled back.
- Run Quartus in Docker from WSL, not from Git Bash: from Git Bash the
  container's working directory gets rewritten to a Windows path and the run
  dies before Quartus starts.

## Phase 5 - close out

- [ ] `fpga/mister/README.md`: a storage section on how it works, with the
      slot map and image sizes (floppy 315 392 B / >= 1 261 568 B, WD
      8x9x1024 cylinders x 1024 B).
- [ ] Move "The HPS block contract" below into
      `fpga/mister/docs/05-devices-block-char.md`, then delete this plan.

## Decided by Ronny (01-SEP-2026)

- Two Winchester slots (WD0, WD1), matching the card (its unit field is one
  bit, control word b9, `ND_WINCHESTER.v`). SMD is not built.
- Paper tape: one file, one slot.
- The mount flags and the tape fault code are NOT displayed - the OSD shows
  what is mounted, and the FDISK/WDISK error codes reach SINTRAN. The nets
  stay in `nd120.sv` for a probe.

## The HPS block contract (reference)

Read 01-SEP-2026 from the official docs, `Main_MiSTer/user_io.cpp`, the
Template `hps_io.sv` and a survey of 11 official cores.

Decision: drive `sd_rd/sd_wr` DIRECTLY, one OSD slot per drive. That is what
7 of the 11 mainstream computer cores do (Atari ST and Archie floppies, Apple
II, C64, BK0011M, TRS-80, ZX Spectrum's floppy slot). The `sys/sd_card.sv`
virtual SPI card is used only where the GUEST software bit-bangs an SPI card
(DivMMC, MSX SD mapper, Acorn MMFS); ours never were SPI. ao486, PCXT and
Minimig use an ARM-served protocol that needs Main_MiSTer C++ changes.

- The ARM POLLS. It reads a status word (`{1, sd_blk_cnt[sdn], BLKSZ, sdn,
  sd_wr, sd_rd}`) up to 4 times per main loop pass, picks ONE slot round-robin,
  reads that slot's `sd_lba` in the same transaction, then runs one data
  transaction with `sd_ack[slot]` high for its whole length. So: hold
  `sd_rd`/`sd_wr` until `sd_ack` RISES, then clear it; the FALLING edge means
  done; `sd_lba` and `sd_blk_cnt` stable from request until ack; several slots
  may request at once and are served one per poll.
- `sd_blk_cnt = 3` with `BLKSZ = 2` (512) = one 2048-byte transaction (one ND
  storage client block), one ack, `sd_buff_addr` running 0..1023 words in
  WIDE mode. BLKSZ is one value for ALL slots. The HPS clamps at 16384 bytes.
- `WIDE=1` gives 16-bit words. HPS words are little-endian (`{byte 2w+1,
  byte 2w}`); ND image words are big-endian. The backend swaps bytes once, in
  both directions.
- Data arrives at the HPS SPI rate, not one word per clock; `sd_buff_wr`
  pulses one `clk_sys` cycle per word, the address increments two cycles
  later, saturates, never wraps. For writes the core must present
  `sd_buff_din = buffer[sd_buff_addr]` from address 0 the moment ack rises.
  The buffer bus is BROADCAST: qualify every buffer write with the slot's own
  `sd_ack` bit.
- `clk_sys` into `hps_io` must be >= 20 MHz (sorgelig, Main_MiSTer #683);
  ours is 40 MHz.
- `sd_lba` is file-relative: the HPS resolves the mounted file, so no FAT
  layer is needed on the MiSTer.
- A read on an unmounted or short image is still acked and returns ZEROS.
  "No image" is only knowable from the mount pulse: `img_mounted[n]` is a
  few-cycle PULSE, `img_size`/`img_readonly` are valid during it (size sent
  first); unmount is the same pulse with `img_size == 0`.
- Writes go to the file immediately (`O_SYNC`, fwrite+fflush). A write past
  EOF is trimmed; an image cannot grow through the core. Read-only is only
  reported (`img_readonly`), never enforced on the HPS side.
- `S{slot}` is documented as 0-3 but the code accepts 0-9, `hps_io.sv` allows
  VDNUM 1..10, and TRS-80_MiSTer ships `S4` with `VDNUM(5)`. (Bit 7 of the
  mount word is the read-only flag, so 7+ would collide.) TRS-80 also found
  that an `FS` save-file line clobbers slot 0 - we have no such line.
- The HPS is documented to automount `boot0.vhd`..`boot3.vhd` / `ND120.VHD`
  from the core's folder into slots 0-3 at start (for this core it did not -
  see Phase 4).
- Tapes in official cores (PDP-1, ZX Spectrum, C64, TRS-80) are `F` downloads
  via `ioctl_*`, never `S` mounts. Our tape adapter already reads blocks,
  gives rewind for free and holds one 2048-byte block, so the tape stays on an
  `S` slot. Fallback if that misbehaves: an `F` line with `ioctl_wait` pacing,
  the PDP-1 shape.
- Neither `ND_FLOPPY_DMA` (its `DISK_TIMEOUT` defaults to 0 = off) nor
  `ND_WINCHESTER` times out a backend; a backend that never answers hangs the
  guest. The MiSTer backend answers NOTOPEN at once for an empty slot.
