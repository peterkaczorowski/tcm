-- =============================================================================
-- Module:  amplitude_sum
-- Project: CERN ALICE FIT TCM Firmware
-- Brief:   Pipelined binary-adder-tree that sums the charge (amplitude) values
--          reported by all PM links.
--
-- Fixed topology for C_PM_LINKS_A = C_PM_LINKS_C = 4 (both sides):
--
--   Stage 1 (1 cycle):  pair sums      4 → 2 per side
--   Stage 2 (1 cycle):  quad sums      2 → 1 per side
--   Stage 3 (1 cycle):  side + total   1 → sum_a, sum_c, sum_total
--
--   Total latency: 3 clk_bc cycles
--
-- Outputs arrive aligned; out_valid is the pipelined version of in_valid.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_tcm.all;

entity amplitude_sum is
  generic (
    G_OUT_BITS : natural := C_CHARGE_WIDTH
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;

    pm_a      : in  t_pm_data_arr(0 to C_PM_LINKS_A - 1);
    pm_c      : in  t_pm_data_arr(0 to C_PM_LINKS_C - 1);
    in_valid  : in  std_logic;

    sum_a     : out unsigned(G_OUT_BITS - 1 downto 0);
    sum_c     : out unsigned(G_OUT_BITS - 1 downto 0);
    sum_total : out unsigned(G_OUT_BITS - 1 downto 0);
    out_valid : out std_logic
  );
end entity amplitude_sum;

architecture rtl of amplitude_sum is

  subtype t_word is unsigned(G_OUT_BITS - 1 downto 0);

  -- Stage 1: pair sums (2 per side)
  signal s1_a0, s1_a1 : t_word;
  signal s1_c0, s1_c1 : t_word;

  -- Stage 2: quad sums (1 per side)
  signal s2_a, s2_c   : t_word;

  -- Stage 3: outputs
  signal s3_a, s3_c, s3_total : t_word;

  -- Valid pipeline
  signal v_pipe : std_logic_vector(2 downto 0);

begin

  -- ---------------------------------------------------------------------------
  -- Stage 1 — pair sums
  -- ---------------------------------------------------------------------------
  p_s1 : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        s1_a0 <= (others => '0'); s1_a1 <= (others => '0');
        s1_c0 <= (others => '0'); s1_c1 <= (others => '0');
        v_pipe(0) <= '0';
      else
        v_pipe(0) <= in_valid;

        s1_a0 <= resize(pm_a(0).charge_sum, G_OUT_BITS) +
                 resize(pm_a(1).charge_sum, G_OUT_BITS);
        s1_a1 <= resize(pm_a(2).charge_sum, G_OUT_BITS) +
                 resize(pm_a(3).charge_sum, G_OUT_BITS);

        s1_c0 <= resize(pm_c(0).charge_sum, G_OUT_BITS) +
                 resize(pm_c(1).charge_sum, G_OUT_BITS);
        s1_c1 <= resize(pm_c(2).charge_sum, G_OUT_BITS) +
                 resize(pm_c(3).charge_sum, G_OUT_BITS);
      end if;
    end if;
  end process p_s1;

  -- ---------------------------------------------------------------------------
  -- Stage 2 — quad sums
  -- ---------------------------------------------------------------------------
  p_s2 : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        s2_a <= (others => '0');
        s2_c <= (others => '0');
        v_pipe(1) <= '0';
      else
        v_pipe(1) <= v_pipe(0);
        s2_a <= s1_a0 + s1_a1;
        s2_c <= s1_c0 + s1_c1;
      end if;
    end if;
  end process p_s2;

  -- ---------------------------------------------------------------------------
  -- Stage 3 — side totals and grand total
  -- ---------------------------------------------------------------------------
  p_s3 : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        s3_a     <= (others => '0');
        s3_c     <= (others => '0');
        s3_total <= (others => '0');
        v_pipe(2) <= '0';
      else
        v_pipe(2) <= v_pipe(1);
        s3_a     <= s2_a;
        s3_c     <= s2_c;
        s3_total <= s2_a + s2_c;
      end if;
    end if;
  end process p_s3;

  sum_a     <= s3_a;
  sum_c     <= s3_c;
  sum_total <= s3_total;
  out_valid <= v_pipe(2);

end architecture rtl;
