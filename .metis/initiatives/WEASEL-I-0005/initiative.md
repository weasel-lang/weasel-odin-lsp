---
id: weasel-element-attribute-spreads
level: initiative
title: "Weasel element attribute spreads"
short_code: "WEASEL-I-0005"
created_at: 2026-04-27T15:09:16.694503+00:00
updated_at: 2026-04-27T16:54:41.490839+00:00
parent: WEASEL-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/completed"


exit_criteria_met: false
estimated_complexity: S
initiative_id: weasel-element-attribute-spreads
---

# Weasel element attribute spreads Initiative

## Context

Weasel components receive typed props structs. When a component wraps a native HTML element (e.g., a `Card` wrapping a `<div>`), callers have no way to pass arbitrary additional HTML attributes (ARIA attributes, `data-*`, `id`, event handlers, class overrides) to the inner element. This is a well-known ergonomic gap: TSX solves it with the spread operator (`{...props}`).

Weasel needs an equivalent: a `$(...expr)` syntax in element attribute position that passes a bag of attributes through to a host element. The spread is distinct from the existing `$(expr)` expression syntax and requires a new lexer token, a new AST node, and a new entry point in the `Host_Driver` interface so each host language can control how its attribute type is serialised.

## Goals & Non-Goals

**Goals:**
- Add `$(...expr)` spread syntax in element attribute position
- Introduce a new lexer token (`Token_Kind.Spread_Expr` or similar) for the `$(...` prefix so the parser needs no lookahead
- Add a `Spread_Attr` AST node produced by the parser when encountering the spread token
- Extend the `Host_Driver` interface with an `emit_spread` (or equivalent) emitter
- Implement the Odin driver: emit call to Odin runtime `weasel.write_spread(w, expr)` where expression now is code not a string.
- Define `Attribute_Value` (union of `int`, `bool`, `string`) and `Attributes` (`map[string]Attribute_Value`) in the Odin runtime
- Implement `write_spread` in `runtime.odin` that iterates over an `Attributes` map and emit each `key="value"` pair
- Corpus tests covering spread in static context, spread mixed with static attributes, and spread in a component call

**Non-Goals:**
- Spread syntax outside of element attribute position (e.g., inside element bodies or proc arguments)
- Deep-merging of spread with static attributes — ordering and precedence is the author's responsibility
- Implementing spread for non-Odin host drivers beyond the interface stub (those are follow-on work per-driver)

## Architecture

### Overview

The spread travels the same pipeline as other attribute forms: lexer → parser → AST → transpiler → host driver emission.

```
$(...p.attrs)
     │
     ▼
Lexer:       Token{ kind = .Spread_Expr_Start }  followed by expr text  then  Token{ kind = .Rparen }
     │
     ▼
Parser:      Spread_Attr{ expr = "p.attrs" }   (new AST node, child of Element_Node.attrs)
     │
     ▼
Transpiler:  calls host_driver.emit_spread(w, "p.attrs")
     │
     ▼
Odin driver: emits code to call runtime `weasel.write_spread(w, p.attrs)`   (note the expression is now verbatim)
     │
     ▼
Odin runtime: write_spread :: proc(...) { for key, val in attrs { io.write_string(w, ` key="..."`); } }
```

### Lexer change

The existing expression token starts with `$(`. The spread token starts with `$(...`. Since the lexer is a state machine with character-by-character lookahead, detecting `$(...` vs `$(` requires reading three characters before deciding. The cleanest approach is to produce a dedicated `Token_Kind` (e.g. `.Spread_Expr`) for this case so the parser never needs to inspect the token text to distinguish spread from expression.

### Parser / AST change

`Element_Node.attrs` is a slice of attribute variants. A new `Spread_Attr` variant is added:

```
Spread_Attr :: struct {
    expr: string,   // raw source text of the spread argument, e.g. "p.attrs"
}
```

`parse_element_attributes` recognises `.Spread_Expr` token and appends a `Spread_Attr` to the attrs slice.

### Transpiler change

In `transpile_element`, when iterating attributes, a `Spread_Attr` branch calls:

```
host_driver.emit_spread(w, spread.expr)
```

No change to the source map logic is needed — spread attrs do not map back to a Weasel position at sub-attribute granularity.

### Type safety

Weasel itself does not type-check spread expressions — it treats the expression as an opaque string and emits it verbatim into the generated host-language code. Type correctness is enforced by the host language compiler: if the expression passed to `$(...expr)` is not of the correct type (`weasel.Attributes` in Odin), the generated code will not compile. This gives strong static guarantees at development time without requiring Weasel to understand host-language types.

### Host driver interface change

```
Host_Driver :: struct {
    // ... existing fields ...
    emit_spread: proc(w: io.Writer, expr: string) -> io.Error,
}
```

### Odin runtime additions

```odin
// runtime.odin
Attribute_Value :: union {
    int,
    bool,
    string,
}

Attributes :: map[string]Attribute_Value
```

The Odin driver's `emit_spread` emits code to call upon the Odin runtime's `emit_spread` which then iterates the map and writes `key="value"` pairs, applying the same HTML escaping as `write_escaped_string` for string values. `bool` attributes emit as bare attribute names when true and are omitted when false. `int` values are written as decimal strings.

## Detailed Design

**Spread syntax:**
```
<div class="p-2" $(...p.attrs)>
```

Multiple spreads on one element are valid and are emitted in declaration order:
```
<div $(...defaults) $(...overrides)>
```

Mixing static attributes and spreads is valid; the author controls ordering:
```
<div id="card" $(...p.attrs) class="base">
```

**Transpiler output (Odin):**
```odin
// <div class="p-2" $(...p.attrs)>
weasel.write_string(w, `<div class="p-2"`) or_return
weasel.write_spread(w, p.attrs) or_return
weasel.write_string(w, `>`) or_return
```

`write_spread` is a top-level helper defined in the Odin runtime.

## Alternatives Considered

**Reuse `$(expr)` token with parser lookahead for `...`** — rejected. Adding lookahead to distinguish spread from expression couples the parser to token internals and makes error messages harder to produce. A dedicated token is the pattern already used elsewhere in the lexer (e.g. `.Block_Start` vs expression start).

**Convention-based spread via a special prop name (e.g. `attrs:`)** — rejected. It would require an out-of-band contract between template author and caller with no syntax-level enforcement, and would not compose naturally with multiple spreads.

**Inline spread resolution in transpiler (no driver delegation)** — rejected. Hard-coding Odin map iteration in the transpiler defeats the host-agnosticism established by WEASEL-I-0004. The driver boundary must be respected.

## Implementation Plan

1. **Runtime types** — Add `Attribute_Value` and `Attributes` to `runtime.odin`
2. **Host driver interface** — Add `emit_spread` to `Host_Driver` and implement it in the Odin driver
3. **Lexer** — Add `$(...` detection and new `Token_Kind` variant
4. **Parser / AST** — Add `Spread_Attr` node, update `parse_element_attributes`
5. **Transpiler** — Handle `Spread_Attr` in attribute emission loop
6. **Corpus tests** — Add fixtures: spread-only, spread + static attrs, multiple spreads