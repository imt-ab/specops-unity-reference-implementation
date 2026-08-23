# Legacy AI Rules Compatibility Router

Status: **NOT current authority.** This file is retained only as a legacy compatibility path during the SpecOps v2 migration.

[`AGENTS.md`](AGENTS.md) is a derived operational router. Current authority consists of the following four authority domains:

1. [SpecOps v2 framework authority](Assets/Project/Docs/SpecOps/SPECOPS_V2.md)
2. [Unity structural authority](Assets/Project/Docs/Architecture/ARCHITECTURE.md)
3. [Repository-wide engineering constraints](Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md)
4. Approved feature authority under [`Assets/Project/Docs/Specifications/`](Assets/Project/Docs/Specifications/README.md): `SPEC.md`, `CONSTRAINTS.md`, and `ACCEPTANCE.md`

This compatibility router contains no independent normative rules. If any historical reference, retained tooling artifact, or prior version of this file conflicts with current authority, current authority wins.

## E5 Migration Traceability

- Mandatory XML documentation on every test was intentionally dropped. Meaningful XML documentation and comments remain allowed when they explain non-obvious intent, rationale, constraints, regressions, or setup.
- `<TargetClass>Tests.cs` naming for tests with one clear target type is deferred to E9 as a default tooling/style convention. It is not current repository-wide authority and is not mandatory for integration, architecture, acceptance, cross-cutting, multi-type, or similar tests.
- Test directory placement is governed by the `Testing and Validation` section of [`GLOBAL_CONSTRAINTS.md`](Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md).
- Production API visibility for testing is governed by the `Testing and Validation` section of [`GLOBAL_CONSTRAINTS.md`](Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md).
- PascalCase for applicable C# identifiers is deferred to E9 coding-style and tooling reconciliation. It is not established here as governance authority.

Concrete legacy PowerShell, encoding, command-safety, and Rider migration information remains temporarily available in [`TOOLING_RULES.md`](TOOLING_RULES.md), which is an E9 tooling migration source and not governance authority.
