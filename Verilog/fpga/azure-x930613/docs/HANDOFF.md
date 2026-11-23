# Azure card - handoff

Where the Azure card port stands, and what is needed to go on. Work stopped
here for two reasons, both outside the code: **there is no Quartus Prime
Standard licence**, and **the card is not installed in a PC yet**.

The living plan is [`00-plan.md`](00-plan.md); this page is the short way
back in.

## Done, and how to check it

Everything below runs without the card and without Quartus (WSL `Ubuntu`,
iverilog + Verilator):

| What | Check |
|---|---|
| PCIe console block, PC-served disk block, PCIe window split, PCIe wrapper (simulation version) | `make -C Verilog/fpga/azure-x930613/sim all` (also in `make test`) |
| The whole machine boots: MOPC's `#` arrives through the PCIe console and answers RETURN | `make -C Verilog/fpga/azure-x930613/sim vtest` (about 2 min, in `make test-full`) |
| Floppy boot from an image served by the simulated PC (`1560&`, program loaded at 0o2000 and run) | `make -C Verilog/fpga/azure-x930613/sim vtest-disk` (in `make test-full`) |
| 2 MB board in block RAM (derived 2 MB address decode, `ND120_ONBOARD_2MB`) | `make -C Verilog/PAL/sim test-44445b-d-2mb test-44446b-d-2mb` |
| Quartus project for the stand-in part `5SGSMD5K2F40I3L` | `nd120_azure.qpf` / `.qsf` / `.sdc`, file list `files.qip` (the Verilator tests read the same list) |
| Board in the module docs | `Verilog/HIERARCHY.md`, "Azure card X930613" |
| Card facts, each with its source | [`../README.md`](../README.md); prior work [`01-prior-work.md`](01-prior-work.md); DDR3 [`02-ddr3.md`](02-ddr3.md) |

Not run before stopping: the whole unit suite (`make test`) and
`make test-full` end to end. Only the tests the changes touched were run.

## Blocked on the licence

Quartus Prime Standard is needed for Stratix V and its licence is paid
(about USD 3,645, SW-ONE-QUARTUS). No free route was found - see
`00-plan.md` "Build" and the distributor enquiry draft there. With a
licence, in this order:

1. Generate the PCIe hard block as module `nd120_azure_pcie_ip`, with the
   port names `rtl/pcie_hip_wrap.v` expects (`bar0_*`). One x8 link is
   enough to start; the second needs the device-database patch described
   in `00-plan.md`.
2. Write the CPU clock PLL from the 125 MHz oscillator (pin M23) to
   20 MHz, replacing the `clk_cpu` top-level port.
3. First compile. Read the fit report for the real block-RAM use (planned
   about 1,024 of 2,014 M20K blocks for the 2 MB memory) and the timing.

## Blocked on the card

1. Install the card in a PC whose x16 slot can be split into two x8 links
   (bifurcation in the BIOS), or accept one x8 link.
2. Check the pins against the card before enabling any of them. The known
   ones are in `nd120_azure.qsf`, commented out; they come from a pin file
   shared with the sister card (Pikes Peak), and the 8 LEDs are not
   confirmed on this card.
3. Program over the on-board FT232H (USB-JTAG) - see `01-prior-work.md`,
   "Tools".
4. Write the PC program (plan step V6): map the PCIe window, connect the
   console to a telnet port, serve image files to the disk block. The
   simulated PC in `sim/pc_storage_model.v` shows the exact register
   sequence it must follow.

## Open, not tested anywhere yet

- Winchester, tape and any WRITE to an image on this top.
- A SINTRAN boot (needs a full SINTRAN image served by the PC).
- That the custom chip has the stand-in's block RAM (only the JTAG ID
  points to the same family member).
- The 4 GB DDR3 is not used; the route to it is in `02-ddr3.md`.
