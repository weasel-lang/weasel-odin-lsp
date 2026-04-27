---
id: add-spread-token-to-lexer
level: task
title: "Add $(...) spread token to lexer"
short_code: "WEASEL-T-0031"
created_at: 2026-04-27T15:41:50.095364+00:00
updated_at: 2026-04-27T16:44:12.943580+00:00
parent: WEASEL-I-0005
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0005
---

# Add $(...) spread token to lexer

## Parent Initiative

[[WEASEL-I-0005]]

## Objective

Teach the lexer in `transpiler/lexer.odin` to distinguish `$(...` from `$(` at the character level and produce a dedicated `Token_Kind` variant (e.g., `.Spread_Expr`) for spread attributes, eliminating any need for parser lookahead.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] A new `Token_Kind` variant `.Spread_Expr` (or similar) is added
- [ ] The lexer detects `$(...` by reading `$`, `(`, `.`, `.`, `.` in sequence before branching
- [ ] The spread token's payload contains the raw expression text (between `$(...` and the matching `)`)
- [ ] `$(` not followed by `...` continues to produce the existing expression token unchanged
- [ ] `odin test transpiler/` passes including any existing lexer unit tests

## Implementation Notes

### Technical Approach
Edit `transpiler/lexer.odin`. The lexer is character-by-character with a state machine. After matching `$` and `(`, peek at the next three characters. If they are `.`, `.`, `.` then consume them and switch into a new state that collects the spread expression until the matching `)`, emitting `.Spread_Expr`. Otherwise fall through to the existing expression-scanning path. Error recovery: if `$(...` is seen but no closing `)` is found before end-of-input, append an error and recover by treating the remainder as the expression text.

### Dependencies
No dependencies on other tasks; this is a foundational change that T-0032 (parser) depends on.

### Risk Considerations
The `$(` and `$(...` cases share the same two-character prefix — the branch must happen after reading the third character. Take care not to consume characters past the branch point in the non-spread path.

## Status Updates

**2026-04-27** — Complete. Added `Attr_Spread` to `Token_Kind` enum in `transpiler/lexer.odin`. Extracted `_scan_paren_content` helper from `_scan_paren_expr` to share the paren-depth-tracking loop. Added `case ch == '$':` in `_scan_element_open`'s attribute loop: detects `$(...` by checking offsets +1..+4, consumes `$(` + `...`, then calls `_scan_paren_content` to get the expression. Invalid `$` in attribute position produces an error and recovers. All 135 unit tests and 9 corpus tests pass.