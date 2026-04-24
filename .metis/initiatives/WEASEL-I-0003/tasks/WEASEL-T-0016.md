---
id: lexer-add-expression-tokens-and
level: task
title: "Lexer: add $() expression tokens and remove keyword lookahead"
short_code: "WEASEL-T-0016"
created_at: 2026-04-24T19:20:45.232629+00:00
updated_at: 2026-04-24T19:20:45.232629+00:00
parent: WEASEL-I-0003
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0003
---

# Lexer: add $() expression tokens and remove keyword lookahead

## Parent Initiative

[[WEASEL-I-0003]]

## Objective

Add `EXPR_OPEN` (`$(`) and `EXPR_CLOSE` (`)`) token types to `transpiler/lexer.odin`. Clarify that `{` and `}` inside element bodies are unambiguously `BLOCK_OPEN` / `BLOCK_CLOSE`. Remove any keyword-lookahead logic that currently peeks inside `{...}` to decide whether the content is an expression or a code block.

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

*To be added during implementation*