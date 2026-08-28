# Reference Architecture Example — Feature Acceptance Criteria

Status: APPROVED — CURRENT FEATURE AUTHORITY — IMPLEMENTATION COMPLETE

These criteria define observable outcomes. They do not record validation results and must not be treated as PASS until the required implementation and validation have executed under separate authorization.

## Identifier and Stability Rules

- Identifiers `AC-001` through `AC-008` are stable for this approved feature authority.
- Do not reuse an identifier for a different outcome.
- A material criterion change invalidates the affected downstream plan and permission and returns the work to specification and review.
- Retain superseded identifiers in feature history rather than silently renumbering remaining criteria.

### AC-001 — Pure Domain ReferenceMessage behavior

- Requirement / observable outcome: `ReferenceMessage` accepts valid non-empty text unchanged as an immutable value and deterministically rejects null, empty, and whitespace-only text. Its assembly and compiled source have no Unity engine/editor dependency.
- Deterministic validation method: Run focused EditMode NUnit cases for valid, null, empty, and whitespace-only inputs; inspect Domain asmdef and compiled assembly-reference evidence.
- Evidence expectation: Valid input yields the same accepted text; each invalid category yields the specified consistent rejection; `InfiniteMonkey.Domain` has `noEngineReferences = true` and no Unity engine/editor assembly reference.
- Validation category: EditMode plus static/compilation evidence.
- Manual requirement: None.
- Optional Given/When/Then framing:
  - Given: A candidate source string.
  - When: A `ReferenceMessage` is constructed.
  - Then: Valid text is exposed unchanged and invalid text is rejected deterministically without Unity involvement.

### AC-002 — Application-owned port and use case

- Requirement / observable outcome: Application owns `IReferenceTextSource`; `CreateReferenceMessage` obtains text through that port, delegates validation to Domain, and returns the accepted string through an API usable by Presentation without a Domain reference.
- Deterministic validation method: Run EditMode use-case tests with controlled port implementations or Moq for valid and invalid source text, then inspect the public contract and asmdef ownership.
- Evidence expectation: The source is called through `IReferenceTextSource`; valid text returns unchanged; invalid text follows Domain rejection; the Presentation-facing return type requires no Domain assembly reference.
- Validation category: EditMode plus static inspection.
- Manual requirement: None.
- Optional Given/When/Then framing:
  - Given: A controlled `IReferenceTextSource` and `CreateReferenceMessage`.
  - When: The use case executes.
  - Then: Domain validation governs the result and Presentation receives an Application-safe string.

### AC-003 — Deterministic Infrastructure adapter

- Requirement / observable outcome: `FixedReferenceTextSource` implements the Application-owned `IReferenceTextSource` and returns one fixed value without Unity or external/environmental dependencies.
- Deterministic validation method: Run an EditMode contract test through the `IReferenceTextSource` interface and inspect its assembly references and constructor/runtime requirements.
- Evidence expectation: Repeated calls return the same specified non-whitespace string; no network, file, clock, environment, external service, AI, or Unity dependency is required.
- Validation category: EditMode plus static inspection.
- Manual requirement: None.
- Optional Given/When/Then framing:
  - Given: A `FixedReferenceTextSource` viewed through the Application port.
  - When: Text is requested repeatedly.
  - Then: The same valid fixed text is returned each time.

### AC-004 — Thin Presentation adapter boundary

- Requirement / observable outcome: `ReferenceMessagePresenter` is a Unity-facing `MonoBehaviour` that invokes `CreateReferenceMessage` through an explicit method and requires no project-layer dependency on Domain, Infrastructure, or VContainer.
- Deterministic validation method: In EditMode, create the component with `GameObject.AddComponent<T>()`, supply its Application dependency through Composition-compatible initialization, invoke its explicit method, observe the produced value, and destroy the object; inspect Presentation asmdef project references.
- Evidence expectation: One explicit invocation produces the Application result; the component contains no Domain rule, Infrastructure knowledge, service locator, scene search, frame-loop requirement, or VContainer attribute/reference; Presentation references Application only among project runtime layers.
- Validation category: EditMode plus static inspection.
- Manual requirement: None.
- Optional Given/When/Then framing:
  - Given: A presenter initialized with a controlled Application use case.
  - When: Its explicit presentation method is invoked.
  - Then: It forwards the Application result without performing Domain or Infrastructure work.

### AC-005 — VContainer composed execution

- Requirement / observable outcome: Composition uses supported VContainer behavior to register `IReferenceTextSource` to `FixedReferenceTextSource`, register `CreateReferenceMessage`, and wire or initialize `ReferenceMessagePresenter`; the complete deterministic flow executes without a tracked scene.
- Deterministic validation method: Run an EditMode composition test that builds the bounded container graph using verified VContainer APIs, initializes a safely created presenter, invokes it, and observes the fixed accepted string.
- Evidence expectation: Container construction and resolution succeed; the presenter executes Presentation -> Application -> Domain while Infrastructure supplies the port; Composition contains wiring only and no direct Domain dependency unless separately returned for approval as genuinely necessary.
- Validation category: EditMode composition/integration.
- Manual requirement: None.
- Optional Given/When/Then framing:
  - Given: The approved registrations and a presenter created for EditMode validation.
  - When: Composition initializes the graph and the presenter is invoked.
  - Then: The fixed text passes through Domain validation and is observed at Presentation.

### AC-006 — Domain and Application engine independence

- Requirement / observable outcome: Domain and Application retain `noEngineReferences = true` and compile without Unity engine or editor assembly dependencies.
- Deterministic validation method: Parse both asmdefs for the required flag and inspect Unity compilation metadata for their compiled assembly references.
- Evidence expectation: Both flags are `true`; neither compiled assembly references `UnityEngine*` or `UnityEditor*`; compilation succeeds.
- Validation category: Static plus compilation/EditMode architecture validation.
- Manual requirement: None.
- Optional Given/When/Then framing:
  - Given: The implemented Domain and Application assemblies.
  - When: Architecture checks inspect declarations and compiled references.
  - Then: Engine independence remains enforced.

### AC-007 — Runtime assembly dependency conformance

- Requirement / observable outcome: Runtime project-layer asmdef references conform to `ARCHITECTURE.md`, with only implementation-required approved directions added and no prohibited direction introduced.
- Deterministic validation method: Parse all seven runtime asmdefs and compare project-assembly references against the authoritative allowlist while treating allowed unused directions as optional.
- Evidence expectation: The feature uses at most Application -> Domain; Infrastructure -> Application; Presentation -> Application; Composition -> Application, Infrastructure, Presentation. There is no Domain -> project layer; Presentation -> Domain, Infrastructure, or VContainer; Application -> Infrastructure or Presentation; Composition -> AI; or other unapproved project direction.
- Validation category: EditMode architecture/static validation.
- Manual requirement: None.
- Optional Given/When/Then framing:
  - Given: All runtime asmdefs after implementation.
  - When: Project-layer references are checked against structural authority.
  - Then: Every physical project-layer reference is allowed and required by actual implementation.

### AC-008 — Combined EditMode validation passes

- Requirement / observable outcome: All feature-required EditMode tests and the existing Moq smoke test are discovered and pass together, with no PlayMode test required solely to increase test count.
- Deterministic validation method: Run the complete EditMode test assembly through the Unity Test Framework under the repository's authorized validation procedure.
- Evidence expectation: The test run reports zero failures; all feature tests and `MoqSmokeTest.Can_mock_interface` are discovered and pass; the retained result identifies executed tests and does not claim unexecuted PlayMode coverage.
- Validation category: EditMode.
- Manual requirement: None beyond invoking the authorized deterministic test run.
- Optional Given/When/Then framing:
  - Given: The completed feature implementation and EditMode test assembly.
  - When: The complete EditMode suite runs.
  - Then: All required feature tests and the existing smoke test pass together.

## Traceability References

- Feature specification: `Assets/Project/Docs/Specifications/reference-architecture-example/SPEC.md`
- Feature constraints: `Assets/Project/Docs/Specifications/reference-architecture-example/CONSTRAINTS.md`
- Related authority or ADRs: `Assets/Project/Docs/Architecture/ARCHITECTURE.md`; `Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md`; no ADR
