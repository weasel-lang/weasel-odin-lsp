---
id: simplification-of-grammar
level: initiative
title: "Simplification of grammar"
short_code: "WEASEL-I-0003"
created_at: 2026-04-24T19:13:03.521404+00:00
updated_at: 2026-04-24T19:26:00.407585+00:00
parent: WEASEL-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/active"


exit_criteria_met: false
estimated_complexity: M
initiative_id: simplification-of-grammar
---

# Simplification of grammar Initiative

## Context

The current Weasel grammar uses `{...}` for two distinct purposes inside element bodies: expression emission (e.g. `{name}`) and host-language code blocks (e.g. `{if show { <span>visible</span> }}`). The parser distinguishes these by recognising Odin-specific keywords (`if`, `for`, `when`, `switch`).

This tight coupling to Odin syntax is a blocker for a planned future initiative that introduces multiple host-language runtimes (C, Zig, or other C-like languages). To prepare for that, we need the grammar itself to make the distinction unambiguous — without any knowledge of host-language keywords.

## Goals & Non-Goals

**Goals:**
- Introduce `$()` as the explicit, unambiguous syntax for expression emission (rendered via `__weasel_write_escaped_string`).
- Repurpose `{}` inside Weasel elements to mean strictly a block of Weasel statements/expressions, removing its current dual role.
- Update the lexer, parser, and transpiler to implement the new grammar.
- Update the LSP (source maps, position rewriting) to stay correct under the new grammar.
- Update the corpus test suite and all golden files to reflect the new syntax.

**Non-Goals:**
- Introducing actual multi-language runtime support — that is a separate future initiative.
- Changing the template declaration syntax (`name :: template(params) { ... }`).
- Changing static or dynamic attribute syntax.
- Changing component-call or children-callback conventions.

## New Grammar (Canonical Reference)

```
// Expression: emitted as an escaped string
$(props.name)

// Weasel code block: host-language control flow lives here,
// and can contain nested Weasel elements
{
    if (props.name === "Weasel") {
        <span>Cool</span>
    }
}
```

**Full example:**

```
Greet_Props :: struct {
    name: string;
}

greet :: template(props: Greet_Props) {
    <p>
        Hello, $(props.name)!
        {
            if (props.name == "Weasel") {
                <span>Cool</span>
            }
        }
    </p>
}
```

The parser no longer needs to inspect the content of `{...}` to decide its role — `$()` is always an expression, `{}` is always a code block.

## Detailed Design

### Lexer changes
- Add token `EXPR_OPEN` for `$(` and `EXPR_CLOSE` for `)` (or reuse `LPAREN`/`RPAREN` scoped after `$(`).
- `{` and `}` inside element bodies are now unambiguously `BLOCK_OPEN` / `BLOCK_CLOSE`.
- Remove any keyword-lookahead logic used to classify `{...}` content.

### Parser changes
- `parse_element_body` dispatches on token type:
  - `$(` → parse expression node (reads until matching `)`)
  - `{` → parse weasel block node (reads until matching `}`, recursing into nested element parsing within)
  - `<tag` → parse child element
  - text → emit raw text
- Remove the current heuristic that peeks at the first token inside `{...}` to choose between expression and code block.

### Transpiler changes
- Expression node (`$()`) → emit `__weasel_write_escaped_string(<expr>)`.
- Block node (`{}`) → emit the block contents verbatim, interleaving any nested Weasel element emission calls.
- No change to template signature emission or attribute handling.

### LSP / source map changes
- Source map entries for `$()` expressions must track the inner expression span, not the `$()` delimiters.
- Block nodes `{}` map similarly to the current code-block mapping.
- Position rewriting logic in `lsp/rewriter.odin` and `lsp/proxy.odin` should require no structural changes — only the offset arithmetic needs to account for the new delimiter lengths (`$(` is 2 chars, not 1).

## Alternatives Considered

**Keep `{...}` with smarter host-language detection** — rejected because it requires the compiler to know host-language keywords, which is exactly the coupling we want to eliminate.

**Use `#()` or `@()` instead of `$()`** — `$()` is conventional in template languages (JSX uses `{}`, Svelte uses `{}`, Handlebars uses `{{}}`). The `$` sigil is widely understood as "interpolation", making it the most readable choice.

**Make `$expr` (no parens) the expression syntax** — rejected because it complicates the lexer (requires whitespace/punctuation to terminate the expression) and is harder to nest.

## Implementation Plan

1. **Lexer** — add `$(` / `)` tokens, clarify `{` / `}` roles, remove keyword lookahead.
2. **Parser** — update `parse_element_body` dispatch, add expression node type, remove heuristic.
3. **Transpiler** — update emission for expression nodes and block nodes.
4. **Source maps** — adjust offset accounting for new delimiter lengths.
5. **LSP** — verify position rewriting remains correct; update any span assumptions.
6. **Tests** — rewrite corpus `.weasel` files and `.odin.golden` files for the new syntax; add dedicated expression vs block test cases.