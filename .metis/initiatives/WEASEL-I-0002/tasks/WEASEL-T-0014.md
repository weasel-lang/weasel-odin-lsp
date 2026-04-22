---
id: position-rewriting-for-lsp
level: task
title: "Position rewriting for LSP requests and responses"
short_code: "WEASEL-T-0014"
created_at: 2026-04-22T17:55:36.496498+00:00
updated_at: 2026-04-22T19:29:56.272175+00:00
parent: WEASEL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/active"


exit_criteria_met: false
initiative_id: WEASEL-I-0002
---

# Position rewriting for LSP requests and responses

## Parent Initiative

[[WEASEL-I-0002]]

## Objective

Make the proxy actually useful: parse LSP message bodies for the subset of methods that carry positions, rewrite Weasel coordinates to Odin before forwarding to `ols`, and rewrite Odin coordinates back to Weasel before returning responses to the editor. Non-position methods continue passing through as opaque bytes.

## Acceptance Criteria

## Acceptance Criteria

- [ ] Inventory documented: the set of LSP methods whose params or result carry positions (at minimum: `textDocument/hover`, `textDocument/definition`, `textDocument/completion`, `textDocument/references`, `textDocument/signatureHelp`, `textDocument/publishDiagnostics`).
- [ ] For each inbound request: `TextDocumentPositionParams.position` (and any other position fields) are translated Weasel → Odin via the active document's source map before forwarding.
- [ ] For each outbound response: every `Range` / `Location` / `Position` field in the result is translated Odin → Weasel before returning to the editor. Positions that don't map back (Odin-only scaffolding) are dropped from the result.
- [ ] `publishDiagnostics` notifications from `ols` are rewritten with the same Odin → Weasel rule; diagnostics on generated-only lines are filtered out.
- [ ] URIs in results (e.g. `Location.uri`) are remapped from the shadow `.odin` URI back to the originating `.weasel` URI.
- [ ] Integration test: a canned LSP session (scripted JSON-RPC exchange) produces the expected Weasel coordinates end-to-end without a real editor.

## Implementation Notes

### Technical Approach

Dispatch on the `method` field before deciding whether to parse. For position-bearing methods, decode just enough JSON to find `position`/`range` fields, rewrite them, re-encode, forward. Responses are correlated to requests by `id` so the proxy knows which rewrite direction to apply to the result.

### Dependencies

- WEASEL-T-0011 (translation API).
- WEASEL-T-0013 (per-document source map state is available keyed by URI).

### Risk Considerations

LSP is big and the server can surprise us with unexpected position fields in vendor extensions. Design the rewriter as a recursive JSON walker driven by field-name patterns (`position`, `range`, `selectionRange`, `targetRange`, `targetSelectionRange`) so new fields are covered by default. Log-and-pass when a URI in a result doesn't map to a known document.

## Status Updates

### 2026-04-22 — Starting work

Transitioned to active. Inventoried the existing code to understand the starting point:

- `lsp/proxy.odin` currently handles `textDocument/did{Open,Change,Save,Close}` for `.weasel` URIs (synthesising shadow-`.odin` URIs toward ols) and passes everything else (requests, responses, notifications with other methods) through verbatim. The `ols_writer` is single-writer today via the editor→ols thread.
- `lsp/source_map_index.odin` already exposes `odin_to_weasel` / `weasel_to_odin` operating on a `Translator`. Every `Document` stored in the proxy owns a live `Translator`.
- The ols→editor path in `cmd/weasel-lsp/main.odin` forwards bodies verbatim via `proxy_write_to_editor`. This is where outbound response rewriting must hook in.

### Plan

Design the rewriter as a recursive JSON walker driven by field-name patterns (`position`, `range`, `selectionRange`, `targetRange`, `targetSelectionRange`, `originSelectionRange`). The walker also remaps `uri` fields from the shadow `.odin` URI back to the `.weasel` URI when it belongs to a known document. Positions that don't map back are dropped.

1. **Pending-requests table** on `Proxy` — map `request_id → {method, weasel_uri}` so the ols→editor direction knows which Weasel document's source map to consult when rewriting a response. Populated on the editor→ols direction for requests with position-bearing methods; consumed on the matching response.
2. **Editor→ols rewriting** — in `proxy_process_editor_message`, intercept requests whose method is in the position-bearing set. Walk the `params` JSON, translate positions via `weasel_to_odin`, swap `.weasel` URIs for their `.odin` shadows, re-marshal, forward. Record the pending-request entry. Non-position methods stay verbatim.
3. **ols→editor rewriting** — new entry point `proxy_process_ols_message` that parses responses and `publishDiagnostics` notifications. For a response, look up the pending request to know which document to use; walk the `result` tree translating `odin_to_weasel`, remapping URIs back, and pruning nodes whose positions don't map. For `publishDiagnostics`, dispatch on the URI: shadow `.odin` URIs get rewritten to the Weasel URI and diagnostics filtered; unknown URIs pass through.
4. **Thread-safety** — `editor_write_mu` already serialises editor-bound writes. Add a new mutex for the pending-requests table since both directions touch it.
5. **Tests** — integration-style tests scripted as JSON-RPC exchanges through the proxy, verifying position translation end-to-end for hover, definition, references, and publishDiagnostics.

### 2026-04-22 — Implementation complete

Landed the following:

**`lsp/rewriter.odin`** (new)
Recursive JSON walker driven by field-name patterns. Handles `position`, `positions`, `range`, `selectionRange`, `targetRange`, `targetSelectionRange`, `originSelectionRange`, `editRange`, `fullRange`, `insertRange`, `replaceRange`, `uri`, and `targetUri`. Unknown fields are recursed into so vendor extensions reusing those names are covered automatically. Positions that don't translate become `json.Null`; Array post-filter drops elements whose "required" range field (`range`/`targetRange`) is null. URIs belonging to known documents are swapped between `.weasel` and `.weasel.odin`; unrelated URIs pass through untouched.

**`lsp/source_map_index.odin`** (extended)
Added `odin_to_weasel_range_end` / `weasel_to_odin_range_end` half-open-range-end variants. LSP Range is half-open so the end position sits exactly at a span's exclusive boundary, where the regular interior-only translators correctly return false. The range-end variant additionally succeeds when the target matches a span's end offset.

**`lsp/proxy.odin`** (extended)
- `Proxy` gains a `pending` map keyed by stringified request id and a `state_mu` guarding the per-proxy document & pending tables.
- `proxy_process_editor_message` now dispatches any non-lifecycle message through `_handle_generic_editor_message`. When the message targets a known `.weasel` URI the walker rewrites params Weasel→Odin and, for requests (those carrying an id), a pending entry is recorded so the matching response can be rewritten back.
- New entry point `proxy_process_ols_message` handles the ols→editor direction: responses with tracked ids are rewritten Odin→Weasel in their `result` field; `textDocument/publishDiagnostics` notifications targeting a shadow URI are rewritten (URI back to `.weasel`, diagnostics filtered if their range doesn't map); everything else passes through.
- Request-id stringification uses a type prefix (`i:<n>` / `s:<id>`) to avoid collision between integer and string ids.

**`cmd/weasel-lsp/main.odin`** (extended)
The ols→editor forwarder now funnels every frame through `proxy_process_ols_message` instead of writing verbatim. The module header comment was updated to reflect the new data flow.

**Tests** (`lsp/proxy_rewrite_test.odin`, new — 10 tests; all passing)
- Hover request: records pending entry, rewrites URI and position before forwarding.
- Hover response: rewrites range back to Weasel coords, consumes pending entry.
- Definition response with Location: URI shadow→weasel, range translated.
- References response array: element whose range lies in Odin-only space is dropped.
- Response with unknown id: pass-through.
- publishDiagnostics from ols: URI rewrite + diagnostic filtering.
- publishDiagnostics for unrelated URI: byte-for-byte pass-through.
- Request targeting an unrelated URI: byte-for-byte pass-through, no pending entry created.
- Walker unit test: Object with uri + range is rewritten in place.
- Walker unit test: position whose offset has no span is nulled.

Total package tests: 53 pass (43 pre-existing + 10 new). Full Odin `transpiler` test suite still passes. `cmd/weasel-lsp` binary still builds clean.

### Method inventory (from the LSP 3.17 spec and the intended coverage)

The walker is method-agnostic: it activates on key names, not method names. Listed here as the set the proxy is *intended* to cover end-to-end once exercised against a real editor session:

Request → response (positions in both directions):
- `textDocument/hover` → `Hover { contents, range? }`
- `textDocument/definition`, `declaration`, `typeDefinition`, `implementation` → `Location | Location[] | LocationLink[]`
- `textDocument/references` → `Location[]`
- `textDocument/completion` → `CompletionItem[] | CompletionList` (item.textEdit.range, item.additionalTextEdits[].range)
- `textDocument/signatureHelp` → `SignatureHelp` (no range in item shape)
- `textDocument/documentHighlight` → `DocumentHighlight[]` (each has `range`)
- `textDocument/prepareRename` → `Range | { range, placeholder }`
- `textDocument/rename` → `WorkspaceEdit { changes/documentChanges with ranges }`
- `textDocument/codeAction` → `(Command | CodeAction)[]` (edit.changes with ranges)
- `textDocument/selectionRange` → `SelectionRange[]`
- `textDocument/rangeFormatting` → `TextEdit[]`

Notifications:
- `textDocument/publishDiagnostics` (`Diagnostic { range, relatedInformation[].location.range, … }`)

Non-position methods (e.g. `initialize`, `shutdown`, `$/setTrace`, `$/cancelRequest`, `workspace/didChangeConfiguration`) pass through unchanged because their params either don't carry positions or don't contain a `textDocument.uri` the proxy recognises.