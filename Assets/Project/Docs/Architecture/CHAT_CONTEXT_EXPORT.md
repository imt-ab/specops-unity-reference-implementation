# Architecture Context (Chat Export)

## Project Summary
- **Environment:** Unity 6000.3, C#, Plastic SCM.
- **DI/Testing:** VContainer, MOQ.
- **Logging:** `IMonkeyLogger` (Utility) only. No `UnityEngine.Debug`.

## Layer Order & Dependencies
Order: Domain → Application → AI → Infrastructure / Presentation
- **Unity-Free Layers:** Domain, Application (`"noEngineReferences": true`).
- **Domain:** No dependencies, no `UnityEngine`, no MonoBehaviours.
- **Application:** Depends on Domain only. No `UnityEngine`.
- **AI/Infrastructure:** Depend on Application + Domain.
- **Presentation:** Depends on Application; handles Unity APIs/input.
- **Composition:** VContainer registration only.

## Folder Structure
- **Runtime:** `Assets/Project/Code/Runtime/<Layer>/`
- **Tests:** `Assets/Project/Code/Tests/(EditMode|PlayMode)/`
- **Docs:** `Assets/Project/Docs/`
- **Specifications:** `Assets/Project/Docs/Specifications/<feature>/`

## Critical Constraints
- **Safety:** No `.meta` deletion/regeneration. No `ProjectSettings` or `Packages` edits.
- **Diffs:** Minimal changes only. No unrelated reformatting.
- **Testing:** No reflection. Use `AddComponent<T>()` for MonoBehaviours. Cleanup in `TearDown`.
- **Namespaces:** Match folder structure (e.g., `InfiniteMonkey.Domain`).

## Specification Governance (Condensed)
- Features live in `Assets/Project/Docs/Specifications/<feature>/`.
- Required: `SPEC.md`, `CONSTRAINTS.md`, `ACCEPTANCE.md`.
- Acceptance: **Given/When/Then** format, testable in Unity, no Unity in Domain/Application layers, no reflection.
- Reference AC identifiers in implementation. Ambiguity blocks progress.
