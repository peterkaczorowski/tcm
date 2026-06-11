-- =============================================================================
-- Module:  clk_manager
-- Project: CERN ALICE FIT TCM Firmware
-- Brief:   Clock management — generates system and bunch-crossing clocks from
--          the 40.0789 MHz LHC differential reference clock.
--
-- Implementation notes:
--   * Targets Xilinx UltraScale+ / 7-series FPGAs.
--   * IBUFDS receives the LVDS LHC clock.
--   * MMCME4_ADV (or MMCME2_ADV for 7-series) synthesises:
--       clk_sys  ≈ 240 MHz  (system / data-path clock)
--       clk_bc   ≈ 40 MHz   (bunch-crossing / GBT-frame clock)
--   * BUFG drives global clock networks.
--   * The locked output must be used to hold all downstream logic in reset
--     until the PLL has stabilised.
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

entity clk_manager is
  port (
    -- LHC reference clock — differential LVDS pair (40.0789 MHz)
    clk_ref_p : in  std_logic;
    clk_ref_n : in  std_logic;

    -- Generated clocks
    clk_sys   : out std_logic;   -- System clock  ≈ 240.47 MHz
    clk_bc    : out std_logic;   -- BC clock      ≈ 40.079 MHz

    -- PLL locked indicator (active high)
    locked    : out std_logic
  );
end entity clk_manager;

architecture rtl of clk_manager is

  signal clk_ref_buf  : std_logic;
  signal clk_fb       : std_logic;
  signal clk_fb_buf   : std_logic;
  signal clk_sys_raw  : std_logic;
  signal clk_bc_raw   : std_logic;

begin

  -- ---------------------------------------------------------------------------
  -- Differential input buffer for LHC reference clock
  -- ---------------------------------------------------------------------------
  u_ibufds : IBUFDS
    generic map (
      DIFF_TERM    => TRUE,     -- Internal 100 Ω termination
      IBUF_LOW_PWR => FALSE,
      IOSTANDARD   => "LVDS"
    )
    port map (
      I  => clk_ref_p,
      IB => clk_ref_n,
      O  => clk_ref_buf
    );

  -- ---------------------------------------------------------------------------
  -- MMCM: 40.0789 MHz → VCO 961.9 MHz → clk_sys 240.47 MHz, clk_bc 40.08 MHz
  --
  --   CLKFBOUT_MULT_F = 24.0  → VCO = 40.0789 × 24 = 961.894 MHz
  --   CLKOUT0_DIVIDE_F = 4.0  → clk_sys = 961.894 / 4 = 240.473 MHz
  --   CLKOUT1_DIVIDE   = 24   → clk_bc  = 961.894 / 24 = 40.079 MHz
  --   DIVCLK_DIVIDE    = 1    → f_pfd = 40.079 MHz (within PFD range)
  -- ---------------------------------------------------------------------------
  u_mmcm : MMCME4_ADV
    generic map (
      BANDWIDTH          => "OPTIMIZED",
      CLKFBOUT_MULT_F    => 24.000,
      CLKFBOUT_PHASE     => 0.000,
      CLKIN1_PERIOD      => 24.951,   -- 1 / 40.0789 MHz = 24.951 ns
      CLKOUT0_DIVIDE_F   => 4.000,
      CLKOUT0_PHASE      => 0.000,
      CLKOUT0_DUTY_CYCLE => 0.500,
      CLKOUT1_DIVIDE     => 24,
      CLKOUT1_PHASE      => 0.000,
      CLKOUT1_DUTY_CYCLE => 0.500,
      DIVCLK_DIVIDE      => 1,
      REF_JITTER1        => 0.010,
      STARTUP_WAIT       => FALSE,
      -- Unused outputs
      CLKOUT2_DIVIDE     => 1,
      CLKOUT3_DIVIDE     => 1,
      CLKOUT4_DIVIDE     => 1,
      CLKOUT5_DIVIDE     => 1,
      CLKOUT6_DIVIDE     => 1
    )
    port map (
      CLKIN1    => clk_ref_buf,
      CLKFBIN   => clk_fb_buf,
      CLKOUT0   => clk_sys_raw,
      CLKOUT1   => clk_bc_raw,
      CLKFBOUT  => clk_fb,
      LOCKED    => locked,
      -- Unused / tie-off ports
      PWRDWN    => '0',
      RST       => '0',
      CLKIN2    => '0',
      CLKINSEL  => '1',
      DCLK      => '0',
      DEN       => '0',
      DWE       => '0',
      DADDR     => (others => '0'),
      DI        => (others => '0'),
      PSEN      => '0',
      PSINCDEC  => '0',
      PSCLK     => '0',
      -- Open outputs
      CLKOUT2   => open,
      CLKOUT3   => open,
      CLKOUT4   => open,
      CLKOUT5   => open,
      CLKOUT6   => open,
      CLKFBOUTB => open,
      CLKOUT0B  => open,
      CLKOUT1B  => open,
      CLKOUT2B  => open,
      DO        => open,
      DRDY      => open,
      PSDONE    => open,
      CDDCREQ   => '0',
      CDDCDONE  => open,
      CLKINSTOPPED => open,
      CLKFBSTOPPED => open
    );

  -- ---------------------------------------------------------------------------
  -- Global clock buffers
  -- ---------------------------------------------------------------------------
  u_bufg_fb  : BUFG port map (I => clk_fb,      O => clk_fb_buf);
  u_bufg_sys : BUFG port map (I => clk_sys_raw, O => clk_sys);
  u_bufg_bc  : BUFG port map (I => clk_bc_raw,  O => clk_bc);

end architecture rtl;
