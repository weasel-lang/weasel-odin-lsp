---
id: handle-spread-attr-in-transpiler
level: task
title: "Handle Spread_Attr in transpiler attribute emission"
short_code: "WEASEL-T-0033"
created_at: 2026-04-27T15:41:52.374177+00:00
updated_at: 2026-04-27T16:53:22.387144+00:00
parent: WEASEL-I-0005
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0005
---

# Handle Spread_Attr in transpiler attribute emission

## Parent Initiative

[[WEASEL-I-0005]]

## Objective

Add a `Spread_Attr` branch in `transpiler/transpile.odin`'s attribute emission loop that calls `host_driver.emit_spread(w, spread.expr)`, completing the end-to-end pipeline from spread syntax in `.weasel` source to generated Odin code.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] `transpile_element` handles `Spread_Attr` by calling `host_driver.emit_spread(w, spread.expr)`
- [ ] Emitted spread calls appear at the correct position relative to surrounding static attribute strings (declaration order preserved)
- [ ] Static attribute strings are split correctly around spreads — e.g., `<div class="p-2" $(...p.attrs)>` emits the open tag string up to the spread, then the spread call, then `>`
- [ ] No source map `Span_Entry` is emitted for spread attrs
- [ ] `odin run tests/` passes (golden files will be added in WEASEL-T-0034)

## Implementation Notes

### Technical Approach
Edit `transpiler/transpile.odin`. In the attribute emission loop, add a type switch branch for `Spread_Attr`. The surrounding raw-string segments need to be split at the spread boundary: collect static attrs into a string up to the first spread, emit it, emit the spread call, then continue with remaining attrs. The simplest approach is to emit each attr segment-by-segment rather than accumulating all static attrs into one string before the spread.

### Dependencies
Depends on WEASEL-T-0030 (driver `emit_spread` field) and WEASEL-T-0032 (`Spread_Attr` AST node). Both must be complete before this compiles.

### Risk Considerations
The current transpiler may accumulate all static attribute strings into a single raw string literal before emitting. If so, the accumulation logic needs to be restructured to emit eagerly at each spread boundary rather than at the end of the attribute list.

## Status Updates

**2026-04-27** — Complete. The `Spread_Attr` branch in `_emit_open_tag` was already in place from T-0032. Cleaned up the stub comment, updated the proc doc comment to mention spread attrs. Added 3 unit tests in `transpile_test.odin`: `test_transpile_spread_attr_only` (verifies `<div` flushed before spread, `>` after), `test_transpile_spread_attr_mixed_static` (static attr folded into flush before spread), `test_transpile_spread_attr_multiple` (two spreads in order, a before b). All 138 unit tests and 9 corpus tests pass.