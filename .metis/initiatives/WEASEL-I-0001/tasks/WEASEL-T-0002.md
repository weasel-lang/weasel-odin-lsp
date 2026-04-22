---
id: implement-first-pass-template-proc
level: task
title: "Implement first-pass template proc registry"
short_code: "WEASEL-T-0002"
created_at: 2026-04-21T22:11:30.810170+00:00
updated_at: 2026-04-22T11:05:44.332849+00:00
parent: WEASEL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0001
---

# Implement element resolution heuristic

## Parent Initiative **[CONDITIONAL: Assigned Task]**

[[WEASEL-I-0001]]

## Objective

Implement the stateless element resolution heuristic (see WEASEL-A-0002) used by the transpiler to decide whether a Weasel element tag should be emitted as raw HTML or as a template proc call. No source-scanning pre-pass is required.

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

## Acceptance Criteria

## Acceptance Criteria

- [ ] Tag names containing `-` always resolve to `Raw` (custom web component rule)
- [ ] A hard-coded map of all standard HTML elements is defined (covering the full WHATWG living standard, including uncommon tags like `details`, `dialog`, `summary`, `canvas`, `picture`, `slot`, etc.)
- [ ] Tag names in the HTML map resolve to `Raw`
- [ ] Any other tag name resolves to `Component`
- [ ] Resolution logic is a pure function `resolve_tag(name: string) -> TagKind` with no global state
- [ ] `resolve_tag` is unit-tested directly, independent of the lexer and parser

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
Define a `TagKind` enum (`Raw`, `Component`) and a `resolve_tag` function. Check the dash rule first (O(n) on name length), then map lookup against the HTML tag set (O(1) hash or O(log n) sorted slice), then default to `Component`.

### Dependencies
None — pure logic, no dependency on the lexer or parser. Can be implemented and tested in isolation.

### Risk Considerations
The HTML tag map must be comprehensive. Use the WHATWG HTML living standard element list as the source of truth to avoid missing uncommon but valid tags.

## Status Updates **[REQUIRED]**

### 2026-04-22 — Implementation complete

Created two files:

- `transpiler/tags.odin` — defines `Tag_Kind` enum (`Raw`, `Component`) and `resolve_tag(name: string) -> Tag_Kind`. Pure function, no global state, no allocations. Three-rule heuristic: dash rule → HTML map (full WHATWG living standard including `details`, `dialog`, `summary`, `canvas`, `picture`, `slot`, `search`, `hgroup`, etc.) → default Component.

- `transpiler/tags_test.odin` — 14 unit tests covering: dash rule variants, common HTML tags, uncommon/rarely-tested HTML tags, media/table tag groups, Component resolution for custom names, package-qualified names, empty string, near-miss names.

All 28 tests pass (14 lexer + 14 tags).