-- =============================================================================
-- Module:  slow_ctrl
-- Project: CERN ALICE FIT TCM Firmware
-- Brief:   Slow-control register bank.
--
-- Acts as the bus master for the internal register bus.  Requests originate
-- from an upstream IPbus bridge (Ethernet) or from the GBT slow-control
-- channel connected to the CRU.  This module decodes the address and
-- arbitrates responses from multiple slaves:
--   • Addresses 0x00–0x01  → handled locally (CTRL, STATUS)
--   • Addresses 0x10–0x1F  → routed to trigger_processor
--   • Addresses 0x20–0x2F  → handled locally (timing counters)
--   • Addresses 0x30–0x3F  → handled locally (event/trigger counters)
--   • Addresses 0x40–0x4F  → routed to trigger_processor (trig counters)
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.pkg_tcm.all;

entity slow_ctrl is
  port (
    clk_sys    : in  std_logic;
    rst        : in  std_logic;

    -- Upstream bus (from IPbus bridge or GBT SC decoder)
    -- Simple strobe-based interface: present addr + data, pulse we/re for 1 cycle
    up_addr    : in  std_logic_vector(7 downto 0);
    up_wdata   : in  std_logic_vector(31 downto 0);
    up_we      : in  std_logic;
    up_re      : in  std_logic;
    up_rdata   : out std_logic_vector(31 downto 0);
    up_ack     : out std_logic;

    -- Register bus to trigger_processor slave
    trig_m2s   : out t_reg_m2s;
    trig_s2m   : in  t_reg_s2m;

    -- Status inputs
    pll_locked : in  std_logic;
    links_up   : in  std_logic_vector(C_PM_LINKS_TOTAL + C_CRU_LINKS - 1 downto 0);

    -- Timing (from timing_counter)
    bc_id      : in  std_logic_vector(C_BC_ID_WIDTH   - 1 downto 0);
    orbit_id   : in  std_logic_vector(C_ORBIT_ID_WIDTH - 1 downto 0);

    -- Readout statistics (from readout_manager)
    event_cnt  : in  unsigned(31 downto 0);

    -- Trigger counters (from trigger_processor)
    cnt_mb     : in  unsigned(31 downto 0);
    cnt_vx     : in  unsigned(31 downto 0);
    cnt_sc     : in  unsigned(31 downto 0);
    cnt_c      : in  unsigned(31 downto 0);

    -- Configuration outputs
    global_en  : out std_logic;
    laser_en   : out std_logic
  );
end entity slow_ctrl;

architecture rtl of slow_ctrl is

  signal ctrl_reg   : std_logic_vector(31 downto 0) := (others => '0');

  -- Route commands to trigger_processor
  signal trig_addr  : std_logic;   -- '1' when address targets trigger slave

begin

  global_en <= ctrl_reg(0);
  laser_en  <= ctrl_reg(1);

  -- Address decode: trigger_processor owns 0x10–0x1F and 0x40–0x4F
  trig_addr <= '1' when (up_addr(7 downto 4) = x"1" or
                          up_addr(7 downto 4) = x"4")
               else '0';

  -- Forward bus commands to trigger_processor
  trig_m2s.addr  <= up_addr;
  trig_m2s.wdata <= up_wdata;
  trig_m2s.we    <= up_we and trig_addr;
  trig_m2s.re    <= up_re and trig_addr;

  p_regs : process(clk_sys)
  begin
    if rising_edge(clk_sys) then
      if rst = '1' then
        ctrl_reg  <= (others => '0');
        up_rdata  <= (others => '0');
        up_ack    <= '0';
      else
        up_ack   <= '0';
        up_rdata <= (others => '0');

        -- Acknowledge from trigger_processor slave
        if trig_s2m.ack = '1' then
          up_rdata <= trig_s2m.rdata;
          up_ack   <= '1';
        end if;

        -- Local register write
        if up_we = '1' and trig_addr = '0' then
          up_ack <= '1';
          case up_addr is
            when C_REG_CTRL => ctrl_reg <= up_wdata;
            when others     => null;
          end case;
        end if;

        -- Local register read
        if up_re = '1' and trig_addr = '0' then
          up_ack <= '1';
          case up_addr is
            when C_REG_CTRL =>
              up_rdata <= ctrl_reg;
            when C_REG_STATUS =>
              up_rdata        <= (others => '0');
              up_rdata(0)     <= pll_locked;
              up_rdata(C_PM_LINKS_TOTAL + C_CRU_LINKS downto 1) <=
                links_up;
            when C_REG_ORBIT_ID =>
              up_rdata <= orbit_id;
            when C_REG_BC_ID =>
              up_rdata                           <= (others => '0');
              up_rdata(C_BC_ID_WIDTH - 1 downto 0) <= bc_id;
            when C_REG_EVENT_CNT =>
              up_rdata <= std_logic_vector(event_cnt);
            when C_REG_TRIG_CNT_MB =>
              up_rdata <= std_logic_vector(cnt_mb);
            when C_REG_TRIG_CNT_VX =>
              up_rdata <= std_logic_vector(cnt_vx);
            when C_REG_TRIG_CNT_SC =>
              up_rdata <= std_logic_vector(cnt_sc);
            when C_REG_TRIG_CNT_C  =>
              up_rdata <= std_logic_vector(cnt_c);
            when others =>
              up_rdata <= (others => '0');
          end case;
        end if;
      end if;
    end if;
  end process p_regs;

end architecture rtl;
