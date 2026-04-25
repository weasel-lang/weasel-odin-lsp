---
id: pass-template-props-by-value
level: task
title: "Pass template props by value instead of by pointer"
short_code: "WEASEL-T-0022"
created_at: 2026-04-25T11:58:04.385668+00:00
updated_at: 2026-04-25T12:04:06.490254+00:00
parent: 
blocked_by: []
archived: false

tags:
  - "#task"
  - "#feature"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: NULL
---

# Pass template props by value instead of by pointer

> Implements decision recorded in WEASEL-A-0003.

## Objective

Change the transpiler so that component call sites emit props structs by value rather than by pointer. Currently the transpiler emits `tag(w, &Tag_Props{...})` — this task changes that to `tag(w, Tag_Props{...})` and updates template proc signatures to accept `props: Tag_Props` instead of `props: ^Tag_Props`.

## Backlog Item Details

### Type
- [x] Feature - New functionality or enhancement

### Priority
- [ ] P2 - Medium (nice to have)

### Business Justification
- **User Value**: Generated Odin code is simpler and idiomatic; no heap allocation at call sites.
- **Effort Estimate**: S

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] Transpiler emits `tag(w, Tag_Props{...})` without `&` at component call sites.
- [ ] Generated template proc signatures use `props: Tag_Props` (by value).
- [ ] All corpus golden files updated to reflect the new emit shape.
- [ ] `odin run tests/` passes with no diffs.

## Implementation Notes

### Technical Approach
- In `transpiler/transpile.odin`, find the component call emit path and remove the `&` address-of operator from the props struct literal.
- Find the `Template_Proc` emit path and change the props parameter from pointer type to value type.
- Run `odin run tests/ -- --update` to regenerate golden files, then verify with `odin run tests/`.

### Dependencies
None — self-contained transpiler change.

### Risk Considerations
Low risk. The change is mechanical and fully covered by the corpus test suite.

## Status Updates

### 2026-04-25 — Completed

Changed `_emit_component` in `transpiler/transpile.odin:471`: removed `&` from props struct literal at call sites (`", &"` → `", "`). Ran `odin run tests/ -- --update` to regenerate all 9 corpus golden files (functional changes only in `component_no_children` and `template_proc_calls`). Updated 6 hardcoded expected strings in `transpiler/transpile_test.odin`. All 120 unit tests and 9 corpus tests pass.