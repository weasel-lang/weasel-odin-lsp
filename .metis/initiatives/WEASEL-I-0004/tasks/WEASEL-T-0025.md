---
id: parameterise-the-transpiler-with
level: task
title: "Parameterise the transpiler with Transpile_Options and Host_Driver"
short_code: "WEASEL-T-0025"
created_at: 2026-04-27T10:36:51.198886+00:00
updated_at: 2026-04-27T11:29:08.927481+00:00
parent: WEASEL-I-0004
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0004
---

# Parameterise the transpiler with Transpile_Options and Host_Driver

## Parent Initiative

[[WEASEL-I-0004]]

## Objective

Replace all hardcoded Odin strings and logic in `transpile.odin` with calls into a `Host_Driver` passed via `Transpile_Options`. After this task the transpiler emits identical output for Odin projects but is driven entirely through the options struct.

## Transpile_Options Shape

```odin
Transpile_Options :: struct {
    driver:   ^Host_Driver,
    preamble: []string, // lines injected after package declaration
}
```

`write_raw_symbol` and `write_escaped_symbol` are gone — emission of raw and escaped strings is now fully delegated to `driver.emit_raw_string` and `driver.emit_escaped_string`. The driver owns the entire call-site shape, not just the symbol name.

The preamble is injected unconditionally (every generated file). The source map offset adjustment pass uses `len(options.preamble)` instead of the current hardcoded `2`.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] `transpile()` accepts `Transpile_Options` as a parameter
- [ ] No Odin-specific string literals remain in `transpile.odin` (all go through driver or options)
- [ ] The preamble line count is derived from `len(options.preamble)`, replacing the hardcoded constant
- [ ] `cmd/weasel-c/main.odin` updated to pass Odin-default options (no behavior change)
- [ ] `odin run tests/` passes with no golden file changes
- [ ] `odin test transpiler/` passes

## Dependencies

- WEASEL-T-0024 (Host_Driver interface must exist first)

## Status Updates

2026-04-27: Completed. All hardcoded host-language strings removed from transpile.odin. _Emitter now has `driver: Host_Driver` field. `_emit_template_proc`, `_emit_node`, `_emit_raw_element`, `_emit_open_tag`, `_emit_component`, `_flush_pending` all delegate to driver procs. Preamble injection is conditional on template procs being present and no preamble line already in source. All 120 transpiler tests, 57 LSP tests, and 9 corpus tests pass. **[REQUIRED]**

*To be added during implementation*