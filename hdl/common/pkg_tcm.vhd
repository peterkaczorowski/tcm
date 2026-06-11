-- =============================================================================
-- Package: pkg_tcm
-- Project: CERN ALICE FIT TCM (Trigger and Clock Module) Firmware
-- Author:  TCM Firmware Team
-- Brief:   Shared constants, types and utility functions used by all TCM
--          sub-modules.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package pkg_tcm is

  -- ---------------------------------------------------------------------------
  -- Global constants
  -- ---------------------------------------------------------------------------

  -- LHC bunch-crossing frequency (Hz).  Actual value ≈ 40 078 900 Hz.
  constant C_BC_FREQ_HZ        : natural := 40_078_900;

  -- System clock = 6 × BC clock ≈ 240.47 MHz
  constant C_SYS_CLK_MUL      : natural := 6;

  -- GBT user-payload width (bits per bunch crossing)
  constant C_GBT_DATA_WIDTH    : natural := 80;

  -- Number of GBT links to PM boards
  constant C_PM_LINKS_A        : natural := 4;   -- A-side photomultiplier boards
  constant C_PM_LINKS_C        : natural := 4;   -- C-side photomultiplier boards
  constant C_PM_LINKS_TOTAL    : natural := C_PM_LINKS_A + C_PM_LINKS_C;

  -- Number of GBT links to CRU (Common Readout Unit)
  constant C_CRU_LINKS         : natural := 2;

  -- Number of physics-trigger output bits
  constant C_TRIG_BITS         : natural := 5;

  -- ADC / timing data widths
  constant C_ADC_WIDTH         : natural := 12;   -- ADC amplitude resolution
  constant C_TIME_WIDTH        : natural := 11;   -- Timing (HPTDCv2) resolution
  constant C_CHARGE_WIDTH      : natural := 16;   -- Summed charge width
  constant C_MULT_WIDTH        : natural := 8;    -- Hit-multiplicity width

  -- Bunch-crossing and orbit counter widths
  constant C_BC_ID_WIDTH       : natural := 12;   -- 0 – 3563 (LHC orbit)
  constant C_ORBIT_ID_WIDTH    : natural := 32;

  -- Maximum BC count per LHC orbit
  constant C_BC_PER_ORBIT      : natural := 3564;

  -- ---------------------------------------------------------------------------
  -- Trigger bit indices
  -- ---------------------------------------------------------------------------
  constant C_TB_MIN_BIAS       : natural := 0;
  constant C_TB_VERTEX         : natural := 1;
  constant C_TB_SEMI_CENT      : natural := 2;
  constant C_TB_CENTRAL        : natural := 3;
  constant C_TB_LASER          : natural := 4;

  -- ---------------------------------------------------------------------------
  -- Slow-control register addresses (byte-addressed, 8-bit field)
  -- ---------------------------------------------------------------------------
  constant C_REG_CTRL          : std_logic_vector(7 downto 0) := x"00";
  constant C_REG_STATUS        : std_logic_vector(7 downto 0) := x"01";
  constant C_REG_THR_MB        : std_logic_vector(7 downto 0) := x"10";
  constant C_REG_THR_VERTEX    : std_logic_vector(7 downto 0) := x"11";
  constant C_REG_THR_SC        : std_logic_vector(7 downto 0) := x"12";
  constant C_REG_THR_CENT      : std_logic_vector(7 downto 0) := x"13";
  constant C_REG_VERTEX_WIN    : std_logic_vector(7 downto 0) := x"14";
  constant C_REG_ORBIT_ID      : std_logic_vector(7 downto 0) := x"20";
  constant C_REG_BC_ID         : std_logic_vector(7 downto 0) := x"21";
  constant C_REG_EVENT_CNT     : std_logic_vector(7 downto 0) := x"30";
  constant C_REG_TRIG_CNT_MB   : std_logic_vector(7 downto 0) := x"40";
  constant C_REG_TRIG_CNT_VX   : std_logic_vector(7 downto 0) := x"41";
  constant C_REG_TRIG_CNT_SC   : std_logic_vector(7 downto 0) := x"42";
  constant C_REG_TRIG_CNT_C    : std_logic_vector(7 downto 0) := x"43";

  -- ---------------------------------------------------------------------------
  -- Record types
  -- ---------------------------------------------------------------------------

  -- Single GBT frame (parallel, 80-bit user payload + valid flag)
  type t_gbt_frame is record
    data  : std_logic_vector(C_GBT_DATA_WIDTH - 1 downto 0);
    valid : std_logic;
  end record t_gbt_frame;

  constant C_GBT_FRAME_ZERO : t_gbt_frame := (
    data  => (others => '0'),
    valid => '0'
  );

  -- Array of GBT frames (one entry per link)
  type t_gbt_frame_arr is array (natural range <>) of t_gbt_frame;

  -- Aggregated per-PM data (decoded from GBT frame)
  type t_pm_data is record
    charge_sum : unsigned(C_CHARGE_WIDTH - 1 downto 0);
    mean_time  : signed(C_TIME_WIDTH - 1 downto 0);
    hit_count  : unsigned(C_MULT_WIDTH - 1 downto 0);
    side       : std_logic;   -- '0' = A-side, '1' = C-side
    valid      : std_logic;
  end record t_pm_data;

  constant C_PM_DATA_ZERO : t_pm_data := (
    charge_sum => (others => '0'),
    mean_time  => (others => '0'),
    hit_count  => (others => '0'),
    side       => '0',
    valid      => '0'
  );

  -- Array of PM data (all links)
  type t_pm_data_arr is array (natural range <>) of t_pm_data;

  -- Physics trigger output
  type t_trigger is record
    bits     : std_logic_vector(C_TRIG_BITS - 1 downto 0);
    bc_id    : std_logic_vector(C_BC_ID_WIDTH - 1 downto 0);
    orbit_id : std_logic_vector(C_ORBIT_ID_WIDTH - 1 downto 0);
    valid    : std_logic;
  end record t_trigger;

  constant C_TRIGGER_ZERO : t_trigger := (
    bits     => (others => '0'),
    bc_id    => (others => '0'),
    orbit_id => (others => '0'),
    valid    => '0'
  );

  -- Slow-control register bus — split into master-to-slave and slave-to-master
  -- directions to avoid VHDL resolved-signal / multiple-driver issues.

  -- Master → Slave: driven by the bus master (slow_ctrl or IPbus bridge)
  type t_reg_m2s is record
    addr  : std_logic_vector(7 downto 0);
    wdata : std_logic_vector(31 downto 0);
    we    : std_logic;
    re    : std_logic;
  end record t_reg_m2s;

  -- Slave → Master: driven by the addressed peripheral
  type t_reg_s2m is record
    rdata : std_logic_vector(31 downto 0);
    ack   : std_logic;
  end record t_reg_s2m;

  constant C_REG_M2S_ZERO : t_reg_m2s := (
    addr  => (others => '0'),
    wdata => (others => '0'),
    we    => '0',
    re    => '0'
  );

  constant C_REG_S2M_ZERO : t_reg_s2m := (
    rdata => (others => '0'),
    ack   => '0'
  );

  -- Legacy combined alias kept for backward compatibility (do not use for new code)
  type t_reg_bus is record
    addr  : std_logic_vector(7 downto 0);
    wdata : std_logic_vector(31 downto 0);
    we    : std_logic;
    re    : std_logic;
    rdata : std_logic_vector(31 downto 0);
    ack   : std_logic;
  end record t_reg_bus;

  constant C_REG_BUS_ZERO : t_reg_bus := (
    addr  => (others => '0'),
    wdata => (others => '0'),
    we    => '0',
    re    => '0',
    rdata => (others => '0'),
    ack   => '0'
  );

  -- ---------------------------------------------------------------------------
  -- Utility functions
  -- ---------------------------------------------------------------------------

  -- Convert integer to std_logic_vector of specified width
  function to_slv(val : integer; width : natural)
      return std_logic_vector;

  -- Count number of '1' bits (popcount) in a std_logic_vector
  function count_ones(vec : std_logic_vector)
      return unsigned;

  -- Return maximum of two unsigned values
  function max_uns(a, b : unsigned)
      return unsigned;

end package pkg_tcm;

-- =============================================================================
package body pkg_tcm is

  function to_slv(val : integer; width : natural)
      return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(val, width));
  end function;

  function count_ones(vec : std_logic_vector)
      return unsigned is
    variable cnt : unsigned(7 downto 0) := (others => '0');
  begin
    for i in vec'range loop
      if vec(i) = '1' then
        cnt := cnt + 1;
      end if;
    end loop;
    return cnt;
  end function;

  function max_uns(a, b : unsigned)
      return unsigned is
  begin
    if a > b then
      return a;
    else
      return b;
    end if;
  end function;

end package body pkg_tcm;
