---
id: tests-rewrite-corpus-files-and-add
level: task
title: "Tests: rewrite corpus files and add expression-vs-block cases"
short_code: "WEASEL-T-0021"
created_at: 2026-04-24T19:20:50.924111+00:00
updated_at: 2026-04-24T19:20:50.924111+00:00
parent: WEASEL-I-0003
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0003
---

# Tests: rewrite corpus files and add expression-vs-block cases

## Parent Initiative

[[WEASEL-I-0003]]

## Objective

Update all corpus test files under `tests/corpus/` to use the new grammar: replace `{expr}` expression syntax with `$(expr)` and wrap code blocks in unambiguous `{}`. Update the corresponding `.odin.golden` files to match the new transpiler output. Add at least one new corpus pair (`expression_emission.weasel` / `.odin.golden`) that explicitly exercises expression emission alongside a code block to prevent regression. Depends on WEASEL-T-0018 (transpiler output).

## Acceptance Criteria

- [ ] All existing `tests/corpus/*.weasel` files updated to `$(expr)` syntax for expressions
- [ ] All corresponding `tests/corpus/*.odin.golden` files updated to match new transpiler output
- [ ] New `expression_emission.weasel` + `.odin.golden` corpus pair added covering `$()` alongside `{}`
- [ ] Full test suite (`tests/main.odin`) passes with zero failures

## Implementation Notes

### Files
- `tests/corpus/*.weasel` — replace `{expr}` with `$(expr)`, wrap code blocks in `{}`
- `tests/corpus/*.odin.golden` — update expected output
- `tests/corpus/expression_emission.weasel` + `.odin.golden` — new test case

### Dependencies
- WEASEL-T-0018 (transpiler output must be stable before updating golden files)

## Status Updates

*To be added during implementation*

