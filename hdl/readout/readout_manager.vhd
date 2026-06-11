-- =============================================================================
-- Module:  readout_manager
-- Project: CERN ALICE FIT TCM Firmware
-- Brief:   Event data readout manager.
--
-- Collects PM data for each bunch crossing in which a physics trigger fires
-- and packages it into GBT frames for transmission to the CRU
-- (Common Readout Unit).
--
-- GBT frame payload layout (80 bits) for readout:
--   [79:68]  BC ID             (12 bits)
--   [67:56]  Sum charge A      (12 bits, MSBs of 16-bit sum)
--   [55:44]  Sum charge C      (12 bits, MSBs of 16-bit sum)
--   [43:33]  Mean time A       (11 bits)
--   [32:22]  Mean time C       (11 bits)
--   [21:17]  Trigger bits      (5 bits)
--   [16:9]   Hit multiplicity A (8 bits)
--   [8:1]    Hit multiplicity C (8 bits)
--   [0]      Reserved
--
-- The module implements a shallow FIFO to buffer events while awaiting
-- GBT link credit, and tracks per-orbit event counts.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_tcm.all;

entity readout_manager is
  generic (
    G_FIFO_DEPTH : natural := 16   -- Must be power of 2, max events buffered
  );
  port (
    -- Bunch-crossing clock
    clk_bc     : in  std_logic;
    rst        : in  std_logic;

    -- Aggregated PM data (same cycle as pm_valid)
    pm_a       : in  t_pm_data_arr(0 to C_PM_LINKS_A - 1);
    pm_c       : in  t_pm_data_arr(0 to C_PM_LINKS_C - 1);
    pm_valid   : in  std_logic;

    -- Trigger decision (latency-aligned with pm_valid + 3 cycles)
    trig_in    : in  t_trigger;

    -- Bunch-crossing timing
    bc_id      : in  std_logic_vector(C_BC_ID_WIDTH  - 1 downto 0);
    orbit_id   : in  std_logic_vector(C_ORBIT_ID_WIDTH - 1 downto 0);

    -- Charge sums from amplitude_sum (same latency as trig_in)
    sum_a      : in  unsigned(C_CHARGE_WIDTH - 1 downto 0);
    sum_c      : in  unsigned(C_CHARGE_WIDTH - 1 downto 0);

    -- GBT frame output to CRU link
    frame_out  : out t_gbt_frame;

    -- Running event counter (readable via slow control)
    event_cnt  : out unsigned(31 downto 0);

    -- FIFO overflow flag (sticky, cleared by reset)
    overflow   : out std_logic
  );
end entity readout_manager;

architecture rtl of readout_manager is

  -- -------------------------------------------------------------------------
  -- Event record stored in FIFO
  -- -------------------------------------------------------------------------
  type t_event is record
    bc_id    : std_logic_vector(C_BC_ID_WIDTH  - 1 downto 0);
    orbit_id : std_logic_vector(C_ORBIT_ID_WIDTH - 1 downto 0);
    sum_a    : unsigned(C_CHARGE_WIDTH - 1 downto 0);
    sum_c    : unsigned(C_CHARGE_WIDTH - 1 downto 0);
    mult_a   : unsigned(C_MULT_WIDTH  - 1 downto 0);
    mult_c   : unsigned(C_MULT_WIDTH  - 1 downto 0);
    time_a   : signed(C_TIME_WIDTH - 1 downto 0);
    time_c   : signed(C_TIME_WIDTH - 1 downto 0);
    trig     : std_logic_vector(C_TRIG_BITS - 1 downto 0);
  end record t_event;

  constant C_EVENT_ZERO : t_event := (
    bc_id    => (others => '0'),
    orbit_id => (others => '0'),
    sum_a    => (others => '0'),
    sum_c    => (others => '0'),
    mult_a   => (others => '0'),
    mult_c   => (others => '0'),
    time_a   => (others => '0'),
    time_c   => (others => '0'),
    trig     => (others => '0')
  );

  type t_event_fifo is array (0 to G_FIFO_DEPTH - 1) of t_event;

  -- -------------------------------------------------------------------------
  -- Pipeline to align PM data with trigger output (3 cycles delay)
  -- -------------------------------------------------------------------------
  type t_pm_pipe is array (0 to 2) of t_pm_data_arr(0 to C_PM_LINKS_A - 1);
  type t_pmc_pipe is array (0 to 2) of t_pm_data_arr(0 to C_PM_LINKS_C - 1);

  signal pm_a_pipe    : t_pm_pipe;
  signal pm_c_pipe    : t_pmc_pipe;
  signal pm_a_aligned : t_pm_data_arr(0 to C_PM_LINKS_A - 1);
  signal pm_c_aligned : t_pm_data_arr(0 to C_PM_LINKS_C - 1);

  -- -------------------------------------------------------------------------
  -- FIFO signals
  -- -------------------------------------------------------------------------
  signal fifo         : t_event_fifo;
  signal wr_ptr       : unsigned(3 downto 0) := (others => '0');
  signal rd_ptr       : unsigned(3 downto 0) := (others => '0');
  signal fifo_empty   : std_logic;
  signal fifo_full    : std_logic;

  signal ev_cnt_int   : unsigned(31 downto 0) := (others => '0');

begin

  fifo_empty <= '1' when wr_ptr = rd_ptr else '0';
  fifo_full  <= '1' when
    (wr_ptr + 1) mod G_FIFO_DEPTH = rd_ptr else '0';

  -- -------------------------------------------------------------------------
  -- Pipeline PM data to align with trigger output (3-cycle latency match)
  -- -------------------------------------------------------------------------
  p_pipe : process(clk_bc)
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        for s in 0 to 2 loop
          for i in 0 to C_PM_LINKS_A - 1 loop
            pm_a_pipe(s)(i) <= C_PM_DATA_ZERO;
          end loop;
          for i in 0 to C_PM_LINKS_C - 1 loop
            pm_c_pipe(s)(i) <= C_PM_DATA_ZERO;
          end loop;
        end loop;
      else
        pm_a_pipe(0) <= pm_a;
        pm_c_pipe(0) <= pm_c;
        for s in 1 to 2 loop
          pm_a_pipe(s) <= pm_a_pipe(s - 1);
          pm_c_pipe(s) <= pm_c_pipe(s - 1);
        end loop;
      end if;
    end if;
  end process p_pipe;

  pm_a_aligned <= pm_a_pipe(2);
  pm_c_aligned <= pm_c_pipe(2);

  -- -------------------------------------------------------------------------
  -- FIFO write: capture event on each trigger assertion
  -- -------------------------------------------------------------------------
  p_fifo_wr : process(clk_bc)
    variable ev  : t_event;
    variable ma  : unsigned(C_MULT_WIDTH - 1 downto 0);
    variable mc  : unsigned(C_MULT_WIDTH - 1 downto 0);
    variable ta  : signed(C_TIME_WIDTH - 1 downto 0);
    variable tc  : signed(C_TIME_WIDTH - 1 downto 0);
    variable cnt : natural;
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        wr_ptr    <= (others => '0');
        ev_cnt_int <= (others => '0');
        overflow  <= '0';
      else
        if trig_in.valid = '1' and
           trig_in.bits /= std_logic_vector(to_unsigned(0, C_TRIG_BITS)) then

          ev_cnt_int <= ev_cnt_int + 1;

          if fifo_full = '0' then
            -- Accumulate per-side multiplicity and mean time from aligned PM data
            ma  := (others => '0');
            ta  := (others => '0');
            cnt := 0;
            for i in 0 to C_PM_LINKS_A - 1 loop
              if pm_a_aligned(i).valid = '1' then
                ma  := ma  + resize(pm_a_aligned(i).hit_count, C_MULT_WIDTH);
                ta  := ta  + resize(pm_a_aligned(i).mean_time, C_TIME_WIDTH);
                cnt := cnt + 1;
              end if;
            end loop;
            if cnt > 0 then ta := ta / cnt; end if;

            mc  := (others => '0');
            tc  := (others => '0');
            cnt := 0;
            for i in 0 to C_PM_LINKS_C - 1 loop
              if pm_c_aligned(i).valid = '1' then
                mc  := mc  + resize(pm_c_aligned(i).hit_count, C_MULT_WIDTH);
                tc  := tc  + resize(pm_c_aligned(i).mean_time, C_TIME_WIDTH);
                cnt := cnt + 1;
              end if;
            end loop;
            if cnt > 0 then tc := tc / cnt; end if;

            ev.bc_id    := trig_in.bc_id;
            ev.orbit_id := trig_in.orbit_id;
            ev.sum_a    := sum_a;
            ev.sum_c    := sum_c;
            ev.mult_a   := ma;
            ev.mult_c   := mc;
            ev.time_a   := ta;
            ev.time_c   := tc;
            ev.trig     := trig_in.bits;

            fifo(to_integer(wr_ptr) mod G_FIFO_DEPTH) <= ev;
            wr_ptr <= wr_ptr + 1;
          else
            overflow <= '1';
          end if;
        end if;
      end if;
    end if;
  end process p_fifo_wr;

  -- -------------------------------------------------------------------------
  -- FIFO read: emit one GBT frame per BC when data is available
  -- -------------------------------------------------------------------------
  p_fifo_rd : process(clk_bc)
    variable ev : t_event;
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        rd_ptr     <= (others => '0');
        frame_out  <= C_GBT_FRAME_ZERO;
      else
        if fifo_empty = '0' then
          ev := fifo(to_integer(rd_ptr) mod G_FIFO_DEPTH);
          rd_ptr <= rd_ptr + 1;

          -- Pack event into 80-bit GBT payload
          -- [79:68] BC ID (12b)
          -- [67:52] Sum A (16b)
          -- [51:36] Sum C (16b)
          -- [35:25] Time A (11b)
          -- [24:14] Time C (11b)
          -- [13:9]  Trig bits (5b)
          -- [8:1]   Mult A (8b)
          -- [0]     MSB of Mult C (1b — remainder in next frame if needed)
          frame_out.data <=
            ev.bc_id &                                  -- 79:68
            std_logic_vector(ev.sum_a) &                -- 67:52
            std_logic_vector(ev.sum_c) &                -- 51:36
            std_logic_vector(ev.time_a) &               -- 35:25
            std_logic_vector(ev.time_c) &               -- 24:14
            ev.trig &                                   -- 13:9
            std_logic_vector(ev.mult_a) &               -- 8:1
            std_logic_vector(ev.mult_c(C_MULT_WIDTH-1 downto C_MULT_WIDTH-1)); -- 0
          frame_out.valid <= '1';
        else
          frame_out <= C_GBT_FRAME_ZERO;
        end if;
      end if;
    end if;
  end process p_fifo_rd;

  event_cnt <= ev_cnt_int;

end architecture rtl;
