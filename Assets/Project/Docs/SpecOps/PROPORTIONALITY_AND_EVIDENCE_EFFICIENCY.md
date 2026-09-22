# Proportionality and Evidence Efficiency

Status: Derived operational guidance. This file is not framework, structural, repository-wide constraint, or feature authority.

## Purpose

This guide captures practical lessons for keeping SpecOps-governed work proportionate, evidence-driven, and quota-efficient without weakening Human Authority, protected-area controls, Unity metadata safety, or required validation.

It is operational guidance, not competing technical authority. If it conflicts with SpecOps, Architecture, Global Constraints, or approved feature authority, the higher authority wins.

Normative proportionality and evidence-efficiency rules belong in the governing SpecOps authority. This guide explains how to apply those rules operationally without turning process guidance into competing authority.

## Core Principle

Use the smallest amount of work that can reliably answer the current decision question.

A check is justified when its result can materially change:

- the decision;
- risk classification;
- required Human Authority;
- implementation safety;
- acceptance or validation verdict;
- release or publication safety.

If a check cannot change any of those, it should normally not be performed.

## Preferred Workflow

For vendor imports, Unity integration work, and similar repository tasks, prefer:

```text
BOUNDED PRE-CHECK
-> ISOLATED NATIVE TEST
-> RELEVANT SMOKE VALIDATION
-> TARGETED ANALYSIS OF ACTUAL DEVIATIONS
-> SHORT PLAN + BOUNDED HUMAN AUTHORITY
-> IMPLEMENT
-> VALIDATE
-> REVIEW
-> RELEASE/SYNC
```

This is a logical workflow, not a requirement that every phase use a separate conversation, executor run, report, or Human Authority message.

Do not perform phases ceremonially. Reuse existing evidence whenever it still covers the current question.

## 1. Test the Simplest Relevant Path Early

Before building a custom import, transformation, migration, or validation mechanism, first test the vendor- or platform-supported path in an isolated environment when safe and practical.

Examples:

- Prefer a disposable Unity clone and native `.unitypackage` import before emulating package import through archive extraction and raw file copying.
- Prefer opening representative prefabs/scenes in Unity before declaring serialized references broken from text scanning alone.
- Prefer observing the actual package/dependency prompts before designing policy around assumed installer behavior.

Static analysis remains useful, but should not replace a low-cost native test when the engine or tool owns important import semantics.

## 2. Separate Diagnostics from Verified Defects

Use explicit evidence states:

- **Observed** — directly seen in repository, tool output, Unity, or logs.
- **Inferred** — best explanation of observed evidence, not yet proven.
- **Unknown** — unresolved and not safe to invent.
- **Verified defect** — reproduced in the authoritative/runtime environment relevant to the acceptance criterion.
- **Proposed work** — possible corrective action, not authorized.
- **Approved work** — explicitly authorized bounded mutation.

A static GUID or reference-closure warning is diagnostic evidence. It is not automatically proof of a broken Unity binding.

## 3. Every Check Must Have a Decision Question

Before performing a new check, state internally:

> What decision could change if this result is different?

If there is no concrete answer, skip the check.

Good examples:

- "Does native import mutate `Packages/*`?" — can change permission/risk requirements.
- "Does the prefab still contain a Missing Script after a clean Library rebuild?" — can change acceptance verdict.
- "Did HEAD change in a way that affects this conclusion?" — can require delta reconciliation.

Low-value examples:

- Rehashing unchanged archives because a new phase started.
- Re-running full GUID scans after only an unrelated documentation change.
- Re-auditing package inventories already established and unchanged.

## 4. Time-Box Discovery and Reassess the Method

Use a short bounded discovery pass for ordinary work before choosing a large analysis path.

Typical goal: identify only what is needed to decide the next safe action, such as:

- protected areas;
- known dependency/install behavior;
- obvious path/GUID collisions;
- whether a native isolated test is possible;
- what Human Authority would be required for real mutation.

If two similar stop conditions occur in succession, reassess the method instead of automatically adding another audit layer.

Ask whether the real problem is:

- the implementation mechanism;
- the validation criterion;
- an incomplete permission boundary;
- a tool limitation;
- an actual vendor defect.

## 5. Prefer Semantic Boundaries over Fragile Inventory Counts

Do not make incomplete discovery counts into authority unless the count itself is required.

Prefer:

> "The approved HUD identities may be remapped within the HUD vendor subtree, including directly affected serialized asset and metadata references, with all actual mutations enumerated and validated before completion."

over:

> "Exactly 42 files may change."

Use exact path or file counts only when they are fully known, stable, and materially improve safety.

This reduces unnecessary re-approval when discovery finds one additional valid reference within an already approved semantic boundary.

## 6. Batch Normal Work; Stop at Real Decision Boundaries

Human Authority must remain explicit and bounded, but not every predictable sub-step needs a separate conversational approval.

Where authority allows, one bounded authorization may cover:

- implementation within named roots;
- the corresponding validation pass;
- evidence collection;
- derived-state/status updates.

Logical phase separation does not require separate executor runs or separate conversations. Multiple logical responsibilities may be executed in one bounded work slice when each included action is explicitly authorized and their evidence remains distinguishable.

A single Human Authority message may also grant several separate permissions when each permission is stated explicitly with its own scope and boundaries. Combining decisions in one message does not merge their semantics. Permission for one action must never be inferred as permission for another.

For example, one authorization may explicitly permit:

```text
implement the approved bounded slice
-> collect the specified evidence
-> execute the specified validation checks
-> update the agreed derived state
-> stop before publication
```

This is valid only when all of those actions are explicitly included. Implementation permission does not automatically grant validation permission, and validation permission does not automatically grant publication permission.

Keep separate authorization for consequential boundaries such as:

- `Packages/*` / dependency mutation;
- `ProjectSettings/*`;
- architecture/global-constraint changes;
- feature-authority changes;
- assembly topology;
- destructive operations;
- commit/push/merge/release/publication.

Do not create additional approval gates for normal sub-steps already covered by an explicit bounded authorization unless new evidence changes risk, scope, permission, acceptance, or safety.

## 7. Reuse Evidence Aggressively but Safely

Follow delta-first reconciliation.

Reuse prior evidence unless:

- relevant source/state changed;
- authority changed in a way that may affect the conclusion;
- previous evidence does not cover the question;
- evidence conflicts;
- fresh execution is genuinely required.

When HEAD changes:

```text
inspect exact diff
-> identify affected conclusions
-> reconcile only those conclusions
```

Do not audit an audit.

### Re-check only when something relevant could have changed

A new phase, new message, new executor, status update, or Human Authority decision is not by itself evidence that previously established technical facts became stale.

Re-check remote repository state when it can materially affect the next decision, for example when:

- the next action depends on a remote baseline;
- concurrent work may have changed relevant sources;
- a merge, release, publication, or remote comparison is being prepared;
- a previously reviewed conclusion depends on the exact remote commit.

A cheap local root/branch/worktree check before mutation can still be appropriate. Do not, however, make the user perform the same pre-check manually and then have the executor repeat it unless the independent repetition has a concrete safety purpose.

Recalculate hashes or byte identities when identity itself matters to the gate, not merely because work moved to another phase.

## 8. Use Unity for Unity Semantics

For Unity-specific correctness, prefer Unity evidence for questions Unity owns, including:

- imported asset binding;
- missing scripts/components;
- shader/material rendering;
- prefab/scene load behavior;
- importer warnings;
- compilation;
- Library/Asset Database reproducibility.

Textual YAML/.meta inspection is valuable for identity and change analysis, but should not independently override successful Unity-resolved behavior unless the acceptance criterion explicitly concerns serialized source identity.

### Classify inspection by actual side effects, not intent

"Read-only inspection" must describe the actual allowed operation and side-effect boundary, not merely the user's intention not to save a scene.

Opening Unity or another native tool can cause engine-managed refresh, import, compilation, cache, generated-state, or metadata activity even when no project-owned source asset is intentionally edited.

Before calling a Unity-based qualification or inspection read-only, define:

- which repository/source files must remain byte-identical;
- which generated or disposable side effects are acceptable;
- whether the work should run in the production worktree or an isolated/disposable copy;
- what post-operation diff or state check is required to prove the intended boundary held.

Do not promote a low-risk inspection to a large governance exercise merely because the tool has internal activity. Instead, classify the concrete side effects that matter to repository safety and permission.

## 9. Use Codex Where It Provides Leverage

Good Codex uses:

- bounded repository diff analysis;
- exact path/GUID inventories when needed;
- local filesystem evidence unavailable from GitHub;
- authorized deterministic mutations;
- validation automation that mirrors an approved acceptance criterion.

Poor Codex uses:

- reconstructing complex Unity-native behavior before testing Unity itself;
- broad rediscovery of already-established facts;
- repeated full scans after irrelevant changes;
- verbose intermediate reports that do not affect a decision.

Prefer one continuing Codex conversation when safe and useful. Logical phase separation does not require a new conversation.

### Prefer one writing owner per working copy

Where practical, use one executor as the writing owner for a worktree during a bounded workstream.

Avoid unnecessary file shuttling such as:

```text
executor creates file
-> another chat rewrites a separate copy
-> human manually copies it back
-> executor re-verifies identity
```

Prefer:

```text
executor owns repository copy
-> reviewer reports bounded findings
-> writing owner applies authorized correction in place
-> reviewer checks only the affected delta
```

This reduces parallel versions, manual copy errors, repeated hashing, and avoidable context reconstruction.

### Use delta-oriented continuation prompts

Stable repository rules, authority routing, and already-established evidence should normally be referenced rather than restated in full on every continuation.

A continuation prompt should focus on:

- the current decision or outcome;
- what changed since the previous step;
- exact allowed targets/actions;
- relevant reused evidence;
- stop conditions.

Start a new executor conversation when there is a concrete reason, such as unsafe context contamination, incompatible tool requirements, or a genuinely separate workstream. Do not start one merely because the logical SpecOps phase changed.

## 10. Keep Derived State Lightweight

Derived state such as `SPECOPS_STATE.json` records workflow status; it is not authority.

Update it when the state change matters, but do not let status synchronization become a repeated gate that overshadows the actual technical decision.

Prefer one bounded synchronization after a meaningful work slice rather than repeated updates after every small intermediate step.

### Record a decision once; synchronize it proportionately

A Human Authority decision should be recorded once. When allowed, synchronize the corresponding derived state as part of the next meaningful authorized work slice instead of creating a separate executor run whose only purpose is to mirror the decision.

A standalone status-sync run is justified only when, for example:

- a contract or downstream tool requires the state before any further safe work can begin;
- the status itself is the requested deliverable;
- a separate mutation boundary is required by authority;
- failing to synchronize immediately would create a material ambiguity or safety risk.

A derived-state update must never be used as a pretext to rewrite authority content, acceptance semantics, implementation scope, or other substantive material.

A status-only change does not by itself require a new substantive review of unchanged authority or implementation evidence.

## 11. Review at Decision Boundaries

Review stable material when the review can influence a real decision.

Typical useful review points include:

- before Human Authority approves a material feature authority;
- before Human Authority approves a consequential implementation plan;
- after implementation when evidence is ready for acceptance or release decisions;
- before publication when release safety depends on the result.

After a bounded correction, review the affected findings and necessary follow-on effects rather than repeating the entire prior audit or review.

Do not trigger a new substantive review merely because:

- a derived status field changed;
- work moved from one logical phase to another;
- a different executor continues the same unchanged artifact;
- the same already-reviewed content is copied without semantic change.

Use multiple independent reviewers only when independence can materially improve the decision, is required by authority, or addresses a specific unresolved risk. Do not routinely have several agents fully review the same unchanged artifact.

Persist a review artifact when it adds traceability needed by the workflow. Do not create review documents solely to duplicate a verdict already recorded adequately elsewhere.

## 12. Keep Process Experiments Lightweight

When SpecOps work includes an experiment about process efficiency, AI assistance, or developer capability, measure only what is needed to answer the approved experiment question.

If the approved method uses a pre-task team estimate rather than a controlled manual benchmark, do not manufacture a duplicate manual implementation merely to make the experiment look more scientific.

A proportionate process experiment can often use:

```text
PRE-TASK
- bounded task identity
- current-team effort estimate or range
- short rationale
- confidence

DURING
- meaningful iterations
- active human effort
- material tool/waiting friction when relevant
- human review/correction decisions

AFTER
- resulting artifact quality/status
- efficiency classification
- capability classification
- material limitations/uncertainty
```

Active human effort may include preparation, prompting, review, correction, attributable troubleshooting, cleanup, and necessary documentation. Unattended model execution time should not automatically be counted as active human effort.

Allow `INCONCLUSIVE` when the evidence does not support a credible conclusion. Do not add process overhead merely to force a stronger result.

The experiment must remain subordinate to the feature outcome. A positive process result cannot compensate for a failed feature acceptance result unless the governing acceptance authority explicitly says otherwise.

## 13. Practical Stop Rule

Stop gathering evidence when the current gate is sufficiently supported.

Continue only if another check can materially affect:

- permission;
- risk;
- implementation mechanism;
- acceptance result;
- validation result;
- release safety.

"More confidence" by itself is not enough when the next check is expensive and cannot change the decision.

## 14. Vendor Import Default Pattern

For future vendor `.unitypackage` work, use this default unless authority or evidence requires otherwise:

```text
1. Verify source identity/hash only if not already established.
2. Create or reuse an isolated clone at the relevant commit.
3. Perform the vendor-supported native Unity import.
4. Follow required installer/resource prompts in the disposable environment.
5. Record actual package/project mutations.
6. Run representative smoke checks.
7. If portability matters, perform one clean Library rebuild and repeat the minimal smoke checks.
8. Analyze only the deviations actually observed.
9. Design the production import/policy from that evidence.
10. Obtain bounded Human Authority before production mutation.
```

Do not begin with custom archive reconstruction unless native import is impossible or there is already evidence that it cannot satisfy the approved constraints.

## 15. Lessons from the Synty Pre-Sandbox Work

The Synty work demonstrated several concrete failure modes in process design:

- Native Unity import should have been tested before a custom raw extraction/copy workflow was made central to the implementation plan.
- Static unresolved-reference results were treated too strongly before Unity binding behavior was tested.
- Exact mutation counts were frozen before discovery was complete, creating avoidable re-approval churn.
- Package Helper, TMP Essentials, and dependency behavior were better understood by observing the native import than by reasoning from archive contents alone.
- Base Locomotion's magenta sample rendering is a render-pipeline compatibility issue, not evidence that the native import itself failed.
- Once sufficient evidence existed for a decision, additional broad scans would have added little value.
- Logical phase separation can become expensive when translated mechanically into separate conversations, repeated authority reads, repeated HEAD checks, repeated approval messages, and status-only runs.
- Moving corrected authority files through parallel chat copies creates avoidable versioning and identity-verification work; bounded in-place correction by the writing owner is usually safer and cheaper.

The intended response is not less governance. It is better ordering, tighter decision questions, stronger evidence-state discipline, fewer redundant checks, and fewer artificial conversational gates.

## Quick Checklist

Before starting a substantial SpecOps-governed task, ask:

- What is the current decision question?
- What is the cheapest safe test that can answer it?
- Does the platform/vendor provide a native path we should test first?
- Which facts are already established and reusable?
- Which protected boundaries actually require Human Authority?
- Can predictable implementation, evidence, validation, and state work be explicitly batch-authorized without crossing a consequential boundary?
- Is a proposed re-check triggered by relevant state change, or merely by a new phase/message/executor?
- Are we treating diagnostics as diagnostics rather than verified defects?
- Are exact counts truly necessary, or would a semantic boundary be safer?
- Is a supposedly read-only native-tool step actually side-effect free at the repository boundary that matters?
- Is there one clear writing owner for the active worktree/artifact?
- Can the continuation prompt describe only the delta instead of reconstructing all prior context?
- Is the next review tied to a real decision, or merely to a status transition?
- Can a derived-state update be folded into the next meaningful authorized slice?
- After two stops, should we reassess the method rather than add another audit?
- Can the next check materially change the decision?
- If not, stop gathering evidence.
