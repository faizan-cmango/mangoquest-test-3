# System Architecture Document — sync_fifo · SAD v0.1

> Machine index: `sad.yaml`. Requirements live in `rtm.yaml`, ports in `idd/`, scenarios in
> `vps.yaml`, risk in `riskmap.yaml`, clocks in `clocks.yaml`.

## 1 Scope and context

A synchronous FIFO between a source and a sink, both with a valid/ready handshake (IDD-S_IN for the input, IDD-M_OUT for the output), on one clock and one synchronous active-low reset (`clocks.yaml`). It preserves order, loses and duplicates nothing, holds exactly 16 words of 32 bits, and accepts and releases a word in the same cycle even when full.

Out of scope: registers, interrupts, almost-full/empty flags, occupancy counts, error flags, clock crossing, power, DFT insertion, board.

**Mutual compatibility of the brief.** Every clause was checked against the others:
- "Simultaneous enqueue and dequeue when full" with "no extra ports" and "exactly 16 words" holds only if `in_ready` is allowed to depend on `out_ready` in the same cycle (ADR-01). It is not a contradiction; it fixes how `in_ready` is defined. The cost is one gate on the path out_ready to in_ready, inside the 30 % input and output delay budget.
- "Stable output during stalls" with "avoid unnecessary stages": a head output stage is needed for the 200 MHz output timing (ADR-04), at no cost in capacity or ports.
- "200 MHz" with the simplest architecture: the first measurement on the proxy does not meet it (section 6.1). That is the one open conflict (AC-1, section 8); the frequency is not changed.

**Assumptions** (defaults, none asked since nothing blocks):
1. Reset gates `in_ready` to 0 and clears `out_valid` and `out_data` to 0 (ADR-02).
2. A word accepted into an empty FIFO shows on the output 1 cycle later, no bypass (ADR-03).
3. `out_ready` may be 1 while `out_valid` is 0; nothing is taken then.
4. The source keeps `in_valid` and `in_data` while `in_ready` is 0 (IDD-S_IN R1).
5. No area, power or pin targets in the brief: these sections of `sad.yaml` are `not_applicable`; area is only reported.

## 2 Block decomposition

One block, `sync_fifo`, owned by Kemi. Two internal parts (ADR-04): a head output stage holding the oldest word and driving `out_valid` and `out_data` straight from flops, and a 15-word circular store for the younger words, with a read select, a write select and an occupancy count. Capacity is 1 + 15 = 16. One block is the simplest cut: the two parts share every control decision.

## 3.1 Transfer and ordering — REQ-3.1.1 … REQ-3.1.4

A transfer happens at a rising `core_clk` edge where valid and ready are both 1 (REQ-3.1.1, REQ-3.1.2). Per edge, with `enq` = in_valid and in_ready, `deq` = out_valid and out_ready:

| Head | Store | enq | deq | Effect at the edge |
|---|---|---|---|---|
| empty | empty | 1 | – | word goes to the head; out_valid 1 next cycle (REQ-3.1.4) |
| full | any | 1 | 0 | word goes to the store tail |
| full | not empty | any | 1 | head takes the store's oldest word; an accepted word goes to the store tail |
| full | empty | 1 | 1 | head takes the accepted word |
| full | empty | 0 | 1 | head becomes empty; out_valid 0 |

Stall: with deq 0 the head is not written, so out_valid and out_data hold (REQ-3.1.3). Sketch, FIFO empty, out_ready 0:

```
edge:      0      1      2      3
in_valid   1      0      0      0
in_ready   1      1      1      1
out_valid  0      1      1      1     (word held until out_ready)
```

## 3.2 Occupancy and capacity — REQ-3.2.1 … REQ-3.2.5

16 words are held when the head and the 15 store words are full. `in_ready` is 1 unless 16 are held and `out_ready` is 0 (REQ-3.2.1, REQ-3.2.2, ADR-01). At 16 held with `out_ready` 1, the head takes the oldest store word and the new word enters the store, so 16 remain (REQ-3.2.3). At 1 to 15 held the same happens without the full condition (REQ-3.2.4). `out_valid` is 1 exactly while at least one word is held (REQ-3.2.5).

## 3.3 Reset — REQ-3.3.1 … REQ-3.3.3

While `rst_n` is 0, `in_ready` is 0 at once (REQ-3.3.1). At a rising edge with `rst_n` 0 the head and store are emptied and `out_valid` and `out_data` go to 0 (REQ-3.3.2, REQ-3.3.3, ADR-02). The store words themselves are not cleared; they are unreachable while the count is 0. Reset release is synchronous.

## 6.1 Performance — REQ-6.1.1, REQ-6.1.2

Timing analysis. Tool `feasibility`, method opensta_liberty (confidence 0.5, pre-layout, ideal clock, tt), on a proxy of the ADR-04 architecture (`docs/feasibility/sync_fifo/sync_fifo.sv`), 200 MHz, input and output delay 30 % of the period:

| Item | Result |
|---|---|
| fmax estimate | 162.9 MHz |
| worst setup slack at 200 MHz | -1.140 ns (VIOLATED) |
| area | 20482 µm² (1136 cells, 75 % sequential) |
| meets target | no |

Worst path: from one store read-select flop through an unbuffered fan-out of 32-bit 15:1 mux to the head flops; clock-to-Q alone is 4.2 ns because one `dfxtp_1` drives hundreds of loads. The input-to-flop and flop-to-output paths (out_ready to in_ready, the head outputs) are not among the worst paths in the report. The miss is therefore a fan-out and mux-structure problem of the store read, not of the architecture's port timing; ADR-05 proposes a one-hot read select replicated per byte lane. This is a proposal, not a measurement: it has not been measured. The proxy is not RTL and the target was not relaxed (AC-1).

## 7 Risk register

See `riskmap.yaml` (R-01, R-02).

## 8 Open items

**Open ArchChallenge AC-1 (target_conflict, blocker):** the proxy misses 200 MHz (162.9 MHz, slack -1.140 ns). Options for the person: (a) accept ADR-05, one-hot replicated read select, same ports and capacity, then re-measure on Kemi's RTL; (b) an errata_major lowering the clock (the brief refuses it; the frequency is not changed by me).

Unresolved decisions: acceptance of ADR-01..ADR-05 (all proposed); whether out_data may be left unreset (saves 32 reset terms; ADR-02 resets it to 0 for a numeric reset value).

Test plan outline: VPS-01..VPS-10 (`vps.yaml`); formal on REQ-3.1.2, REQ-3.2.1, REQ-3.2.2, REQ-3.2.3; scoreboard with random in_valid/out_ready gaps; coverage targets in `riskmap.yaml`.
