-- =============================================================================
-- Module:  gbt_tx
-- Project: CERN ALICE FIT TCM Firmware
-- Brief:   GBT (Gigabit Bidirectional Transceiver) transmitter front-end.
--
-- Assembles a 120-bit GBT frame from the 80-bit user payload and passes it
-- to the Xilinx GTH/GTX transceiver for serialisation at 4.8 Gbps.
--
-- Frame layout (120 bits, MSB first):
--   [119:116]  Header nibble — 0101 for data frames
--   [115:36]   User payload  — 80 bits from frame_in.data
--   [35:0]     EC / SC bits  — set to 0 (not used by data path)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.pkg_tcm.all;

entity gbt_tx is
  port (
    -- Bunch-crossing clock (clk_bc domain, 40 MHz)
    clk_bc   : in  std_logic;

    -- Active-high synchronous reset
    rst      : in  std_logic;

    -- 80-bit user payload to transmit (clk_bc domain)
    frame_in : in  t_gbt_frame;

    -- 120-bit parallel GBT frame to GTH/GTX transceiver
    tx_raw   : out std_logic_vector(119 downto 0);
    tx_valid : out std_logic   -- One-cycle strobe per GBT frame
  );
end entity gbt_tx;

architecture rtl of gbt_tx is

  -- Fixed header for data frames
  constant C_GBT_HEADER : std_logic_vector(3 downto 0) := "0101";
  constant C_GBT_IDLE   : std_logic_vector(3 downto 0) := "0000";
  constant C_EC_SC_BITS : std_logic_vector(35 downto 0) := (others => '0');

begin

  p_frame : process(clk_bc)
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        tx_raw   <= (others => '0');
        tx_valid <= '0';
      else
        if frame_in.valid = '1' then
          -- Assemble data frame
          tx_raw   <= C_GBT_HEADER & frame_in.data & C_EC_SC_BITS;
          tx_valid <= '1';
        else
          -- Send idle frame to maintain link
          tx_raw(119 downto 116) <= C_GBT_IDLE;
          tx_raw(115 downto 0)   <= (others => '0');
          tx_valid <= '1';
        end if;
      end if;
    end if;
  end process p_frame;

end architecture rtl;
