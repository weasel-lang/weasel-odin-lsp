---
id: lexer-add-expression-tokens-and
level: task
title: "Lexer: add $() expression tokens and remove keyword lookahead"
short_code: "WEASEL-T-0016"
created_at: 2026-04-24T19:20:45.232629+00:00
updated_at: 2026-04-24T19:37:16.822176+00:00
parent: WEASEL-I-0003
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0003
---

# Lexer: add $() expression tokens and remove keyword lookahead

## Parent Initiative

[[WEASEL-I-0003]]

## Objective

Add `EXPR_OPEN` (`$(`) and `EXPR_CLOSE` (`)`) token types to `transpiler/lexer.odin`. Clarify that `{` and `}` inside element bodies are unambiguously `BLOCK_OPEN` / `BLOCK_CLOSE`. Remove any keyword-lookahead logic that currently peeks inside `{...}` to decide whether the content is an expression or a code block.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] `EXPR_OPEN` token emitted when lexer sees `$(` inside an element body
- [ ] `EXPR_CLOSE` token emitted for the matching `)`
- [ ] `{` / `}` inside element bodies produce `BLOCK_OPEN` / `BLOCK_CLOSE` without any keyword inspection
- [ ] Keyword-lookahead code removed from `transpiler/lexer.odin`
- [ ] Existing `transpiler/lexer_test.odin` tests pass; new tests cover `$(expr)` tokenisation

## Implementation Notes

### Files
- `transpiler/lexer.odin` — add token types, update scanning logic
- `transpiler/lexer_test.odin` — add tests for `$(` / `)` tokens

### Dependencies
None — this is the foundation task; all other tasks depend on it.

## Status Updates

### Implementation complete

**Token_Kind changes (`transpiler/lexer.odin`):**
- Removed `Inline_Expr`
- Added `Expr_Open` — emitted for `$(expr)`; value = inner expression (without `$(` and `)`)
- Added `Expr_Close` — paired positional marker; pos = position of the closing `)`
- Added `Block_Open` — emitted for `{block}`; value = inner content (without `{` and `}`)
- Added `Block_Close` — paired positional marker; pos = position of the closing `}`

**New scanner functions:**
- `_scan_paren_expr` — scans `$(...)`, returns (inner, close_pos)
- `_scan_brace_block` — scans `{...}` in element bodies, returns (inner, close_pos)

**Main scan loop:** `$(` at depth>0 → `Expr_Open`+`Expr_Close`; `{` at depth>0 → `Block_Open`+`Block_Close`. No keyword lookahead anywhere in the lexer (the old lookahead was in the parser's `_is_control_flow`, which is now removed per T-0017 stub).

**Parser stub (`transpiler/parser.odin`):** Minimal update to make the package compile:
- `Inline_Expr` → replaced with `Expr_Open` (→ `Expr_Node`) and `Block_Open` (→ `Odin_Block`)
- `_parse_inline_expr` → renamed `_parse_block_content`; `_is_control_flow` check removed (T-0017 will refine)

**Tests (`transpiler/lexer_test.odin`):**
- All old `Inline_Expr` tests updated to use new token kinds
- Added 9 new tests: `test_expr_simple`, `test_expr_nested_parens`, `test_expr_paren_inside_string`, `test_expr_close_position`, `test_block_simple`, `test_block_with_nested_braces`, `test_block_brace_inside_string`, `test_dollar_sign_in_odin_passthrough`, `test_expr_and_block_mixed`

**Results:** 21/21 lexer tests pass. 7 parser/transpiler tests now fail (expected — they use old `{expr}` expression syntax, to be fixed in T-0017 and T-0021).