---
id: bidirectional-weasel-odin-position
level: task
title: "Bidirectional Weasel-Odin position translation API"
short_code: "WEASEL-T-0011"
created_at: 2026-04-22T17:55:32.649424+00:00
updated_at: 2026-04-22T18:51:23.185928+00:00
parent: WEASEL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0002
---

# Bidirectional Weasel-Odin position translation API

## Parent Initiative

[[WEASEL-I-0002]]

## Objective

Given a populated `Source_Map` (from WEASEL-T-0010), provide two fast functions that translate a `(row, col)` in one file to the corresponding `(row, col)` in the other. This is the hot path of every LSP request the proxy forwards, so it must be O(log n) per call.

## Acceptance Criteria

## Acceptance Criteria

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

### 2026-04-22 — Implementation complete

Implemented `weasel_to_odin` and `odin_to_weasel` in `transpiler/source_map.odin`.

**Design**

- Extended `Source_Map` with a second sorted view `weasel_sorted: [dynamic]Span_Entry` — a copy of `entries` sorted by `weasel_start.offset`. `entries` remains sorted by `odin_start.offset` as before. Both slices are populated by `_sort_entries` at the end of `transpile()`.
- `source_map_destroy` frees both slices. Safe on zero value.
- Both lookup functions share a single `_find_span` helper that binary-searches the appropriate slice for the first entry whose end offset exceeds the target, then verifies `start.offset <= target`. Half-open semantics: a cursor on `end.offset` is NOT inside the span and resolves to the next adjacent span (if any) or returns false.
- Interpolation uses `_interpolate`: `delta_offset` carries byte-for-byte. On the same line as `src_start`, column is linearly interpolated. On later lines (multi-line passthrough) the line delta is carried and `col` from the input is preserved — exact for byte-identical spans.

**Files changed**

- `transpiler/source_map.odin` — added `weasel_sorted` field, `odin_to_weasel`, `weasel_to_odin`, private `_find_span` and `_interpolate` helpers; updated `_sort_entries` and `source_map_destroy`.
- `transpiler/source_map_translate_test.odin` (new) — 17 unit tests covering: exact span start, exact span end (with and without adjacent successor), interior, between spans, before first, after last, empty map, multi-line passthrough, shared Weasel origin, and an end-to-end round-trip via `transpile()`.

**Acceptance criteria**

- [x] `weasel_to_odin(sm, pos) -> (Position, bool)` — implemented; false when pos is not covered by any span.
- [x] `odin_to_weasel(sm, pos) -> (Position, bool)` — implemented; inverse.
- [x] Both use binary search (`_find_span`) — O(log n), no linear scan.
- [x] Column-wise interpolation inside spans (`_interpolate`).
- [x] Between-span positions on Odin→Weasel return false (so the proxy can drop ols responses that have no Weasel origin).
- [x] Unit tests cover the required cases.

**Test results**

- `odin test transpiler/` — 124 passed, 0 failed (17 new tests).
- `odin run tests/` (golden corpus) — 7 passed, 0 failed; no regression in existing source-map emission.
- `odin build cmd/` — clean.