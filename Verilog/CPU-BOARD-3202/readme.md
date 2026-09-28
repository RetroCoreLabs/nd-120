# Verilog code for CPU BOARD 3202D

## Verilog file per schematic sheet

`circuit/` holds one Verilog file per sheet. Testbenches are in `circuit/sim/`
(`<file>_tb.v`) or in a per-sheet folder (`circuit/<SHEET>/`); the ones that
check themselves are registered in `Verilog/tests/run_all_tests.sh`.

| Page name         |                       | Sheet | Area | Verilog | Notes |
|-------------------|-----------------------|-------|------|---------|-------|
| **Main PCB**      |                       |       |      |         |       |
| DELILAH TOP LEVEL | BLOCK DIAGRAM         | 1     | D3202 | [ND3202D.v](circuit/ND3202D.v) | [Test](circuit/ND3202D/readme.md) |
| DELILAH TOP LEVEL | A PLUG                | 2     | D3202 | | |
| DELILAH TOP LEVEL | B PLUG                | 3     | D3202 | | |
| DELILAH TOP LEVEL | C PLUG                | 4     | D3202 | | |
| **Bus interface** |                       |       |      |         |       |
| BIF               | BUS IF                | 5     | BIF  | [BIF_5.v](circuit/BIF_5.v) | |
| BIF/BCTL          | BIF CONTROL           | 6     | BIF  | [BIF_BCTL_6.v](circuit/BIF_BCTL_6.v) | |
| BIF/BCTL/BDRV     | BUS DRIVERS           | 7     | BIF  | [BIF_BCTL_BDRV_7.v](circuit/BIF_BCTL_BDRV_7.v) | |
| BIF/DPATH         | BIF SYNC              | 8     | BIF  | [BIF_BCTL_SYNC_8.v](circuit/BIF_BCTL_SYNC_8.v) | `sim/BIF_BCTL_SYNC_8_tb.v` |
| BIF DATA PATH     | BIF SYNC              | 9     | BIF  | [BIF_DPATH_9.v](circuit/BIF_DPATH_9.v) | |
| BIF/DPATH/BDLBD   | BIF BD TO LBD         | 10    | BIF  | [BIF_DPATH_BDLBD_10.v](circuit/BIF_DPATH_BDLBD_10.v) | `sim/BIF_DPATH_BDLBD_10_tb.v` |
| BIF/DPATH/CDLBD   | BIF CD TO LBD         | 11    | BIF  | [BIF_DPATH_CDLBD_11.v](circuit/BIF_DPATH_CDLBD_11.v) | `sim/BIF_DPATH_CDLBD_11_tb.v` |
| BIF/DPATH/LBCTL   | LBD CONTROL           | 12    | BIF  | [BIF_DPATH_LDBCTL_12.v](circuit/BIF_DPATH_LDBCTL_12.v) | `sim/BIF_DPATH_LDBCTL_12_tb.v` |
| BIF/DPATH/PESPEA  | BIF PES & PEA         | 13    | BIF  | [BIF_DPATH_PESPEA_13.v](circuit/BIF_DPATH_PESPEA_13.v) | `sim/BIF_DPATH_PESPEA_13_tb.v` |
| BIF/DPATH/PPNLBD  | BIF PPN to LBD        | 14    | BIF  | [BIF_DPATH_PPNLBD_14.v](circuit/BIF_DPATH_PPNLBD_14.v) | |
| **CPU**           |                       |       |      |         |       |
| CPU               | TOP LEVEL             | 15    | CPU  | [CPU_15.v](circuit/CPU_15.v) | [Test](circuit/CPU_15/readme.md) |
| CPU/CS            | CONTROL STORE         | 16    | CPU  | [CPU_CS_16.v](circuit/CPU_CS_16.v) | [Test](circuit/CPU_CS_16/readme.md) |
| CPU/CS/ACAL       | MICRO ADDR CALC       | 17    | CPU  | [CPU_CS_ACAL_17.v](circuit/CPU_CS_ACAL_17.v) | [Test](circuit/CPU_CS_ACAL_17/readme.md) |
| CPU/CS/CTL        | CS CONTROL            | 18    | CPU  | [CPU_CS_CTL_18.v](circuit/CPU_CS_CTL_18.v) | [Test](circuit/CPU_CS_CTL_18/readme.md) |
| CPU/CS/PROM       | CS PROMS              | 19    | CPU  | [CPU_CS_PROM_19.v](circuit/CPU_CS_PROM_19.v) | [Test](circuit/CPU_CS_PROM_19/readme.md). `CPU_CS_PROM_19_ORG.v` is the original Logisim-generated version. |
| CPU/CS/TCV        | CS TRANSCIEVERS       | 20    | CPU  | [CPU_CS_TCV_20.v](circuit/CPU_CS_TCV_20.v) | [Test](circuit/CPU_CS_TCV_20/readme.md) |
| CPU/CS/WCS        | WRITABLE CTRL STORE   | 21-22 | CPU  | [CPU_CS_WCS_21_22.v](circuit/CPU_CS_WCS_21_22.v) | [Test](circuit/CPU_CS_WCS_21_22/readme.md) |
| CPU/LAPA          | LA TO PPN BUFF        | 23    | CPU  | none | One line of code in `CPU_15.v` |
| CPU/MMU           | MMU TOP LEVEL         | 24    | CPU  | [CPU_MMU_24.v](circuit/CPU_MMU_24.v) | `sim/CPU_MMU_24_*_tb.v` |
| CPU/MMU/CACHE     | CACHE                 | 25    | CPU  | [CPU_MMU_CACHE_25.v](circuit/CPU_MMU_CACHE_25.v) | `sim/CPU_MMU_CACHE_25*_tb.v` |
| CPU/MMU/CSR       | CACHE STATUS REG      | 26    | CPU  | [CPU_MMU_CSR_26.v](circuit/CPU_MMU_CSR_26.v) | [Test](circuit/CPU_MMU_CSR_26/readme.md) |
| CPU/MMU/HIT       | HIT DETECTION         | 27    | CPU  | [CPU_MMU_HIT_27.v](circuit/CPU_MMU_HIT_27.v) | |
| CPU/MMU/PPNX      | PPN TO IDB            | 28    | CPU  | [CPU_MMU_PPNX_28.v](circuit/CPU_MMU_PPNX_28.v) | [Test](circuit/CPU_MMU_PPNX_28/readme.md) |
| CPU/MMU/PT        | PAGE TABLES           | 29    | CPU  | [CPU_MMU_PT_29.v](circuit/CPU_MMU_PT_29.v) | [Test](circuit/CPU_MMU_PT_29/readme.md), `sim/CPU_MMU_PT_29*_tb.v` |
| CPU/MMU/PTIDB     | PT TO IDB             | 30    | CPU  | [CPU_MMU_PTIDB_30.v](circuit/CPU_MMU_PTIDB_30.v) | [Test](circuit/CPU_MMU_PTIDB_30/readme.md) (2024 note, not re-checked: bidirectional bus not working correctly in Verilator) |
| CPU/MMU/WCA       | PPN TO CPN            | 31    | CPU  | [CPU_MMU_WCA_31.v](circuit/CPU_MMU_WCA_31.v) | [Test](circuit/CPU_MMU_WCA_31/readme.md) |
| CPU/PROC          | PROCESSOR TOP LEVEL   | 32    | CPU  | [CPU_PROC_32.v](circuit/CPU_PROC_32.v) | [Test](circuit/CPU_PROC_32/readme.md) |
| CPU/PROC/CGA      | CPU GATE ARRAY        | 33    | CPU  | [CPU_PROC_CGA_33.v](circuit/CPU_PROC_CGA_33.v) | [Test](circuit/CPU_PROC_CGA_33/readme.md) |
| CPU/PROC/CMDDEC   | COMMANDS & IDB DECODE | 34    | CPU  | [CPU_PROC_CMDDEC_34.v](circuit/CPU_PROC_CMDDEC_34.v) | [Test](circuit/CPU_PROC_CMDDEC_34/readme.md) |
| CPU/STOC          | IDB TO CD             | 35    | CPU  | [CPU_STOC_35.v](circuit/CPU_STOC_35.v) | Not used by the board: `CPU_15.v` does it in one line. The file and `sim/CPU_STOC_35_tb.v` remain. |
| **Cycle control** |                       |       |      |         |       |
| CYC               | CYCLE CONTROL         | 36    | CYC  | [CYC_36.v](circuit/CYC_36.v) | [Test](circuit/CYC_36/readme.md). `CYC_CC_D.v` and `CYC_TERM_D.v` copy the next-state logic of PAL_44601B so CYC_36 can make sysclk clock enables. |
| **IO**            |                       |       |      |         |       |
| IO                | IO TOP LEVEL          | 37    | IO   | [IO_37.v](circuit/IO_37.v) | [Test](circuit/IO_37/readme.md) |
| IO/DCD            | IO DECODING           | 38    | IO   | [IO_DCD_38.v](circuit/IO_DCD_38.v) | [Test](circuit/IO_DCD_38/readme.md). Connects the DGA. |
| IO/DCD/DGA        | DECODE GATE ARRAY     | 39    | IO   | none | Directly integrated in sheet 38. |
| IO/PANCAL         | PANEL PROC & CALENDAR | 40    | IO   | [IO_PANCAL_40.v](circuit/IO_PANCAL_40.v) | `sim/IO_PANCAL_40*_tb.v`. `PANCAL_68705_CLOCK.v` stands in for the MC68705U3 + MM58274 clock path (`Verilog/docs/panel-clock-68705.md`). |
| IO/REG            | IOC, ALD & INR REGS   | 41    | IO   | [IO_REG_41.v](circuit/IO_REG_41.v) | [Test](circuit/IO_REG_41/readme.md) |
| IO/UART           | UART AND IOR REG      | 42    | IO   | [IO_UART_42.v](circuit/IO_UART_42.v) | [Test](circuit/IO_UART_42/readme.md) |
| **Memory**        |                       |       |      |         |       |
| MEM               | MEMORY TOP LEVEL      | 43    | MEM  | [MEM_43.v](circuit/MEM_43.v) | `sim/MEM_CHAIN*_tb.v` |
| MEM/ADDR          | MEM ADDR MUX          | 44    | MEM  | [MEM_ADDR_44.v](circuit/MEM_ADDR_44.v) | `sim/MEM_ADDR_44_tb.v` |
| MEM/ADEC          | ADDRESS DECODER       | 45    | MEM  | [MEM_ADEC_45.v](circuit/MEM_ADEC_45.v) | `sim/MEM_ADEC_45_tb.v` |
| MEM/DATA          | DATA & PARITY TCV     | 46    | MEM  | [MEM_DATA_46.v](circuit/MEM_DATA_46.v) | `sim/MEM_DATA_46_tb.v` |
| MEM/ERROR         | LOCAL PES & PEA       | 47    | MEM  | [MEM_ERROR_47.v](circuit/MEM_ERROR_47.v) | `sim/MEM_ERROR_47_tb.v` |
| MEM/LBDIF         | LOCAL BD CONTROL      | 48    | MEM  | [MEM_LBDIF_48.v](circuit/MEM_LBDIF_48.v) | `sim/MEM_LBDIF_48_tb.v` |
| MEM/RAM           | LOCAL RAM             | 49    | MEM  | [MEM_RAM_49.v](circuit/MEM_RAM_49.v) | Back ends: `MEM_RAM_49_SIM.v` (Verilator), `MEM_RAM_49_BLOCKRAM.v` (FPGA block RAM). `sim/MEM_RAM_49_*_tb.v` |
| MEM/RAMC          | LOCAL RAM CONTROL     | 50    | MEM  | [MEM_RAMC_50.v](circuit/MEM_RAMC_50.v) | `sim/MEM_RAMC_50_tb.v` |

`PAL_44445B_D.v` and `PAL_44446B_D.v` are sysclk-domain copies of the PALs
44445B (UCADEC) and 44446B (UBADEC): same equations, registers sampled on
sysclk with an enable instead of the original clock net.

# Test program verification

![Screenshot from GTKWave](gtkwave.png)
