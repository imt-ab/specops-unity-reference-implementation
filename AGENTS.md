# Agent Operational Router

Status: Derived operational guidance. This file is not an independent authority.

## Authority Routes

Read the authority that governs the requested work before acting:

1. Framework semantics: [`Assets/Project/Docs/SpecOps/SPECOPS_V2.md`](Assets/Project/Docs/SpecOps/SPECOPS_V2.md)
2. Unity structure and dependency boundaries: [`Assets/Project/Docs/Architecture/ARCHITECTURE.md`](Assets/Project/Docs/Architecture/ARCHITECTURE.md)
3. Repository-wide engineering constraints: [`Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md`](Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md)
4. Feature intent: `Assets/Project/Docs/Specifications/<feature>/SPEC.md`, `CONSTRAINTS.md`, and `ACCEPTANCE.md`, when that feature authority exists

ADRs record decision history and rationale. They do not replace current architecture or global-constraint authority.

## Operational Rules

- Establish the applicable authority, requested scope, evidence, risk, approval, and permission before mutation.
- Inspect evidence before issuing a verdict. Separate observation from inference.
- Keep changes explicit, bounded, and minimal. Do not widen scope through incidental cleanup or refactoring.
- Stop when required authority, evidence, permission, or human approval is missing or contradictory.
- Treat tool capability, MCP availability, and executor access as capability only, never as authorization.
- Protect `Packages/*` and `ProjectSettings/*`; modify them only under separate explicit authorization.
- Preserve Unity `.meta` files and matching asset metadata. Do not mutate generated Unity directories.

## Repository Instance

This repository uses Git and GitHub. Read-only inspection is permitted when relevant. Commits, pushes, releases, destructive Git operations, history changes, branch changes, and other consequential VCS or publication actions require explicit authorization. Final consequential check-in, release, and publication remain human-controlled under repository policy.

Do not silently modify user-global IDE, agent, or tool configuration.

## Derived and Planned Structures

This router, `Assets/Project/Docs/SpecOps/WORKFLOW.md`, `DEPLOYMENT.md`, `ONBOARDING.md`, ADRs, plans, reviews, validation results, and context exports are subordinate to current authority.

Future `.specops/*` and Skill artifacts are planned derived/supporting structures. They are not installed by E1 and must not be assumed to exist or to carry independent authority.
