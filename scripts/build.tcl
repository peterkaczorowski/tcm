# =============================================================================
# Script:  build.tcl
# Project: CERN ALICE FIT TCM Firmware
# Brief:   Vivado build script — creates project, adds sources, synthesises,
#          implements and generates a bitstream for the TCM board.
#
# Usage (from project root):
#   vivado -mode batch -source scripts/build.tcl
#
# Output:
#   build/tcm_top.bit   — programming bitstream
#   build/tcm_top.ltx   — ILA probe description (if ILAs present)
# =============================================================================

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------
set project_name  "tcm"
set top_module    "tcm_top"
set part          "xcku5p-ffvb676-2-e"   ;# Kintex UltraScale+
set build_dir     "[file dirname [file normalize [info script]]]/../build"

# Source file lists (relative to project root)
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
}

set sim_files {
    sim/tb_trigger_processor.vhd
}

set xdc_files {
    constraints/tcm_pins.xdc
}

# -----------------------------------------------------------------------------
# Create project
# -----------------------------------------------------------------------------
file mkdir $build_dir
create_project $project_name $build_dir -part $part -force

set_property target_language VHDL [current_project]
set_property default_lib work   [current_project]

# -----------------------------------------------------------------------------
# Add HDL sources
# -----------------------------------------------------------------------------
set root_dir [file dirname [file normalize [info script]]]/..

foreach f $hdl_files {
    add_files -norecurse [file normalize "$root_dir/$f"]
}

set_property file_type "VHDL 2008" [get_files *.vhd]

# Set top-level module
set_property top $top_module [current_fileset]

# -----------------------------------------------------------------------------
# Add simulation sources
# -----------------------------------------------------------------------------
foreach f $sim_files {
    add_files -fileset sim_1 -norecurse [file normalize "$root_dir/$f"]
}
set_property top tb_trigger_processor [get_filesets sim_1]

# -----------------------------------------------------------------------------
# Add constraints
# -----------------------------------------------------------------------------
foreach f $xdc_files {
    add_files -fileset constrs_1 -norecurse [file normalize "$root_dir/$f"]
}

# -----------------------------------------------------------------------------
# Synthesis settings
# -----------------------------------------------------------------------------
set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} \
    -value {-verbose} \
    -objects [get_runs synth_1]

# -----------------------------------------------------------------------------
# Implementation settings
# -----------------------------------------------------------------------------
set_property strategy "Performance_ExplorePostRoutePhysOpt" [get_runs impl_1]

# -----------------------------------------------------------------------------
# Run synthesis
# -----------------------------------------------------------------------------
puts "INFO: Starting synthesis ..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if { [get_property PROGRESS [get_runs synth_1]] != "100%" } {
    error "Synthesis failed — check synth_1.log for details."
}

# -----------------------------------------------------------------------------
# Run implementation
# -----------------------------------------------------------------------------
puts "INFO: Starting implementation ..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if { [get_property PROGRESS [get_runs impl_1]] != "100%" } {
    error "Implementation failed — check impl_1.log for details."
}

# -----------------------------------------------------------------------------
# Copy outputs
# -----------------------------------------------------------------------------
file copy -force \
    [file normalize "$build_dir/$project_name.runs/impl_1/${top_module}.bit"] \
    [file normalize "$build_dir/${top_module}.bit"]

puts "INFO: Build complete.  Bitstream: $build_dir/${top_module}.bit"
