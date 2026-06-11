-- =============================================================================
-- Module:  timing_counter
-- Project: CERN ALICE FIT TCM Firmware
-- Brief:   Bunch-crossing and orbit counter, synchronised to the LHC clock.
--
-- The LHC orbit contains 3564 bunch crossings (slots) at 40.079 MHz.
-- BC 0 marks the start of each orbit (BC0 marker from the LHC timing system).
-- The orbit counter wraps at 2^32 (≈ 107 000 orbits per second → wraps after
-- several hours — sufficient for run durations).
--
-- A bc0 input pulse (one clk_bc cycle high, derived from TTC or programmable)
-- resets the BC counter and increments the orbit counter.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_tcm.all;

entity timing_counter is
  port (
    clk_bc   : in  std_logic;
    rst      : in  std_logic;

    -- BC0 synchronisation marker (one clk_bc pulse per orbit)
    bc0      : in  std_logic;

    -- Current bunch-crossing ID (0 – 3563)
    bc_id    : out std_logic_vector(C_BC_ID_WIDTH  - 1 downto 0);

    -- Current orbit ID (free-running 32-bit counter)
    orbit_id : out std_logic_vector(C_ORBIT_ID_WIDTH - 1 downto 0)
  );
end entity timing_counter;

architecture rtl of timing_counter is

  signal bc_cnt    : unsigned(C_BC_ID_WIDTH  - 1 downto 0) := (others => '0');
  signal orbit_cnt : unsigned(C_ORBIT_ID_WIDTH - 1 downto 0) := (others => '0');

begin

  p_count : process(clk_bc)
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        bc_cnt    <= (others => '0');
        orbit_cnt <= (others => '0');
      elsif bc0 = '1' then
        -- BC0 marker: reset BC counter and start new orbit
        bc_cnt    <= (others => '0');
        orbit_cnt <= orbit_cnt + 1;
      elsif bc_cnt = to_unsigned(C_BC_PER_ORBIT - 1, C_BC_ID_WIDTH) then
        -- Auto-wrap at orbit boundary (fallback if no bc0 pulse received)
        bc_cnt    <= (others => '0');
        orbit_cnt <= orbit_cnt + 1;
      else
        bc_cnt <= bc_cnt + 1;
      end if;
    end if;
  end process p_count;

  bc_id    <= std_logic_vector(bc_cnt);
  orbit_id <= std_logic_vector(orbit_cnt);

end architecture rtl;
