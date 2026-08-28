# Reference Architecture Example — Feature Constraints

Status: APPROVED — CURRENT FEATURE AUTHORITY — IMPLEMENTATION COMPLETE

These feature-specific constraints cannot override:

- [SpecOps framework authority](../../SpecOps/SPECOPS_V2.md)
- [Structural authority](../../Architecture/ARCHITECTURE.md)
- [Repository-wide engineering constraints](../../Governance/GLOBAL_CONSTRAINTS.md)

A conflict stops work for clarification by Human Authority. A proposed change to current authority is separate R3 work.

## Architecture

- Must: Keep `ReferenceMessage` pure and immutable; keep `IReferenceTextSource` and `CreateReferenceMessage` in Application; implement the port in Infrastructure; keep `ReferenceMessagePresenter` thin and Unity-facing; isolate VContainer-specific wiring in Composition.
- Must: Keep Domain and Application `noEngineReferences = true`.
- Must: Use only this later dependency intent, subject to separate R3 approval: Application -> Domain; Infrastructure -> Application; Presentation -> Application; Composition -> Application, Infrastructure, Presentation.
- Must not: Introduce Domain -> any project layer; Presentation -> Domain, Infrastructure, or VContainer; Application -> Infrastructure or Presentation; Composition -> AI; or any other unapproved project-layer direction.
- Must not: Put Domain rules, game behavior, scene discovery, service location, or frame-loop behavior in Presentation or Composition.
- Must not: Redefine or supersede `ARCHITECTURE.md`; allowed directions remain ceilings rather than requirements.

## Dependencies

- No package mutation, package addition, package removal, package upgrade, or new package dependency.
- No external service, network, file-system, environment-state, clock, random, or external AI dependency.
- Presentation must not reference VContainer or use VContainer injection attributes.
- The representative flow must not require Utility.

Documenting later asmdef intent does not authorize assembly-topology mutation.

## Performance

- Frame-time or latency budget: No frame-driven behavior is permitted or required; the explicit invocation must complete synchronously for the fixed in-memory source.
- Throughput budget: Not applicable; this is one reference invocation, not a production throughput feature.

## Memory and Allocation

- Memory budget: No persistent data beyond required objects and, if necessary for test observation, the presenter's last produced string.
- Allocation or GC budget: No per-frame path exists. Avoid abstractions or collections not needed by the single deterministic flow.

## Unity and Runtime

- Target runtime/platform conditions: Existing repository Unity baseline only; no ProjectSettings mutation.
- Lifecycle, scene, serialization, or engine constraints: No scene mutation or attachment; no `Update`, `LateUpdate`, or `FixedUpdate`; no PlayMode requirement merely to create a non-zero test count.
- Required behavior must be testable in EditMode. If implementation discovers a genuine Unity lifecycle dependency, it must stop for Human Authority review before adding scene or PlayMode scope.

## Persistence and Data

- No persistence, data migration, serialization contract, save data, file access, or retained user data.

## Security and Privacy

- No secrets, credentials, personal data, external trust boundary, or remote access.

## Compatibility

- No compatibility-breaking API or data-format requirement is authorized.
- Production API visibility must not be widened solely for tests. When justified, narrowly scoped internal access must follow existing global constraints.
- Existing `Dummy.cs` files are outside scope and must not be deleted or changed by this feature.

## Tooling and Build

- Use NUnit through the existing Unity Test Framework for deterministic EditMode evidence.
- Do not add CI or perform E8 release/evaluation work or E9 tooling work.
- Do not use reflection to bypass intended architecture or visibility boundaries.
- Architecture tests must validate explicit repository invariants and avoid brittle semantic source-token rules.
- No authority, package, ProjectSettings, scene, or user-global tooling mutation.

Tool availability is not authorization, and product/executor assignments do not belong in this file.

## Operational and Manual Constraints

- The feature does not exercise or implement AI. `AI/Dummy.cs` remains outside scope; do not add `DeterministicReferencePolicy` or any other AI behavior.
- AI is optional for this reference flow; forcing it into the flow would be artificial; allowed dependency directions are ceilings, not requirements; Composition -> AI is not currently an explicit allowed direction.
- Utility modernization is out of scope. Do not use, move, or rewrite `IMonkeyLogger`, `IVersionProvider`, `MonkeyDebugLogger`, `MonkeyNullLogger`, or `VersionProvider`, and do not extend their placement pattern.
- No Dummy cleanup, documentation expansion outside this feature, production implementation, validation claim, release-readiness claim, staging, commit, push, or next-slice work is authorized by this approved feature authority.

## Traceability References

- Feature specification: `Assets/Project/Docs/Specifications/reference-architecture-example/SPEC.md`
- Acceptance criteria: `Assets/Project/Docs/Specifications/reference-architecture-example/ACCEPTANCE.md`
- Related authority or ADRs: `Assets/Project/Docs/Architecture/ARCHITECTURE.md`; `Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md`; no ADR
