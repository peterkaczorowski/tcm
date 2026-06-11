-- =============================================================================
-- Module:  gbt_rx
-- Project: CERN ALICE FIT TCM Firmware
-- Brief:   GBT (Gigabit Bidirectional Transceiver) receiver front-end.
--
-- The GBT protocol transmits 120-bit frames at the LHC bunch-crossing rate
-- (40.079 MHz), giving a line rate of 4.8 Gbps.  The full-rate serial
-- interface is handled by a Xilinx GTH/GTX transceiver IP core whose parallel
-- (40 MHz) output feeds into this module.
--
-- Frame format (120 bits, MSB first):
--   [119:116]  Header nibble (0101 for data, 0000 for idle)
--   [115:36]   User payload  (80 bits)
--   [35:0]     EC / SC bits  (36 bits, not used by data path)
--
-- This module:
--   1. Detects and aligns to the 4-bit GBT header.
--   2. Extracts the 80-bit user payload.
--   3. Asserts frame_out.valid once the link is locked.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_tcm.all;

entity gbt_rx is
  generic (
    -- Number of consecutive valid headers required before declaring lock
    G_LOCK_THRESHOLD : natural := 32
  );
  port (
    -- System and BC clocks (from clk_manager)
    clk_sys    : in  std_logic;
    clk_bc     : in  std_logic;

    -- Active-high synchronous reset
    rst        : in  std_logic;

    -- 120-bit parallel GBT frame from GTH/GTX transceiver (clk_bc domain)
    rx_raw     : in  std_logic_vector(119 downto 0);
    rx_raw_val : in  std_logic;   -- Valid strobe from transceiver (1/BC)

    -- Decoded user payload output (clk_bc domain)
    frame_out  : out t_gbt_frame;

    -- Link status
    locked     : out std_logic
  );
end entity gbt_rx;

architecture rtl of gbt_rx is

  -- GBT header patterns
  constant C_HDR_DATA  : std_logic_vector(3 downto 0) := "0101";
  constant C_HDR_IDLE  : std_logic_vector(3 downto 0) := "0000";

  -- Field positions within the 120-bit raw frame
  constant C_HDR_HI    : natural := 119;
  constant C_HDR_LO    : natural := 116;
  constant C_PAY_HI    : natural := 115;
  constant C_PAY_LO    : natural := 36;

  signal lock_cnt      : unsigned(5 downto 0) := (others => '0');
  signal locked_int    : std_logic := '0';
  signal header_ok     : std_logic;

begin

  -- ---------------------------------------------------------------------------
  -- Header check
  -- ---------------------------------------------------------------------------
  header_ok <= '1' when rx_raw(C_HDR_HI downto C_HDR_LO) = C_HDR_DATA or
                        rx_raw(C_HDR_HI downto C_HDR_LO) = C_HDR_IDLE
               else '0';

  -- ---------------------------------------------------------------------------
  -- Lock acquisition — assert locked after G_LOCK_THRESHOLD consecutive valid
  -- headers; de-assert immediately on a bad header.
  -- ---------------------------------------------------------------------------
  p_lock : process(clk_bc)
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        lock_cnt   <= (others => '0');
        locked_int <= '0';
      elsif rx_raw_val = '1' then
        if header_ok = '1' then
          if lock_cnt = to_unsigned(G_LOCK_THRESHOLD - 1, lock_cnt'length) then
            locked_int <= '1';
          else
            lock_cnt <= lock_cnt + 1;
          end if;
        else
          lock_cnt   <= (others => '0');
          locked_int <= '0';
        end if;
      end if;
    end if;
  end process p_lock;

  -- ---------------------------------------------------------------------------
  -- Payload extraction
  -- ---------------------------------------------------------------------------
  p_payload : process(clk_bc)
  begin
    if rising_edge(clk_bc) then
      if rst = '1' then
        frame_out <= C_GBT_FRAME_ZERO;
      elsif rx_raw_val = '1' and locked_int = '1' then
        frame_out.data  <= rx_raw(C_PAY_HI downto C_PAY_LO);
        frame_out.valid <= header_ok;
      else
        frame_out.valid <= '0';
      end if;
    end if;
  end process p_payload;

  locked <= locked_int;

end architecture rtl;
