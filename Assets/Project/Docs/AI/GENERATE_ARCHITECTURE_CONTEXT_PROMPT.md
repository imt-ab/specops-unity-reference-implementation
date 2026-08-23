Status: Derived context-export tooling prompt. This prompt is not authority and does not grant permission.

You are operating inside an existing Unity 6000.3 repository whose current instance uses Git/GitHub and whose default IDE target is Rider.

Goal:
Create or update the following files so they reflect the current authoritative architecture and governance rules:

1) Assets/Project/Docs/Architecture/ARCHITECTURE_CONTEXT_SNAPSHOT.md
2) Assets/Project/Docs/Architecture/CHAT_CONTEXT_EXPORT.md

Non-negotiable rules:
- Make the smallest possible diff.
- Do NOT modify any existing files except the two listed above.
- Do NOT touch ProjectSettings/* or Packages/*.
- Do NOT delete or regenerate any .meta files.
- Do NOT reformat unrelated content.
- Do NOT introduce new dependencies.

────────────────────────────────
SOURCE OF TRUTH
────────────────────────────────

Use `AGENTS.md` to route to the applicable current authority. Read these current authority and instance sources:

- /AGENTS.md
- Assets/Project/Docs/SpecOps/SPECOPS_V2.md
- Assets/Project/Docs/Architecture/ARCHITECTURE.md
- Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md
- Assets/Project/Docs/Specifications/README.md (for structure overview)
- .specops/specops.json (derived instance configuration; not authority)

Do NOT invent architectural rules.
If required authority or information is missing or contradictory, stop and report the gap rather than inferring a rule.

────────────────────────────────
FILE 1: ARCHITECTURE_CONTEXT_SNAPSHOT.md
────────────────────────────────

Purpose:
A discussion-ready but complete snapshot of the current architecture and governance.

Requirements:
- Must contain:
    - Project basics (Unity version, language, version control)
    - Layer definitions and responsibilities
    - Dependency direction rules
    - asmdef constraints (including noEngineReferences for Domain and Application)
    - Folder placement rules (runtime, tests, content, editor)
    - Testing rules summary derived from the current `Testing and Validation` constraints
    - Logging rule (IMonkeyLogger only)
    - Repository safety rules (no meta deletion, no ProjectSettings edits)
    - Specification governance (see below)
- Must clearly state which assemblies use `"noEngineReferences": true`
- Must include authoritative dependency graph in textual form
- Must include snapshot generation timestamp
- Must include this header:

  # Architecture Context Snapshot
  _Auto-generated from repository rules. Do not edit manually._

- Structure it with clear sections and separators.

This file should be detailed enough to allow architectural discussion outside the repository.

────────────────────────────────
FILE 2: CHAT_CONTEXT_EXPORT.md
────────────────────────────────

Purpose:
Ultra-condensed architecture export for standalone AI chats.

Requirements:
- Maximum ~150 lines.
- Must contain:
    - Unity version
    - DI framework
    - Testing approach
    - Layer order
    - Which assemblies are Unity-free
    - Strict dependency rules
    - Folder structure (runtime + tests only)
    - Critical constraints (no meta deletion, minimal diff, no ProjectSettings edits)
    - Logging rule
    - Specification governance (condensed)
- Must be compact and copy-paste friendly.
- No long prose explanations.
- No repetition of full governance text.
- Designed to be pasted directly into a free-standing AI conversation.

Include this header:

# Architecture Context (Chat Export)

────────────────────────────────
SPECIFICATION GOVERNANCE (REQUIRED SECTION)
────────────────────────────────

Both generated files MUST include a section titled:

## Specification Governance

This section must define:

- All features must live under:
  Assets/Project/Docs/Specifications/<feature>/

- Each feature requires:
  - SPEC.md
  - CONSTRAINTS.md
  - ACCEPTANCE.md

- Acceptance criteria must:
  - Use Given / When / Then format
  - Be testable in Unity (EditMode or PlayMode)
  - Respect Domain/Application purity (no Unity in those layers)
  - Avoid reflection and unsafe MonoBehaviour instantiation
  - Be compatible with existing testing constraints

- Implementation must reference acceptance criteria identifiers.

- Spec ambiguity must block implementation.

For CHAT_CONTEXT_EXPORT.md:
Provide a condensed version of the above in bullet form.

────────────────────────────────
VALIDATION REQUIREMENTS
────────────────────────────────

Before writing the files:

- Ensure Domain and Application are marked as:
  "noEngineReferences": true
- Ensure dependency order matches:
  Domain → Application → AI → Infrastructure / Presentation
  Composition wires everything.
- Ensure logging rule references IMonkeyLogger.
- Ensure the testing summary reflects the current `Testing and Validation` section of `GLOBAL_CONSTRAINTS.md` without turning available frameworks or template conventions into mandatory ceremony.
- Do not add a rule that is missing from current authority.

────────────────────────────────
OUTPUT FORMAT
────────────────────────────────

After completion:
- Output only a checklist of the two updated file paths.
- Do NOT include explanations.
- Do NOT suggest further changes.
