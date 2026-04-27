---
id: implement-minimal-c3-host-driver
level: task
title: "Implement minimal C3 host driver and validate end-to-end"
short_code: "WEASEL-T-0028"
created_at: 2026-04-27T10:37:05.865830+00:00
updated_at: 2026-04-27T11:43:38.960669+00:00
parent: WEASEL-I-0004
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0004
---

# Implement minimal C3 host driver and validate end-to-end

## Parent Initiative

[[WEASEL-I-0004]]

## Objective

Create `transpiler/c3_driver.odin` implementing a C3 `Host_Driver`. Validate that `weasel generate` on a minimal `.weasel` file produces valid C3 output when `.weasel.json` selects the C3 driver. This is the acceptance gate proving the host-agnostic architecture actually works.

## C3 Driver Specifics

Key differences from the Odin driver:

| Field | Odin | C3 |
|---|---|---|
| `error_suffix` | `" or_return"` | `"!"` |
| `function_return_stmt` | `"return nil"` | TBD |
| `children_callback_type` | `"proc(w: io.Writer) -> io.Error"` | TBD |
| `preamble_marker` | `"package "` | `"module "` |
| `emit_raw_string` | `__weasel_write_raw_string(w, s) or_return` | `weasel::write_raw(stream, s)!` (TBD) |
| `emit_escaped_string` | `__weasel_write_escaped_string(w, s) or_return` | `weasel::write_escaped(stream, s)!` (TBD) |

`emit_raw_string` and `emit_escaped_string` are now full proc fields on the driver — they emit the entire call-site expression, not just a symbol name. This is what allows a future C++ driver to emit `out << s` with no function call at all.

Exact C3 values to be confirmed during implementation by referencing C3 language docs.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] `transpiler/c3_driver.odin` exists and compiles
- [ ] A `.weasel.json` with `"host": "c3"` selects the C3 driver
- [ ] A minimal fixture (`tests/corpus/c3_basic.weasel`) transpiles to syntactically valid C3 output
- [ ] Odin corpus tests still pass (no regression)
- [ ] C3 golden file committed alongside the fixture

## Dependencies

- WEASEL-T-0025 (parameterised transpiler)
- WEASEL-T-0026 (config loader)
- WEASEL-T-0027 (config wired into CLI)

## Status Updates **[REQUIRED]**

*To be added during implementation*