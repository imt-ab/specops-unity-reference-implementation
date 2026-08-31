# Start a New Unity Project with SpecOps AI

This guide shows the shortest supported path from the published SpecOps AI
Golden Baseline to a new Unity game project.

You do not need to clone the reference repository or reuse its Git history.

The intended flow is:

Latest Golden Baseline
-> download release source
-> extract source
-> run SpecOps Bootstrap
-> open the generated Unity project
-> start development

## Guide Applicability

This installation guide has been reviewed for:

- **SpecOps AI Golden Baseline:** v2.0.1
- **Unity Editor:** 6000.5.8f1
- **Platform:** 64-bit Windows
- **Bootstrap runtime:** PowerShell 7 or later

The installation workflow is intended to remain stable across compatible
Golden Baseline releases, but package versions, Unity versions, known issues,
and Bootstrap requirements may change.

If the latest published Golden Baseline is newer than v2.0.1, review that
release's notes and current known issues before using version-specific values
from this guide.

## Table of Contents

- [Prerequisites](#1-prerequisites)
- [Download the Latest Golden Baseline](#2-download-the-latest-golden-baseline)
- [Extract the Release Source](#3-extract-the-release-source)
- [Install the Required Unity Version](#4-install-the-required-unity-version)
- [Choose Your Project Identity](#5-choose-your-project-identity)
- [Run SpecOps Bootstrap](#6-run-specops-bootstrap)
- [Verify Bootstrap](#7-verify-bootstrap)
- [Open the Generated Project](#8-open-the-generated-project)
- [First-Open Check](#9-first-open-check)
- [Known First-Open Behaviors](#10-known-first-open-behaviors)
- [Set Up Your Own Version Control](#11-set-up-your-own-version-control)
- [Understand the Authority Before Developing](#12-understand-the-authority-before-developing)
- [Start Your First Feature](#13-start-your-first-feature)
- [What Bootstrap Does Not Mean](#14-what-bootstrap-does-not-mean)
- [Troubleshooting](#troubleshooting)
- [Further Reading](#further-reading)

## 1. Prerequisites

Before starting, you need:

- Windows 11 or another supported 64-bit Windows environment.
- 64-bit PowerShell 7 or later (`pwsh`).
- Unity Hub.
- The exact Unity Editor version required by the Golden Baseline release.
- Enough local disk space for a normal Unity project and its generated
  `Library/` directory.

JetBrains Rider is the default IDE used by this reference implementation,
but Rider is not a requirement of the SpecOps framework itself.

Git is not required by SpecOps Bootstrap. You may initialize your own
version-control repository after Bootstrap according to your project needs.

## 2. Download the Latest Golden Baseline

Open the:

[Latest published GitHub Release](https://github.com/imt-ab/specops-unity-reference-implementation/releases/latest)

Use a published release for a new stable project.

Do not use the current `main` branch as a substitute for the latest release
unless you intentionally want development state rather than the published
Golden Baseline.

On the release page, download:

**Source code (zip)**

Do NOT use a file named similar to:

```text
specops-vX.Y.Z-release-evidence.zip
```

as the installation source.

The release-evidence archive contains release evidence. It is not the
Golden Baseline source used to create your Unity project.

## 3. Extract the Release Source

Extract the Source code ZIP to a temporary or tools location, for example:

```text
C:\Temp\SpecOpsGoldenBaseline
```

Do not use this extracted directory as your new game project.

Do not edit or re-save files in the extracted source before running Bootstrap.
Bootstrap verifies the source against the release's governed source identity.

Your new game will be created at a separate destination path.

Example:

```text
Source:
C:\Temp\SpecOpsGoldenBaseline

New project:
C:\UnityProjects\MyGame
```

## 4. Install the Required Unity Version

In the extracted release source, inspect:

```text
ProjectSettings\ProjectVersion.txt
```

Install the exact editor version recorded there through Unity Hub.

For the current v2.0.1 Golden Baseline this is:

```text
Unity 6000.5.8f1
```

Using another Unity version may trigger an upgrade or other changes that are
outside the validated release baseline.

You do not need to create an empty Unity project manually.

SpecOps Bootstrap creates the new project.

## 5. Choose Your Project Identity

Bootstrap requires exactly six explicit values.

| Input | Purpose | Example |
| --- | --- | --- |
| `DestinationPath` | New Unity project directory | `C:\UnityProjects\MyGame` |
| `ProjectId` | Portable SpecOps project identifier | `my-game` |
| `ProductName` | Unity product/display name | `My Game` |
| `CompanyName` | Company or studio name | `Example Studio AB` |
| `ApplicationIdentifier` | Reverse-domain application identifier | `com.examplestudio.mygame` |
| `CodeNamespaceRoot` | Root C# namespace | `ExampleStudio.MyGame` |

### Important input rules

`DestinationPath`:

- must be an absolute Windows path;
- must point to a fresh destination;
- should not already contain another project.

`ProjectId` must use lowercase letters, digits, and optional internal hyphens.

Example:

```text
my-game
```

`ApplicationIdentifier` must use lowercase dot-separated segments.

Example:

```text
com.examplestudio.mygame
```

`CodeNamespaceRoot` must use valid SpecOps namespace segments beginning with
uppercase letters.

Example:

```text
ExampleStudio.MyGame
```

Bootstrap validates these values and fails rather than silently correcting an
invalid value.

## 6. Run SpecOps Bootstrap

Open PowerShell 7.

Change directory to the root of the extracted Golden Baseline source.

For example:

```powershell
Set-Location "C:\Temp\SpecOpsGoldenBaseline"
```

Then run Bootstrap:

```powershell
& pwsh `
    -NoLogo `
    -NoProfile `
    -File ".\tools\specops\bootstrap\Invoke-SpecOpsBootstrap.ps1" `
    -DestinationPath "C:\UnityProjects\MyGame" `
    -ProjectId "my-game" `
    -ProductName "My Game" `
    -CompanyName "Example Studio AB" `
    -ApplicationIdentifier "com.examplestudio.mygame" `
    -CodeNamespaceRoot "ExampleStudio.MyGame"
```

Replace the example values with your own project identity.

Do not remove any of the six parameters.

## 7. Verify Bootstrap

Bootstrap should complete successfully with exit code `0`.

Immediately after the command you can check:

```powershell
$LASTEXITCODE
```

Expected:

```text
0
```

The requested destination should now exist:

```text
C:\UnityProjects\MyGame
```

If Bootstrap reports a failure, do not manually copy missing files or partially
repair the destination.

Read the reported failure, correct the input or environment problem, and retry
using a fresh destination.

Bootstrap is designed to fail closed rather than publish a partially verified
project.

## 8. Open the Generated Project

Open Unity Hub.

Add/open:

```text
C:\UnityProjects\MyGame
```

Do NOT open the extracted Golden Baseline source as your game project.

Open the generated project using the exact Unity version recorded in its:

```text
ProjectSettings\ProjectVersion.txt
```

Allow Unity to complete:

- initial asset import;
- package resolution;
- script compilation;
- initial domain reload.

The first import can take significantly longer than later project opens.

## 9. First-Open Check

After Unity has finished importing, check the Console.

Look specifically for:

- red compile errors;
- missing scripts;
- package-resolution failures;
- import failures.

Warnings are not automatically defects. Evaluate them according to their
actual functional impact.

Do not modify `Packages/*` or `ProjectSettings/*` merely to remove a warning
without first understanding its cause.

## 10. Known First-Open Behaviors

The current Golden Baseline has documented non-blocking known issues.

### AI Inference analytics define

On first Unity open, the AI Inference package can add:

```text
SENTIS_ANALYTICS_ENABLED
```

to the tracked scripting defines in:

```text
ProjectSettings/ProjectSettings.asset
```

This is a known non-blocking issue rather than evidence that Bootstrap failed.

See:

[KI-001](https://github.com/imt-ab/specops-unity-reference-implementation/issues/1)

### Unity Version Control panel

Opening the Unity Version Control panel can cause Unity's Version Control
package to change:

```text
ProjectSettings/VersionControlSettings.asset
```

to use the Unity Version Control provider.

Plain project opening does not require this panel.

If your project uses Git or another VCS, do not open or configure the Unity
Version Control panel unless that is intentional.

See:

[KI-002](https://github.com/imt-ab/specops-unity-reference-implementation/issues/2)

Check the repository's current open issues for newer known limitations when
using a later Golden Baseline release.

## 11. Set Up Your Own Version Control

Bootstrap creates project content. It does not give your new project the
reference repository's release history or release authority.

Choose and initialize the version-control system appropriate for your project.

If you use Git, it is useful to record the freshly generated Bootstrap state
before beginning feature development so later project changes remain easy to
review.

SpecOps framework semantics themselves are VCS-neutral.

## 12. Understand the Authority Before Developing

Before implementing your first feature, read these files in the generated
project:

```text
Assets/Project/Docs/SpecOps/SPECOPS_V2.md
Assets/Project/Docs/Architecture/ARCHITECTURE.md
Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md
Assets/Project/Docs/SpecOps/WORKFLOW.md
```

Their roles are different:

1. `SPECOPS_V2.md`
   defines SpecOps framework semantics.

2. `ARCHITECTURE.md`
   is the structural authority for the Unity project.

3. `GLOBAL_CONSTRAINTS.md`
   defines repository-wide engineering constraints.

4. `WORKFLOW.md`
   provides derived operational guidance for applying the framework.

For a feature, authority normally continues under:

```text
Assets/Project/Docs/Specifications/<feature>/
```

with:

```text
SPEC.md
CONSTRAINTS.md
ACCEPTANCE.md
```

## 13. Start Your First Feature

A typical SpecOps development flow is:

```text
DISCOVER
-> AUDIT
-> SPECIFY
-> PLAN
-> HUMAN AUTHORITY
-> IMPLEMENT
-> VALIDATE
-> REVIEW
-> RELEASE / SYNC
```

Do not start by asking an AI coding agent to implement an undefined feature.

Start by establishing:

- feature intent;
- constraints;
- acceptance criteria;
- architectural placement.

Then use the appropriate SpecOps responsibility for the bounded task.

## 14. What Bootstrap Does Not Mean

A successful Bootstrap proves that the governed Golden Baseline was
successfully projected into a new project according to the Bootstrap contract.

It does not mean:

- your future game features are approved;
- every future Unity version is automatically supported;
- every package upgrade is safe;
- all future tests automatically pass;
- the generated project inherits release evidence from the public reference
  repository.

Your generated project becomes its own engineering lifecycle after Bootstrap.

## Troubleshooting

### `pwsh` is not found

Install or enable 64-bit PowerShell 7 or later.

Windows PowerShell 5.1 is not the supported Bootstrap runtime.

### Bootstrap rejects `DestinationPath`

Use a canonical absolute Windows path to a fresh project destination.

Example:

```text
C:\UnityProjects\MyGame
```

Do not use a relative path.

### Bootstrap rejects `ProjectId`

Use a lowercase identifier such as:

```text
my-game
```

### Bootstrap rejects `ApplicationIdentifier`

Use at least three lowercase dot-separated segments.

Example:

```text
com.examplestudio.mygame
```

### Bootstrap rejects `CodeNamespaceRoot`

Use namespace segments beginning with uppercase letters.

Example:

```text
ExampleStudio.MyGame
```

### Unity asks to upgrade the project

Verify that you opened the generated project with the exact editor version
specified in:

```text
ProjectSettings\ProjectVersion.txt
```

Do not accept an upgrade if your goal is to reproduce the released Golden
Baseline.

### Documentation inside an older release mentions publication as pending

Release source is an immutable historical snapshot.

Some derived documentation may describe lifecycle actions that had not yet
occurred when that release container was frozen.

Use the actual GitHub Release and annotated tag as the publication record.
Do not modify the frozen release to rewrite that history.

## Further Reading

After installation, start with:

- `README.md`
- `Assets/Project/Docs/SpecOps/ONBOARDING.md`
- `Assets/Project/Docs/SpecOps/SPECOPS_V2.md`
- `Assets/Project/Docs/SpecOps/WORKFLOW.md`
- `Assets/Project/Docs/Architecture/ARCHITECTURE.md`
- `Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md`

For Bootstrap's normative behavior, see:

```text
.specops/contracts/bootstrap-v1.md
```

For current defects and limitations, see the repository's open GitHub issues.
