---
name: specops-audit
description: Perform a read-only SpecOps conformance audit across authority routing, derived structures, permissions, contracts, drift, and readiness evidence.
---

# SpecOps Audit

Status: Derived read-only audit procedure. This Skill is not authority and cannot override current authority.

## Authority and Instance Routing

1. Read `.specops/specops.json` to locate current authority and derived operational structures. Treat all `.specops/*` content as derived instance configuration or evidence.
2. Read applicable current authority before judging conformance.
3. Read `.specops/permissions.json` and operate under `READ_ONLY`.
4. Use instance/deployment configuration for VCS and tool behavior; reusable audit semantics remain VCS-neutral and executor-neutral.

## Procedure

- Confirm explicit audit scope, baseline, and requested verdict.
- Inspect authority routing, duplicate or stale authority, role/product leakage, VCS leakage, Skill count and responsibilities, permissions, contracts, state/eval consistency, drift, broken references, and publication/readiness evidence where applicable.
- Verify derived artifacts identify their subordinate status and do not silently override authority.
- Separate observed evidence, inference, and unknowns.
- Report findings and traceability without mutating the repository or external systems.

## Authorization Boundary

Audit is read-only. Tool capability, MCP availability, credentials, and writable access are not authorization. Never self-approve R2/R3 work, repair findings, change authority, or widen scope during audit.

## Evidence and Traceability

Record baseline identity, authority paths, inspected artifacts, exact findings, evidence locations, confidence, unknowns, and checks not performed. Never infer publication or readiness from missing evidence.

## Stop Conditions

Stop and report the limitation when required authority, baseline identity, evidence, or safe read access is missing; when scope changes; or when a requested audit would require mutation. Never repair during audit.
