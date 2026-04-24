---
id: transpiler-emit-as-escaped-string
level: task
title: "Transpiler: emit $() as escaped string and {} as verbatim block"
short_code: "WEASEL-T-0018"
created_at: 2026-04-24T19:20:47.900739+00:00
updated_at: 2026-04-24T19:44:12.687339+00:00
parent: WEASEL-I-0003
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0003
---

# Transpiler: emit $() as escaped string and {} as verbatim block

## Parent Initiative

[[WEASEL-I-0003]]

## Objective

Update `transpiler/transpile.odin` to handle the two new node types from the parser. Expression nodes (`$()`) must emit `__weasel_write_escaped_string(<inner_expr>)`. Block nodes (`{}`) must emit the block contents verbatim, interleaving any nested Weasel element emission calls. No changes needed to template signature emission or attribute handling. Depends on WEASEL-T-0017 (parser nodes).

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] Expression node emits `__weasel_write_escaped_string(<inner_expr>)` in generated Odin
- [ ] Block node emits contents verbatim with nested Weasel element calls interleaved correctly
- [ ] Template signature and attribute emission unchanged
- [ ] `transpiler/transpile_test.odin` passes; golden output updated where needed

## Implementation Notes

### Files
- `transpiler/transpile.odin` — handle new AST node types
- `transpiler/transpile_test.odin` — verify emission

### Dependencies
- WEASEL-T-0017 (parser must produce expression/block nodes)

## Status Updates

### 2026-04-24

Transpiler already correctly handles both node types (implemented in T-0016/T-0017 period). Updated stale comments:
- `_emit_node` Expr_Node case: updated from `{` to `$(` reference; noted T-0019 TODO for the +2 offset
- `_emit_odin_block`: removed reference to obsolete "Inline_Expr" terminology

All 120 tests pass.