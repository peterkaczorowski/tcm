-- =============================================================================
-- Module:  tcm_top
-- Project: CERN ALICE FIT TCM (Trigger and Clock Module) Firmware
-- Author:  TCM Firmware Team
-- Brief:   Top-level entity — connects all sub-modules and maps to board IOs.
--
-- Board: CERN ALICE FIT TCM (Xilinx Kintex UltraScale+)
--
-- Architecture overview:
--
--   LHC Ref Clk (LVDS, 40 MHz)
--       │
--       └─► clk_manager ──► clk_sys (240 MHz)
--                      │──► clk_bc  (40 MHz)
--
--   PM A-side GBT links (4×)           PM C-side GBT links (4×)
--       │                                      │
--       ▼ (via GTH transceivers)               ▼
--   gbt_rx → pm_decoder → pm_a_data   gbt_rx → pm_decoder → pm_c_data
--                │                                  │
--                └────────────┬───────────────────┘
--                             ▼
--                    trigger_processor ◄── amplitude_sum
--                             │
--                    readout_manager
--                             │
--                    gbt_tx (2 CRU links) ──► CRU
--
--   slow_ctrl ◄──► IPbus / upstream register bus
--
-- Note on GTH transceivers:
--   The 4.8 Gbps GBT serial links are implemented using Xilinx GTH
--   transceivers instantiated via the Vivado IP Catalog.  In this RTL
--   description the GTH parallel-side interfaces are represented as named
--   signals.  Real integration requires generating the GTH IP and connecting
--   its parallel ports to gbt_rx/gbt_tx rx_raw/tx_raw ports.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_tcm.all;

entity tcm_top is
  port (
    -- -------------------------------------------------------------------------
    -- LHC reference clock — differential LVDS, 40.0789 MHz
    -- -------------------------------------------------------------------------
    lhc_clk_p   : in  std_logic;
    lhc_clk_n   : in  std_logic;

    -- -------------------------------------------------------------------------
    -- Board reset (active low)
    -- -------------------------------------------------------------------------
    sys_rst_n   : in  std_logic;

    -- -------------------------------------------------------------------------
    -- BC0 synchronisation marker (one pulse per LHC orbit, 40 MHz domain)
    -- -------------------------------------------------------------------------
    bc0_in      : in  std_logic;

    -- -------------------------------------------------------------------------
    -- GBT serial links — PM A-side (4 × 4.8 Gbps LVDS via GTH)
    -- -------------------------------------------------------------------------
    pm_a_rx_p   : in  std_logic_vector(C_PM_LINKS_A - 1 downto 0);
    pm_a_rx_n   : in  std_logic_vector(C_PM_LINKS_A - 1 downto 0);
    pm_a_tx_p   : out std_logic_vector(C_PM_LINKS_A - 1 downto 0);
    pm_a_tx_n   : out std_logic_vector(C_PM_LINKS_A - 1 downto 0);

    -- -------------------------------------------------------------------------
    -- GBT serial links — PM C-side (4 × 4.8 Gbps LVDS via GTH)
    -- -------------------------------------------------------------------------
    pm_c_rx_p   : in  std_logic_vector(C_PM_LINKS_C - 1 downto 0);
    pm_c_rx_n   : in  std_logic_vector(C_PM_LINKS_C - 1 downto 0);
    pm_c_tx_p   : out std_logic_vector(C_PM_LINKS_C - 1 downto 0);
    pm_c_tx_n   : out std_logic_vector(C_PM_LINKS_C - 1 downto 0);

    -- -------------------------------------------------------------------------
    -- GBT serial links — CRU readout (2 × 4.8 Gbps LVDS via GTH)
    -- -------------------------------------------------------------------------
    cru_rx_p    : in  std_logic_vector(C_CRU_LINKS - 1 downto 0);
    cru_rx_n    : in  std_logic_vector(C_CRU_LINKS - 1 downto 0);
    cru_tx_p    : out std_logic_vector(C_CRU_LINKS - 1 downto 0);
    cru_tx_n    : out std_logic_vector(C_CRU_LINKS - 1 downto 0);

    -- -------------------------------------------------------------------------
    -- Physics trigger outputs — LVDS to downstream trigger distribution
    -- [0] Min-bias  [1] Vertex  [2] Semi-central  [3] Central  [4] Laser
    -- -------------------------------------------------------------------------
    trig_out_p  : out std_logic_vector(C_TRIG_BITS - 1 downto 0);
    trig_out_n  : out std_logic_vector(C_TRIG_BITS - 1 downto 0);

    -- -------------------------------------------------------------------------
    -- Upstream slow-control bus (from IPbus bridge, 240 MHz domain)
    -- -------------------------------------------------------------------------
    sc_addr     : in  std_logic_vector(7 downto 0);
    sc_wdata    : in  std_logic_vector(31 downto 0);
    sc_we       : in  std_logic;
    sc_re       : in  std_logic;
    sc_rdata    : out std_logic_vector(31 downto 0);
    sc_ack      : out std_logic;

    -- -------------------------------------------------------------------------
    -- Status LEDs
    --  [0] PLL locked
    --  [1] All PM links locked
    --  [2] Trigger active
    --  [3] Readout FIFO overflow
    -- -------------------------------------------------------------------------
    led_status  : out std_logic_vector(3 downto 0)
  );
end entity tcm_top;

architecture rtl of tcm_top is

  -- ===========================================================================
  -- Clocks and reset
  -- ===========================================================================
  signal clk_sys    : std_logic;
  signal clk_bc     : std_logic;
  signal pll_locked : std_logic;
  signal sys_rst    : std_logic;   -- Active high

  -- ===========================================================================
  -- Timing
  -- ===========================================================================
  signal bc_id      : std_logic_vector(C_BC_ID_WIDTH   - 1 downto 0);
  signal orbit_id   : std_logic_vector(C_ORBIT_ID_WIDTH - 1 downto 0);

  -- ===========================================================================
  -- GBT parallel-side signals (from/to GTH transceivers)
  -- In a real design, each element connects to a separate GTH instance.
  -- ===========================================================================
  type t_raw_arr is array (natural range <>) of std_logic_vector(119 downto 0);

  -- PM A-side RX (GTH → gbt_rx)
  signal pm_a_rx_raw : t_raw_arr(0 to C_PM_LINKS_A - 1) :=
    (others => (others => '0'));
  signal pm_a_rx_val : std_logic_vector(C_PM_LINKS_A - 1 downto 0) :=
    (others => '0');

  -- PM C-side RX
  signal pm_c_rx_raw : t_raw_arr(0 to C_PM_LINKS_C - 1) :=
    (others => (others => '0'));
  signal pm_c_rx_val : std_logic_vector(C_PM_LINKS_C - 1 downto 0) :=
    (others => '0');

  -- PM A-side TX (gbt_tx → GTH)
  signal pm_a_tx_raw : std_logic_vector(119 downto 0);
  signal pm_a_tx_val : std_logic;

  -- PM C-side TX
  signal pm_c_tx_raw : std_logic_vector(119 downto 0);
  signal pm_c_tx_val : std_logic;

  -- CRU TX (one frame broadcast to all CRU links)
  signal cru_tx_raw  : std_logic_vector(119 downto 0);
  signal cru_tx_val  : std_logic;

  -- ===========================================================================
  -- GBT decoded frames
  -- ===========================================================================
  type t_gbt_frame_link_arr is array (natural range <>) of t_gbt_frame;
  signal pm_a_frames : t_gbt_frame_link_arr(0 to C_PM_LINKS_A - 1);
  signal pm_c_frames : t_gbt_frame_link_arr(0 to C_PM_LINKS_C - 1);
  signal pm_a_locked : std_logic_vector(C_PM_LINKS_A - 1 downto 0);
  signal pm_c_locked : std_logic_vector(C_PM_LINKS_C - 1 downto 0);

  -- ===========================================================================
  -- Decoded PM data records
  -- ===========================================================================
  signal pm_a_data   : t_pm_data_arr(0 to C_PM_LINKS_A - 1);
  signal pm_c_data   : t_pm_data_arr(0 to C_PM_LINKS_C - 1);
  signal pm_valid    : std_logic;

  -- ===========================================================================
  -- Amplitude sums
  -- ===========================================================================
  signal sum_a       : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal sum_c       : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal sum_total   : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal sum_valid   : std_logic;

  -- ===========================================================================
  -- Trigger output
  -- ===========================================================================
  signal trig_sig    : t_trigger;

  -- ===========================================================================
  -- Readout
  -- ===========================================================================
  signal rdo_frame   : t_gbt_frame;
  signal event_cnt   : unsigned(31 downto 0);
  signal rdo_overfl  : std_logic;

  -- ===========================================================================
  -- Register bus
  -- ===========================================================================
  signal trig_m2s    : t_reg_m2s;
  signal trig_s2m    : t_reg_s2m;

  -- Trigger counters
  signal cnt_mb      : unsigned(31 downto 0);
  signal cnt_vx      : unsigned(31 downto 0);
  signal cnt_sc      : unsigned(31 downto 0);
  signal cnt_c       : unsigned(31 downto 0);

  -- Control
  signal global_en   : std_logic;
  signal laser_en    : std_logic;

  -- Link status
  signal all_links_up : std_logic_vector(C_PM_LINKS_TOTAL + C_CRU_LINKS - 1
                                         downto 0);

  -- PM broadcast frame (same for both sides)
  signal pm_tx_frame : t_gbt_frame;

  -- LED helpers
  signal all_pm_locked : std_logic;

begin

  -- ===========================================================================
  -- Reset
  -- ===========================================================================
  sys_rst <= not sys_rst_n;

  -- ===========================================================================
  -- Clock management
  -- ===========================================================================
  u_clk_mgr : entity work.clk_manager
    port map (
      clk_ref_p => lhc_clk_p,
      clk_ref_n => lhc_clk_n,
      clk_sys   => clk_sys,
      clk_bc    => clk_bc,
      locked    => pll_locked
    );

  -- ===========================================================================
  -- Timing counters
  -- ===========================================================================
  u_timing : entity work.timing_counter
    port map (
      clk_bc   => clk_bc,
      rst      => sys_rst,
      bc0      => bc0_in,
      bc_id    => bc_id,
      orbit_id => orbit_id
    );

  -- ===========================================================================
  -- GBT receivers — PM A-side (one instance per link)
  -- ===========================================================================
  gen_pm_a_rx : for i in 0 to C_PM_LINKS_A - 1 generate
    u_gbt_rx : entity work.gbt_rx
      port map (
        clk_sys    => clk_sys,
        clk_bc     => clk_bc,
        rst        => sys_rst,
        rx_raw     => pm_a_rx_raw(i),
        rx_raw_val => pm_a_rx_val(i),
        frame_out  => pm_a_frames(i),
        locked     => pm_a_locked(i)
      );

    u_pm_dec : entity work.pm_decoder
      port map (
        clk_bc   => clk_bc,
        rst      => sys_rst,
        frame_in => pm_a_frames(i),
        side     => '0',
        pm_data  => pm_a_data(i)
      );
  end generate gen_pm_a_rx;

  -- ===========================================================================
  -- GBT receivers — PM C-side
  -- ===========================================================================
  gen_pm_c_rx : for i in 0 to C_PM_LINKS_C - 1 generate
    u_gbt_rx : entity work.gbt_rx
      port map (
        clk_sys    => clk_sys,
        clk_bc     => clk_bc,
        rst        => sys_rst,
        rx_raw     => pm_c_rx_raw(i),
        rx_raw_val => pm_c_rx_val(i),
        frame_out  => pm_c_frames(i),
        locked     => pm_c_locked(i)
      );

    u_pm_dec : entity work.pm_decoder
      port map (
        clk_bc   => clk_bc,
        rst      => sys_rst,
        frame_in => pm_c_frames(i),
        side     => '1',
        pm_data  => pm_c_data(i)
      );
  end generate gen_pm_c_rx;

  -- ===========================================================================
  -- PM valid: all links on both sides report valid data
  -- ===========================================================================
  p_pm_valid : process(clk_bc)
    variable va, vc : std_logic;
  begin
    if rising_edge(clk_bc) then
      if sys_rst = '1' then
        pm_valid <= '0';
      else
        va := '1';
        for i in 0 to C_PM_LINKS_A - 1 loop
          if pm_a_data(i).valid = '0' then va := '0'; end if;
        end loop;
        vc := '1';
        for i in 0 to C_PM_LINKS_C - 1 loop
          if pm_c_data(i).valid = '0' then vc := '0'; end if;
        end loop;
        pm_valid <= va and vc and global_en;
      end if;
    end if;
  end process p_pm_valid;

  -- ===========================================================================
  -- Amplitude sum (shared tree, 3-cycle latency)
  -- ===========================================================================
  u_amp_sum : entity work.amplitude_sum
    port map (
      clk       => clk_bc,
      rst       => sys_rst,
      pm_a      => pm_a_data,
      pm_c      => pm_c_data,
      in_valid  => pm_valid,
      sum_a     => sum_a,
      sum_c     => sum_c,
      sum_total => sum_total,
      out_valid => sum_valid
    );

  -- ===========================================================================
  -- Trigger processor
  -- ===========================================================================
  u_trig : entity work.trigger_processor
    port map (
      clk_bc    => clk_bc,
      rst       => sys_rst,
      pm_a      => pm_a_data,
      pm_c      => pm_c_data,
      pm_valid  => pm_valid,
      bc_id     => bc_id,
      orbit_id  => orbit_id,
      sum_total => sum_total,
      sum_valid => sum_valid,
      reg_in    => trig_m2s,
      reg_out   => trig_s2m,
      trig_out  => trig_sig,
      cnt_mb    => cnt_mb,
      cnt_vx    => cnt_vx,
      cnt_sc    => cnt_sc,
      cnt_c     => cnt_c
    );

  -- ===========================================================================
  -- Readout manager
  -- ===========================================================================
  u_readout : entity work.readout_manager
    port map (
      clk_bc    => clk_bc,
      rst       => sys_rst,
      pm_a      => pm_a_data,
      pm_c      => pm_c_data,
      pm_valid  => pm_valid,
      trig_in   => trig_sig,
      bc_id     => bc_id,
      orbit_id  => orbit_id,
      sum_a     => sum_a,
      sum_c     => sum_c,
      frame_out => rdo_frame,
      event_cnt => event_cnt,
      overflow  => rdo_overfl
    );

  -- ===========================================================================
  -- GBT transmitter — CRU readout (one instance; frame broadcast to all CRU links)
  -- ===========================================================================
  u_gbt_tx_cru : entity work.gbt_tx
    port map (
      clk_bc   => clk_bc,
      rst      => sys_rst,
      frame_in => rdo_frame,
      tx_raw   => cru_tx_raw,
      tx_valid => cru_tx_val
    );

  -- ===========================================================================
  -- GBT transmitter — PM broadcast (timing + trigger downstream)
  -- One tx instance per side (same frame to all PMs on that side)
  -- ===========================================================================
  pm_tx_frame.data(79 downto 68) <= bc_id;
  pm_tx_frame.data(67 downto 36) <= orbit_id;
  pm_tx_frame.data(35 downto 31) <= trig_sig.bits;
  pm_tx_frame.data(30 downto 0)  <= (others => '0');
  pm_tx_frame.valid               <= '1';

  u_gbt_tx_pma : entity work.gbt_tx
    port map (
      clk_bc   => clk_bc,
      rst      => sys_rst,
      frame_in => pm_tx_frame,
      tx_raw   => pm_a_tx_raw,
      tx_valid => pm_a_tx_val
    );

  u_gbt_tx_pmc : entity work.gbt_tx
    port map (
      clk_bc   => clk_bc,
      rst      => sys_rst,
      frame_in => pm_tx_frame,
      tx_raw   => pm_c_tx_raw,
      tx_valid => pm_c_tx_val
    );

  -- ===========================================================================
  -- Slow control
  -- ===========================================================================
  all_links_up(C_PM_LINKS_A - 1 downto 0)
    <= pm_a_locked;
  all_links_up(C_PM_LINKS_A + C_PM_LINKS_C - 1 downto C_PM_LINKS_A)
    <= pm_c_locked;
  all_links_up(C_PM_LINKS_TOTAL + C_CRU_LINKS - 1 downto C_PM_LINKS_TOTAL)
    <= (others => '1');   -- CRU link lock status (placeholder)

  u_slow_ctrl : entity work.slow_ctrl
    port map (
      clk_sys    => clk_sys,
      rst        => sys_rst,
      up_addr    => sc_addr,
      up_wdata   => sc_wdata,
      up_we      => sc_we,
      up_re      => sc_re,
      up_rdata   => sc_rdata,
      up_ack     => sc_ack,
      trig_m2s   => trig_m2s,
      trig_s2m   => trig_s2m,
      pll_locked => pll_locked,
      links_up   => all_links_up,
      bc_id      => bc_id,
      orbit_id   => orbit_id,
      event_cnt  => event_cnt,
      cnt_mb     => cnt_mb,
      cnt_vx     => cnt_vx,
      cnt_sc     => cnt_sc,
      cnt_c      => cnt_c,
      global_en  => global_en,
      laser_en   => laser_en
    );

  -- ===========================================================================
  -- Trigger output LVDS
  -- In hardware: use OBUFDS primitives for differential drive
  -- ===========================================================================
  gen_trig_lvds : for i in 0 to C_TRIG_BITS - 1 generate
    trig_out_p(i) <= trig_sig.bits(i);
    trig_out_n(i) <= not trig_sig.bits(i);
  end generate gen_trig_lvds;

  -- ===========================================================================
  -- Serial IO tie-offs (GTH parallel outputs connected to external GTH IP;
  -- these assignments are structural placeholders)
  -- ===========================================================================
  pm_a_tx_p <= (others => '0');
  pm_a_tx_n <= (others => '1');
  pm_c_tx_p <= (others => '0');
  pm_c_tx_n <= (others => '1');
  cru_tx_p  <= (others => '0');
  cru_tx_n  <= (others => '1');

  -- ===========================================================================
  -- Status LEDs
  -- ===========================================================================
  p_leds : process(clk_bc)
    variable locked_all : std_logic;
  begin
    if rising_edge(clk_bc) then
      locked_all := '1';
      for i in 0 to C_PM_LINKS_A - 1 loop
        if pm_a_locked(i) = '0' then locked_all := '0'; end if;
      end loop;
      for i in 0 to C_PM_LINKS_C - 1 loop
        if pm_c_locked(i) = '0' then locked_all := '0'; end if;
      end loop;
      all_pm_locked <= locked_all;
    end if;
  end process p_leds;

  led_status(0) <= pll_locked;
  led_status(1) <= all_pm_locked;
  led_status(2) <= trig_sig.valid;
  led_status(3) <= rdo_overfl;

end architecture rtl;
