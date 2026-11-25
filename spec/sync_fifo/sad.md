# System Architecture Document — sync_fifo · SAD v0.1

> Machine index: `sad.yaml`. Requirements live in `rtm.yaml`, ports in `idd/`, scenarios in
> `vps.yaml`, risk in `riskmap.yaml`, clocks in `clocks.yaml`.

## 1 Scope and context
A single-clock first-in first-out buffer with valid/ready handshakes on both sides (IDD-S_IN, IDD-M_OUT). Depth, width, clock and reset are as the brief gives them (RTM, IDDs, clocks.yaml). Out of scope: asynchronous crossing, almost-full/empty flags, registers, error reporting, power targets.

**Compatibility check of the brief.** All 18 stated requirements were checked against each other. One pair needs a choice, not a change of the brief: "enqueue and dequeue in the same cycle when full" cannot hold if in_ready is a function of stored occupancy only. It holds when in_ready also follows out_ready in the same cycle (ADR-01); this adds a feed-through but no port and no stage, and capacity stays exactly 16 words. The 200 MHz target is checked in 6.1. No other conflict was found: a registered output stage would add a 17th storage word, and a bypass would add input-to-output paths, so neither is used (ADR-02). No requirement is dropped.

**Assumptions** (defaults, none blocking):
1. A word accepted into an empty FIFO is visible one cycle later; there is no bypass (ADR-02).
2. in_ready and out_valid are 0 while rst_n is 0; out_data is undefined while out_valid is 0 (ADR-03).
3. The upstream need not hold in_valid or in_data when in_ready is 0 (a plain handshake without a stability rule).
4. No area, power or pin-placement target (brief gives none).
5. Reset is held for at least one core_clk edge and changes synchronously with core_clk.

## 2 Block decomposition
One block, `sync_fifo`: a 16-entry circular store of 32-bit words, a write position, a read position and an occupancy count from 0 to 16. Splitting it further adds interfaces without benefit.

## 3.1 Data path behaviour — REQ-3.1.1 … REQ-3.1.7
Write: on an accepting edge (REQ-3.1.2) in_data goes to the entry at the write position, which then advances. Read: out_data is the entry at the read position and out_valid is 1 while the count is above 0 (REQ-3.1.4, REQ-3.1.7); the read position advances at a releasing edge. The count rises on a write alone, falls on a read alone and is unchanged on both (REQ-3.1.5). in_ready is 1 when the count is below 16 or out_ready is 1 (REQ-3.1.3, REQ-3.1.6); the count is 16 at most.

```
cycle:      0     1     2     3
in_valid    1     1     1     0
in_ready    1     1     1     1      (FIFO empty at cycle 0)
out_valid   0     1     1     1      (word A visible from cycle 1)
out_ready   1     0     1     1
event       wA    wB    wC+rA rB
```
In cycle 2 the write of C and the read of A share an edge. At 16 words with out_ready 1 the same happens with in_ready 1 (REQ-3.1.6). Because out_valid depends only on stored state and in_ready on state and out_ready, there is no combinational loop.

## 3.2 Reset behaviour — REQ-3.2.1, REQ-3.2.2
While rst_n is 0 the two outputs in_ready and out_valid are forced to 0 and the first edge clears the count and positions; storage is not cleared (ADR-03). After rst_n returns to 1 the FIFO is empty and in_ready is 1 in the first cycle.

## 4.1 Interfaces — REQ-4.1.1
IDD-S_IN carries core_clk, rst_n, in_valid, in_data, in_ready. IDD-M_OUT carries out_valid, out_data, out_ready. No other signal exists.

## 5 Clocks and resets
See `clocks.yaml`: one domain, no crossings.

## 6.1 Timing and performance — REQ-6.1.1
Critical paths: (a) out_ready to in_ready to write enable and count, input delay 30 % plus a few gates; (b) read position to 16:1 mux to out_data with output delay 30 %; (c) count to out_valid. The measured result is below.

Feasibility (proxy `docs/feasibility/sync_fifo/sync_fifo.sv`, method opensta_liberty, confidence 0.5, tt corner, pre-layout): register-to-register fmax estimate 262 MHz (1.184 ns path) against the 200 MHz target; area 19779 um2 (779 cells, information only). **Target missed**: worst setup slack -2.746 ns on the output path to out_data (the 16:1 read mux at the output with a 30 % output delay). Challenge AC-1 (target_conflict) is open; the frequency is not relaxed. Proposal in section 8.

## 7 Risk register
See `riskmap.yaml`.

## 8 Open items
Open ArchChallenges: AC-1 (target_conflict, blocker): the output read path misses 200 MHz by 2.746 ns. Proposed resolution, for a person to decide: ADR-04 (decomposition change, no port or requirement change) keeps the 16-word capacity but holds the oldest word in a head register that drives out_data and out_valid directly, with the other 15 words in the store; the read mux then feeds the head register inside the cycle rather than the port. Alternative: errata_major lowering the frequency, not proposed. A proxy of ADR-04 has not been measured. Decisions proposed for a person to accept: ADR-01, ADR-02, ADR-03.
Open points: (1) confirm no bypass latency is acceptable; (2) confirm out_data may be undefined while out_valid is 0; (3) if the feasibility run misses 200 MHz, propose an ADR to split the read mux, never a lower frequency.
