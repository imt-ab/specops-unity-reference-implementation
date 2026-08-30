# Contributing

Thank you for helping improve `specops-unity-reference-implementation`. Contributions should strengthen its purpose as a public SpecOps AI v2 + Unity Clean Architecture reference and Golden Baseline without turning it into a generic framework or finished game.

The repository is the `v2.0.1` Container B working state on `specops-v2`. The qualified evidence subject remains A at `53595414f559d884d6d34ecafa7d350c1da96955`, with durable pre-Container evidence staged at `release-evidence/v2.0.1-staging` commit `68760e6f177c443214efac465de8bcfb708cec33`. Production Bootstrap, fresh-project validation, and the Container B lifecycle transition are complete; the `v2.0.1` tag, GitHub Release publication, and promotion to `main` remain future Human Authority-controlled actions and have not yet occurred.

## Start With Authority

Before proposing or implementing a change, read the authority that governs it:

1. [SpecOps framework authority](Assets/Project/Docs/SpecOps/SPECOPS_V2.md)
2. [Unity structural authority](Assets/Project/Docs/Architecture/ARCHITECTURE.md)
3. [Repository-wide engineering constraints](Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md)
4. The applicable feature's `SPEC.md`, `CONSTRAINTS.md`, and `ACCEPTANCE.md`, if feature authority exists

Use the [onboarding guide](Assets/Project/Docs/SpecOps/ONBOARDING.md) and [workflow](Assets/Project/Docs/SpecOps/WORKFLOW.md) for navigation. They are derived guidance and do not override authority.

SpecOps responsibilities are logical responsibilities, not product identities. No contribution workflow assigns specification, implementation, or validation ownership by product, model, IDE, or tool name. Repository deployment mappings may select tools for a bounded task without changing the framework.

## Issues and Change Proposals

Use the repository's GitHub issue forms for reproducible defects, documentation improvements, or bounded change requests.

A useful proposal identifies:

- the observed problem and intended outcome;
- goals, non-goals, and exact scope;
- affected authority, features, layers, files, or systems;
- stable acceptance criteria or another deterministic completion boundary;
- architecture, dependency, package, settings, compatibility, or external impact;
- known evidence, assumptions, and unresolved unknowns.

Discuss consequential changes before implementation. Framework-authority, architecture-authority, global-constraint, dependency, `Packages/*`, `ProjectSettings/*`, assembly-topology, compatibility-breaking, destructive, and publication changes are elevated boundaries requiring explicit Human Authority.

## Feature Specification Model

An approved feature is defined by this triplet under `Assets/Project/Docs/Specifications/<feature>/`:

- `SPEC.md`
- `CONSTRAINTS.md`
- `ACCEPTANCE.md`

Use the canonical templates documented in the [Specifications index](Assets/Project/Docs/Specifications/README.md). Templates are unapproved scaffolding. `SPECOPS_STATE.json` is derived state and cannot grant authority, approval, or permission.

Keep acceptance identifiers stable during an implementation slice. A material acceptance change invalidates the affected downstream plan and permission.

## Pull Requests

Keep each pull request to the smallest coherent, reviewable change. The pull request should state:

- the governing issue, specification, and acceptance identifiers;
- included and excluded scope;
- risk, required approval, and permission boundary;
- affected layers and authority paths;
- validation performed, actual evidence, and checks not performed;
- unresolved limitations or follow-up work.

Do not include unrelated cleanup, broad formatting, dependency changes, or adjacent migration work. Do not repair validation findings inside a validation-only task.

## Architecture and Repository Safety

- Preserve the seven-layer architecture and its allowed dependency directions.
- Keep Domain and Application engine-independent.
- Keep Composition limited to dependency wiring.
- Preserve Unity `.meta` files and existing GUIDs.
- Preserve intentional placeholders, directory markers, and repository-specific legal/publication files.
- Do not modify `Packages/*` or `ProjectSettings/*` without separate explicit approval.
- Do not silently mutate user-global IDE, agent, shell, MCP, or tool configuration.

JetBrains Rider is the repository's default Golden Baseline IDE target, not a SpecOps requirement. Contributions may use another suitable IDE or deterministic tool while following the same authority and evidence requirements.

## Validation and Evidence

Evidence must precede a PASS verdict. Report exactly what ran and what did not run.

- Use static inspection for documentation, paths, schemas, and dependency evidence where sufficient.
- Use compilation evidence for compile claims.
- Prefer EditMode tests for pure logic.
- Use PlayMode tests for Unity lifecycle, frames, scenes, or runtime behavior.
- Record manual steps when deterministic automation is not suitable.
- Do not claim compilation, test success, or coverage from package presence, scaffolding, or documentation.

## Git and Human Control

This repository uses Git and GitHub. That is repository-specific deployment policy, not a framework invariant.

Preserve unrelated work and do not rewrite history. Commits, pushes, merges, tags, releases, deployments, and external publication remain human-controlled consequential actions. A pull request or available tool does not grant permission for those actions.

## License and Attribution

Contributions are submitted under the repository's [Apache License 2.0](LICENSE). Preserve the attribution and publication information in [`NOTICE`](NOTICE).
