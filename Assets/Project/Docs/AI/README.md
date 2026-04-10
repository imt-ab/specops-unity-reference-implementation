# AI Documentation & Automation

This folder contains AI meta-files used to automate documentation, governance exports, and architectural consistency across the project.

These files are not runtime code and are not architecture definitions. They are instructions and tooling artifacts used by AI agents to maintain consistency.

For the operating model, see [`SpecOpsAI.md`](../SpecOpsAI.md).
For structural rules, see [`UnityCleanArchitecture.md`](../UnityCleanArchitecture.md).

---

# Purpose of This Folder

The `/Docs/AI/` folder centralizes:

- AI generation prompts
- Architecture export automation
- Governance tooling instructions
- Standardized meta-prompts used inside the repository

This keeps AI automation separate from:

- `/Docs/Architecture` -> authoritative system design
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

- Extract architecture rules from authoritative documents
- Build discussion-ready exports
- Maintain consistency with `AI_RULES.md` and `ARCHITECTURE.md`
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
- `AI_RULES.md` -> AI enforcement rules
- `TOOLING_RULES.md` -> Tooling constraints

---

# Governance Rules

- AI meta-files must not modify runtime code.
- They must derive content from authoritative sources.
- They must not invent new architectural constraints.
- Any changes to prompts should be reviewed via PR.

---

# Philosophy

Architecture is the source of truth.
AI prompts are automation around that truth.

This folder ensures:

- Repeatable architecture exports
- Safe AI usage
- Clear separation between design and tooling
- Stable long-term governance for AI-assisted development
