---
id: add-attribute-value-and-attributes
level: task
title: "Add Attribute_Value and Attributes types plus write_spread to runtime.odin"
short_code: "WEASEL-T-0029"
created_at: 2026-04-27T15:41:47.421762+00:00
updated_at: 2026-04-27T16:35:34.333075+00:00
parent: WEASEL-I-0005
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0005
---

# Add Attribute_Value and Attributes types plus write_spread to runtime.odin

## Parent Initiative

[[WEASEL-I-0005]]

## Objective

Define the `Attribute_Value` union type, `Attributes` map type, and `write_spread` proc in `runtime.odin` so that generated Weasel code can serialise an arbitrary attribute bag to HTML output.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] `Attribute_Value :: union { int, bool, string }` is defined in `runtime.odin`
- [ ] `Attributes :: map[string]Attribute_Value` is defined in `runtime.odin`
- [ ] `write_spread` proc iterates the map and emits `key="value"` pairs to an `io.Writer`
- [ ] `bool` true emits as a bare attribute name (e.g., `disabled`); `bool` false is omitted entirely
- [ ] String values are HTML-escaped (same rules as `write_escaped_string`)
- [ ] `int` values are written as decimal strings
- [ ] `odin test transpiler/` passes

## Implementation Notes

### Technical Approach
Edit `runtime.odin`. Add the two type declarations at the top, then add `write_spread` alongside the existing `write_escaped_string` and `write_raw_string` helpers. Iteration order over Odin maps is non-deterministic — document this in a comment so callers know not to rely on attribute ordering.

### Dependencies
No dependencies on other tasks in this initiative; this can be done first.

### Risk Considerations
Map iteration order is non-deterministic in Odin. For correctness this is fine (HTML attributes are unordered), but corpus golden files must not assume a fixed order. The corpus test task (WEASEL-T-0034) should account for this if needed.

## Status Updates

**2026-04-27** — Complete. Added `Attribute_Value` union, `Attributes` map type, and `write_spread` proc to `runtime.odin`. Keys are sorted before emission for deterministic output (important for golden file tests). Used `strconv.write_int` for int formatting to avoid allocations. All 135 transpiler unit tests and 9 corpus tests pass.