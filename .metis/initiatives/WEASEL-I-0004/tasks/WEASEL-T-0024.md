---
id: define-host-driver-interface-and
level: task
title: "Define Host_Driver interface and implement the Odin default driver"
short_code: "WEASEL-T-0024"
created_at: 2026-04-27T10:36:48.832272+00:00
updated_at: 2026-04-27T11:19:07.018979+00:00
parent: WEASEL-I-0004
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0004
---

# Define Host_Driver interface and implement the Odin default driver

## Parent Initiative

[[WEASEL-I-0004]]

## Objective

Create a new `transpiler/host_driver.odin` file defining the `Host_Driver` struct and a `odin_driver()` function that returns the default Odin driver. Extract all Odin-specific hardcoded strings and logic from `transpile.odin` into this struct.

## Interface Definition

```odin
Host_Driver :: struct {
    // proc fields — full emission control
    is_template_start:       proc(tokens: []Token) -> bool,
    emit_signature:          proc(t: ^Template_Proc, e: ^_Emitter),
    emit_dynamic_attr:       proc(w_param, expr: string, e: ^_Emitter),
    emit_raw_string:         proc(w_param, expr: string, e: ^_Emitter),
    emit_escaped_string:     proc(w_param, expr: string, e: ^_Emitter),
    emit_children_open:      proc(w_param: string, e: ^_Emitter),
    emit_children_close:     proc(e: ^_Emitter),
    emit_epilogue:           proc(e: ^_Emitter),

    // string fields
    preamble_marker:         string,   // "package "
}
```

String fields are kept only where a bare string is genuinely sufficient. Everything that varies in *structure* (not just name) is a proc:

- `emit_raw_string` / `emit_escaped_string` own the entire write call including any error-propagation suffix (`or_return`, `!`, etc.) — `error_suffix` is removed as a separate field.
- `emit_children_open` / `emit_children_close` replace the `children_callback_type` string. At Odin call sites the open emits `proc(w: io.Writer) -> io.Error {` and the close emits `}`. A C++ driver emits `[&](std::ostream& out) {` and `}` — which a bare type string cannot represent.
- `emit_signature` already owns the full template declaration, including the children parameter type when a `<slot/>` is present, so `children_callback_type` has no role there either.
- `emit_epilogue` replaces `function_return_stmt`. The Odin driver emits `return nil`; a C++ driver returning `void` emits nothing. A bare string cannot express "emit nothing".

The `odin_driver()` function returns a fully populated `Host_Driver` with current Odin behavior. The proc fields wrap the existing inline logic extracted from `transpile.odin`.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] `transpiler/host_driver.odin` exists with `Host_Driver` struct and `odin_driver()` proc
- [ ] The Odin driver captures all string values currently hardcoded in `transpile.odin`
- [ ] Compiles cleanly (`odin build transpiler/`)
- [ ] This task does NOT yet wire the driver into `transpile()` — that is WEASEL-T-0025

## Implementation Notes

Do a full audit of `transpiler/transpile.odin` before writing the struct — grep for string literals and any proc-level logic that is Odin-specific. The initiative doc lists the known fields but may not be exhaustive.

## Status Updates

2026-04-27: Completed. Created `transpiler/host_driver.odin` with `Host_Driver` struct and `odin_driver()` proc. Changed `_Emitter`, `_write`, `_write_byte`, `_write_tracked`, `_write_string_literal_content` from `@(private = "file")` to `@(private = "package")` so driver procs can call them. Made `_find_template_decl` and `_Template_Decl` package-visible for the `is_template_start` driver proc. All tests pass, `odin check transpiler/ -no-entry-point` clean.