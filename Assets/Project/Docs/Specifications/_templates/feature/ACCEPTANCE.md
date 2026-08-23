# TEMPLATE — Feature Acceptance Criteria

Status: TEMPLATE — NOT CURRENT AUTHORITY — NOT APPROVED BY DEFAULT

Acceptance criteria define observable outcomes, not implementation preferences, unless implementation structure is itself required by current authority. Do not record validation results or mark template criteria PASS.

## Identifier and Stability Rules

- Use stable identifiers in the form `AC-001`, `AC-002`, and so on.
- Do not reuse an identifier for a different outcome.
- Keep identifiers and meanings stable throughout an implementation slice.
- A material criterion change invalidates the affected downstream plan and permission and returns the work to specification and review.
- Retain superseded identifiers in feature history rather than silently renumbering remaining criteria.

## Criterion Template

Copy this section once for each real criterion. `AC-NNN` and all angle-bracketed values are placeholders, not feature requirements.

### AC-NNN — `<SHORT_OUTCOME_NAME>`

- Requirement / observable outcome: `<WHAT_MUST_BE_OBSERVED>`
- Deterministic validation method: `<COMMAND_TEST_INSPECTION_OR_PROCEDURE>`
- Evidence expectation: `<EXACT_RESULT_OR_RETAINED_EVIDENCE>`
- Validation category: `<STATIC_COMPILATION_EDIT_MODE_PLAY_MODE_MANUAL_OR_OTHER>`
- Manual requirement: `<REQUIRED_STEPS_AND_REASON_AUTOMATION_IS_NOT_SUITABLE_OR_NONE>`
- Optional Given/When/Then framing:
  - Given: `<PRECONDITION>`
  - When: `<ACTION>`
  - Then: `<OBSERVABLE_OUTCOME>`

## Traceability References

- Feature specification: `Assets/Project/Docs/Specifications/<feature>/SPEC.md`
- Feature constraints: `Assets/Project/Docs/Specifications/<feature>/CONSTRAINTS.md`
- Related authority or ADRs: `<REPOSITORY_RELATIVE_PATHS_OR_NONE>`
