---
id: 001-element-resolution-heuristic-over
level: adr
title: "Element resolution: heuristic over template proc registry"
number: 1
short_code: "WEASEL-A-0002"
created_at: 2026-04-21T22:19:17.022185+00:00
updated_at: 2026-04-22T09:24:01.693851+00:00
decision_date: 
decision_maker: 
parent: 
archived: false

tags:
  - "#adr"
  - "#phase/decided"


exit_criteria_met: false
initiative_id: NULL
---

# ADR-1: Element resolution: heuristic over template proc registry

## Context

The transpiler needs to decide, for each Weasel element tag, whether to emit it as a raw HTML string or as a call to a template proc. The original design (WEASEL-T-0002) proposed a two-pass registry that scanned source files for `:: template` declarations. This adds a pre-pass, requires tracking declaration scope, and breaks down for templates defined in other packages.

## Decision

Element resolution uses a stateless heuristic applied at transpile time, with no pre-pass required:

1. **Dash rule**: If the tag name contains a `-` (e.g. `my-component`), it is a [custom web component](https://developer.mozilla.org/en-US/docs/Web/Web_Components) and is emitted as raw HTML.
2. **Known HTML tags**: If the tag name appears in a hard-coded map of all standard HTML elements (e.g. `div`, `span`, `ul`, `li`, `input`, ...), it is emitted as raw HTML.
3. **Otherwise**: The tag is treated as a template proc call.

This means naming is load-bearing: a template named `card` is invoked by `<card>`, while `<div>` always emits raw HTML regardless of whether a `div :: template` exists.

## Rationale

The heuristic eliminates the need for a source-scanning pre-pass entirely. It handles cross-file templates naturally (no visibility problem), aligns with web conventions (dash = custom element), and is easy to reason about: if it looks like an HTML tag, it emits as HTML; everything else is a component.

The tradeoff — that a `div :: template` would be silently ignored — is acceptable because shadowing HTML tag names is bad practice anyway.

## Consequences

### Positive
- No pre-pass, no registry, no file-scope tracking
- Cross-package templates work without any import analysis
- Aligns with the web platform convention for custom elements

### Negative
- Template procs must not be named after standard HTML tags — the transpiler will silently emit raw HTML instead of calling them
- The hard-coded HTML tag map must be maintained as the HTML spec evolves (rare in practice)

### Neutral
- WEASEL-T-0002 is retitled and simplified to: build the hard-coded HTML tag map and implement the three-rule resolution logic