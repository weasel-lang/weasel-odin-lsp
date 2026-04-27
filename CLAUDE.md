# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

Weasel is a JSX-style HTML templating extension for the Odin programming language. It transpiles `.weasel` files (Odin with embedded HTML) into pure `.odin` files. The output uses a streaming write model — all HTML emission calls an `io.Writer` directly with no buffering.

## Commands

```sh
# Run corpus (golden file) tests — all languages
odin run tests/

# Run corpus tests for a single language
odin run tests/ -- --language odin
odin run tests/ -- --language c3

# Update golden files after intentional output changes
odin run tests/ -- --update
odin run tests/ -- --update --language c3

# Run unit tests for a module
odin test transpiler/
odin test lsp/

# Build the CLI transpiler
odin build cmd/weasel-c/ -out:weasel

# Build the LSP proxy
odin build cmd/weasel-lsp/ -out:weasel-lsp
```

There is no Makefile. All test and build commands use the `odin` CLI directly.

## Architecture

The pipeline is: `.weasel` source → **Lexer** → token stream → **Parser** → AST → **Transpiler** → `.odin` source + `Source_Map`.

### transpiler/

- **lexer.odin** — Scanner with two modes: depth=0 is plain Odin passthrough; depth>0 (inside an element body) activates Weasel syntax. Tokenizes element boundaries, `$(expr)` expressions, `{block}` code blocks, and static/dynamic attributes.
- **parser.odin** — Recursive descent parser producing a typed AST. Node types: `Odin_Span` (verbatim Odin), `Expr_Node` (`$(expr)`), `Element_Node` (HTML tag or component call), `Odin_Block` (`{...}` containing nested Weasel), `Template_Proc` (a `template(...)` definition).
- **transpile.odin** — Walks the AST and emits Odin. Key mapping: `Template_Proc` → `proc(w: io.Writer, ...)`, `Expr_Node` → `__weasel_write_escaped_string(...)`, HTML elements → `__weasel_write_raw_string(...)`, component calls → `tag(w, &Tag_Props{...}) or_return`. Appends `Span_Entry` records to a `Source_Map` during emission.
- **tags.odin** — Stateless heuristic for resolving whether a tag is a raw HTML element or a component call. Rules in order: contains `-` → raw; in the WHATWG known-tag set → raw; otherwise → component. No pre-pass or registry needed.
- **source_map.odin** — `Source_Map` is a slice of `Span_Entry` values mapping generated Odin byte ranges back to originating Weasel byte ranges. Sorted by `odin_start.offset` after transpilation for binary search.

### lsp/

The LSP layer is a proxy that sits between the editor and `ols` (the Odin Language Server). It holds all `.weasel` documents in memory as their generated `.odin` equivalents.

- **proxy.odin** — Central coordinator. `Document` holds per-URI state: Weasel source, generated Odin text, `Source_Map`, and a `Translator`. On `textDocument/didChange`, re-transpiles in-memory and forwards the updated Odin to `ols`. On `textDocument/didSave`, writes the generated `.odin` to disk. URI mapping: `foo.weasel` ↔ `foo.weasel.odin`.
- **rewriter.odin** — Bidirectional position translation. Incoming editor requests carry Weasel positions → translated to Odin positions before forwarding to `ols`. Responses from `ols` carry Odin positions → translated back to Weasel positions for the editor.
- **source_map_index.odin** — Secondary index over the `Source_Map`, keyed by Weasel byte offset, used by the `Translator` for O(log n) Weasel→Odin lookups (the primary source map is keyed by Odin offset).
- **framing.odin** — LSP JSON-RPC wire framing (`Content-Length: N\r\n\r\n<body>`).

### cmd/

- **weasel-c/main.odin** — CLI driver: `weasel generate [--out <dir>] [--force] <file.weasel>...`. Uses a 4 MB arena allocator per file.
- **weasel-lsp/main.odin** — Spawns `ols` as a child process, routes editor ↔ `ols` messages through two I/O threads calling `proxy_process_editor_message` / `proxy_process_ols_message`.

### tests/

- **tests/main.odin** — Corpus runner. Iterates known language configs (`odin`, `c3`, …), globs `tests/<lang>/*.weasel`, transpiles each with the matching driver, and diffs against the corresponding golden file. Shows up to 10 line-level differences per file. `--update` overwrites golden files; `--language <name>` restricts to one language.
- **tests/odin/** — Fixture pairs for Odin output: `feature.weasel` + `feature.odin.golden`.
- **tests/c3/** — Fixture pairs for C3 output: `feature.weasel` + `feature.c3.golden`.
- Golden files are right-trimmed (trailing blank lines removed). Adding a new language driver requires adding an entry to the `languages` array in `tests/main.odin`.

### runtime.odin

Defines `__weasel_write_escaped_string` (XSS-escapes `&`, `"`, `'`, `<`, `>`) and `__weasel_write_raw_string`. These are called directly by transpiler output and must be linked into any Weasel-based project.

## Key Conventions

**Grammar syntax** — `$(expr)` emits an HTML-escaped expression; `{block}` is a host-language code block that may contain nested Weasel elements. These are deliberately unambiguous (no keyword lookahead).

**Children / slots** — A `template` body containing `<slot />` automatically receives a `children: proc(w: io.Writer) -> io.Error` parameter. At call sites, child content is wrapped in an anonymous proc and passed as the last argument. No allocation; streaming throughout.

**Component props** — `<tag attr="val" dyn=$(expr) />` emits `tag(w, &Tag_Props{attr = "val", dyn = expr}) or_return`. The props struct name is derived by capitalising the tag's local name and appending `_Props` (e.g. `item` → `Item_Props`).

**Positions** — `Position` is `{offset, line, col}` (offset is a byte index; line and col are 1-indexed). Use `advance_position()` to walk forward byte-by-byte.

**Error collection** — Errors are appended to a slice rather than returned early, so multiple errors can be reported in one pass.

**Adding a corpus fixture** — Create `tests/<lang>/name.weasel`, run `odin run tests/ -- --update --language <lang>` to generate the golden file, then commit both files.
