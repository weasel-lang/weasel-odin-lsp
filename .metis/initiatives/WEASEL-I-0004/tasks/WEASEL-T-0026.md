---
id: implement-weasel-json-config
level: task
title: "Implement .weasel.json config loader with upward directory traversal"
short_code: "WEASEL-T-0026"
created_at: 2026-04-27T10:36:57.490850+00:00
updated_at: 2026-04-27T11:33:24.119242+00:00
parent: WEASEL-I-0004
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0004
---

# Implement .weasel.json config loader with upward directory traversal

## Parent Initiative

[[WEASEL-I-0004]]

## Objective

Create a config loader (in a new `config/` package or within `transpiler/`) that walks from the working directory up to the filesystem root looking for `.weasel.json`, parses it, and returns a resolved `Weasel_Config` struct. If no file is found, return built-in Odin defaults.

## Config Schema

```json
{
  "host":       "odin",
  "preamble":   ["import \"core:io\"", "import \"lib:weasel\""],
  "lsp_binary": "ols",
  "lsp_args":   []
}
```

`write_raw` and `write_escaped` are no longer config fields — emission is fully owned by the driver's `emit_raw_string`/`emit_escaped_string` procs and cannot be overridden by a string substitution. All fields are optional; missing fields fall back to the active driver's defaults.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] Config loader compiles and can be called from both `cmd/weasel-c` and `cmd/weasel-lsp`
- [ ] Upward traversal stops at filesystem root and returns defaults if no `.weasel.json` found
- [ ] A `.weasel.json` with only some fields overrides only those fields; other fields use driver defaults
- [ ] Unit tests cover: no file found, full file, partial override, malformed JSON (returns error)

## Dependencies

- WEASEL-T-0024 (needs driver defaults to fall back on)



## Status Updates **[REQUIRED]**

*To be added during implementation*