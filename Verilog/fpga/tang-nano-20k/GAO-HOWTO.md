# GAO (Gowin Analyzer Oscilloscope) capture on the Tang Nano 20K

Date: 17-JUL-2026. Written for the S1 experiment from
Verilog/docs/tang-masked-grant-audit.md (deleted 28-SEP-2026, in git history) - capture the CGA_INTR grant chain
(int_req_q, INTRQN, PICV, mask/request bit 10, CSA) around a spurious
PIL 0 -> 10 grant. **That fault was solved 18-JUL-2026 (see
`ANALYSIS-cga-intr-masked-grant-root-cause.md`).** The GAO mechanics below
(build hook, cable handover, launching the analyzer, troubleshooting) are
general; the signal list and trigger are what `src/nd120_tang20k_gao.rao`
holds today - change the .rao for a different question. The campaign-only
"what decides S1" reading guide was cut 28-SEP-2026 (git history keeps it).

Every claim in this document is tagged VERIFIED (read from the named
Gowin document / repo file / synthesized netlist) or INFERRED (labelled).
Sources with URLs are at the end.

---

## 1. What was built

- GAO config file (RTL-mode, Standard):
  Verilog/fpga/tang-nano-20k/src/nd120_tang20k_gao.rao
- Build hook (opt-in flag file, same mechanism as the clock variant):
  Verilog/fpga/tang-nano-20k/gowin_build.tcl
  (adds `add_file -type gao src/nd120_tang20k_gao.rao` when
  build/gao_enable.flag exists)
  Verilog/fpga/tang-nano-20k/gowin_build.ps1
  (new `-Gao` switch writes/removes the flag; a build WITHOUT -Gao is
  always GAO-free)
- Inert keep-pragmas (`/* synthesis syn_keep=1 */`, a trailing comment
  that Verilator, iverilog and yosys all ignore - verified by compiling a
  test module with all three) on every probed net, so Gowin synthesis
  cannot optimize them away before the AO core taps them:
  - Verilog/DELILAH-CPU/CGA_INTR/circuit/CGA_INTR_CNTLR_IRGEL_HIRL.v (s_int_req_q, s_int_req_qn, s_hidis_n)
  - Verilog/DELILAH-CPU/CGA_INTR/circuit/CGA_INTR_CNTLR_IRGEL_LORL.v (s_int_req_enable_q)
  - Verilog/DELILAH-CPU/CGA_INTR/circuit/CGA_INTR_CNTLR_IRGEL.v (s_hve, s_lve)
  - Verilog/DELILAH-CPU/CGA_INTR/circuit/CGA_INTR.v (s_intrq_n, s_picv_2_0_out, s_ireq_15_0_n, s_mclk)
  - Verilog/DELILAH-CPU/CGA_INTR/circuit/CGA_INTR_CNTLR_IRQ.v (s_lreq_15_0, s_picmask_15_0_n_out)
  - Verilog/fpga/tang-nano-20k/src/ND120_TANG20K_TOP.v (CSA_12_0)

Why RTL mode (.rao) and not post-synthesis (.gao): the synthesized
netlist on disk
(Verilog/fpga/tang-nano-20k/build/nd120_tang20k_build/impl/gwsynthesis/nd120_tang20k_build.vg)
was inspected directly: deep module boundaries are restructured and most
of the wanted nets are renamed to synthetic `n7_*` style names
(s_int_req_qn, HVE, INTRQN etc. do not survive under their RTL names).
Post-synthesis signal selection would therefore break on every rebuild.
RTL-mode GAO selects the signals BEFORE synthesis, where every name is
stable - VERIFIED against the RTL sources listed above. No debug-bus
port plumbing through the 10-level hierarchy is needed.

## 2. What is captured (28 bits, clk_cpu domain)

Hierarchy prefix (instance names VERIFIED in the RTL):
`CORE/CPU_BOARD/CPU/PROC/CGA/DELILAH/INTR`

| Signal (path under the prefix)                | Meaning |
|-----------------------------------------------|---------|
| `CSA_12_0[12:0]` (top level, no prefix)       | microcode Control Store Address - which microinstruction is executing |
| `s_mclk`                                      | MCLK, the microcycle clock (level signal in FF mode) |
| `s_intrq_n`                                   | INTRQN - interrupt request to the microcode, LOW = grant pending (also fires on every panel/RTC event) |
| `s_picv_2_0_out[2:0]`                         | PICV - the 3-bit vector the CPU reads at RDVECT (level 10 = high chip, vector 2 = binary 010) |
| `CNTLR/IRGEL/HIRL/s_int_req_q`                | THE key signal: Am2914 high-chip interrupt-request-enable FF (ND PIC ION/IOF state). Should be 0 after the IOF at 000261 |
| `CNTLR/IRGEL/HIRL/s_int_req_qn`               | its inverse (sanity check that the FF pair is consistent) |
| `CNTLR/IRGEL/HIRL/s_hidis_n`                  | high-chip status-overflow disable FF (1 = chip enabled) |
| `CNTLR/IRGEL/LORL/s_int_req_enable_q`         | low-chip twin of int_req_q (note: different net name in LORL) |
| `CNTLR/IRGEL/s_hve`                           | HVE - high-chip vector claim (this steers PICV) |
| `CNTLR/IRGEL/s_lve`                           | LVE - low-chip vector claim |
| `s_ireq_15_0_n[10]`                           | request source bit 10, active low (PID-write path OR IOXERR - they share this bit) |
| `s_ireq_15_0_n[12]`                           | request source bit 12 (level-12 storm context from the tape/SD device) |
| `CNTLR/IRQ/s_lreq_15_0[10]`                   | latched request bit 10 (RQBIT output - the pending bit) |
| `CNTLR/IRQ/s_picmask_15_0_n_out[10]`          | mask FF Q for level 10: 1 = level ENABLED in the Am2914 mask (the S2 window is open), 0 = masked |

All of these net and instance names were VERIFIED by reading the RTL
files listed in section 1 (they are declared wires in those modules).

## 3. Trigger choice (documented decision)

Trigger = **M0: rising edge of HVE while PICV == 2** (match value
`R010` over the 4-bit trigger port {s_hve, s_picv[2], s_picv[1],
s_picv[0]}). That is the high-chip claim of vector 2 = the level-10
grant itself - exactly the fatal event, and nothing else:

- Plain "falling edge of INTRQN" (the task's first suggestion) is wired
  as match unit M1 but NOT used in the trigger expression, because
  INTRQN also asserts on every panel/RTC/console event (audit section
  1e: PANN reaches INTRQN with no mask term), so it would trigger on the
  first console keystroke instead of the bug.
- "PIL changes" is not directly triggerable: PIL is microcode-held state
  (register file), not a discrete RTL net in the grant chain.
- Normal RTC/panel dispatches claim vector 5 (level 13), and the
  tape/SD storm pends level 12 (vector 4) - neither matches `010`, so
  the first trigger IS the spurious level-10 claim.

Trigger position 512 of 1024: 512 samples of pre-trigger history (the
IOF decode, MCLK phases, int_req_q state leading in) and 512 samples of
post-trigger dispatch (CSA microcode addresses).

To retrigger on INTRQN falling instead: edit
Verilog/fpga/tang-nano-20k/src/nd120_tang20k_gao.rao
and change `<Expression>M0</Expression>` to `<Expression>M1</Expression>`
(or `M0|M1` for either), then rebuild. Expression syntax `M0&M1`,
`!M4&(M3|M6)` etc. is VERIFIED from SUG114. The expression is Static, so
changing it requires a rebuild; Dynamic expressions exist but cost extra
BSRAM we do not have (SUG114 shows a Dynamic expression consuming 2
BSRAM) - with Static, match VALUES can still not be edited at runtime,
so plan trigger changes via the .rao.

## 4. Resource budget (why the window is 1024 samples, not 4096)

On 17-JUL-2026 the GAO-free Gowin EDA build used 43 of 46 BSRAM blocks (94%,
SP 34 + SDPB 9 - VERIFIED in
Verilog/fpga/tang-nano-20k/build/nd120_tang20k_build/impl/pnr/nd120_tang20k_build.rpt.txt).
Only 3 blocks were free. (The storage build measured 3-AUG-2026 is at
96% - re-read the current `.rpt` before sizing a capture.)

- 28 capture bits x 1024 depth fits in 2 BSRAM (1Kx18 mode x2 = 36
  bits) - leaves 1 block spare. (BSRAM mode geometry is standard GW2A;
  the exact packing by GAO is INFERRED.)
- 2048 depth would need 2Kx9-mode blocks: ceil(28/9) = 4 blocks - MORE
  than the 3 free. That is why storage_depth=1024.
- If PnR still fails on BSRAM: delete the `s_ireq_15_0_n[12]` and
  `s_int_req_qn` signals and/or drop storage_depth/capture_amount to
  512 in the .rao.
- Logic is at 58% in this flow (the 88% LUT figure is the OSS
  yosys/nextpnr flow, not Gowin EDA), so the AO core's control logic is
  not a concern.

## 5. Build (Windows host)

    cd Verilog/fpga/tang-nano-20k
    .\gowin_build.ps1 -Variant full -Gao

Pick the variant the fault shows on (`-Variant full` was used for the
17-JUL capture). `-Gao` writes build\gao_enable.flag; gowin_build.tcl then
adds the .rao. A later build WITHOUT `-Gao` removes the flag - no sticky
state.

Verify GAO really got inserted before flashing:

1. The gw_sh console printed `GAO ENABLED: src/nd120_tang20k_gao.rao`.
2. The PnR report
   Verilog/fpga/tang-nano-20k/build/nd120_tang20k_build/impl/pnr/nd120_tang20k_build.rpt.txt
   shows BSRAM ABOVE the GAO-free 43 (expect 45), and (per SUG100) the
   report includes GAO place/route time and a GAO Resource section when
   a GAO is in the project.
3. If the log complains about a signal name it cannot find, see
   Troubleshooting below.
4. The usual WCS gate still applies: no EX3988 in the synthesis log.

## 6. JTAG cable reality check (read BEFORE the capture session)

- The board's USB is a BL616 MCU running Sipeed firmware that emulates
  an FTDI FT2232 composite device (JTAG channel + UART channel, VID:PID
  0403:6010 - same IDs the Basys3 FTDI shows). openFPGALoader in WSL
  drives it via the usbipd attachment.
- The Gowin Analyzer Oscilloscope reaches the board through the Gowin
  cable stack. Its cable options are: Gowin USB Cable (GWU2X), Gowin USB
  Cable (FT2CH), Gowin USB Cable (WINUSB), Parallel Port (VERIFIED,
  SUG114). **Select "Gowin USB Cable (FT2CH)"** - that is the
  FTDI-2232-protocol option.
- That the BL616's FT2232 emulation is good enough for the Gowin
  programmer/GAO is INFERRED from the FTDI emulation + community usage
  of Gowin IDE with Sipeed Tang boards; it is NOT verified on this
  board here. If the cable scan finds nothing on FT2CH:
  1. check the USB attachment (next section),
  2. try the WINUSB option,
  3. worst case the Gowin tools need a real FTDI/Gowin dongle on the
     board's external JTAG pins - report back and we wire that.

### usbipd handover (the single most likely stumbling block)

GAO runs on WINDOWS, so the board must NOT be attached to WSL during
capture. In an admin PowerShell:

    usbipd list                     # find the Sipeed/FTDI device (task notes busid 2-3;
                                    # earlier sessions saw 3-3 - trust `usbipd list`, not memory)
    usbipd detach --busid <busid>   # give it back to Windows

After the session, to return to the WSL flow:

    usbipd attach --wsl --busid <busid>

(and in WSL, the usual workflow -
Verilog/fpga/tang-nano-20k/usb-attach.sh, or `make usb`.)

Console note: while the board is on Windows, the OPCOM console (115200
7E1 since 27-AUG-2026; 9600 before) is the OTHER channel of the same USB device - use a Windows
terminal (PuTTY / TeraTerm) on the COM port that appears, NOT the WSL
picocom. JTAG and UART are separate channels of the FT2232 emulation, so
GAO capture and the console can run at the same time (INFERRED - the
channels are independent in a real FT2232; verify on first session).

### Launching the tools (VERIFIED 17-JUL-2026 on this board)

Executables live in the Gowin EDA install's `IDE\bin\` folder:
`gao_analyzer.exe` (the logic analyzer), `gvio_analyzer.exe`. The
Programmer is separate: `Programmer\bin\programmer.exe` in the same install.

Launch the analyzer with NO command-line device args - passing
`-series/-device/-gao/-fs` on the command line produced a
**"Can not set device"** dialog on this install. Start it bare and open
the `.rao` from the GUI (File -> Open ->
`Verilog/fpga/tang-nano-20k/src/nd120_tang20k_gao.rao`):

    Start-Process '<Gowin install>\IDE\bin\gao_analyzer.exe'

(From WSL, prefix with `powershell.exe -Command "..."`.)

### The cable / "Can not set device" resolution (VERIFIED)

"Can not set device" here was NOT a wrong device name - it is the tool
not being pointed at a JTAG cable PORT. Confirm and select the cable via
the **Programmer** first (it shares the cable stack), then use the SAME
port in the analyzer:

- Open the Programmer -> its cable dialog reports, on this board:
    Cable found: Gowin USB Cable(FT2CH)/0/4913/null   (USB location 4913)
    Cable found: Gowin USB Cable(FT2CH)/1/4914/null   (USB location 4914)
  Series GW2AR, Device **GW2AR-18C**, IDCODE reads back - so the FT2232
  emulation IS good enough (this retires the "might need a real dongle"
  worry from section 6 for THIS board).
- **Two ports**: `/0/4913` = channel 0 = the JTAG interface the analyzer
  wants (4914 is the other FT2232 channel). Frequency 0.5 MHz is fine.
- **DO NOT press Program in the Programmer.** Its default FS File may
  point at a STALE bitstream (seen: `...\ND-120-Gowin\...`, NOT our
  tang-nano-20k build) - programming it would overwrite the running GAO
  bitstream. The Programmer is only used here to confirm/Save the cable;
  the board is already flashed (openFPGALoader `make load-gowin`, or the
  Programmer pointed at the CORRECT
  `...\build\nd120_tang20k_build\impl\pnr\nd120_tang20k_build.fs`).
- In the **Analyzer**, choose the same cable "Gowin USB Cable(FT2CH)",
  port `.../0/4913`. It then connects to the GAO core in the running SRAM
  bitstream. (If a driver-layer failure appears instead - the tool cannot
  see any cable while the COM terminal works - Windows has only the FTDI
  VCP driver bound; install the FTDI CDM combined driver (D2XX+VCP),
  replug once, retry. Not needed on this board as of 17-JUL.)

## 7. Capture session, step by step

1. Build with `-Gao` (section 5) and note the bitstream:
   Verilog/fpga/tang-nano-20k/build/nd120_tang20k_build/impl/pnr/nd120_tang20k_build.fs
2. Hand the USB device to Windows (section 6).
3. Start the analyzer. Two equivalent ways (VERIFIED in SUG114):
   - Gowin IDE: open the project-less IDE
     (`<Gowin install>\IDE\bin\gw_ide.exe`), menu
     Tools -> Gowin Analyzer Oscilloscope, then toolbar Open and select
     Verilog/fpga/tang-nano-20k/src/nd120_tang20k_gao.rao
   - Standalone exe:
     <Gowin install>\IDE\bin\gao_analyzer.exe
       -series GW2AR -device GW2AR-18C
       -gao Verilog/fpga/tang-nano-20k/src/nd120_tang20k_gao.rao
       -fs Verilog/fpga/tang-nano-20k/build/nd120_tang20k_build/impl/pnr/nd120_tang20k_build.fs
     (-series and -device are mandatory, -gao and -fs optional -
     VERIFIED argument list from SUG114; the exact -series/-device
     strings for this part are INFERRED from the SUG114 example format
     "GW1N-4D = type + version". Our part is GW2AR-18C, device version
     C.)
4. Cable: select Gowin USB Cable (FT2CH); use the scan button so the
   location/SN fills in.
5. Program the FPGA with the GAO bitstream (the analyzer's built-in
   GAO-Programmer with the -fs file, or the Gowin Programmer GUI). A
   bitstream loaded by openFPGALoader from WSL contains the same AO core
   and should also be capturable afterwards (INFERRED - GAO only needs
   JTAG access to the AO core plus a matching GAO_ID between .rao and
   bitstream; the ID is embedded in both).
6. ARM BEFORE REPRODUCING: click Start (F1) = one-shot capture. The
   analyzer waits for the trigger.
7. Reproduce the fault on the Windows COM console. The trigger fires and
   the waveform view fills with 512 pre / 512 post samples.
   - If nothing triggers, click Force Trigger (F3) to grab a window
     anyway and look at the state, and consider the M1 (INTRQN)
     expression for the next build.
8. Export: toolbar Export -> format CSV (also VCD if wanted - GTKWave
   reads it with the existing tooling). Default export dir is
   impl/wave under the project, i.e.
   Verilog/fpga/tang-nano-20k/build/nd120_tang20k_build/impl/wave
   - copy the file into
   Verilog/fpga/tang-nano-20k/ and note
   the bitstream it came from.

## 8. Automation notes

- Bitstream flashing can be scripted with
  `<Gowin install>\Programmer\bin\programmer_cli.exe`
  (path INFERRED from the standard install layout; adjust to the local
  install). openFPGALoader from WSL works as today when the device is
  attached to WSL.
- The CAPTURE itself (arm/trigger/export) has no documented CLI:
  SUG114 documents only the gao_analyzer GUI (its command line only
  selects files/device at launch). Treat capture as an interactive
  step. A remote-capture option exists via `jtagserver` (SUG502
  section 3.14) if driving the GUI from another machine ever matters.

## 9. Troubleshooting

- "signal not found" style error at build or when the analyzer loads
  the config: open the .rao in the Gowin IDE GAO editor (add it to the
  GUI project as a GAO config file - .rao files are referenced in
  .gprj as `type="file.gao"`, VERIFIED in the nestang reference
  project - or double-click it), use the Search Nets dialog to re-pick
  the signal, save. Names were verified against today's RTL; a future
  rename in CGA_INTR will break the config loudly, not silently.
- Match-type dropdown: the .rao sets match_type="1" intending "Basic
  w/edges" (needed for the R and F edge values). The numeric encoding
  of that enum is INFERRED from the documented dropdown order (Basic,
  Basic w/edges, Extended, Extended w/edges, Range, Range w/edges); if
  the tool rejects the value or shows the wrong type, set Match Type to
  "Basic w/edges" in the Match Unit dialog and re-save - the R/F/B/N
  edge characters and the value syntax are VERIFIED from SUG114
  Table 3-1.
- PnR fails on BSRAM: section 4 fallback (drop signals or halve the
  depth).
- Trigger fires instantly/constantly: something else is claiming vector
  2 - that is itself a finding; export and look at LREQ/IREQ bits.
- Sample clock: clk_cpu equals the domain of every probed signal
  (SUG114 recommends expression + data in the sample clock domain -
  satisfied). MCLK is captured as DATA, it is not the sample clock.

## 10. VERIFIED vs INFERRED summary

VERIFIED (from the named source):
- .rao/.gao XML schema, Standard mode, hierarchical `/` signal paths,
  Trigger/MatchUnit/Expression structure: real-world configs
  src/nes.gao and src/nestang_console60k.rao from the nestang project,
  plus SUG114.
- Edge trigger values R/F/B/N, match types and expression syntax
  (M0&M1 etc.), storage sizes, trigger position semantics, segments,
  Capture Initial Data, Force Trigger by Falling Edge: SUG114-3.4.4E.
- `add_file -type gao <file>.rao` in a gw_sh Tcl script: SUG1220
  (add_file supports type gao) + two real gw_sh build scripts (pctang
  build.tcl, MSXgoauld_tn20k fpga/build.tcl).
- Analyzer usage: Tools menu / gao_analyzer.exe and its arguments,
  cable list incl. FT2CH, Start/AutoRun/ForceTrigger/Stop = F1-F4,
  Export CSV/VCD/PRN/GWD and default impl/wave path, jtagserver:
  SUG114-3.4.4E; GAO time/resource lines in reports: SUG100-4.4.6E.
- All probed net names and the CORE/CPU_BOARD/CPU/PROC/CGA/DELILAH/
  INTR/CNTLR/IRGEL/HIRL instance path: read from this repo's RTL.
- Post-synthesis netlist name-crushing (why RTL mode): read from
  build/nd120_tang20k_build/impl/gwsynthesis/nd120_tang20k_build.vg.
- BSRAM 43/46 headroom: build/.../impl/pnr/nd120_tang20k_build.rpt.txt.
- syn_keep comment pragma inert for Verilator/iverilog/yosys: compiled
  a probe module with all three locally. The "signals optimized away
  unless syn_keep" hazard itself: nand2mario's Tang tips page.
- Dynamic trigger expressions can consume BSRAM (2 in the SUG114
  example): SUG114.

INFERRED (labelled in the text above):
- match_type numeric encoding 1 = "Basic w/edges" (dropdown order).
- BL616 FT2232 emulation works with the Gowin FT2CH cable driver.
- JTAG + UART channels usable concurrently on the emulated FT2232.
- Exact -series/-device strings for gao_analyzer.exe on GW2AR-18C.
- GAO capture works on a bitstream loaded by openFPGALoader (GAO_ID
  match is the requirement).
- programmer_cli.exe install path.
- GAO BSRAM packing geometry (1Kx18 assumption for the depth math).

## 11. Sources

- SUG114-3.4.4E, Gowin Analyzer Oscilloscope User Guide:
  https://cdn.gowinsemi.com.cn/SUG114E.pdf
- SUG100-4.4.6E, Gowin Software User Guide:
  https://cdn.gowinsemi.com.cn/SUG100E.pdf
- SUG1220-2.0E, Gowin Software Tcl Commands User Guide:
  https://cdn.gowinsemi.com.cn/SUG1220E.pdf
- SUG502, Gowin Programmer User Guide (jtagserver, programmer_cli):
  referenced by SUG114; https://cdn.gowinsemi.com.cn/SUG502E.pdf
- Real-world GAO configs (schema ground truth):
  https://github.com/nand2mario/nestang (src/nes.gao,
  src/nestang_console60k.rao, nestang_console60k.gprj)
- gw_sh scripts adding .rao files:
  https://github.com/nand2mario/pctang (build.tcl),
  https://github.com/jabadiagm/MSXgoauld_tn20k (fpga/build.tcl)
- Tang/Gowin practical tips (syn_keep gotcha, GAO trigger-value note):
  https://nand2mario.github.io/posts/2024/tang_tips/
