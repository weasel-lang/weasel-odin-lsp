---
id: implement-transpiler-template
level: task
title: "Implement transpiler: template signatures and raw element emission"
short_code: "WEASEL-T-0004"
created_at: 2026-04-21T22:11:36.142301+00:00
updated_at: 2026-04-22T12:10:09.038424+00:00
parent: WEASEL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0001
---

# Implement transpiler: template signatures and raw element emission

*This template includes sections for various types of tasks. Delete sections that don't apply to your specific use case.*

## Parent Initiative **[CONDITIONAL: Assigned Task]**

[[WEASEL-I-0001]]

## Objective

Implement the core transpiler: walk the AST and emit valid Odin source. This task covers the two foundational cases — rewriting `template` procedure signatures to `proc` with a leading `w: io.Writer` parameter, and emitting raw HTML elements as `__weasel_write_raw_string` calls.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] `template` keyword in proc declaration is replaced with `proc`
- [ ] `w: io.Writer` is inserted as the first parameter in every template proc signature
- [ ] Every generated template proc has `-> io.Error` as its return type
- [ ] If a template body contains `<slot />`, a `children: proc(w: io.Writer) -> io.Error` parameter is appended to the generated proc signature
- [ ] `<slot />` in the template body emits `children(w) or_return`
- [ ] Raw HTML elements emit `__weasel_write_raw_string(w, "<tag>") or_return` for open and `__weasel_write_raw_string(w, "</tag>") or_return` for close
- [ ] Self-closing raw elements emit a single combined open+close string (e.g. `<br/>`)
- [ ] `Odin_Span` nodes are emitted verbatim, preserving whitespace and formatting
- [ ] Inline expressions `{expr}` emit `__weasel_write_escaped_string(w, expr) or_return` (HTML-escaped by default)

## Implementation Notes **[CONDITIONAL: Technical Task]**

{Keep for technical tasks, delete for non-technical. Technical details, approach, or important considerations}

### Technical Approach
AST walker that writes to a `strings.Builder`. Each node type has a dedicated emit function. `Odin_Span` nodes write directly; `Element_Node` nodes dispatch on raw vs component (deferred to T-0006).

### Dependencies
WEASEL-T-0003 (parser)

### Risk Considerations
The `or_return` suffix on write calls means the emitted proc must return an error type. The transpiler should ensure the generated proc signature is compatible (e.g. `-> io.Error`).

## Status Updates **[REQUIRED]**

### 2026-04-22 — Implementation complete

Created `transpiler/transpile.odin` and `transpiler/transpile_test.odin`.

**What was implemented:**
- `transpile(nodes []Node) -> (string, [dynamic]Transpile_Error)` — main entry point
- `_emit_template_proc` — rewrites `name :: template(params)` to `name :: proc(w: io.Writer, params) -> io.Error`. Appends `children: proc(w: io.Writer) -> io.Error` when `has_slot == true`
- `_emit_raw_element` — void elements (br, hr, img, etc.) emit `<tag/>` as a single self-closing string; non-void elements emit separate open + close calls
- `_emit_element` — `<slot />` emits `children(w) or_return`; `.Component` elements record a Transpile_Error (deferred to T-0006)
- `_emit_odin_block` — control-flow blocks: emit `head{` + children + `}`
- `_emit_node` — `Odin_Span` verbatim; `Expr_Node` → `__weasel_write_escaped_string`

**Tests:** 19 new tests in `transpile_test.odin`; all 73 tests across the package pass.

**2026-04-22 — Addendum:** Fixed `Odin_Span` emission in HTML context. Added `in_html: bool` parameter to `_emit_node`. Text content inside element children (e.g. `"Hello"` in `<div>Hello</div>`) is now emitted as `__weasel_write_raw_string(w, "Hello") or_return` rather than as verbatim Odin. Added `_write_string_literal_content` helper for proper escaping of `"`, `\`, and control characters. Template body spans (indentation/Odin code) remain verbatim. Added 4 new tests covering: static text, mixed static+dynamic (`<div>Hello {p.user.name}!</div>`), ordering, and quote escaping.

**All acceptance criteria met.**