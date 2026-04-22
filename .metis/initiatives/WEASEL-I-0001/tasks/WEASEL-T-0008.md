---
id: build-round-trip-test-suite-for
level: task
title: "Build round-trip test suite for transpiler output"
short_code: "WEASEL-T-0008"
created_at: 2026-04-21T22:11:48.952763+00:00
updated_at: 2026-04-22T14:00:42.505513+00:00
parent: WEASEL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0001
---

# Build round-trip test suite for transpiler output

*This template includes sections for various types of tasks. Delete sections that don't apply to your specific use case.*

## Parent Initiative **[CONDITIONAL: Assigned Task]**

[[WEASEL-I-0001]]

## Objective

Build a round-trip test suite that feeds `.weasel` input through the full pipeline and asserts the transpiled `.odin` output matches expected golden files. Covers the core language features: raw elements, component calls, attributes, control flow, and children callbacks.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] Golden file test for raw element emission: `<div>text</div>` → expected Odin output
- [ ] Golden file test for template proc signature rewrite
- [ ] Golden file test for static attributes
- [ ] Golden file test for dynamic attributes
- [ ] Golden file test for component call without children
- [ ] Golden file test for component call with nested children (anonymous proc callback)
- [ ] Golden file test for inline Odin control flow (`for`, `if`, `switch`) inside elements
- [ ] Test runner reports diff on mismatch, with option to update golden files (`--update`)

## Implementation Notes **[CONDITIONAL: Technical Task]**

{Keep for technical tasks, delete for non-technical. Technical details, approach, or important considerations}

### Technical Approach
Golden file approach: `tests/corpus/` contains pairs of `.weasel` input and `.odin.golden` expected output. Test runner calls the pipeline directly (not via CLI) and diffs the result. `--update` flag overwrites golden files for easy snapshot updates.

### Dependencies
All transpiler tasks (WEASEL-T-0004, WEASEL-T-0005, WEASEL-T-0006)

### Risk Considerations
Golden files will need updating whenever the emitted code format changes (e.g. whitespace, helper function names). Keep golden files minimal and focused — one feature per fixture — to limit churn.

## Status Updates **[REQUIRED]**

### 2026-04-22 — Implementation complete

**Transpiler fix**: Changed `_emit_odin_block` to emit `Odin_Span` children with `in_html=false` (Odin context) instead of `in_html=true` (HTML context). This fixes `switch` case labels being incorrectly emitted as `__weasel_write_raw_string` calls. All 93 existing unit tests still pass.

**Test runner**: Created `tests/main.odin` — a standalone Odin binary (`package corpus_tests`) that:
- Globs `tests/corpus/*.weasel` (or `--corpus <dir>`)
- Transpiles each fixture through the full pipeline
- Diffs output against `.odin.golden` file; reports line-level differences on mismatch
- Accepts `--update` flag to overwrite golden files

**Corpus fixtures** (`tests/corpus/`):
- `raw_element.weasel` — `<div>Hello, world!</div>` covers basic open/text/close emission
- `template_proc.weasel` — `greet :: template(name: string)` covers signature rewrite + body
- `static_attrs.weasel` — `<a href="/home" class="nav">` covers static attr folding
- `dynamic_attrs.weasel` — `<div id={eid} class="box">` covers dynamic attr splitting
- `component_no_children.weasel` — `<card title="Hello" size={n} />` covers props struct emit
- `component_with_children.weasel` — `<layout><p>{msg}</p></layout>` covers anonymous proc callback
- `control_flow.weasel` — `for`, `if`, `switch` all in one fixture; switch case labels now emit correctly

All 7 golden files generated and all 7 tests pass. Running: `odin run tests/` or `odin run tests/ -- --update`.