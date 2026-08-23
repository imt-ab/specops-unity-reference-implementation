---
name: specops-spec
description: Establish or refine bounded SpecOps feature intent, constraints, and stable acceptance criteria before implementation.
---

# SpecOps Specification

Status: Derived procedure. This Skill is not authority and cannot override current authority.

## Authority and Instance Routing

1. Read `.specops/specops.json` to locate repository authority and deployment configuration. Treat the manifest as derived instance configuration, never as authority.
2. Read the framework authority, structural authority, repository-wide constraints, and any existing feature authority identified by the manifest.
3. Read `.specops/permissions.json` before any authorized documentation mutation.
4. When VCS or tool behavior matters, use the repository instance and deployment configuration. The reusable procedure remains VCS-neutral and executor-neutral; do not impose a universal VCS command or product requirement.

## Procedure

- Confirm explicit work-item scope and the intended feature directory.
- Establish goals, non-goals, functional and non-functional requirements, constraints, edge cases, and unresolved unknowns.
- Define stable, identifiable acceptance criteria with deterministic validation expectations.
- Identify conflicts with framework, architecture, repository constraints, or existing feature authority.
- Identify likely risk, approval needs, protected boundaries, and manual or external dependencies without granting permission.
- Keep specification changes minimal and traceable to the stated intent.
- Stop before implementation. This Skill does not plan implementation details beyond what is needed to make intent testable and bounded.

## Authorization Boundary

Tool capability, executor access, and available MCP integrations are not authorization. Never self-approve R2 or R3 work, widen a permission, or treat a writable file as permission to change it. Logical responsibility is executor-neutral and must not be assigned by product identity.

## Evidence and Traceability

Record consulted authority paths, the work-item identifier, acceptance identifiers, conflicts, assumptions, evidence, unknowns, risk indicators, approval requirements, and the exact specification files affected.

## Stop Conditions

Stop without implementation when scope is missing, authority conflicts, acceptance is unstable or untestable, required evidence is unavailable, a protected/elevated boundary is implicated without approval, permission is insufficient, or a derived artifact conflicts with authority.
