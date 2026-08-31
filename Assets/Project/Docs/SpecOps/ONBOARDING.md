# Public Reference Repository Onboarding

Status: Derived contributor guidance for the current development state of
`specops-unity-reference-implementation`. This document is not release,
framework, structural, or feature authority.

This repository is a public reference implementation showing one concrete
combination of SpecOps AI v2 and a selected Unity Clean Architecture.

For contribution and reference-repository development, work from the
human-selected current development state and applicable current authority.

For a new stable Unity project, do not treat `main` as the released Golden
Baseline. Follow the root [INSTALL.md](../../../../INSTALL.md) and use the latest
published GitHub Release.

Release tags, publication state, release identities, and immutable release
evidence are defined by their release-bound records and are intentionally not
duplicated as mutable status in this contributor guide.

## Choose the Correct Starting Point

**Contributing to or developing this reference repository:** use the
human-selected development branch and inspect current repository authority and
state before work begins.

**Starting a new stable Unity project:** use the latest published Golden
Baseline and follow [INSTALL.md](../../../../INSTALL.md).

Development state and released state are deliberately distinct. Do not infer
that `main` and the latest published Golden Baseline are identical.

## Start With Current Authority

1. Read the [SpecOps v2 framework authority](SPECOPS_V2.md).
2. Read the [Unity structural authority](../Architecture/ARCHITECTURE.md).
3. Read the [repository-wide engineering constraints](../Governance/GLOBAL_CONSTRAINTS.md).
4. For feature work, read that feature's `SPEC.md`, `CONSTRAINTS.md`, and `ACCEPTANCE.md` under `../Specifications/<feature>/`.

The root [`AGENTS.md`](../../../../AGENTS.md) is an operational router, not authority. ADRs, workflow guides, deployment guidance, plans, reviews, validation results, templates, installed Skills, and `.specops/*` files are subordinate.

## Repository Identity and Structure

The public identity, maturity, licensing, and contribution scope are described in the root [`README.md`](../../../../README.md), [`LICENSE`](../../../../LICENSE), and [`NOTICE`](../../../../NOTICE).

The current Unity editor baseline is retained in [`ProjectSettings/ProjectVersion.txt`](../../../../ProjectSettings/ProjectVersion.txt). The layered runtime, editor, test, content, and documentation layout is indexed by [`Assets/Project/README.md`](../../README.md).

The selected architecture contains Domain, Application, AI, Infrastructure, Presentation, Composition, and Utility runtime layers. Domain and Application remain engine-independent. Refer to structural authority for the allowed dependency directions; do not infer that every allowed dependency must already exist physically.

## Repository Workflow

Use the derived [`WORKFLOW.md`](WORKFLOW.md) to navigate intent, specification, governance, risk, approval, planning, scoped permission, implementation, validation, traceability, global-impact review, and human-controlled publication.

The specification root is [`Assets/Project/Docs/Specifications`](../Specifications/README.md). The sole canonical feature-template location is [`../Specifications/_templates/feature/`](../Specifications/_templates/feature/), containing the authority triplet plus derived `SPECOPS_STATE.json`. The state template conforms to [the feature-state schema](../../../../.specops/contracts/feature-state.schema.json). Templates are unapproved scaffolding only. The approved and implemented [`reference-architecture-example`](../Specifications/reference-architecture-example/SPEC.md) is an actual feature instance with derived state; it is not inherited by fresh Bootstrap children.

## Git and GitHub

This repository instance uses Git and GitHub. Keep work on the human-selected branch, inspect status and diffs, preserve unrelated work, and leave commits, pushes, merges, tags, releases, and other consequential publication actions under explicit human control.

Do not modify `Packages/*`, `ProjectSettings/*`, Git configuration, history, branches, or the index without separate authorization.

## Default Developer Path

JetBrains Rider is the Golden Baseline default IDE target for this repository. It is a deployment default, not a SpecOps framework requirement. Existing Rider templates and product-specific tooling guidance are retained as subordinate legacy compatibility material; they do not define SpecOps v2 authority.

Open or execute Unity only when the current task explicitly authorizes it. Do not allow tools to silently modify user-global IDE or agent configuration.

## Validation Expectations

Validation must match the authorized slice and produce reportable evidence. Distinguish static inspection, compilation, EditMode tests, PlayMode tests, and manual Unity validation. Never report a PASS for a check that was not performed.

Before handing work back:

- review the complete diff and working-tree status;
- confirm only authorized paths changed;
- confirm protected areas and Unity metadata remain safe;
- report executed validation, omitted validation, unexpected observations, and remaining approval boundaries;
- stop without beginning an unapproved next slice or release action.
