---
id: weasel
level: vision
title: "weasel"
short_code: "WEASEL-V-0001"
created_at: 2026-04-21T20:39:51.449880+00:00
updated_at: 2026-04-21T20:59:55.507485+00:00
archived: false

tags:
  - "#vision"
  - "#phase/published"


exit_criteria_met: false
initiative_id: NULL
---

# Weasel Vision

Weasel is a variant of the Odin programming language that introduces JSX/TSX-style HTML templating directly within Odin source files. It enables server-side rendered web applications with a developer experience on par with TypeScript + TSX, but backed by Odin's native compilation toolchain for superior performance and memory efficiency.

## Purpose

Web developers working in TypeScript + TSX enjoy tight integration between UI markup and application logic. Odin developers building server-side applications lack an equivalent ergonomic option. Weasel closes that gap: bringing HTML-in-code templating to Odin without sacrificing the language's performance characteristics or requiring a runtime VM.

## Product/Solution Overview

Weasel is a language extension and toolchain for Odin projects:

- `.weasel` files coexist with `.odin` files in the same project
- Weasel syntax extends Odin with embedded HTML-like expressions (no virtual DOM)
- A CLI transpiler converts `.weasel` files to plain `.odin` files, fitting naturally into existing Odin build workflows
- An LSP server provides IDE support by routing messages to the appropriate backend: `ols` (Odin Language Server) for Odin code, and an HTML+Tailwind CSS LSP for Weasel expressions
- Prebuilt binaries are distributed via GitHub Actions for Linux (x86_64) and macOS (Apple Silicon), with Windows planned

Target audience: Odin developers building server-side rendered web applications.

## Current State

- No HTML templating story exists in the Odin ecosystem
- Odin developers must either use external template engines (losing type safety and IDE support) or generate HTML programmatically (verbose, error-prone)
- The `ols` LSP covers Odin code well but has no concept of embedded markup

## Future State

- Developers write `.weasel` files combining Odin logic with inline HTML expressions, with full IDE support (completions, hover, diagnostics) across both language domains
- The CLI integrates into `odin build` workflows transparently — `.weasel` files are transpiled to `.odin` before compilation
- Applications built with Weasel are compiled to native binaries via Odin's toolchain, achieving throughput and memory efficiency exceeding equivalent Bun+TSX applications
- Binaries ship via GitHub Releases for Linux and macOS Silicon (Windows to follow)

## Major Features

- **Weasel syntax**: Odin files with embedded HTML-like expressions in `.weasel` files — familiar to any TSX developer
- **CLI transpiler**: `weasel build` (or equivalent) converts `.weasel` → `.odin`; composable with `odin build`
- **Hybrid LSP**: Single LSP server that routes diagnostics, completions, and hover to `ols` or HTML+Tailwind LSP based on cursor position
- **GitHub Actions distribution**: Automated builds and releases for Linux x86_64 and macOS Apple Silicon

## Success Criteria

- A developer can write a server-side rendered page in Weasel with full IDE completions and diagnostics for both Odin code and HTML/Tailwind expressions
- The CLI transpiler produces valid `.odin` files that compile without modification via `odin build`
- A representative SSR benchmark shows Weasel-compiled binaries outperform an equivalent Bun+TSX application in throughput and memory usage
- Prebuilt binaries are available on GitHub Releases for Linux x86_64 and macOS Apple Silicon

## Principles

- **Odin-first**: Weasel is a thin layer over Odin, not a new language. Generated `.odin` files must be readable and idiomatic.
- **No runtime overhead**: No virtual DOM, no GC, no managed runtime. HTML templating compiles away entirely.
- **Composable tooling**: The CLI and LSP are standalone tools that fit into existing Odin workflows rather than replacing them.
- **DX parity with TSX**: If a TypeScript+TSX developer would expect a feature, Weasel should provide it.

## Constraints

- Weasel targets server-side rendering only — no client-side interactivity framework is in scope
- The transpiler output must be valid, unmodified Odin; no fork of the Odin compiler is planned
- Initial platform support is Linux x86_64 and macOS Apple Silicon; Windows support is deferred but must remain architecturally possible
- The project depends on upstream `ols` and an HTML+Tailwind LSP remaining available and maintained