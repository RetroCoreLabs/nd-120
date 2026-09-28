# Core Configuration: CONF_STR, hps_io, the OSD Menu

Goal: understand exactly how the F12 menu is defined and how its selections reach
your logic. Punchline up front: **the menu is a string constant in your Verilog.
There is no Linux-side code to write.** Confirmed from both the official docs
(https://mister-devel.github.io/MkDocs_MiSTer/developer/conf_str/) and Main_MiSTer
source (`user_io.cpp` reads the string from the FPGA via `user_io_read_confstr()`
and `parse_config()` builds the whole menu from it —
https://github.com/MiSTer-devel/Main_MiSTer).

All links verified 2026-07-08.

## 1. How it plugs together

In your `emu` module (from Template.sv, verbatim shape):

```verilog
localparam CONF_STR = { ... the menu ... };

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
    .clk_sys(clk_sys),
    .HPS_BUS(HPS_BUS),
    .buttons(buttons),
    .status(status),           // OSD selections land here
    .status_menumask({...}),   // dynamic show/hide of entries
    .ps2_key(ps2_key),
    ...
);
```

- `hps_io.sv` lives in `sys/` (source:
  https://raw.githubusercontent.com/MiSTer-devel/Template_MiSTer/master/sys/hps_io.sv).
  Key parameters: `VDNUM` (number of virtual disk drives, 1-10), `WIDE` (16-bit vs
  8-bit file I/O), `BLKSZ` (block size code: 0=128 bytes ... 2=512 default ... 7=16384).
- The ARM reads CONF_STR byte-by-byte over `HPS_BUS` at core load; the OSD renders it.
- Official hps_io overview:
  https://mister-devel.github.io/MkDocs_MiSTer/developer/hps_io/

## 2. CONF_STR syntax (validated against the official wiki + live cores)

References: https://mister-devel.github.io/MkDocs_MiSTer/developer/conf_str/ and
https://github.com/MiSTer-devel/Wiki_MiSTer/wiki/Core-configuration-string

- `"<CoreName>;<options>;"` — header. Extras can ride in the header, e.g. PDP2011
  uses `"PDP2011;UART19200;"` — the `UART<speed>` token enables the framework UART
  menu/bridge (that's how we get OPCOM to a real terminal).
- `-;` — separator line.
- `O[hi:lo],Name,opt0,opt1,...` — option mapped to `status[hi:lo]`. 128 status bits
  exist (`status[127:0]` port); **bit 0 is reserved for reset by convention**.
- `T[i],Name;` — momentary trigger, pulses `status[i]` (e.g. `T[0],Reset;`).
- `R[i],Name;` — same, but closes the OSD.
- `S<slot>,<EXT1><EXT2>...,Label;` — **mount a disk image** into virtual-drive slot
  0-3. Extensions are 3 chars each, concatenated: `S0,DSKIMGVHD,Mount Drive;`.
  Mounting drives the `img_mounted/img_size` + `sd_*` block interface
  ([05-devices-block-char.md](05-devices-block-char.md)).
- `F[S]<index>,<EXT>,Label[,Address];` — **load a file** streamed into the core via
  the ioctl interface; `ioctl_index` tells you which F-entry sent it. `FS` = savable.
- `P<n>,Title;` + `P<n>O[...]...` — submenu pages.
- `H<n>`/`h<n>` hide and `D<n>`/`d<n>` disable entries based on
  `status_menumask[n]` (uppercase = when mask bit set, lowercase = when clear).
- `J[1],...` / `jn,`/`jp,` — joystick button definitions (not needed for ND-120).
- `V,v` + `` `BUILD_DATE `` — version string shown next to the core name.
- `I,...` info lines; `SS<base>:<size>` savestates (future exotica).

## 3. A real, complete example

PDP2011's menu (`pdp2011.sv` in
https://github.com/MiSTer-Enhanced/PDP2011_MiSTer) shows the usual pattern:
S-slots for disks, O-bits for machine configuration, a P1 page for terminal
cosmetics, T/R reset. Section 4 is ours, and is the one to copy from.

## 4. The shipped ND-120 CONF_STR

The menu the core actually ships with (verbatim from `nd120.sv`, comments
trimmed — read the source for the full rationale on each line):

```verilog
localparam CONF_STR = {
    "ND120;;",
    "-;",
    "O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
    "-;",
    "O[6],Keyboard,US,Norwegian;",
    "O[7],Operator panel,On,Off;",         // default On
    "O[9:8],Console colour,Green,Amber,White,Cyan;",
    "-;",
    "S0,IMG,Floppy drive 0;",              // block dev, served by rtl/nd_storage_hps.v
    "S1,IMG,Floppy drive 1;",
    "S2,IMG,Winchester unit 0;",
    "S3,IMG,Winchester unit 1;",
    "S4,BPUTAP,Paper tape;",               // slot 4: TRS-80_MiSTer pattern
    "-;",
    "T[0],Reset;",
    "R[0],Reset and close OSD;",
    "v,0;",
    "V,v",`BUILD_DATE
};
```

Wiring notes:

- `status[0]` (T/R) OR the framework `RESET` input → MCL (Master Clear).
- `status[6]` → keyboard layout (US / Norwegian); `status[7]` → operator panel
  on/off (default on); `status[9:8]` → console text colour (a board-only re-tint
  of the console-text palette index, terminal RTL untouched).
- The five `S` slots are the storage mount points, served through hps_io's block
  interface by `rtl/nd_storage_hps.v` — the slot number is the hps_io index is the
  storage client (slot map in `rtl/nd_storage_mister_devices.v`). Extensions are
  3-character groups, so paper tape is `.BPU`/`.TAP`, not `.BPUN`.
- Microcode is NOT an F-entry here — it is uploaded from the HPS at core load; see
  [05-devices-block-char.md](05-devices-block-char.md) §3.
- The console is the machine's own TDV2200 screen + keyboard, not a `UART<speed>`
  bridge; the CPU serial line is also on the HPS `/dev/ttyS1` at 115200 7E1.

## 5. The status word, both directions

- `status[127:0]` — OSD selections → core.
- `status_in[127:0]` + `status_set` — core → OSD (e.g. reflect a mode the machine
  changed itself).
- `status_menumask[15:0]` — drives the `H/h/D/d` visibility rules.

## 6. When WOULD Linux-side code be needed?

Main_MiSTer has a `support/` directory of per-core helpers (x86/ao486 IDE, minimig,
CD-image formats like CHD/CUE, etc.), activated by core-name checks in
`user_io.cpp`. That exists only for cores needing host-side smarts — image-format
parsing or complex device config
(https://github.com/MiSTer-devel/Main_MiSTer/tree/master/support). A minicomputer
core with **raw disk images does not need any of it** — plain images are served by
the generic vhd path. If we ever want the Linux side to understand SINTRAN volume
formats or e.g. expose files as ND floppy images on the fly, THAT would be a
`support/nd120/` contribution to Main_MiSTer — strictly optional, much later.

## Menu checklist

- [ ] F12 shows the ND-120 menu with Reset, options, and the disc/tape mount slots.
- [ ] `status` bits reach the core (keyboard layout, panel on/off, console colour
      all take effect).
- [ ] Mounting a Winchester image in a slot lets `&` boot SINTRAN at the `#` prompt.
