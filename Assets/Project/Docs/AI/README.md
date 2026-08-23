# AI Documentation & Automation

Status: Derived tooling index. This file and the prompts it indexes are not authority.

This folder contains AI meta-files used to automate documentation, governance exports, and architectural consistency across the project.

These files are not runtime code and are not architecture definitions. They are instructions and tooling artifacts used by AI agents to maintain consistency.

For framework authority, see [`SpecOps/SPECOPS_V2.md`](../SpecOps/SPECOPS_V2.md); for the derived lifecycle, see [`SpecOps/WORKFLOW.md`](../SpecOps/WORKFLOW.md).
For structural authority, see [`Architecture/ARCHITECTURE.md`](../Architecture/ARCHITECTURE.md). [`UnityCleanArchitecture.md`](../UnityCleanArchitecture.md) is a subordinate explainer.

---

# Purpose of This Folder

The `/Docs/AI/` folder centralizes:

- AI generation prompts
- Architecture export automation
- Governance tooling instructions
- Standardized meta-prompts used inside the repository

This keeps AI automation separate from:

- `/Docs/Architecture/ARCHITECTURE.md` -> sole structural authority
- `/Docs/Specifications` -> feature specs
- `/Docs/Ide` -> Rider tooling

---

# Files in This Folder

## GENERATE_ARCHITECTURE_CONTEXT_PROMPT.md

**Purpose:**
Master prompt used to generate or update:

- `ARCHITECTURE_CONTEXT_SNAPSHOT.md`
- `CHAT_CONTEXT_EXPORT.md`

This file instructs AI agents to:

- Extract architecture rules from current authority
- Build discussion-ready exports
- Maintain consistency with `AGENTS.md`, current authority, and `.specops/specops.json`
- Avoid inventing new architectural rules

Use this when:
- Updating architecture
- Preparing a portable discussion snapshot
- Exporting constraints for standalone AI chats

---

# Related Files (Outside This Folder)

These files are generated or referenced by the prompts in this folder:

### /Docs/Architecture/
- `ARCHITECTURE.md` -> Authoritative architecture
- `ARCHITECTURE_CONTEXT_SNAPSHOT.md` -> Full export for discussions
- `CHAT_CONTEXT_EXPORT.md` -> Ultra-condensed chat-ready export

### Repo Root
- `AGENTS.md` -> derived operational authority router
- `AI_RULES.md` -> legacy compatibility router; not authority
- `TOOLING_RULES.md` -> retained E9 tooling migration source; not governance authority

---

# Governance Rules

- AI meta-files must not modify runtime code.
- They must derive content from authoritative sources.
- They must not invent new architectural constraints.
- Any changes to prompts should be reviewed via PR.

---

# Philosophy

`Architecture/ARCHITECTURE.md` is the sole structural authority within the four-domain authority model.
AI prompts are automation around that truth.

This folder ensures:

- Repeatable architecture exports
- Safe AI usage
- Clear separation between design and tooling
- Stable long-term governance for AI-assisted development
