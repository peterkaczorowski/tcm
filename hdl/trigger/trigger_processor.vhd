-- =============================================================================
-- Module:  trigger_processor
-- Project: CERN ALICE FIT TCM Firmware
-- Brief:   Main trigger processing pipeline.
--
-- Implements the five ALICE FIT physics-trigger algorithms:
--
--   0 – Min-Bias  (MB):  at least thr_mb hits on A-side AND C-side
--   1 – Vertex    (VX):  MB AND |mean_time_A − mean_time_C| ≤ thr_vx_win
--   2 – Semi-Cent (SC):  total amplitude sum ≥ thr_sc
--   3 – Central   (C):   total amplitude sum ≥ thr_c  (> thr_sc)
--   4 – Laser     (LA):  current BC matches laser_bc setting
--
-- Pipeline latency: 3 clk_bc cycles from pm_valid to trig_out.valid.
-- Amplitude sums arrive from an external amplitude_sum instance with the same
-- 3-cycle latency, so they are aligned with trig_out.
--
-- Register interface uses separate m2s / s2m port pairs to avoid VHDL
-- multiple-driver issues.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_tcm.all;

entity trigger_processor is
  generic (
    -- Default thresholds (overridden at run time via reg_bus)
    G_THR_MB_DEF   : natural := 1;
    G_THR_VX_DEF   : natural := 6;
    G_THR_SC_DEF   : natural := 16#0800#;
    G_THR_C_DEF    : natural := 16#1800#;
    G_LASER_BC_DEF : natural := 3455
  );
  port (
    clk_bc   : in  std_logic;
    rst      : in  std_logic;

    -- PM aggregated data (clk_bc domain)
    pm_a     : in  t_pm_data_arr(0 to C_PM_LINKS_A - 1);
    pm_c     : in  t_pm_data_arr(0 to C_PM_LINKS_C - 1);
    pm_valid : in  std_logic;

    -- Bunch-crossing timing
    bc_id    : in  std_logic_vector(C_BC_ID_WIDTH   - 1 downto 0);
    orbit_id : in  std_logic_vector(C_ORBIT_ID_WIDTH - 1 downto 0);

    -- Amplitude sums from amplitude_sum (3-cycle latency — same as trig_out)
    sum_total : in  unsigned(C_CHARGE_WIDTH - 1 downto 0);
    sum_valid : in  std_logic;

    -- Slow-control register interface
    reg_in   : in  t_reg_m2s;
    reg_out  : out t_reg_s2m;

    -- Physics trigger output
    trig_out : out t_trigger;

    -- Trigger counters (readable via slow control)
    cnt_mb   : out unsigned(31 downto 0);
    cnt_vx   : out unsigned(31 downto 0);
    cnt_sc   : out unsigned(31 downto 0);
    cnt_c    : out unsigned(31 downto 0)
  );
end entity trigger_processor;

architecture rtl of trigger_processor is

  -- ---------------------------------------------------------------------------
  -- Configurable thresholds
  -- ---------------------------------------------------------------------------
  signal thr_mb     : unsigned(C_MULT_WIDTH   - 1 downto 0);
  signal thr_vx_win : unsigned(C_TIME_WIDTH   - 1 downto 0);
  signal thr_sc     : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal thr_c      : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal laser_bc   : unsigned(C_BC_ID_WIDTH  - 1 downto 0);

  -- ---------------------------------------------------------------------------
  -- Pipeline stage 1 — multiplicity and mean time
  -- ---------------------------------------------------------------------------
  signal s1_mult_a : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal s1_mult_c : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal s1_time_a : signed(C_TIME_WIDTH - 1 downto 0);
  signal s1_time_c : signed(C_TIME_WIDTH - 1 downto 0);
  signal s1_valid  : std_logic;
  signal s1_bc_id  : std_logic_vector(C_BC_ID_WIDTH   - 1 downto 0);
  signal s1_orbit  : std_logic_vector(C_ORBIT_ID_WIDTH - 1 downto 0);

  -- ---------------------------------------------------------------------------
  -- Pipeline stage 2 — time difference
  -- ---------------------------------------------------------------------------
  signal s2_mult_a    : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal s2_mult_c    : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal s2_time_diff : signed(C_TIME_WIDTH downto 0);
  signal s2_valid     : std_logic;
  signal s2_bc_id     : std_logic_vector(C_BC_ID_WIDTH   - 1 downto 0);
  signal s2_orbit     : std_logic_vector(C_ORBIT_ID_WIDTH - 1 downto 0);

  -- Stage 2b: one-cycle latch to align trigger data with amplitude-sum output
  signal s2b_mult_a    : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal s2b_mult_c    : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal s2b_time_diff : signed(C_TIME_WIDTH downto 0);
  signal s2b_valid     : std_logic;
  signal s2b_bc_id     : std_logic_vector(C_BC_ID_WIDTH   - 1 downto 0);
  signal s2b_orbit     : std_logic_vector(C_ORBIT_ID_WIDTH - 1 downto 0);

  -- ---------------------------------------------------------------------------
  -- Trigger counters
  -- ---------------------------------------------------------------------------
  signal cnt_mb_int : unsigned(31 downto 0) := (others => '0');
  signal cnt_vx_int : unsigned(31 downto 0) := (others => '0');
  signal cnt_sc_int : unsigned(31 downto 0) := (others => '0');
  signal cnt_c_int  : unsigned(31 downto 0) := (others => '0');

begin

  cnt_mb <= cnt_mb_int;
  cnt_vx <= cnt_vx_int;
  cnt_sc <= cnt_sc_int;
  cnt_c  <= cnt_c_int;

  -- ---------------------------------------------------------------------------
  -- Register bank — threshold initialisation and run-time update
  -- ---------------------------------------------------------------------------
  p_regs : process(clk_bc)
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        thr_mb     <= to_unsigned(G_THR_MB_DEF,   thr_mb'length);
        thr_vx_win <= to_unsigned(G_THR_VX_DEF,   thr_vx_win'length);
        thr_sc     <= to_unsigned(G_THR_SC_DEF,   thr_sc'length);
        thr_c      <= to_unsigned(G_THR_C_DEF,    thr_c'length);
        laser_bc   <= to_unsigned(G_LASER_BC_DEF, laser_bc'length);
        reg_out    <= C_REG_S2M_ZERO;
      else
        reg_out.ack   <= '0';
        reg_out.rdata <= (others => '0');

        if reg_in.we = '1' then
          reg_out.ack <= '1';
          case reg_in.addr is
            when C_REG_THR_MB     => thr_mb     <= unsigned(reg_in.wdata(thr_mb'range));
            when C_REG_THR_VERTEX => thr_vx_win <= unsigned(reg_in.wdata(thr_vx_win'range));
            when C_REG_THR_SC     => thr_sc     <= unsigned(reg_in.wdata(thr_sc'range));
            when C_REG_THR_CENT   => thr_c      <= unsigned(reg_in.wdata(thr_c'range));
            when C_REG_VERTEX_WIN => laser_bc   <= unsigned(reg_in.wdata(laser_bc'range));
            when others           => null;
          end case;
        end if;

        if reg_in.re = '1' then
          reg_out.ack <= '1';
          case reg_in.addr is
            when C_REG_THR_MB     => reg_out.rdata <= std_logic_vector(resize(thr_mb,   32));
            when C_REG_THR_VERTEX => reg_out.rdata <= std_logic_vector(resize(thr_vx_win, 32));
            when C_REG_THR_SC     => reg_out.rdata <= std_logic_vector(resize(thr_sc,   32));
            when C_REG_THR_CENT   => reg_out.rdata <= std_logic_vector(resize(thr_c,    32));
            when C_REG_TRIG_CNT_MB => reg_out.rdata <= std_logic_vector(cnt_mb_int);
            when C_REG_TRIG_CNT_VX => reg_out.rdata <= std_logic_vector(cnt_vx_int);
            when C_REG_TRIG_CNT_SC => reg_out.rdata <= std_logic_vector(cnt_sc_int);
            when C_REG_TRIG_CNT_C  => reg_out.rdata <= std_logic_vector(cnt_c_int);
            when others => null;
          end case;
        end if;
      end if;
    end if;
  end process p_regs;

  -- ---------------------------------------------------------------------------
  -- Stage 1: sum multiplicity and compute mean arrival time per side
  -- ---------------------------------------------------------------------------
  p_stage1 : process(clk_bc)
    variable acc_mult_a : unsigned(C_CHARGE_WIDTH - 1 downto 0);
    variable acc_mult_c : unsigned(C_CHARGE_WIDTH - 1 downto 0);
    variable acc_time_a : signed(C_TIME_WIDTH + C_MULT_WIDTH - 1 downto 0);
    variable acc_time_c : signed(C_TIME_WIDTH + C_MULT_WIDTH - 1 downto 0);
    variable hits_a     : integer range 0 to C_PM_LINKS_A;
    variable hits_c     : integer range 0 to C_PM_LINKS_C;
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        s1_mult_a <= (others => '0');
        s1_mult_c <= (others => '0');
        s1_time_a <= (others => '0');
        s1_time_c <= (others => '0');
        s1_valid  <= '0';
        s1_bc_id  <= (others => '0');
        s1_orbit  <= (others => '0');
      else
        s1_valid <= pm_valid;
        s1_bc_id <= bc_id;
        s1_orbit <= orbit_id;

        acc_mult_a := (others => '0');
        acc_time_a := (others => '0');
        hits_a     := 0;
        for i in 0 to C_PM_LINKS_A - 1 loop
          if pm_a(i).valid = '1' then
            acc_mult_a := acc_mult_a +
                          resize(pm_a(i).hit_count, C_CHARGE_WIDTH);
            acc_time_a := acc_time_a +
                          resize(pm_a(i).mean_time,
                                 C_TIME_WIDTH + C_MULT_WIDTH);
            hits_a := hits_a + 1;
          end if;
        end loop;
        s1_mult_a <= acc_mult_a;
        if hits_a > 0 then
          s1_time_a <= resize(acc_time_a / hits_a, C_TIME_WIDTH);
        else
          s1_time_a <= (others => '0');
        end if;

        acc_mult_c := (others => '0');
        acc_time_c := (others => '0');
        hits_c     := 0;
        for i in 0 to C_PM_LINKS_C - 1 loop
          if pm_c(i).valid = '1' then
            acc_mult_c := acc_mult_c +
                          resize(pm_c(i).hit_count, C_CHARGE_WIDTH);
            acc_time_c := acc_time_c +
                          resize(pm_c(i).mean_time,
                                 C_TIME_WIDTH + C_MULT_WIDTH);
            hits_c := hits_c + 1;
          end if;
        end loop;
        s1_mult_c <= acc_mult_c;
        if hits_c > 0 then
          s1_time_c <= resize(acc_time_c / hits_c, C_TIME_WIDTH);
        else
          s1_time_c <= (others => '0');
        end if;
      end if;
    end if;
  end process p_stage1;

  -- ---------------------------------------------------------------------------
  -- Stage 2: compute |time_A − time_C| and latch multiplicity
  -- ---------------------------------------------------------------------------
  p_stage2 : process(clk_bc)
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        s2_mult_a    <= (others => '0');
        s2_mult_c    <= (others => '0');
        s2_time_diff <= (others => '0');
        s2_valid     <= '0';
        s2_bc_id     <= (others => '0');
        s2_orbit     <= (others => '0');
      else
        s2_valid     <= s1_valid;
        s2_bc_id     <= s1_bc_id;
        s2_orbit     <= s1_orbit;
        s2_mult_a    <= s1_mult_a;
        s2_mult_c    <= s1_mult_c;
        s2_time_diff <= resize(s1_time_a, C_TIME_WIDTH + 1) -
                        resize(s1_time_c, C_TIME_WIDTH + 1);
      end if;
    end if;
  end process p_stage2;

  -- ---------------------------------------------------------------------------
  -- Stage 2b: latch stage-2 data by one extra cycle so it aligns with
  -- amplitude_sum out_valid (which has one more register stage than s2_valid)
  -- ---------------------------------------------------------------------------
  p_stage2b : process(clk_bc)
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        s2b_mult_a    <= (others => '0');
        s2b_mult_c    <= (others => '0');
        s2b_time_diff <= (others => '0');
        s2b_valid     <= '0';
        s2b_bc_id     <= (others => '0');
        s2b_orbit     <= (others => '0');
      else
        s2b_mult_a    <= s2_mult_a;
        s2b_mult_c    <= s2_mult_c;
        s2b_time_diff <= s2_time_diff;
        s2b_valid     <= s2_valid;
        s2b_bc_id     <= s2_bc_id;
        s2b_orbit     <= s2_orbit;
      end if;
    end if;
  end process p_stage2b;

  -- ---------------------------------------------------------------------------
  -- Stage 3: apply trigger algorithms (aligned with amplitude_sum output)
  -- ---------------------------------------------------------------------------
  p_stage3 : process(clk_bc)
    variable trig_bits : std_logic_vector(C_TRIG_BITS - 1 downto 0);
    variable abs_tdiff : unsigned(C_TIME_WIDTH - 1 downto 0);
    variable hit_a     : std_logic;
    variable hit_c     : std_logic;
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        trig_out  <= C_TRIGGER_ZERO;
        cnt_mb_int <= (others => '0');
        cnt_vx_int <= (others => '0');
        cnt_sc_int <= (others => '0');
        cnt_c_int  <= (others => '0');
      else
        trig_bits := (others => '0');

        if sum_valid = '1' and s2b_valid = '1' then

          if s2b_time_diff(s2b_time_diff'high) = '1' then
            abs_tdiff :=
              unsigned(-s2b_time_diff(C_TIME_WIDTH - 1 downto 0));
          else
            abs_tdiff :=
              unsigned(s2b_time_diff(C_TIME_WIDTH - 1 downto 0));
          end if;

          if s2b_mult_a >= resize(thr_mb, s2b_mult_a'length) then
            hit_a := '1';
          else
            hit_a := '0';
          end if;
          if s2b_mult_c >= resize(thr_mb, s2b_mult_c'length) then
            hit_c := '1';
          else
            hit_c := '0';
          end if;

          -- 0: Minimum-bias
          if hit_a = '1' and hit_c = '1' then
            trig_bits(C_TB_MIN_BIAS) := '1';
            cnt_mb_int <= cnt_mb_int + 1;
          end if;

          -- 1: Vertex — MB plus timing coincidence
          if trig_bits(C_TB_MIN_BIAS) = '1' and
             abs_tdiff <= resize(thr_vx_win, abs_tdiff'length) then
            trig_bits(C_TB_VERTEX) := '1';
            cnt_vx_int <= cnt_vx_int + 1;
          end if;

          -- 2: Semi-central — large total charge
          if sum_total >= thr_sc then
            trig_bits(C_TB_SEMI_CENT) := '1';
            cnt_sc_int <= cnt_sc_int + 1;
          end if;

          -- 3: Central — very large total charge
          if sum_total >= thr_c then
            trig_bits(C_TB_CENTRAL) := '1';
            cnt_c_int <= cnt_c_int + 1;
          end if;

          -- 4: Laser — fixed BC number
          if unsigned(s2b_bc_id) = laser_bc then
            trig_bits(C_TB_LASER) := '1';
          end if;

          trig_out.bits     <= trig_bits;
          trig_out.bc_id    <= s2b_bc_id;
          trig_out.orbit_id <= s2b_orbit;
          -- Only assert valid when at least one trigger bit fired
          if unsigned(trig_bits) /= 0 then
            trig_out.valid <= '1';
          else
            trig_out.valid <= '0';
          end if;

        else
          trig_out.valid <= '0';
          trig_out.bits  <= (others => '0');
        end if;
      end if;
    end if;
  end process p_stage3;

end architecture rtl;
