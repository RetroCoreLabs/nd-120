-------------------------------------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework  
--
-- Clock Generator using the Xilinx specific MMCME2_ADV:
--
--   ND-120: ONE MMCM makes the machine's four clocks, because
--   the SDRAM bridge (fpga/tang-nano-20k/sdram-bridge/sdram18.v) samples
--   the CPU's RAS/CAS as synchronous signals, which is only true when its
--   2x clock comes from the SAME PLL as the CPU clock (MiSTer pll_cpu.v).
--   100 MHz x 8 = 800 MHz VCO (Artix-7 -2 range 600..1440 MHz):
--     CLKOUT0 /31.75     25.197 MHz  pix_clk:  the console's pixel clock,
--                                    640x480@60 (VESA 25.175 MHz, -0.09%).
--                                    CLKOUT0 is the MMCM's only fractional
--                                    divider, so the pixel clock lives here.
--     CLKOUT1 /G_CPU_DIV 20.000 MHz  cpu_clk:  the ND-120 CPU board (/40);
--                        13.333 MHz  on R3 (/60). BOARD_CLK_FREQ in build.tcl
--                                    must agree.
--     CLKOUT2 /20 @180   40.000 MHz  sdram_clk: the SDRAM chip's clock pin
--                                    (R4/R5/R6 builds; unused on R3)
--     CLKOUT3 /20        40.000 MHz  main_clk  = clk_2x: the SDRAM bridge
--                                    clock and the framework's own logic
--                                    (keyboard scan, OSD). The whole console
--                                    - terminal, keyboard decoder, UART
--                                    bridge - runs on pix_clk.
--
--   WHY THE PIXEL CLOCK IS NOT THE 40 MHz MAIN CLOCK. The framework's HDMI
--   path stores every pixel in the board's HyperRAM through the ascal
--   rescaler, and that one 8-bit 100 MHz chip (~75 clocks per 128-byte
--   burst, hyperram_ctrl.vhd) also serves the read-back for the HDMI mode.
--   The rescaler's input buffer is 2 x 128 bytes with NO back-pressure
--   (ascal.vhd i_dpram, write queue depth 1+1): a half must be drained within
--   ~151 clocks - its own burst plus one read burst already in flight - or
--   the input overwrites it and that chunk is lost. At 40 Mpx/s x 24 bpp a
--   half filled every 107 clocks, so chunks were lost whenever the output
--   side was reading: the torn, colour-rotated picture the R6 tester filmed
--   in 720p, and the red flecks in 480p. At 25.2 Mpx/s x 16 bpp (the pixel
--   format is set in framework-overrides/digital_pipeline.vhd) a half fills
--   every 254 clocks and the chip runs at ~45% in 720p60. The other M2M cores
--   feed the rescaler 7.9 Mpx/s (C64) and 14.3 Mpx/s (Apple II); 40 Mpx/s was
--   2.8x anything it had been used with. The budget table is in
--   docs/00-plan.md ("Video data rate and the HyperRAM budget").
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
-------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

entity clk is
   generic (
      -- CLKOUT1 divider from the 800 MHz VCO: 40 -> 20.000 MHz (R4/R5/R6),
      -- 60 -> 13.333 MHz (R3, whose IDB-ring timing artefact needs the
      -- longer period - build.tcl and mega65.vhd). Keep it a divisor of the
      -- CLKOUT0 (40 MHz) period's multiple so the two stay edge-related.
      G_CPU_DIV : natural := 40
   );
   port (
      sys_clk_i       : in  std_logic;   -- expects 100 MHz

      main_clk_o      : out std_logic;   -- 40.000 MHz - SDRAM bridge clock, the framework's keyboard scan
      main_rst_o      : out std_logic;   -- main's reset, synchronized
      cpu_clk_o       : out std_logic;   -- 20.000 MHz - the ND-120 CPU
      sdram_clk_o     : out std_logic;   -- 40.000 MHz, 180 degrees - the SDRAM chip
      pix_clk_o       : out std_logic;   -- 25.197 MHz - the console's clock: pixels (640x480@60), keyboard decoder, UART bridge
      pix_rst_o       : out std_logic    -- pix_clk's reset, synchronized
   );
end entity clk;

architecture rtl of clk is

signal clkfb1             : std_logic;
signal clkfb1_mmcm        : std_logic;
signal clkfb2             : std_logic;
signal clkfb2_mmcm        : std_logic;
signal clkfb3             : std_logic;
signal clkfb3_mmcm        : std_logic;
signal main_clk_mmcm      : std_logic;
signal cpu_clk_mmcm       : std_logic;
signal sdram_clk_mmcm     : std_logic;
signal pix_clk_mmcm       : std_logic;

signal main_locked        : std_logic;

begin

   -------------------------------------------------------------------------------------
   -- Generate the machine's clocks: pixel, CPU, SDRAM chip, main
   -------------------------------------------------------------------------------------

   i_clk_main : MMCME2_ADV
      generic map (
         BANDWIDTH            => "OPTIMIZED",
         CLKOUT4_CASCADE      => FALSE,
         COMPENSATION         => "ZHOLD",
         STARTUP_WAIT         => FALSE,
         CLKIN1_PERIOD        => 10.0,       -- INPUT @ 100 MHz
         REF_JITTER1          => 0.010,
         DIVCLK_DIVIDE        => 1,
         CLKFBOUT_MULT_F      => 8.000,      -- 800 MHz
         CLKFBOUT_PHASE       => 0.000,
         CLKFBOUT_USE_FINE_PS => FALSE,
         CLKOUT0_DIVIDE_F     => 31.750,     -- 25.197 MHz, the pixel clock (fractional: 800/31.75)
         CLKOUT0_PHASE        => 0.000,
         CLKOUT0_DUTY_CYCLE   => 0.500,
         CLKOUT0_USE_FINE_PS  => FALSE,
         CLKOUT1_DIVIDE       => G_CPU_DIV,  -- 20.000 MHz (40) or 13.333 MHz (60)
         CLKOUT1_PHASE        => 0.000,
         CLKOUT1_DUTY_CYCLE   => 0.500,
         CLKOUT1_USE_FINE_PS  => FALSE,
         CLKOUT2_DIVIDE       => 20,         -- 40.000 MHz, 180 degrees
         CLKOUT2_PHASE        => 180.000,
         CLKOUT2_DUTY_CYCLE   => 0.500,
         CLKOUT2_USE_FINE_PS  => FALSE,
         CLKOUT3_DIVIDE       => 20,         -- 40.000 MHz, main_clk
         CLKOUT3_PHASE        => 0.000,
         CLKOUT3_DUTY_CYCLE   => 0.500,
         CLKOUT3_USE_FINE_PS  => FALSE
      )
      port map (
         -- Output clocks
         CLKFBOUT            => clkfb3_mmcm,
         CLKOUT0             => pix_clk_mmcm,
         CLKOUT1             => cpu_clk_mmcm,
         CLKOUT2             => sdram_clk_mmcm,
         CLKOUT3             => main_clk_mmcm,
         -- Input clock control
         CLKFBIN             => clkfb3,
         CLKIN1              => sys_clk_i,
         CLKIN2              => '0',
         -- Tied to always select the primary input clock
         CLKINSEL            => '1',
         -- Ports for dynamic reconfiguration
         DADDR               => (others => '0'),
         DCLK                => '0',
         DEN                 => '0',
         DI                  => (others => '0'),
         DO                  => open,
         DRDY                => open,
         DWE                 => '0',
         -- Ports for dynamic phase shift
         PSCLK               => '0',
         PSEN                => '0',
         PSINCDEC            => '0',
         PSDONE              => open,
         -- Other control and status signals
         LOCKED              => main_locked,
         CLKINSTOPPED        => open,
         CLKFBSTOPPED        => open,
         PWRDWN              => '0',
         RST                 => '0'
      ); -- i_clk_main

   -------------------------------------------------------------------------------------
   -- Output buffering
   -------------------------------------------------------------------------------------

   clkfb3_bufg : BUFG
      port map (
         I => clkfb3_mmcm,
         O => clkfb3
      );

   main_clk_bufg : BUFG
      port map (
         I => main_clk_mmcm,
         O => main_clk_o
      );

   cpu_clk_bufg : BUFG
      port map (
         I => cpu_clk_mmcm,
         O => cpu_clk_o
      );

   sdram_clk_bufg : BUFG
      port map (
         I => sdram_clk_mmcm,
         O => sdram_clk_o
      );

   pix_clk_bufg : BUFG
      port map (
         I => pix_clk_mmcm,
         O => pix_clk_o
      );

   -------------------------------------
   -- Reset generation
   -------------------------------------

   i_xpm_cdc_async_rst_main : xpm_cdc_async_rst
      generic map (
         RST_ACTIVE_HIGH => 1,
         DEST_SYNC_FF    => 6
      )
      port map (
         src_arst  => not main_locked,   -- 1-bit input: Source reset signal.
         dest_clk  => main_clk_o,        -- 1-bit input: Destination clock.
         dest_arst => main_rst_o         -- 1-bit output: src_rst synchronized to the destination clock domain.
                                         -- This output is registered.
      );

   -- The pixel domain gets the same MMCM-lock reset, released on its own clock
   -- (the framework's own pattern for each of its clock domains, clk_m2m.vhd).
   i_xpm_cdc_async_rst_pix : xpm_cdc_async_rst
      generic map (
         RST_ACTIVE_HIGH => 1,
         DEST_SYNC_FF    => 6
      )
      port map (
         src_arst  => not main_locked,
         dest_clk  => pix_clk_o,
         dest_arst => pix_rst_o
      );

end architecture rtl;

