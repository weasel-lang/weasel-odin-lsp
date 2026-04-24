---
id: parser-dispatch-on-vs-in-parse
level: task
title: "Parser: dispatch on $() vs {} in parse_element_body"
short_code: "WEASEL-T-0017"
created_at: 2026-04-24T19:20:46.564794+00:00
updated_at: 2026-04-24T19:20:46.564794+00:00
parent: WEASEL-I-0003
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0003
---

# Parser: dispatch on $() vs {} in parse_element_body

## Parent Initiative

[[WEASEL-I-0003]]

## Objective

Update `parse_element_body` in `transpiler/parser.odin` to dispatch purely on token type: `EXPR_OPEN` → expression node, `BLOCK_OPEN` → weasel block node, `<tag` → child element, text → raw text. Introduce an expression AST node type. Remove the existing heuristic that peeks at the first token inside `{...}` to choose between expression and code block. Depends on WEASEL-T-0016 (lexer tokens).

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

*To be added during implementation*

