# =============================================================================
# Constraints: tcm_pins.xdc
# Project:     CERN ALICE FIT TCM Firmware
# Target:      Xilinx Kintex UltraScale+ (xcku5p-ffvb676-2-e or similar)
# Brief:       Pin assignment and I/O standard constraints for the TCM board.
#
# Sections:
#   1. LHC Reference Clock
#   2. Reset
#   3. BC0 Input
#   4. PM A-side GBT Links (MGT)
#   5. PM C-side GBT Links (MGT)
#   6. CRU GBT Links (MGT)
#   7. Trigger Outputs
#   8. Slow-control Bus
#   9. Status LEDs
#  10. Timing Constraints
# =============================================================================

# -----------------------------------------------------------------------------
# 1. LHC Reference Clock — 40.0789 MHz LVDS
#    Note: Connected to dedicated REFCLK input of a clock-capable LVDS pin pair
#          feeding the MMCM reference input.
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN AK17 IOSTANDARD LVDS DIFF_TERM TRUE } \
    [get_ports lhc_clk_p]
set_property -dict { PACKAGE_PIN AK16 IOSTANDARD LVDS DIFF_TERM TRUE } \
    [get_ports lhc_clk_n]

create_clock -name lhc_clk -period 24.951 [get_ports lhc_clk_p]

# -----------------------------------------------------------------------------
# 2. Board reset (active low)
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN AB14 IOSTANDARD LVCMOS18 } \
    [get_ports sys_rst_n]

# -----------------------------------------------------------------------------
# 3. BC0 synchronisation marker
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN AC14 IOSTANDARD LVCMOS18 } \
    [get_ports bc0_in]

# -----------------------------------------------------------------------------
# 4. PM A-side GBT Links — GTH transceivers, Quad 224
#    RX: MGTHRXP/N  TX: MGTHTXP/N  (example Quad 224, channels 0–3)
# -----------------------------------------------------------------------------
# Link 0
set_property -dict { PACKAGE_PIN AB2 } [get_ports {pm_a_rx_p[0]}]
set_property -dict { PACKAGE_PIN AB1 } [get_ports {pm_a_rx_n[0]}]
set_property -dict { PACKAGE_PIN AA4 } [get_ports {pm_a_tx_p[0]}]
set_property -dict { PACKAGE_PIN AA3 } [get_ports {pm_a_tx_n[0]}]
# Link 1
set_property -dict { PACKAGE_PIN AD2 } [get_ports {pm_a_rx_p[1]}]
set_property -dict { PACKAGE_PIN AD1 } [get_ports {pm_a_rx_n[1]}]
set_property -dict { PACKAGE_PIN AC4 } [get_ports {pm_a_tx_p[1]}]
set_property -dict { PACKAGE_PIN AC3 } [get_ports {pm_a_tx_n[1]}]
# Link 2
set_property -dict { PACKAGE_PIN AF2 } [get_ports {pm_a_rx_p[2]}]
set_property -dict { PACKAGE_PIN AF1 } [get_ports {pm_a_rx_n[2]}]
set_property -dict { PACKAGE_PIN AE4 } [get_ports {pm_a_tx_p[2]}]
set_property -dict { PACKAGE_PIN AE3 } [get_ports {pm_a_tx_n[2]}]
# Link 3
set_property -dict { PACKAGE_PIN AH2 } [get_ports {pm_a_rx_p[3]}]
set_property -dict { PACKAGE_PIN AH1 } [get_ports {pm_a_rx_n[3]}]
set_property -dict { PACKAGE_PIN AG4 } [get_ports {pm_a_tx_p[3]}]
set_property -dict { PACKAGE_PIN AG3 } [get_ports {pm_a_tx_n[3]}]

# -----------------------------------------------------------------------------
# 5. PM C-side GBT Links — GTH transceivers, Quad 225
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN AK2 } [get_ports {pm_c_rx_p[0]}]
set_property -dict { PACKAGE_PIN AK1 } [get_ports {pm_c_rx_n[0]}]
set_property -dict { PACKAGE_PIN AJ4 } [get_ports {pm_c_tx_p[0]}]
set_property -dict { PACKAGE_PIN AJ3 } [get_ports {pm_c_tx_n[0]}]

set_property -dict { PACKAGE_PIN AM2 } [get_ports {pm_c_rx_p[1]}]
set_property -dict { PACKAGE_PIN AM1 } [get_ports {pm_c_rx_n[1]}]
set_property -dict { PACKAGE_PIN AL4 } [get_ports {pm_c_tx_p[1]}]
set_property -dict { PACKAGE_PIN AL3 } [get_ports {pm_c_tx_n[1]}]

set_property -dict { PACKAGE_PIN AP2 } [get_ports {pm_c_rx_p[2]}]
set_property -dict { PACKAGE_PIN AP1 } [get_ports {pm_c_rx_n[2]}]
set_property -dict { PACKAGE_PIN AN4 } [get_ports {pm_c_tx_p[2]}]
set_property -dict { PACKAGE_PIN AN3 } [get_ports {pm_c_tx_n[2]}]

set_property -dict { PACKAGE_PIN AR2 } [get_ports {pm_c_rx_p[3]}]
set_property -dict { PACKAGE_PIN AR1 } [get_ports {pm_c_rx_n[3]}]
set_property -dict { PACKAGE_PIN AR4 } [get_ports {pm_c_tx_p[3]}]
set_property -dict { PACKAGE_PIN AR3 } [get_ports {pm_c_tx_n[3]}]

# -----------------------------------------------------------------------------
# 6. CRU GBT Links — GTH transceivers, Quad 226
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN AT2 } [get_ports {cru_rx_p[0]}]
set_property -dict { PACKAGE_PIN AT1 } [get_ports {cru_rx_n[0]}]
set_property -dict { PACKAGE_PIN AT4 } [get_ports {cru_tx_p[0]}]
set_property -dict { PACKAGE_PIN AT3 } [get_ports {cru_tx_n[0]}]

set_property -dict { PACKAGE_PIN AV2 } [get_ports {cru_rx_p[1]}]
set_property -dict { PACKAGE_PIN AV1 } [get_ports {cru_rx_n[1]}]
set_property -dict { PACKAGE_PIN AV4 } [get_ports {cru_tx_p[1]}]
set_property -dict { PACKAGE_PIN AV3 } [get_ports {cru_tx_n[1]}]

# -----------------------------------------------------------------------------
# 7. Trigger outputs — LVDS
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN J16 IOSTANDARD LVDS } [get_ports {trig_out_p[0]}]
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVDS } [get_ports {trig_out_n[0]}]

set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVDS } [get_ports {trig_out_p[1]}]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVDS } [get_ports {trig_out_n[1]}]

set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVDS } [get_ports {trig_out_p[2]}]
set_property -dict { PACKAGE_PIN L15 IOSTANDARD LVDS } [get_ports {trig_out_n[2]}]

set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVDS } [get_ports {trig_out_p[3]}]
set_property -dict { PACKAGE_PIN M15 IOSTANDARD LVDS } [get_ports {trig_out_n[3]}]

set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVDS } [get_ports {trig_out_p[4]}]
set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVDS } [get_ports {trig_out_n[4]}]

# -----------------------------------------------------------------------------
# 8. Slow-control bus (parallel, to IPbus bridge FPGA or processor)
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS18 } [get_ports {sc_addr[0]}]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS18 } [get_ports {sc_addr[1]}]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS18 } [get_ports {sc_addr[2]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS18 } [get_ports {sc_addr[3]}]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS18 } [get_ports {sc_addr[4]}]
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS18 } [get_ports {sc_addr[5]}]
set_property -dict { PACKAGE_PIN AA16 IOSTANDARD LVCMOS18 } [get_ports {sc_addr[6]}]
set_property -dict { PACKAGE_PIN AB16 IOSTANDARD LVCMOS18 } [get_ports {sc_addr[7]}]

set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS18 } [get_ports sc_we]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS18 } [get_ports sc_re]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS18 } [get_ports sc_ack]

# -----------------------------------------------------------------------------
# 9. Status LEDs (active high)
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS18 } [get_ports {led_status[0]}]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS18 } [get_ports {led_status[1]}]
set_property -dict { PACKAGE_PIN Y15 IOSTANDARD LVCMOS18 } [get_ports {led_status[2]}]
set_property -dict { PACKAGE_PIN AA15 IOSTANDARD LVCMOS18 } [get_ports {led_status[3]}]

# -----------------------------------------------------------------------------
# 10. Timing constraints
# -----------------------------------------------------------------------------

# System clock (240 MHz) — generated by MMCM
create_generated_clock -name clk_sys \
    -source [get_pins u_clk_mgr/u_mmcm/CLKIN1] \
    -multiply_by 24 -divide_by 4 \
    [get_pins u_clk_mgr/u_bufg_sys/O]

# BC clock (40 MHz) — generated by MMCM
create_generated_clock -name clk_bc \
    -source [get_pins u_clk_mgr/u_mmcm/CLKIN1] \
    -multiply_by 24 -divide_by 24 \
    [get_pins u_clk_mgr/u_bufg_bc/O]

# Input delay for slow-control bus (relaxed, 10 ns window)
set_input_delay -clock clk_sys -max 5.0 [get_ports {sc_addr[*] sc_wdata[*] sc_we sc_re}]
set_input_delay -clock clk_sys -min 1.0 [get_ports {sc_addr[*] sc_wdata[*] sc_we sc_re}]

# Output delay for trigger outputs (tight, must be within 5 ns of BC edge)
set_output_delay -clock clk_bc -max 3.0 [get_ports {trig_out_p[*] trig_out_n[*]}]
set_output_delay -clock clk_bc -min 0.5 [get_ports {trig_out_p[*] trig_out_n[*]}]

# False paths across clock-domain crossings (clk_bc ↔ clk_sys)
set_false_path -from [get_clocks clk_bc] -to [get_clocks clk_sys]
set_false_path -from [get_clocks clk_sys] -to [get_clocks clk_bc]

# Async path to reset input
set_false_path -from [get_ports sys_rst_n]

# Don't optimise LED registers
set_property DONT_TOUCH TRUE [get_cells -hier -filter {NAME =~ *led*}]
