---
name: specops-implement
description: Execute only an approved bounded SpecOps implementation plan under verified permission and approval.
---

# SpecOps Implement

Status: Derived implementation procedure. This Skill is not authority and cannot override current authority.

## Authority and Instance Routing

1. Read `.specops/specops.json` for current repository-relative authority, contract, permission, and deployment paths. The manifest is derived instance configuration.
2. Read applicable current authority, feature authority, review verdict, and approved implementation plan.
3. Read `.specops/permissions.json` and verify the named permission profile, scope, risk, and Human Authority approvals before mutation.
4. Obtain VCS and tool behavior from instance/deployment configuration. Reusable implementation semantics remain VCS-neutral and executor-neutral.

## Procedure

- Confirm that the plan conforms to `.specops/contracts/implementation-plan.schema.json`.
- Verify exact allowed paths, excluded scope, validation expectations, stop conditions, permission, risk, and approval references.
- Execute only the approved bounded plan with the smallest coherent diff.
- Preserve unrelated work, repository metadata, protected areas, and traceability.
- Stop immediately if implementation requires scope expansion, permission elevation, an unapproved R2/R3 action, or a protected/elevated boundary not already authorized.
- Report actual changes and unresolved implementation findings without converting a failed or incomplete result into `PASS`.

Implementation does not acquire authority merely because it discovers global or architectural impact. Record the impact and route it to review or synchronization; do not mutate current authority without separately approved R3 work.

## Authorization Boundary

Tool capability, credentials, MCP availability, writable files, and the existence of `ELEVATED_CHANGE` are not approval. Never self-approve R2/R3 work or silently widen permission.

## Evidence and Traceability

Retain plan identifier, acceptance identifiers, authority and approval references, permission profile, files actually changed, deviations, stop conditions encountered, and validation still required.

## Stop Conditions

Stop on missing or stale approval, permission mismatch, changed acceptance, unexpected files, protected-area impact, failed preconditions, authority conflict, or any need to exceed the approved plan.
