-- =============================================================================
-- Testbench: tb_trigger_processor
-- Project:   CERN ALICE FIT TCM Firmware
-- Brief:     Simulates trigger_processor + amplitude_sum under various PM
--            data scenarios and checks that all five trigger algorithms fire
--            at the expected bunch crossings.
--
-- Test cases:
--   TC1  No hit — no trigger expected.
--   TC2  Hits on A-side only — no trigger (MB requires both sides).
--   TC3  Hits on both sides, small charge — MB + VX expected.
--   TC4  Hits on both sides, large charge — MB + VX + SC + C expected.
--   TC5  Hits on both sides within vertex window — MB + VX expected.
--   TC6  Hits on both sides outside vertex window — MB only, no VX.
--   TC7  Laser BC match — Laser bit expected.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_tcm.all;

entity tb_trigger_processor is
end entity tb_trigger_processor;

architecture sim of tb_trigger_processor is

  -- -------------------------------------------------------------------------
  -- Clock and reset
  -- -------------------------------------------------------------------------
  constant C_CLK_PERIOD : time := 24.951 ns;   -- ~40.079 MHz

  signal clk_bc     : std_logic := '0';
  signal rst        : std_logic := '1';

  -- -------------------------------------------------------------------------
  -- DUT inputs
  -- -------------------------------------------------------------------------
  signal pm_a      : t_pm_data_arr(0 to C_PM_LINKS_A - 1) :=
    (others => C_PM_DATA_ZERO);
  signal pm_c      : t_pm_data_arr(0 to C_PM_LINKS_C - 1) :=
    (others => C_PM_DATA_ZERO);
  signal pm_valid  : std_logic := '0';

  signal bc_id     : std_logic_vector(C_BC_ID_WIDTH   - 1 downto 0) :=
    (others => '0');
  signal orbit_id  : std_logic_vector(C_ORBIT_ID_WIDTH - 1 downto 0) :=
    (others => '0');

  signal reg_in    : t_reg_m2s := C_REG_M2S_ZERO;

  -- -------------------------------------------------------------------------
  -- DUT outputs
  -- -------------------------------------------------------------------------
  signal reg_out   : t_reg_s2m;
  signal trig_out  : t_trigger;
  signal cnt_mb    : unsigned(31 downto 0);
  signal cnt_vx    : unsigned(31 downto 0);
  signal cnt_sc    : unsigned(31 downto 0);
  signal cnt_c     : unsigned(31 downto 0);

  -- -------------------------------------------------------------------------
  -- Amplitude sum outputs (fed into trigger_processor)
  -- -------------------------------------------------------------------------
  signal sum_a_int   : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal sum_c_int   : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal sum_tot_int : unsigned(C_CHARGE_WIDTH - 1 downto 0);
  signal sum_val_int : std_logic;

  -- -------------------------------------------------------------------------
  -- Test infrastructure
  -- -------------------------------------------------------------------------
  signal test_done : boolean := false;
  signal fail_cnt  : natural := 0;

begin

  -- -------------------------------------------------------------------------
  -- Clock generation
  -- -------------------------------------------------------------------------
  clk_bc <= not clk_bc after C_CLK_PERIOD / 2;

  -- -------------------------------------------------------------------------
  -- Amplitude sum instance (feeds into trigger processor)
  -- -------------------------------------------------------------------------
  u_amp_sum : entity work.amplitude_sum
    port map (
      clk       => clk_bc,
      rst       => rst,
      pm_a      => pm_a,
      pm_c      => pm_c,
      in_valid  => pm_valid,
      sum_a     => sum_a_int,
      sum_c     => sum_c_int,
      sum_total => sum_tot_int,
      out_valid => sum_val_int
    );

  -- -------------------------------------------------------------------------
  -- DUT: trigger_processor
  -- -------------------------------------------------------------------------
  u_dut : entity work.trigger_processor
    generic map (
      G_THR_MB_DEF   => 1,
      G_THR_VX_DEF   => 10,       -- ±10 time units = vertex window
      G_THR_SC_DEF   => 16#0400#, -- 1024 — semi-central threshold
      G_THR_C_DEF    => 16#0C00#, -- 3072 — central threshold
      G_LASER_BC_DEF => 100       -- Laser fires at BC 100
    )
    port map (
      clk_bc    => clk_bc,
      rst       => rst,
      pm_a      => pm_a,
      pm_c      => pm_c,
      pm_valid  => pm_valid,
      bc_id     => bc_id,
      orbit_id  => orbit_id,
      sum_total => sum_tot_int,
      sum_valid => sum_val_int,
      reg_in    => reg_in,
      reg_out   => reg_out,
      trig_out  => trig_out,
      cnt_mb    => cnt_mb,
      cnt_vx    => cnt_vx,
      cnt_sc    => cnt_sc,
      cnt_c     => cnt_c
    );

  -- -------------------------------------------------------------------------
  -- Stimulus and checker
  -- -------------------------------------------------------------------------
  p_stim : process

    -- Drive one BC of PM data (pm_valid high for exactly one clock cycle)
    procedure drive_bc (
      charge_a : in natural;
      time_a   : in integer;
      hits_a   : in natural;
      charge_c : in natural;
      time_c   : in integer;
      hits_c   : in natural
    ) is
    begin
      wait until rising_edge(clk_bc);
      for i in 0 to C_PM_LINKS_A - 1 loop
        pm_a(i).charge_sum <= to_unsigned(charge_a / C_PM_LINKS_A,
                                           C_CHARGE_WIDTH);
        pm_a(i).mean_time  <= to_signed(time_a, C_TIME_WIDTH);
        pm_a(i).hit_count  <= to_unsigned(hits_a, C_MULT_WIDTH);
        pm_a(i).side       <= '0';
        pm_a(i).valid      <= '1';
      end loop;
      for i in 0 to C_PM_LINKS_C - 1 loop
        pm_c(i).charge_sum <= to_unsigned(charge_c / C_PM_LINKS_C,
                                           C_CHARGE_WIDTH);
        pm_c(i).mean_time  <= to_signed(time_c, C_TIME_WIDTH);
        pm_c(i).hit_count  <= to_unsigned(hits_c, C_MULT_WIDTH);
        pm_c(i).side       <= '1';
        pm_c(i).valid      <= '1';
      end loop;
      pm_valid <= '1';

      wait until rising_edge(clk_bc);
      for i in pm_a'range loop pm_a(i) <= C_PM_DATA_ZERO; end loop;
      for i in pm_c'range loop pm_c(i) <= C_PM_DATA_ZERO; end loop;
      pm_valid <= '0';
    end procedure drive_bc;

    -- Check: wait for trig_out.valid='1' then verify bits (with 20-BC timeout)
    procedure check_trig (
      desc   : in string;
      exp_mb : in std_logic;
      exp_vx : in std_logic;
      exp_sc : in std_logic;
      exp_c  : in std_logic;
      exp_la : in std_logic
    ) is
    begin
      -- Wait until trigger fires OR timeout after 20 BCs
      wait until trig_out.valid = '1'
           for 20 * C_CLK_PERIOD;

      if trig_out.valid /= '1' then
        -- No trigger asserted
        if exp_mb = '1' or exp_vx = '1' or exp_sc = '1' or
           exp_c = '1'  or exp_la = '1' then
          report "FAIL [" & desc & "]: no trigger asserted (timeout)" severity error;
          fail_cnt <= fail_cnt + 1;
        end if;
        return;
      end if;

      -- Trigger asserted — check each bit
      if trig_out.bits(C_TB_MIN_BIAS)  /= exp_mb then
        report "FAIL [" & desc & "] MB: expected " &
          std_logic'image(exp_mb) & " got " &
          std_logic'image(trig_out.bits(C_TB_MIN_BIAS)) severity error;
        fail_cnt <= fail_cnt + 1;
      end if;
      if trig_out.bits(C_TB_VERTEX)    /= exp_vx then
        report "FAIL [" & desc & "] VX: expected " &
          std_logic'image(exp_vx) & " got " &
          std_logic'image(trig_out.bits(C_TB_VERTEX)) severity error;
        fail_cnt <= fail_cnt + 1;
      end if;
      if trig_out.bits(C_TB_SEMI_CENT) /= exp_sc then
        report "FAIL [" & desc & "] SC: expected " &
          std_logic'image(exp_sc) & " got " &
          std_logic'image(trig_out.bits(C_TB_SEMI_CENT)) severity error;
        fail_cnt <= fail_cnt + 1;
      end if;
      if trig_out.bits(C_TB_CENTRAL)   /= exp_c then
        report "FAIL [" & desc & "] C: expected " &
          std_logic'image(exp_c) & " got " &
          std_logic'image(trig_out.bits(C_TB_CENTRAL)) severity error;
        fail_cnt <= fail_cnt + 1;
      end if;
      if trig_out.bits(C_TB_LASER)     /= exp_la then
        report "FAIL [" & desc & "] LA: expected " &
          std_logic'image(exp_la) & " got " &
          std_logic'image(trig_out.bits(C_TB_LASER)) severity error;
        fail_cnt <= fail_cnt + 1;
      end if;
    end procedure check_trig;

    -- Check that no trigger fires (20-BC window)
    procedure check_no_trig (desc : in string) is
    begin
      wait until trig_out.valid = '1'
           for 20 * C_CLK_PERIOD;
      if trig_out.valid = '1' then
        report "FAIL [" & desc & "]: unexpected trigger fired (bits=" &
          to_hstring(trig_out.bits) & ")" severity error;
        fail_cnt <= fail_cnt + 1;
      end if;
    end procedure check_no_trig;

  begin
    -- Release reset after 10 clock cycles
    rst <= '1';
    for i in 1 to 10 loop wait until rising_edge(clk_bc); end loop;
    rst <= '0';
    wait until rising_edge(clk_bc);

    -- -------------------------------------------------------------------
    -- TC1: No hit — expect no trigger
    -- -------------------------------------------------------------------
    drive_bc(0, 0, 0, 0, 0, 0);
    check_no_trig("TC1 No hit");

    -- -------------------------------------------------------------------
    -- TC2: A-side hits only — expect no trigger
    -- -------------------------------------------------------------------
    drive_bc(256, 5, 4, 0, 0, 0);
    check_no_trig("TC2 A-only");

    -- -------------------------------------------------------------------
    -- TC3: Both sides, small charge (400 < SC thr 1024)
    --      Expect: MB=1, VX=1 (|0 − 0| = 0 ≤ 10), SC=0, C=0
    -- -------------------------------------------------------------------
    drive_bc(200, 0, 4, 200, 0, 4);
    check_trig("TC3 MB small", '1', '1', '0', '0', '0');

    -- -------------------------------------------------------------------
    -- TC4: Both sides, large charge (total = 8192 > C thr 3072)
    --      Expect: MB=1, VX=1, SC=1, C=1
    -- -------------------------------------------------------------------
    drive_bc(4096, 0, 4, 4096, 0, 4);
    check_trig("TC4 MB+SC+C", '1', '1', '1', '1', '0');

    -- -------------------------------------------------------------------
    -- TC5: Within vertex window (|5 − (−5)| = 10 ≤ 10)
    --      Expect: MB=1, VX=1
    -- -------------------------------------------------------------------
    drive_bc(200, 5, 4, 200, -5, 4);
    check_trig("TC5 VX in window", '1', '1', '0', '0', '0');

    -- -------------------------------------------------------------------
    -- TC6: Outside vertex window (|50 − (−50)| = 100 > 10)
    --      Expect: MB=1, VX=0
    -- -------------------------------------------------------------------
    drive_bc(200, 50, 4, 200, -50, 4);
    check_trig("TC6 VX out window", '1', '0', '0', '0', '0');

    -- -------------------------------------------------------------------
    -- TC7: Laser BC match (bc_id = 100)
    --      Expect: MB=1, VX=1, LA=1
    -- -------------------------------------------------------------------
    bc_id <= std_logic_vector(to_unsigned(100, C_BC_ID_WIDTH));
    drive_bc(200, 0, 4, 200, 0, 4);
    check_trig("TC7 Laser", '1', '1', '0', '0', '1');
    bc_id <= (others => '0');

    -- -------------------------------------------------------------------
    -- Final report
    -- -------------------------------------------------------------------
    wait until rising_edge(clk_bc);
    if fail_cnt = 0 then
      report "tb_trigger_processor: ALL TESTS PASSED" severity note;
    else
      report "tb_trigger_processor: " & natural'image(fail_cnt) &
             " TEST(S) FAILED" severity failure;
    end if;

    test_done <= true;
    wait;
  end process p_stim;

  -- Guard: timeout after 5000 clock cycles
  p_timeout : process
  begin
    wait for 5000 * C_CLK_PERIOD;
    if not test_done then
      report "tb_trigger_processor: TIMEOUT" severity failure;
    end if;
    wait;
  end process p_timeout;

end architecture sim;
