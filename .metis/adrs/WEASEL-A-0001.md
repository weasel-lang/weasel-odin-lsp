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

Children are passed as a `proc(w: io.Writer) -> io.Error` callback parameter. The transpiler wraps the nested content in an anonymous proc at the call site. The `children` parameter is the last parameter by convention and is **inferred by the transpiler** — a template that contains `<slot />` in its body automatically receives a `children` parameter in the generated Odin proc; no explicit declaration is needed in Weasel source.

### Weasel source

```weasel
Card_Props :: struct {
    title: string,
}

card :: template(p: ^Card_Props) {
    <div class="card">
        <h2>{p.title}</h2>
        <slot />
    </div>
}

Task_Item_Props :: struct {
    task: ^Task_Data,
}

task_item :: template(p: ^Task_Item_Props) {
    <card title="Task">
        <p>{p.task.description}</p>
    </card>
}
```

### Transpiled Odin

```odin
Card_Props :: struct {   // Regular Odin code, emitted verbatim
    title: string,
}

// `children` parameter added because <slot /> appears in the source template
card :: proc(w: io.Writer, p: ^Card_Props, children: proc(w: io.Writer) -> io.Error) -> io.Error {
    __weasel_write_raw_string(w, "<div class=\"card\">") or_return
    __weasel_write_raw_string(w, "<h2>") or_return
    __weasel_write_escaped_string(w, p.title) or_return
    __weasel_write_raw_string(w, "</h2>") or_return
    children(w) or_return   // <slot /> expands to this
    __weasel_write_raw_string(w, "</div>") or_return
    return nil
}

Task_Item_Props :: struct {   // Regular Odin code, emitted verbatim
    task: ^Task_Data,
}

task_item :: proc(w: io.Writer, p: ^Task_Item_Props) -> io.Error {
    // <card title="Task"> with children: attributes map to struct fields,
    // child content is wrapped in an anonymous proc
    card(w, &Card_Props{title = "Task"}, proc(w: io.Writer) -> io.Error {
        __weasel_write_raw_string(w, "<p>") or_return
        __weasel_write_escaped_string(w, p.task.description) or_return
        __weasel_write_raw_string(w, "</p>") or_return
        return nil
    }) or_return
    return nil
}
```

Key points in the transpilation:
- `{p.title}` interpolation emits `__weasel_write_escaped_string` (HTML-escaped by default)
- Attributes on component tags (`title="Task"`) map directly to struct field names in a composite literal
- The composite literal is passed as a pointer (`&Card_Props{...}`) to match the `^Card_Props` parameter
- All template procs return `io.Error`; every call uses `or_return` so errors propagate without buffering
- The anonymous proc captures outer-scope variables (e.g. `p`) naturally via Odin's closure semantics

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
- The transpiler must detect whether a template body contains `<slot />` and conditionally add the `children` parameter to the generated proc signature
- The transpiler must detect whether a component call has child content and conditionally emit the anonymous proc wrapper
- Templates without `<slot />` cannot accept children — passing child content to such a template is a transpile-time error

### Neutral
- `children` is last by convention, matching common patterns in other languages
