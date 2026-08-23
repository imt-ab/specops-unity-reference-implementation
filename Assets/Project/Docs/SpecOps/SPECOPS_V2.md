# SpecOps AI v2

Status: Current framework authority for SpecOps semantics in this repository.

This document defines the framework rules used by the public Unity reference implementation. The repository is a concrete SpecOps AI v2 deployment and Golden Baseline candidate; it is not the generic SpecOps Core repository.

## Authority Model

There are exactly four current-authority domains:

1. **Framework authority** — this document defines SpecOps semantics, risk, approval, permission, evidence, and traceability.
2. **Structural authority** — [`../Architecture/ARCHITECTURE.md`](../Architecture/ARCHITECTURE.md) defines the selected Unity architecture and allowed dependency directions.
3. **Repository-wide engineering constraints** — [`../Governance/GLOBAL_CONSTRAINTS.md`](../Governance/GLOBAL_CONSTRAINTS.md) defines engineering constraints for this public repository.
4. **Feature authority** — `../Specifications/<feature>/SPEC.md`, `CONSTRAINTS.md`, and `ACCEPTANCE.md` define an approved feature within the higher-scope authorities.

The domains have distinct boundaries. Framework semantics constrain the operating model; structural authority controls code structure; repository constraints apply across work in this repository; feature authority controls only its bounded feature. A lower-scope authority cannot silently override a higher-scope rule. Conflicts stop work until the relevant authority is clarified by Human Authority.

ADRs preserve decision history and rationale. An accepted ADR is not competing current authority: its accepted consequence must be synchronized into the applicable current authority document before implementation relies on it.

## Evidence Before Verdict

A verdict must follow evidence. Evidence must identify its source, scope, and limitations. Observed state must be separated from inference, and unknowns must remain unknown rather than being filled by assumption.

Validation claims must state what was actually inspected or executed. Tool availability, prior results, documentation intent, and a plausible implementation do not by themselves prove current conformance or success.

## Specification Before Implementation

Consequential implementation begins from explicit intent and applicable authority. Feature work requires stable specification, constraints, and acceptance criteria before its implementation slice is authorized.

Acceptance criteria must be identifiable, deterministic enough to validate, and stable for the duration of an implementation slice. A material change to an acceptance criterion invalidates the affected plan and permission; work returns to specification and review.

Ambiguity, missing authority, or conflict between feature intent and higher-scope authority blocks implementation.

## Bounded Change

Work must be divided into explicit, reviewable slices. Each slice identifies its intended outcome, affected scope, validation, and stop boundary.

Changes must be minimal relative to the authorized outcome. Permission for one change does not authorize cleanup, broad refactoring, dependency changes, settings changes, publication, or adjacent migration work.

## Logical Responsibilities

SpecOps separates logical responsibilities such as:

- intent and specification;
- governance, authority, and risk review;
- planning and permission framing;
- implementation;
- independent validation and evidence review;
- Human Authority for consequential approval and final control.

These are logical responsibilities, not product identities. No AI product, IDE agent, model, person, or tool owns a framework role by name. Deployment configuration may map executors to responsibilities for a particular slice, and the same mapping may change without changing framework authority.

## Risk Classification

Every proposed action is classified at the highest applicable level:

- **R0 — Observation:** read-only inspection, analysis, or reporting with no repository, external-system, or user-setting mutation.
- **R1 — Bounded reversible change:** a narrow, locally reviewable change inside established authority that avoids protected or consequential areas.
- **R2 — Material or cross-cutting change inside established authority:** a change affecting shared behavior, migration state, or multiple significant consumers while remaining inside established authority and without redefining framework authority, structural authority, the dependency baseline, protected project configuration, permissions, or another elevated boundary.
- **R3 — Consequential or elevated boundary change:** includes, as applicable, framework-authority semantic changes; architecture-authority semantic changes; repository-wide or global-constraint changes; dependency addition, removal, or upgrade; changes under `Packages/*` or `ProjectSettings/*`; assembly-topology changes; permission elevation; compatibility-breaking changes; destructive operations; history mutation; external publication, deployment, or release; and other difficult-to-reverse boundary changes.

Uncertainty about impact raises the classification until evidence resolves it. Splitting work into a smaller slice may reduce scope, but does not conceal or lower the risk of the underlying action.

## Human Approval

Human approval must be informed, explicit, and tied to a described scope and risk. Silence, prior approval for a different slice, product capability, or access to a tool is not approval.

R0 inspection may proceed within the requested scope. R1 mutation requires task-level authorization and bounded permission. R2 and R3 require explicit Human Authority approval before the consequential action. Conditions attached to approval remain binding.

Final consequential publication, release, deployment, push, merge, or check-in remains human-controlled according to repository policy. An executor may prepare evidence and an unstaged or uncommitted change only when that is the authorized boundary.

## Permission Semantics

Permission is scoped authority to perform specific actions, not a general grant. A usable permission identifies:

- the authorized objective and slice;
- allowed actions and targets;
- prohibited or protected areas;
- applicable risk ceiling and approvals;
- validation and stop conditions;
- the point at which permission expires.

Permission does not propagate to adjacent work. Higher-risk actions require their own approval. Revocation, changed evidence, changed acceptance criteria, or an encountered stop condition ends the permission.

Tool capability is not authorization. The presence of an MCP server, command, plugin, API, network connection, credential, filesystem access, or writable repository does not grant permission to use it.

## Derived Artifacts

Operational routers, Skills, `.specops/*`, workflow and deployment guides, onboarding, state files, plans, reviews, validation and synchronization results, eval definitions/results, release evidence, IDE templates, agent adapters, and context exports are derived or subordinate artifacts.

They may summarize, route, automate, or evidence current authority. They must identify their status and sources, and must not silently introduce, supersede, or compete with authority.

## Traceability

Each consequential slice must retain enough traceability to connect:

- intent and applicable authority;
- acceptance criteria or other bounded outcome;
- risk classification and human approvals;
- granted permission and affected files or systems;
- implementation changes;
- validation evidence and unresolved unknowns;
- global-impact or authority synchronization;
- final human review or publication decision where required.

Traceability may be represented by derived artifacts, but those records do not become authority merely by recording the work.

## Stop Conditions

Stop before mutation or further consequential action when:

- applicable authority is missing, contradictory, or outside the requested scope;
- required evidence cannot be obtained safely;
- acceptance criteria are absent, ambiguous, or materially changed;
- risk cannot be classified with available evidence;
- required permission or Human Authority approval is missing;
- actual work would exceed the approved targets or risk;
- validation cannot support the required verdict;
- a derived artifact conflicts with current authority.

A stop must report the blocking evidence and must not silently repair, widen scope, or substitute inference for authority.

## VCS Neutrality

SpecOps framework semantics are VCS-neutral. The framework neither requires nor prohibits any specific VCS. Repository-specific version-control rules belong to the deployment and operational guidance for that repository instance.
