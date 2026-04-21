---
id: implement-lexer-scanner-for-weasel
level: task
title: "Implement lexer / scanner for .weasel files"
short_code: "WEASEL-T-0001"
created_at: 2026-04-21T22:11:28.584791+00:00
updated_at: 2026-04-21T22:11:28.584791+00:00
parent: WEASEL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0001
---

# Implement lexer / scanner for .weasel files

*This template includes sections for various types of tasks. Delete sections that don't apply to your specific use case.*

## Parent Initiative **[CONDITIONAL: Assigned Task]**

[[WEASEL-I-0001]]

## Objective

Implement a lexer/scanner that reads a `.weasel` source file and produces a flat token stream, distinguishing Odin passthrough spans from Weasel element boundaries.

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

- [ ] Token types defined: `OdinText`, `ElementOpen` (tag name + position), `ElementClose`, `AttrStatic` (name + string value), `AttrDynamic` (name + raw expression span), `InlineExpr`, `SelfClose`
- [ ] `/<[a-z_]/` triggers element open; `</tag>` triggers element close; `/>` triggers self-close
- [ ] Odin source between Weasel markers is captured verbatim as `OdinText` tokens
- [ ] Curly-brace expressions `{...}` inside element content are tokenized as `InlineExpr` with the inner span
- [ ] Lexer handles nested curly braces correctly (Odin code inside `{}` may contain `{}`)
- [ ] Returns meaningful errors with line/column for malformed input

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
Single-pass character scanner. Track a simple state machine: `InOdin`, `InElementOpen`, `InElementContent`, `InAttr`, `InExpr`. Brace depth counter handles nested `{}`.

### Dependencies
None — this is the foundation task.

### Risk Considerations
Nested braces are the main complexity: `{for x in y { <tag/> }}` requires correct depth tracking to avoid splitting Odin code mid-expression.

## Status Updates **[REQUIRED]**

*To be added during implementation*