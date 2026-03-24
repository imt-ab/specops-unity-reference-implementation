# Rider Live Templates - AI Enterprise Pack

This folder contains Rider Live Templates designed for AI-assisted development with Clean Architecture and VContainer.

------------------------------------------------------------------------

## Template Systems

This project uses two template systems in Rider:

1.  **IntelliJ Live Templates (`.xml`)**
    -   Used for AI prompt templates (Claude, Codex, Junie).
    -   Installed to: `%APPDATA%\JetBrains\Rider<version>\templates`
    -   These appear under **Other Languages** in Rider.
2.  **ReSharper / Rider C# Live Templates (`.DotSettings`)**
    -   Used for C# scaffolding (EditMode/PlayMode tests, VContainer, Moq, etc.).
    -   Installed as a **team-shared settings layer**: `<SolutionName>.sln.DotSettings`
    -   These appear under **Editor → Live Templates → C#**.

------------------------------------------------------------------------

## Quick Start

### 1. Install Templates

right-click on [install-rider-live-templates.ps1](install-rider-live-templates.ps1) → Run with PowerShell and then restart Rider to load the new templates


After importing, you'll see a template group called **AI**.

------------------------------------------------------------------------

## How to Use

1. Type the template abbreviation (e.g., `codex`)
2. Press **Tab**
3. Template expands with variables
4. Use **Tab** to navigate between `$VARIABLES$`
5. Cursor lands at `$END$` when complete

------------------------------------------------------------------------

## Quick Reference

### AI Workflow Templates
| Abbreviation | Purpose |
|--------------|---------|
| `codex` | Implementation task prompt |
| `junie` | Architecture / feasibility check |
| `claudespec` | Spec authoring / review |
| `claudeac` | Acceptance criteria generation |
| `codexspec` | Spec implementability validation |

### Specification Templates
| Abbreviation | Purpose |
|--------------|---------|
| `specdraft` | Start a new feature specification |
| `acceptance` | Write Given / When / Then blocks |

### EditMode Test Templates
| Abbreviation | Purpose |
|--------------|---------|
| `edittest` | VContainer + Moq test class scaffold |
| `mbtest` | MonoBehaviour test scaffold |
| `moqbind` | Moq setup + VContainer binding snippet |
| `ivt` | InternalsVisibleTo assembly snippet |

### PlayMode Test Templates
| Abbreviation | Purpose |
|--------------|---------|
| `pmtest` | VContainer integration PlayMode test |
| `pmmbtest` | MonoBehaviour PlayMode test scaffold |
| `unitytest` | UnityTest coroutine snippet |

------------------------------------------------------------------------

## Detailed Workflow Guides

### [AI_WORKFLOW_TEAM.md](../AI_WORKFLOW_TEAM.md)
Complete daily development workflow guide covering:
- Daily feature development workflow
- Context-specific template usage
- Best practices and golden rules
- AI agent coordination
- EditMode and PlayMode test workflows
- AI fill-in prompts and operational discipline

------------------------------------------------------------------------

## Troubleshooting

**Template not expanding?**
- Confirm "AI" template group exists in Settings
- Verify you're in a supported file type (C# or Markdown)
- Restart Rider
- Re-import the XML file
- Check XML root element: `<templateSet group="AI">`

------------------------------------------------------------------------

## Team-Shared Settings (`.sln.DotSettings`)

### Why We Use `<Solution>.sln.DotSettings`

Rider (via ReSharper) supports *settings layers*. When a file named `YourSolution.sln.DotSettings` exists next to the `.sln` file, Rider automatically loads it as a **Team-Shared Settings Layer**.

This means:
-   All developers get identical C# Live Templates.
-   No manual importing is required.
-   Templates are version-controlled.
-   Template changes are reviewable via PR.

This is the recommended JetBrains way to share C# templates across a team.

### Should the `.sln.DotSettings` File Be Committed?

**Yes** — commit it.

Reasons:
-   Ensures consistent scaffolding across the team.
-   Prevents template drift.
-   Makes template updates reviewable.
-   Aligns with Clean Architecture + testing governance.
-   Keeps AI-assisted workflows deterministic.

It should live in the repository root next to the `.sln` file.

### What Should NOT Be Committed

Do NOT commit:
-   Personal Rider settings (`.DotSettings.user`)
-   `%APPDATA%` template folders
-   Per-user environment configuration

Only commit: `<Solution>.sln.DotSettings`

### Updating Templates

If templates are updated:
1.  Modify the source template file in `/Docs/ide/`
2.  Re-run the install script
3.  Commit the updated `.sln.DotSettings`
4.  Open a PR

All developers will receive the updated templates after pulling and restarting Rider.

------------------------------------------------------------------------

## Template Comparison Summary

| Template Type        | Storage     | Version Controlled | Used For            |
|----------------------|-------------|--------------------|---------------------|
| IntelliJ XML         | AppData     | No                 | AI prompts          |
| `.sln.DotSettings`   | Repo root   | Yes                | C# test scaffolds   |

This separation ensures:
-   Prompts work in AI Chat.
-   C# scaffolds work in `.cs` files.
-   The team shares identical C# template behavior.

------------------------------------------------------------------------

## Files in This Directory

- `RiderLiveTemplates-Enterprise.xml` - IntelliJ template definitions (AI prompts)
- `RiderLiveTemplates-CSharpTests.DotSettings` - C# test scaffold templates
- `install-rider-live-templates.ps1` - Automated installer
