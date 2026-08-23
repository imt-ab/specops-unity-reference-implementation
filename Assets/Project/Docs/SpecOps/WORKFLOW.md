# SpecOps v2 Workflow

Status: Derived process documentation. This file is not authority.

This workflow explains how to apply [`SPECOPS_V2.md`](SPECOPS_V2.md) with the repository's [structural authority](../Architecture/ARCHITECTURE.md), [global constraints](../Governance/GLOBAL_CONSTRAINTS.md), and applicable feature authority. If this guide conflicts with current authority, current authority wins and work stops for clarification.

## Logical Lifecycle

Intent
→ Specification
→ Governance review
→ Risk classification
→ Human approval when required
→ Plan
→ Scoped permission
→ Implementation
→ Validation
→ Traceability
→ Synchronization and global-impact review
→ Human review, check-in, or publication where required

The lifecycle describes logical responsibilities. It does not assign those responsibilities to named AI products, IDE agents, or tools.

The seven installed derived procedures under `.agents/skills/` map this lifecycle to specification, review, planning, implementation, validation, synchronization, and audit responsibilities. They route through `.specops/specops.json` and remain subordinate to current authority.

## 1. Establish Intent and Authority

State the requested outcome, exclusions, and completion boundary. Locate the framework, architecture, repository constraints, and feature authority that apply. Missing or conflicting authority is a stop condition.

## 2. Stabilize Specification and Acceptance

Create or review explicit feature intent, constraints, and deterministic acceptance criteria before implementation. Identify non-goals, edge cases, architecture impact, manual Unity work, and validation expectations.

Acceptance criteria remain stable during an implementation slice. Material changes return the work to specification and invalidate the affected downstream plan and permission.

## 3. Review Governance and Risk

Check authority alignment, cross-feature effects, architectural drift, protected areas, external effects, and evidence gaps. Assign R0–R3 using the framework authority. Obtain explicit Human Authority approval where the risk or repository policy requires it.

Findings should be canonical, scoped, and evidence-linked. Resolve bounded mechanical issues without unrelated rewrites. Present consequential choices to Human Authority rather than selecting them silently.

## 4. Plan a Bounded Slice

A slice identifies:

- its outcome and acceptance identifiers;
- affected authority and implementation areas;
- files or systems expected to change;
- protected and explicitly excluded areas;
- validation evidence required;
- risk, approval, permission, and stop boundary.

Prefer the smallest coherent vertical result. Planning does not authorize implementation.

## 5. Grant Scoped Permission

Permission is granted for the selected slice only. Confirm allowed actions, targets, risk ceiling, approvals, validation, and expiry before mutation. Availability of tools, credentials, or writable systems does not expand permission.

Use the installed `.specops/permissions.json` profiles and `.specops/contracts/implementation-plan.schema.json` contract. These derived structures record scope, permission, and approval but do not grant them. Human-authorized scope and approval must remain explicit and traceable.

## 6. Implement Minimally

Implement only the selected slice. Preserve repository safety, architecture boundaries, metadata, and unrelated work. Stop on unexpected files, dependencies, protected-area changes, or a need to widen scope.

## 7. Validate and Form a Verdict

Use deterministic validation where suitable and authorized. Record what ran, what did not run, results, limitations, and remaining unknowns. A verdict must follow evidence and must not imply tests or execution that did not occur.

Validation responsibility is logically distinct from implementation responsibility even when one executor performs both. Evidence must remain reviewable.

## 8. Preserve Traceability

Connect the authorized intent, acceptance, risk, approval, permission, diff, validation, and unresolved observations. Derived plans and reports record this chain but do not become authority.

## 9. Review Global Impact

After implementation evidence exists, determine whether the slice changes repository-wide constraints or structural truth. Consequential changes require Human Authority. Accepted outcomes must be synchronized into the relevant current authority; ADRs retain rationale but do not substitute for that synchronization.

## 10. Human Review and Publication

Human Authority retains final control over consequential check-in, merge, push, release, deployment, and publication according to repository policy. Completion of implementation or validation does not grant the next lifecycle permission.
