# ISSUE RESOLUTION PROTOCOL
**SpecOps AI - Deterministic, Low-Token Spec Issue Resolution (Balanced Mode)**

Version: 1.4 (Balanced Mode – Copy-Ready Prompts)
Generated: 2026-02-23 11:56:32 UTC

---

# 0. Purpose

This document defines the complete Balanced Mode issue resolution workflow including:

- Required agent per step
- Exact prompts (copy-ready)
- Manual checkpoints
- Hard guardrails
- Deterministic precedence rules

Balanced Mode allows bounded structured interaction for governance (B)
and structural rewrite (C) issues without introducing open dialogue
loops.

This protocol is used when specification or architecture review
produces issues that should be resolved without open-ended discussion.

---

# 1. Global Guardrails

1. Max 3 AI turns per issue batch (excluding canonicalization).
2. Max 12 issues per batch.
3. No full-document rewrites.
4. Final output must be patch blocks only.
5. Governance precedence (fixed):

GLOBAL_CONSTRAINTS > Feature CONSTRAINTS > ARCHITECTURE > SPEC > ACCEPTANCE

---

# 2. Canonical Issue Format (Required)

IssueID | File | SectionPath | Type | Action | PatchHint

Type taxonomy:

AMBIGUOUS_TERM
UNTESTABLE_AC
MISSING_SECTION
MISSING_EDGE_CASE
SCOPE_CREEP
CONSTRAINT_CONFLICT
ARCH_LAYER_VIOLATION
DUPLICATION
NON_DETERMINISTIC_LANGUAGE

---

# 3. Workflow (Step-by-Step with Agent + Prompt)

---

## STEP 1 — Generate Findings

**Agent:** Codex (codexspec)
**Mode:** Analysis only

Run your normal codexspec workflow.

---

## STEP 2 — Canonicalize Findings

**Agent:** Codex
**Mode:** Normalization-only (no re-analysis)

### Prompt (Codex)

```text
Task: Convert your previous findings into a CANONICAL ISSUE LIST.

STRICT RULES:
- Do NOT perform new review.
- Do NOT add new issues.
- Max 12 issues.
- Merge duplicates.
- Discard cosmetic-only findings.

CANONICAL FORMAT:
IssueID | File | SectionPath | Type | Action | PatchHint

Type must be one of:
AMBIGUOUS_TERM, UNTESTABLE_AC, MISSING_SECTION, MISSING_EDGE_CASE,
SCOPE_CREEP, CONSTRAINT_CONFLICT, ARCH_LAYER_VIOLATION,
DUPLICATION, NON_DETERMINISTIC_LANGUAGE

Output only canonical issue lines.
```
Manual Check:
- ≤12 issues
- Valid taxonomy
- Section paths exist

---

## STEP 3 — Classification

**Agent:** Claude
**Mode:** Phase A Classification

### Prompt (Claude)

```text
You are executing the ISSUE RESOLUTION PROTOCOL (Balanced Mode).

Classify each IssueID into:

A) MECHANICAL
B) GOVERNANCE_DECISION_REQUIRED
C) NEEDS_HUMAN_REWRITE

Rules:
- Do NOT fix anything.
- Do NOT explain reasoning.
- Output only:
  A:
  B:
  C:
- List IssueIDs only.

Issues:
<PASTE CANONICAL ISSUE LIST>
```
Manual Action:
- A → Auto-fix later
- B → Governance framing required
- C → Rewrite proposal required

---

# 4. Balanced Mode Resolution

---

## STEP 4 — Governance Framing (B Issues)

**Agent:** Claude
**Mode:** Structured reasoning (bounded)

### Prompt (Claude)

```text
You are executing the ISSUE RESOLUTION PROTOCOL (Balanced Mode).

For each GOVERNANCE_DECISION_REQUIRED issue:

1) Restate the Problem (1–2 sentences).
2) Identify Structural Cause (1 sentence).
3) Provide:
   Option A (Conservative / constraint-preserving)
   Option B (Progressive / spec-expanding)
4) State Trade-off (1 sentence).

Rules:
- Do NOT rewrite documents.
- Max 150 tokens per issue.
- No global re-analysis.

Issues:
<PASTE B ISSUES>
```
Human Response (single turn):

```text
Decisions:
I-01 -> Option A
I-03 -> Option B
```

---

## STEP 5 — Structured Rewrite Proposal (C Issues)

**Agent:** Claude
**Mode:** Structured rewrite proposal (bounded)

### Prompt (Claude)

```text
You are executing the ISSUE RESOLUTION PROTOCOL (Balanced Mode).

For each NEEDS_HUMAN_REWRITE issue:

1) Restate the Problem (1–2 sentences).
2) Identify Root Cause (1 sentence).
3) Proposed Minimal Rewrite (≤180 tokens).
4) Architectural Impact:
   - None
   - Clarifies boundary
   - Introduces dependency (must flag)

Rules:
- Do NOT rewrite unrelated sections.
- Minimize scope expansion.
- No discussion.

Issues:
<PASTE C ISSUES>
```
Manual Action:
- Accept rewrite
- Modify manually
- Defer

---

## STEP 6 — Patch Generation

**Agent:** Claude
**Mode:** Deterministic patch output (final AI turn)

### Prompt (Claude)

```text
You are executing Phase C of the ISSUE RESOLUTION PROTOCOL.

Input:
- Canonical issues (A + B + accepted C)
- Governance decisions

Rules:
- Output PATCHES ONLY.
- No commentary.
- No reasoning.
- Max 120 tokens per issue.
- Apply mechanical rules.
- Respect precedence order.

Output format:

[IssueID]
Target: <FILE> :: <Heading path>
Operation: ADD | REPLACE | DELETE
Patch:
<exact text>

Issues:
<PASTE ISSUES>

Governance Decisions:
<PASTE DECISIONS OR "None">
```
Stop after patch output.

---

## STEP 7 — Apply Patches

**Agent:** Junie (Rider) or Manual

### Prompt (Junie)

```text
Apply the following patch blocks exactly.

Rules:
- Touch only referenced files.
- No extra edits.
- Preserve structure and IDs.
- If heading missing, apply under closest parent.
- Output checklist of applied IssueIDs.

Patch blocks:
<PASTE PATCHES>
```
---

## STEP 8 — Verification (Manual)

Checklist:
- All IssueIDs addressed
- No unrelated edits
- Precedence respected
- Deterministic language preserved
- Architecture boundaries maintained

Optional:
Re-run codexspec.

---

# 5. Token Control Limits

Balanced Mode enforces:

- Max 3 AI turns total
- Max 150 tokens per B issue
- Max 180 tokens per C rewrite
- No iterative clarification loops

If complexity grows → split batch.

---

# 6. Minimal Execution Summary

1) codexspec
2) Canonicalize (Codex)
3) Classify (Claude)
4) Governance framing (Claude)
5) Rewrite proposal (Claude)
6) Human decisions
7) Patch generation (Claude)
8) Apply (Junie/manual)
9) Verify

---

**End of Protocol — Version 1.4 (Balanced Mode – Copy-Ready Prompts)**
