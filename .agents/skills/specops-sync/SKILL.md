---
name: specops-sync
description: Assess completed work for global or authority impact and produce a structured synchronization result without mutating authority.
---

# SpecOps Sync

Status: Derived synchronization-assessment procedure. This Skill is not authority and cannot override current authority.

## Authority and Instance Routing

1. Read `.specops/specops.json` for current authority, ADR, contract, permission, feature, and deployment paths. The manifest is derived instance configuration.
2. Read applicable current authority, completed implementation evidence, and validation result.
3. Read `.specops/permissions.json` and operate read-only unless a separate later task authorizes a bounded derived result artifact.
4. Use instance/deployment configuration when VCS or tools matter; reusable sync semantics remain VCS-neutral and executor-neutral.

## Procedure

- Confirm explicit completed-work and synchronization-review scope.
- Assess whether observed implementation truth affects feature authority, structural authority, repository-wide constraints, or decision rationale.
- Use exactly one result: `NO_GLOBAL_IMPACT`, `GLOBAL_UPDATE_REQUIRED`, `ADR_REQUIRED`, or `BLOCK`.
- Identify affected authority paths, ADR references, evidence, unknowns, risk, and Human Authority requirements.
- Produce output conforming to `.specops/contracts/sync-result.schema.json`.

A synchronization result does not authorize authority mutation. An accepted ADR is decision approval, not automatic authority synchronization. Any current-authority mutation is R3 and requires explicit Human Authority.

## Authorization Boundary

Tool capability and MCP availability are not authorization. Never self-approve R2/R3 work, mutate authority during assessment, or widen permission to apply a recommended update.

## Evidence and Traceability

Retain work-item identifiers, implementation and validation references, findings, affected authority paths, ADR references, approval requirements, and evidence.

## Stop Conditions

Return `BLOCK` when implementation or validation evidence is insufficient, authority impact cannot be bounded, authority conflicts, or required Human Authority cannot be established. Stop before applying any authority or global update.
