---
id: in-memory-transpilation-and-ols
level: task
title: "In-memory transpilation and ols document sync"
short_code: "WEASEL-T-0013"
created_at: 2026-04-22T17:55:35.335130+00:00
updated_at: 2026-04-22T17:55:35.335130+00:00
parent: WEASEL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0002
---

# In-memory transpilation and ols document sync

## Parent Initiative

[[WEASEL-I-0002]]

## Objective

Keep `ols` continuously fed with the latest generated Odin text for every open `.weasel` document, entirely in memory. The editor talks to the proxy about `.weasel` files; `ols` sees a live stream of the corresponding `.odin` text via LSP `textDocument/didChange` notifications. This avoids any disk I/O in the hot editing path.

## Acceptance Criteria

- [ ] Proxy maintains a per-document state keyed by URI, storing: latest Weasel source, latest generated Odin source, latest `Source_Map`.
- [ ] On `textDocument/didOpen` for a `.weasel` URI: transpile in memory, synthesize a `textDocument/didOpen` to `ols` with the generated Odin text and a corresponding `.odin` URI.
- [ ] On `textDocument/didChange`: re-transpile, send `textDocument/didChange` to `ols` with the full new Odin document (use `TextDocumentSyncKind.Full` toward `ols` even if the editor sent incremental changes).
- [ ] On `textDocument/didSave`: flush the current generated Odin string to the `.odin` file on disk so the developer can open and inspect it.
- [ ] On `textDocument/didClose`: forward to `ols` and drop proxy-side state.
- [ ] Transpile errors do not crash the proxy; they are reported as diagnostics on the Weasel document and `ols` is sent an empty (or last-good) Odin document to keep it alive.

## Implementation Notes

### Technical Approach

Weasel and Odin URIs live in parallel — `file:///foo.weasel` maps to `file:///foo.weasel.odin` (or similar shadow path) when talking to `ols`. The proxy owns both sides of this mapping; the disk file from `didSave` uses the same shadow path so inspection works naturally.

### Dependencies

- WEASEL-T-0010 (in-memory source map from transpiler).
- WEASEL-T-0012 (proxy skeleton with plumbing to inject synthesized messages toward `ols`).

### Risk Considerations

Transpile failures on every keystroke are the common case during editing (unfinished identifiers, dangling elements). The proxy must handle this gracefully — sending `ols` incomplete Odin it can't parse produces useless diagnostics. Cache the last-good transpile and reuse it while the current source is broken.

## Status Updates

*To be added during implementation*