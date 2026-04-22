---
id: weasel-lsp-proxy-skeleton-with
level: task
title: "weasel-lsp proxy skeleton with stdio JSON-RPC and ols child process"
short_code: "WEASEL-T-0012"
created_at: 2026-04-22T17:55:34.193278+00:00
updated_at: 2026-04-22T18:51:55.744982+00:00
parent: WEASEL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/active"


exit_criteria_met: false
initiative_id: WEASEL-I-0002
---

# weasel-lsp proxy skeleton with stdio JSON-RPC and ols child process

## Parent Initiative

[[WEASEL-I-0002]]

## Objective

Stand up the `weasel-lsp` binary as a pure passthrough proxy between an editor and `ols`. No translation yet — just reliable JSON-RPC framing in both directions and a stable `ols` child process. This isolates the LSP plumbing from the translation logic so the latter can be added in a focused follow-up.

## Acceptance Criteria

## Acceptance Criteria

- [ ] New `weasel-lsp` binary builds and runs (Odin, consistent with the rest of the toolchain).
- [ ] Reads LSP JSON-RPC messages from stdin with correct `Content-Length` header framing; writes responses to stdout with the same framing.
- [ ] Spawns `ols` as a child process on startup; pipes stdout/stdin to the editor side.
- [ ] Every message from editor is forwarded verbatim to `ols`, and every message from `ols` is forwarded verbatim back to the editor.
- [ ] `initialize` / `initialized` / `shutdown` / `exit` handshake completes cleanly between editor and `ols` through the proxy.
- [ ] If `ols` exits unexpectedly the proxy logs the exit code and terminates with a non-zero status rather than hanging.

## Implementation Notes

### Technical Approach

Two goroutine-equivalent read loops (one per direction). `Content-Length` header parser + body reader, JSON-RPC message represented as opaque bytes at this stage — no need to parse bodies until WEASEL-T-0014 starts rewriting them. Use `os/exec`-equivalent Odin facility to spawn `ols` with its stdin/stdout wired to pipes.

### Dependencies

- `ols` must be on the user's `PATH` (or a configurable path) — document the assumption.
- No dependency on the source map work (T-0010, T-0011) at this stage; those land in T-0014.

### Follow-up carried from WEASEL-T-0011

During T-0011 the bidirectional translation API (`weasel_to_odin`, `odin_to_weasel`) was added to `transpiler/source_map.odin` for expediency. The translators depend only on the public `Source_Map` / `Span_Entry` / `Position` types and are used exclusively by the LSP layer — not by the transpiler itself. As part of T-0012's skeleton work:

- Move `weasel_to_odin`, `odin_to_weasel`, `_find_span`, `_interpolate`, and the `source_map_translate_test.odin` file from `transpiler/` to `lsp/`.
- Move the `weasel_sorted` secondary index out of `Source_Map` and into an LSP-side cache built once per document (alongside the transpile result). This also stops the CLI (`weasel generate`) from paying to build an index it never uses.
- Leave `entries` sorted by `odin_start.offset` inside the transpiler; that ordering is the natural output of emission.

### Risk Considerations

LSP framing is unforgiving — a single off-by-one in `Content-Length` handling corrupts the stream and editors surface the error as "language server crashed". Tests should exercise messages that straddle buffer boundaries.

## Status Updates

*To be added during implementation*