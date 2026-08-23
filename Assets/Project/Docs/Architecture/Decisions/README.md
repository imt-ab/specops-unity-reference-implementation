# Architecture Decision Records

Status: Subordinate decision history and rationale. This directory is not current structural or repository-constraint authority.

ADRs record consequential architectural and repository-wide engineering decisions, their context, considered constraints, human approval, consequences, and supersession history.

Current structural truth remains in [`../ARCHITECTURE.md`](../ARCHITECTURE.md). Current repository-wide constraints remain in [`../../Governance/GLOBAL_CONSTRAINTS.md`](../../Governance/GLOBAL_CONSTRAINTS.md). Framework semantics remain in [`../../SpecOps/SPECOPS_V2.md`](../../SpecOps/SPECOPS_V2.md).

## Status Model

- **Draft** — incomplete working record; not approved.
- **Proposed** — ready for Human Authority review; not current authority.
- **Accepted** — Human Authority approved the recorded decision. Acceptance does not automatically change current authority.
- **Rejected** — considered and not approved.
- **Superseded** — replaced by an explicitly identified later decision.

## Authority Synchronization State

Decision status and authority synchronization are separate:

- **Pending** — the accepted decision changes current structural or repository-wide truth, but the applicable authority document has not yet been synchronized. Implementation must not rely on the changed truth.
- **Complete** — every affected current-authority document has been updated and reviewed to reflect the accepted decision.
- **Not required** — the accepted decision does not change current structural or repository-wide truth; the ADR records why synchronization is unnecessary.

An accepted ADR does not become competing current authority by itself. When the accepted decision changes current truth, it must be reflected in `ARCHITECTURE.md`, `GLOBAL_CONSTRAINTS.md`, or other applicable current authority before implementation relies on it. The ADR must record the synchronization state rather than acting as an implicit override.

Supersession must name the replacing ADR and affected authority. Do not rewrite or delete historical rationale merely because a later decision supersedes it.

Consequential architecture and global-constraint decisions require explicit Human Authority. Do not create retroactive or fake accepted ADRs to imply approval that was not recorded.

Use [`ADR-TEMPLATE.md`](ADR-TEMPLATE.md) for future decision records.
