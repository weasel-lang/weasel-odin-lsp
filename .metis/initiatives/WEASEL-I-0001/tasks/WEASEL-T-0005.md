---
id: implement-transpiler-static-and
level: task
title: "Implement transpiler: static and dynamic attribute handling"
short_code: "WEASEL-T-0005"
created_at: 2026-04-21T22:11:39.552179+00:00
updated_at: 2026-04-22T12:25:21.908931+00:00
parent: WEASEL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0001
---

# Implement transpiler: static and dynamic attribute handling

*This template includes sections for various types of tasks. Delete sections that don't apply to your specific use case.*

## Parent Initiative **[CONDITIONAL: Assigned Task]**

[[WEASEL-I-0001]]

## Objective

Extend the transpiler to handle element attributes — both static string values and dynamic Weasel expressions — emitting them correctly as part of the HTML string or as Odin code.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] Static attributes (`attr="value"`) are folded into the opening HTML string literal: `<tag attr="value">`
- [ ] Dynamic attributes (`attr={expr}`) split the string: `__weasel_write_raw_string(w, "<tag attr=\"")`, emit expr via `fmt.wprint`, then `__weasel_write_raw_string(w, "\">")`
- [ ] Mixed static and dynamic attributes on the same element are handled correctly
- [ ] Attribute values are emitted in source order
- [ ] Dynamic attribute expressions are emitted verbatim without validation

## Implementation Notes **[CONDITIONAL: Technical Task]**

{Keep for technical tasks, delete for non-technical. Technical details, approach, or important considerations}

### Technical Approach
In the element open-tag emitter, iterate attributes in order. Accumulate a string buffer for the opening tag; when a dynamic attribute is encountered, flush the buffer as a `__weasel_write_raw_string` call, emit the dynamic value, then continue accumulating.

### Dependencies
WEASEL-T-0004 (core transpiler)

### Risk Considerations
Dynamic attribute values need to be written as strings — the exact emit helper (`fmt.wprint`, `fmt.wprintf`, or a dedicated `__weasel_write_attr`) is an open choice that may affect the runtime support library.

## Status Updates **[REQUIRED]**

### 2026-04-22 — Implementation complete

**Approach**: Added `_emit_open_tag` and `_flush_pending` helpers in `transpiler/transpile.odin`. Modified `_emit_raw_element` to delegate open-tag emission to `_emit_open_tag` for both void and non-void elements.

**Implementation details**:
- `_emit_open_tag(sb, tag, attrs, self_close)` accumulates raw HTML in a `pending` builder. Static and boolean attrs are folded in directly. On each dynamic attr, it flushes pending as `__weasel_write_raw_string`, emits `fmt.wprint(w, expr)`, then resumes accumulation from the closing `"`. The final pending (including `>` or `/>`) is flushed at the end.
- `_flush_pending` writes `__weasel_write_raw_string(w, "...") or_return` using `_write_string_literal_content` to properly escape the accumulated HTML content for Odin string literals.
- All acceptance criteria covered: static attrs folded, dynamic attrs split, mixed attrs, source order, verbatim expressions.

**Tests added** (8 new tests in `transpiler/transpile_test.odin`):
- `test_transpile_static_attr_folded_into_open_tag`
- `test_transpile_multiple_static_attrs`
- `test_transpile_dynamic_attr_splits_string`
- `test_transpile_dynamic_attr_ordering`
- `test_transpile_mixed_static_and_dynamic_attrs`
- `test_transpile_static_after_dynamic_attr`
- `test_transpile_void_element_with_static_attr`
- `test_transpile_void_element_with_dynamic_attr`
- `test_transpile_dynamic_attr_expr_verbatim`

All 82 tests pass.