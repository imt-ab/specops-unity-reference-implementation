# SpecOps Unity Reference Implementation

`specops-unity-reference-implementation` is a public reference repository demonstrating one concrete combination of SpecOps AI v2 and a selected Unity Clean Architecture.

It is being developed as a Golden Baseline candidate for bootstrapping new Unity game projects: a reviewable starting point with explicit authority, bounded workflows, stable assembly boundaries, and evidence-driven validation.

## Current Status

This repository is on the `specops-v2` migration branch and is migrating toward the first verified SpecOps v2 Golden Baseline.

- `v1.0.0` is the immutable final pre-SpecOps-v2 public baseline.
- `v2.0.0` is the intended first SpecOps v2 + Unity Clean Architecture Golden Baseline release.
- `v2.0.0` has **not** been released.
- The current repository still contains intentionally retained legacy governance and tooling artifacts pending later migration slices.
- Some runtime and test areas remain scaffolded. Documentation or package presence is not evidence that compilation, tests, bootstrap, or final release validation has passed.

See the [changelog](CHANGELOG.md) for public migration history.

## What This Repository Is

- A public reference implementation of SpecOps AI v2 applied to a Unity repository.
- A concrete example of a selected layered Unity Clean Architecture.
- A Golden Baseline candidate for teams that want to evaluate or bootstrap a disciplined Unity project structure.
- A place to examine how specifications, authority, permissions, implementation boundaries, and validation evidence fit together.

## What This Repository Is Not

- The generic SpecOps Core repository.
- Project Reclaimer.
- A finished game.
- A claim that this architecture is mandatory for every Unity project.
- A released or finally validated `v2.0.0` baseline.

## Current Authority

The repository has four current-authority domains:

| Domain | Current authority |
| --- | --- |
| SpecOps framework semantics | [`Assets/Project/Docs/SpecOps/SPECOPS_V2.md`](Assets/Project/Docs/SpecOps/SPECOPS_V2.md) |
| Unity structure and dependency boundaries | [`Assets/Project/Docs/Architecture/ARCHITECTURE.md`](Assets/Project/Docs/Architecture/ARCHITECTURE.md) |
| Repository-wide engineering constraints | [`Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md`](Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md) |
| Approved feature intent | `Assets/Project/Docs/Specifications/<feature>/SPEC.md`, `CONSTRAINTS.md`, and `ACCEPTANCE.md` |

Start with these documents before relying on workflow guides, templates, Skills, `.specops/*`, ADRs, plans, or validation records. Those artifacts are derived or subordinate and cannot silently override current authority.

For an operational entry path, read the [public onboarding guide](Assets/Project/Docs/SpecOps/ONBOARDING.md) and [derived workflow](Assets/Project/Docs/SpecOps/WORKFLOW.md).

## Selected Unity Clean Architecture

The reference architecture has seven runtime layers:

- **Domain** — enterprise rules and core models; pure C# with no Unity engine references.
- **Application** — use cases, orchestration, and ports; depends on Domain and has no Unity engine references.
- **AI** — AI strategies and policies built on Application and Domain.
- **Infrastructure** — persistence, networking, files, platform services, and other adapters.
- **Presentation** — Unity-facing views, input translation, and scene hooks.
- **Composition** — VContainer lifetime scopes and registrations; wiring rather than gameplay logic.
- **Utility** — shared cross-cutting helpers and logging abstractions.

Domain and Application assemblies retain `noEngineReferences = true`. The architecture document defines **allowed dependency directions**; it does not require every allowed dependency to exist physically.

The repository uses `InfiniteMonkey.*` assembly names. VContainer is present for composition and Moq is present for test isolation where appropriate. Neither dependency is mandatory ceremony for every implementation or test.

## Current Migration Baseline

The values below are the observed repository state during migration, not a promise of the final `v2.0.0` baseline:

- Unity editor: `6000.3.7f1`, from `ProjectSettings/ProjectVersion.txt`.
- Unity package declarations: current values in `Packages/manifest.json`.
- Default IDE target: JetBrains Rider.
- Repository VCS and hosting: Git and GitHub.

The final Unity and package baseline remains subject to the separately authorized E6 migration slice. E4 does not upgrade Unity, change packages, or prove package restoration.

Rider is the verified/default Golden Baseline IDE direction for this repository deployment. It is not a SpecOps framework requirement, and user-global Rider or tool settings must never be silently changed. Codex, Junie, and deterministic tools may be deployment executors; they do not define SpecOps logical roles. See [deployment guidance](Assets/Project/Docs/SpecOps/DEPLOYMENT.md).

## Repository Layout

- `Assets/Project/Code/Runtime` — seven layered runtime assemblies.
- `Assets/Project/Code/Tests` — EditMode and PlayMode test assemblies.
- `Assets/Project/Editor` — editor-only tooling.
- `Assets/Project/Docs` — framework, architecture, governance, workflow, and feature documentation.
- `Assets/Project/Docs/Specifications` — feature authority instances and canonical templates.
- `Assets/ScriptTemplates` — retained Unity script templates.

See [`Assets/Project/README.md`](Assets/Project/README.md) for the detailed Unity asset and code layout.

## Getting Started

1. Read the [onboarding guide](Assets/Project/Docs/SpecOps/ONBOARDING.md).
2. Read the applicable current authority listed above.
3. Confirm the editor version in `ProjectSettings/ProjectVersion.txt` and review current package declarations in `Packages/manifest.json`.
4. Inspect the project structure and `InfiniteMonkey.*` assembly definitions under `Assets/Project/Code`.
5. Open Unity or allow package resolution only when appropriate for your task and environment; report those actions and their results as evidence.
6. Run only the validation relevant to the change. Distinguish static inspection, compilation, EditMode tests, PlayMode tests, and manual Unity checks.

## Feature Specifications

Feature authority is an approved triplet under `Assets/Project/Docs/Specifications/<feature>/`:

- `SPEC.md` — intent, goals, non-goals, and requirements.
- `CONSTRAINTS.md` — feature-specific constraints.
- `ACCEPTANCE.md` — stable, testable acceptance criteria.

`SPECOPS_STATE.json` is derived traceability state and never authority. Templates are unapproved scaffolding; copying them does not approve a feature.

Read the [Specifications index](Assets/Project/Docs/Specifications/README.md) before creating or changing a feature specification.

## Validation Philosophy

Evidence comes before a verdict. A validation report must identify what was executed, what was not executed, the actual results, limitations, and unresolved unknowns.

- Prefer deterministic checks when they directly establish the required evidence.
- Use EditMode tests for pure logic and PlayMode tests when Unity lifecycle, frames, scenes, or runtime behavior is material.
- Do not infer compilation or test success from scaffolding, documentation, package declarations, or an earlier run.
- Never report PASS for a check that did not run.

## Git and GitHub

Git and GitHub are repository-instance choices, not universal SpecOps requirements. Keep changes bounded, inspect the complete diff, preserve unrelated work, and follow the repository's issue and pull-request guidance.

Commits, pushes, merges, tags, releases, history mutation, and external publication remain human-controlled consequential operations. Completing one migration slice does not authorize the next slice or publication.

## Contributing

Public contributions are welcome when they preserve the repository's reference purpose and authority boundaries. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening an issue or pull request.

In particular, discuss architecture, dependency, `Packages/*`, `ProjectSettings/*`, assembly-topology, compatibility, or broad migration changes before implementation. Prefer small, evidence-backed changes over unrelated cleanup or broad rewrites.

## License and Attribution

This repository is published under the [Apache License 2.0](LICENSE).

Copyright 2026 Infinite Monkey Theorem AB. Preserve the repository attribution and publication notices in [`NOTICE`](NOTICE) when redistributing the work.
