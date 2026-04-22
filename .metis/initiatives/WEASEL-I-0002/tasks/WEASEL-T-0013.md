---
id: in-memory-transpilation-and-ols
level: task
title: "In-memory transpilation and ols document sync"
short_code: "WEASEL-T-0013"
created_at: 2026-04-22T17:55:35.335130+00:00
updated_at: 2026-04-22T19:29:20.281965+00:00
parent: WEASEL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0002
---

# In-memory transpilation and ols document sync

## Parent Initiative

[[WEASEL-I-0002]]

## Objective

Keep `ols` continuously fed with the latest generated Odin text for every open `.weasel` document, entirely in memory. The editor talks to the proxy about `.weasel` files; `ols` sees a live stream of the corresponding `.odin` text via LSP `textDocument/didChange` notifications. This avoids any disk I/O in the hot editing path.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [x] Proxy maintains a per-document state keyed by URI, storing: latest Weasel source, latest generated Odin source, latest `Source_Map`.
- [x] On `textDocument/didOpen` for a `.weasel` URI: transpile in memory, synthesize a `textDocument/didOpen` to `ols` with the generated Odin text and a corresponding `.odin` URI.
- [x] On `textDocument/didChange`: re-transpile, send `textDocument/didChange` to `ols` with the full new Odin document (use `TextDocumentSyncKind.Full` toward `ols` even if the editor sent incremental changes).
- [x] On `textDocument/didSave`: flush the current generated Odin string to the `.odin` file on disk so the developer can open and inspect it.
- [x] On `textDocument/didClose`: forward to `ols` and drop proxy-side state.
- [x] Transpile errors do not crash the proxy; they are reported as diagnostics on the Weasel document and `ols` is sent an empty (or last-good) Odin document to keep it alive.

## Implementation Notes

### Technical Approach

Weasel and Odin URIs live in parallel — `file:///foo.weasel` maps to `file:///foo.weasel.odin` (or similar shadow path) when talking to `ols`. The proxy owns both sides of this mapping; the disk file from `didSave` uses the same shadow path so inspection works naturally.

### Dependencies

- WEASEL-T-0010 (in-memory source map from transpiler).
- WEASEL-T-0012 (proxy skeleton with plumbing to inject synthesized messages toward `ols`).

### Risk Considerations

Transpile failures on every keystroke are the common case during editing (unfinished identifiers, dangling elements). The proxy must handle this gracefully — sending `ols` incomplete Odin it can't parse produces useless diagnostics. Cache the last-good transpile and reuse it while the current source is broken.

## Status Updates

### 2026-04-22 — Implementation plan

Design:

- New file `lsp/proxy.odin` owning a `Proxy` struct and per-URI `Document` state.
- `Document` carries: `weasel_uri`, `odin_uri`, `weasel_text`, `odin_text` (last-good), `Source_Map`, `Translator`, `version`, `language_id`, `last_good` flag.
- URI mapping: `file:///…/foo.weasel` → `file:///…/foo.weasel.odin` (suffix-append). Shadow path on disk is the appended form with the `file://` prefix stripped.
- The existing editor→ols forwarder in `cmd/weasel-lsp/main.odin` is replaced with a single call to `proxy_process_editor_message`, which either forwards verbatim or synthesizes replacement messages toward `ols`. The ols→editor forwarder still runs in a second thread; it writes through `proxy_write_to_editor` so a write mutex serializes it against proxy-initiated diagnostics.
- Lifecycle handling:
  - `didOpen` for a `.weasel` URI: transpile, store `Document`, synthesize `didOpen` to `ols` with the `.odin` URI and generated Odin text. Publish diagnostics collected from scan/parse/transpile errors.
  - `didChange`: support both full-sync and incremental `contentChanges`. Apply changes to the stored `weasel_text` (byte-based offsets — UTF-16 conversion is a known simplification), re-transpile, emit a Full `didChange` toward `ols`. On failure keep the last-good Odin text and forward that to `ols` so its session stays alive; publish diagnostics to the editor.
  - `didSave`: flush `odin_text` to disk at the shadow path. Also forward a synthesized `didSave` to `ols`.
  - `didClose`: synthesize `didClose` to `ols` with the `.odin` URI, drop state.
- Non-`.weasel` URIs pass through unchanged.
- Diagnostics use `textDocument/publishDiagnostics` with the Weasel URI and 1-based → 0-based position conversion from transpiler `Position`.
- Tests live in `lsp/proxy_test.odin` and exercise URI mapping, didOpen synthesis, didChange re-transpile, last-good preservation, and didClose state drop, using in-memory `bytes.Buffer` writers.

### 2026-04-22 — Implementation complete

Landed in two files and one integration site:

- `lsp/proxy.odin` (new) — `Proxy`, `Document`, URI mapping, JSON-RPC helpers, message dispatch, `_transpile_into` with last-good semantics, incremental/full content-change application, and Odin-struct-backed JSON marshal for `didOpen` / `didChange` / `didSave` / `didClose` / `publishDiagnostics`.
- `lsp/proxy_test.odin` (new) — 11 tests covering URI mapping (match / no-match), `.weasel` didOpen synthesis + diagnostics, non-`.weasel` didOpen passthrough, full-sync didChange, incremental didChange position math, last-good preservation on broken source, didClose state drop + ols notification, `initialize` passthrough, and unparseable-body passthrough.
- `cmd/weasel-lsp/main.odin` — the two forwarder threads now call `proxy_process_editor_message` (editor→ols) and `proxy_write_to_editor` (ols→editor), sharing a `Proxy` value that owns the document map and the editor-direction write mutex.

Test + build status (all from project root):

- `odin test lsp` — 43 tests pass; only pre-existing leak is in `test_translate_roundtrip_via_transpile`.
- `odin test transpiler` — 107 tests pass.
- `odin run tests` — 7 corpus tests pass.
- `odin build cmd/weasel-lsp` — builds clean.
- `odin build cmd` — builds clean.

Notable design points:

- Scan/parse/transpile intermediate state lives in a `mem.Dynamic_Arena` per `_transpile_into` call, with `alignment = 64` so Odin's map internals (the `known` name→`has_slot` map inside `transpile`) don't trip the runtime's cache-line alignment check. Only `odin_text`, `source_map.entries`, and cloned diagnostic messages leave the arena — everything else is reaped by `dynamic_arena_destroy`, which sidesteps deep-free for nested parser arrays.
- JSON synthesis uses typed structs with `json:"…"` tags rather than string concatenation so escaping and quoting are handled by the encoder.
- The editor-direction writer is serialised by `sync.Mutex`; the ols→editor forwarder routes through `proxy_write_to_editor` for this reason.
- Known limitation: `_position_to_offset` treats LSP `character` as bytes rather than UTF-16 code units. Non-ASCII source will misalign incremental edits. Flagged in the proc doc — T-0014 or a later ADR can lift this when real editor traffic demands it.

Ready for review.