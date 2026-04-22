---
id: build-round-trip-test-suite-for
level: task
title: "Build round-trip test suite for transpiler output"
short_code: "WEASEL-T-0008"
created_at: 2026-04-21T22:11:48.952763+00:00
updated_at: 2026-04-21T22:11:48.952763+00:00
parent: WEASEL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


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

- [ ] Golden file test for raw element emission: `<div>text</div>` → expected Odin output
- [ ] Golden file test for template proc signature rewrite
- [ ] Golden file test for static attributes
- [ ] Golden file test for dynamic attributes
- [ ] Golden file test for component call without children
- [ ] Golden file test for component call with nested children (anonymous proc callback)
- [ ] Golden file test for inline Odin control flow (`for`, `if`) inside elements
- [ ] Test runner reports diff on mismatch, with option to update golden files (`--update`)

## Test Cases **[CONDITIONAL: Testing Task]**

{Delete unless this is a testing task}

### Test Case 1: {Test Case Name}
- **Test ID**: TC-001
- **Preconditions**: {What must be true before testing}
- **Steps**: 
  1. {Step 1}
  2. {Step 2}
  3. {Step 3}
- **Expected Results**: {What should happen}
- **Actual Results**: {To be filled during execution}
- **Status**: {Pass/Fail/Blocked}

### Test Case 2: {Test Case Name}
- **Test ID**: TC-002
- **Preconditions**: {What must be true before testing}
- **Steps**: 
  1. {Step 1}
  2. {Step 2}
- **Expected Results**: {What should happen}
- **Actual Results**: {To be filled during execution}
- **Status**: {Pass/Fail/Blocked}

## Documentation Sections **[CONDITIONAL: Documentation Task]**

{Delete unless this is a documentation task}

### User Guide Content
- **Feature Description**: {What this feature does and why it's useful}
- **Prerequisites**: {What users need before using this feature}
- **Step-by-Step Instructions**:
  1. {Step 1 with screenshots/examples}
  2. {Step 2 with screenshots/examples}
  3. {Step 3 with screenshots/examples}

### Troubleshooting Guide
- **Common Issue 1**: {Problem description and solution}
- **Common Issue 2**: {Problem description and solution}
- **Error Messages**: {List of error messages and what they mean}

### API Documentation **[CONDITIONAL: API Documentation]**
- **Endpoint**: {API endpoint description}
- **Parameters**: {Required and optional parameters}
- **Example Request**: {Code example}
- **Example Response**: {Expected response format}

## Implementation Notes **[CONDITIONAL: Technical Task]**

{Keep for technical tasks, delete for non-technical. Technical details, approach, or important considerations}

### Technical Approach
Golden file approach: `tests/fixtures/` contains pairs of `.weasel` input and `.odin.golden` expected output. Test runner calls the pipeline directly (not via CLI) and diffs the result. `--update` flag overwrites golden files for easy snapshot updates.

### Dependencies
All transpiler tasks (WEASEL-T-0004, WEASEL-T-0005, WEASEL-T-0006)

### Risk Considerations
Golden files will need updating whenever the emitted code format changes (e.g. whitespace, helper function names). Keep golden files minimal and focused — one feature per fixture — to limit churn.

## Status Updates **[REQUIRED]**

*To be added during implementation*
