---
id: implement-weasel-cli-tool-weasel
level: task
title: "Implement weasel CLI tool (weasel build)"
short_code: "WEASEL-T-0007"
created_at: 2026-04-21T22:11:45.900088+00:00
updated_at: 2026-04-21T22:11:45.900088+00:00
parent: WEASEL-I-0001
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/todo"


exit_criteria_met: false
initiative_id: WEASEL-I-0001
---

# Implement weasel CLI tool (weasel build)

*This template includes sections for various types of tasks. Delete sections that don't apply to your specific use case.*

## Parent Initiative **[CONDITIONAL: Assigned Task]**

[[WEASEL-I-0001]]

## Objective

Implement the `weasel build` CLI command that accepts one or more `.weasel` source files, runs the lexer → registry → parser → transpiler pipeline, and writes the resulting `.odin` files to disk.

## Acceptance Criteria

- [ ] `weasel build <file.weasel>` writes `<file.odin` alongside the input file
- [ ] Multiple file arguments are supported; each produces its own `.odin` output
- [ ] Non-zero exit code and descriptive error message on parse or transpile failure
- [ ] `--out <dir>` flag optionally redirects output to a different directory
- [ ] Skips files that are already up-to-date (mtime comparison) unless `--force` is passed
- [ ] Prints a summary of files processed on success

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
Thin CLI wrapper (Odin `main` package) that parses args, calls the pipeline in sequence, and handles errors. mtime check uses `os.stat` on input and output files.

### Dependencies
WEASEL-T-0004, WEASEL-T-0005, WEASEL-T-0006 (full transpiler)

### Risk Considerations
The CLI is the integration point — it should be implemented last so the pipeline is stable first.

## Status Updates **[REQUIRED]**

*To be added during implementation*
