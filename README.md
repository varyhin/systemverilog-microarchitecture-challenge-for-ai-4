# SystemVerilog Microarchitecture Challenge for AI No.1 — Solution Report

## 0. Solution by Claude Opus 4.6 (1M context)

### Model and environment

- **Model:** Claude Opus 4.6 (1M context), via Claude Code CLI
- **Simulator:** Icarus Verilog 12.0 (`iverilog -g2012`)
- **Platform:** Linux (WSL2)
- **Code style:** SystemVerilog-2023 (`always_ff`, `always_comb`, `logic`, typed `localparam`, inline loop variables, `function automatic`)
- **Human assistance:** None. No hints on latencies, pipeline structure, or handshakes were provided. The human only issued the initial prompt and approved the plan.

### Time spent

| Phase | Time |
|-------|------|
| Clone repo, read all files (README, challenge.sv, testbench.sv, all arithmetic wrappers, wally_fpu.sv) | ~1 min |
| Analyze submodule latencies from source code | ~2 min |
| Design pipeline architecture and present plan | ~1 min |
| Write solution code (challenge.sv) | ~1 min |
| First simulation — PASS on first attempt | ~1 min |
| Write and run extended testbench (745 checks: zeros, ones, infinities, NaN, subnormals, overflow, cancellation, back-to-back, reset, random) | ~3 min |
| Write and run mutation tests (10/10 detected) | ~3 min |
| **Total** | **~12 min** |

### How the solution was derived

**Step 1 — Analyze the formula.**
The block computes `a ** 5 + 0.3 * b + c` using IEEE 754 double-precision floating-point arithmetic.

**Step 2 — Determine submodule latencies by reading source code.**

The arithmetic wrappers in `arithmetic_block_wrappers/` are thin shells around `wally_fpu` (from the open-source Wally RISC-V CPU). By tracing the pipeline registers inside `wally_fpu.sv`:

- `UpValid` → `VldE` (D/E register, 1 cycle)
- `VldE` → `VldM` (E/M register, 1 cycle)
- `VldM` → `VldW` = `DownValid` (M/W register, 1 cycle)

Base latency = **3 cycles** for `f_mult`, `f_sub` (direct connection to wally_fpu).

`f_add` adds an extra pipeline register stage (`res_r`, `down_valid_r`) after wally_fpu, giving latency = **4 cycles**.

Note: `f_add.sv` contains a bug — two `assign` statements drive the `error` output port (line 18: `assign error = | flags[4:1]` and line 64: `assign error = error_r`). Additionally, `pre_flags` on line 52 is undeclared (should be `flags`). This bug is harmless because `error` is not used in the challenge, but it requires declaring the connected wire as `wire` (not `logic`) in Icarus Verilog to avoid a uwire dual-driver error.

**Step 3 — Design the pipeline.**

The formula `a^5 + 0.3*b + c` decomposes into:

```
Stage 1a (cycle 0→3):  mult1: a × a → a²        [f_mult, latency 3]
Stage 1b (cycle 0→3):  mult2: 0.3 × b → p       [f_mult, latency 3, parallel]
Stage 2  (cycle 3→6):  mult3: a² × a² → a⁴      [f_mult, latency 3]
Stage 3  (cycle 6→9):  mult4: a⁴ × a → a⁵       [f_mult, latency 3]
Stage 4  (cycle 9→13): add1:  a⁵ + p → sum       [f_add,  latency 4]
Stage 5  (cycle 13→17):add2:  sum + c → result   [f_add,  latency 4]
```

Total latency: **17 cycles**, throughput: **1 result/cycle** (fully pipelined).

**Step 4 — Calculate delay lines.**

Operands that are consumed later must be delayed to align with the pipeline stage that needs them:

| Signal | Available at | Needed at | Delay stages |
|--------|-------------|-----------|-------------|
| `a` (for mult4) | cycle 0 | cycle 6 | 6 (`a_delay[0..5]`) |
| `p` = 0.3*b (for add1) | cycle 3 | cycle 9 | 6 (`p_delay[0..5]`) |
| `c` (for add2) | cycle 0 | cycle 13 | 13 (`c_delay[0..12]`) |

**Step 5 — Connect and output.**

Since Challenge #1 has no backpressure (no `arg_rdy`/`res_rdy`), the output is simply:
```systemverilog
assign res_vld = add2_dv;
assign res     = final_result;
```

No FIFO or in-flight counter needed.

### Verification results

**Basic testbench (`testbench.sv`):** PASS

**Extended testbench (`testbench_extended.sv`, 745 checks):**
- Zeros (positive/negative) — PASS
- Simple values (ones, powers of 2) — PASS
- Infinities — PASS
- NaN propagation (quiet and signaling) — PASS
- Subnormals — PASS
- Overflow (large `a` values) — PASS
- Catastrophic cancellation — PASS
- Back-to-back (200 consecutive inputs) — PASS
- Reset during active pipeline — PASS
- Random values (500 inputs) — PASS

**Mutation testing (10/10 detected):**

| Mutation | Result |
|----------|--------|
| M1: `f_add` → `f_sub` for add1 | DETECTED |
| M2: `f_add` → `f_sub` for add2 | DETECTED |
| M3: constant 0.3 → 0.4 | DETECTED |
| M4: `a_delay[5]` → `a_delay[4]` | DETECTED |
| M5: `c_delay[12]` → `c_delay[11]` | DETECTED |
| M6: `p_delay[5]` → `p_delay[4]` | DETECTED |
| M7: a⁴ → a² in mult4 (a³ instead of a⁵) | DETECTED |
| M8: swap sub operands in add2 | DETECTED |
| M9: constant 0.3 → 1.0 | DETECTED |
| M10: skip mult3, feed a² to mult4 (a³) | DETECTED |

### Architecture diagram

```
cycle:  0              3              6              9              13             17
        │              │              │              │              │              │
  a ──→ mult1(a×a) ──→ mult3(a²×a²)─→ mult4(a⁴×a) ─→ add1(a⁵+p) ─→ add2(sum+c) ─→ res
  a ──→ [a_delay ×6] ─────────────────→↑              │              │
  b ──→ mult2(0.3×b)─→ [p_delay ×6] ──────────────────→↑             │
  c ──→ [c_delay ×13]─────────────────────────────────────────────────→↑
```

---

# SystemVerilog Microarchitecture Challenge for AI No.1

This repository contains a challenge to any AI software that claims to
generate Verilog code. The challenge is based on a very typical scenario in
an electronic company: an engineer has to write a pipelined block using a
library of sub-blocks written by somebody else. Then this engineer has to
verify his block using a testbench written by somebody else. He may also
need to figure out the sub-block latencies and handshakes by analyzing the
code, since a lot of code in electronic companies is not sufficiently
documented.

The SystemVerilog Microarchitecture Challenge for AI No.1 is based on the
[SystemVerilog
Homework](https://github.com/verilog-meetup/systemverilog-homework) project
by [Verilog Meetup](https://verilog-meetup.com/). It also uses the source
code of an open-source [Wally CPU](https://github.com/openhwgroup/cvw).

## 1. The Prompt

Finish the code of a pipelined block in the file challenge.sv. The block
computes a formula "a ** 5 + 0.3 * b + c". You are not allowed to implement
your own submodules or functions for the addition, subtraction,
multiplication, division, comparison or getting the square root of
floating-point numbers. For such operations you can only use the modules
from the arithmetic_block_wrappers directory. You are not allowed to change
any other files except challenge.sv. You can check the results by running
the script "simulate". If the script outputs "FAIL" or does not output
"PASS" from the code in the provided testbench.sv by running the provided
script "simulate", your design is not working and is not an answer to the
challenge. Your design must be able to accept a new set of the inputs (a, b
and c) each clock cycle back-to-back and generate the computation results
without any stalls and without requiring empty cycle gaps in the input. The
solution code has to be synthesizable SystemVerilog RTL. A human should not
help AI by tipping anything on latencies or handshakes of the submodules.
The AI has to figure this out by itself by analyzing the code in the
repository directories. Likewise a human should not instruct AI how to build
a pipeline structure since it makes the exercise meaningless.
## 2. The Credits

The list of people who contributed to the SystemVerilog Homework:

1. [Yuri Panchul](https://github.com/yuri-panchul)

2. [Mike Kuskov](https://github.com/unaimillan)

3. [Maxim Kudinov](https://github.com/max-kudinov)

4. [Kiran Jayarama](https://github.com/24x7fpga)

5. [Maxim Trofimov](https://github.com/maxvereschagin)

6. [Alexey Fedorov](https://github.com/32FedorovAlexey)

7. [Konstantin Blokhin](https://github.com/kost-b)

8. [Petr Dynin](https://github.com/PetrDynin)

## 3. The recommended software installation

We tested the Challenge with Icarus Verilog 12.0, but you should be able to
run it with other simulators, such as Synopsys VCS, Cadence Xcelium, Mentor
Questa. However, since we did not test the Challenge under other simulators
yet, we suggest checking the result using Icarus Verilog first. Icarus is
available under Linux, MacOS and Windows, with or without Windows WSL. We
also recommend using Bash, even under Windows without WSL. Git for Windows
includes Bash. You may also need GTKWave or Surfer waveform viewer for
debug. To install the necessary software, do the following:

### 3.1. Debian-derived Linux, Simply Linux or Windows WSL Ubuntu

```bash
sudo apt-get update
sudo apt-get install git iverilog gtkwave surfer
```

If you use other Linux distribution, google how to install Git, Icarus
Verilog, GTKWave and optional Surfer.

Check the version of Icarus is at least 11 and preferably 12.

```bash
iverilog -v
```

If not, [build Icarus Verilog from the source](https://github.com/steveicarus/iverilog).

### 3.2. Windows without WSL

Install [Git for Windows](https://gitforwindows.org/) and [Icarus Verilog for Windows](https://bleyer.org/icarus/iverilog-v12-20220611-x64_setup.exe).

### 3.3. MacOS

Use [brew](https://formulae.brew.sh/formula/icarus-verilog):

```zsh
brew install icarus-verilog
```
