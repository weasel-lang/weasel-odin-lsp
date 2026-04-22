---
id: position-rewriting-for-lsp
level: task
title: "Position rewriting for LSP requests and responses"
short_code: "WEASEL-T-0014"
created_at: 2026-04-22T17:55:36.496498+00:00
updated_at: 2026-04-22T17:55:36.496498+00:00
parent: WEASEL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0002
---

# Position rewriting for LSP requests and responses

## Parent Initiative

[[WEASEL-I-0002]]

## Objective

Make the proxy actually useful: parse LSP message bodies for the subset of methods that carry positions, rewrite Weasel coordinates to Odin before forwarding to `ols`, and rewrite Odin coordinates back to Weasel before returning responses to the editor. Non-position methods continue passing through as opaque bytes.

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

*To be added during implementation*