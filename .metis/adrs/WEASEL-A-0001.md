---
id: 001-children-passed-as-proc-callback
level: adr
title: "Children passed as proc callback to component templates"
number: 1
short_code: "WEASEL-A-0001"
created_at: 2026-04-21T22:10:00.974648+00:00
updated_at: 2026-04-21T22:10:00.974648+00:00
decision_date: 
decision_maker: 
parent: 
archived: false

tags:
  - "#adr"
  - "#phase/draft"


exit_criteria_met: false
initiative_id: NULL
---

# ADR-1: Children passed as proc callback to component templates

## Context

Weasel templates use procedural emission — they write HTML directly to an `io.Writer` as the transpiler encounters elements. Component templates (e.g. `<ui.card>`) can have nested child content, and the parent component needs to control where those children are rendered (e.g. wrapping them in a `<div class="card">`). The question is how the transpiler passes that nested content to the parent.

## Decision

Children are passed as a `proc(w: io.Writer)` callback parameter. The transpiler wraps the nested content in an anonymous proc at the call site:

```odin
ui.card(w, props, proc(w: io.Writer) {
    task_item(w, {task = task})
})
```

The `children` parameter is the last parameter by convention. Component templates that accept children declare it explicitly:

```odin
card :: template(p: ^card_props, children: proc(w: io.Writer)) {
    __weasel_write_raw_string(w, "<div class=\"card\">") or_return
    children(w)
    __weasel_write_raw_string(w, "</div>") or_return
}
```

## Alternatives Analysis

| Option | Pros | Cons | Risk Level | Implementation Cost |
|--------|------|------|------------|-------------------|
| **A: `proc` callback** | Streaming, no allocation, captures outer scope vars | Slightly more complex transpiler output | Low | Medium |
| **B: Buffer to string** | Simple parent API | Allocates per component, breaks streaming | Low | Low |
| **C: No children** | Eliminates the problem | Severely limits composability | Low | None |
| **D: Before/after slots** | Structured | Too rigid for general layout components | Low | Medium |

## Rationale

Option A preserves the streaming `io.Writer` model that is central to Weasel's design. Anonymous procs in Odin can capture variables from the enclosing scope, so loop variables and other locals work naturally inside child content. No heap allocation is required. The transpiler output is straightforward to generate.

## Consequences

### Positive
- No buffering or allocation for child content
- Outer-scope variables (e.g. loop iterators) are captured naturally
- Consistent with the rest of the streaming emission model

### Negative
- Component templates that accept children must declare the `children` parameter explicitly — the transpiler cannot infer it
- The transpiler must detect whether a component call has child content and conditionally emit the anonymous proc wrapper

### Neutral
- `children` is last by convention, matching common patterns in other languages