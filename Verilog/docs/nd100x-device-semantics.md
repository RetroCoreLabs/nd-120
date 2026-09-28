# nd100x device semantics - reference for the Verilog device port

Extracted 11-JUL-2026 from the nd100x emulator (the nd100x repository).
This was the first semantics source for ND-BUS-DEVICES; the other
reference is Verilog/simDevices/NDDevices.cpp (the C models runSim boots
with). File/line references below are into nd100x as of that date.

Not every device follows nd100x any more: `ND_SMD.v` follows the RetroCore
C# model (`NDBusDiscControllerSMD.cs`) and its C port
`ND-BUS-DEVICES/portable/src/nd_smd.c` (see the `ND_SMD.v` header), and the
floppy status words follow the ND-11.021.01 manual
(`floppy-3112-register-spec-ND-11.021.md`).

## Interrupt mechanism (device levels 10-13)

Two layers:

- **Per-device pending mask** (`Device.interruptBits`, devices_types.h:134):
  each device holds its own 16-bit word, bits 10-13 used. Set via
  `Device_GenerateInterrupt` (device.c:255), cleared via
  `Device_ClearInterrupt` (device.c:240). Only levels 10-13 honored.
- **CPU PID/PIE**: every tick, `device_interrupt()` (cpu.c:384) copies
  the OR of all devices' masks into PID with mask 0xBC00 (bits
  10,11,12,13,15), clear-then-set. So PID levels 10-13 MIRROR the
  device flags each tick - level-sensitive, not edge-latched. A device
  dropping its flag clears PID without any IDENT.
- CPU takes the interrupt when `PIE & PID` has a higher level than the
  current PIL and the interrupt system is on (STS_IONI); `gCHKIT` must
  be set on every PID change or the level switch never happens.
- Level 14 (internal: IOX error etc.) is a separate IID/IIE/IIC
  mechanism. IOX to an unclaimed address raises level 14 sub-bit 7
  (IOX error) - devicemanager.c:290-334.

For the FPGA: BINT<level>_n = NOR of all device pending flags for that
level, continuously - this matches the PID-mirroring model.

## IDENT mechanism

- `IDENT PL<level>`: opcode operand low 6 bits = 004/011/022/043 for
  levels 10/11/12/13 (cpu_instr.c:3434). These same octal values appear
  as the bus ADDRESS during the OUTIDENT window (NDBus.cpp switch).
- Poll order = device REGISTRATION order, first pending device wins
  (devicemanager.c:336-357) = the daisy chain.
- A device answers ONLY if its pending bit for that exact level is set.
  Answering returns the ident code and AT THAT MOMENT clears BOTH:
  (a) the device's status-register interruptEnabled bit, and
  (b) the pending bit for that level.
  Because interruptEnabled is cleared, the device cannot re-raise until
  software re-enables via the control word.
- No pending device on the level -> A register gets 0 (the emulator's
  IOX-error-on-IDENT branch is dead code; DeviceManager_Ident returns
  0, never negative).
- Ident codes (octal) / levels / IOX bases:
  RTC 01 / 13 / 010-013; SMD 017 / 11 / 1540-1547 (tw1: 020, 1550);
  Floppy 021 / 11 / 1560-1567 (tw1: 022, 1570);
  papertape reader 02 / 12 / 400-403 (from NDDevices.cpp).

## Device framework

- Dispatch: linear scan over [startAddress,endAddress]; register index
  = address - startAddress; IOX address LSB: even = read, odd = write.
- Latency + completion interrupts via a delayed-IO queue: command
  handler queues a callback N ticks out (IODELAY_FLOPPY=300,
  IODELAY_HDD_SMD=10); the `...End` callback sets completion status
  bits and returns interruptEnabled - that return value gates
  Device_GenerateInterrupt. Interrupts fire at COMPLETION, not at
  command issue.

## Floppy PIO (deviceFloppyPIO.{h,c})

Base 1560 (tw0), ident 021, level 11. Registers (offset from base):
0 R read data buffer (word, auto-incr pointer), 1 W write data buffer,
2 R status reg 1, 3 W control word, 4 R status reg 2, 5 W drive
address/difference, 6 R test data, 7 W sector/test byte.

- RSR1: b1 intEnabled, b2 busy, b3 readyForTransfer, b4 OR-of-RSR2
  (computed on read as RSR2.raw>0), b5 deletedRecord, b6 rwComplete,
  b7 seekComplete, b8 timeout.
- RSR2: b8 driveNotReady, b9 writeProtect, b11 sectorMissing,
  b12 crcError, b14 dataOverrun.
- WCWD: b1 enableInterrupt, b2 autoload, b3 testMode, b4 deviceClear,
  b5 clearInterfaceBufferAddress, b6 enableTimeout; b8-15 = command
  one-hot (format,write,writeDeleted,readID,read,seek,recal,ctlReset).
  Command = HIGHEST set bit wins (decode loop overwrites).
- WDAD b0=1: drive = b8-10, deselect = b11, format = b14-15
  (0/1: 128 B x 26 sect; 2: 256 B x 15; 3: 512 B x 8).
  b0=0: seek difference = b8-14, direction = b15 (1 = in/higher),
  track clamped 0..76.
- WSCT: sector = b8-14 (1-based!), autoIncrement = b15 (not past end
  of track). In testMode: testByte = high byte.
- Buffer: 1024 words, wrap pointer; sector read fills it, CPU reads
  out word-by-word via offset 0.
- File position = (sector-1)*bps + track*bps*spt (single-sided math).
- Completion callbacks set busy=0 ready=1 rwComplete/seekComplete=1,
  auto-increment sector, raise level-11 interrupt if intEnabled.
- KNOWN HACKS in the models (do NOT blindly copy): RSR1 read
  fabricates bits 9/10/11 from bufferPointer bits ("for testprogram to
  succeed"); autoload memcpys a hardcoded 388-byte boot blob instead
  of reading track 0 sector 1. Ask Ronny per the standing rule before
  porting either hack.

## Floppy DMA (deviceFloppyDMA.{h,c}) - default-registered in nd100x

Same base/ident/level. Command block (12 words) in ND memory pointed
to by pointerHI/LO regs (offsets 5/7); RSR1 b15 dualDensity FORCED 1
so SINTRAN detects a DMA controller. Function codes 0x00 read, 0x01
write, 0x21 format, 0x38 identify, etc. Several functions are TODO
stubs; FLOPPY-STREAM C03 test fails. Known rough edge: 18-vs-8
sectors_pr_track inconsistency in the disk-address math.

## SMD (deviceSMD.{h,c})

Base 1540, ident 017, level 11. Pure DMA (core-address + word-count +
block-address registers in the controller). Most register offsets are
dual-function, multiplexed by control-word b15 (registerMultiplexBit,
mirrored in status b15). Operations b11-14: read/write transfer,
parity, compare, seek, format, RTZ, ECC, release. Completion after
IODELAY 10 ticks; standard IDENT pattern. Only device with a working
Boot (memory boot). Porting note: the C bit-field unions break under
-mms-bitfields if field types are mixed - keep uint16_t fields.
