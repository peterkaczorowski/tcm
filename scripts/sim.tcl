# =============================================================================
# Script:  sim.tcl
# Project: CERN ALICE FIT TCM Firmware
# Brief:   Vivado simulation script — compiles all HDL and runs the trigger
#          processor testbench with full waveform logging.
#
# Usage (from project root):
#   vivado -mode batch -source scripts/sim.tcl
#
# Alternative using GHDL (open-source VHDL simulator):
#   See the README for GHDL simulation instructions.
# =============================================================================

set root_dir [file dirname [file normalize [info script]]]/..

# Source files in compilation order
set hdl_files {
    hdl/common/pkg_tcm.vhd
    hdl/common/timing_counter.vhd
    hdl/common/pm_decoder.vhd
    hdl/clocking/clk_manager.vhd
    hdl/gbt/gbt_rx.vhd
    hdl/gbt/gbt_tx.vhd
    hdl/trigger/amplitude_sum.vhd
    hdl/trigger/trigger_processor.vhd
    hdl/readout/readout_manager.vhd
    hdl/control/slow_ctrl.vhd
    hdl/top/tcm_top.vhd
    sim/tb_trigger_processor.vhd
}

# Create simulation project
create_project sim_tcm /tmp/sim_tcm -part xcku5p-ffvb676-2-e -force
set_property target_language VHDL [current_project]

foreach f $hdl_files {
    add_files -norecurse [file normalize "$root_dir/$f"]
}
set_property file_type "VHDL 2008" [get_files *.vhd]
set_property top tb_trigger_processor [get_filesets sim_1]

# Run simulation
launch_simulation
run -all
close_sim
