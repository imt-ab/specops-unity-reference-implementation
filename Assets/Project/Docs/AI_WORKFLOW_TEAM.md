# AI Workflow — Team Operating Model (Updated)

_Last Updated: 2026-02-22_

This document defines exactly how the team works using the hybrid AI
model (Claude, Junie, Codex) and standardized Rider Live Templates.

This workflow is mandatory for all feature work.

-----------------------------------------------------------------------

# Core Governance Rule

No Code Before Drift Clearance.
No Slice Before Implementability Validation.
No Commit Without AC Coverage.

-----------------------------------------------------------------------

# Updated Lifecycle

Idea
→ SpecDraft
→ Spec Review
→ Acceptance Criteria
→ Drift Prevention Gate
→ Implementability Check
→ Feasibility Validation
→ Slice Planning
→ Slice Implementation
→ Validation
→ Commit

Testing is embedded inside slice completion and driven by Acceptance Criteria.
Rider test templates are enforcement tools, not default ceremony steps.

-----------------------------------------------------------------------

# 1. Roles

## Claude (Specification Author & Reviewer — No Code)

Responsibilities:
- Draft `SPEC.md` using `specdraft`.
- Refine spec using `claudespec`.
- Generate `ACCEPTANCE.md` using `claudeac`.
- Perform Drift Prevention using `claudedrift`.
- Ensure clarity, determinism, and architectural compliance.
- Identify ambiguity and missing constraints.

Claude MUST NOT:
- Write production code.
- Modify `ProjectSettings/` or `Packages/`.
- Propose architectural violations without ADR.

-----------------------------------------------------------------------

## Junie (Navigator & Feasibility Validator)

Responsibilities:
- Validate layer placement and asmdef boundaries.
- Enforce `noEngineReferences` constraints.
- Confirm folder structure compliance.
- Identify structural risks.
- Approve or block refactors.

Junie MUST NOT:
- Modify `ProjectSettings/` or `Packages/`.
- Delete `.meta` files.
- Perform structural refactors without explicit request.

-----------------------------------------------------------------------

## Codex (Implementation + Minimal Diff)

Responsibilities:
- Validate implementability using `codexspec`.
- Propose vertical slices.
- Implement one AC slice at a time.
- Respect Clean Architecture boundaries.
- Respect DI (VContainer) and logging conventions.
- Make the smallest possible diff.

Codex MUST:
- Stop after requested slice.
- Avoid unrelated refactors.
- Never modify protected folders.

-----------------------------------------------------------------------

# 2. Specification Phase

## Step 1 — specdraft

Create:
Assets/Project/Docs/Specifications/<FeatureName>/SPEC.md


Complete:
- Governance Header
- Goals / Non-goals
- Requirements
- Edge cases
- Performance
- Telemetry

If governance indicates ADR required → stop and create ADR first.

-----------------------------------------------------------------------

## Step 2 — claudespec

Refine wording and eliminate ambiguity.

Ensure:
- Architectural alignment
- Testability
- Explicit edge cases
- Manual Unity artifacts identified (listed only, not created)

-----------------------------------------------------------------------

## Step 3 — claudeac

Generate deterministic ACs:
- AC-01…AC-XX
- Given / When / Then format
- Mark `[EditMode]` or `[PlayMode]`
- Each AC must be testable

-----------------------------------------------------------------------

# 3. Drift Prevention Phase (Mandatory)

## Step 4 — claudedrift

Purpose:
- Detect architectural redefinitions.
- Prevent ownership, lifecycle, DI, logging, or invariant drift.
- Ensure ADRs are written before architecture changes.

Blocking conditions:
- ADR required but not written
- Governance header incomplete
- Supersession not defined
- Global invariant conflict

Verdict must be:
Safe to implement


Otherwise → return to specification stage.

No implementation work may begin before drift clearance.

-----------------------------------------------------------------------

# 4. Implementability Phase

All issues identified in `codexspec` must be resolved using the formal **ISSUE_RESOLUTION_PROTOCOL.md (Balanced Mode)** before implementation proceeds.


## Step 5 — codexspec

Validate:
- Ambiguous ACs
- Untestable ACs
- Missing constraints
- Layer compatibility
- Manual Unity artifacts list

No code generation allowed.

-----------------------------------------------------------------------

# 5. Feasibility Phase

## Step 6 — junie

Validate:
- Folder structure
- Dependency direction
- asmdef boundaries
- `noEngineReferences`
- Minimal diff strategy

Conflicts → return to specification stage.

-----------------------------------------------------------------------

# 6. Vertical Slice Planning

## Step 7 — codex (Planning Mode)

Codex must:
- Propose 3–7 vertical slices
- Map slices 1:1 to AC IDs
- List layers
- List files (new/modified)
- List required tests
- List manual setup (if any)

STOP after slice proposal.

Implementation begins only after slice selection.

-----------------------------------------------------------------------

# 7. Slice Implementation

## Step 8 — codex (Implementation Mode)

Implement only:
- The selected AC slice
- Minimal diff
- Required test coverage per AC

Embedded Testing Rule:

If AC requires new coverage → use Rider template.
If existing coverage satisfies AC → do not scaffold unnecessarily.
If regression detected → enforce Rider template.

-----------------------------------------------------------------------

# 8. Validation

Run Unity tests in batchmode.

If failures:
- Fix before next slice.

-----------------------------------------------------------------------

# 9. Commit Discipline

Before commit:
- Minimal diff only
- No `ProjectSettings` changes
- No `Packages` changes
- All `.meta` files present
- No formatting-only diffs

Commit message must reference:
- Feature name
- AC IDs implemented

-----------------------------------------------------------------------

# 10. Stop Conditions

Immediately stop if:
- Drift verdict ≠ Safe to implement
- ADR required but missing
- Acceptance contradicts architecture
- `ProjectSettings` or `Packages` must change
- Unity required in Domain/Application layer

Return to specification stage.

-----------------------------------------------------------------------

# Cultural Rule

Structure first. AI second.

AI accelerates disciplined engineering — it does not replace it.
