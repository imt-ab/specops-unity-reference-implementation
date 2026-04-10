# Post-Implementation Global Sync Process
**SpecOps AI - Spec Synchronization Protocol (Unity 6000.3 + Plastic SCM)**

This process is run after implementing a new feature to ensure the new
requirements and constraints stay consistent with the repository's
global documentation and to prevent multiple features from describing
conflicting realities.

It is designed to work with:
- **Unity 6000.3 (Unity 6.3)**
- **Plastic SCM** (no Git assumptions)
- **Rider IDE** with AI agents
- A **Claude agent limit of 3 `@` file references per prompt**

---

## Objectives

After each new feature:
1. Detect whether the feature introduces **global** requirements/constraints or architectural decisions.
2. Promote stable invariants to **GLOBAL_CONSTRAINTS.md**.
3. Capture cross-feature decisions as **ADR entries** in **ARCHITECTURE_DECISIONS.md**.
4. Ensure feature **ACCEPTANCE.md** remains truthful and does not implicitly invalidate older features.
5. Apply changes with **minimal diffs** and **docs-only** edits.

---

## Inputs and Outputs

### Inputs (per feature)
Feature folder (example):
- `Assets/Project/Docs/Specifications/<FeatureX>/SPEC.md`
- `Assets/Project/Docs/Specifications/<FeatureX>/CONSTRAINTS.md`
- `Assets/Project/Docs/Specifications/<FeatureX>/ACCEPTANCE.md`

Global docs (recommended to exist):
- `Assets/Project/Docs/Standards/GLOBAL_CONSTRAINTS.md`
- `Assets/Project/Docs/Architecture/ARCHITECTURE_DECISIONS.md`
- `Assets/Project/Docs/Architecture/ARCHITECTURE.md`

### Outputs
- Updated global docs (if needed)
- Updated feature docs (Alignment section + any required edits)
- A single **Junie-executable Sync Plan**
- No runtime code changes

---

## Phase 0 — Preconditions (Manual)

Before syncing:
- Feature implementation is complete.
- Tests are passing.
- `SPEC.md`, `CONSTRAINTS.md`, `ACCEPTANCE.md` reflect the *implemented* reality (not a draft).

If the global docs do not exist yet, create placeholders (docs only):
- `Assets/Project/Docs/Standards/GLOBAL_CONSTRAINTS.md`
- `Assets/Project/Docs/Architecture/ARCHITECTURE_DECISIONS.md`

---

## Phase 1 — Concept Drift Detection (Claude)

### Goal
Determine whether `<FeatureX>` introduces:
- Cross-feature invariants (global constraints)
- Architectural decisions (ADR-worthy)
- System-wide behavioral shifts

### Claude Prompt (3-file safe)
Replace `<FeatureX>` with your actual feature folder name.

```text
You are Claude acting as Specification Author & Reviewer.

You MUST follow:
- /AI_RULES.md
- /TOOLING_RULES.md
- Assets/Project/Docs/Architecture/ARCHITECTURE.md

Role constraints:
- Documentation analysis only.
- No production code changes.

Goal:
Determine whether FeatureX introduces global architectural,
constraint, or behavioral changes.

Files under review:

@Assets/Project/Docs/Specifications/<FeatureX>/SPEC.md
@Assets/Project/Docs/Specifications/<FeatureX>/CONSTRAINTS.md
@Assets/Project/Docs/Standards/GLOBAL_CONSTRAINTS.md

Task:

1) Identify any requirement or constraint in FeatureX that:
   - Redefines an existing global rule
   - Introduces a cross-feature invariant
   - Alters system-wide behavior

2) Classify each as:
   - Local (feature-only)
   - Global candidate
   - ADR required

3) If global:
   - Provide exact bullet wording for GLOBAL_CONSTRAINTS.md
   - Or propose ADR entry

4) If no global impact:
   - Explicitly confirm: "No global sync required."

Output:
A) Local-only changes
B) Global candidates
C) ADR candidates
D) Required doc updates
```

### Manual step after Phase 1
Save Claude’s output as **`PHASE1_OUTPUT`** (e.g., in a scratch note).

If Claude outputs **“No global sync required.”**, you can typically stop here and only perform:
- Phase 5 (Junie) to append the Alignment section (optional but recommended), or
- Do nothing if your feature docs already include Alignment.

---

## Phase 2 — Architectural Impact Check (Claude, conditional)

Run Phase 2 **only if Phase 1 reports**: *Global candidates* or *ADR required*.

### Claude Prompt (3-file safe)

```text
You are Claude.

Goal:
Verify whether FeatureX modifies architectural decisions.

Files under review:

@Assets/Project/Docs/Specifications/<FeatureX>/SPEC.md
@Assets/Project/Docs/Architecture/ARCHITECTURE.md
@Assets/Project/Docs/Architecture/ARCHITECTURE_DECISIONS.md

Task:

1) Identify conflicts with ARCHITECTURE.md.
2) Identify need for new ADR entries.
3) Provide ADR drafts in required format.
4) Confirm whether ARCHITECTURE.md must be amended.

Output:
A) Architectural conflicts
B) ADR drafts
C) Required architecture edits (if any)
```

### Manual step after Phase 2
Save Claude’s output as **`PHASE2_OUTPUT`**.

---

## Phase 3 — Acceptance Reality Check (Claude, optional)

Run Phase 3 when:
- Phase 1 or 2 suggests behavioral/system-wide changes, **or**
- You want a disciplined check that ACs still reflect a coherent system.

### Claude Prompt (3-file safe)

```text
You are Claude.

Goal:
Ensure FeatureX ACCEPTANCE criteria do not redefine global behavior
without being captured in global docs (GLOBAL_CONSTRAINTS/ADRs).

Files under review:

@Assets/Project/Docs/Specifications/<FeatureX>/ACCEPTANCE.md
@Assets/Project/Docs/Standards/GLOBAL_CONSTRAINTS.md
@Assets/Project/Docs/Architecture/ARCHITECTURE_DECISIONS.md

Task:

1) Identify ACs that redefine system-wide behavior.
2) Identify ACs that should be marked as:
   - Superseding older behavior
   - Narrowing scope
3) Propose minimal wording changes.

Output:
A) AC adjustments
B) Superseded markers (if required)
C) No-impact confirmation (if none)
```

### Manual step after Phase 3
Save Claude’s output as **`PHASE3_OUTPUT`**.

---

## Phase 4 — Consolidation (Minimize Manual Effort)

### Goal
Turn Phase 1–3 outputs into a single **Junie-executable Sync Plan** with:
- Deduplication
- Normalized wording
- Clear doc edits (paths + exact text)
- Explicit “Manual Decision Required” if conflicts exist

### What you do manually
Copy/paste the full outputs from Phase 1–3 into a single message to Claude using the prompt below.
This is the only manual consolidation step.

### Claude Prompt — Phase 4 Consolidation

```text
You are Claude acting as Specification Author & Reviewer.

You MUST follow:
- /AI_RULES.md
- /TOOLING_RULES.md
- Assets/Project/Docs/Architecture/ARCHITECTURE.md

Role constraints:
- Documentation consolidation only.
- No runtime code changes.
- Do not invent repository contents.
- Use only the provided Phase outputs.

Goal:
Consolidate multiple Phase outputs into a single deterministic Sync Plan suitable for Junie execution.

Context:
Below are raw outputs from:
Phase 1 — Concept Drift Detection
Phase 2 — Architectural Impact Check (if run)
Phase 3 — Acceptance Reality Check (if run)

<PASTE PHASE OUTPUTS HERE>

Task:

1) Deduplicate
- Remove repeated global candidates.
- Merge identical ADR suggestions.
- Collapse overlapping constraint updates.

2) Normalize wording
- Produce final authoritative wording for:
  - GLOBAL_CONSTRAINTS additions
  - ADR entries
  - ACCEPTANCE edits
  - ARCHITECTURE.md edits (if any)

3) Resolve internal conflicts
If two Phase outputs propose different resolutions:
- Prefer minimal-change option.
- If architectural decision required, classify as:
  "Manual Decision Required"
- Do NOT guess silently.

4) Remove noise
Exclude:
- Observational analysis
- Low-severity commentary
- Items classified as Local-only

5) Produce a clean Sync Plan with strict structure:

OUTPUT FORMAT (strict):

## Sync Plan

### 1. GLOBAL_CONSTRAINTS.md Updates
- [ ] <Exact bullet text to add>

### 2. ARCHITECTURE_DECISIONS.md Updates
ADR-XXX: <Title>
Status: Proposed/Accepted
Context:
Decision:
Consequences:

### 3. ARCHITECTURE.md Edits (if any)
File: Assets/Project/Docs/Architecture/ARCHITECTURE.md
Section: <Heading>
Replace with:
<Exact replacement text>

### 4. FeatureX CONSTRAINTS.md Updates
File: Assets/Project/Docs/Specifications/<FeatureX>/CONSTRAINTS.md
Section: <Heading>
Add/Replace:
<Exact text>

### 5. FeatureX ACCEPTANCE.md Updates (if required)
File: Assets/Project/Docs/Specifications/<FeatureX>/ACCEPTANCE.md
AC-XX:
Change to:
<Exact wording>
OR
Mark:
Status: Superseded by ADR-XXX

### 6. Manual Decision Required (if any)
- <Clear unresolved issue requiring human decision>

Constraints:
- Prefer minimal diffs.
- Do not restate unchanged content.
- Do not restructure documents.
- Output only the Sync Plan.

If no global changes are required:
Output only:
"NO GLOBAL SYNC REQUIRED"
```

### Manual step after Phase 4
- If the Sync Plan includes **“Manual Decision Required”**, resolve that decision *before* running Junie.
- Save the final Sync Plan as **`SYNC_PLAN`** (copy/paste).

---

## Phase 5 — Apply Sync Plan (Junie, run once)

### Goal
Apply documentation changes with:
- **Minimal diff**
- **Docs only**
- No runtime changes

### Junie Prompt (paste SYNC_PLAN)

```text
You are Junie operating in this Unity 6000.3 repository using Plastic SCM.

You MUST follow:
- /AI_RULES.md
- /TOOLING_RULES.md
- Assets/Project/Docs/Architecture/ARCHITECTURE.md
- ARCHITECTURE_CONTEXT_SNAPSHOT.md (if present)

Role constraints:
- Documentation-only changes.
- Do NOT modify runtime code, asmdefs, ProjectSettings/*, Packages/*.
- Do NOT delete/regenerate .meta files.
- Minimal diff only; do not reformat unrelated text.

Goal:
Apply FeatureX global synchronization plan.

Sync Plan:
<PASTE SYNC_PLAN HERE>

Tasks:

1) Update GLOBAL_CONSTRAINTS.md (if specified).
2) Add ADR entries to ARCHITECTURE_DECISIONS.md (if specified).
3) Amend ARCHITECTURE.md only if required by the plan.
4) Append Alignment section to FeatureX CONSTRAINTS.md if missing:

---
## Alignment

Depends on:
- GLOBAL_CONSTRAINTS.md
- ARCHITECTURE_DECISIONS.md

Overrides:
- None
---

If the plan indicates ADR impact, add:

Potential ADR Required:
- <items from plan>

5) Update ACCEPTANCE.md if required.
- Preserve AC numbering.
- If superseded, mark clearly:
  Status: Superseded by <Feature/ADR>
- Keep edits minimal.

Output (strict):
A) Files created
B) Files modified
C) Exact sections changed (file + heading)
D) Confirmation that no runtime files were modified
E) Any conflicts encountered (STOP instead of guessing)
```

---

## Phase 6 — Review + Commit (Manual)

### Review checklist (Manual)
- Only documentation files changed.
- Diffs are minimal (no reformatting of unrelated sections).
- Global docs updated correctly:
    - `GLOBAL_CONSTRAINTS.md`
    - `ARCHITECTURE_DECISIONS.md`
- FeatureX docs updated:
    - Alignment section present in `CONSTRAINTS.md`
    - ACCEPTANCE status markings (if any) are clear

### Commit message template (Manual)
```text
<FeatureX>: Post-implementation global sync

- Updated GLOBAL_CONSTRAINTS.md (if applicable)
- Added/updated ADR(s) (if applicable)
- Aligned FeatureX CONSTRAINTS/ACCEPTANCE
- Docs only; no runtime changes
```

---

## Optional: Add a “Global Impact Assessment” block to every feature CONSTRAINTS.md

Add this to your feature template to make sync easier next time:

```text
## Global Impact Assessment

Does this feature:
- Modify architectural layering? (Yes/No)
- Introduce cross-feature invariants? (Yes/No)
- Redefine system-wide behavior? (Yes/No)

If Yes → ADR required and GLOBAL_CONSTRAINTS review required.
```

---

## Summary (Fast Path)

1) **Claude Phase 1** (FeatureX SPEC + CONSTRAINTS + GLOBAL_CONSTRAINTS)
2) If needed: **Claude Phase 2** (FeatureX SPEC + ARCHITECTURE + ADR doc)
3) Optional: **Claude Phase 3** (FeatureX ACCEPTANCE + globals)
4) **Claude Phase 4** consolidation (paste outputs; get SYNC_PLAN)
5) **Junie Phase 5** apply SYNC_PLAN (docs only)
6) Manual review + commit
