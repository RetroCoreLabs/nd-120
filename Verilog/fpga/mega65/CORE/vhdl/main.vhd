----------------------------------------------------------------------------------
-- ND-120 for MEGA65 - the core behind the MiSTer2MEGA65 wrapper
--
-- Full path: Verilog/fpga/mega65/CORE/vhdl/main.vhd
--
-- The framework's template main.vhd held its demo core. This one holds the
-- ND-120 machine, which is written in Verilog (Verilog/fpga/mega65/rtl/
-- nd120_mega65_machine.v and everything under it: the CPU board, the sheet-49
-- main-memory backend, the storage controllers on the virtual drives, the
-- shared terminal). This file is the thin VHDL skin the framework's
-- mega65.vhd expects: the template's ports, plus the ones the machine needs
-- from the wrapper (the CPU and SDRAM clocks, the virtual drives, the
-- HyperRAM Avalon port, the SDRAM pins, the OSD settings).
--
-- Written 02-SEP-2026 for the full machine (Ronny: "a fully working nd120
-- cpu, a tdv terminal emulator with keys working, a floppy, tape and
-- winchester"). Which main memory is in the build is a Verilog define chosen
-- by build.tcl from the board revision (docs/00-plan.md): MAIN_RAM_SDRAM on
-- R4/R5/R6, MAIN_RAM_DDR2 (the Nexys seam over HyperRAM) on R3. The machine's
-- port list is the same either way; the unused group idles.
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_modes_pkg.all;
use work.vdrives_pkg.all;

entity main is
   generic (
      G_VDNUM                 : natural                     -- amount of virtual drives
   );
   port (
      clk_main_i              : in  std_logic;              -- 40 MHz: SDRAM bridge clock; the framework's keyboard scan arrives on it
      reset_soft_i            : in  std_logic;
      reset_hard_i            : in  std_logic;
      pause_i                 : in  std_logic;

      -- MiSTer core main clock speed:
      -- Make sure you pass very exact numbers here, because they are used for avoiding clock drift at derived clocks
      clk_main_speed_i        : in  natural;

      -- ND-120: the machine's other clocks, from the same MMCM (clk.vhd)
      clk_cpu_i               : in  std_logic;              -- 20 MHz
      clk_sdram_i             : in  std_logic;              -- 40 MHz, 180 degrees
      clk_pix_i               : in  std_logic;              -- 25.197 MHz: the console's clock, pixels + keyboard decoder + UART bridge (= the framework's video_clk)
      rst_pix_i               : in  std_logic;              -- active high, synchronous to clk_pix_i (MMCM lock)

      -- ND-120: settings from the OSD
      text_colour_i           : in  std_logic_vector(1 downto 0);   -- 0 green 1 amber 2 white 3 cyan
      panel_enable_i          : in  std_logic;                      -- operator panel drawn under the text
      cache_on_i              : in  std_logic;                      -- the CPU's own cache

      -- Video output
      video_ce_o              : out std_logic;
      video_ce_ovl_o          : out std_logic;
      video_red_o             : out std_logic_vector(7 downto 0);
      video_green_o           : out std_logic_vector(7 downto 0);
      video_blue_o            : out std_logic_vector(7 downto 0);
      video_vs_o              : out std_logic;
      video_hs_o              : out std_logic;
      video_hblank_o          : out std_logic;
      video_vblank_o          : out std_logic;

      -- Audio output (Signed PCM)
      audio_left_o            : out signed(15 downto 0);
      audio_right_o           : out signed(15 downto 0);

      -- M2M Keyboard interface
      kb_key_num_i            : in  integer range 0 to 79;    -- cycles through all MEGA65 keys
      kb_key_pressed_n_i      : in  std_logic;                -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- ND-120: the virtual drives (vdrives.vhd), QNICE clock domain
      clk_qnice_i             : in  std_logic;
      rst_qnice_i             : in  std_logic;                -- active high (the framework's)
      vd_img_mounted_i        : in  std_logic_vector(G_VDNUM - 1 downto 0);
      vd_img_readonly_i       : in  std_logic;
      vd_img_size_i           : in  std_logic_vector(31 downto 0);
      vd_sd_lba_o             : out vd_vec_array(G_VDNUM - 1 downto 0)(31 downto 0);
      vd_sd_blk_cnt_o         : out vd_vec_array(G_VDNUM - 1 downto 0)(5 downto 0);
      vd_sd_rd_o              : out vd_std_array(G_VDNUM - 1 downto 0);
      vd_sd_wr_o              : out vd_std_array(G_VDNUM - 1 downto 0);
      vd_sd_ack_i             : in  vd_std_array(G_VDNUM - 1 downto 0);
      vd_sd_buff_addr_i       : in  std_logic_vector(13 downto 0);
      vd_sd_buff_dout_i       : in  std_logic_vector(7 downto 0);
      vd_sd_buff_din_o        : out vd_vec_array(G_VDNUM - 1 downto 0)(7 downto 0);
      vd_sd_buff_wr_i         : in  std_logic;

      -- ND-120: HyperRAM through the framework's Avalon port (R3 builds), hr_clk domain
      hr_clk_i                : in  std_logic;
      hr_rst_i                : in  std_logic;
      hr_write_o              : out std_logic;
      hr_read_o               : out std_logic;
      hr_address_o            : out std_logic_vector(31 downto 0);
      hr_writedata_o          : out std_logic_vector(15 downto 0);
      hr_byteenable_o         : out std_logic_vector(1 downto 0);
      hr_burstcount_o         : out std_logic_vector(7 downto 0);
      hr_readdata_i           : in  std_logic_vector(15 downto 0);
      hr_readdatavalid_i      : in  std_logic;
      hr_waitrequest_i        : in  std_logic;

      -- ND-120: the board's SDRAM (R4/R5/R6 builds)
      sdram_clk_o             : out std_logic;
      sdram_cke_o             : out std_logic;
      sdram_cs_n_o            : out std_logic;
      sdram_ras_n_o           : out std_logic;
      sdram_cas_n_o           : out std_logic;
      sdram_we_n_o            : out std_logic;
      sdram_a_o               : out std_logic_vector(12 downto 0);
      sdram_ba_o              : out std_logic_vector(1 downto 0);
      sdram_dqml_o            : out std_logic;
      sdram_dqmh_o            : out std_logic;
      sdram_dq_io             : inout std_logic_vector(15 downto 0);

      -- ND-120: status for the LEDs (CPU clock domain)
      cpu_green_o             : out std_logic;
      disc_activity_o         : out std_logic;

      -- MEGA65 joysticks and paddles/mouse/potentiometers (unused)
      joy_1_up_n_i            : in  std_logic;
      joy_1_down_n_i          : in  std_logic;
      joy_1_left_n_i          : in  std_logic;
      joy_1_right_n_i         : in  std_logic;
      joy_1_fire_n_i          : in  std_logic;

      joy_2_up_n_i            : in  std_logic;
      joy_2_down_n_i          : in  std_logic;
      joy_2_left_n_i          : in  std_logic;
      joy_2_right_n_i         : in  std_logic;
      joy_2_fire_n_i          : in  std_logic;

      pot1_x_i                : in  std_logic_vector(7 downto 0);
      pot1_y_i                : in  std_logic_vector(7 downto 0);
      pot2_x_i                : in  std_logic_vector(7 downto 0);
      pot2_y_i                : in  std_logic_vector(7 downto 0)
   );
end entity main;

architecture synthesis of main is

   -- The Verilog machine (Verilog/fpga/mega65/rtl/nd120_mega65_machine.v).
   -- Declared as a component: Vivado binds it to the Verilog module by name
   -- at elaboration (mixed-language flow). Every per-slot vdrives signal is
   -- FLATTENED on the Verilog side (slot n in bits [n*W +: W]) and unpacked
   -- into the framework's arrays below.
   component nd120_mega65_machine is
      generic (
         N_CLIENTS  : integer;
         LOCAL_ECHO : integer
      );
      port (
         clk_cpu          : in  std_logic;
         clk_2x           : in  std_logic;
         clk_2x_sdram     : in  std_logic;
         clk_pix          : in  std_logic;
         rst_n            : in  std_logic;
         rst_pix_n        : in  std_logic;
         cache_on         : in  std_logic;
         key_num          : in  std_logic_vector(6 downto 0);
         key_pressed_n    : in  std_logic;
         text_colour      : in  std_logic_vector(1 downto 0);
         panel_enable     : in  std_logic;
         video_r          : out std_logic_vector(7 downto 0);
         video_g          : out std_logic_vector(7 downto 0);
         video_b          : out std_logic_vector(7 downto 0);
         video_hs         : out std_logic;
         video_vs         : out std_logic;
         video_hblank     : out std_logic;
         video_vblank     : out std_logic;
         clk_qnice        : in  std_logic;
         rst_qnice_n      : in  std_logic;
         img_mounted      : in  std_logic_vector(G_VDNUM - 1 downto 0);
         img_readonly     : in  std_logic;
         img_size         : in  std_logic_vector(31 downto 0);
         sd_lba           : out std_logic_vector(G_VDNUM * 32 - 1 downto 0);
         sd_blk_cnt       : out std_logic_vector(G_VDNUM * 6 - 1 downto 0);
         sd_rd            : out std_logic_vector(G_VDNUM - 1 downto 0);
         sd_wr            : out std_logic_vector(G_VDNUM - 1 downto 0);
         sd_ack           : in  std_logic_vector(G_VDNUM - 1 downto 0);
         sd_buff_addr     : in  std_logic_vector(13 downto 0);
         sd_buff_dout     : in  std_logic_vector(7 downto 0);
         sd_buff_din      : out std_logic_vector(7 downto 0);
         sd_buff_wr       : in  std_logic;
         sdram_clk        : out std_logic;
         sdram_cke        : out std_logic;
         sdram_cs_n       : out std_logic;
         sdram_ras_n      : out std_logic;
         sdram_cas_n      : out std_logic;
         sdram_we_n       : out std_logic;
         sdram_a          : out std_logic_vector(12 downto 0);
         sdram_ba         : out std_logic_vector(1 downto 0);
         sdram_dqml       : out std_logic;
         sdram_dqmh       : out std_logic;
         sdram_dq         : inout std_logic_vector(15 downto 0);
         hr_clk           : in  std_logic;
         hr_rst           : in  std_logic;
         hr_write         : out std_logic;
         hr_read          : out std_logic;
         hr_address       : out std_logic_vector(31 downto 0);
         hr_writedata     : out std_logic_vector(15 downto 0);
         hr_byteenable    : out std_logic_vector(1 downto 0);
         hr_burstcount    : out std_logic_vector(7 downto 0);
         hr_readdata      : in  std_logic_vector(15 downto 0);
         hr_readdatavalid : in  std_logic;
         hr_waitrequest   : in  std_logic;
         cpu_red          : out std_logic;
         cpu_green        : out std_logic;
         cpu_running      : out std_logic;
         disc_activity    : out std_logic
      );
   end component;

   signal rst_n        : std_logic;
   signal rst_pix_n    : std_logic;
   signal rst_qnice_n  : std_logic;
   signal key_num_slv  : std_logic_vector(6 downto 0);

   -- the flattened vdrives buses
   signal sd_lba_flat     : std_logic_vector(G_VDNUM * 32 - 1 downto 0);
   signal sd_blk_cnt_flat : std_logic_vector(G_VDNUM * 6 - 1 downto 0);
   signal sd_rd_flat      : std_logic_vector(G_VDNUM - 1 downto 0);
   signal sd_wr_flat      : std_logic_vector(G_VDNUM - 1 downto 0);
   signal sd_ack_flat     : std_logic_vector(G_VDNUM - 1 downto 0);
   signal sd_buff_din_one : std_logic_vector(7 downto 0);

begin

   -- The whole machine runs on the framework's reset (either button press),
   -- asynchronous and active low into the Verilog side. The pixel domain
   -- takes the same buttons plus its own clock's lock; the Verilog side
   -- synchronises the release onto clk_pix.
   rst_n       <= not (reset_soft_i or reset_hard_i);
   rst_pix_n   <= not (reset_soft_i or reset_hard_i or rst_pix_i);
   rst_qnice_n <= not rst_qnice_i;
   key_num_slv <= std_logic_vector(to_unsigned(kb_key_num_i, 7));

   -- vdrives arrays <-> flat vectors. Only one transaction is ever in flight,
   -- so every slot is fed the same sd_buff_din byte (nd_storage_vdrives).
   unpack : for i in 0 to G_VDNUM - 1 generate
      vd_sd_lba_o(i)      <= sd_lba_flat(i * 32 + 31 downto i * 32);
      vd_sd_blk_cnt_o(i)  <= sd_blk_cnt_flat(i * 6 + 5 downto i * 6);
      vd_sd_rd_o(i)       <= sd_rd_flat(i);
      vd_sd_wr_o(i)       <= sd_wr_flat(i);
      sd_ack_flat(i)      <= vd_sd_ack_i(i);
      vd_sd_buff_din_o(i) <= sd_buff_din_one;
   end generate unpack;

   i_machine : nd120_mega65_machine
      generic map (
         N_CLIENTS  => G_VDNUM,
         LOCAL_ECHO => 0                    -- the ND-120 echoes what you type
      )
      port map (
         clk_cpu          => clk_cpu_i,
         clk_2x           => clk_main_i,
         clk_2x_sdram     => clk_sdram_i,
         clk_pix          => clk_pix_i,
         rst_n            => rst_n,
         rst_pix_n        => rst_pix_n,
         cache_on         => cache_on_i,
         key_num          => key_num_slv,
         key_pressed_n    => kb_key_pressed_n_i,
         text_colour      => text_colour_i,
         panel_enable     => panel_enable_i,
         video_r          => video_red_o,
         video_g          => video_green_o,
         video_b          => video_blue_o,
         video_hs         => video_hs_o,
         video_vs         => video_vs_o,
         video_hblank     => video_hblank_o,
         video_vblank     => video_vblank_o,
         clk_qnice        => clk_qnice_i,
         rst_qnice_n      => rst_qnice_n,
         img_mounted      => vd_img_mounted_i,
         img_readonly     => vd_img_readonly_i,
         img_size         => vd_img_size_i,
         sd_lba           => sd_lba_flat,
         sd_blk_cnt       => sd_blk_cnt_flat,
         sd_rd            => sd_rd_flat,
         sd_wr            => sd_wr_flat,
         sd_ack           => sd_ack_flat,
         sd_buff_addr     => vd_sd_buff_addr_i,
         sd_buff_dout     => vd_sd_buff_dout_i,
         sd_buff_din      => sd_buff_din_one,
         sd_buff_wr       => vd_sd_buff_wr_i,
         sdram_clk        => sdram_clk_o,
         sdram_cke        => sdram_cke_o,
         sdram_cs_n       => sdram_cs_n_o,
         sdram_ras_n      => sdram_ras_n_o,
         sdram_cas_n      => sdram_cas_n_o,
         sdram_we_n       => sdram_we_n_o,
         sdram_a          => sdram_a_o,
         sdram_ba         => sdram_ba_o,
         sdram_dqml       => sdram_dqml_o,
         sdram_dqmh       => sdram_dqmh_o,
         sdram_dq         => sdram_dq_io,
         hr_clk           => hr_clk_i,
         hr_rst           => hr_rst_i,
         hr_write         => hr_write_o,
         hr_read          => hr_read_o,
         hr_address       => hr_address_o,
         hr_writedata     => hr_writedata_o,
         hr_byteenable    => hr_byteenable_o,
         hr_burstcount    => hr_burstcount_o,
         hr_readdata      => hr_readdata_i,
         hr_readdatavalid => hr_readdatavalid_i,
         hr_waitrequest   => hr_waitrequest_i,
         cpu_red          => open,
         cpu_green        => cpu_green_o,
         cpu_running      => open,
         disc_activity    => disc_activity_o
      );

   -- One pixel per clock: the console's 25.197 MHz pix_clk IS the pixel clock,
   -- and mega65.vhd hands that clock to the framework as video_clk_o.
   video_ce_o     <= '1';
   video_ce_ovl_o <= '1';

   -- Silence. The terminal's bell could become a click here later.
   audio_left_o   <= (others => '0');
   audio_right_o  <= (others => '0');

end architecture synthesis;
