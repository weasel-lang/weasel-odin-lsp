---
id: add-emit-spread-to-host-driver
level: task
title: "Add emit_spread to Host_Driver interface and implement in Odin driver"
short_code: "WEASEL-T-0030"
created_at: 2026-04-27T15:41:48.762730+00:00
updated_at: 2026-04-27T16:44:10.974569+00:00
parent: WEASEL-I-0005
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0005
---

# Add emit_spread to Host_Driver interface and implement in Odin driver

## Parent Initiative

[[WEASEL-I-0005]]

## Objective

Extend the `Host_Driver` struct with an `emit_spread` proc field and wire up the Odin driver's implementation so the transpiler can delegate spread-attribute emission to the host language without containing any Odin-specific logic itself.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] `Host_Driver` has a new field `emit_spread: proc(w: io.Writer, expr: string) -> io.Error`
- [ ] The Odin driver's `emit_spread` emits `weasel.write_spread(w, <expr>) or_return` — the expression is spliced verbatim, not wrapped in quotes
- [ ] All existing corpus tests (`odin run tests/`) continue to pass
- [ ] `odin test transpiler/` passes

## Implementation Notes

### Technical Approach
Locate the `Host_Driver` struct (in `transpiler/transpile.odin` or wherever it is defined) and add the new field. Then find where the Odin-specific driver is initialised and add the `emit_spread` proc. The proc body is a single `fmt.fprintf`-style emit: `io.write_string(w, "weasel.write_spread(w, ")`, then write `expr`, then `) or_return\n`.

### Dependencies
Depends on WEASEL-T-0029 for the runtime type (`weasel.Attributes`) that the emitted code references. Can be developed in parallel but the generated code won't compile until T-0029 is done.

### Risk Considerations
The expression is emitted verbatim — if a caller passes an expression of the wrong type, the error surfaces at Odin compile time, not at Weasel transpile time. This is intentional per the initiative design.

## Status Updates

**2026-04-27** — Complete. Added `emit_spread: proc(w_param, expr: string, e: ^_Emitter)` to `Host_Driver` struct in `transpiler/host_driver.odin`, with doc comment. Implemented `_odin_emit_spread` (emits `weasel.write_spread(w, expr) or_return\n`) and wired into `odin_driver()`. Added `_c3_emit_spread` stub (emits `weasel::write_spread(w, expr)!\n`) and wired into `c3_driver()`. All 135 unit tests and 9 corpus tests pass.