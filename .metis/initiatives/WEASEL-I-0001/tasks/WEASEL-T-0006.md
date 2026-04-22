---
id: implement-transpiler-component
level: task
title: "Implement transpiler: component calls with children proc callback"
short_code: "WEASEL-T-0006"
created_at: 2026-04-21T22:11:42.917418+00:00
updated_at: 2026-04-22T12:38:36.130977+00:00
parent: WEASEL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0001
---

# Implement transpiler: component calls with children proc callback

*This template includes sections for various types of tasks. Delete sections that don't apply to your specific use case.*

## Parent Initiative **[CONDITIONAL: Assigned Task]**

[[WEASEL-I-0001]]

## Objective

Extend the transpiler to emit component template calls for Weasel elements that resolve to template procs via the heuristic in WEASEL-A-0002. When the component has nested children, wrap them in an anonymous `proc(w: io.Writer) -> io.Error` callback as per WEASEL-A-0001.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] Elements resolved as template procs (via the WEASEL-A-0002 heuristic) are emitted as proc calls: `tag_name(w, &Tag_Props{...}) or_return`
- [ ] Dotted names (`ui.card`) are emitted as qualified calls: `ui.card(w, &Card_Props{...}) or_return`
- [ ] Attributes on component tags map to struct fields in a composite literal passed as a pointer: `title="Task"` → `&Card_Props{title = "Task"}`
- [ ] Self-closing component elements (`<tag />`) emit a call with no children argument
- [ ] Component elements with nested children emit an anonymous proc as the last argument: `tag(w, &Tag_Props{...}, proc(w: io.Writer) -> io.Error { ... }) or_return`
- [ ] The nested children inside the anonymous proc are themselves fully transpiled (recursion)
- [ ] Passing child content to a component that has no `<slot />` in its definition is a transpile-time error
- [ ] Blocked by WEASEL-T-0004 (core transpiler)

## Implementation Notes **[CONDITIONAL: Technical Task]**

{Keep for technical tasks, delete for non-technical. Technical details, approach, or important considerations}

### Technical Approach
In the element emitter, apply the three-rule heuristic from WEASEL-A-0002: if the tag resolves to a template proc, emit a proc call instead of raw string writes. Attributes are collected and emitted as a `&Tag_Props{field = value, ...}` composite literal. If the element has children, open an anonymous proc literal `proc(w: io.Writer) -> io.Error {`, recursively emit children, then close with `return nil\n}` and pass it as the final argument, followed by `or_return`.

### Dependencies
WEASEL-T-0004 (core transpiler)

### Risk Considerations
Anonymous proc literals in Odin capture outer variables by reference. If the component is called inside a loop, the loop variable is captured correctly — but the transpiler must ensure the emitted `w` parameter name in the inner proc shadows the outer `w` without conflict.

## Status Updates **[REQUIRED]**

### 2026-04-22 — Implementation complete

Implemented `_emit_component` in `transpiler/transpile.odin` and added 11 new tests in `transpiler/transpile_test.odin`. All 93 tests pass.

**Changes made:**

- Added `import "core:fmt"` to transpile.odin
- In `transpile`: build a `known map[string]bool` (template name → has_slot) pre-pass over the top-level nodes, then thread it through all emitter procs
- Updated signatures of all `@(private = "file")` emitters to accept `known map[string]bool`
- Replaced the `.Component` error stub in `_emit_element` with a call to new `_emit_component`
- Added `_write_props_name`: writes the Props struct name from a tag (e.g. `"ui.card"` → `"Card_Props"`)
- Added `_emit_component`: emits `tag(w[, &Tag_Props{...}][, proc callback]) or_return`

**All acceptance criteria met:**
- Self-closing component → `tag(w) or_return` (no children arg)
- Attrs → `&Tag_Props{field = val, ...}` composite literal
- Static and dynamic attrs both handled
- Dotted names (`ui.card`) → qualified calls with `Card_Props` from last segment
- Children → anonymous `proc(w: io.Writer) -> io.Error { ... return nil }` callback
- Children recursively transpiled
- Slotless-component-with-children → transpile error (for same-file templates via `known` map)