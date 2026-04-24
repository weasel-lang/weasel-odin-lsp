---
id: lsp-verify-position-rewriting-is
level: task
title: "LSP: verify position rewriting is correct under new grammar"
short_code: "WEASEL-T-0020"
created_at: 2026-04-24T19:20:50.093273+00:00
updated_at: 2026-04-24T19:49:24.202073+00:00
parent: WEASEL-I-0003
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0003
---

# LSP: verify position rewriting is correct under new grammar

## Parent Initiative

[[WEASEL-I-0003]]

## Objective

Audit `lsp/rewriter.odin` and `lsp/proxy.odin` to confirm position rewriting is correct after the grammar change. The structural logic should be unchanged, but any span assumptions that relied on `{` being a 1-char delimiter must be updated to account for `$(` being 2 chars. Run and extend `lsp/proxy_rewrite_test.odin` and `lsp/source_map_translate_test.odin` to cover expression positions. Depends on WEASEL-T-0019 (source map offsets).

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] `lsp/rewriter.odin` correctly translates positions for `$()` expression spans
- [ ] `lsp/proxy.odin` handles requests whose positions fall inside `$()` expressions
- [ ] `lsp/proxy_rewrite_test.odin` and `lsp/source_map_translate_test.odin` extended with expression-position cases
- [ ] All existing LSP tests pass

## Implementation Notes

### Files
- `lsp/rewriter.odin` — audit and fix span arithmetic if needed
- `lsp/proxy.odin` — audit position dispatch
- `lsp/proxy_rewrite_test.odin`, `lsp/source_map_translate_test.odin` — add expression-position tests

### Dependencies
- WEASEL-T-0019 (source map offsets must be correct before LSP can rely on them)

## Status Updates

### 2026-04-24

**Audit:** `rewriter.odin` and `source_map_index.odin` use byte-offset interpolation only — no hardcoded delimiter assumptions. No structural changes needed.

**Pre-existing failures fixed (5):** All caused by tests assuming "greet" maps to Odin offset 0, but the auto-injected `import "core:io"\n` (17 bytes) shifts the proc to line 2. Fixed by updating expected Odin line from 0→1 in proxy tests and offset from 0→17 in round-trip test.

**New tests added (3):**
- `test_translate_roundtrip_expr_via_transpile` — Weasel offset 5 inside `$(name)` maps to 'n' in Odin `__weasel_write_escaped_string` call; round-trips back exactly
- `test_translate_expr_range_end_via_transpile` — weasel_to_odin_range_end for the exclusive end of the expression
- `test_rewrite_hover_on_expr_position` — proxy correctly forwards a hover at Weasel char 5 to Odin line 1 char ≥ 33

All 56 LSP tests + 120 transpiler tests pass.