---
id: bidirectional-weasel-odin-position
level: task
title: "Bidirectional Weasel-Odin position translation API"
short_code: "WEASEL-T-0011"
created_at: 2026-04-22T17:55:32.649424+00:00
updated_at: 2026-04-22T17:55:32.649424+00:00
parent: WEASEL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0002
---

# Bidirectional Weasel-Odin position translation API

## Parent Initiative

[[WEASEL-I-0002]]

## Objective

Given a populated `Source_Map` (from WEASEL-T-0010), provide two fast functions that translate a `(row, col)` in one file to the corresponding `(row, col)` in the other. This is the hot path of every LSP request the proxy forwards, so it must be O(log n) per call.

## Acceptance Criteria

- [ ] `weasel_to_odin(sm, pos) -> (Position, bool)` returns the generated Odin position for a Weasel position (bool false if the Weasel position is not covered by any span — e.g. interior of a comment).
- [ ] `odin_to_weasel(sm, pos) -> (Position, bool)` is the inverse.
- [ ] Both use binary search over the sorted `entries` slice; no linear scan.
- [ ] Positions inside a span are interpolated column-wise against span start (so the middle of an identifier maps to the middle of the corresponding identifier, not the start).
- [ ] Positions between spans (generated scaffolding like `proc(...) {` that has no Weasel origin) return `false` on the Odin→Weasel direction so the proxy can drop them.
- [ ] Unit tests cover: exact span start, exact span end, interior of span, between spans, before first span, after last span.

## Implementation Notes

### Technical Approach

Binary search `entries` on the appropriate key (`odin_start` or `weasel_start`) to find the containing span, then interpolate the column offset inside the span. The initiative assumes a single-row span in most cases (identifiers don't span lines); still, handle multi-line spans correctly since string literals can.

### Dependencies

- WEASEL-T-0010 (the `Source_Map` type + sorted entries).

### Risk Considerations

The "between spans" case matters more than it looks: if the Odin→Weasel translation silently falls back to the nearest span, `ols` diagnostics for generated-only code (e.g. scaffolding errors) will be reported at unrelated Weasel positions. Returning `false` and letting the proxy drop those responses is safer.

## Status Updates

*To be added during implementation*