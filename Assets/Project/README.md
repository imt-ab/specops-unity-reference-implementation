# Project Structure Overview


This project uses a structured and scalable folder layout to clearly separate:

* Visual and audio assets
* Runtime gameplay content
* Source code
* Rendering configuration
* Documentation
* Editor tooling

The goal is clarity, consistency, and predictable asset placement as the project grows.

Scope: The structure defined in this document refers to the Assets/Project subtree. To maintain a clean workspace, all production assets and code are contained here. Standard Unity folders or project-wide configurations that must reside directly under Assets (such as Assets/Plugins or Assets/ScriptTemplates) are documented separately in the "Other Project-Level Folders" section.

---

# Top-Level Structure

```
Art/        → Visual assets (models, materials, textures, shaders)
Audio/      → Music and sound effects
Content/    → Runtime gameplay assets and configuration
Code/       → All C# source code
Docs/       → Documentation
Editor/     → Editor-only tooling
```

---

# Other Project-Level Folders

These folders live directly under `Assets` and are outside `Assets/Project`:

`Assets/Scenes` → Unity’s default scenes folder (currently contains `SampleScene`). Prefer placing production scenes in `Assets/Project/Content/Scenes`.

`Assets/Plugins` → Third‑party/native plugins when used.

`Assets/ScriptTemplates` → Custom C# script templates used to enforce consistent file and class creation patterns.
---


# Art

`Assets/Project/Art`

Visual assets used by the project.

* **Materials** → Unity Material assets
* **Models** → Meshes, FBX files, rigged characters, environment models
* **Textures** → Texture maps (albedo, normal, masks, UI textures)
* **Shaders** → Shader Graphs, HLSL shaders, includes, subgraphs

---

# Audio

`Assets/Project/Audio`

* **Music** → Background music and ambient tracks
* **SFX** → Sound effects (UI, gameplay, loops, one-shots)

---

# Content (Runtime Assets)

`Assets/Project/Content`

Contains all runtime assets loaded or used by the game.

* **Scenes** → Unity scenes (bootstrap, gameplay, test scenes)
* **Prefabs** → Gameplay prefabs and entities
* **UI** → UI prefabs and layout assets (visual assets only)
* **Animations** → Animation clips and controllers
* **Input** → Input System action assets
* **Addressables** → Addressable-managed assets and groups

---

# Settings

`Assets/Project/Content/Settings`

Runtime configuration assets.

## Rendering

`Assets/Project/Content/Settings/Rendering`

Contains all URP-related configuration.

### Global

* **UniversalRenderPipelineGlobalSettings**
  Global URP configuration referenced by Project Settings.

### Pipeline

* **PC_RPAsset**
* **Mobile_RPAsset**
  URP Pipeline assets referenced by Graphics and Quality settings.

### Renderers

* **PC_Renderer**
* **Mobile_Renderer**
* Renderer Features (e.g., Screen Space Ambient Occlusion)
  Renderer data assets used by pipeline assets.

### Volumes

* **DefaultVolumeProfile**
* Scene-specific volume profiles
  Post-processing and lighting profiles referenced by Volume components.

---

## Lighting

`Assets/Project/Content/Settings/Lighting`

* Lighting settings assets
* Baked lighting configurations
* Reflection probe settings

---

## Quality

`Assets/Project/Content/Settings/Quality`

* Quality level configuration assets
* Platform-specific overrides

---

# Code

`Assets/Project/Code`

All C# source code and assembly definitions (`.asmdef`). Each major system is isolated into its own assembly to ensure clean dependency management.

## Runtime

`Assets/Project/Code/Runtime`

Contains gameplay and runtime systems.

* **AI** → AI logic and behavior systems
* **Application** → Use cases and orchestration
* **Composition** → Bootstrapping and dependency wiring
* **Domain** → Core game logic and rules
* **Infrastructure** → External system integrations
* **Presentation** → UI and player-facing logic

    * `UI` → UI logic and controllers
    * `Input` → Input handling logic
    * `Navigation` → Screen flow and state transitions
* **Utility** → Technical helpers and extensions

---

## Tests

`Assets/Project/Code/Tests`

* **EditMode** → Unit tests (fast-running logic tests)
* **PlayMode** → Integration/runtime tests

---

# Documentation

`Assets/Project/Docs`

* **Architecture** → Design documentation and diagrams
* **Specifications** → Feature specifications and gameplay requirements
* **Ide** → Rider Live Templates and other IDE-specific documentation

---

# Editor

`Assets/Project/Editor`

Editor-only tooling:

* Custom inspectors
* Build scripts
* Menu extensions
* Debug utilities

---

# ScriptTemplates (Project‑Level)

`Assets/ScriptTemplates`

Custom C# script templates used to enforce consistent file and class creation patterns.

---

This structure is designed to remain stable as the project scales. New assets and systems should be placed in the most specific existing folder rather than introducing parallel or redundant directories.
