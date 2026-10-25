----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- MEGA65 main file that contains the whole machine
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.globals.all;
use work.types_pkg.all;
use work.video_modes_pkg.all;
use work.vdrives_pkg.all;

library xpm;
use xpm.vcomponents.all;

entity MEGA65_Core is
generic (
   G_BOARD : string                                         -- Which platform are we running on.
);
port (
   --------------------------------------------------------------------------------------------------------
   -- QNICE Clock Domain
   --------------------------------------------------------------------------------------------------------

   -- Get QNICE clock from the framework: for the vdrives as well as for RAMs and ROMs
   qnice_clk_i             : in  std_logic;
   qnice_rst_i             : in  std_logic;

   -- Video and audio mode control
   qnice_dvi_o             : out std_logic;              -- 0=HDMI (with sound), 1=DVI (no sound)
   qnice_video_mode_o      : out video_mode_type;        -- Defined in video_modes_pkg.vhd
   qnice_osm_cfg_scaling_o : out std_logic_vector(8 downto 0);
   qnice_scandoubler_o     : out std_logic;              -- 0 = no scandoubler, 1 = scandoubler
   qnice_audio_mute_o      : out std_logic;
   qnice_audio_filter_o    : out std_logic;
   qnice_zoom_crop_o       : out std_logic;
   qnice_ascal_mode_o      : out std_logic_vector(1 downto 0);
   qnice_ascal_polyphase_o : out std_logic;
   qnice_ascal_triplebuf_o : out std_logic;
   qnice_retro15kHz_o      : out std_logic;              -- 0 = normal frequency, 1 = retro 15 kHz frequency
   qnice_csync_o           : out std_logic;              -- 0 = normal HS/VS, 1 = Composite Sync  

   -- Flip joystick ports
   qnice_flip_joyports_o   : out std_logic;

   -- On-Screen-Menu selections
   qnice_osm_control_i     : in  std_logic_vector(255 downto 0);

   -- QNICE general purpose register
   qnice_gp_reg_i          : in  std_logic_vector(255 downto 0);

   -- Core-specific devices
   qnice_dev_id_i          : in  std_logic_vector(15 downto 0);
   qnice_dev_addr_i        : in  std_logic_vector(27 downto 0);
   qnice_dev_data_i        : in  std_logic_vector(15 downto 0);
   qnice_dev_data_o        : out std_logic_vector(15 downto 0);
   qnice_dev_ce_i          : in  std_logic;
   qnice_dev_we_i          : in  std_logic;
   qnice_dev_wait_o        : out std_logic;

   --------------------------------------------------------------------------------------------------------
   -- HyperRAM Clock Domain
   --------------------------------------------------------------------------------------------------------

   hr_clk_i                : in  std_logic;
   hr_rst_i                : in  std_logic;
   hr_core_write_o         : out std_logic;
   hr_core_read_o          : out std_logic;
   hr_core_address_o       : out std_logic_vector(31 downto 0);
   hr_core_writedata_o     : out std_logic_vector(15 downto 0);
   hr_core_byteenable_o    : out std_logic_vector( 1 downto 0);
   hr_core_burstcount_o    : out std_logic_vector( 7 downto 0);
   hr_core_readdata_i      : in  std_logic_vector(15 downto 0);
   hr_core_readdatavalid_i : in  std_logic;
   hr_core_waitrequest_i   : in  std_logic;
   hr_high_i               : in  std_logic;  -- Core is too fast
   hr_low_i                : in  std_logic;  -- Core is too slow

   --------------------------------------------------------------------------------------------------------
   -- ND-120: the board's SDRAM (R4/R5/R6), straight from the top-level pins
   -- (the framework's own tops park these; CORE/vhdl/framework-overrides/
   -- top_mega65-r*.vhd hand them in here - R3 has no SDRAM and connects them
   -- to open/constants). Driven by the machine's own bridge in the main clock
   -- domain and its 180-degree twin.
   --------------------------------------------------------------------------------------------------------

   sdram_clk_o             : out   std_logic;
   sdram_cke_o             : out   std_logic;
   sdram_ras_n_o           : out   std_logic;
   sdram_cas_n_o           : out   std_logic;
   sdram_we_n_o            : out   std_logic;
   sdram_cs_n_o            : out   std_logic;
   sdram_ba_o              : out   std_logic_vector(1 downto 0);
   sdram_a_o               : out   std_logic_vector(12 downto 0);
   sdram_dqml_o            : out   std_logic;
   sdram_dqmh_o            : out   std_logic;
   sdram_dq_io             : inout std_logic_vector(15 downto 0);

   --------------------------------------------------------------------------------------------------------
   -- Video Clock Domain
   --------------------------------------------------------------------------------------------------------

   video_clk_o             : out std_logic;
   video_rst_o             : out std_logic;
   video_ce_o              : out std_logic;
   video_ce_ovl_o          : out std_logic;
   video_red_o             : out std_logic_vector(7 downto 0);
   video_green_o           : out std_logic_vector(7 downto 0);
   video_blue_o            : out std_logic_vector(7 downto 0);
   video_vs_o              : out std_logic;
   video_hs_o              : out std_logic;
   video_hblank_o          : out std_logic;
   video_vblank_o          : out std_logic;

   --------------------------------------------------------------------------------------------------------
   -- Core Clock Domain
   --------------------------------------------------------------------------------------------------------

   clk_i                   : in  std_logic;              -- 100 MHz clock

   -- Share clock and reset with the framework
   main_clk_o              : out std_logic;              -- CORE's 54 MHz clock
   main_rst_o              : out std_logic;              -- CORE's reset, synchronized

   -- M2M's reset manager provides 2 signals:
   --    m2m:   Reset the whole machine: Core and Framework
   --    core:  Only reset the core
   main_reset_m2m_i        : in  std_logic;
   main_reset_core_i       : in  std_logic;

   main_pause_core_i       : in  std_logic;

   -- On-Screen-Menu selections
   main_osm_control_i      : in  std_logic_vector(255 downto 0);

   -- QNICE general purpose register converted to main clock domain
   main_qnice_gp_reg_i     : in  std_logic_vector(255 downto 0);

   -- Audio output (Signed PCM)
   main_audio_left_o       : out signed(15 downto 0);
   main_audio_right_o      : out signed(15 downto 0);

   -- M2M Keyboard interface (incl. power led and drive led)
   main_kb_key_num_i       : in  integer range 0 to 79;  -- cycles through all MEGA65 keys
   main_kb_key_pressed_n_i : in  std_logic;              -- low active: debounced feedback: is kb_key_num_i pressed right now?
   main_power_led_o        : out std_logic;
   main_power_led_col_o    : out std_logic_vector(23 downto 0);
   main_drive_led_o        : out std_logic;
   main_drive_led_col_o    : out std_logic_vector(23 downto 0);

   -- Joysticks and paddles input
   main_joy_1_up_n_i       : in  std_logic;
   main_joy_1_down_n_i     : in  std_logic;
   main_joy_1_left_n_i     : in  std_logic;
   main_joy_1_right_n_i    : in  std_logic;
   main_joy_1_fire_n_i     : in  std_logic;
   main_joy_1_up_n_o       : out std_logic;
   main_joy_1_down_n_o     : out std_logic;
   main_joy_1_left_n_o     : out std_logic;
   main_joy_1_right_n_o    : out std_logic;
   main_joy_1_fire_n_o     : out std_logic;
   main_joy_2_up_n_i       : in  std_logic;
   main_joy_2_down_n_i     : in  std_logic;
   main_joy_2_left_n_i     : in  std_logic;
   main_joy_2_right_n_i    : in  std_logic;
   main_joy_2_fire_n_i     : in  std_logic;
   main_joy_2_up_n_o       : out std_logic;
   main_joy_2_down_n_o     : out std_logic;
   main_joy_2_left_n_o     : out std_logic;
   main_joy_2_right_n_o    : out std_logic;
   main_joy_2_fire_n_o     : out std_logic;

   main_pot1_x_i           : in  std_logic_vector(7 downto 0);
   main_pot1_y_i           : in  std_logic_vector(7 downto 0);
   main_pot2_x_i           : in  std_logic_vector(7 downto 0);
   main_pot2_y_i           : in  std_logic_vector(7 downto 0);
   main_rtc_i              : in  std_logic_vector(64 downto 0);

   -- CBM-488/IEC serial port
   iec_reset_n_o           : out std_logic;
   iec_atn_n_o             : out std_logic;
   iec_clk_en_o            : out std_logic;
   iec_clk_n_i             : in  std_logic;
   iec_clk_n_o             : out std_logic;
   iec_data_en_o           : out std_logic;
   iec_data_n_i            : in  std_logic;
   iec_data_n_o            : out std_logic;
   iec_srq_en_o            : out std_logic;
   iec_srq_n_i             : in  std_logic;
   iec_srq_n_o             : out std_logic;

   -- C64 Expansion Port (aka Cartridge Port)
   cart_en_o               : out std_logic;  -- Enable port, active high
   cart_phi2_o             : out std_logic;
   cart_dotclock_o         : out std_logic;
   cart_dma_i              : in  std_logic;
   cart_reset_oe_o         : out std_logic;
   cart_reset_i            : in  std_logic;
   cart_reset_o            : out std_logic;
   cart_game_oe_o          : out std_logic;
   cart_game_i             : in  std_logic;
   cart_game_o             : out std_logic;
   cart_exrom_oe_o         : out std_logic;
   cart_exrom_i            : in  std_logic;
   cart_exrom_o            : out std_logic;
   cart_nmi_oe_o           : out std_logic;
   cart_nmi_i              : in  std_logic;
   cart_nmi_o              : out std_logic;
   cart_irq_oe_o           : out std_logic;
   cart_irq_i              : in  std_logic;
   cart_irq_o              : out std_logic;
   cart_roml_oe_o          : out std_logic;
   cart_roml_i             : in  std_logic;
   cart_roml_o             : out std_logic;
   cart_romh_oe_o          : out std_logic;
   cart_romh_i             : in  std_logic;
   cart_romh_o             : out std_logic;
   cart_ctrl_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_ba_i               : in  std_logic;
   cart_rw_i               : in  std_logic;
   cart_io1_i              : in  std_logic;
   cart_io2_i              : in  std_logic;
   cart_ba_o               : out std_logic;
   cart_rw_o               : out std_logic;
   cart_io1_o              : out std_logic;
   cart_io2_o              : out std_logic;
   cart_addr_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_a_i                : in  unsigned(15 downto 0);
   cart_a_o                : out unsigned(15 downto 0);
   cart_data_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_d_i                : in  unsigned( 7 downto 0);
   cart_d_o                : out unsigned( 7 downto 0)
);
end entity MEGA65_Core;

architecture synthesis of MEGA65_Core is

---------------------------------------------------------------------------------------------
-- Clocks and active high reset signals for each clock domain
---------------------------------------------------------------------------------------------

signal main_clk               : std_logic;               -- Core main clock: 40 MHz, SDRAM bridge + the framework's keyboard scan
signal main_rst               : std_logic;
signal cpu_clk                : std_logic;               -- 20 MHz, the ND-120 CPU
signal sdram_clk              : std_logic;               -- 40 MHz at 180 degrees, the SDRAM chip
signal pix_clk                : std_logic;               -- 25.197 MHz, the console's pixel clock (the framework's video_clk)
signal pix_rst                : std_logic;

---------------------------------------------------------------------------------------------
-- main_clk (MiSTer core's clock)
---------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------
-- qnice_clk
---------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------
-- Menu items: line numbers in config.vhd's OPTM_ITEMS
---------------------------------------------------------------------------------------------

-- ND-120 menu (config.vhd OPTM_ITEMS, 02-SEP-2026): line numbers
constant C_MENU_TEXT_GREEN     : natural := 2;
constant C_MENU_TEXT_AMBER     : natural := 3;
constant C_MENU_TEXT_WHITE     : natural := 4;
constant C_MENU_TEXT_CYAN      : natural := 5;
constant C_MENU_PANEL          : natural := 7;
constant C_MENU_CACHE          : natural := 8;
-- drives: lines 12..16 (mount items, handled by the firmware)
constant C_MENU_HDMI_16_9_50   : natural := 21;
constant C_MENU_HDMI_16_9_60   : natural := 22;
constant C_MENU_HDMI_4_3_50    : natural := 23;
constant C_MENU_HDMI_5_4_50    : natural := 24;
constant C_MENU_HDMI_640_60    : natural := 25;
constant C_MENU_HDMI_720_5994  : natural := 26;
constant C_MENU_SVGA_800_60    : natural := 27;
constant C_MENU_CRT_EMULATION  : natural := 31;
constant C_MENU_HDMI_ZOOM      : natural := 32;

-- main clock domain
signal main_text_colour       : std_logic_vector(1 downto 0);

-- QNICE clock domain: the virtual drives' MMIO device
signal qnice_vd_data_o        : std_logic_vector(15 downto 0);
signal qnice_vd_ce            : std_logic;
signal qnice_vd_we            : std_logic;

-- the virtual drives <-> the machine
signal vd_img_mounted         : std_logic_vector(C_VDNUM - 1 downto 0);
signal vd_img_readonly        : std_logic;
signal vd_img_size            : std_logic_vector(31 downto 0);
signal vd_sd_lba              : vd_vec_array(C_VDNUM - 1 downto 0)(31 downto 0);
signal vd_sd_blk_cnt          : vd_vec_array(C_VDNUM - 1 downto 0)(5 downto 0);
signal vd_sd_rd               : vd_std_array(C_VDNUM - 1 downto 0);
signal vd_sd_wr               : vd_std_array(C_VDNUM - 1 downto 0);
signal vd_sd_ack              : vd_std_array(C_VDNUM - 1 downto 0);
signal vd_sd_buff_addr        : std_logic_vector(13 downto 0);
signal vd_sd_buff_dout        : std_logic_vector(7 downto 0);
signal vd_sd_buff_din         : vd_vec_array(C_VDNUM - 1 downto 0)(7 downto 0);
signal vd_sd_buff_wr          : std_logic;
signal main_disc_activity     : std_logic;
signal main_cpu_green         : std_logic;

begin

   -- Tristate all expansion port drivers that we can directly control
   -- @TODO: As soon as we support modules that can act as busmaster, we need to become more flexible here
   cart_ctrl_oe_o       <= '0';
   cart_addr_oe_o       <= '0';
   cart_data_oe_o       <= '0';

   -- Due to a bug in the R5/R6 boards, the cartridge port needs to be enabled for joystick port 2 to work 
   cart_en_o            <= '1';

   cart_reset_oe_o      <= '0';
   cart_game_oe_o       <= '0';
   cart_exrom_oe_o      <= '0';
   cart_nmi_oe_o        <= '0';
   cart_irq_oe_o        <= '0';
   cart_roml_oe_o       <= '0';
   cart_romh_oe_o       <= '0';

   -- Default values for all signals
   cart_phi2_o          <= '0';
   cart_reset_o         <= '1';
   cart_dotclock_o      <= '0';
   cart_game_o          <= '1';
   cart_exrom_o         <= '1';
   cart_nmi_o           <= '1';
   cart_irq_o           <= '1';
   cart_roml_o          <= '0';
   cart_romh_o          <= '0';
   cart_ba_o            <= '0';
   cart_rw_o            <= '0';
   cart_io1_o           <= '0';
   cart_io2_o           <= '0';
   cart_a_o             <= (others => '0');
   cart_d_o             <= (others => '0');

   main_joy_1_up_n_o    <= '1';
   main_joy_1_down_n_o  <= '1';
   main_joy_1_left_n_o  <= '1';
   main_joy_1_right_n_o <= '1';
   main_joy_1_fire_n_o  <= '1';
   main_joy_2_up_n_o    <= '1';
   main_joy_2_down_n_o  <= '1';
   main_joy_2_left_n_o  <= '1';
   main_joy_2_right_n_o <= '1';
   main_joy_2_fire_n_o  <= '1';


   -- MMCME2_ADV clock generators (clk.vhd, one MMCM):
   --   main_clk 40 MHz (SDRAM bridge, the framework's keyboard scan),
   --   pix_clk 25.197 MHz (the whole console: 640x480@60 pixels, keyboard
   --   decoder, UART bridge - why it is not the 40 MHz main clock is
   --   explained at the top of clk.vhd: the framework's HDMI rescaler cannot
   --   store a 40 Mpx/s picture in the HyperRAM fast enough).
   -- The CPU clock per revision (docs/00-plan.md): 20 MHz on
   -- R4/R5/R6; 13.333 MHz on R3, where the HyperRAM configuration's netlist
   -- times the CGA's IDB ring through a longer loop-break (57 ns) - a path
   -- that cannot happen but that the tool cannot prove, so the period is
   -- made long enough for it rather than untiming the internal data bus.
   clk_gen : entity work.clk
      generic map (
         G_CPU_DIV         => 60 when G_BOARD = "MEGA65_R3" else 40
      )
      port map (
         sys_clk_i         => clk_i,           -- expects 100 MHz
         main_clk_o        => main_clk,        -- 40 MHz: SDRAM bridge, the framework's keyboard scan
         main_rst_o        => main_rst,        -- CORE's reset, synchronized
         cpu_clk_o         => cpu_clk,         -- 20 MHz: the ND-120
         sdram_clk_o       => sdram_clk,       -- 40 MHz at 180 degrees
         pix_clk_o         => pix_clk,         -- 25.197 MHz: the console's pixel clock
         pix_rst_o         => pix_rst          -- its reset, synchronized
      ); -- clk_gen

   main_clk_o  <= main_clk;
   main_rst_o  <= main_rst;
   -- The video clock domain the framework consumes IS the pixel clock, as in
   -- the Apple II core (video_clk /= main_clk is a supported shape).
   video_clk_o <= pix_clk;
   video_rst_o <= pix_rst;

   ---------------------------------------------------------------------------------------------
   -- main_clk (MiSTer core's clock)
   ---------------------------------------------------------------------------------------------

   -- MEGA65's power led: By default, it is on and glows green when the MEGA65 is powered on.
   -- We switch it to blue when a long reset is detected and as long as the user keeps pressing the preset button
   -- ND-120: the case's power LED is the boot verdict you can see without a
   -- monitor - blue during a long reset (framework), AMBER while the CPU is
   -- in Master Clear / self-test or halted in STERR, GREEN once the
   -- microcode reaches MACL2 (self-test passed, OPCOM alive) - the same
   -- meaning as the CPU board's own green lamp (ND3202D LED[1]).
   main_power_led_o     <= '1';
   main_power_led_col_o <= x"0000FF" when main_reset_m2m_i = '1' else
                           x"00FF00" when main_cpu_green = '1' else
                           x"FF8000";

   -- Console text colour from the OSD (one-of-four group; green if none)
   main_text_colour <= "01" when main_osm_control_i(C_MENU_TEXT_AMBER) = '1' else
                       "10" when main_osm_control_i(C_MENU_TEXT_WHITE) = '1' else
                       "11" when main_osm_control_i(C_MENU_TEXT_CYAN)  = '1' else
                       "00";

   -- main.vhd is the ND-120 machine
   i_main : entity work.main
      generic map (
         G_VDNUM              => C_VDNUM
      )
      port map (
         clk_main_i           => main_clk,
         reset_soft_i         => main_reset_core_i,
         reset_hard_i         => main_reset_m2m_i,
         pause_i              => main_pause_core_i,

         clk_main_speed_i     => CORE_CLK_SPEED,

         clk_cpu_i            => cpu_clk,
         clk_sdram_i          => sdram_clk,
         clk_pix_i            => pix_clk,
         rst_pix_i            => pix_rst,

         text_colour_i        => main_text_colour,
         panel_enable_i       => main_osm_control_i(C_MENU_PANEL),
         cache_on_i           => main_osm_control_i(C_MENU_CACHE),

         -- Video output: 640x480 @ 60 Hz, one pixel per pix_clk (25.197 MHz)
         video_ce_o           => video_ce_o,
         video_ce_ovl_o       => video_ce_ovl_o,
         video_red_o          => video_red_o,
         video_green_o        => video_green_o,
         video_blue_o         => video_blue_o,
         video_vs_o           => video_vs_o,
         video_hs_o           => video_hs_o,
         video_hblank_o       => video_hblank_o,
         video_vblank_o       => video_vblank_o,

         -- audio output (pcm format, signed values)
         audio_left_o         => main_audio_left_o,
         audio_right_o        => main_audio_right_o,

         -- M2M Keyboard interface
         kb_key_num_i         => main_kb_key_num_i,
         kb_key_pressed_n_i   => main_kb_key_pressed_n_i,

         -- the virtual drives (QNICE clock domain)
         clk_qnice_i          => qnice_clk_i,
         rst_qnice_i          => qnice_rst_i,
         vd_img_mounted_i     => vd_img_mounted,
         vd_img_readonly_i    => vd_img_readonly,
         vd_img_size_i        => vd_img_size,
         vd_sd_lba_o          => vd_sd_lba,
         vd_sd_blk_cnt_o      => vd_sd_blk_cnt,
         vd_sd_rd_o           => vd_sd_rd,
         vd_sd_wr_o           => vd_sd_wr,
         vd_sd_ack_i          => vd_sd_ack,
         vd_sd_buff_addr_i    => vd_sd_buff_addr,
         vd_sd_buff_dout_i    => vd_sd_buff_dout,
         vd_sd_buff_din_o     => vd_sd_buff_din,
         vd_sd_buff_wr_i      => vd_sd_buff_wr,

         -- HyperRAM through the framework's Avalon port (R3 builds)
         hr_clk_i             => hr_clk_i,
         hr_rst_i             => hr_rst_i,
         hr_write_o           => hr_core_write_o,
         hr_read_o            => hr_core_read_o,
         hr_address_o         => hr_core_address_o,
         hr_writedata_o       => hr_core_writedata_o,
         hr_byteenable_o      => hr_core_byteenable_o,
         hr_burstcount_o      => hr_core_burstcount_o,
         hr_readdata_i        => hr_core_readdata_i,
         hr_readdatavalid_i   => hr_core_readdatavalid_i,
         hr_waitrequest_i     => hr_core_waitrequest_i,

         -- the board's SDRAM (R4/R5/R6 builds)
         sdram_clk_o          => sdram_clk_o,
         sdram_cke_o          => sdram_cke_o,
         sdram_cs_n_o         => sdram_cs_n_o,
         sdram_ras_n_o        => sdram_ras_n_o,
         sdram_cas_n_o        => sdram_cas_n_o,
         sdram_we_n_o         => sdram_we_n_o,
         sdram_a_o            => sdram_a_o,
         sdram_ba_o           => sdram_ba_o,
         sdram_dqml_o         => sdram_dqml_o,
         sdram_dqmh_o         => sdram_dqmh_o,
         sdram_dq_io          => sdram_dq_io,

         cpu_green_o          => main_cpu_green,
         disc_activity_o      => main_disc_activity,

         -- MEGA65 joysticks and paddles/mouse/potentiometers
         joy_1_up_n_i         => main_joy_1_up_n_i ,
         joy_1_down_n_i       => main_joy_1_down_n_i,
         joy_1_left_n_i       => main_joy_1_left_n_i,
         joy_1_right_n_i      => main_joy_1_right_n_i,
         joy_1_fire_n_i       => main_joy_1_fire_n_i,

         joy_2_up_n_i         => main_joy_2_up_n_i,
         joy_2_down_n_i       => main_joy_2_down_n_i,
         joy_2_left_n_i       => main_joy_2_left_n_i,
         joy_2_right_n_i      => main_joy_2_right_n_i,
         joy_2_fire_n_i       => main_joy_2_fire_n_i,

         pot1_x_i             => main_pot1_x_i,
         pot1_y_i             => main_pot1_y_i,
         pot2_x_i             => main_pot2_x_i,
         pot2_y_i             => main_pot2_y_i
      ); -- i_main

   ---------------------------------------------------------------------------------------------
   -- Audio and video settings (QNICE clock domain)
   ---------------------------------------------------------------------------------------------

   -- Due to a discussion on the MEGA65 discord (https://discord.com/channels/719326990221574164/794775503818588200/1039457688020586507)
   -- we decided to choose a naming convention for the PAL modes that might be more intuitive for the end users than it is
   -- for the programmers: "4:3" means "meant to be run on a 4:3 monitor", "5:4 on a 5:4 monitor".
   -- The technical reality is though, that in our "5:4" mode we are actually doing a 4/3 aspect ratio adjustment
   -- while in the 4:3 mode we are outputting a 5:4 image. This is kind of odd, but it seemed that our 4/3 aspect ratio
   -- adjusted image looks best on a 5:4 monitor and the other way round.
   -- Not sure if this will stay forever or if we will come up with a better naming convention.
   qnice_video_mode_o <= C_VIDEO_SVGA_800_60   when qnice_osm_control_i(C_MENU_SVGA_800_60)    = '1' else
                         C_VIDEO_HDMI_720_5994 when qnice_osm_control_i(C_MENU_HDMI_720_5994)  = '1' else
                         C_VIDEO_HDMI_640_60   when qnice_osm_control_i(C_MENU_HDMI_640_60)    = '1' else
                         C_VIDEO_HDMI_5_4_50   when qnice_osm_control_i(C_MENU_HDMI_5_4_50)    = '1' else
                         C_VIDEO_HDMI_4_3_50   when qnice_osm_control_i(C_MENU_HDMI_4_3_50)    = '1' else
                         C_VIDEO_HDMI_16_9_50  when qnice_osm_control_i(C_MENU_HDMI_16_9_50)   = '1' else
                         C_VIDEO_HDMI_16_9_60;   -- ND-120: the console is 60 Hz, so 720p60 is the fallback

   -- Use On-Screen-Menu selections to configure several audio and video settings
   -- Video and audio mode control
   qnice_dvi_o                <= '0';                                         -- 0=HDMI (with sound), 1=DVI (no sound)
   qnice_scandoubler_o        <= '0';                                         -- no scandoubler
   qnice_audio_mute_o         <= '0';                                         -- audio is not muted
   qnice_audio_filter_o       <= '0';                                         -- no audio in this core
   qnice_zoom_crop_o          <= qnice_osm_control_i(C_MENU_HDMI_ZOOM);       -- 0 = no zoom/crop
   
   -- These two signals are often used as a pair (i.e. both '1'), particularly when
   -- you want to run old analog cathode ray tube monitors or TVs (via SCART)
   -- If you want to provide your users a choice, then a good choice is:
   --    "Standard VGA":                     qnice_retro15kHz_o=0 and qnice_csync_o=0
   --    "Retro 15 kHz with HSync and VSync" qnice_retro15kHz_o=1 and qnice_csync_o=0
   --    "Retro 15 kHz with CSync"           qnice_retro15kHz_o=1 and qnice_csync_o=1
   qnice_retro15kHz_o         <= '0';
   qnice_csync_o              <= '0';
   qnice_osm_cfg_scaling_o    <= (others => '1');

   -- ascal filters that are applied while processing the input
   -- 00 : Nearest Neighbour
   -- 01 : Bilinear
   -- 10 : Sharp Bilinear
   -- 11 : Bicubic
   qnice_ascal_mode_o         <= "00";

   -- If polyphase is '1' then the ascal filter mode is ignored and polyphase filters are used instead
   -- @TODO: Right now, the filters are hardcoded in the M2M framework, we need to make them changeable inside m2m-rom.asm
   qnice_ascal_polyphase_o    <= qnice_osm_control_i(C_MENU_CRT_EMULATION);

   -- ascal triple-buffering
   -- @TODO: Right now, the M2M framework only supports OFF, so do not touch until the framework is upgraded
   qnice_ascal_triplebuf_o    <= '0';

   -- Flip joystick ports (i.e. the joystick in port 2 is used as joystick 1 and vice versa)
   qnice_flip_joyports_o      <= '0';

   ---------------------------------------------------------------------------------------------
   -- Core specific device handling (QNICE clock domain)
   ---------------------------------------------------------------------------------------------

   core_specific_devices : process(all)
   begin
      -- make sure that this is x"EEEE" by default and avoid a register here by having this default value
      qnice_dev_data_o     <= x"EEEE";
      qnice_dev_wait_o     <= '0';

      qnice_vd_ce          <= '0';
      qnice_vd_we          <= '0';

      case qnice_dev_id_i is

         -- the virtual drives (floppy 0/1, Winchester 0/1, tape)
         when C_VD_DEVICE =>
            qnice_vd_ce          <= qnice_dev_ce_i;
            qnice_vd_we          <= qnice_dev_we_i;
            qnice_dev_data_o     <= qnice_vd_data_o;

         -- @TODO YOUR RAMs or ROMs (e.g. for cartridges) or other devices here
         -- Device numbers need to be >= 0x0100

         when others => null;
      end case;
   end process core_specific_devices;

   ---------------------------------------------------------------------------------------------
   -- Dual Clocks
   ---------------------------------------------------------------------------------------------

   -- Put your dual-clock devices such as RAMs and ROMs here
   --
   -- Use the M2M framework's official RAM/ROM: dualport_2clk_ram
   -- and make sure that the you configure the port that works with QNICE as a falling edge
   -- by setting G_FALLING_A or G_FALLING_B (depending on which port you use) to true.

   ---------------------------------------------------------------------------------------
   -- Virtual drives: the ND-120's floppy 0/1, Winchester 0/1 and paper tape,
   -- served by the framework's Shell from image files on the SD card
   -- (m2m/M2M/vhdl/vdrives.vhd), in the slot order of config.vhd's mount lines.
   ---------------------------------------------------------------------------------------

   -- The drive LED shows the ND-120's disc activity.
   main_drive_led_o     <= main_disc_activity;
   main_drive_led_col_o <= x"00FF00";

   i_vdrives : entity work.vdrives
      generic map (
         VDNUM       => C_VDNUM
      )
      port map
      (
         clk_qnice_i       => qnice_clk_i,
         -- "core clock" = the QNICE clock here, on purpose: vdrives puts its
         -- mount records (img_mounted/img_size/img_readonly) in clk_core_i
         -- while the block stream is in clk_qnice_i, and our storage backend
         -- (rtl/nd_storage_vdrives.v) samples BOTH on one clock, the QNICE
         -- one - it does its own crossing into the CPU domain. With main_clk
         -- here the records crossed 40 MHz -> 50 MHz untimed: 17 setup
         -- misses, WNS -0.174 ns (R6 build, 02-SEP-2026).
         clk_core_i        => qnice_clk_i,
         reset_core_i      => qnice_rst_i,

         -- Core clock domain (= QNICE clock, see above)
         img_mounted_o     => vd_img_mounted,
         img_readonly_o    => vd_img_readonly,
         img_size_o        => vd_img_size,
         img_type_o        => open,
         drive_mounted_o   => open,

         cache_dirty_o     => open,
         cache_flushing_o  => open,

         -- QNICE clock domain
         sd_lba_i          => vd_sd_lba,
         sd_blk_cnt_i      => vd_sd_blk_cnt,
         sd_rd_i           => vd_sd_rd,
         sd_wr_i           => vd_sd_wr,
         sd_ack_o          => vd_sd_ack,

         sd_buff_addr_o    => vd_sd_buff_addr,
         sd_buff_dout_o    => vd_sd_buff_dout,
         sd_buff_din_i     => vd_sd_buff_din,
         sd_buff_wr_o      => vd_sd_buff_wr,

         -- QNICE interface (MMIO, 4k-segmented)
         qnice_addr_i      => qnice_dev_addr_i,
         qnice_data_i      => qnice_dev_data_i,
         qnice_data_o      => qnice_vd_data_o,
         qnice_ce_i        => qnice_vd_ce,
         qnice_we_i        => qnice_vd_we
      ); -- i_vdrives

end architecture synthesis;

