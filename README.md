# CERN ALICE FIT — TCM Board Firmware

FPGA firmware for the **TCM (Trigger and Clock Module)** board of the
[ALICE FIT](https://alice-fit.web.cern.ch/) (Fast Interaction Trigger)
detector at CERN.

## Overview

The TCM board is the central timing and trigger hub of the FIT detector
system.  It:

* Receives the LHC reference clock (40.079 MHz) and distributes it to all
  PM (photo-multiplier) boards.
* Collects charge and timing data from up to 4 A-side and 4 C-side PM boards
  via GBT links at 4.8 Gbps.
* Evaluates five physics-trigger algorithms every bunch crossing (25 ns):
  * **Min-Bias** — ≥1 hit on A-side AND C-side.
  * **Vertex** — Min-Bias AND |time_A − time_C| within a configurable window.
  * **Semi-Central** — Total charge ≥ semi-central threshold.
  * **Central** — Total charge ≥ central threshold (> semi-central).
  * **Laser** — Bunch crossing matches a programmed laser calibration BC.
* Distributes the trigger decision downstream (LVDS) within the same bunch
  crossing.
* Packages event data and sends it to the CRU (Common Readout Unit) via GBT.
* Provides a 32-bit register bank accessible via an IPbus bridge or the GBT
  slow-control channel.

## Hardware Target

| Parameter     | Value                              |
|---------------|------------------------------------|
| FPGA          | Xilinx Kintex UltraScale+  xcku5p  |
| LHC clock     | 40.0789 MHz LVDS                   |
| System clock  | 240.47 MHz (×6 MMCM)               |
| GBT line rate | 4.8 Gbps per link (GTH transceiver)|
| PM links      | 4 A-side + 4 C-side               |
| CRU links     | 2 (readout)                        |
| Trigger outs  | 5 LVDS                             |

## Repository Structure

```
tcm/
├── hdl/
│   ├── common/
│   │   ├── pkg_tcm.vhd          # Shared types, constants, utility functions
│   │   ├── timing_counter.vhd   # BC and orbit counters (LHC timing)
│   │   └── pm_decoder.vhd       # GBT → PM data record decoder
│   ├── clocking/
│   │   └── clk_manager.vhd      # IBUFDS + MMCME4_ADV clock synthesis
│   ├── gbt/
│   │   ├── gbt_rx.vhd           # GBT receiver (parallel interface to GTH)
│   │   └── gbt_tx.vhd           # GBT transmitter (parallel interface to GTH)
│   ├── trigger/
│   │   ├── amplitude_sum.vhd    # 3-stage pipelined adder tree (charge sums)
│   │   └── trigger_processor.vhd# Five trigger algorithms, register interface
│   ├── readout/
│   │   └── readout_manager.vhd  # Event FIFO and GBT frame packer for CRU
│   ├── control/
│   │   └── slow_ctrl.vhd        # 32-bit register bank, bus arbitration
│   └── top/
│       └── tcm_top.vhd          # Top-level entity connecting all modules
├── sim/
│   └── tb_trigger_processor.vhd # Trigger algorithm testbench (7 test cases)
├── constraints/
│   └── tcm_pins.xdc             # Xilinx pin/timing constraints
├── scripts/
│   ├── build.tcl                # Vivado batch build (synth + impl + bitstream)
│   └── sim.tcl                  # Vivado batch simulation
└── README.md
```

## Design Details

### Clock Architecture

```
LHC Ref (40.079 MHz LVDS)
     │ IBUFDS
     ▼
  MMCME4_ADV ──────────► clk_sys (240.47 MHz)  BUFG
       │ VCO ≈ 961.9 MHz
       └──────────────► clk_bc  (40.079 MHz)   BUFG
```

### Data Pipeline (per bunch crossing, 25 ns)

```
PM data arrives (clk_bc)
        │
    [cycle 0] pm_decoder — extract charge, time, multiplicity per PM
        │
    [cycle 1] Stage 1 — sum multiplicities, compute mean times per side
        │                amplitude_sum stage 1 (pair sums)
        │
    [cycle 2] Stage 2 — compute time difference |t_A − t_C|
        │                amplitude_sum stage 2 (quad sums)
        │
    [cycle 3] Stage 3 — evaluate trigger algorithms
        │                amplitude_sum stage 3 (total sum available)
        │
    trigger_out.valid='1' → LVDS outputs
                          → readout_manager captures event
```

### GBT Frame Format

#### PM → TCM (received from each PM board)

| Bits    | Field       | Width | Description                        |
|---------|-------------|-------|------------------------------------|
| [79:68] | BC ID       | 12 b  | Bunch-crossing ID (cross-check)    |
| [67:52] | Charge sum  | 16 b  | Sum of all channel ADC values      |
| [51:41] | Mean time   | 11 b  | Amplitude-weighted mean, 13 ps/LSB |
| [40:33] | Hit count   | 8 b   | Number of channels above threshold |
| [32:0]  | Reserved    | 33 b  | Channel flags, status              |

#### TCM → PM (broadcast clock + trigger)

| Bits    | Field       | Width | Description         |
|---------|-------------|-------|---------------------|
| [79:68] | BC ID       | 12 b  | Current BC counter  |
| [67:36] | Orbit ID    | 32 b  | Current orbit ID    |
| [35:31] | Trig bits   | 5 b   | Trigger decision    |
| [30:0]  | Reserved    | 31 b  |                     |

#### TCM → CRU (readout)

| Bits    | Field       | Width | Description               |
|---------|-------------|-------|---------------------------|
| [79:68] | BC ID       | 12 b  | Triggered BC              |
| [67:52] | Sum charge A| 16 b  | A-side total charge       |
| [51:36] | Sum charge C| 16 b  | C-side total charge       |
| [35:25] | Mean time A | 11 b  | A-side mean arrival time  |
| [24:14] | Mean time C | 11 b  | C-side mean arrival time  |
| [13:9]  | Trig bits   | 5 b   | Trigger bits fired        |
| [8:1]   | Mult A      | 8 b   | A-side hit multiplicity   |
| [0]     | Mult C MSB  | 1 b   | C-side multiplicity MSB   |

### Register Map

| Address | Name          | R/W | Description                        |
|---------|---------------|-----|------------------------------------|
| 0x00    | CTRL          | R/W | Bit 0: global enable, Bit 1: laser |
| 0x01    | STATUS        | R   | Bit 0: PLL locked, [N:1]: links up |
| 0x10    | THR_MB        | R/W | Min-bias hit threshold             |
| 0x11    | THR_VERTEX    | R/W | Vertex half-window (time units)    |
| 0x12    | THR_SC        | R/W | Semi-central charge threshold      |
| 0x13    | THR_CENT      | R/W | Central charge threshold           |
| 0x14    | LASER_BC      | R/W | Laser bunch-crossing number        |
| 0x15    | VERTEX_WIN    | R/W | Vertex timing half-window          |
| 0x20    | ORBIT_ID      | R   | Current orbit counter              |
| 0x21    | BC_ID         | R   | Current BC counter                 |
| 0x30    | EVENT_CNT     | R   | Total triggered events             |
| 0x40    | TRIG_CNT_MB   | R   | Min-bias trigger count             |
| 0x41    | TRIG_CNT_VX   | R   | Vertex trigger count               |
| 0x42    | TRIG_CNT_SC   | R   | Semi-central trigger count         |
| 0x43    | TRIG_CNT_C    | R   | Central trigger count              |

## Building

### Requirements

* Xilinx Vivado 2023.1 or later (with UltraScale+ device support).
* Xilinx GTH transceiver IP (generate via Vivado IP Catalog and add to the
  project before synthesis — one instance per GBT link).

### Synthesis and Implementation

```bash
vivado -mode batch -source scripts/build.tcl
```

Output bitstream: `build/tcm_top.bit`

### Simulation (Vivado)

```bash
vivado -mode batch -source scripts/sim.tcl
```

### Simulation (GHDL — open source)

```bash
# Compile
ghdl -a --std=08 hdl/common/pkg_tcm.vhd
ghdl -a --std=08 hdl/common/timing_counter.vhd
ghdl -a --std=08 hdl/common/pm_decoder.vhd
ghdl -a --std=08 hdl/gbt/gbt_rx.vhd
ghdl -a --std=08 hdl/gbt/gbt_tx.vhd
ghdl -a --std=08 hdl/trigger/amplitude_sum.vhd
ghdl -a --std=08 hdl/trigger/trigger_processor.vhd
ghdl -a --std=08 hdl/readout/readout_manager.vhd
ghdl -a --std=08 hdl/control/slow_ctrl.vhd
ghdl -a --std=08 hdl/top/tcm_top.vhd
ghdl -a --std=08 sim/tb_trigger_processor.vhd

# Elaborate and run
ghdl -e --std=08 tb_trigger_processor
ghdl -r --std=08 tb_trigger_processor --vcd=build/tb_trigger_processor.vcd

# View waveforms
gtkwave build/tb_trigger_processor.vcd
```

> **Note:** `clk_manager.vhd` instantiates Xilinx UNISIM primitives (IBUFDS,
> MMCME4_ADV, BUFG) which require either the Xilinx UNISIM library or a
> behavioural stub for GHDL simulation.  The remaining RTL modules are
> simulator-agnostic.

## License

Copyright © CERN 2024.  Released under the [CERN Open Hardware Licence v2](https://ohwr.org/cern_ohl_w_v2.txt).
