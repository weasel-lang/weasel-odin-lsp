---
id: add-spread-attr-ast-node-and-parse
level: task
title: "Add Spread_Attr AST node and parse_element_attributes handling"
short_code: "WEASEL-T-0032"
created_at: 2026-04-27T15:41:51.458981+00:00
updated_at: 2026-04-27T16:50:30.886089+00:00
parent: WEASEL-I-0005
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0005
---

# Add Spread_Attr AST node and parse_element_attributes handling

## Parent Initiative

[[WEASEL-I-0005]]

## Objective

Add a `Spread_Attr` variant to the element attribute union in `transpiler/parser.odin` and update `parse_element_attributes` to recognise `.Spread_Expr` tokens and produce `Spread_Attr` nodes, completing the parser half of the spread pipeline.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] `Spread_Attr :: struct { expr: string }` is defined in the AST (alongside other attribute types)
- [ ] `parse_element_attributes` branches on `.Spread_Expr` and appends a `Spread_Attr` with `expr` set to the raw source text (e.g., `"p.attrs"`)
- [ ] Multiple spread attrs on one element parse correctly (each produces its own `Spread_Attr` node)
- [ ] Spread attrs interleaved with static attrs parse correctly and preserve declaration order
- [ ] `odin test transpiler/` passes

## Implementation Notes

### Technical Approach
Edit `transpiler/parser.odin`. Find the attribute union/variant type and add `Spread_Attr`. In `parse_element_attributes`, add a branch for `.Spread_Expr` token kind that extracts the token's text as `expr` and appends the node. The token text should already contain only the expression (without the `$(...` prefix and `)` suffix) as set by the lexer.

### Dependencies
Depends on WEASEL-T-0031 (the `.Spread_Expr` token must be defined and produced by the lexer).

### Risk Considerations
The `expr` field stores raw source text — no evaluation or validation. If the lexer includes the surrounding punctuation in the token text, strip it here before storing in `expr`.

## Status Updates

**2026-04-27** — Complete. Added `Spread_Attr :: struct { expr, pos }` and `Attr_Node :: union { Attr, Spread_Attr }` to `transpiler/parser.odin`. Changed `Element_Node.attrs` from `[dynamic]Attr` to `[dynamic]Attr_Node`. Updated `_parse_element` to handle `.Attr_Spread` token with `append(&elem.attrs, Attr_Node(Spread_Attr{...}))`. Updated `_emit_open_tag` signature and loop (type switch), `_emit_component` (filters to named attrs only via temp slice), and all parser_test.odin assertions to go through type assertion `.(Attr)`. All 135 unit tests and 9 corpus tests pass.