# TEMPLATE — Feature Specification

Status: TEMPLATE — NOT CURRENT AUTHORITY — NOT APPROVED BY DEFAULT

Instantiation: Copy the complete canonical feature template into `Assets/Project/Docs/Specifications/<feature>/`, replace every placeholder, and complete review and approval. This template must not be used as an implementation plan or validation-result record.

## Identity

- Feature ID: `<FEATURE_ID>`
- Title: `<FEATURE_TITLE>`
- Feature status: Draft
- Applicable feature path: `Assets/Project/Docs/Specifications/<feature>/`

## Purpose / Problem

Describe the observed problem, affected users or systems, and why this feature is needed.

## Users and Use Cases

- Affected user, actor, or system: `<ACTOR>`
- Intended use case or optional user story: `<USE_CASE_OR_USER_STORY>`

## Goals

- `<GOAL>`

## Non-goals

- `<NON_GOAL>`

## Functional Requirements

- `FR-001` — `<REQUIRED_BEHAVIOR>`

## Non-functional Requirements

Record only requirements that apply, such as determinism, latency, throughput, accessibility, reliability, security, or observability.

- `NFR-001` — `<MEASURABLE_REQUIREMENT>`

## Inputs, Outputs, and Behavior

- Inputs: `<INPUTS>`
- Outputs: `<OUTPUTS>`
- State transitions or externally observable behavior: `<BEHAVIOR>`

## Edge Cases and Failure Behavior

- `<EDGE_CASE_OR_FAILURE>` — `<EXPECTED_OUTCOME>`

## Dependencies and External Assumptions

Identify required services, packages, assets, platforms, external systems, or environmental assumptions. A dependency change is not authorized by documenting it here.

- `<DEPENDENCY_OR_ASSUMPTION>`

## Architecture Impact

Reference the [structural authority](../../../Architecture/ARCHITECTURE.md). Identify affected layers, shared contracts, ownership, lifecycle, dependency directions, composition, or other structural impact. If no impact is expected, record the evidence supporting that conclusion.

- Affected layers or contracts: `<IMPACT>`
- ADR required or referenced: `<ADR_PATH_OR_NONE>`

## Global-Constraint Impact

Reference the [repository-wide constraints](../../../Governance/GLOBAL_CONSTRAINTS.md). Identify any cross-feature, repository-wide, logging, testing, safety, compatibility, or operational impact. A required authority change is separate R3 work and cannot be approved by this specification.

- Impact: `<IMPACT_OR_NONE_WITH_EVIDENCE>`

## Validation Considerations

Identify high-level validation categories, runtime-only assumptions, lifecycle concerns, or manual evidence needs. Define criterion-specific methods and evidence in `ACCEPTANCE.md`; do not record plans or results here.

- `<VALIDATION_CONSIDERATION_OR_NONE>`

## Manual or External Steps

- `<MANUAL_OR_EXTERNAL_STEP_OR_NONE>`

## Open Questions

- `<OPEN_QUESTION_OR_NONE>`

Unresolved authority conflicts or material ambiguity stop implementation.

## Traceability References

- Framework authority: [`SPECOPS_V2.md`](../../../SpecOps/SPECOPS_V2.md)
- Structural authority: [`ARCHITECTURE.md`](../../../Architecture/ARCHITECTURE.md)
- Repository-wide constraints: [`GLOBAL_CONSTRAINTS.md`](../../../Governance/GLOBAL_CONSTRAINTS.md)
- Acceptance criteria: `Assets/Project/Docs/Specifications/<feature>/ACCEPTANCE.md`
- Related features or ADRs: `<REPOSITORY_RELATIVE_PATHS_OR_NONE>`
