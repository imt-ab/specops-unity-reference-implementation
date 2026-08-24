# Architecture (Clean Architecture — Authoritative)

Status: Sole current structural authority for this repository.

This document defines responsibilities and allowed dependency directions for project layers. It complements the Project Structure README without duplicating it. Explanatory architecture documents, ADRs, workflow guidance, templates, and context exports are subordinate and cannot supersede this document. Accepted structural decisions must be synchronized here before they become current structural truth.

## Layers & Responsibilities
- Domain
  - Enterprise rules and core models.
  - Pure C#; no `UnityEngine`, no `MonoBehaviour`.
- Application
  - Use cases, orchestration, and ports (interfaces) to drive Domain.
  - Depends only on Domain and the cross-cutting Utility leaf; no `UnityEngine`.
- AI
  - Application of AI strategies and policies.
  - Depends on Application + Domain + Utility.
- Infrastructure
  - Adapters: persistence, files, networking, platform services.
  - Depends on Application + Domain + Utility.
- Presentation
  - Unity-facing layer: views, input translation, scene hooks.
  - Depends on Application + Utility; can reference `UnityEngine`.
- Composition
  - VContainer LifetimeScopes and registrations only; no gameplay logic.
  - Wires all concrete implementations to interfaces; may depend on Application, Domain, Infrastructure, Presentation, and Utility.
- Utility
  - Cross-cutting helpers and shared utilities (e.g., logging interfaces).

## Dependency Graph (textual)

The arrows and references below express allowed dependency directions. They do not require every allowed dependency to exist physically when an assembly has no implementation need for it.

- Domain: depends on nothing.
- Application: -> Domain, Utility
- AI: -> Application, Domain, Utility
- Infrastructure: -> Application, Domain, Utility
- Presentation: -> Application, Utility (and Unity APIs as needed)
- Composition: -> Application, Domain, Infrastructure, Presentation, Utility (wiring only)
- Utility: depends on no runtime layer; it is a standalone cross-cutting leaf that may be referenced by Application, AI, Infrastructure, Presentation, and Composition, but deliberately not by Domain.

No runtime-layer dependencies other than those listed above are allowed. Violations are not permitted.

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
