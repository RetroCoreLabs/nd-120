# Deploying and Testing on the MiSTer

A fast edit-compile-run loop. Three deploy paths, fastest first. (For the
user-facing copy-and-boot steps see [`../../QUICKSTART-mister.md`](../../QUICKSTART-mister.md).)
All links verified 2026-07-08.

## 1. The everyday loop: scp + hot-load (no SD card swapping, no cable)

The MiSTer's Linux side exposes a command FIFO at `/dev/MiSTer_cmd`. This is
confirmed straight from Main_MiSTer source (`input.cpp`:
`#define CMD_FIFO "/dev/MiSTer_cmd"`, parser calls `fpga_load_rbf()` for
`load_core`) — repo: https://github.com/MiSTer-devel/Main_MiSTer

```bash
# from Verilog/fpga/mister/ after a successful compile:
scp output_files/nd120.rbf root@<mister-ip>:/media/fat/
ssh root@<mister-ip> 'echo "load_core /media/fat/nd120.rbf" > /dev/MiSTer_cmd'
```

Password is `1` (official docs:
https://mister-devel.github.io/MkDocs_MiSTer/advanced/network/). Set up an ssh key
so the loop is two commands with no prompts. `load_core` also accepts `.mra` and
`.mgl` paths (arcade/shortcut files — not needed for us).

scp deploy example in the wild (validated writeup):
https://gabriellawrence.com/posts/MiSTerVGA/index.html

There is **no** documented file-watcher that auto-loads a new .rbf; you either issue
`load_core` or pick the core in the OSD (the menu re-enumerates `/media/fat` when
browsed).

For scripted control beyond load_core (inject key presses, generate .mgl shortcuts),
**MiSTer_Batch_Control** runs on the MiSTer itself:
https://github.com/pocomane/MiSTer_Batch_Control (e.g. `mbc raw_seq EEMDDO` to drive
the menu, `mbc load_rom ...`).

### Mounting images at core load: use an MGL

For this core the framework automount (`boot<n>.vhd` in
`/media/fat/games/ND120/`) does NOT attach anything - measured 02-SEP-2026
with the `ND120_STORAGE_PROBE` console probe (`MNT=00000`). Use an MGL:
`load_core /media/fat/ND120-storage-test.mgl` mounts floppy 0, floppy 1,
WD0 and the tape (probe shows MNT 10000 -> 11000 -> 11100 -> 11101, bit
order fd0 fd1 WD0 WD1 tape).

Board loop: `Verilog/fpga/mister/tools/deploy_and_look.sh` (its header lists
MISTER_HOST, MISTER_PASS, MISTER_SETTLE).

## 2. Making the core appear in the menu (the "release" path)

- A core is one `.rbf`; loading it reprograms the FPGA (official explanation:
  https://mister-devel.github.io/MkDocs_MiSTer/cores/what/ — flash-free, "safe for
  many millions of rewrites").
- The OSD's top-level sections come from underscore-prefixed folders on `/media/fat`
  (`_Console`, `_Computer`, `_Arcade`, `_Other`, `_Utility`). This convention is
  confirmed indirectly by the official FAQ's `/_Unstable/` folder note
  (https://mister-devel.github.io/MkDocs_MiSTer/basics/faq/) and the `_Console`
  reference on the cores/what page. **[the exact rule "put nd120_YYYYMMDD.rbf in
  /media/fat/_Computer/" is inferred from this convention, not stated on one page —
  verify once with your own SD card]**

```bash
ssh root@<mister-ip> 'mkdir -p "/media/fat/_Computer"'
scp output_files/nd120.rbf root@<mister-ip>:"/media/fat/_Computer/nd120_20260708.rbf"
```

Then F12 → Computer section → ND120. The date suffix is the official release naming
convention (Template README: `<core_name>_YYYYMMDD.rbf`).

- The menu *entries inside* the core (options, mount slots, reset) come from
  CONF_STR in the FPGA bitstream itself — **zero Linux-side code**. See
  [04-core-config-menu.md](04-core-config-menu.md).
- Where disk images go (for later phases): games/media are searched under
  `/media/fat/games/<CORE>/`, with USB and CIFS taking priority
  (https://mister-devel.github.io/MkDocs_MiSTer/cores/paths/). Transfer via
  scp/FTP/Samba (https://mister-devel.github.io/MkDocs_MiSTer/setup/games/).

## 3. JTAG upload from Quartus (best while iterating in the GUI)

Official debugging page:
https://mister-devel.github.io/MkDocs_MiSTer/developer/debugging/

- Connect the DE10-Nano's **mini-USB port next to HDMI** (on-board USB-Blaster II,
  VID:PID 09fb:6810) to the dev machine.
- Program the FPGA directly from Quartus (the Template ships a `jtag.cdf` programmer
  file). "MiSTer supports USB Blaster and automatically reloads Linux part for
  uploaded core" — the ARM side reboots for stability, so it takes a bit longer;
  the docs advise having a console attached to watch the boot.
- Linux udev rules for non-root JTAG (`/etc/udev/rules.d/92-usbblaster.rules`):

  ```
  SUBSYSTEM=="usb", ATTR{idVendor}=="09fb", ATTR{idProduct}=="6010", MODE="666"
  SUBSYSTEM=="usb", ATTR{idVendor}=="09fb", ATTR{idProduct}=="6810", MODE="666"
  ```

- Under WSL2, attach the blaster with `usbipd` first — same workflow as the
  Basys3/Tang FTDI devices (see `Verilog/fpga/tang-nano-20k/README.md`).
- This is also the transport for **SignalTap** ([06-debugging.md](06-debugging.md)).

## 4. Testing the ND-120 core specifically

Smoke tests, cheapest signal first:

- **Core loads:** LED heartbeat correct (PLL ok)? Core name in OSD (CONF_STR ok)?
  Four-line banner on screen and the CPU `G` lamp green (self-test passed)?
- **OPCOM:** the console is the MiSTer's own screen and keyboard (a TDV2200
  terminal); the CPU serial line is also on the HPS `/dev/ttyS1` at 115200 7E1
  (see the UART notes in [05-devices-block-char.md](05-devices-block-char.md)).
  Expect the same OPCOM behavior as `runSim/` (prompt, `0/`, deposit/examine).
  Compare against the Verilator reference transcript — divergence here means
  clock-domain or latch-residue issues, not MiSTer issues.
- **Microcode upload:** deliberately load a corrupted WCS file — the core should
  fail the same way the Verilator harness does with the same corruption.
- **Disks:** mount a known image via the OSD `S0` slot; watch `LED_DISK`
  activity; verify sector reads against the same image file checked with
  `xxd`/`dd` on the Linux side (ssh in — the image is just a file).

When something fails on the board but works in Verilator, go to
[06-debugging.md](06-debugging.md) — that's the whole discipline this repo already
practices, with SignalTap replacing Vivado ILA.

## Deploy checklist

- [ ] One-command deploy works (`scp` + `load_core`).
- [ ] Core appears under `_Computer` in the OSD with its own name + build date.
- [ ] Comes up at the `#` MOPC monitor; `&` boots SINTRAN from a mounted image.
