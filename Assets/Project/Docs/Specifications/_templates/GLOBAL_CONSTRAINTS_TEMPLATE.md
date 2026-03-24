# GLOBAL_CONSTRAINTS

Status: Draft / Active\
Last Updated: `<YYYY-MM-DD>`{=html}\
Owner: `<Team/Role>`{=html}

------------------------------------------------------------------------

## Purpose

This document defines **project-wide, cross-feature invariants** that
all specifications and implementations must follow.

**Rules:** - Feature-level `CONSTRAINTS.md` files may **add**
constraints but must not **override** global invariants. - If a feature
needs to change a global invariant, it must be captured as an ADR in
`ARCHITECTURE_DECISIONS.md` and then reflected here.

------------------------------------------------------------------------

## Architectural Invariants (Authoritative)

### Layering & Dependencies (Clean Architecture)

-   Domain depends on nothing.
-   Application depends only on Domain.
-   AI depends on Application + Domain.
-   Infrastructure depends on Application + Domain.
-   Presentation depends on Application (and Unity APIs as needed).
-   Composition wires dependencies only (VContainer registrations); no
    gameplay logic.
-   Utility is cross-cutting; avoid circular dependencies.

### Unity Engine Usage

-   Domain: **no** `UnityEngine` references; **no** `MonoBehaviour`.
-   Application: **no** `UnityEngine` references.
-   Presentation: Unity-facing code only; translates Unity events/input
    to Application calls.

### Assembly Definitions (asmdef) Rules

-   Domain and Application assemblies must enforce no-Unity via
    `"noEngineReferences": true`.
-   Do not introduce new cross-assembly references without explicit
    approval/ADR.

------------------------------------------------------------------------

## Tooling & Repository Safety (Authoritative)

### Version Control & Environment

-   Repository uses Plastic SCM (Unity Version Control), not Git.
-   Do not execute `git` commands; do not assume Git is installed.
-   Do not assume Unix tooling (`rg`, `grep`, `sed`, etc.); PowerShell
    only if explicitly required.

### Protected Areas

-   Do not modify `ProjectSettings/*` or `Packages/*` unless explicitly
    requested and approved.
-   Never delete or regenerate `.meta` files.
-   Never modify generated folders: `Library/`, `Temp/`, `Obj/`,
    `Logs/`, `Build/`, `Builds/`.

### Minimal Diff

-   Keep changes minimal and focused.
-   Do not reformat unrelated files.

------------------------------------------------------------------------

## Dependency Injection & Composition

-   Use VContainer for DI.
-   Composition layer contains **only** registrations/wiring.
-   No gameplay logic in Composition.

------------------------------------------------------------------------

## Logging

-   Use `IMonkeyLogger` exclusively for logging in runtime code.
-   Avoid `UnityEngine.Debug` in runtime code.

------------------------------------------------------------------------

## Testing Invariants

### General

-   Tests must be deterministic and repeatable.
-   Prefer EditMode unless runtime/frame behavior is required.
-   Do not use reflection in tests.

### Test Tooling

-   Use Moq for mocking.
-   Use VContainer for DI setup in tests.

### MonoBehaviour Rules

-   Do not instantiate MonoBehaviours via `new`.
-   Create MonoBehaviours with `GameObject.AddComponent<T>()`.
-   Destroy created GameObjects in `TearDown`.

### Test Placement

-   EditMode: `Assets/Project/Code/Tests/EditMode/<mirrored path>/`
-   PlayMode: `Assets/Project/Code/Tests/PlayMode/<mirrored path>/`
-   File naming: `<TargetClass>Tests.cs`

------------------------------------------------------------------------

## Performance Baselines

-   Avoid per-frame allocations in `Update` / `LateUpdate` /
    `FixedUpdate`.
-   Avoid LINQ/closures in hot paths.
-   Prefer `[SerializeField]` over runtime lookups.
-   Avoid `Find()` and scene-wide searches.

------------------------------------------------------------------------

## Change Control

Any change to the invariants in this document must be: 1) Captured in an
ADR in `ARCHITECTURE_DECISIONS.md` 2) Reflected here with an updated
date and summary of the change

------------------------------------------------------------------------

## Changelog

-   `<YYYY-MM-DD>`{=html}: `<Short summary of change>`{=html} (ADR-XXX)
