# Architecture Context Snapshot
_Auto-generated from repository rules. Do not edit manually._

**Snapshot Date:** 2026-02-14 12:45

## Project Basics
- **Unity Version:** Unity 6000.3 (Unity 6.3)
- **Language:** C# 9.0 (net471)
- **Version Control:** Plastic SCM (Unity Version Control)

## Layer Definitions & Responsibilities
- **Domain:** Enterprise rules and core models. Pure C#; no `UnityEngine`, no `MonoBehaviour`.
- **Application:** Use cases, orchestration, and ports (interfaces) to drive Domain. Depends only on Domain; no `UnityEngine`.
- **AI:** Application of AI strategies and policies. Depends on Application + Domain.
- **Infrastructure:** Adapters for persistence, files, networking, and platform services. Depends on Application + Domain.
- **Presentation:** Unity-facing layer: views, input translation, and scene hooks. Depends on Application; can reference `UnityEngine`.
- **Composition:** VContainer LifetimeScopes and registrations only; no gameplay logic. Wires all concrete implementations to interfaces.
- **Utility:** Cross-cutting helpers and shared utilities (e.g., logging interfaces). Standalone.

## Dependency Rules
### Dependency Graph
Domain ← Application ← AI ← Infrastructure / Presentation
Composition wires all layers.

### Constraints
- **Domain:** Depends on nothing. No `UnityEngine`.
- **Application:** Depends on Domain. No `UnityEngine`.
- **AI:** Depends on Application, Domain.
- **Infrastructure:** Depends on Application, Domain.
- **Presentation:** Depends on Application (and Unity APIs).
- **Composition:** Depends on all layers (for wiring only).
- **Utility:** Standalone.

## Assembly Definition (asmdef) Constraints
The following assemblies enforce the "No UnityEngine" rule by setting `"noEngineReferences": true`:
- `InfiniteMonkey.Domain`
- `InfiniteMonkey.Application`

All Runtime assemblies:
- `InfiniteMonkey.Domain`
- `InfiniteMonkey.Application`
- `InfiniteMonkey.AI`
- `InfiniteMonkey.Infrastructure`
- `InfiniteMonkey.Presentation`
- `InfiniteMonkey.Utility`
- `InfiniteMonkey.Composition`

## Folder Placement Rules
All new files must follow this structure under `Assets/Project/`:

- **Code (Runtime):** `Assets/Project/Code/Runtime/<Layer>/`
- **Code (Tests):** `Assets/Project/Code/Tests/EditMode/` or `PlayMode/`
- **Editor Scripts:** `Assets/Project/Editor/`
- **Content:**
    - Scenes: `Assets/Project/Content/Scenes/`
    - Prefabs: `Assets/Project/Content/Prefabs/`
    - UI: `Assets/Project/Content/UI/`
    - Input: `Assets/Project/Content/Input/`
    - Addressables: `Assets/Project/Content/Addressables/`
    - Settings: `Assets/Project/Content/Settings/` (Rendering, Lighting, Quality)
- **Art:** `Assets/Project/Art/`
- **Audio:** `Assets/Project/Audio/`
- **Docs:** `Assets/Project/Docs/`

## Testing Rules
- **Frameworks:** MOQ for mocking, VContainer for DI.
- **Constraints:**
    - No reflection allowed.
    - Use `internal` + `InternalsVisibleTo` for test access.
    - MonoBehaviours must be created via `GameObject.AddComponent<T>()`.
    - Always clean up in `TearDown` (destroy created GameObjects).
    - File Naming: `<TargetClass>Tests.cs`.
    - Location: Must follow the same folder hierarchy as the code they test.

## Logging Rule
- **Primary Rule:** Use `IMonkeyLogger` (found in `InfiniteMonkey.Utility.Interfaces`) exclusively.
- **Prohibited:** Do not use `UnityEngine.Debug` for logging in runtime code.

## Repository Safety Rules
- **Metas:** Never delete or regenerate `.meta` files. Always commit matching `.meta` files.
- **Protected Folders:** Never modify `Library/`, `Temp/`, `Obj/`, `Logs/`, `Build/`, `Builds/`.
- **Protected Settings:** Do NOT modify `ProjectSettings/*` or `Packages/*` unless explicitly requested.
- **Diffs:** Make the smallest possible diff; do not reformat unrelated content.

## Specification Governance
- **Location:** All features must live under `Assets/Project/Docs/Specifications/<feature>/`.
- **Required Files:**
    - `SPEC.md`: Goals, requirements, and edge cases.
    - `CONSTRAINTS.md`: Must/Must not and performance budgets.
    - `ACCEPTANCE.md`: Testable acceptance criteria.
- **Acceptance Criteria Standards:**
    - Format: Use **Given / When / Then** format.
    - Testability: Must be testable in Unity (EditMode or PlayMode).
    - Purity: Respect Domain/Application purity (no Unity in those layers).
    - Safety: Avoid reflection and unsafe MonoBehaviour instantiation.
    - Compatibility: Must be compatible with existing testing constraints.
- **Process:**
    - Implementation must reference acceptance criteria identifiers.
    - Specification ambiguity must block implementation.
