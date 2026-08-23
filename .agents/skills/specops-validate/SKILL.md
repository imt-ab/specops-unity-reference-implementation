---
name: specops-validate
description: Collect deterministic authorized validation evidence and report PASS, FAIL, or INCONCLUSIVE without repairing findings.
---

# SpecOps Validate

Status: Derived validation procedure. This Skill is not authority and cannot override current authority.

## Authority and Instance Routing

1. Read `.specops/specops.json` for authority, validation contract, permission, and deployment paths. Treat the manifest as derived instance configuration.
2. Read applicable current authority, acceptance/check identifiers, and the approved validation scope.
3. Read `.specops/permissions.json` and verify `VALIDATE` plus any additional approval required by risk or side effects.
4. Use instance/deployment configuration for VCS and tool selection. Prefer deterministic evidence where suitable; reusable validation semantics remain VCS-neutral and executor-neutral.

## Procedure

- Confirm explicit validation scope, checks, side effects, evidence destinations, and prohibited repair work.
- Execute only authorized checks.
- Distinguish executed checks from checks not executed.
- Record actual commands or procedures where appropriate, exit codes where relevant, evidence, limitations, and unknowns.
- Use only `PASS`, `FAIL`, or `INCONCLUSIVE` as the overall result.
- Produce output conforming to `.specops/contracts/validation-result.schema.json`.

`PASS` requires executed evidence supporting every required check. Missing, partial, stale, or contradictory evidence is `INCONCLUSIVE` or `FAIL` as applicable.

## Authorization Boundary

Validation does not authorize implementation repair, package/settings mutation, or authority changes. Tool capability and MCP availability are not authorization. Never self-approve R2/R3 work or widen validation permission.

## Evidence and Traceability

Retain work-item and check identifiers, executed/not-executed state, actual evidence, exit codes, evidence locations, limitations, and unresolved unknowns.

## Stop Conditions

Stop when validation would exceed permission, mutate a protected area, install or restore an unauthorized dependency, require missing approval, or contaminate the evidence. Report the result without repairing it.
