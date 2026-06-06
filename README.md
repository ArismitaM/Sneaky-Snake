# 🧬 SneakySnake: High-Throughput Pipelined Architecture for Genomic String Matching

A hardware-accelerated FPGA implementation of the **SneakySnake pre-alignment filtering algorithm** for genomic sequence analysis.

This project implements a fully pipelined architecture in **Verilog HDL** that rapidly filters candidate DNA sequence pairs before expensive sequence alignment. The design leverages parallel processing elements, diagonal data propagation, and efficient hardware primitives to achieve high throughput while maintaining filtering accuracy.

---

## Overview

Modern genome sequencing workflows require comparing billions of DNA reads against reference genomes. Performing full sequence alignment on every candidate pair is computationally expensive.

**SneakySnake** is a pre-alignment filter that quickly estimates whether two sequences are likely to align within a given edit distance threshold. By rejecting poor candidates early, it significantly reduces the workload of downstream alignment algorithms.

This project presents a synthesizable FPGA implementation of SneakySnake using:

* Parallel hardware processing
* Deep pipelining
* Bit-vector based maze generation
* Leading Zero Count (LZC) acceleration
* Comparator-tree based maximum escape selection
* Barrel-shifter checkpoint updates

---

## Key Features

✅ Fully synthesizable Verilog implementation

✅ FPGA-oriented pipelined architecture

✅ Parallel evaluation of all alignment shifts

✅ Hardware-efficient LZC computation

✅ Comparator-tree based longest escape detection

✅ Modular and scalable design

✅ Custom testbenches for verification

✅ Vivado synthesis and implementation ready

---

## Hardware Architecture

The design is organized into the following modules:

### 1. Chip Maze Generator

Generates a `(2E + 1) × T` binary maze representing sequence matches and mismatches.

* Match → 0
* Mismatch → 1

Each row corresponds to a possible alignment shift.

**Hardware Equivalent:** XNOR-based comparison network

---

### 2. Leading Zero Counter (LZC)

Determines the maximum contiguous matching region before encountering a mismatch.

**Hardware Equivalent:** Priority Encoder

Input:

```text
000001011
```

Output:

```text
5
```

---

### 3. LZC Comparator Tree

Computes the maximum escape segment among all candidate alignment rows.

**Hardware Equivalent:**

```text
Comparator + Multiplexer Tree
```

Complexity:

```text
O(log₂(2E+1))
```

---

### 4. Barrel Shifter

Updates maze checkpoints after traversing an escape segment.

Operations:

* Discards processed bits
* Removes crossed obstacle
* Prepares data for next pipeline stage

**Hardware Equivalent:** Shift Network

---

### 5. Snake Stage

Combines:

* Chip Maze Generator
* LZC Array
* Comparator Tree
* Barrel Shifter

Each stage performs one routing iteration.

---

### 6. Snake Pipeline

Multiple Snake Stages are connected sequentially.

Responsibilities:

* Traverse multiple obstacles
* Accumulate obstacle counts
* Process a complete T-wide subproblem

---

### 7. Top-Level Controller

Coordinates:

* Sequence loading
* Subproblem scheduling
* Pipeline execution
* Result aggregation
* Accept/Reject decision

Outputs:

```verilog
accept_o
reject_o
done_o
busy_o
```

---

## Pipeline Flow

```text
Reference Sequence
         │
         ▼
 ┌─────────────────┐
 │ Chip Maze Gen   │
 └─────────────────┘
         │
         ▼
 ┌─────────────────┐
 │ LZC Array       │
 └─────────────────┘
         │
         ▼
 ┌─────────────────┐
 │ Comparator Tree │
 └─────────────────┘
         │
         ▼
 ┌─────────────────┐
 │ Barrel Shifter  │
 └─────────────────┘
         │
         ▼
 ┌─────────────────┐
 │ Snake Stage     │
 └─────────────────┘
         │
         ▼
     Pipeline
         │
         ▼
 Accept / Reject
```

---

## Repository Structure

```text
Sneaky-Snake/
│
├── Vivado_files/
│   ├── barrel_shifter.v
│   ├── chip_maze_gen.v
│   ├── lzc.v
│   ├── lzc_comparator_tree.v
│   ├── snake_stage.v
│   ├── snake_pipeline.v
│   ├── snake_on_chip_top.v
│   ├── snake_dataset_tb.v
│   ├── snake_4pairs_tb.v
│   ├── snake_100pairs_tb.v
│   ├── snake_input2_tb.v
│   └── snake_input3_tb.v
│
├── schematic.pdf
├── Sneakysnake_ppt.pptx
├── visualizer_after.py
└── README.md
```

---

## Verification

The design was validated using custom Verilog testbenches:

* 4 sequence-pair dataset
* 100 sequence-pair dataset
* Input dataset validation
* Top-level functional verification

Verification goals:

* Correct obstacle counting
* Proper checkpoint updates
* Pipeline consistency
* Accept/Reject correctness

---

## FPGA Synthesis

Toolchain:

* Xilinx Vivado

The project includes:

* Synthesizable RTL
* Post-synthesis schematic
* Resource utilization reports
* Timing analysis reports

The critical path primarily traverses:

```text
LZC Network
    →
Comparator Tree
    →
Decision Logic
```

as observed in the synthesized design.

---

## Python Visualization

The repository also contains:

```text
visualizer_after.py
```

which provides:

* Chip maze generation
* Routing-path visualization
* Obstacle tracking
* Filtering statistics
* Dataset processing utilities

This allows comparison between the algorithmic model and hardware implementation.

---

## Results

The FPGA architecture demonstrates:

* High-throughput sequence filtering
* Efficient hardware utilization
* Reduced alignment workload
* Scalable pipelined processing

Suitable for:

* Genome read mapping
* DNA sequence analysis
* Bioinformatics accelerators
* FPGA-based genomic computing

---

## Future Work

* Wider processing windows (larger T)
* Multi-core SneakySnake pipelines
* HBM/DDR integrated streaming
* ASIC implementation
* Integration with full alignment accelerators
* Support for longer genomic reads

---

## Authors

**Arismita Mukherjee**

Project developed as part of:

**VLS 731 – VLSI Architecture Design**

International Institute of Information Technology Bangalore

---

## References

A. Alser et al.,

*"SneakySnake: A Fast and Accurate Universal Genome Pre-Alignment Filter for Read Mapping"*

Bioinformatics Hardware Acceleration Research.
