---
id: implement-transpiler-template
level: task
title: "Implement transpiler: template signatures and raw element emission"
short_code: "WEASEL-T-0004"
created_at: 2026-04-21T22:11:36.142301+00:00
updated_at: 2026-04-21T22:11:36.142301+00:00
parent: WEASEL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0001
---

# Implement transpiler: template signatures and raw element emission

*This template includes sections for various types of tasks. Delete sections that don't apply to your specific use case.*

## Parent Initiative **[CONDITIONAL: Assigned Task]**

[[WEASEL-I-0001]]

## Objective

Implement the core transpiler: walk the AST and emit valid Odin source. This task covers the two foundational cases — rewriting `template` procedure signatures to `proc` with a leading `w: io.Writer` parameter, and emitting raw HTML elements as `__weasel_write_raw_string` calls.

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

- [ ] `template` keyword in proc declaration is replaced with `proc`
- [ ] `w: io.Writer` is inserted as the first parameter in every template proc signature
- [ ] Raw HTML elements (not in registry) emit `__weasel_write_raw_string(w, "<tag>") or_return` for open and `__weasel_write_raw_string(w, "</tag>") or_return` for close
- [ ] Self-closing raw elements emit a single combined open+close string (e.g. `<br/>`)
- [ ] `OdinSpan` nodes are emitted verbatim, preserving whitespace and formatting
- [ ] Inline expressions `{expr}` emit the inner expression verbatim (no wrapper)

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
AST walker that writes to a `strings.Builder`. Each node type has a dedicated emit function. `OdinSpan` nodes write directly; `ElementNode` nodes dispatch on raw vs component (deferred to T-0006).

### Dependencies
WEASEL-T-0003 (parser)

### Risk Considerations
The `or_return` suffix on write calls means the emitted proc must return an error type. The transpiler should ensure the generated proc signature is compatible (e.g. `-> io.Error`).

## Status Updates **[REQUIRED]**

*To be added during implementation*