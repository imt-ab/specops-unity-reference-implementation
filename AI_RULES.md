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

## Encoding Invariant

- Treat all repository text as UTF-8.
- When reading or searching files via PowerShell, follow TOOLING_RULES.md "Text Encoding (Authoritative)" exactly.
- Do NOT rely on default Windows PowerShell encoding.
- 
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
    - VContainer lifetime scopes only.
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

### Unity Constraints
- Respect Unity lifecycle methods.
- Avoid per-frame allocations in Update/LateUpdate/FixedUpdate.
- Avoid LINQ and closures in hot paths.
- Prefer [SerializeField] over runtime lookups.
- Avoid Find() and scene-wide searches.

### Logging
- Use IMonkeyLogger (interface in InfiniteMonkey.Utility.Interfaces) exclusively for logging.
- Do not introduce UnityEngine.Debug calls.

### Testing (Unity EditMode – Authoritative)
- Use MOQ for mocking.
- Use VContainer for dependency injection.
- Do NOT use reflection.
- Use internal + InternalsVisibleTo for test access.
- MonoBehaviours must be created with GameObject.AddComponent<T>().
- Destroy created GameObjects in TearDown.
- Add XML documentation comments to test classes and methods.
- Test files should be named <TargetClass>Tests.cs and follow the same folder hierarchy as the code they test under Assets/Project/Code/Tests/EditMode or PlayMode.

### Formatting And Naming (Authoritative: .editorconfig)
- Always follow `.editorconfig` for any file you create or modify.
- Use `utf-8` charset.
- Use `LF` line endings.
- Trim trailing whitespace.
- Keep diffs minimal: do not reformat unrelated files.

#### Indentation By File Type
- Default: spaces, 4-space indent.
- `*.asmdef`, `*.asmref`, `*.json`, `*.jsonc`, `*.yaml`, `*.yml`: spaces, 2-space indent.
- `*.cs`: spaces, 4-space indent.

#### C# Style
- Keep opening braces on new line for methods/types/properties/control blocks.
- Prefer `var` when type is apparent or elsewhere.
- Do not prefer `var` for built-in types (`int`, `string`, etc.).
- Respect configured qualification preferences (`this.` usage) from `.editorconfig`.
- Preserve existing formatting/layout unless directly touching that code block.

#### Unity Naming
- Unity serialized field names must be `lowerCamelCase` (no leading underscore).
- Keep type names (`class`, `struct`, `interface`) in `PascalCase`.
- Keep method/property names in `PascalCase`.
