---
id: source-map-data-structure-and
level: task
title: "Source map data structure and transpiler emission"
short_code: "WEASEL-T-0010"
created_at: 2026-04-22T17:54:33.388387+00:00
updated_at: 2026-04-22T18:14:55.480346+00:00
parent: WEASEL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/active"


exit_criteria_met: false
initiative_id: WEASEL-I-0002
---

# Source map data structure and transpiler emission

## Parent Initiative

[[WEASEL-I-0002]]

## Objective

Introduce a `Source_Map` data structure to the transpiler and populate it during code generation so every position-bearing token in the generated Odin output carries back-pointers to its originating `.weasel` source span. This is the foundation the LSP proxy relies on to translate coordinates between the two files.

## Acceptance Criteria

## Acceptance Criteria

- [x] `Source_Map` and `Span_Entry` types are defined matching the shape in the initiative: `odin_start`, `odin_end`, `weasel_start`, `weasel_end`.
- [x] The transpiler returns a `Source_Map` alongside the generated Odin string (in memory — no on-disk format).
- [x] Entries are emitted for: procedure names, identifier references, string literals, and element names (the position-bearing output listed in the initiative).
- [x] `entries` slice is sorted by `odin_start` at end of transpilation so downstream lookup can binary-search.
- [x] Unit tests cover a representative `.weasel` fixture and assert span entries land on the right generated-Odin offsets.
- [x] Existing transpiler tests (round-trip suite from WEASEL-T-0008) continue to pass.

## Implementation Notes

### Technical Approach

Thread a `^Source_Map` through the emission code paths that currently write identifiers/literals/element names. At each write, capture the current `(row, col)` in the output buffer before and after writing, pair with the originating Weasel token span, and append a `Span_Entry`. The transpiler tracks output position already for error messages — reuse that counter rather than rescanning the emitted string.

### Dependencies

- Transpiler from WEASEL-I-0001 (completed).
- Token spans from the lexer (WEASEL-T-0001) — already carry `(line, col)`.

### Risk Considerations

Incomplete coverage is the main risk: if a category of emitted token is forgotten, the proxy will silently mistranslate positions for that category. Mitigate by asserting in tests that every LSP-relevant identifier in the fixture produces a span entry.

## Status Updates

### 2026-04-22 — Implementation complete

Source map foundation landed in the transpiler. Summary of changes:

**New file `transpiler/source_map.odin`:**
- `Span_Entry` — `{odin_start, odin_end, weasel_start, weasel_end}` (all `Position`), matching the initiative's spec.
- `Source_Map` — `{entries: [dynamic]Span_Entry}`. Using `[dynamic]` (rather than `[]` as sketched in the initiative) so the struct owns its backing storage; callers can treat it as a slice via `entries[:]`.
- `advance_position(p, text)` — walks bytes from `p` to compute the resulting `Position` (handles newlines). Reused by both the parser (to precompute Weasel positions of template names) and the transpiler's emission cursor.
- `source_map_destroy(m)` — frees `entries`.
- `_sort_entries(m)` — orders entries by `odin_start.offset` so downstream callers can binary-search (used by WEASEL-T-0011).

**Rewritten `transpiler/transpile.odin`:**
- `transpile()` signature changed from `(source, errs)` to `(source, smap, errs)`.
- Internal `_Emitter` struct now threads `sb`, a running `pos` cursor, `^Source_Map`, `^errs`, and the `known`-templates map through every emitter.
- `_write`/`_write_byte` append to the builder *and* advance the cursor — no rescanning needed.
- `_write_tracked(e, s, weasel_start, s_weasel?)` appends `s` and records a `Span_Entry`. `s_weasel` is used when the emitted identifier differs from its Weasel origin (e.g. `Card_Props` derived from `card`).
- Spans are recorded for: procedure names (`Template_Proc.name` / `.name_pos`), parameter lists (`.params` / `.params_pos`), `Expr_Node` identifier references, component tag names (`Element_Node.tag` when `kind == .Component`), derived `*_Props` struct names (mapped back to the originating local tag segment), component attribute names and dynamic-attr expressions, `Odin_Span` passthrough text (in Odin context), and `Odin_Block.head` control-flow preambles.
- Static text inside raw HTML elements is *not* tracked: it lives inside synthetic string literals in the generated Odin and is not a meaningful hover target for the LSP.

**Parser adjustments (`transpiler/parser.odin`):**
- `Template_Proc` gained `name_pos: Position` and `params_pos: Position` so the transpiler can record precise Weasel offsets for the procedure name and parameter list without rescanning the original token text.
- `_Template_Decl` grew internal `name_off` / `params_off` byte offsets that `_parse_file` feeds into `advance_position(tok.pos, …)` to derive the positions.

**Caller updates:**
- `cmd/main.odin` discards the new `smap` return (CLI doesn't need it; arena handles cleanup).
- `tests/main.odin` destroys the map alongside the other per-fixture allocations.
- `transpiler/transpile_test.odin`'s `_spt` helper discards the map so the existing 93 transpile tests keep their original shape.

**New test file `transpiler/source_map_test.odin`** (14 tests):
- `advance_position` ASCII / newline semantics.
- Passthrough Odin span covers full source.
- Procedure name span (at start of file and after a prefix).
- Parameter list span offsets.
- Inline expression spans (plain and dotted).
- Component tag span and synthesised `Card_Props` mapping back to `card`.
- Dynamic attribute expression span.
- `Odin_Block` head span.
- Entries sorted by `odin_start.offset` invariant.
- Fixture-level assertion that `greet`, `name: string`, and `name` all produce entries.

**Verification:**
- `odin test transpiler` — 107 tests pass (93 prior + 14 new).
- `odin run tests/` — all 7 corpus golden files still match byte-for-byte.
- CLI build + smoke-generate on `template_proc.weasel` diffs clean against the golden.

Ready for review.