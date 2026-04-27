---
id: wire-config-into-cli-and-lsp-proxy
level: task
title: "Wire config into CLI and LSP proxy (Proxy_Options for backend binary)"
short_code: "WEASEL-T-0027"
created_at: 2026-04-27T10:37:00.221560+00:00
updated_at: 2026-04-27T10:37:00.221560+00:00
parent: WEASEL-I-0004
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0004
---

# Wire config into CLI and LSP proxy (Proxy_Options for backend binary)

## Parent Initiative

[[WEASEL-I-0004]]

## Objective

Load `.weasel.json` at startup in both `cmd/weasel-c/main.odin` and `cmd/weasel-lsp/main.odin`. Construct `Transpile_Options` (for the CLI) and `Proxy_Options` (for the LSP proxy) from the resolved config, replacing all hardcoded values.

## Changes Required

**`cmd/weasel-c/main.odin`:**
- Call config loader at startup
- Construct `Transpile_Options{driver, write_raw, write_escaped, preamble}` from config
- Pass options to each `transpile()` call

**`cmd/weasel-lsp/main.odin` + `lsp/proxy.odin`:**
- Introduce `Proxy_Options :: struct { lsp_binary: string, lsp_args: []string }`
- Load binary name and args from config instead of hardcoding `"ols"`
- Pass `Proxy_Options` to the proxy startup function

## Acceptance Criteria

- [ ] `weasel generate` with no `.weasel.json` present behaves identically to today
- [ ] `weasel-lsp` with no `.weasel.json` still spawns `ols` as before
- [ ] A `.weasel.json` with `"lsp_binary": "c3-lsp"` causes the proxy to spawn `c3-lsp` instead
- [ ] `odin run tests/` passes
- [ ] Both binaries build cleanly

## Dependencies

- WEASEL-T-0025 (Transpile_Options must exist)
- WEASEL-T-0026 (config loader must exist)

## Status Updates **[REQUIRED]**

*To be added during implementation*