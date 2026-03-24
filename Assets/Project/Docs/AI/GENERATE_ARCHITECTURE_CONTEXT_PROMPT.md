You are operating inside an existing Unity 6000.3 repository using Plastic SCM and Rider.

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

Use these files as authoritative input sources:

- /AI_RULES.md
- /TOOLING_RULES.md
- Assets/Project/Docs/Architecture/ARCHITECTURE.md
- Assets/Project/Docs/Specifications/README.md (for structure overview)

Do NOT invent architectural rules.
If information is missing, infer only from existing documentation.

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
    - Testing rules summary (Moq, VContainer, no reflection, AddComponent, cleanup)
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
- Ensure test constraints include:
    - MOQ
    - VContainer
    - No reflection
    - AddComponent<T>() for MonoBehaviours
    - TearDown cleanup

If any of these are missing in the source documentation,
include them based on authoritative architecture rules already defined.

────────────────────────────────
OUTPUT FORMAT
────────────────────────────────

After completion:
- Output only a checklist of the two updated file paths.
- Do NOT include explanations.
- Do NOT suggest further changes.
