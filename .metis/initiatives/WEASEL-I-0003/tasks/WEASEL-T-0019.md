---
id: source-maps-adjust-offset
level: task
title: "Source maps: adjust offset arithmetic for new delimiter lengths"
short_code: "WEASEL-T-0019"
created_at: 2026-04-24T19:20:48.803576+00:00
updated_at: 2026-04-24T19:20:48.803576+00:00
parent: WEASEL-I-0003
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0003
---

# Source maps: adjust offset arithmetic for new delimiter lengths

## Parent Initiative

[[WEASEL-I-0003]]

## Objective

Update `transpiler/source_map.odin` so that source map entries for `$()` expressions track the inner expression span, not the `$(` / `)` delimiters. The key change is that `$(` is 2 chars wide (vs the old `{` which was 1), so any offset arithmetic that assumed a 1-char open delimiter needs updating. Block nodes `{}` map similarly to the current code-block mapping and should require minimal changes. Depends on WEASEL-T-0017 (parser nodes).

## Acceptance Criteria

- [ ] Source map entries for `$()` expressions record the inner-expression span (excluding `$(` and `)`)
- [ ] Offset arithmetic updated to account for `$(` being 2 chars wide
- [ ] Block node mapping unchanged in behaviour (only delimiter-length arithmetic reviewed)
- [ ] `transpiler/source_map_test.odin` passes with updated expectations

## Implementation Notes

### Files
- `transpiler/source_map.odin` — fix offset accounting
- `transpiler/source_map_test.odin` — verify span correctness

### Dependencies
- WEASEL-T-0017 (parser nodes carry the spans to be recorded)

## Status Updates

*To be added during implementation*

