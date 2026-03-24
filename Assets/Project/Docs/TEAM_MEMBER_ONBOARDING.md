# Team Member Onboarding Guide

Welcome to the project! This document will guide you through everything you need to know to become productive on this Unity-based game development project.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Development Environment Setup](#development-environment-setup)
3. [Project Structure & Architecture](#project-structure--architecture)
4. [AI-Assisted Development Workflow](#ai-assisted-development-workflow)
5. [Coding Standards & Best Practices](#coding-standards--best-practices)
6. [Testing Guidelines](#testing-guidelines)
7. [Repository Safety Rules](#repository-safety-rules)
8. [Specification & Documentation Process](#specification--documentation-process)
9. [Daily Development Workflow](#daily-development-workflow)
10. [Key Resources & References](#key-resources--references)

---

## Project Overview

### Technology Stack

- **Unity Version:** Unity 6000.3 (Unity 6.3)
- **Language:** C# 9.0 (net471)
- **Version Control:** Plastic SCM (Unity Version Control)
- **Dependency Injection:** VContainer
- **Testing Frameworks:** MOQ (mocking), VContainer
- **IDE:** JetBrains Rider (with Live Templates)

### Core Principles

This project follows **Clean Architecture** principles with strict layer separation and dependency management. We use a hybrid AI-assisted development model with three specialized AI agents (Claude, Junie, Codex) to maintain architectural integrity and code quality.

---

## Development Environment Setup

### Required Tools

1. **Unity 6000.3 (Unity 6.3)**
   - Download and install from Unity Hub
   - Ensure all required modules are installed

2. **JetBrains Rider 2025.3+**
   - Preferred IDE for this project
   - Import the provided Live Templates for consistency

3. **Plastic SCM (Unity Version Control)**
   - Configure your Plastic SCM credentials
   - Familiarize yourself with basic Plastic SCM commands

### PowerShell 7+ (Recommended)

PowerShell 7+ (`pwsh`) is strongly recommended for this project.

**Reason:**
- Windows PowerShell 5.1 does NOT reliably default to UTF-8.
- AI agents are required to read repository text files using explicit UTF-8 encoding.
- PowerShell 7+ has safer UTF-8 defaults and improved cross-platform behavior.

#### Check If Installed

```powershell
pwsh --version
```

If a version number (7.x or higher) is returned, PowerShell 7+ is installed.

If the command is not recognized, install it using one of the methods below.

Installation (Windows 11)
Option 1 — Winget (Recommended)

```powershell
winget install --id Microsoft.Powershell --source winget
```
Option 2 — Microsoft Installer

Go to:
https://github.com/PowerShell/PowerShell/releases

Download the latest stable .msi for Windows (x64).

Run the installer.

Restart your terminal.

After Installation

Use pwsh instead of powershell when running commands manually.

AI agents should prefer PowerShell 7+ when available.

UTF-8 encoding must still be explicitly enforced when reading files as defined in TOOLING_RULES.md.

#### Set pwsh as Default Shell in Rider’s Integrated Terminal

- Open Settings/Preferences
  - Press Ctrl + Alt + S (Windows)
  - Or go to File > Settings…
- Navigate to: Tools > Terminal
- Locate “Shell path”
  - Under Application Settings, you’ll see Shell path, which Rider uses for the integrated terminal.
- Replace the existing path with the path to pwsh:
  - For a typical PowerShell 7 install on Windows (x64):
    - `C:\Program Files\PowerShell\7\pwsh.exe`
  - If you installed it from the Microsoft Store or another location, use the corresponding path (find it by running `where pwsh` in a normal Windows terminal).
- Apply & restart Rider (if needed)

Now, when you open the Terminal pane in Rider (View > Tool Windows > Terminal or `Alt + F12`), it will start using PowerShell 7 instead of the old PowerShell 5.1.

### Initial Repository Setup

1. Clone the repository using Plastic SCM
2. Open the project in Unity (let it compile and import all packages)
3. Open the project in Rider
4. Verify all assembly definitions compile without errors

---

## Project Structure & Architecture

### Folder Organization

All project files are organized under `Assets/Project/`:

```
Assets/Project/
├── Art/                    # Art assets (models, materials, shaders, textures)
├── Audio/                  # Audio assets (music, SFX)
├── Code/                   # All C# code
│   ├── Runtime/           # Runtime code organized by layer
│   │   ├── Domain/        # Enterprise rules and core models
│   │   ├── Application/   # Use cases and orchestration
│   │   ├── AI/            # AI strategies and policies
│   │   ├── Infrastructure/# Adapters (persistence, files, networking)
│   │   ├── Presentation/  # Unity-facing layer (views, input)
│   │   ├── Composition/   # VContainer LifetimeScopes
│   │   └── Utility/       # Cross-cutting helpers
│   ├── Tests/
│   │   ├── EditMode/      # Unit tests (pure logic)
│   │   └── PlayMode/      # Integration tests (runtime)
├── Content/               # Unity content
│   ├── Scenes/           # Scene files
│   ├── Prefabs/          # Prefab assets
│   ├── UI/               # UI prefabs
│   ├── Input/            # Input System assets
│   ├── Addressables/     # Addressable assets
│   ├── Animations/       # Animation clips
│   └── Settings/         # Project settings (Rendering, Lighting, Quality)
├── Docs/                 # Documentation
│   ├── Architecture/     # Architecture documentation
│   ├── Specifications/   # Feature specifications
│   └── Ide/             # IDE workflow guides
└── Editor/              # Editor-only scripts
```

### Clean Architecture Layers

#### Layer Responsibilities

1. **Domain**
   - Enterprise rules and core models
   - Pure C# - **NO** `UnityEngine` references
   - **NO** `MonoBehaviour` classes
   - Assembly: `InfiniteMonkey.Domain`

2. **Application**
   - Use cases, orchestration, and ports (interfaces)
   - Depends **only** on Domain
   - **NO** `UnityEngine` references
   - Assembly: `InfiniteMonkey.Application`

3. **AI**
   - AI strategies and policies
   - Depends on Application + Domain
   - Assembly: `InfiniteMonkey.AI`

4. **Infrastructure**
   - Adapters: persistence, files, networking, platform services
   - Depends on Application + Domain
   - Assembly: `InfiniteMonkey.Infrastructure`

5. **Presentation**
   - Unity-facing layer: views, input translation, scene hooks
   - Depends on Application
   - **CAN** reference `UnityEngine`
   - Assembly: `InfiniteMonkey.Presentation`

6. **Composition**
   - VContainer LifetimeScopes and registrations **only**
   - **NO** gameplay logic
   - Wires all concrete implementations to interfaces
   - Assembly: `InfiniteMonkey.Composition`

7. **Utility**
   - Cross-cutting helpers and shared utilities (e.g., logging interfaces)
   - Standalone; can be referenced by other layers
   - Assembly: `InfiniteMonkey.Utility`

#### Dependency Graph

```
Domain ← Application ← AI
                    ← Infrastructure
                    ← Presentation

Composition wires all layers
Utility is standalone
```

#### Critical Dependency Rules

- **Domain:** Depends on nothing. No `UnityEngine`.
- **Application:** Depends on Domain. No `UnityEngine`.
- **AI:** Depends on Application, Domain.
- **Infrastructure:** Depends on Application, Domain.
- **Presentation:** Depends on Application (and Unity APIs).
- **Composition:** Depends on all layers (for wiring only).
- **Utility:** Standalone.

**Violations of these dependency rules are not permitted.**

### Assembly Definitions

Each Runtime layer has an `.asmdef` file:

- `InfiniteMonkey.Domain` - **`"noEngineReferences": true`**
- `InfiniteMonkey.Application` - **`"noEngineReferences": true`**
- `InfiniteMonkey.AI`
- `InfiniteMonkey.Infrastructure`
- `InfiniteMonkey.Presentation`
- `InfiniteMonkey.Utility`
- `InfiniteMonkey.Composition`

The `noEngineReferences` setting enforces the "No UnityEngine" rule at compile time.

**Do not introduce new cross-assembly references casually.**

---

## AI-Assisted Development Workflow

### The Hybrid AI Model

This project follows the [AI Workflow Team Operating Model](AI_WORKFLOW_TEAM.md) using three specialized AI agents with distinct roles:

#### 1. **Claude** (Specification Author & Reviewer)
- **Purpose:** Drafts and refines specifications
- **Responsibilities:**
  - Writes and refines specifications
  - Defines constraints and acceptance criteria
  - Ensures clarity and testability
  - Reviews acceptance criteria for testability
- **Does NOT:** Write or modify production code

#### 2. **Junie** (Navigator & Feasibility Validator)
- **Purpose:** Navigates the repository and validates architectural compliance
- **Responsibilities:**
  - Navigates the repository and gathers context
  - Validates architectural compliance
  - Checks layer placement and asmdef boundaries
  - Proposes minimal-diff plans
  - Performs feasibility checks against architectural and tooling rules
  - Refactors only when explicitly requested
- **Never:** Changes ProjectSettings/Packages or deletes .meta files

#### 3. **Codex** (Implementation + Tests)
- **Purpose:** Implements features with minimal diff
- **Responsibilities:**
  - Implements acceptance criteria
  - Writes EditMode/PlayMode tests using VContainer and MOQ
  - Adheres to Clean Architecture and assembly boundaries
  - Makes the smallest possible diff
  - Uses `IMonkeyLogger` for logging
- **Constraints:** Respects all architectural and testing rules

### Feature Development Lifecycle

**Every feature follows this lifecycle:**

```
Idea → Spec → Constraints → Acceptance → Feasibility → Implementation → Tests → Validation → Commit
```

**No shortcuts.**

### Workflow Summary

1. **Claude** authors or updates a feature spec under `Assets/Project/Docs/Specifications/<feature>/`
2. **Junie** validates structure, constraints, and feasibility against `AI_RULES.md` and `TOOLING_RULES.md`
3. **Codex** implements code under the correct layer (`Assets/Project/Code/Runtime/<Layer>`) and adds tests under `Assets/Project/Code/Tests`
4. Tests are executed in Unity batchmode; logs are reviewed for failures
5. Changes are committed to Plastic SCM with matching `.meta` files and without touching generated folders

### Rider Live Templates

The project uses standardized Rider Live Templates for consistency. Key templates include:

#### Specification Phase (Claude)
- **`specdraft`** - Starting a new feature specification
- **`claudespec`** - Reviewing a draft SPEC.md
- **`claudeac`** - Writing or refining acceptance criteria

#### Feasibility Phase (Junie)
- **`junie`** - Checking layer placement and assembly boundaries

#### Implementation Phase (Codex)
- **`codex`** - Implementing a specific acceptance criterion slice

#### Test Writing
- **`edittest`** - Unit tests for Domain or Application logic (EditMode)
- **`moqbind`** - Binding mocked dependencies in VContainer
- **`mbtest`** - Testing MonoBehaviour-based components (EditMode)
- **`pmtest`** - Integration tests requiring runtime context (PlayMode)
- **`pmmbtest`** - Testing runtime MonoBehaviour behaviors (PlayMode)
- **`unitytest`** - Coroutine-based tests
- **`ivt`** - Adding InternalsVisibleTo for test access

**For detailed workflow instructions, see the [AI Workflow Team Operating Model](AI_WORKFLOW_TEAM.md).**

---

## Coding Standards & Best Practices

### Namespace Conventions

- All C# scripts must use the root namespace defined in their corresponding assembly
- Example: `namespace InfiniteMonkey.Domain`
- Avoid nested namespaces unless the folder structure justifies it

### Unity Constraints

- **Respect Unity lifecycle methods**
- Avoid per-frame allocations in `Update`/`LateUpdate`/`FixedUpdate`
- Avoid LINQ and closures in hot paths
- Prefer `[SerializeField]` over runtime lookups
- Avoid `Find()` and scene-wide searches

### Logging Standards

- **Primary Rule:** Use `IMonkeyLogger` (interface in `InfiniteMonkey.Utility.Interfaces`) exclusively for logging
- **Prohibited:** Do not introduce `UnityEngine.Debug` calls in runtime code

### File Placement Rules

**DO NOT create scripts in:**
- `Assets/` (root)
- `Assets/Scripts`
- `Assets/Scenes`
- `Assets/Resources`

Unless explicitly instructed.

**Always follow the defined folder structure under `Assets/Project/`**

---

## Testing Guidelines

### Testing Philosophy

- **EditMode preferred** unless runtime behavior is required
- Tests must be **deterministic** and **repeatable**
- Tests must respect architectural boundaries

### EditMode vs PlayMode

#### Choose EditMode when:
- Testing pure logic
- No frame-based behavior
- No Unity lifecycle dependencies
- Fast feedback needed

#### Choose PlayMode when:
- Testing coroutines
- Frame-based behavior
- Physics / rendering
- VContainer scene integration

### Testing Frameworks

- **MOQ** for mocking
- **VContainer** for dependency injection
- **VContainer** for container setup

**Note:** VContainer is already configured in the EditModeTests assembly definition.

### Testing Constraints

- **DO NOT use reflection**
- Use `internal` + `InternalsVisibleTo` for test access
- MonoBehaviours must be created with `GameObject.AddComponent<T>()`
- **NEVER** instantiate MonoBehaviours using `new`
- Always destroy created GameObjects in `TearDown`
- Add XML documentation comments to test classes and methods

### Test File Naming and Location

- Test files should be named `<TargetClass>Tests.cs`
- Follow the same folder hierarchy as the code they test
- EditMode tests: `Assets/Project/Code/Tests/EditMode/<mirrored path>/`
- PlayMode tests: `Assets/Project/Code/Tests/PlayMode/<mirrored path>/`

### Test Writing Workflow

1. **Plan with AI:** Determine which acceptance criteria need tests
2. **Create test file** in the correct location
3. **Expand template:** Use appropriate Rider Live Template (`edittest`, `pmtest`, etc.)
4. **Add mocks:** Use `moqbind` template for dependency mocking
5. **Ask AI to fill in:** Provide context and let AI implement test logic within the scaffold

---

## Repository Safety Rules

### .meta File Handling

- **NEVER** delete or regenerate `.meta` files
- **ALWAYS** commit matching `.meta` files with your changes
- For every file and directory created, Unity generates a `.meta` file that must be tracked

### Protected Folders

**Never modify these generated folders:**
- `Library/`
- `Temp/`
- `Obj/`
- `Logs/`
- `Build/`
- `Builds/`

### Protected Settings

- **DO NOT** modify `ProjectSettings/*` or `Packages/*` unless explicitly requested
- These changes require team coordination and approval

### Minimal Diff Philosophy

- Make the **smallest possible diff** that adds only the requested changes
- Do **NOT** modify existing files unless necessary
- Do **NOT** reformat existing code
- Formatting changes should only be applied to files you're actively working on

### Allowed vs Prohibited Actions

**Allowed:**
- Add runtime/editor code
- Add tests
- Unity batchmode test execution

**Prohibited:**
- ProjectSettings/Packages edits (without explicit approval)
- Deleting .meta files
- Large restructures (without proper planning)
- Destructive CLI commands

---

## Specification & Documentation Process

### Feature Specification Location

All features must have specifications under:
```
Assets/Project/Docs/Specifications/<feature>/
```

### Required Specification Files

Every feature requires three files:

1. **SPEC.md**
   - Goals and non-goals
   - User stories
   - Requirements
   - Edge cases
   - Performance considerations
   - Telemetry/logging requirements
   - Out of scope items

2. **CONSTRAINTS.md**
   - Must (requirements)
   - Must not (prohibitions)
   - Platform constraints
   - Performance budget
   - Compatibility requirements

3. **ACCEPTANCE.md**
   - Testable acceptance criteria
   - Format: **Given / When / Then**
   - Each criterion must be testable in Unity (EditMode or PlayMode)
   - Must respect Domain/Application purity

### Acceptance Criteria Standards

**Format Example:**
```
AC-01: User can see health bar
Given: A player character with health component
When: The player takes damage
Then: The health bar updates to reflect current health percentage
```

**Requirements:**
- Must be testable in Unity
- Must respect architectural boundaries
- Must avoid reflection and unsafe MonoBehaviour instantiation
- Must be compatible with existing testing constraints

### Specification Process

1. Start with templates under `Assets/Project/Docs/Specifications/_templates/`
2. Use Rider Live Templates to scaffold specifications
3. **Claude** reviews and refines
4. **Junie** validates architectural feasibility
5. **Codex** implements based on approved specification
6. Implementation must reference acceptance criteria identifiers (e.g., AC-01, AC-02)

**Specification ambiguity must block implementation.**

---

## Daily Development Workflow

### Recommended Daily Loop

Follow this sequence per acceptance criterion:

1. **`specdraft`** — Define feature
2. **`claudeac`** — Write acceptance criteria
3. **`codexspec`** — Validate spec clarity
4. **`junie`** — Architecture validation
5. **`codex`** — Implement slice
6. **`edittest`** / **`pmtest`** — Write tests
7. **Run tests** in Unity batchmode
8. **Fix failures** before commit

**Repeat per acceptance criterion.**

### Stage-by-Stage Process

#### Stage 1 — Specification (Claude)
- Create required files: SPEC.md, CONSTRAINTS.md, ACCEPTANCE.md
- Blocking conditions: ambiguous requirements, missing edge cases, untestable criteria

#### Stage 2 — Feasibility (Junie)
- Verify layer placement, dependency direction, noEngineReferences enforcement
- Confirm folder structure compliance and testability
- If conflicts found → Return to Claude

#### Stage 3 — Implementation (Codex)
- Implement one acceptance criterion at a time
- Respect assembly boundaries
- Use smallest possible diff
- Use IMonkeyLogger for logging

#### Stage 4 — Testing
- Write EditMode tests for pure logic
- Write PlayMode tests for runtime behavior
- Use MOQ for mocking, VContainer for DI
- No reflection, proper cleanup in TearDown

#### Stage 5 — Validation
- Run Unity tests in batchmode
- Review logs for failures
- Fix failures before proceeding

#### Stage 6 — Commit Discipline

**Before commit, verify:**
- Minimal diff achieved
- No ProjectSettings changes
- No Package changes
- All .meta files included
- No formatting-only diffs

**Commit message must reference:**
- Feature name
- Acceptance criteria IDs (e.g., "Implemented health system AC-01, AC-02")

### Context-Specific Workflows

#### When Starting a New Feature
```
specdraft → claudeac → codexspec → junie → codex → edittest/pmtest
```

#### When Implementing
```
junie → codex → (edittest OR pmtest)
```

#### When Fixing a Bug
```
junie (understand impact) → codex (fix) → edittest/pmtest (regression test)
```

#### When Refactoring
- Requires **Junie** validation first
- No structural changes without explicit plan
- No cross-assembly shortcuts
- Lock behavior with tests before refactoring

**For more details on the mandatory daily workflow and stage-by-stage process, see the [AI Workflow Team Operating Model](AI_WORKFLOW_TEAM.md).**

---

## Stop Conditions

**Immediately stop and escalate if:**

- You need Unity in Domain/Application layers
- You must modify ProjectSettings or Packages
- Acceptance criteria contradict architecture
- You must delete or regenerate .meta files

**Return to specification stage and seek clarification.**

---

## Key Resources & References

### Core Documentation

- **AI Rules:** `AI_RULES.md` (repository root)
- **Tooling Rules:** `TOOLING_RULES.md` (repository root)
- **Junie Guidelines:** `.junie/guidelines.md`
- **Architecture:** `Assets/Project/Docs/Architecture/ARCHITECTURE.md`
- **Architecture Context Snapshot:** `Assets/Project/Docs/Architecture/ARCHITECTURE_CONTEXT_SNAPSHOT.md`
- **AI Workflow:** [AI Workflow Team Operating Model](AI_WORKFLOW_TEAM.md)

### Specification Templates

- **SPEC Template:** `Assets/Project/Docs/Specifications/_templates/SPEC.md`
- **CONSTRAINTS Template:** `Assets/Project/Docs/Specifications/_templates/CONSTRAINTS.md`
- **ACCEPTANCE Template:** `Assets/Project/Docs/Specifications/_templates/ACCEPTANCE.md`

---



---

## Issue Resolution Protocol (Balanced Mode)

All specification validation issues (e.g., findings from `codexspec`) must be resolved using the formal:

**ISSUE_RESOLUTION_PROTOCOL.md (Version 1.4 – Balanced Mode)**

Location:
```
ISSUE_RESOLUTION_PROTOCOL.md (repository root)
```

This protocol defines:

- Canonical issue normalization
- Classification (A/B/C)
- Governance Framing Pass (B issues)
- Structured Rewrite Proposal (C issues)
- Deterministic patch generation
- Hard token guardrails
- Agent responsibility per step

No ad-hoc conversational issue resolution is permitted.

Balanced Mode is mandatory when:
- Governance conflicts exist
- Structural ambiguity exists
- Architecture boundaries are implicated

Strict Mode may be used when issues are purely mechanical.

Refer to ISSUE_RESOLUTION_PROTOCOL.md before attempting to resolve specification validation findings.

## Cultural Rules

### Never Skip the Specification Stage

AI accelerates development — it must not bypass discipline.

### Structure First, AI Second

Templates enforce structure. AI fills logic.

### Architectural Integrity is Non-Negotiable

Clean Architecture boundaries exist for a reason. Violations require architectural review and team consensus.

### Test-Driven Discipline

Tests are not optional. Every acceptance criterion must have corresponding test coverage.

---

## Getting Help

If you have questions or encounter issues:

1. **Review this onboarding guide** first
2. **Check the relevant documentation** in `Assets/Project/Docs/`
3. **Consult with team members** or tech leads
4. **Use AI agents appropriately:**
   - Claude for specification clarification
   - Junie for architectural questions
   - Codex for implementation guidance

---

## Welcome Aboard!

This project maintains high standards for architecture, testing, and code quality. The AI-assisted workflow is designed to help you work efficiently while maintaining these standards.

Take time to familiarize yourself with the architecture, read through existing specifications, and experiment with the Rider Live Templates.

Happy coding!
