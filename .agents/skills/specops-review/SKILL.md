---
name: specops-review
description: Perform read-only SpecOps governance and implementability review with a structured PASS, BLOCK, or NEEDS_APPROVAL verdict.
---

# SpecOps Review

Status: Derived read-only procedure. This Skill is not authority and cannot override current authority.

## Authority and Instance Routing

1. Read `.specops/specops.json` for repository-relative authority, feature, contract, and deployment paths. The manifest is derived instance configuration.
2. Read all applicable current authority before review.
3. Read `.specops/permissions.json` and operate under `READ_ONLY`.
4. Use repository instance configuration for VCS or tool behavior; reusable review semantics remain VCS-neutral and executor-neutral.

## Procedure

- Confirm explicit review scope and work-item identifier.
- Review authority alignment, ambiguity, acceptance stability, implementability, repository constraints, architecture impact, evidence gaps, and unresolved unknowns.
- Classify risk using R0–R3 from framework authority.
- Identify the required permission profile and Human Authority requirement.
- Use only the verdict vocabulary `PASS`, `BLOCK`, or `NEEDS_APPROVAL`.
- Produce output conforming to `.specops/contracts/review-verdict.schema.json`.

`PASS` requires sufficient evidence and no unresolved blocking or approval condition. `NEEDS_APPROVAL` identifies otherwise implementable R2/R3 or explicitly human-controlled work. `BLOCK` identifies missing or conflicting authority, unstable acceptance, insufficient evidence, or another stop condition.

## Authorization Boundary

Review is read-only. Do not mutate implementation, authority, configuration, state, or derived artifacts as part of the review. Tool capability and MCP availability are not permission. Never self-approve R2/R3 work or silently widen scope.

## Evidence and Traceability

Retain authority paths, findings, risk, permission, approval references, evidence sources, and unresolved unknowns in the structured verdict.

## Stop Conditions

Stop and return `BLOCK` when required authority or evidence is unavailable or contradictory. Return `NEEDS_APPROVAL` when explicit Human Authority is the remaining gate. Never convert uncertainty into `PASS`.
