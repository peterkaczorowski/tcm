-- =============================================================================
-- Module:  pm_decoder
-- Project: CERN ALICE FIT TCM Firmware
-- Brief:   Decodes the 80-bit GBT payload received from a PM board into a
--          structured t_pm_data record.
--
-- PM → TCM GBT frame payload layout (80 bits):
--   [79:68]  BC ID        (12 bits) — cross-check with local BC counter
--   [67:52]  Charge sum   (16 bits) — sum of all channel ADC values
--   [51:41]  Mean time    (11 bits, signed 2-complement, units of 13 ps)
--   [40:33]  Hit count    (8 bits)  — number of channels above threshold
--   [32:17]  Flags        (16 bits) — per-channel hit bitmap (first 16 ch)
--   [16:0]   Reserved
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_tcm.all;

entity pm_decoder is
  port (
    clk_bc   : in  std_logic;
    rst      : in  std_logic;

    -- Input GBT frame from one PM link (80-bit parallel, 40 MHz)
    frame_in : in  t_gbt_frame;

    -- Side assignment for this decoder instance
    side     : in  std_logic;   -- '0' = A-side, '1' = C-side

    -- Decoded PM data
    pm_data  : out t_pm_data
  );
end entity pm_decoder;

architecture rtl of pm_decoder is
begin

  p_decode : process(clk_bc)
    variable raw : std_logic_vector(C_GBT_DATA_WIDTH - 1 downto 0);
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        pm_data <= C_PM_DATA_ZERO;
      else
        if frame_in.valid = '1' then
          raw := frame_in.data;

          pm_data.charge_sum <= unsigned(raw(67 downto 52));
          pm_data.mean_time  <= signed(raw(51 downto 41));
          pm_data.hit_count  <= unsigned(raw(40 downto 33));
          pm_data.side       <= side;
          pm_data.valid      <= '1';
        else
          pm_data <= C_PM_DATA_ZERO;
        end if;
      end if;
    end if;
  end process p_decode;

end architecture rtl;
