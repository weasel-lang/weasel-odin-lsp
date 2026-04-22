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

### 2026-04-22 — Implementation complete

Implemented the `weasel-lsp` proxy skeleton plus the T-0011 refactor that it depends on. The proxy builds, handshakes cleanly with real `ols`, and exits non-zero with an explanatory stderr message when `ols` dies unexpectedly.

**Refactor carried from T-0011 (moved to LSP layer)**

- `transpiler/source_map.odin` — dropped the `weasel_sorted` field from `Source_Map`, simplified `_sort_entries` to only sort `entries` by `odin_start.offset`, removed `odin_to_weasel`/`weasel_to_odin`/`_find_span`/`_interpolate`, and updated `source_map_destroy` to only free `entries`. The CLI (`weasel generate`) no longer pays to build a reverse index it never reads.
- `lsp/source_map_index.odin` (new) — introduced `Translator`, built once per document. Borrows `sm.entries` as `odin_sorted` and owns a `weasel_sorted` copy. `translator_make`/`translator_destroy` is the public surface. `odin_to_weasel` and `weasel_to_odin` now take a `^Translator` instead of a `^Source_Map`.
- `lsp/source_map_translate_test.odin` (new, moved from `transpiler/`) — 17 tests rewritten to use the `Translator` wrapper and `transpiler.Source_Map` directly. The test helper sorts synthetic entries in place rather than reaching into a transpiler-private sort routine.

**Framing layer (`lsp/framing.odin`)**

- `Frame_Error` enum: `None | EOF | Unexpected_EOF | Invalid_Header | Oversize | IO`.
- `read_message(r: io.Reader)` — byte-at-a-time header read terminated by CRLFCRLF or LFLF (lenient on the read side), parses `Content-Length` case-insensitively, ignores all other headers, reads exactly that many body bytes. Clean EOF before any header byte surfaces as `.EOF`; EOF mid-frame surfaces as `.Unexpected_EOF`. Caps: 8 KiB headers, 64 MiB body.
- `write_message(w: io.Writer, body)` — emits `Content-Length: N\r\n\r\n<body>` per spec.
- `lsp/framing_test.odin` (new) — 16 tests covering: basic round-trip, byte-at-a-time straddled reads via a `_Chunk_Reader` helper, back-to-back frames on one reader, extra headers, LF-only delimiters, zero body, clean EOF, truncated headers, truncated body, missing `Content-Length`, garbage header, non-numeric length, case-insensitive match.

**Proxy binary (`cmd/weasel-lsp/main.odin`)**

- Args: `--ols <path>` (default `ols` on PATH); `-h`/`--help`.
- Creates two pipes, spawns `ols` via `os.process_start` with them wired to its stdin/stdout; inherits this process's stderr so `ols` logs are still visible.
- Two I/O threads: `editor->ols` and `ols->editor`. Each is a `Forwarder` that reads framed messages and writes them verbatim. Using the framing layer (not raw byte forwarding) catches protocol errors on the boundary and mirrors the shape T-0014 will need.
- When the editor closes its stdin, the `editor->ols` forwarder's defer closes `ols_stdin_w`, propagating EOF to `ols` so it can exit cleanly after the LSP `exit` notification.
- Main thread blocks on `os.process_wait`. Non-zero exit code → `"weasel-lsp: ols exited unexpectedly with code N"` on stderr, then `os.exit(N)`. Zero exit → `os.exit(0)`.

**End-to-end validation**

- Unit: `odin test transpiler/` 107/107 pass. `odin test lsp/` 33/33 pass (17 translator + 16 framing).
- Integration with a Python fake-ols echo server: two request/response cycles relay correctly, proxy exits 0 after stdin close.
- Integration with a Python fake-ols that exits 42 immediately: proxy logs `ols exited unexpectedly with code 42` and exits 42.
- Missing `ols` binary: `weasel-lsp: cannot spawn '<path>': Not_Exist`, exit 1.
- Real `ols` (`/Users/greger/.local/bin/ols`) through the proxy: full `initialize`/`initialized`/`shutdown`/`exit` handshake — both responses (ids 1 and 2) arrive, proxy exits 0.

**Acceptance criteria**

- [x] New `weasel-lsp` binary builds and runs — Odin, under `cmd/weasel-lsp/`.
- [x] Reads framed LSP messages from stdin / writes framed responses to stdout.
- [x] Spawns `ols` as a child with pipes wired to stdin/stdout.
- [x] Every editor message forwarded verbatim to `ols`; every `ols` message forwarded back verbatim (bodies are opaque bytes at this stage).
- [x] `initialize` / `initialized` / `shutdown` / `exit` handshake completes cleanly against real `ols` through the proxy.
- [x] Unexpected `ols` exit logs the code and terminates non-zero rather than hanging.

**Notes for T-0013 / T-0014**

- The `Translator` lives alongside the `Source_Map` and generated Odin string; T-0013 will keep one per open document. `translator_make` takes a `^transpiler.Source_Map` and borrows its `entries` slice, so the `Source_Map` must outlive the `Translator`.
- The proxy uses `lsp.read_message` / `lsp.write_message` at the frame layer, so T-0014 just needs to replace `write_message(dst, body)` with a "parse → rewrite positions → re-serialize → write" step in the appropriate direction.