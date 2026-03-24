# Architecture (Clean Architecture — Authoritative)

This document defines responsibilities and dependencies for project layers. It complements the Project Structure README without duplicating it.

## Layers & Responsibilities
- Domain
  - Enterprise rules and core models.
  - Pure C#; no `UnityEngine`, no `MonoBehaviour`.
- Application
  - Use cases, orchestration, and ports (interfaces) to drive Domain.
  - Depends only on Domain; no `UnityEngine`.
- AI
  - Application of AI strategies and policies.
  - Depends on Application + Domain.
- Infrastructure
  - Adapters: persistence, files, networking, platform services.
  - Depends on Application + Domain.
- Presentation
  - Unity-facing layer: views, input translation, scene hooks.
  - Depends on Application; can reference `UnityEngine`.
- Composition
  - VContainer LifetimeScopes and registrations only; no gameplay logic.
  - Wires all concrete implementations to interfaces.
- Utility
  - Cross-cutting helpers and shared utilities (e.g., logging interfaces).

## Dependency Graph (textual)
- Domain: depends on nothing.
- Application: -> Domain
- AI: -> Application, Domain
- Infrastructure: -> Application, Domain
- Presentation: -> Application (and Unity APIs as needed)
- Composition: -> Application, Domain, Infrastructure, Presentation (wiring only)
- Utility: standalone; can be referenced by other layers for cross-cutting concerns.

No other dependencies are allowed. Violations are not permitted.

## Assemblies
Each Runtime layer has an `asmdef`:
- `InfiniteMonkey.Domain`
- `InfiniteMonkey.Application`
- `InfiniteMonkey.AI`
- `InfiniteMonkey.Infrastructure`
- `InfiniteMonkey.Presentation`
- `InfiniteMonkey.Utility`
- `InfiniteMonkey.Composition`

For `InfiniteMonkey.Domain` and `InfiniteMonkey.Application`, set `"noEngineReferences": true` to enforce the no-Unity rule.

## Notes
- Keep Unity-specific code out of Domain and Application.
- Presentation translates Unity input/events into Application calls.
- Composition binds interfaces to implementations via VContainer.
- Utility provides logging via `IMonkeyLogger`; avoid `UnityEngine.Debug`.
