---
id: implement-transpiler-static-and
level: task
title: "Implement transpiler: static and dynamic attribute handling"
short_code: "WEASEL-T-0005"
created_at: 2026-04-21T22:11:39.552179+00:00
updated_at: 2026-04-21T22:11:39.552179+00:00
parent: WEASEL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0001
---

# Implement transpiler: static and dynamic attribute handling

*This template includes sections for various types of tasks. Delete sections that don't apply to your specific use case.*

## Parent Initiative **[CONDITIONAL: Assigned Task]**

[[WEASEL-I-0001]]

## Objective

Extend the transpiler to handle element attributes — both static string values and dynamic Weasel expressions — emitting them correctly as part of the HTML string or as Odin code.

## Acceptance Criteria

- [ ] Static attributes (`attr="value"`) are folded into the opening HTML string literal: `<tag attr="value">`
- [ ] Dynamic attributes (`attr={expr}`) split the string: `__weasel_write_raw_string(w, "<tag attr=\"")`, emit expr via `fmt.wprint`, then `__weasel_write_raw_string(w, "\">")`
- [ ] Mixed static and dynamic attributes on the same element are handled correctly
- [ ] Attribute values are emitted in source order
- [ ] Dynamic attribute expressions are emitted verbatim without validation

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
In the element open-tag emitter, iterate attributes in order. Accumulate a string buffer for the opening tag; when a dynamic attribute is encountered, flush the buffer as a `__weasel_write_raw_string` call, emit the dynamic value, then continue accumulating.

### Dependencies
WEASEL-T-0004 (core transpiler)

### Risk Considerations
Dynamic attribute values need to be written as strings — the exact emit helper (`fmt.wprint`, `fmt.wprintf`, or a dedicated `__weasel_write_attr`) is an open choice that may affect the runtime support library.

## Status Updates **[REQUIRED]**

*To be added during implementation*
