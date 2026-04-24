---
id: parser-dispatch-on-vs-in-parse
level: task
title: "Parser: dispatch on $() vs {} in parse_element_body"
short_code: "WEASEL-T-0017"
created_at: 2026-04-24T19:20:46.564794+00:00
updated_at: 2026-04-24T19:41:43.607119+00:00
parent: WEASEL-I-0003
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0003
---

# Parser: dispatch on $() vs {} in parse_element_body

## Parent Initiative

[[WEASEL-I-0003]]

## Objective

Update `parse_element_body` in `transpiler/parser.odin` to dispatch purely on token type: `EXPR_OPEN` → expression node, `BLOCK_OPEN` → weasel block node, `<tag` → child element, text → raw text. Introduce an expression AST node type. Remove the existing heuristic that peeks at the first token inside `{...}` to choose between expression and code block. Depends on WEASEL-T-0016 (lexer tokens).

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] `parse_element_body` dispatches on `EXPR_OPEN` without peeking at token content
- [ ] Expression AST node type introduced and populated with inner expression text/span
- [ ] `BLOCK_OPEN` produces a weasel block node (recursive element parsing within)
- [ ] Old keyword-heuristic code removed from `transpiler/parser.odin`
- [ ] `transpiler/parser_test.odin` updated; new tests for expression node and block node parsing

## Implementation Notes

### Files
- `transpiler/parser.odin` — update dispatch, add expression node type
- `transpiler/parser_test.odin` — extend test coverage

### Dependencies
- WEASEL-T-0016 (lexer must provide `EXPR_OPEN` / `BLOCK_OPEN` tokens)

## Status Updates

### 2026-04-24

**Analysis complete.** The parser dispatching was already implemented as part of T-0016 — `_parse_children`, `_parse_template`, and `_parse_until_eof` all dispatch directly on `Expr_Open` vs `Block_Open` token types. 

What remains:
1. Remove dead code: `_is_control_flow` function (defined but never called in parser.odin)
2. Update parser_test.odin: `{expr}` → `$(expr)` in 3 tests; add 2 new tests
3. Update transpile_test.odin: 4 tests use `{}` for expressions — change to `$()`

7 tests currently failing, all in the `Expr_Node` / `{}` vs `$()` area.

**Changes made:**
- `parser.odin`: removed dead `_is_control_flow` function (14 lines)
- `parser_test.odin`: updated 3 tests to use `$()` syntax; split `test_parse_simple_expr_not_odin_block` into `test_parse_expr_delimiter` + `test_parse_block_delimiter`
- `transpile_test.odin`: updated 5 tests (`inline_expr`, `inline_expr_field_access`, `static_text_mixed_with_expr`, `static_text_ordering`, `component_children_recursive`) to use `$()`

Result: 120 tests, all passing.