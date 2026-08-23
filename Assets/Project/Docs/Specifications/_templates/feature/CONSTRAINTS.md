# TEMPLATE — Feature Constraints

Status: TEMPLATE — NOT CURRENT AUTHORITY — NOT APPROVED BY DEFAULT

Use this file only for feature-specific constraints. Do not duplicate repository-wide rules unnecessarily; reference higher authority instead.

This template and any instantiated feature constraints cannot override:

- [SpecOps framework authority](../../../SpecOps/SPECOPS_V2.md)
- [Structural authority](../../../Architecture/ARCHITECTURE.md)
- [Repository-wide engineering constraints](../../../Governance/GLOBAL_CONSTRAINTS.md)

A conflict stops work for clarification by Human Authority. A proposed change to current authority is separate R3 work.

## Architecture

- Must: `<FEATURE_SPECIFIC_ARCHITECTURE_CONSTRAINT_OR_NONE>`
- Must not: `<FEATURE_SPECIFIC_ARCHITECTURE_PROHIBITION_OR_NONE>`

## Dependencies

- `<ALLOWED_OR_REQUIRED_DEPENDENCY_CONSTRAINT_OR_NONE>`

Documenting a dependency addition, removal, or upgrade does not authorize it.

## Performance

- Frame-time or latency budget: `<BUDGET_OR_NOT_APPLICABLE>`
- Throughput budget: `<BUDGET_OR_NOT_APPLICABLE>`

## Memory and Allocation

- Memory budget: `<BUDGET_OR_NOT_APPLICABLE>`
- Allocation or GC budget: `<BUDGET_OR_NOT_APPLICABLE>`

## Unity and Runtime

- Target runtime/platform conditions: `<CONDITIONS_OR_NONE>`
- Lifecycle, scene, serialization, or engine constraints: `<CONSTRAINTS_OR_NONE>`

## Persistence and Data

- Data ownership, format, migration, retention, or consistency: `<CONSTRAINTS_OR_NONE>`

## Security and Privacy

- Trust boundaries, secrets, personal data, or access constraints: `<CONSTRAINTS_OR_NONE>`

## Compatibility

- Backward, interoperability, platform, save-data, or API compatibility: `<CONSTRAINTS_OR_NONE>`

## Tooling and Build

- Feature-specific build or validation constraints: `<CONSTRAINTS_OR_NONE>`

Tool availability is not authorization, and product/executor assignments do not belong in this file.

## Operational and Manual Constraints

- `<CONSTRAINT_OR_NONE>`

## Traceability References

- Feature specification: `Assets/Project/Docs/Specifications/<feature>/SPEC.md`
- Acceptance criteria: `Assets/Project/Docs/Specifications/<feature>/ACCEPTANCE.md`
- Related authority or ADRs: `<REPOSITORY_RELATIVE_PATHS_OR_NONE>`
