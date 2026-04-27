---
id: corpus-tests-for-attribute-spread
level: task
title: "Corpus tests for attribute spread: spread-only, mixed static, multiple spreads"
short_code: "WEASEL-T-0034"
created_at: 2026-04-27T15:41:53.776124+00:00
updated_at: 2026-04-27T16:54:41.024347+00:00
parent: WEASEL-I-0005
blocked_by: []
archived: false

tags:
  - "#task"
  - "#phase/completed"


exit_criteria_met: false
initiative_id: WEASEL-I-0005
---

# Corpus tests for attribute spread: spread-only, mixed static, multiple spreads

## Parent Initiative

[[WEASEL-I-0005]]

## Objective

Add `.weasel` corpus fixture files covering the three spread scenarios defined in the initiative and generate their `.odin.golden` files, giving the test suite full regression coverage for attribute spread.

## Acceptance Criteria

## Acceptance Criteria

## Acceptance Criteria

- [ ] `tests/corpus/spread_only.weasel` exists — a template with a single element using only `$(...expr)` and no static attrs
- [ ] `tests/corpus/spread_static_mix.weasel` exists — static attrs before and after a spread on the same element
- [ ] `tests/corpus/spread_multiple.weasel` exists — two or more spread attrs on a single element
- [ ] All three corresponding `.odin.golden` files exist and are committed
- [ ] `odin run tests/` exits with no diffs

## Implementation Notes

### Technical Approach
Create the three `.weasel` fixtures first, then run `odin run tests/ -- --update` to generate the golden files. Inspect each golden file manually to confirm the emitted `weasel.write_spread(w, ...)` calls appear at the correct positions relative to surrounding `weasel.write_raw_string` calls.

### Dependencies
Depends on all prior tasks (WEASEL-T-0029 through WEASEL-T-0033) being complete; the transpiler must produce correct output before golden files can be generated.

### Risk Considerations
Map iteration order in `write_spread` is non-deterministic. Corpus fixtures should not assert on the order of spread attribute output in the golden file — or, if the runtime sorts by key before emitting, document that decision so the golden files remain stable.

## Status Updates

**2026-04-27** — Complete. Created three corpus fixtures: `spread_only.weasel` (spread-only attribute), `spread_static_mix.weasel` (static attrs before and after a spread), `spread_multiple.weasel` (two spread attrs). Generated golden files via `odin run tests/ -- --update`. Verified all 12 corpus tests pass (9 existing unchanged, 3 new). Golden files correctly show `write_raw_string` calls split at spread boundaries and `write_spread` calls in declaration order.