---
id: 001-template-props-by-value
level: adr
title: "Template props by value"
number: 1
short_code: "WEASEL-A-0003"
created_at: 2026-04-25T11:54:10.380135+00:00
updated_at: 2026-04-25T11:58:07.475201+00:00
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

# ADR-1: Template props by value

## Context

Weasel templates accept a props struct at their call sites (e.g. `<item title="Hello" count=$(n) />`). The transpiler emits these as a struct literal passed by pointer: `item(w, &Item_Props{title = "Hello", count = n}) or_return`. This means every call site allocates a temporary struct, raising questions about ownership and allocator lifetime.

In practice, props structs will only ever contain primitives, strings, dynamic arrays, and pointers — all of which are cheap to copy. There are no large values or types that require careful ownership tracking.

## Decision

Props structs are passed by value (copy), not by pointer. The transpiler emits `item(w, Item_Props{title = "Hello", count = n}) or_return` without the `&` address-of operator. Template proc signatures accept `props: Tag_Props` rather than `props: ^Tag_Props`.

## Rationale

Since props fields are constrained to cheap-to-copy types, pass-by-value costs nothing meaningful. It eliminates the need to think about heap allocation, allocator lifetimes, or pointer validity at call sites. The resulting generated code is simpler and ownership is trivially clear — the callee gets its own copy and the caller's stack frame is unaffected.

## Consequences

### Positive
- No heap allocation at call sites; props live on the stack and are discarded automatically.
- Generated code is simpler (no `&` operators, no pointer dereferencing in template bodies).
- Ownership is unambiguous — no aliasing between caller and callee.

### Negative
- If a future props field needs to be large or non-copyable, this convention would need to be revisited.

### Neutral
- Odin's calling convention handles small struct copies efficiently; this is idiomatic for the language.