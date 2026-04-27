---
id: host-language-agnosticism
level: initiative
title: "Host Language Agnosticism"
short_code: "WEASEL-I-0004"
created_at: 2026-04-27T08:30:35.248868+00:00
updated_at: 2026-04-27T11:06:44.952806+00:00
parent: WEASEL-V-0001
blocked_by: []
archived: false

tags:
  - "#initiative"
  - "#phase/active"


exit_criteria_met: false
estimated_complexity: L
initiative_id: host-language-agnosticism
---

# Host Language Agnosticism Initiative

## Context

Weasel is currently hardwired to Odin at every layer of the stack. The AST uses `Odin_Span` / `Odin_Block` node types, the transpiler emits hardcoded calls to `__weasel_write_raw_string` and `__weasel_write_escaped_string`, and the LSP proxy unconditionally spawns `ols` as its backend language server.

This coupling is incidental rather than fundamental. The Weasel grammar — `$(expr)` for escaped expressions, `{block}` for host-language code blocks, HTML-like element syntax — is completely independent of Odin. Any C-family language with a similar streaming write model can serve as the host language. The transpiler's core logic (element resolution, attribute handling, slot/children passing) has no Odin-specific semantics; only the call-site syntax and the two runtime function names vary between hosts.

Removing this coupling would allow Weasel to be used with C3, C++, and potentially other languages in the future without maintaining separate forks. It also makes the architecture honest: "host language" is the right conceptual boundary, and naming things `Odin_Span` when the concept is really "verbatim host code" is misleading.

## Problem Statement

- `Odin_Span`, `Odin_Block`, and `Odin_Text` token/node names leak implementation details into the grammar and AST layers where they have no business being.
- The transpiler has two hardcoded string literals for the runtime write calls (`__weasel_write_raw_string`, `__weasel_write_escaped_string`). Changing them requires editing source code.
- The LSP proxy has a hardcoded binary name (`ols`) and no mechanism to use a different language server for a different host language.
- There is no project-level configuration file. All host-language specifics are baked into the binary.

## Goals & Non-Goals

**Goals:**
- Rename `Odin_Span`, `Odin_Block`, and `Odin_Text` to `Host_Span`, `Host_Block`, and `Host_Text` (and any similar Odin-named identifiers) throughout the codebase, making the abstraction explicit.
- Introduce a project configuration file (`.weasel.json` or `.weaselrc`) that specifies host-language runtime symbols and the LSP binary to invoke.
- Make the transpiler read runtime call names from configuration rather than hardcoding them, so a C3 project can emit `weasel::write_raw_string` and a C++ project can emit `weasel::write_raw_string` with the appropriate namespace.
- Make the LSP proxy read the backend binary name (and any extra flags) from configuration, so the same `weasel-lsp` binary can proxy `clangd`, `c3-lsp`, or `ols`.
- Validate the approach against at least one non-Odin host language (C3 is the primary candidate given its similar streaming model).
- Keep Odin the default: if no configuration file is present, behavior is identical to today.

**Non-Goals:**
- Supporting dynamically typed or garbage-collected languages (Python, JavaScript, Ruby). The streaming write model and `or_return`-style error propagation assume value-typed, non-GC semantics.
- Adapting the grammar itself to different host-language expression syntax. `$(expr)` and `{block}` remain fixed delimiters regardless of host.
- Providing a full runtime library for non-Odin hosts. Each host-language user is responsible for implementing the two runtime functions (`write_raw_string`, `write_escaped_string`) in their own project.
- Building a plugin or extension system. Configuration is static and declarative, not programmatic.

## Detailed Design

Design work is ongoing and this initiative is in discovery. The following are working assumptions to be validated.

### Configuration File

A `.weasel.json` (or `.weaselrc`) at the project root specifies host-language overrides:

```json
{
  "host": {
    "write_raw":     "__weasel_write_raw_string",
    "write_escaped": "__weasel_write_escaped_string",
    "lsp_binary":    "ols",
    "lsp_args":      [],
    "preamble":      [
      "import \"core:io\"",
      "import \"lib:weasel\""
    ]
  }
}
```

Odin defaults are shown above. A C3 project would supply `"c3-lsp"`, the appropriate namespaced call names, and its own `preamble` lines.

The CLI (`weasel-c`) and LSP proxy (`weasel-lsp`) both load this file at startup. The transpiler receives the resolved names and preamble as parameters rather than reading the file itself (keeping the transpiler library pure and testable).

### Host Preamble

The transpiler currently injects a small block of Odin-specific import lines (`import "core:io"` and `import "lib:weasel"`) after the `package` declaration of the generated file whenever the output contains at least one `Template_Proc`. This injection is hardcoded today.

Under the host-agnostic model this becomes the `preamble` array in the config. The transpiler concatenates the preamble lines (each followed by a newline) and inserts the resulting block at the same position. The number of lines and total byte length of the preamble are derived from the array at runtime — the existing source-map adjustment pass (which shifts all `odin_start`/`odin_end` offsets by the injected byte length and line count) consumes these values directly, replacing the two hardcoded constants.

The LSP proxy's position-translation layer is unaffected in structure: it already relies on the source map being correctly offset after injection. What changes is that the line-count used during source map construction comes from `len(options.preamble)` rather than a literal `2`.

**`Transpile_Options` addition:**

```
Transpile_Options :: struct {
    write_raw_symbol:     string,
    write_escaped_symbol: string,
    preamble:             []string,   // lines to inject after the module/package declaration
}
```

The preamble is injected **unconditionally** — every generated file receives it regardless of whether `Template_Proc` nodes are present. A Weasel file with no template procs is unlikely to be useful on its own, and unconditional injection keeps the source map adjustment logic simple and always-active.

`.weasel.json` is located by **upward directory traversal** from the working directory at startup (the same convention as `tsconfig.json`). Both the CLI and the LSP proxy walk parent directories until they find the file or reach the filesystem root. If no file is found, built-in Odin defaults apply.

### Rename Pass

The following identifiers are renamed across the codebase (non-exhaustive; full list determined during design):

| Current name | New name |
|---|---|
| `Odin_Span` (AST node) | `Host_Span` |
| `Odin_Block` (AST node) | `Host_Block` |
| `Odin_Text` (token kind) | `Host_Text` |

Source map types and comments that refer to "Odin" in a host-language-generic context are updated similarly.

### Template Signature Portability — Host Driver Model

The current template syntax is deliberately Odin-flavoured. `name :: template(p: Props)` mirrors `name :: proc(...)` — only the keyword differs. This works for Odin but would feel foreign to C3, C++, or Zig developers. Encoding the full variation of declaration forms and emitted signatures in `.weasel.json` fields quickly becomes unwieldy; the config schema ends up encoding a mini-language-description that is harder to reason about than actual code.

The better approach mirrors the `runtime.*` contract that already exists on the user side. Introducing support for a host language already requires two artefacts:

| Artefact | Where | Purpose |
|---|---|---|
| `runtime.X` | host project, in host language | Implements `write_raw` and `write_escaped` |
| `X.odin` | weasel codebase, in Odin | Implements host-specific transpiler logic |

`X.odin` is a **host driver** — an Odin file (e.g. `odin.odin`, `c3.odin`, `zig.odin`, `cpp.odin`) that satisfies a `Host_Driver` interface. The driver encodes everything that cannot be expressed as a simple string substitution: how to identify a template declaration in the source, how to emit a host-idiomatic function signature, what the writer type and children proc type look like, and so on.

An audit of `transpile.odin` identified every Odin-specific string hardcoded in the emitter. These fall into four groups:

**Proc fields** — behaviour too complex or variable for a simple string:

| Field | Responsibility |
|---|---|
| `is_template_start` | Parser lookahead: does this token sequence open a template declaration? |
| `emit_signature` | Emit the full template function header (connector, keyword, writer param, user params, optional children param, return type). |
| `emit_dynamic_attr_write` | Emit a dynamic attribute value write. Currently `fmt.wprint(w, expr)` in Odin; each host has its own formatted-write call. |

**String fields** — simple per-host substitutions used directly by the emitter:

| Field | Odin value | Notes |
|---|---|---|
| `error_suffix` | `" or_return"` | Appended to every write call and component call (`try` in Zig, `!` in C3, etc.) |
| `function_return_stmt` | `"return nil"` | Emitted at the end of every template body and children callback |
| `children_callback_type` | `"proc(w: io.Writer) -> io.Error"` | Type of the anonymous children argument at component call sites |
| `preamble_marker` | `"package "` | Prefix that identifies the module-declaration line; preamble is injected immediately after it |

```
Host_Driver :: struct {
    // --- proc fields ---
    is_template_start:       proc(tokens: []Token) -> bool,
    emit_signature:          proc(t: ^Template_Proc, e: ^_Emitter),
    emit_dynamic_attr_write: proc(w_param, expr: string, e: ^_Emitter),

    // --- string fields ---
    error_suffix:            string,   // " or_return" / "!" / "try " etc.
    function_return_stmt:    string,   // "return nil" / "return" / ""
    children_callback_type:  string,   // anonymous proc/lambda type for children arg
    preamble_marker:         string,   // prefix of the module-declaration line
}
```

Per-host default config values (write symbols, preamble, LSP binary) are plain constants in each driver file (`odin.odin`, `c3.odin`, …), consulted by the config loader when `.weasel.json` does not override them. They have no bearing on span mapping or emission and do not belong on the behavioral interface.

The built-in drivers are compiled into the `weasel` binary. `.weasel.json` selects the active driver by name.

This keeps `.weasel.json` lean — it is a project configuration file, not a language description file:

```json
{
  "host":    "c3",
  "preamble": ["#include <weasel/runtime.h>"],
  "lsp_binary": "c3-lsp"
}
```

The `template` keyword remains the single fixed Weasel marker across all hosts. What each driver does when it encounters that keyword is entirely its own concern.

### Transpiler Parameterisation

`transpile.odin` currently has the write call names as string literals. These are replaced with fields on a `Transpile_Options` struct passed to the top-level `transpile()` call:

```
Transpile_Options :: struct {
    driver:               ^Host_Driver,
    write_raw_symbol:     string,   // resolved from driver default + .weasel.json override
    write_escaped_symbol: string,   // resolved from driver default + .weasel.json override
    preamble:             []string, // resolved from driver default + .weasel.json override
}
```

### LSP Proxy Parameterisation

`proxy.odin` / `weasel-lsp/main.odin` currently hardcodes the `ols` binary. The binary name and argument list move to `Proxy_Options`, loaded from the configuration file at startup.

## Alternatives Considered

**Per-language transpiler binaries (separate forks):** Maintain `weasel-odin`, `weasel-c3`, etc. as separate builds with different hardcoded defaults. Rejected: divergence is certain, maintenance burden grows linearly with host count, and the actual variation between hosts is two string literals and one binary name.

**Plugin/scripting system:** Allow arbitrary code to customise transpiler output. Rejected: far exceeds the scope of the variation being handled. A JSON config file is sufficient for the foreseeable use cases.

**Template files for generated code:** Use a Go-style template to define how element calls are emitted, giving per-host full control over generated syntax. Rejected: the variation is too narrow to justify this complexity. The only differences between Odin and C3 output are the namespace separator in call names and the `or_return` vs `!` error-propagation suffix — both trivially handled by config fields if they become necessary.

## Implementation Plan

This initiative is in discovery. The following phases are planned once design is settled:

1. **Discovery (current):** Confirm the scope of Odin-specific coupling; prototype the config file schema; validate against a minimal C3 example to ensure the model holds.
2. **Design:** Finalise `Transpile_Options` and `Proxy_Options` shapes, configuration file format, and the complete rename list. Produce an ADR for the config file format choice.
3. **Decompose:** Break into tasks — rename pass, config file loader, transpiler parameterisation, LSP proxy parameterisation, corpus test updates, documentation.
4. **Execute:** Implement in dependency order. The rename pass is safe to do first (purely mechanical). Config loader and parameterisation follow. End-to-end validation with a C3 project closes the initiative.

## Open Questions

No open questions remain. The `Host_Driver` interface boundary audit is complete — all Odin-specific emitter references are accounted for in the struct definition above.

## Status Updates

2026-04-27: All 4 tasks completed. Initiative implemented end-to-end:
- WEASEL-T-0025: Transpiler fully parameterised via Host_Driver/Transpile_Options; all emit paths through driver; `emit_component_call_close` added for `<slot />` and component call closes
- WEASEL-T-0026: `.weasel.json` config loader (`load_config`, `load_config_from_bytes`) with upward traversal; `Weasel_Config` struct; 8 unit tests covering full/partial/empty/malformed JSON and defaults
- WEASEL-T-0027: Config wired into `cmd/weasel-c` and `cmd/weasel-lsp`; `Proxy_Options` with `transpile` field added to lsp package; `proxy_init` accepts options; all test helpers updated
- WEASEL-T-0028: C3 host driver in `transpiler/c3_driver.odin`; `c3_transpile_options()`/`c3_default_weasel_config()`; `config_to_transpile_options` dispatches on host; 7 C3-specific unit tests; all 135+57+9 tests pass; all binaries build cleanly