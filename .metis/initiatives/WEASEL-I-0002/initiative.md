---
id: weasel-lsp-provider
level: initiative
title: "Weasel LSP provider"
short_code: "WEASEL-I-0002"
created_at: 2026-04-22T17:17:32.190493+00:00
updated_at: 2026-04-25T12:06:14.380925+00:00
parent: WEASEL-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/completed"


exit_criteria_met: false
estimated_complexity: L
initiative_id: weasel-lsp-provider
---

# Weasel LSP provider Initiative

*This template includes sections for various types of initiatives. Delete sections that don't apply to your specific use case.*

## Context **[REQUIRED]**

Weasel is a template/transpiler language that compiles to Odin. As the language matures, developer experience becomes critical — in particular, IDE support via the Language Server Protocol (LSP). Because Weasel is a thin layer over Odin and HTML/Tailwind expressions, a full from-scratch LSP implementation is unnecessary and expensive to maintain. Instead, Weasel's LSP will act as a **proxy**, delegating to [`ols`](https://github.com/DanielGavin/ols) (the Odin Language Server) for all LSP requests. This covers the Odin domain of Weasel files, which is the primary developer experience concern.

For this proxy architecture to work, the LSP must be able to map positions in `.weasel` source files to the corresponding positions in generated Odin files. This requires a **source map** layer that tracks the coordinate transformation applied during transpilation.

**HTML/Tailwind support is deferred.** Weasel is a superset of Odin, meaning its source is not valid HTML and cannot be passed directly to an HTML language service. A proper HTML view synthesizer (analogous to `svelte2tsx` in the Svelte LSP) is required to strip/stub Weasel-specific syntax before delegating to `vscode-html-language-server`. That work is scoped to a future initiative. In the interim, Tailwind class completions can be obtained by configuring `tailwindCSS.includeLanguages: {"weasel": "html"}` at the editor level — imperfect but functional for class strings.

## Goals & Non-Goals **[REQUIRED]**

**Goals:**
- Provide LSP features (hover, go-to-definition, completions, diagnostics) for Weasel source files by proxying to `ols`
- Implement source mapping in the transpiler so Weasel ↔ generated Odin positions can be translated bidirectionally
- Package the proxy as a standalone `weasel-lsp` binary that editors can point to

**Non-Goals:**
- Implementing a full LSP from scratch — the proxy delegates all language intelligence to `ols`
- HTML tag/attribute completions — requires a Weasel→HTML view synthesizer, deferred to a future initiative
- Supporting LSP features for Odin itself beyond what `ols` already provides
- Editor plugin development (assumes editors speak standard LSP)



## Architecture

### Overview

The `weasel-lsp` binary sits between the editor and `ols`. It speaks standard LSP to the editor, re-transpiles Weasel source on every change, and forwards requests to `ols` with coordinates rewritten via the in-memory source map.

```
Editor (LSP client)
       │  LSP (JSON-RPC)
       ▼
  weasel-lsp  (proxy)
   ├─ in-memory transpilation + source map
   └──► ols  (Odin LSP)
```

### Source Map Layer

The transpiler currently discards coordinate information. It must be extended to emit a source map alongside each generated `.odin` file. The map records, for each token or node in the output, the originating line/column in the `.weasel` source. The proxy uses this map to:

1. Translate an incoming Weasel position → generated Odin position (for forwarding to `ols`)
2. Translate a response position from `ols` back → Weasel position (for returning to the editor)

## Detailed Design **[REQUIRED]**

### Phase 1 — Source mapping in the transpiler

Extend the transpiler so that alongside the generated Odin string it also returns an in-memory source map — a data structure that maps positions in the generated Odin text back to their origin positions in the `.weasel` source. No on-disk format is needed; the map lives in the proxy process for the lifetime of an open document.

The core structure needs to answer one query efficiently: *given a (row, col) in the generated Odin, what (row, col) does it correspond to in the Weasel source?* (And the inverse, for rewriting positions in `ols` responses back to Weasel coordinates.) A sorted array of span entries covering each emitted node is sufficient; binary search gives O(log n) lookup per LSP request.

```
Span_Entry :: struct {
    odin_start: Position,   // row/col in generated Odin
    odin_end:   Position,
    weasel_start: Position, // corresponding origin in .weasel source
    weasel_end:   Position,
}

Source_Map :: struct {
    entries: []Span_Entry,   // sorted by odin_start
}
```

The transpiler must populate this for all position-bearing output: procedure names, identifiers, string literals, and element names at minimum.

### Phase 2 — Proxy implementation

Implement `weasel-lsp` in Odin (consistent with the rest of the toolchain). The proxy:
- Speaks LSP JSON-RPC over stdio to the editor
- Spawns `ols` as a child process on startup
- On `textDocument/didChange`: re-transpile in memory, forward updated Odin text to `ols` via its stdin
- On `textDocument/didSave`: flush generated `.odin` to disk (for standalone inspection)
- For each position-bearing request: rewrite Weasel coordinates → Odin coordinates via the in-memory source map, forward to `ols`, rewrite positions in the response back to Weasel coordinates
- Passes non-position requests (e.g. `initialize`, `shutdown`) through to `ols` unchanged

### Rebuild and In-Memory Translation Strategy

The proxy maintains a live in-memory transpilation of each open `.weasel` file and communicates with `ols` continuously via its stdin pipe using standard LSP notifications — no disk I/O is required for `ols` to stay current.

**On every document change (`textDocument/didChange` from the editor):**
1. Re-transpile the Weasel source in memory → fresh generated Odin string + fresh source map
2. Forward a `textDocument/didChange` to `ols` carrying the new Odin text as the document content
3. `ols` processes the update entirely in memory; the `.odin` file on disk is not consulted

**On save (`textDocument/didSave`):**
1. Write the current generated Odin string to the `.odin` file on disk
2. This is solely so the developer can open and inspect (or directly edit) the generated file — it has no effect on the live `ols` session

This gives the developer real-time Odin LSP support (hover, completions, diagnostics) while editing `.weasel` files through the `Editor → weasel-lsp → ols` path. The `Editor → ols` direct path remains functional for the generated `.odin` files when opened standalone.

## Alternatives Considered **[REQUIRED]**

- **Full custom LSP implementation**: Would give complete control but requires reimplementing type inference, symbol resolution, and all language intelligence from scratch. Maintenance burden is prohibitive.
- **Extend `ols` directly**: `ols` has no model of `.weasel` syntax. Forking it would couple us to its internals.
- **No LSP**: Acceptable short-term but increasingly painful as the language grows. Source mapping is required regardless for good error reporting, so building on it for LSP is a natural step.
- **HTML/Tailwind support in this initiative**: Weasel is a superset of Odin, so its source cannot be passed directly to an HTML language service. A Weasel→HTML view synthesizer (analogous to `svelte2tsx`) is needed first — deferred to a future initiative.

## Implementation Plan **[REQUIRED]**

1. **Discovery** (current phase): Finalise architecture → transition to design
2. **Source map**: Extend transpiler to produce an in-memory `Source_Map` alongside the generated Odin string
3. **Proxy skeleton**: `weasel-lsp` binary that receives LSP messages and forwards them verbatim to `ols`
4. **Position rewriting**: Integrate source map into the proxy; translate Weasel ↔ Odin coordinates for all position-bearing requests
5. **End-to-end validation**: Test hover, completions, and go-to-definition in a real editor (VS Code or Neovim) against a sample Weasel project

## Status Updates

### 2026-04-22 — Decomposed into tasks

Decomposed the initiative into six tasks following the Implementation Plan structure:

- [[WEASEL-T-0010]] — Source map data structure and transpiler emission (foundation for everything else)
- [[WEASEL-T-0011]] — Bidirectional Weasel↔Odin position translation API (the hot path for every LSP request)
- [[WEASEL-T-0012]] — `weasel-lsp` proxy skeleton with stdio JSON-RPC and `ols` child process (pure passthrough, no translation)
- [[WEASEL-T-0013]] — In-memory transpilation + `ols` document sync (keeps `ols` fed on every keystroke)
- [[WEASEL-T-0014]] — Position rewriting for LSP requests and responses (makes the proxy actually useful)
- [[WEASEL-T-0015]] — End-to-end editor validation against a sample Weasel project (initiative exit criterion)

Dependency order: T-0010 → T-0011 (translation needs the data structure), T-0012 is independent and can run in parallel with T-0010/T-0011, T-0013 depends on T-0010+T-0012, T-0014 depends on T-0011+T-0013, T-0015 depends on T-0014.

Awaiting user review before transitioning to `active`.