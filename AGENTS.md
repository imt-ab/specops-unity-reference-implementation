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

## Derived Operational Structures

This router, `Assets/Project/Docs/SpecOps/WORKFLOW.md`, `DEPLOYMENT.md`, `ONBOARDING.md`, ADRs, plans, reviews, validation results, and context exports are subordinate to current authority.

The installed [`.specops/specops.json`](.specops/specops.json) manifest routes to instance paths and deployment defaults. [`.specops/permissions.json`](.specops/permissions.json), [`.specops/contracts/`](.specops/contracts/), and all `.specops/*` content are derived/supporting and never carry independent authority.

Exactly seven derived logical Skills are installed under `.agents/skills/`:

- `specops-spec`
- `specops-review`
- `specops-plan`
- `specops-implement`
- `specops-validate`
- `specops-sync`
- `specops-audit`

Use the Skills as executor-neutral procedures after authority routing. Eval definitions and feature-state instances remain uninstalled; do not assume that planned paths contain artifacts.
