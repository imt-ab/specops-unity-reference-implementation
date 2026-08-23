---
name: specops-plan
description: Convert approved SpecOps intent and review evidence into a bounded implementation slice without granting implementation permission.
---

# SpecOps Plan

Status: Derived planning procedure. This Skill is not authority and cannot override current authority.

## Authority and Instance Routing

1. Read `.specops/specops.json` for authority, feature, contract, permission, and deployment paths. Treat it as derived instance configuration.
2. Read applicable current authority, approved feature intent, and the structured review verdict.
3. Read `.specops/permissions.json` to identify—not grant—the required profile.
4. Obtain VCS or tool behavior from instance/deployment configuration; the reusable plan remains VCS-neutral and executor-neutral.

## Procedure

- Confirm explicit work-item and planning scope.
- Require approved or otherwise unblocked intent and review evidence.
- Map acceptance identifiers to exact repository-relative planned paths or areas.
- Describe architecture/layer impact only where applicable.
- Identify risk, required permission profile, Human Authority approvals, validation, excluded scope, and stop conditions.
- Keep the slice minimal, coherent, and reviewable.
- Produce output conforming to `.specops/contracts/implementation-plan.schema.json`.

Planning does not authorize implementation. A plan records required permission and approval; it does not issue either.

## Authorization Boundary

Tool capability and MCP availability are not authorization. Never self-approve R2/R3 work, select `ELEVATED_CHANGE` as if it were approval, or widen the planned scope to absorb incidental work.

## Evidence and Traceability

Trace every planned path to intent or acceptance, and retain review, risk, approval, permission, validation, exclusion, and stop-condition references.

## Stop Conditions

Stop when intent or acceptance is unstable, review is blocked, approval is missing, planned work crosses an unapproved elevated boundary, exact scope cannot be identified, or derived inputs conflict with authority.
