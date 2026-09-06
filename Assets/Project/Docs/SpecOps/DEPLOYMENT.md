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

Legacy Rider templates, DotSettings artifacts, agent adapters, and
product-specific tooling guidance predate the v2 consolidation. They are
retained as subordinate compatibility material and do not define SpecOps v2
authority or Core requirements.

Current deployment configuration is represented by the repository's derived
artifacts, including `.specops/specops.json`, permission profiles, contracts,
eval definitions, and installed Skills. Inspect those artifacts directly when
their current contents or counts matter rather than relying on duplicated
numbers in this guide.

## Current Container B Lifecycle

This source tree is the bounded `v2.0.2` Container B release-container state.
The immutable technical subject remains
`46a16eb725294fa43943c8256dfb36d66b75d4e4`, with qualified Bootstrap Source
Identity
`f15e40d81f5612c1d31ab6f6fd52a97a3f35e508c6c2a5ef1eecdee17f4688c5`.
Durable pre-Container evidence remains separate on
`release-evidence/v2.0.2-staging` at
`e22a54ce6f3f056cb2df9868e1973cb59148cf55`.

Container B has a new Source Identity recorded in the projection manifest; its
Git commit identity is established by the materialization commit rather than
embedded in these files. The `v2.0.2` tag, GitHub Release, synchronization to
`origin/main`, and release-evidence finalization remain pending separate Human
Authority gates.

The production Bootstrap is the supported construction path for generating a
fresh project from a published Golden Baseline.

Release publication state is intentionally not duplicated in this deployment
guide. Use the repository's GitHub Releases, annotated tags, and release-bound
evidence when release state or identity matters.

The latest published Golden Baseline remains `v2.0.1`; Container B
materialization does not itself publish `v2.0.2`.
