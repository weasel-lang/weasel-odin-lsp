---
id: implement-transpiler-component
level: task
title: "Implement transpiler: component calls with children proc callback"
short_code: "WEASEL-T-0006"
created_at: 2026-04-21T22:11:42.917418+00:00
updated_at: 2026-04-21T22:11:42.917418+00:00
parent: WEASEL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0001
---

# Implement transpiler: component calls with children proc callback

*This template includes sections for various types of tasks. Delete sections that don't apply to your specific use case.*

## Parent Initiative **[CONDITIONAL: Assigned Task]**

[[WEASEL-I-0001]]

## Objective

Extend the transpiler to emit component template calls for Weasel elements that resolve to template procs via the heuristic in WEASEL-A-0002. When the component has nested children, wrap them in an anonymous `proc(w: io.Writer) -> io.Error` callback as per WEASEL-A-0001.

## Backlog Item Details **[CONDITIONAL: Backlog Item]**

{Delete this section when task is assigned to an initiative}

### Type
- [ ] Bug - Production issue that needs fixing
- [ ] Feature - New functionality or enhancement  
- [ ] Tech Debt - Code improvement or refactoring
- [ ] Chore - Maintenance or setup work

### Priority
- [ ] P0 - Critical (blocks users/revenue)
- [ ] P1 - High (important for user experience)
- [ ] P2 - Medium (nice to have)
- [ ] P3 - Low (when time permits)

### Impact Assessment **[CONDITIONAL: Bug]**
- **Affected Users**: {Number/percentage of users affected}
- **Reproduction Steps**: 
  1. {Step 1}
  2. {Step 2}
  3. {Step 3}
- **Expected vs Actual**: {What should happen vs what happens}

### Business Justification **[CONDITIONAL: Feature]**
- **User Value**: {Why users need this}
- **Business Value**: {Impact on metrics/revenue}
- **Effort Estimate**: {Rough size - S/M/L/XL}

### Technical Debt Impact **[CONDITIONAL: Tech Debt]**
- **Current Problems**: {What's difficult/slow/buggy now}
- **Benefits of Fixing**: {What improves after refactoring}
- **Risk Assessment**: {Risks of not addressing this}

## Acceptance Criteria

- [ ] Elements resolved as template procs (via the WEASEL-A-0002 heuristic) are emitted as proc calls: `tag_name(w, &Tag_Props{...}) or_return`
- [ ] Dotted names (`ui.card`) are emitted as qualified calls: `ui.card(w, &Card_Props{...}) or_return`
- [ ] Attributes on component tags map to struct fields in a composite literal passed as a pointer: `title="Task"` → `&Card_Props{title = "Task"}`
- [ ] Self-closing component elements (`<tag />`) emit a call with no children argument
- [ ] Component elements with nested children emit an anonymous proc as the last argument: `tag(w, &Tag_Props{...}, proc(w: io.Writer) -> io.Error { ... }) or_return`
- [ ] The nested children inside the anonymous proc are themselves fully transpiled (recursion)
- [ ] Passing child content to a component that has no `<slot />` in its definition is a transpile-time error
- [ ] Blocked by WEASEL-T-0004 (core transpiler)

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
In the element emitter, apply the three-rule heuristic from WEASEL-A-0002: if the tag resolves to a template proc, emit a proc call instead of raw string writes. Attributes are collected and emitted as a `&Tag_Props{field = value, ...}` composite literal. If the element has children, open an anonymous proc literal `proc(w: io.Writer) -> io.Error {`, recursively emit children, then close with `return nil\n}` and pass it as the final argument, followed by `or_return`.

### Dependencies
WEASEL-T-0004 (core transpiler)

### Risk Considerations
Anonymous proc literals in Odin capture outer variables by reference. If the component is called inside a loop, the loop variable is captured correctly — but the transpiler must ensure the emitted `w` parameter name in the inner proc shadows the outer `w` without conflict.

## Status Updates **[REQUIRED]**

*To be added during implementation*