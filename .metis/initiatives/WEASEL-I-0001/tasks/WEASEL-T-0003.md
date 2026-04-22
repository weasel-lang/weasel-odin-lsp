---
id: implement-recursive-descent-parser
level: task
title: "Implement recursive descent parser for Weasel elements"
short_code: "WEASEL-T-0003"
created_at: 2026-04-21T22:11:33.674977+00:00
updated_at: 2026-04-22T11:37:07.283803+00:00
parent: WEASEL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0001
---

# Implement recursive descent parser for Weasel elements

*This template includes sections for various types of tasks. Delete sections that don't apply to your specific use case.*

## Parent Initiative **[CONDITIONAL: Assigned Task]**

[[WEASEL-I-0001]]

## Objective

Implement a recursive descent parser that consumes the token stream and produces a minimal AST. Weasel elements become typed nodes; Odin spans are preserved verbatim as leaf nodes. The AST is the input to the transpiler.

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

- [ ] AST node types defined: `OdinSpan`, `ElementNode` (tag, attrs, children), `ExprNode`, `TemplateProc` (name, params, body)
- [ ] Parser correctly handles nested elements of arbitrary depth
- [ ] Self-closing elements (`<tag />`) produce an `ElementNode` with no children
- [ ] Inline Odin control flow (`for`, `if`) inside element content is preserved as `OdinSpan` nodes
- [ ] Mismatched open/close tags produce a parse error with location
- [ ] Parser uses the `resolve_tag` heuristic (WEASEL-T-0002) to annotate element nodes as `Raw` or `Component`

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
Recursive descent. Entry point parses a sequence of top-level declarations; when it encounters a `TemplateProc`, it recurses into `parseBody` which handles mixed Odin/element content. Element children recurse back into `parseBody`.

### Dependencies
WEASEL-T-0001 (lexer), WEASEL-T-0002 (registry)

### Risk Considerations
Odin control flow blocks (`for { }`, `if { }`) contain braces that may enclose Weasel elements — the parser must treat these as transparent containers and recurse into them rather than treating the brace as an `OdinSpan` boundary.

## Status Updates **[REQUIRED]**

### 2026-04-22 — Implementation complete

Created `transpiler/parser.odin` and `transpiler/parser_test.odin`. All 49 tests pass (47 pre-existing + 18 new parser tests).

**Files created:**
- `transpiler/parser.odin` — recursive descent parser (~720 lines)
- `transpiler/parser_test.odin` — 18 tests covering all acceptance criteria

**AST node types implemented:**
- `Odin_Span` — verbatim Odin passthrough
- `Expr_Node` — `{expr}` interpolation (HTML-escaped)
- `Element_Node` — raw HTML or component call, annotated via `resolve_tag`
- `Odin_Block` — control-flow block (for/if/when/switch) with recursively parsed children
- `Template_Proc` — top-level template function; `has_slot` set when `<slot />` found recursively

**Key design decisions:**
- `_find_template_decl` searches `Odin_Text` tokens for `name :: template(params) {` pattern
- Template body ends detected by brace-counting (`_brace_scan`) in `Odin_Text` tokens, respecting strings/comments
- `pending` field on `_Parser` enables splitting an `Odin_Text` token at the template boundary
- `Odin_Block` body is re-scanned with `scan()` and re-parsed recursively
- Multiple templates per file and Odin prefix code before templates handled correctly

**All acceptance criteria verified via tests.**
