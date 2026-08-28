# Reference Architecture Example — Feature Specification

Status: APPROVED — CURRENT FEATURE AUTHORITY — IMPLEMENTATION COMPLETE

This specification is bounded by current framework, structural, and repository-wide authority. It does not authorize implementation, assembly-topology mutation, or validation.

## Identity

- Feature ID: `reference-architecture-example`
- Title: Reference Architecture Example
- Feature status: Approved
- Applicable feature path: `Assets/Project/Docs/Specifications/reference-architecture-example/`

## Purpose / Problem

The repository contains the selected Unity Clean Architecture assembly topology but does not yet provide a small executable feature that shows how responsibilities and dependencies flow through its layers. This feature provides one intentionally trivial, deterministic `ReferenceMessage` example so a developer can understand the architecture from production code and EditMode evidence rather than from folder names or documentation alone. It is reference behavior, not game functionality.

## Users and Use Cases

- Affected user, actor, or system: A developer evaluating or bootstrapping from the public Unity reference implementation.
- Intended use case: Follow one deterministic request from a Unity-facing Presentation adapter through an Application use case and a pure Domain value, with source text supplied through an Application-owned port implemented by Infrastructure and wired by Composition through VContainer.

## Goals

- Demonstrate a pure immutable Domain value and validation rule.
- Demonstrate an Application-owned port and use case without exposing Domain to Presentation.
- Demonstrate dependency inversion through a deterministic Infrastructure adapter.
- Demonstrate a thin Unity-facing Presentation adapter with no business rule or container dependency.
- Demonstrate VContainer wiring isolated to Composition.
- Provide deterministic EditMode evidence for behavior, composition, engine independence, and runtime assembly directions.

## Non-goals

- Game behavior, gameplay terminology, production UI, input, navigation, or scene bootstrap.
- AI behavior or any change to the AI layer.
- Utility modernization, relocation, or use by the representative flow.
- Scene mutation, scene attachment, or PlayMode coverage without a demonstrated lifecycle need.
- Package, ProjectSettings, CI, E8, E9, authority, or Dummy placeholder changes.

## Functional Requirements

- `FR-001` — Domain shall define a concept named `ReferenceMessage` that is constructed from text, exposes accepted text as an immutable value, and deterministically rejects null, empty, and whitespace-only text.
- `FR-002` — `ReferenceMessage` shall be pure C# and contain no Unity, clock, random, persistence, networking, logging, or dependency-injection concern.
- `FR-003` — Application shall own a port named `IReferenceTextSource` whose sole responsibility is to provide source text without exposing Unity or Infrastructure types.
- `FR-004` — Application shall define a use case named `CreateReferenceMessage` that obtains text through `IReferenceTextSource`, delegates validation and value construction to Domain, and returns the accepted string as the Presentation-safe result.
- `FR-005` — Infrastructure shall define `FixedReferenceTextSource`, implementing `IReferenceTextSource` and returning one fixed deterministic value without Unity, external services, file-system access, clock access, environment state, or AI.
- `FR-006` — Presentation shall define a thin Unity-facing `MonoBehaviour` named `ReferenceMessagePresenter` that invokes `CreateReferenceMessage` through an explicit method and may retain only the last produced presentation value when needed for deterministic observation.
- `FR-007` — `ReferenceMessagePresenter` shall contain no Domain rule, Infrastructure knowledge, service locator, scene search, or `Update`, `LateUpdate`, or `FixedUpdate` requirement.
- `FR-008` — Composition shall own all VContainer-specific behavior and provide a minimal composition root, conceptually `ReferenceLifetimeScope` with optional bounded registration support such as `ReferenceRegistrations`.
- `FR-009` — Composition shall register `IReferenceTextSource` to `FixedReferenceTextSource`, register `CreateReferenceMessage`, and wire or initialize `ReferenceMessagePresenter` without requiring Presentation to reference VContainer.
- `FR-010` — The complete deterministic representative flow shall be executable and observable in EditMode without a tracked scene or PlayMode requirement.

## Non-functional Requirements

- `NFR-001` — Given the same fixed source text, the complete flow shall return the same accepted presentation string on every execution.
- `NFR-002` — Domain and Application shall retain `noEngineReferences = true` and compile without Unity engine or editor assembly dependencies.
- `NFR-003` — Feature validation shall be deterministic, automated in EditMode, and shall not widen production API visibility solely for tests.
- `NFR-004` — The feature shall introduce only project-layer references required by the approved flow and permitted by `ARCHITECTURE.md`.

## Inputs, Outputs, and Behavior

- Inputs: The fixed string supplied by `FixedReferenceTextSource`; direct Domain tests also exercise null, empty, whitespace-only, and valid strings.
- Outputs: The accepted immutable Domain text internally and the same accepted string exposed by the Application API to Presentation.
- State transitions or externally observable behavior: Calling the presenter's explicit method invokes the composed use case once and produces the deterministic accepted string. The presenter may retain that value solely as observable adapter state. No frame-driven state transition is required.

## Edge Cases and Failure Behavior

- Null source text — Domain construction rejects it deterministically.
- Empty source text — Domain construction rejects it deterministically.
- Whitespace-only source text — Domain construction rejects it deterministically.
- Valid non-empty text — Domain accepts it unchanged and exposes it immutably.
- A later implementation finding that requires Unity lifecycle, a scene, or PlayMode — implementation stops and returns to Human Authority review; scope is not expanded silently.
- A later implementation finding that appears to require Presentation to reference Domain, Infrastructure, or VContainer — implementation stops because that would violate this feature boundary.

## Dependencies and External Assumptions

- Existing Unity, Unity Test Framework, VContainer, NUnit, and Moq baselines are assumed available; this feature authorizes no dependency change.
- Exact VContainer mechanics must be selected from supported, verified APIs during a separately reviewed implementation plan. This specification requires observable wiring behavior and does not prescribe an undocumented API.
- The existing Moq smoke test remains part of the required combined EditMode result but is not architectural coverage.

## Architecture Impact

Reference the [structural authority](../../Architecture/ARCHITECTURE.md).

- Affected layers or contracts: Domain (`ReferenceMessage`); Application (`IReferenceTextSource`, `CreateReferenceMessage`); Infrastructure (`FixedReferenceTextSource`); Presentation (`ReferenceMessagePresenter`); Composition (VContainer composition root and registrations).
- Required dependency intent for later separately approved R3 implementation: Application -> Domain; Infrastructure -> Application; Presentation -> Application; Composition -> Application, Infrastructure, Presentation.
- Explicitly excluded directions: Domain -> anything; Presentation -> Domain, Infrastructure, or VContainer; Application -> Infrastructure or Presentation; Composition -> AI.
- AI: Not exercised. AI is optional for this flow; forcing it into the example would create artificial functionality. Allowed directions are ceilings, not requirements, and Composition -> AI is not currently an explicit allowed direction.
- Utility: Not used or changed.
- ADR required or referenced: None. `ARCHITECTURE.md` remains structural authority; this feature does not redefine it.

## Global-Constraint Impact

Reference the [repository-wide constraints](../../Governance/GLOBAL_CONSTRAINTS.md).

- Impact: The completed implementation added bounded runtime code, tests, Unity metadata, and approved project assembly references. Assembly-topology mutations remain R3 and require separate explicit Human Authority approval and `ELEVATED_CHANGE` permission. No package, settings, scene, Utility, authority, or publication change is included.

## Validation Considerations

- Pure Domain and Application behavior should use focused EditMode tests.
- Infrastructure conformance should be validated through the Application-owned port and deterministic result.
- Presentation should be created using `GameObject.AddComponent<T>()`, invoked explicitly, and cleaned up in EditMode.
- Composition validation should prove that the configured VContainer graph can initialize the presenter and execute the complete flow without a tracked scene.
- Architecture validation should inspect explicit asmdef invariants and compiled assembly references rather than use brittle semantic source-token rules or reflection to bypass boundaries.

## Manual or External Steps

- Human Authority review and approval of this feature triplet are complete; implementation planning has not started and remains a separate slice.
- Later assembly-topology mutation requires separate explicit R3 approval. No manual Unity, scene, or external-service step is required by feature acceptance.

## Open Questions

- None blocking specification review. Exact supported VContainer registration/injection mechanics are a feasibility detail for the later reviewed plan; discovery of a lifecycle or scene requirement is a stop condition.

Unresolved authority conflicts or material ambiguity stop implementation.

## Traceability References

- Framework authority: [`SPECOPS_V2.md`](../../SpecOps/SPECOPS_V2.md)
- Structural authority: [`ARCHITECTURE.md`](../../Architecture/ARCHITECTURE.md)
- Repository-wide constraints: [`GLOBAL_CONSTRAINTS.md`](../../Governance/GLOBAL_CONSTRAINTS.md)
- Acceptance criteria: `Assets/Project/Docs/Specifications/reference-architecture-example/ACCEPTANCE.md`
- Related features or ADRs: None
