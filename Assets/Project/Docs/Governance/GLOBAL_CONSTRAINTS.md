# Repository-Wide Engineering Constraints

Status: Current repository-wide engineering constraint authority for `specops-unity-reference-implementation`.

These constraints apply to work across this public Unity reference repository. They operate beneath the [SpecOps framework authority](../SpecOps/SPECOPS_V2.md) and alongside the distinct [structural authority](../Architecture/ARCHITECTURE.md). Feature authority may add narrower constraints but cannot silently override these constraints or structural authority.

This repository remains a public reference implementation and Golden Baseline candidate, not the generic SpecOps Core repository or a finished game. Its selected architecture is a repository choice, not a universal mandate for Unity projects.

## Scope and Evidence Discipline

- Work must remain within explicit scope and use the smallest coherent diff.
- Do not perform unrelated cleanup, formatting, refactoring, or dependency changes.
- Inspect evidence before asserting repository state, conformance, compilation, or test success.
- Separate observed facts, inference, and unresolved unknowns.
- Stop when authority, acceptance, permission, approval, or evidence is missing or contradictory.

## Unity Asset and Metadata Safety

- Preserve existing Unity `.meta` files and GUID identity. Never delete, move, or regenerate them casually.
- New tracked Unity assets and directories must include their matching metadata without invoking Unity merely to generate it.
- Keep generated directories such as `Library/`, `Temp/`, `Obj/`, `Logs/`, `Build/`, and `Builds/` outside authored changes.
- Do not infer that an intentional placeholder or directory marker is unnecessary from its filename or lack of product behavior.

## Protected Consequential Areas

- `Packages/*` and `ProjectSettings/*` require separate explicit authorization and proportionate validation.
- Unity version changes, package changes, assembly-topology changes, release operations, and repository-wide configuration changes are never incidental edits.
- User-global IDE, shell, agent, MCP, or tool configuration must not be silently modified.

## Project Placement and Namespaces

- Runtime C# belongs under `Assets/Project/Code/Runtime/<Layer>/`.
- EditMode and PlayMode tests belong under `Assets/Project/Code/Tests/EditMode/` or `PlayMode/`.
- Editor-only C# belongs under `Assets/Project/Editor/`.
- Production content follows the stable layout documented by `Assets/Project/README.md`.
- C# namespaces must follow the root namespace of the containing assembly. Additional nesting must reflect an intentional code boundary rather than incidental folder depth.

## Architecture Conformance

- `Assets/Project/Docs/Architecture/ARCHITECTURE.md` is the sole structural authority.
- Domain remains pure C#, depends on no project layer, and retains `noEngineReferences = true`.
- Application remains free of Unity engine references, retains `noEngineReferences = true`, and may depend only in the directions allowed by structural authority.
- Other assembly references and code dependencies must remain within the allowed directions. An allowed direction is not a requirement to create an otherwise unnecessary reference.
- Unity-facing behavior stays at the architecture edges. Composition remains wiring and registration, not gameplay logic.
- Do not introduce new cross-assembly references or architecture changes as incidental implementation details.

## Determinism and Runtime Safety

- Prefer deterministic behavior and deterministic validation where the requirement permits it.
- Avoid avoidable per-frame allocations, LINQ, and closures in hot Unity paths.
- Avoid scene-wide searches and implicit runtime discovery where explicit references or composition are appropriate.
- Respect Unity lifecycle and safe `MonoBehaviour` construction.

## Logging

- Runtime consumers use `InfiniteMonkey.Utility.Interfaces.IMonkeyLogger` rather than calling logging APIs directly.
- Do not introduce new direct `UnityEngine.Debug` call sites outside an explicitly authorized logging-adapter decision.
- This constraint does not claim that every retained v1 logger implementation is already reconciled with the v2 authority model.

## Testing and Validation

- Acceptance criteria and implementation claims require deterministic evidence appropriate to the behavior.
- Prefer EditMode tests for pure logic; use PlayMode tests when frames, scenes, lifecycle, or other runtime behavior is material.
- Tests targeting a specific runtime layer or production responsibility **SHOULD** mirror the corresponding production directory structure beneath the appropriate EditMode or PlayMode test root. Architecture, integration, acceptance, cross-cutting, and multi-layer tests **MAY** use dedicated descriptive test directories when no meaningful production-path mirror exists. Here, **SHOULD** is the repository-wide default and **MAY** is an explicit legitimate exception.
- Use NUnit through the Unity Test Framework. Use Moq and VContainer where isolation or container behavior requires them; their availability does not make them mandatory ceremony for every test.
- Do not use reflection to bypass intended architecture or visibility boundaries.
- Production API visibility **MUST NOT** be widened solely to make code accessible to tests. Prefer testing through the intended architectural contract. Where justified direct access to an internal production type or member is required, prefer internal visibility plus narrowly scoped `InternalsVisibleTo` for the relevant test assembly rather than changing the production API to public. This does not require direct testing of internal implementation.
- Create `MonoBehaviour` test subjects with `GameObject.AddComponent<T>()` and clean up created objects.
- Do not claim compilation, test coverage, or PASS based only on scaffolds, package presence, or documentation.

## Specifications and Global Impact

- Feature authority lives only in an instantiated `Assets/Project/Docs/Specifications/<feature>/` triplet of `SPEC.md`, `CONSTRAINTS.md`, and `ACCEPTANCE.md`.
- Templates are subordinate scaffolding and are not current feature authority.
- Feature work must preserve acceptance identifiers and traceability through implementation and validation.
- A consequential architecture or repository-wide constraint decision requires Human Authority, explicit rationale, and synchronization into the applicable current authority.
- ADRs retain decision history; they do not silently supersede current authority.
