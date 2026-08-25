# AXI-4.0-Design-and-Implementation

A SystemVerilog implementation of an AXI4 master, AXI4 slave, and a multi-slave
AXI interconnect, verified with self-checking testbenches in QuestaSim.

<img width="873" height="710" alt="image" src="https://github.com/user-attachments/assets/d068401c-ca03-4828-a202-a10bfee798df" />


The diagram above shows the full signal-level view of the design: an AXI
master driving all five AXI channels (AW, W, B, AR, R) through the
interconnect, which decodes the address on every transaction and routes it to
the correct slave region.

---

## Repository Structure

```
AXI-4.0-Design-and-Implementation/
├── rtl/                        # Synthesizable design sources
│   ├── axi-fifo.sv                  # Generic FIFO used by write/read data paths
│   ├── axi_address_decoder.sv       # Address-to-slave decoder (interconnect)
│   ├── axi_burst_address_gen.sv     # INCR/WRAP burst address generator
│   ├── axi_interconnect.sv          # 1-master / N-slave AXI interconnect
│   ├── axi_master_ar_ch.sv          # Master: read address channel
│   ├── axi_master_aw_ch.sv          # Master: write address channel
│   ├── axi_master_b_ch.sv           # Master: write response channel
│   ├── axi_master_r_ch.sv           # Master: read data channel
│   ├── axi_master_w_ch.sv           # Master: write data channel
│   ├── axi_master_top.sv            # Master top-level (single-slave config)
│   ├── axi_master_top_1m3s.sv       # Master top-level (1-master/3-slave config)
│   ├── axi_slave_ar_ch.sv           # Slave: read address channel
│   ├── axi_slave_aw_ch.sv           # Slave: write address channel
│   ├── axi_slave_b_ch.sv            # Slave: write response channel
│   ├── axi_slave_mem.sv             # Backing memory (RAM) for the slave
│   ├── axi_slave_r_ch.sv            # Slave: read data channel
│   ├── axi_slave_w_ch.sv            # Slave: write data channel
│   ├── axi_slave_top.sv             # Slave top-level
│   ├── axi_top.sv                   # Full top: 1 master + 1 slave
│   └── axi_top_1m3s.sv              # Full top: 1 master + 3 slaves + interconnect
│
├── testbench/                  # Self-checking testbenches
│   ├── axi_top_tb.sv                # Testbench for the 1-master/1-slave design
│   └── axi_top_1m3s_tb.sv           # Testbench for the 1-master/3-slave design
│
├── scripts/                    # QuestaSim automation scripts
│   ├── run.do                       # Compile + run script (1M1S)
│   ├── wave.do                      # Waveform setup (1M1S)
│   ├── run3m.do                     # Compile + run script (1M3S)
│   └── wave3m.do                    # Waveform setup (1M3S)
│
├── simulation/                 # Simulation work library / compiled outputs
│
├── vcd/                        # Dumped waveform files
│   ├── axi_top_tb.vcd               # Waveform dump, 1M1S run
│   └── axi_top_1m3s_tb.vcd          # Waveform dump, 1M3S run
│
├── Simulation log/             # Saved transcript / simulation logs
│
└── README.md
```

---

## Design Overview

The design is built up in layers:

1. **Channel modules** (`axi_master_*_ch.sv`, `axi_slave_*_ch.sv`) implement
   each of the five AXI4 channels independently on both the master and slave
   side.
2. **Support modules** (`axi_burst_address_gen.sv`, `axi_address_decoder.sv`,
   `axi-fifo.sv`, `axi_slave_mem.sv`) provide burst address generation,
   address decoding, buffering, and backing memory.
3. **Top-level modules** (`axi_master_top.sv`, `axi_slave_top.sv`,
   `axi_top.sv`, `axi_top_1m3s.sv`) wire the channels and support modules
   together into complete, instantiable AXI master/slave/system blocks.
4. **Interconnect** (`axi_interconnect.sv`) arbitrates and routes a single
   master's transactions across multiple slaves based on address region.

Supported features include INCR and WRAP burst types, narrow (sub-word)
transfers with correct `WSTRB` byte-lane masking, outstanding-transaction
tracking via AXI ID, and independent write/read channel operation.

---

## Simulation Runs

Two separate configurations were built and verified:

- **1 Master / 1 Slave (`axi_top.sv` + `axi_top_tb.sv`)**
  Verifies the master and slave directly connected, covering INCR/WRAP
  bursts of varying lengths, narrow transfers, back-to-back writes/reads,
  and concurrent write/read transactions using AXI IDs.
  Run with `scripts/run.do`, view waveforms with `scripts/wave.do`.

- **1 Master / 3 Slaves (`axi_top_1m3s.sv` + `axi_top_1m3s_tb.sv`)**
  Adds the `axi_interconnect` and verifies correct address-based routing
  across three independent slave memory regions, including boundary
  conditions between slave regions and concurrent transactions targeting
  different slaves.
  Run with `scripts/run3m.do`, view waveforms with `scripts/wave3m.do`.

Waveform dumps for both runs are saved under `vcd/`, and simulation
transcripts/logs are saved under `Simulation log/`.

---

## Running the Simulations

From QuestaSim, in the project directory:

```tcl
# 1 master / 1 slave
do scripts/run.do
do scripts/wave.do

# 1 master / 3 slaves
do scripts/run3m.do
do scripts/wave3m.do
```

Each testbench prints a `PASSED`/`FAILED` summary per test case and a final
overall result to the transcript.
