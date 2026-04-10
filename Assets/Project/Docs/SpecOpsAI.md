# SpecOps AI

## Purpose

SpecOps AI is a specification-first operating model for AI-assisted engineering.

In this repository, it defines how work is shaped, reviewed, and validated before implementation grows beyond a small, controlled slice. It is a method, not a runtime framework and not a generic AI prompt style.

## Why It Exists

AI can produce code quickly. Speed alone does not preserve architecture, traceability, or testability.

SpecOps AI exists to keep AI-assisted work bounded by explicit constraints so the repository can stay readable, testable, and structurally consistent.

## Operating Model

The method is intentionally simple:

1. State the specification.
2. Derive acceptance criteria.
3. Check architectural drift and feasibility.
4. Implement one minimal slice.
5. Validate the slice with tests.
6. Commit only what is covered.

The unit of change is the acceptance criterion, not the prompt, the chat transcript, or a broad feature idea.

## Core Principles

### Specification Before Implementation

Implementation starts from explicit intent. If the scope is unclear, the work stays in specification.

### Acceptance Criteria Drive the Slice

Features should be broken into small, testable outcomes. Each slice should map to a specific acceptance criterion.

### Architecture Comes Before Code

The method does not permit implementation to ignore layer boundaries, dependency direction, or composition rules.

### Minimal Diffs

Changes should touch only the files needed for the current slice. Large, unrelated edits make review and rollback harder.

### Deterministic Verification

Every implemented slice should be validated with tests or other deterministic checks. The repository should not rely on implied correctness.

### Role Separation

The method separates specification work, validation work, and implementation work so a single pass does not silently widen scope.

## Repository Safety Logic

SpecOps AI uses conservative repository rules:

- Protect engine settings, generated metadata, and other project-critical files.
- Avoid destructive commands unless they are explicitly required and approved.
- Prefer narrow context over broad inspection when the task is already well defined.
- Require a reasoned path for structural changes, especially when they affect architecture or composition.
- Treat documentation, assembly definitions, and tests as constraints, not as optional commentary.

The intent is to reduce accidental drift, not to add ceremony.

## What It Is Not

- Not an AI autocomplete plugin.
- Not a prompt collection for ad hoc coding.
- Not a substitute for architecture or testing.
- Not a promise that every task can be fully automated.

SpecOps AI is a control model for AI-assisted engineering. It does not remove the need for engineering judgment.

## Use In This Repository

This repository expresses the method through docs, folder structure, assembly boundaries, and review discipline.

The method is meant to keep implementation work aligned with the architecture described in [Unity Clean Architecture](UnityCleanArchitecture.md).
