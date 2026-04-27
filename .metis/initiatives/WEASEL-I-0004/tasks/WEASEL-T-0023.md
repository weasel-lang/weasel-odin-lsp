---
id: rename-odin-identifiers-to-host
level: task
title: "Rename Odin_* identifiers to Host_* throughout the codebase"
short_code: "WEASEL-T-0023"
created_at: 2026-04-27T10:36:46.320917+00:00
updated_at: 2026-04-27T10:36:46.320917+00:00
parent: WEASEL-I-0004
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0004
---

# Rename Odin_* identifiers to Host_* throughout the codebase

## Parent Initiative

[[WEASEL-I-0004]]

## Objective

Pure mechanical rename — no behavior changes. Replace all Odin-specific identifiers in the AST, lexer, parser, and source map layers with host-language-generic names to make the abstraction boundary explicit.

## Rename Map

| Current name | New name | File(s) |
|---|---|---|
| `Odin_Span` (AST node type) | `Host_Span` | `transpiler/parser.odin`, `transpiler/transpile.odin`, `lsp/` |
| `Odin_Block` (AST node type) | `Host_Block` | same |
| `Odin_Text` (token kind) | `Host_Text` | `transpiler/lexer.odin`, `transpiler/parser.odin` |
| `odin_start` / `odin_end` fields on `Span_Entry` | `host_start` / `host_end` | `transpiler/source_map.odin`, `lsp/` |

Update comments that say "Odin" when they mean "host language" (e.g., "verbatim Odin passthrough" → "verbatim host passthrough").

## Acceptance Criteria

- [ ] No occurrences of `Odin_Span`, `Odin_Block`, `Odin_Text` remain in `transpiler/` or `lsp/`
- [ ] `odin_start`/`odin_end` field names replaced (or confirmed they should stay as positional names)
- [ ] `odin run tests/` passes with no golden file changes
- [ ] `odin test transpiler/` and `odin test lsp/` pass

## Implementation Notes

Safe to execute before any other task in this initiative. No logic changes — rename only. Use `grep -r "Odin_" transpiler/ lsp/` to find all occurrences before starting.

## Status Updates **[REQUIRED]**

*To be added during implementation*