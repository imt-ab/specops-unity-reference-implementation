You are operating inside an existing Unity 6000.3 repository using Plastic SCM and Rider.

Goal:
Create the repository AI governance, Specifications scaffolding, and architecture documentation aligned with the defined Project Structure Overview under Assets/Project.

Non-negotiable rules:
- Make the smallest possible diff that adds ONLY the requested new files/folders and their contents.
- Do NOT modify any existing files.
- Do NOT touch ProjectSettings/* or Packages/*.
- Do NOT delete, move, or regenerate any .meta files.
- Do not add or change dependencies.
- Do not reformat existing code.

Create EXACTLY these new files (create folders if missing):

────────────────────────────────
Governance (Repo Root)
────────────────────────────────
1) AI_RULES.md
2) TOOLING_RULES.md
3) .aiignore
4) .junie/guidelines.md

────────────────────────────────
Specifications (Project Folder)
────────────────────────────────
5) Assets/Project/Docs/Specifications/README.md
6) Assets/Project/Docs/Specifications/_templates/SPEC.md
7) Assets/Project/Docs/Specifications/_templates/CONSTRAINTS.md
8) Assets/Project/Docs/Specifications/_templates/ACCEPTANCE.md

────────────────────────────────
Workflow (Project Folder)
────────────────────────────────
9) Assets/Project/Docs/AI_WORKFLOW.md

────────────────────────────────
Architecture Docs (Project Folder)
────────────────────────────────
10) Assets/Project/Docs/Architecture/ARCHITECTURE.md

(Do NOT modify the existing Project Structure README.)

────────────────────────────────
File Content Requirements
────────────────────────────────

AI_RULES.md MUST include:

### Project
- Unity version: Unity 6000.3 (Unity 6.3)
- Language: C#
- Version control: Plastic SCM (Unity Version Control)

### Repository Safety
- Never delete or regenerate .meta files.
- Always commit matching .meta files.
- Never modify generated folders:
  Library/, Temp/, Obj/, Logs/, Build/, Builds/
- Do NOT modify ProjectSettings/* or Packages/* unless explicitly requested.

### Folder Placement Rules (Aligned to Project Structure README)

All new files must follow this structure:

Assets/Project/
Art/
Audio/
Content/
Code/
Docs/
Editor/


Rules:
- Runtime C# code must live under:
  Assets/Project/Code/Runtime/<Layer>
- Tests must live under:
  Assets/Project/Code/Tests/EditMode or PlayMode
- Editor-only scripts must live under:
  Assets/Project/Editor
- Scenes must live under:
  Assets/Project/Content/Scenes
- Prefabs must live under:
  Assets/Project/Content/Prefabs
- UI prefabs must live under:
  Assets/Project/Content/UI
- Input System assets must live under:
  Assets/Project/Content/Input
- Addressables must live under:
  Assets/Project/Content/Addressables
- Rendering settings must live under:
  Assets/Project/Content/Settings/Rendering
    - Global/
    - Pipeline/
    - Renderers/
    - Volumes/
- Lighting settings must live under:
  Assets/Project/Content/Settings/Lighting
- Quality settings must live under:
  Assets/Project/Content/Settings/Quality
- Art assets must live under:
  Assets/Project/Art
- Audio assets must live under:
  Assets/Project/Audio
- All C# scripts must use the root namespace defined in their corresponding assembly (e.g., namespace InfiniteMonkey.Domain). Avoid nested namespaces unless the folder structure justifies it.

Do NOT create scripts in:
Assets/
Assets/Scripts
Assets/Scenes
Assets/Resources
unless explicitly instructed.

────────────────────────────────

### Architecture (Clean Architecture – Authoritative)

Layer order:
Domain → Application → AI → Infrastructure / Presentation
Composition wires everything.

Dependency rules:
- Domain:
    - No UnityEngine references.
    - No MonoBehaviours.
- Application:
    - Depends only on Domain.
    - No UnityEngine.
- AI:
    - Depends on Application + Domain.
- Infrastructure:
    - Depends on Application + Domain.
- Presentation:
    - Contains UnityEngine references.
    - Translates Unity input into Application calls.
- Composition:
    - VContainer LifetimeScopes only.
    - No gameplay logic.
- Utility:
    - Cross-cutting helpers only.

Each Runtime folder corresponds to an asmdef:
InfiniteMonkey.Domain
InfiniteMonkey.Application
InfiniteMonkey.AI
InfiniteMonkey.Infrastructure
InfiniteMonkey.Presentation
InfiniteMonkey.Utility
InfiniteMonkey.Composition

For InfiniteMonkey.Domain and InfiniteMonkey.Application, ensure the .asmdef file has "noEngineReferences": true to enforce the 'No UnityEngine' rule.

Do not introduce new cross-assembly references casually.

────────────────────────────────

### Unity Constraints
- Respect Unity lifecycle methods.
- Avoid per-frame allocations in Update/LateUpdate/FixedUpdate.
- Avoid LINQ and closures in hot paths.
- Prefer [SerializeField] over runtime lookups.
- Avoid Find() and scene-wide searches.

### Logging
- Use IMonkeyLogger (interface in InfiniteMonkey.Utility.Interfaces) exclusively for logging.
- Do not introduce UnityEngine.Debug calls.

────────────────────────────────

### Testing (Unity EditMode – Authoritative)
- Use MOQ for mocking.
- Use VContainer for dependency injection.
- Use VContainer for container setup. Note: VContainer is already configured in the EditModeTests assembly definition.
- Do NOT use reflection.
- Use internal + InternalsVisibleTo for test access.
- MonoBehaviours must be created with GameObject.AddComponent<T>().
- Destroy created GameObjects in TearDown.
- Add XML documentation comments to test classes and methods.
- Test files should be named <TargetClass>Tests.cs and follow the same folder hierarchy as the code they test under Assets/Project/Code/Tests/EditMode or PlayMode.

────────────────────────────────

TOOLING_RULES.md MUST include:
- Allowed: add runtime/editor code; add tests.
- Prohibited: ProjectSettings/Packages edits; deleting metas; large restructures.
- Formatting: only touched files.
- CLI safety:
    - Allowed: Unity batchmode test execution.
    - Forbidden: destructive commands.

────────────────────────────────

.aiignore MUST ignore:
Library/, Temp/, Obj/, Logs/, Build/, Builds/,
UserSettings/, .vs/, .idea/, *.csproj, *.sln, .DS_Store, .plastic/, *.log

Optionally ignore:
Assets/Project/Art/**
Assets/Project/Audio/**

────────────────────────────────

.junie/guidelines.md MUST:
- State it is auto-loaded.
- Reference AI_RULES.md and TOOLING_RULES.md.
- Repeat non-negotiables.
- Point to:
  Assets/Project/Docs/Architecture/ARCHITECTURE.md
- Instruct: if ambiguous, STOP and propose spec changes.

────────────────────────────────

ARCHITECTURE.md MUST:
- Describe layer responsibilities.
- Include authoritative textual dependency graph.
- State dependency violations are not allowed.
- Align with the existing Project Structure README (do not duplicate it).

────────────────────────────────

Assets/Project/Docs/Specifications/README.md MUST describe:
Assets/Project/Docs/Specifications/<feature>/{SPEC.md, CONSTRAINTS.md, ACCEPTANCE.md}
Acceptance criteria must be testable.

Templates must include required sections:
- SPEC.md: Goals, Non-goals, User stories, Requirements, Edge cases, Performance, Telemetry/logging, Out of scope
- CONSTRAINTS.md: Must, Must not, Platforms, Performance budget, Compatibility
- ACCEPTANCE.md: Given / When / Then examples

────────────────────────────────

Assets/Project/Docs/AI_WORKFLOW.md MUST describe hybrid roles:
- Claude: spec authoring and review (no code).
- Junie: navigation, feasibility checks, refactors.
- Codex: implementation + tests with minimal diff.

────────────────────────────────

After completion:
- Output ONLY a checklist of file paths created.
- For every file and directory created, verify and include its corresponding `.meta` file in the checklist (e.g., `Assets/Project/Docs/AI_RULES.md` and `Assets/Project/Docs/AI_RULES.md.meta`).
- Do NOT include explanations.
- Do NOT suggest further changes.
