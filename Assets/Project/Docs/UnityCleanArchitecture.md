# Unity Clean Architecture

## Purpose

This repository uses Clean Architecture as the structural model for Unity code.

The goal is to keep core behavior testable, keep Unity APIs at the edges, and make dependency direction explicit instead of implicit in scene objects or ad hoc references.

This is a repository-specific adaptation of the pattern. It is practical structure for the current project, not a claim that every Unity project should be organized the same way.

## Architectural Intent

The architecture is built around a simple rule: dependencies point inward.

Core rules and use cases should not depend on Unity engine behavior. Engine-facing code should adapt Unity concepts to the core, not the other way around.

That separation matters in Unity because `MonoBehaviour`, scenes, input callbacks, and inspector wiring can otherwise become the center of the design.

## Layer Model

The repository uses these layers:

| Layer | Responsibility | Dependency Rule |
| --- | --- | --- |
| `Domain` | Core rules, entities, and invariants | Depends on nothing |
| `Application` | Use cases, orchestration, and ports | Depends on `Domain` only |
| `AI` | AI-related policies and coordination used by the runtime | Depends on `Application` and `Domain` |
| `Infrastructure` | Adapters for files, services, persistence, and external systems | Depends on `Application` and `Domain` |
| `Presentation` | Unity-facing UI, input, scene hooks, and interaction flow | Depends on `Application` and Unity APIs as needed |
| `Composition` | Dependency wiring and lifetime scope setup | Wires concrete implementations only |
| `Utility` | Shared technical helpers and cross-cutting abstractions | Kept standalone and reusable |

The concrete assemblies in this repository follow the `InfiniteMonkey.*` naming convention.

## Dependency Rules

- `Domain` and `Application` must remain free of Unity engine references.
- `Presentation` converts Unity events into application calls.
- `Infrastructure` contains adapters, not business rules.
- `Composition` wires objects together and should not hold gameplay logic.
- `Utility` should stay small and should not become a hidden application layer.

If a class needs engine access, it belongs near the edge. If a class needs to express the core rule, it belongs inward.

## Unity-Specific Adaptation

Unity projects often collapse structure when engine lifecycle and business logic share the same classes. This repository avoids that by using:

- separate assemblies for each layer
- `noEngineReferences` on core assemblies where applicable
- VContainer for composition and lifetime scope setup
- scene and UI code as adapters rather than the place where rules live

The result is not abstract purity. It is a project that can be reasoned about and tested without dragging Unity into every decision.

## Testing

Testing follows the layer structure:

- Domain and Application logic should be covered with fast EditMode tests where possible.
- PlayMode tests are reserved for engine behavior, scene wiring, and other runtime concerns.
- Dependencies at the edges should be mocked or stubbed so the core can be exercised in isolation.
- Composition should be verified where wiring is important, but it should remain thin.

Moq is used in this repository to help isolate use cases and adapters in tests.

## Composition

Composition is the last step in the dependency chain.

It is responsible for registering concrete implementations, connecting lifetime scopes, and exposing the object graph needed by runtime systems. It should not add new business rules or duplicate application logic.

## Why It Matters In Unity

Without an explicit architecture, Unity projects tend to drift toward scene-centric code, difficult test boundaries, and behavior that is hard to reuse outside a specific object graph.

Clean Architecture keeps those pressures under control. It gives the repository a stable place for rules, a narrow place for adapters, and a clear place for Unity integration.

## Relationship To SpecOps AI

SpecOps AI is the method that governs how work is introduced.
Unity Clean Architecture is the structural model that governs where the work belongs.

The two are linked, but they are not the same thing. The method controls the change process. The architecture controls the code shape.
