---
id: weasel-parser-and-transpiler
level: initiative
title: "Weasel parser and transpiler"
short_code: "WEASEL-I-0001"
created_at: 2026-04-21T21:55:13.088260+00:00
updated_at: 2026-04-21T22:11:25.048757+00:00
parent: WEASEL-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/decompose"


exit_criteria_met: false
estimated_complexity: XL
initiative_id: weasel-parser-and-transpiler
---

# Weasel parser and transpiler Initiative

## Context

Weasel is a templating language for the [Odin programming language](https://odin-lang.org/) inspired by JSX/TSX. It allows writing HTML-like templates embedded in Odin source files, using a `template` keyword in place of `proc`. The Weasel toolchain must parse these `.weasel` files and transpile them into valid Odin code that writes HTML to an `io.Writer`.

## Goals & Non-Goals

**Goals:**
- Parse Weasel source files containing mixed Odin code and Weasel elements
- Transpile Weasel templates into valid Odin procedures that write HTML to an `io.Writer`
- Support static and dynamic attributes on Weasel elements
- Support component composition (one template calling another as a Weasel element)
- Support inline Odin control flow (loops, conditionals) inside Weasel elements

**Non-Goals:**
- Runtime HTML sanitization or escaping (out of scope for transpiler)
- IDE language server / syntax highlighting (separate initiative)
- Supporting the captured-subtree pattern (`cards := (<>...</>)`) in the initial version — procedural emission only

## Detailed Design

### Template Procedure Signatures

Weasel templates use the `template` keyword instead of `proc`:

```
task_item :: template(p: ^task_item_props)
```

Rules:
- Templates accept 0 or 1 arguments.
- If an argument is passed, it is a struct pointer parameter (similar to TSX "props").

Transpiled output inserts a leading `w: io.Writer` parameter:

```odin
task_item :: proc(w: io.Writer, p: ^task_item_props)
```

### Weasel Elements

A Weasel element has an opening and a closing tag. Opening tags begin with `<` directly followed by a lowercase letter or underscore (`/<[a-z_]/`). Tags may carry static string attributes and dynamic Weasel-expression attributes:

```
<tag attr="static" dynamic={weasel-expr}>
    static text
    {weasel-code}
</tag>
```

- `weasel-expr` / `weasel-code` is emitted verbatim — the transpiler does not validate it as Odin.
- Component tags (e.g. `<ui.card>`) map to procedure calls on the same `io.Writer`.

### Code Emission Strategy

The transpiler uses **procedural emission**: as it encounters Weasel elements during a linear parse, it emits `io.Writer` calls in order. This avoids the need to build an intermediate tree and makes the output straightforward.

Example input:

```
task_list :: template(p: ^task_list_props) {
    <ul>
        {
            for task in p.tasks {
                <ui.card>
                    <task_item task={task} />
                </ui.card>
            }
        }
    </ul>
}
```

Example output:

```odin
task_list :: proc(w: io.Writer, p: ^task_list_props) {
    __weasel_write_raw_string(w, "<ul>") or_return
    for task in p.tasks {
        ui.card(w, { /* children TBD */ })
    }
    __weasel_write_raw_string(w, "</ul>") or_return
}
```

Children are passed as a `proc(w: io.Writer)` callback (see WEASEL-A-0001). The transpiler wraps nested content in an anonymous proc at the call site, which preserves the streaming model and allows outer-scope variable capture.

### Parser Approach

The parser must handle two interleaved grammars:
1. Odin source (passed through largely verbatim)
2. Weasel elements (detected by `/<[a-z_]/` and `</>` patterns)

A recursive descent approach is appropriate given the nesting structure.

### Element Resolution Heuristic

Element resolution uses a stateless heuristic with no pre-pass (see WEASEL-A-0002):

1. Tag names containing `-` → raw HTML (custom web component)
2. Tag name in the hard-coded HTML element map → raw HTML
3. Anything else → template proc call

This means naming is load-bearing: `<card>` calls the `card` template proc; `<div>` always emits raw HTML. Template procs must not be named after standard HTML elements.

## Alternatives Considered

- **Captured subtrees (`cards := (<>...</>)`)**: Deferred — requires buffering into a temporary `io.Writer`, complicating the emission model. Can be added later once the procedural model is solid.
- **AST-based transpiler**: Fully parsing Odin before processing Weasel elements would be more correct but requires a complete Odin parser. Chosen approach (scan for Weasel markers, pass Odin verbatim) is simpler and sufficient.
- **Return-string model (like JSX)**: Not viable given Odin's performance goals; `io.Writer` streaming is the right fit.

## Implementation Plan

1. **Lexer / scanner** — tokenize `.weasel` files, distinguishing Odin passthrough from Weasel element boundaries
2. **Parser** — recursive descent, building a minimal AST for Weasel elements while preserving Odin spans
3. **Transpiler / code generator** — walk the AST and emit valid Odin source
4. **CLI tool** — `weasel build` command that processes `.weasel` files and writes `.odin` output
5. **Test suite** — round-trip tests comparing transpiled output against expected Odin snippets
6. **Children / slots design** — ADR and implementation for passing nested content to component calls