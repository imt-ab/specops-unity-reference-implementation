# TOOLING_RULES.md

> **Status — E9 tooling migration source; NOT SpecOps or repository governance authority.**
>
> This file is retained temporarily for concrete PowerShell, UTF-8/encoding, command-safety, and related tooling information needed by E9. Normative governance comes only from the current authority domains routed through [`AGENTS.md`](AGENTS.md). `AGENTS.md` is a derived operational router. [`.specops/specops.json`](.specops/specops.json) and [`.specops/permissions.json`](.specops/permissions.json) provide instance and permission configuration; they do not define independent authority. Any conflicting legacy VCS, role, product, permission, or authority statement below is superseded and must not be treated as operative policy.

## Allowed Actions

-   Add runtime code under `Assets/Project/Code/Runtime/<Layer>/`
-   Add editor-only code under `Assets/Project/Editor/`
-   Add EditMode and PlayMode tests under `Assets/Project/Code/Tests/`
-   Add new files required by specifications
-   Execute Unity batchmode tests (non-destructive)

------------------------------------------------------------------------

## Prohibited Actions

-   Do NOT modify `ProjectSettings/*`
-   Do NOT modify `Packages/*`
-   Do NOT delete or regenerate `.meta` files
-   Do NOT perform large structural refactors unless explicitly
    requested
-   Do NOT introduce new dependencies unless explicitly requested

------------------------------------------------------------------------

## Formatting Rules

-   Only format or modify files that are directly touched
-   Do NOT reformat unrelated files
-   Keep diffs minimal and focused

------------------------------------------------------------------------

## CLI / Environment Constraints (E9 Migration Source)

### Environment

-   Windows 11
-   Rider IDE
-   GitHub
-   Git

### Version Control

-   This repository uses Git and is hosted on GitHub
-   Use `git` commands when needed for normal repository inspection and commits
-   Avoid destructive `git` commands unless explicitly requested
-   Do not assume GitHub CLI is installed unless the task requires it

### Shell Tools

-   Do NOT assume `rg`, `grep`, `sed`, `awk`, `bash`, or other Unix
    utilities exist
-   Do NOT assume a Unix-like shell environment
-   Assume PowerShell environment only

### Text Encoding (E9 Migration Source)

- Do NOT assume Windows PowerShell 5.1 default encoding is UTF-8.
- Treat all repository text files as UTF-8.
- When reading or searching text files in PowerShell, always force UTF-8 explicitly.

Required command patterns:

- Read file:
    - Get-Content -Encoding utf8 -Path "<path>"

- Search file:
    - Select-String -Encoding utf8 -Path "<path>" -Pattern "<pattern>"

If using .NET APIs in PowerShell:

- Prefer:
    - [System.IO.File]::ReadAllText("<path>", [System.Text.Encoding]::UTF8)

Preferred shell:

- Use PowerShell 7+ (pwsh) if available, as UTF-8 defaults are safer than Windows PowerShell 5.1.

### Repository Inspection

-   Prefer scoped, user-provided context over broad inspection.
-   If repository inspection is required, request one of the following
    (in order of preference):
    -   Semantic anchors: target layer/assembly (asmdef) and root
        namespace, plus relevant type names (classes/interfaces) if
        known.
    -   A small folder tree (2--4 levels) rooted at the relevant area.
    -   File contents for the relevant files.
-   Request exact file paths only when required to avoid writing to the
    wrong location (e.g., creating new files, or multiple plausible
    target files exist).
-   Do NOT attempt to infer repository state using shell commands.
-   Prefer static reasoning over command execution.

------------------------------------------------------------------------

## CLI Safety Policy

### Allowed

-   Unity batchmode test execution
-   Non-destructive PowerShell commands when explicitly required
-   Non-destructive `git` commands when explicitly required

### Forbidden

-   Destructive commands (e.g., deleting folders, force resets, mass
    file removal)
-   Destructive `git` commands unless explicitly requested
-   Unix-only tooling
-   Repository state mutation via CLI
