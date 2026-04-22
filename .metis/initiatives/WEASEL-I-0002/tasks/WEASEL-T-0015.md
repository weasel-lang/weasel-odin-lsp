---
id: end-to-end-editor-validation
level: task
title: "End-to-end editor validation against a sample Weasel project"
short_code: "WEASEL-T-0015"
created_at: 2026-04-22T17:55:37.506994+00:00
updated_at: 2026-04-22T17:55:37.506994+00:00
parent: WEASEL-I-0002
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0002
---

# End-to-end editor validation against a sample Weasel project

## Parent Initiative

[[WEASEL-I-0002]]

## Objective

Prove the whole chain works in a real editor. Stand up a small Weasel sample project, configure an editor (VS Code or Neovim) to launch `weasel-lsp` for `.weasel` files, and manually verify that the core LSP features work at correct positions. This is the initiative's exit criterion.

## Acceptance Criteria

- [ ] A sample Weasel project exists under `examples/` (or similar) with at least: one Weasel template that imports and calls another, some identifiers that reference Odin stdlib, and a mix of static/dynamic attributes.
- [ ] Editor configuration is documented (VS Code client JSON or Neovim lua snippet) that starts `weasel-lsp` for `.weasel` files.
- [ ] Hover on an identifier in a `.weasel` file shows the same type/doc `ols` would show on the generated Odin.
- [ ] Go-to-definition on an Odin identifier inside a `.weasel` file navigates to the correct location (may be another `.weasel` file or Odin source).
- [ ] Completion at a cursor position inside a Weasel attribute expression returns sensible candidates from `ols`.
- [ ] Diagnostics from `ols` appear on the correct Weasel lines; errors on generated-only scaffolding are not shown.
- [ ] A short README documents how to try the sample project end-to-end.

## Implementation Notes

### Technical Approach

Pick one editor to validate — VS Code is easiest because `vscode-languageclient` accepts a stdio server command directly with no extension scaffolding needed for a prototype. Neovim with `nvim-lspconfig` is an acceptable alternative. Record findings (good/bad/ugly) in the initiative's Status Updates on the way through.

### Dependencies

- WEASEL-T-0014 (proxy is feature-complete enough for the listed LSP methods).
- `ols` installed.

### Risk Considerations

This is where integration reality hits. Expect to uncover at least one off-by-one in coordinate translation (LSP uses zero-based line/column; the transpiler/lexer may use one-based) that nothing before this task will catch. Budget for a round-trip back into T-0010/T-0011 if so.

## Status Updates

*To be added during implementation*