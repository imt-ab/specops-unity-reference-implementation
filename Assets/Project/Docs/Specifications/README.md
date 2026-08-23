# Feature Specifications

Status: Operational index and template guidance. This file is not feature authority.

## Feature Authority

An instantiated feature lives at `Assets/Project/Docs/Specifications/<feature>/`. Its current feature authority is exactly this approved triplet:

- `<feature>/SPEC.md` — intent, goals, non-goals, and requirements;
- `<feature>/CONSTRAINTS.md` — feature-specific constraints;
- `<feature>/ACCEPTANCE.md` — stable, testable acceptance criteria.

Only an instantiated and approved triplet can become feature authority. A template, a partial copy, this README, or a derived state file is never feature authority. Feature authority remains bounded by the [framework authority](../SpecOps/SPECOPS_V2.md), [structural authority](../Architecture/ARCHITECTURE.md), and [repository-wide constraints](../Governance/GLOBAL_CONSTRAINTS.md). It cannot silently override higher-scope authority. A conflict or missing authority stops work for Human Authority clarification.

## Derived State

`<feature>/SPECOPS_STATE.json` is derived, non-authoritative lifecycle and traceability state. It must conform to the [feature-state schema](../../../../.specops/contracts/feature-state.schema.json), but schema conformance does not make it authority.

State is rebuilt or synchronized from review, approval, plan, implementation, validation, synchronization, and ADR evidence. Do not edit state to manufacture a desired truth, infer completion from a status without its evidence, or copy requirements, constraints, or acceptance prose into it.

The reusable state template uses `R3` with pending approval as a protective placeholder because the schema requires a risk value. That placeholder is not a completed risk assessment. Every instantiated feature must receive an actual R0–R3 classification through review before permission or implementation relies on state.

## Canonical Feature Templates

The sole canonical feature-template location is [`_templates/feature/`](_templates/feature/). Copy all four files into a new `<feature>/` directory, replace every template placeholder, and complete the required review and approval process. Copying does not approve the feature.

The canonical template contains:

- [`SPEC.md`](_templates/feature/SPEC.md)
- [`CONSTRAINTS.md`](_templates/feature/CONSTRAINTS.md)
- [`ACCEPTANCE.md`](_templates/feature/ACCEPTANCE.md)
- [`SPECOPS_STATE.json`](_templates/feature/SPECOPS_STATE.json)

Older files directly under `_templates/` remain as legacy compatibility routers for retained links. They are not a second canonical template location and must not be instantiated.

## Acceptance Stability

Acceptance criteria use stable identifiers such as `AC-001`, `AC-002`, and so on. Identifiers remain stable throughout an implementation slice. A material change to an acceptance criterion invalidates the affected downstream plan and permission and returns the work to specification and review.

Acceptance criteria test observable outcomes. Implementation structure belongs in acceptance only when that structure is itself required by current authority.

## ADR Traceability

Feature specifications and derived state may reference ADRs for decision rationale and history. ADR acceptance is decision approval only; it does not automatically synchronize current authority. ADR references never replace framework, structural, repository-wide, or feature authority.
