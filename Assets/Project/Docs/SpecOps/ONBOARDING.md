# Public Reference Repository Onboarding

Status: Derived contributor guidance for the `specops-v2` migration branch. SpecOps v2.0.0 is not claimed as released.

This repository is a public reference implementation and Golden Baseline candidate showing one concrete combination of SpecOps AI v2 and a selected Unity Clean Architecture. It is not the generic SpecOps Core repository, a finished game, or a claim that this architecture is mandatory for every Unity project.

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

The specification root is [`Assets/Project/Docs/Specifications`](../Specifications/README.md). The sole canonical feature-template location is [`../Specifications/_templates/feature/`](../Specifications/_templates/feature/), containing the authority triplet plus derived `SPECOPS_STATE.json`. The state template conforms to [the feature-state schema](../../../../.specops/contracts/feature-state.schema.json). Templates are unapproved scaffolding only; no feature or feature-state instance is installed by E3.

## Git and GitHub

This repository instance uses Git and GitHub. Keep work on the human-selected branch, inspect status and diffs, preserve unrelated work, and leave commits, pushes, merges, tags, releases, and other consequential publication actions under explicit human control.

Do not modify `Packages/*`, `ProjectSettings/*`, Git configuration, history, branches, or the index without separate authorization.

## Default Developer Path

JetBrains Rider is the Golden Baseline default IDE target for this repository. It is a deployment default, not a SpecOps framework requirement. Existing Rider templates and agent adapters are legacy artifacts preserved during E1; do not assume they are already v2-conformant.

Open or execute Unity only when the current task explicitly authorizes it. Do not allow tools to silently modify user-global IDE or agent configuration.

## Validation Expectations

Validation must match the authorized slice and produce reportable evidence. Distinguish static inspection, compilation, EditMode tests, PlayMode tests, and manual Unity validation. Never report a PASS for a check that was not performed.

Before handing work back:

- review the complete diff and working-tree status;
- confirm only authorized paths changed;
- confirm protected areas and Unity metadata remain safe;
- report executed validation, omitted validation, unexpected observations, and remaining approval boundaries;
- stop without beginning the next migration slice.
