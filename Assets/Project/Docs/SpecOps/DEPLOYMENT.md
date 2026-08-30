# Public Repository Deployment

Status: Derived instance and toolchain documentation. This file is not framework or structural authority.

This document maps SpecOps logical responsibilities to the default toolchain of `specops-unity-reference-implementation`. Deployment defaults do not become framework requirements.

## Required Distinctions

| Framework concept | Repository deployment |
| --- | --- |
| Logical responsibility describes what must be done. | An executor or product may be selected to perform that responsibility for a bounded slice. |
| Framework rules are VCS-neutral. | This repository uses Git and GitHub. |
| Validation requires suitable evidence. | The repository may use Git inspection, static inspection, Rider tooling, Unity compilation, or Unity tests when each is appropriate and authorized. |
| Permission comes from authority and Human Authority. | Tool access, MCP availability, credentials, and writable files do not grant permission. |

## Repository VCS

Git and GitHub are the approved VCS and hosting deployment for this public repository. Read-only inspection supports evidence collection. Branch changes, index mutation, commits, pushes, merges, tags, releases, destructive history operations, and publication require the authorization applicable to their risk and scope.

Final consequential check-in and publication remain human-controlled. SpecOps framework semantics do not require Git; this is an instance choice.

## Default IDE and Toolchain

JetBrains Rider is the approved Golden Baseline default IDE target. The default is informed by proven Rider-centered Unity workflows where appropriate. Rider is not required by SpecOps, and another suitable executor or deterministic tool may be used without changing framework authority.

Prefer deterministic tools for technical validation when they can directly establish the required evidence. Unity compilation and tests are evidence sources only when their execution is separately authorized and their retained results are reported accurately.

No workflow may silently mutate user-global Rider, IDE, shell, agent, MCP, or tool configuration. Installation or global configuration requires explicit user authorization and must identify its external effects.

## Executor and Product Mappings

The current deployment may use:

- **Codex** as an executor for authorized inspection, planning, implementation, or validation tasks;
- **Junie** as a Rider-integrated executor for authorized repository navigation, feasibility work, edits, or validation;
- **Rider and deterministic command-line tools** as technical interfaces and evidence sources;
- **humans** as executors and as Human Authority for consequential decisions.

These are deployment mappings only. Codex and Junie do not define or own logical framework roles. A task may use a different executor mapping while retaining the same separation of specification, governance, planning, implementation, validation, and Human Authority responsibilities.

## Current Integration Status

Legacy Rider templates, DotSettings artifacts, agent adapters, and product-specific tooling guidance predate the v2 consolidation. They are retained as subordinate compatibility material and do not define SpecOps v2 authority or Core requirements.

The derived `.specops/specops.json` manifest records public-repository deployment defaults. Exactly seven logical Skills, five permission profiles, and twelve JSON Schema contracts are installed beneath current authority. They do not elevate legacy Rider or agent integrations into framework authority.

Four eval definitions are installed under `.specops/evals/`, and `reference-architecture-example` has an instantiated derived feature state. The production Bootstrap and fresh-project Unity validation are complete. The qualified evidence subject remains A at `53595414f559d884d6d34ecafa7d350c1da96955`, and durable pre-Container evidence is staged at `release-evidence/v2.0.1-staging` commit `68760e6f177c443214efac465de8bcfb708cec33`. Container B records the `v2.0.1` release lifecycle state; the `v2.0.1` tag, GitHub Release publication, and promotion to `main` remain separate future Human Authority-controlled actions and have not yet occurred.
