# SpecOps Unity Reference Implementation

This repository is a public reference implementation for combining SpecOps AI and Unity Clean Architecture in one Unity project.

It is intentionally narrow. The goal is to show how the method, the architecture, and the repository structure fit together in practice without overstating maturity or completeness.

SpecOps AI is the operating model used to shape work: specification first, acceptance-criteria driven, drift-checked, minimal-diff, and test-backed.
Unity Clean Architecture is the structural model used in the codebase: explicit layers, strict dependencies, and Unity-specific code kept at the edges.

This repository is not the framework itself and it is not a finished product. It is a working reference that shows one disciplined way to combine the two.

## Status

- Public reference implementation / proof-of-work
- Target editor: Unity `6000.3.7f1`
- Primary package and assembly structure is already in place
- Parts of the implementation are scaffolded rather than complete
- Some folders are documentation-only or scaffolding-only by design
- Treat the structure, asmdefs, docs, and tests as the main signal of intent

## What This Repo Demonstrates

- How AI-assisted work can stay bounded by specifications, acceptance criteria, and architectural rules.
- How Unity code can be split into `Domain`, `Application`, `AI`, `Infrastructure`, `Presentation`, `Composition`, and `Utility` assemblies.
- How VContainer is used for composition and Moq is used for tests.
- How to keep Unity engine dependencies out of the core application model.
- How the repository distinguishes between method, architecture, and implementation.

## Intended Audience

- Unity developers evaluating Clean Architecture in practice.
- Teams looking for a bounded example of AI-assisted engineering.
- Readers who want a reference implementation, not a general-purpose framework.

## What You Will Find Here

- `Assets/Project/Code/Runtime` contains the layered runtime assemblies.
- `Assets/Project/Code/Tests` contains EditMode and PlayMode tests.
- `Assets/Project/Docs` contains method, architecture, and workflow docs.
- `Assets/Project/Docs/Specifications` contains feature specs and templates.
- `Assets/Project/Docs/Architecture` contains the structural authority.
- `Assets/Project/README.md` contains the project structure overview.

## Start Here

1. Open the project in Unity `6000.3.7f1`, or check `ProjectSettings/ProjectVersion.txt` for the exact editor version.
2. Let Unity resolve the packages listed in `Packages/manifest.json`.
3. Read [SpecOps AI](Assets/Project/Docs/SpecOpsAI.md) and [Unity Clean Architecture](Assets/Project/Docs/UnityCleanArchitecture.md).
4. Review the project structure in [Assets/Project/README.md](Assets/Project/README.md) and the code layout under `Assets/Project/Code`.
5. Inspect the `InfiniteMonkey.*` asmdefs under `Assets/Project/Code` to see how the boundaries are applied in the repository.
6. Use `Assets/Project/Docs/Specifications` for feature spec templates and workflow details.

## First Checks

1. Confirm package resolution completes without errors.
2. Confirm the solution and `InfiniteMonkey.*` asmdefs compile.
3. Run EditMode tests first.
4. Run PlayMode tests only when you need runtime or scene-level validation.

## Repository Layout

- `Assets/Project/Code/Runtime` - runtime assemblies and gameplay code
- `Assets/Project/Code/Tests` - EditMode and PlayMode tests
- `Assets/Project/Docs` - method and architecture documentation
- `Assets/Project/Docs/Specifications` - feature specifications and templates
- `Assets/ScriptTemplates` - script templates used to keep file creation consistent

## Requirements

- Unity 6000.3 (Unity 6.3)
- JetBrains Rider if you want the intended IDE workflow
- VContainer and Moq are already referenced in the project packages

## License

This repository is published under the Apache License 2.0. See [LICENSE](LICENSE) for the full text.

Copyright 2026 Infinite Monkey Theorem AB.

## Contributing

Contributions are welcome, but this repository is intentionally scoped as a reference implementation.

Issues and small pull requests are welcome within the scope above.

Welcome:
- Documentation fixes
- Small bug fixes
- Test improvements
- Narrow changes that improve clarity, correctness, or consistency
- Changes that stay within the existing architecture and workflow model

Before opening a pull request:
- Keep the change small and focused
- Follow [SpecOps AI](Assets/Project/Docs/SpecOpsAI.md)
- Follow [Unity Clean Architecture](Assets/Project/Docs/UnityCleanArchitecture.md)
- Include specification updates and tests for behavior changes
- Preserve minimal-diff discipline

Discuss first:
- Architecture changes
- Broad refactors
- New dependencies
- Changes to `ProjectSettings/`
- Changes to `Packages/`

Not a fit:
- Rewrites that turn this repo into a general-purpose framework
- Large feature additions that are not supported by the current reference implementation
- Changes that weaken the architectural boundaries or repository safety rules

## Related Docs

- [SpecOps AI](Assets/Project/Docs/SpecOpsAI.md)
- [Unity Clean Architecture](Assets/Project/Docs/UnityCleanArchitecture.md)
- [AI Workflow Team Operating Model](Assets/Project/Docs/AI_WORKFLOW_TEAM.md)
- [Specifications Index](Assets/Project/Docs/Specifications/README.md)

## Current Scope

This is a reference implementation. Some areas are scaffolded or documentation-only by design. Treat the code, assembly boundaries, documentation, and tests as the source of truth for the intended shape of the system.
