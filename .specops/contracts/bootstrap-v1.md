# Bootstrap v1 Normative Contract

## Status and Authority Boundary

This document is the normative contract for Bootstrap v1 behavior. It is subordinate to the current structural authority in `Assets/Project/Docs/Architecture/ARCHITECTURE.md`, the framework authority in `Assets/Project/Docs/SpecOps/SPECOPS_V2.md`, the repository-wide authority in `Assets/Project/Docs/Governance/GLOBAL_CONSTRAINTS.md`, and applicable current feature authority. A conflict with higher authority stops bootstrap work; this contract does not reinterpret or amend that authority.

This contract constrains the observable behavior and invariants of later Bootstrap v1 schemas, manifests, implementation, transforms, verification, and validation. It is not structural or framework authority, feature authority, evidence, a release result, Human Authority approval evidence, or proof that Unity can open, resolve, compile, or test an output project. It does not authorize implementation, publication, release, or any other mutation.

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHOULD**, and **MAY** in this contract are to be interpreted as described by BCP 14 when they appear in all capitals.

The Bootstrap v1 contract version is `1.0.0`. A behaviorally incompatible change requires a new contract version.

## Terminology

- **Golden Baseline**: the reusable, governed Unity project content selected from the public reference repository for deterministic projection. It excludes repository-instance identity and history unless explicitly retained by the Projection Manifest.
- **Bootstrap Source**: one immutable, verified source snapshot containing the Golden Baseline authored files and the manifest-bound metadata needed for one invocation.
- **Source Authority**: the governed authority that approves which source content and projection rules constitute a Bootstrap Source. Authority is permission and meaning, not a path or digest.
- **Source Locator**: an execution-time means of locating source bytes, such as a filesystem path or a future wrapper-resolved checkout. A locator is not source authority or identity and MUST NOT enter canonical output.
- **Source Identity**: the deterministic identity of the verified, manifest-bound Golden Baseline source. It identifies content, not its locator. A Git revision MAY be supplemental provenance only when later approved; Git revision is not a universal Bootstrap Core identity requirement.
- **Projection Manifest**: the later, governed F3 artifact that binds the Authored Source Inventory and each path's single disposition, expected exact-byte identities, scoped transforms, every explicit Generated Output Inventory declaration, and required output expectations.
- **Authored Source Inventory**: the manifest-bound complete set of regular authored source files eligible for disposition. It excludes untracked, generated, transient, link, and other unsupported entries.
- **Generated Output**: one source-less output file produced only by an explicit `GENERATE_DETERMINISTIC` declaration from approved semantic inputs.
- **Generated Output Inventory**: the manifest-bound complete set of explicit `GENERATE_DETERMINISTIC` declarations and their expected output paths, representations, and verification requirements.
- **Content Input**: one of the five explicitly supplied values that may deterministically affect generated tracked content: `ProjectId`, `ProductName`, `CompanyName`, `ApplicationIdentifier`, or `CodeNamespaceRoot`.
- **Execution Input**: `DestinationPath`, which controls only where an invocation stages and publishes. It is not content identity or retained provenance.
- **Projection**: deterministic construction of the Output Inventory from projected Authored Source Inventory outputs plus the Generated Output Inventory, using one verified Bootstrap Source, its Projection Manifest, and approved semantic inputs.
- **Scoped Transform**: a manifest-declared replacement at an exact selector or parser-located byte span with declared preconditions and postconditions. It is not repository-wide search-and-replace authority.
- **Copied File**: an authored file with disposition `COPY_EXACT`, whose output bytes exactly equal its source bytes.
- **Excluded File**: an authored file with disposition `EXCLUDE`, which has no output path or bytes.
- **Output Inventory**: the complete, deterministic, collision-checked union of emitted `COPY_EXACT` outputs, emitted `TRANSFORM_SCOPED` outputs, and all `GENERATE_DETERMINISTIC` outputs expected after projection and before publication. `EXCLUDE` emits nothing.
- **Bootstrap Provenance**: the later `.specops/bootstrap.json` derived construction-lineage record. It is non-authoritative, non-evidence, and not lifecycle or release state.
- **Staging Destination**: an invocation-owned, non-output sibling path used to construct and verify a candidate project before publication.
- **Published Destination**: the requested, previously nonexistent `DestinationPath` after successful staged publication and post-publication verification.
- **Unity feature template**: reusable feature scaffolding under the canonical specifications template location. This is distinct from the Golden Baseline and Bootstrap Source.

## Required Invocation Inputs

Bootstrap v1 has exactly six required invocation inputs:

1. `DestinationPath` — Execution Input.
2. `ProjectId` — Content Input.
3. `ProductName` — Content Input.
4. `CompanyName` — Content Input.
5. `ApplicationIdentifier` — Content Input.
6. `CodeNamespaceRoot` — Content Input.

Every input MUST be explicitly supplied. No input may be defaulted, inferred from another input, or obtained from the destination or current directory, Git configuration, repository name, machine or user identity, environment variables, clock, random values, or ambient process state. An input that is not already canonical MUST be rejected; it MUST NOT be silently trimmed, normalized, case-folded, rewritten, or otherwise repaired.

### Common String Rules

All six values MUST be non-null and non-empty. They MUST contain valid Unicode scalar values, MUST contain no unpaired surrogate, and MUST contain no C0 or C1 control character (`U+0000` through `U+001F` or `U+007F` through `U+009F`). Leading or trailing Unicode whitespace is prohibited. Comparisons and grammar checks MUST be ordinal and locale-independent.

Except where a grammar below fixes case, case is preserved and significant. No hashing or substitution step performs hidden locale or case conversion.

`ProductName` and `CompanyName` MUST each contain between 1 and 128 Unicode scalar values, inclusive, and MUST already be Unicode Normalization Form C (NFC). Bootstrap validates NFC equality and rejects a non-NFC value rather than normalizing it. These values otherwise remain exact project metadata; they are not path segments and MUST NOT be used to derive another input.

### `ProjectId`

`ProjectId` MUST:

- contain 1 through 63 ASCII characters;
- match `^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$` exactly;
- contain lowercase ASCII only where letters occur; and
- contain no empty hyphen-delimited component.

This intentionally portable Bootstrap v1 subset is stricter than identifiers accepted by some individual tools. Case is fixed by the grammar, not normalized. `ProjectId` is instance identity and MUST NOT be derived from any other input or context.

### `ApplicationIdentifier`

`ApplicationIdentifier` MUST:

- contain 5 through 255 ASCII characters;
- consist of at least three dot-separated segments;
- have every segment match `^[a-z][a-z0-9]*$`; and
- therefore match `^[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*){2,}$` in full.

The lowercase, reverse-domain-style grammar is an intentionally conservative portable subset. Case is fixed by the grammar and MUST NOT be normalized. No segment may be empty, begin with a digit, or contain a hyphen, underscore, whitespace, or non-ASCII character.

### `CodeNamespaceRoot`

`CodeNamespaceRoot` MUST:

- contain 1 through 255 ASCII characters;
- consist of dot-separated C# namespace segments;
- have each segment contain 1 through 64 characters and match `^[A-Z][A-Za-z0-9]*$`; and
- therefore match `^[A-Z][A-Za-z0-9]*(?:\.[A-Z][A-Za-z0-9]*)*$` in full.

This intentionally conservative subset avoids C# keyword, escaping, Unicode-identifier, and portable filename ambiguity. Case is preserved and significant for code identity. F3 path projection and F6 verification MUST additionally prove that every path derived from this input is unique under ordinal, case-insensitive Windows comparison and does not collide with any other output path, file/directory prefix, or reserved Windows device name. A collision MUST fail before publication.

### `DestinationPath`

`DestinationPath` MUST be a fully qualified absolute Windows path in canonical lexical form. Bootstrap v1 MUST reject:

- a relative or drive-relative path;
- a filesystem root;
- `/` as a separator, `.` or `..` segments, empty segments other than the UNC prefix, or a trailing separator;
- device namespace forms such as `\\?\` or `\\.\`;
- a segment containing a Windows-invalid filename character, ending in a space or period, or matching a reserved Windows device name under ordinal case-insensitive comparison; and
- a path that cannot be represented or inspected by the supported PowerShell 7 and Windows filesystem primitives.

Drive-qualified paths MUST use an uppercase ASCII drive letter followed by `:\`. UNC paths MUST contain a non-empty server, share, and leaf path. Canonical-form validation MUST reject an alternative spelling rather than silently rewriting it.

`DestinationPath` MUST satisfy the destination-safety rules below. It is execution-only: its value, spelling, parent path, and resolved filesystem path MUST NOT enter generated tracked bytes, the Output Inventory, Bootstrap Provenance, or deterministic content identity.

## Bootstrap Source Contract

A logical Bootstrap Source is valid only when:

- its Source Authority and contract version are declared;
- its Source Identity is verified using the later approved F3 definition;
- its Projection Manifest is valid and binds one complete Authored Source Inventory and one complete Generated Output Inventory;
- every inventory path is a normalized repository-relative `/`-separated path with no absolute, empty, `.`, or `..` segment;
- every authored entry is a supported regular file and has an ordinary exact-byte SHA-256 identity;
- no authored entry is a symbolic link, gitlink, reparse entry, unsupported special entry, or transient/generated Unity entry;
- the actual authored source exactly matches the manifest-bound inventory and byte identities; and
- every authored path has exactly one valid source disposition; and
- every source-less output has exactly one explicit valid generated-output declaration.

F3 MUST establish the exact inventory and final Golden Baseline Source Identity. It MUST keep Source Authority, Source Locator, and Source Identity separate. The F1/F2 checkpoint Git revision is not the final reusable source identity.

The source content used by one invocation MUST remain immutable from verification through completion. Any missing, unexpected, changed, ambiguous, duplicate, case-equivalent, or unsupported authored entry MUST fail closed. A change detected after initial verification invalidates the invocation. Filesystem enumeration order has no semantic significance; manifest and output processing MUST use an explicitly deterministic ordinal path order wherever order affects calculation or verification.

Git is not required to locate, identify, verify, project, or publish the canonical output. A future wrapper MAY use Git as an external source-location aid only under separate authority.

## Projection Dispositions and Generated Outputs

The Projection Manifest MUST assign every Authored Source Inventory path exactly one of these dispositions. Duplicate, ambiguous, missing, overlapping, or case-equivalent dispositions or output paths MUST fail closed.

The Projection Manifest MUST separately declare every Generated Output Inventory entry as `GENERATE_DETERMINISTIC`. A generated output has no authored source path and MUST NOT be represented using a fake source disposition. The final Output Inventory is the union of all emitted `COPY_EXACT` and `TRANSFORM_SCOPED` outputs with all `GENERATE_DETERMINISTIC` outputs; `EXCLUDE` emits nothing. One complete output namespace and collision check applies across that union.

### `COPY_EXACT`

- **Input precondition:** the source path exists as the expected regular file and its exact-byte SHA-256 equals the manifest value.
- **Output expectation:** exactly one declared output path exists with exactly the source bytes.
- **Preservation:** every byte MUST be identical. Newlines, BOM, encoding, Unicode form, text representation, and metadata content MUST NOT be normalized or reserialized.
- **Failure:** missing, changed, unreadable, multiply mapped, colliding, or unequal output fails the invocation.

### `TRANSFORM_SCOPED`

- **Input precondition:** the source path and exact-byte identity match; every declared selector/parser class is supported; every expected pre-value and exact match count is satisfied.
- **Output expectation:** exactly one declared output path contains only the declared deterministic replacements and satisfies all transform postconditions.
- **Preservation:** the transform MUST identify exact source byte spans, preserve every byte outside those non-overlapping spans, and construct output by concatenating unchanged source byte slices with deterministic replacement bytes. Whole-file text reserialization is nonconforming when it changes any non-selected byte. Verification MUST reproduce the selected span map and prove unchanged-byte equality for all source intervals outside it.
- **Failure:** decoding failure, malformed content, unsupported encoding, overlap, unexpected count or pre-value, residual forbidden identity, path collision, or any undeclared byte difference fails the invocation.

A file is eligible for `TRANSFORM_SCOPED` only when F3/F5 defines encoding-aware, byte-preserving selector behavior. No file is presumed to be text merely because current source files are text-like.

### `EXCLUDE`

- **Input precondition:** the expected source path and exact-byte identity exist in the authored inventory.
- **Output expectation:** no output path or bytes are emitted for that source entry.
- **Preservation:** not applicable; exclusion grants no authority to transform or synthesize a substitute.
- **Failure:** emission of the excluded entry, a renamed copy, a reset/fake substitute, or content reachable through an overlapping rule fails the invocation.

`EXCLUDE` grants no generation authority. `TRANSFORM_SCOPED` grants no generation authority beyond its declared one-source-to-one-output transformation.

### `GENERATE_DETERMINISTIC`

`GENERATE_DETERMINISTIC` maps no authored source file to exactly one explicitly declared deterministic output file. It is a generated-output declaration, not an Authored Source Inventory disposition and not general authority to synthesize arbitrary files.

Every declaration MUST define:

- exact output relative path;
- generator or representation contract;
- exact allowed semantic inputs;
- exact schema or representation requirement where applicable;
- deterministic encoding and byte representation;
- generation count, which MUST be exactly one;
- postconditions;
- collision constraints; and
- verification requirements.

Allowed semantic inputs are limited to the verified Source Identity, Bootstrap contract version, Bootstrap implementation version, the five canonical Content Inputs, approved Bootstrap v1 constants, and values deterministically derived from those inputs under an approved algorithm. A declaration MUST enumerate the subset it consumes.

Generation MUST NOT consume `DestinationPath`, source filesystem path, staging path, clock or time, randomness, machine identity, username, locale, environment variables, ambient Git state, filesystem enumeration order, or any other undeclared ambient state. For identical approved semantic inputs, a generated declaration MUST produce the identical relative path and exact bytes.

Bootstrap MUST fail closed if a generated output is undeclared; a required declaration produces zero or more than one file; an output collides with another generated, `COPY_EXACT`, or `TRANSFORM_SCOPED` output; an output collides under ordinal case-insensitive Windows comparison or as a file/directory prefix; generation consumes an undeclared input; bytes fail required schema, representation, or postcondition validation; bytes differ for identical approved semantic inputs; or any additional source-less output is emitted.

Bootstrap v1 has no optional overlay, example switch, VCS deployment mode, or other authored-source disposition or generated-output declaration class.

## Byte, Encoding, and Hashing Semantics

All arbitrary bootstrap file identities use SHA-256 over the exact file byte sequence. Inventory identity defined in F3 MUST bind deterministic relative paths, source dispositions, generated-output declarations, and applicable exact-byte file identities without treating a directory as a file hash. This ordinary exact-byte use MUST NOT be called `specops-json-jcs-sha256-v1`.

The existing SpecOps JSON content identity profile remains limited to its separately approved JSON scopes. JCS MUST NOT be applied to C#, Markdown, Unity YAML, `.meta`, XML, binary content, directories, or arbitrary text.

`COPY_EXACT` prohibits newline conversion, BOM addition/removal, encoding conversion, text reserialization, and Unicode normalization. `TRANSFORM_SCOPED` permits differences only at declared byte spans. Future arbitrary or binary files MUST remain binary-safe.

Every `GENERATE_DETERMINISTIC` result MUST use its declared deterministic encoding and byte representation and MUST be verified against its declaration, applicable schema or representation contract, and byte-determinism requirements.

## Unity Metadata and Project Identity

Every reusable projected Unity asset and directory MUST remain paired with its corresponding `.meta` file. Every reusable `.meta` file MUST be byte-identical to source and retain its exact Unity asset GUID. If a projected asset path is renamed, its adjacent `.meta` path MUST move as the same logical pair; the `.meta` bytes and GUID MUST remain unchanged. Bootstrap v1 MUST NOT regenerate, randomize, or substitute any asset or `.meta` GUID.

`PlayerSettings.productGUID` is project identity, not a Unity asset or `.meta` GUID. After canonical input validation, it MUST be derived exactly as follows, with `\0` denoting one zero byte:

```text
digest = SHA-256(
  UTF-8(
    "specops-bootstrap-product-guid-v1\0"
    + ProjectId
    + "\0"
    + ApplicationIdentifier
  )
)

productGUID = lowercase hexadecimal representation of digest bytes 0 through 15
```

The result MUST be exactly 32 lowercase hexadecimal characters. UTF-8 has no BOM. The already validated input code points are encoded exactly, with no locale, case conversion, or normalization during hashing.

A child MUST NOT inherit the public source's Unity `cloudProjectId` or `organizationId`. Both MUST begin unbound. `CompanyName` MUST NOT be interpreted as a Unity organization slug, and no cloud identifier may be invented. The exact Unity-serialized representation of unbound remains deferred until deterministic repository or Unity-supported evidence proves it before implementation.

## Identity Transform Contract

Bootstrap v1 MUST use selector-scoped identity substitution and MUST NOT perform broad repository-wide string replacement. Later governed transform definitions may cover only approved locations for:

- Unity company, product, application, and project identity;
- `CodeNamespaceRoot` assembly and namespace identity;
- SpecOps repository and project identity;
- derived project-facing documentation; and
- eval-definition identities after separately authorized definition transformation.

Every transform declaration MUST state:

- source path and output path;
- selector or parser class;
- expected pre-value;
- exact expected match count;
- the Content Input, approved constant, or deterministic derivation supplying replacement bytes;
- deterministic encoding/escaping behavior;
- postcondition; and
- residual forbidden source identity, where applicable.

An unexpected match count, pre-value, residual, decode result, or postcondition MUST fail closed. Transform authority does not extend to similar strings elsewhere. F3/F5 MUST establish the exact file-level selectors.

`IMonkeyLogger`, `MonkeyDebugLogger`, and `MonkeyNullLogger` MUST retain those API symbol names in Bootstrap v1. They MAY appear beneath the parameterized `CodeNamespaceRoot`; symbol renaming is not bootstrap identity substitution. Later manifests MAY exclude separately approved obsolete development or migration artifacts, but exclusion does not authorize API renaming.

## Reference Feature Exclusion

Canonical Bootstrap v1 output MUST exclude the instantiated `reference-architecture-example` feature, including its production implementation, feature-specific tests, authority triplet, completed `SPECOPS_STATE.json`, feature-specific acceptance state/history, and reference-specific Unity eval requirements. Projection MUST NOT emit a reset, empty, renamed, or otherwise fake copy of the completed feature instance.

The seven-layer architecture, canonical feature templates, generic architecture-boundary tests, Moq smoke coverage, generic SampleScene baseline, and other reusable scaffolding remain independently eligible for inclusion when F3 assigns their exact dispositions. Bootstrap v1 has no demo or include-example switch. F3 MUST establish the exact path disposition set.

## Fresh SpecOps and Repository State

A successfully published Bootstrap v1 child project MUST satisfy all of these invariants:

- `repository.id` equals the exact canonical `ProjectId` input;
- `repository.type` equals the constant `unity-game-project`;
- `repository.purpose` equals the constant `SpecOps v2 governed Unity game project`;
- `repository.migrationStatus` is absent, not `null` and not represented by a sentinel value;
- repository identity is not derived from `ProductName`, `CompanyName`, `DestinationPath`, Git repository name, current directory, or machine context;
- repository type and purpose are not derived from an invocation input;
- zero instantiated feature instances exist;
- canonical feature templates are retained as non-authoritative scaffolding;
- `releasedVersion` is `null`;
- `releaseEvidencePresent` is `false`;
- no `.specops/evidence/**` path exists;
- no public-repository validation, synchronization, or migration history is inherited;
- no reference-feature `PASS` or `COMPLETE` state is inherited;
- baseline eval definitions are installed only as definitions;
- definition installation does not imply execution, `PASS`, validation evidence, release readiness, or any result; and
- `bootstrapPresent` is `true` in the final deterministic tracked Output Inventory constructed and verified in the owned Staging Destination before publication.

`bootstrapPresent = true` means only that the projected child-project state identifies itself as constructed under Bootstrap v1. Its presence in staging or a published tree is not evidence that publication or the invocation succeeded, validation evidence, release evidence, Unity-validity evidence, or Human Authority approval evidence. A Staging Destination remains distinct from a Published Destination.

The approved vocabulary above is representable in `.specops/specops.json`, which currently has no governing JSON Schema. F3 MAY later formalize it. F2 does not mutate the public source instance configuration.

Child repository/state content MUST NOT use `public-reference-implementation`, `Golden Baseline candidate`, `specops-v2-migration-in-progress`, `public reference repository`, `reference implementation`, or equivalent terminology to classify or describe the child itself. Such terminology MAY appear only when explicitly required to identify upstream lineage in `.specops/bootstrap.json`; it MUST NOT alter child classification.

Freshness MUST be represented without instantiating a fake feature state. Existing feature-state vocabulary can represent a not-started feature, but canonical fresh output has zero feature instances. Bootstrap Provenance is separate from lifecycle and evidence state.

## Bootstrap Provenance

The final deterministic tracked Output Inventory MUST contain `.specops/bootstrap.json` as an explicitly declared `GENERATE_DETERMINISTIC` output with no authored source file. Its final bytes MUST exist in the owned Staging Destination before publication, and a successfully published child MUST retain those same bytes. F3 will define its schema and exact representation; F2 creates neither the file nor schema.

Bootstrap Provenance MUST be classified as derived, non-authoritative, non-release-evidence construction lineage. It MUST be outside `.specops/evidence/**` and contain, semantically:

- source baseline identity and version;
- Bootstrap contract version;
- Bootstrap implementation version; and
- the exact five canonical Content Inputs.

Those values, the verified Source Identity or source baseline identity/version as later defined, and approved constants required by the future schema are its only allowed semantic inputs.

It MUST NOT persist `DestinationPath`, source filesystem path, timestamp, username, machine identity, Git branch, ambient Git revision unless later explicitly approved as part of Source Identity, release claim, validation claim, or `PASS` claim. The content metadata supplied as `CompanyName`, `ProductName`, and the other Content Inputs is intentional project metadata, not ambient machine/user context.

For identical verified Source Identity, contract version, implementation version, and Content Inputs, Bootstrap Provenance bytes MUST be deterministic. It records construction lineage only. It is not release evidence, validation evidence, feature authority, architecture authority, framework authority, or Human Authority approval evidence.

If F3 identifies another genuinely required Generated Output, it MUST be explicitly manifested and justified under `GENERATE_DETERMINISTIC`. This mechanism does not authorize arbitrary generated documentation, convenience files, Git files, evidence, timestamps, or migration state.

## Destination Safety

Bootstrap MUST fail closed unless the requested destination is nonexistent and safe before staging and remains nonexistent until publication. The requested path MUST NOT already exist as a file, directory, symbolic link, junction, reparse entry, mount-like entry, or broken-link equivalent detectable by supported platform primitives.

The existing destination parent MUST resolve to a real directory. Bootstrap MUST reject unsafe reparse/link traversal in any existing destination or staging ancestor. Source, staging, and destination paths MUST neither equal nor contain one another after canonical ordinal case-insensitive comparison and safe resolution. Their path sets MUST NOT overlap through links, junctions, reparses, aliases, or case-equivalent Windows names.

All projected paths MUST be unique under ordinal case-sensitive comparison and ordinal case-insensitive Windows comparison. File/directory prefix collisions and portable reserved-name collisions are prohibited. Publication MUST NOT overwrite, merge with, or adopt an existing user project.

Destination safety is an execution precondition only. No destination spelling or resolution may affect generated tracked content.

## Failure and Publication Model

Bootstrap v1 uses fail-safe staged publication:

```text
validate
    -> create owned sibling staging
    -> project and transform
    -> complete deterministic verification
    -> publish to the still-nonexistent destination
    -> post-publication verification
```

The staging path MUST be a uniquely invocation-owned sibling under the verified destination parent and MUST never be treated as output content. A failure before successful publication MUST leave the requested destination nonexistent and MUST NOT produce an apparently valid project there. Publication MUST recheck destination nonexistence immediately before moving the verified staging tree.

Before publication, staging MUST contain the complete final deterministic tracked Output Inventory, including `bootstrapPresent = true` and the final `.specops/bootstrap.json` bytes. Publication MUST NOT mutate tracked output paths or bytes, and post-publication verification MUST NOT mutate them. Staging final-form bytes do not make the Staging Destination a Published Destination and MUST NOT be represented as successful completion.

A successful Bootstrap v1 invocation requires all four of: complete deterministic staged Output Inventory, staged verification `PASS`, fail-safe publication to the requested still-nonexistent destination, and post-publication verification `PASS`. Only after all four succeed may the invocation return a successful bootstrap verdict. Publication or post-publication verification failure MUST produce a failure verdict even if staging or published tracked state contains `bootstrapPresent = true` or final Bootstrap Provenance. No tracked-state mutation may convert failure into success.

This contract does not call filesystem rename universally atomic. Fail-safe staged publication assumes the staging and destination share a parent and filesystem, supported path and reparse checks behave as documented, no hostile concurrent actor defeats those checks, and the platform can perform the publication move without cross-volume copying. F4 MUST define supported-platform behavior and exact cleanup mechanics.

Post-publication verification MUST run against the Published Destination. A post-publication failure MUST be reported as failure and MUST NOT be represented as successful bootstrap provenance, validation, or release evidence. Exact recovery behavior is deferred to F4 and MUST not risk unrelated user content.

Cleanup authority extends only to a staging path proven to have been created and owned by the current invocation. A staging name, naming pattern, destination sibling relationship, or partial marker alone is insufficient authority to recursively delete a path. Bootstrap cleanup MUST never delete, overwrite, or modify arbitrary source, destination, ancestor, sibling, or user paths.

## Pre-Unity Verification Boundary

Before publication, and again where applicable after publication, later Bootstrap verification MUST deterministically establish at least:

- the exact expected output relative path set and absence of unexpected output;
- exact-byte equality for every `COPY_EXACT` file;
- only authorized span differences and satisfied postconditions for every `TRANSFORM_SCOPED` file;
- absence of every `EXCLUDE` output;
- exactly one output satisfying every `GENERATE_DETERMINISTIC` declaration, required schema or representation, postcondition, and deterministic-byte expectation;
- absence of undeclared source-less output and collisions across the complete emitted output namespace;
- reusable Unity asset/`.meta` pairing, exact `.meta` bytes, and unchanged asset GUIDs;
- exact expected `ProjectVersion` version and revision;
- static consistency between the package manifest and depth-zero lock inventory;
- expected assembly topology and configuration without changing structural authority;
- required SpecOps routes, templates, contracts, permissions, Skills, and definition structures selected by F3;
- JSON syntax validity and applicable approved-schema validity;
- absence of transient Unity directories;
- absence of source-repository-only artifacts and public-reference child classification;
- absence of `.git`, Git history, release evidence, inherited lifecycle history, and reference-feature state;
- deterministic Bootstrap Provenance semantics;
- absence of machine, user, source-locator, staging, and destination paths in tracked output; and
- after publication, exact equality of the tracked relative path set and bytes with the verified staged Output Inventory, without verification mutation.

These Phase F checks MUST NOT be described as proof that Unity can open the project, resolve packages, import assets, compile assemblies, or pass EditMode or PlayMode tests. Those semantic checks belong to Phase G and require separately authorized Unity execution. Installing an eval definition or passing static checks does not imply Phase G success.

## Determinism

Bootstrap v1 MUST make this reproducibility predicate objectively testable:

```text
same verified Source Identity
+ same Bootstrap contract version
+ same Bootstrap implementation version
+ same five canonical Content Inputs
= same output relative path set
+ same tracked output bytes at every relative path
```

`DestinationPath` is excluded from deterministic content identity. Filesystem enumeration order, locale, current directory, environment, machine, user, Git state, clock, and process state MUST NOT affect output. Randomness is prohibited in generated tracked content. A transient staging name MAY be nondeterministic because it is external, non-output execution state.

The predicate applies to the collision-free union of projected authored-source outputs and all Generated Outputs in the final tracked Output Inventory already present in staging. Each `GENERATE_DETERMINISTIC` declaration is independently byte-deterministic for identical approved semantic inputs. Publication and post-publication verification MUST preserve the complete path set and bytes exactly.

## VCS Neutrality

Canonical Bootstrap v1 generation does not require Git. It MUST NOT project `.git` or history, initialize Git, require a repository or remote, read ambient Git configuration to change output, or write branch/commit state into generated tracked content. A future separately governed wrapper MAY use Git to locate or verify a source tree, but it is outside canonical Bootstrap v1 generation. Bootstrap v1 has no `VcsDeployment` input.

## Attribution

Bootstrap v1 MUST preserve source `LICENSE`, `NOTICE` and other required source attribution, and source copyright notices according to their manifest dispositions. `CompanyName` and other project identity inputs MUST NOT rewrite, replace, or claim source authorship or copyright.

Identity-transform selectors MUST NOT target a copyright or authorship header merely because it contains `Infinite Monkey Theorem AB`, a monkey-branded producer identity, or similar source attribution. Legal or editorial evolution and project-specific attribution extensions are outside this contract.

## Deferred Governed Work

The following are intentionally unresolved here and require later governed work, not implementation discretion:

- the exact F3 Authored Source Inventory and every path disposition;
- the exact F3 Generated Output Inventory and every justified declaration beyond the required `.specops/bootstrap.json` declaration, if any;
- the exact final reusable Golden Baseline Source Identity;
- JSON Schemas, including any manifest, inventory, or repository-state formalization;
- the `.specops/bootstrap.json` schema representation;
- the exact Unity-serialized representation of unbound `cloudProjectId` and `organizationId`;
- exact file-level identity selectors, encodings, match counts, pre-values, and postconditions;
- the implementation module, CLI, and internal design;
- exact owned-staging cleanup and post-publication recovery mechanics;
- the actual generated eval-definition inventory after reference-example exclusion;
- Unity semantic validation in Phase G; and
- release evidence and any release decision.

## Normative Acceptance Criteria

- **AC-F2-001 — Authority and status:** The Bootstrap v1 artifact identifies itself as subordinate normative behavior, not authority, evidence, release result, approval evidence, or Unity-validity proof.
- **AC-F2-002 — Explicit canonical inputs:** An invocation accepts exactly the six required inputs, validates each against this contract without silent normalization or derivation, and proves `DestinationPath` cannot affect tracked output.
- **AC-F2-003 — Source binding:** A source is accepted only when its manifest-bound Authored Source Inventory, complete Generated Output Inventory, exact-byte identities, supported entry types, single Source Identity, and invocation-long immutability are verified; locator and Git state do not substitute for identity.
- **AC-F2-004 — Complete dispositions and generation declarations:** Every authored source path has exactly one non-overlapping `COPY_EXACT`, `TRANSFORM_SCOPED`, or `EXCLUDE` disposition; every source-less output has exactly one explicit `GENERATE_DETERMINISTIC` declaration; the final Output Inventory is one collision-free union; and every missing, duplicate, ambiguous, overlapping, unexpected, undeclared, or case-colliding rule or output fails closed.
- **AC-F2-005 — Byte preservation and deterministic generation:** Every copied output equals its source bytes, every transformed output proves exact equality outside declared non-overlapping byte spans without BOM, newline, encoding, or Unicode normalization side effects, and every generated output has identical bytes for identical approved semantic inputs and satisfies its declared representation.
- **AC-F2-006 — Unity identity:** Every reusable asset remains paired with a byte-identical `.meta` and unchanged asset GUID; `productGUID` matches the specified SHA-256 derivation; cloud project and organization identity are unbound without a guessed serialization.
- **AC-F2-007 — Scoped identity:** Every identity substitution declares its path, selector/parser, pre-value, count, source, encoding, postcondition, and applicable forbidden residual; broad replacement and monkey logger API renaming are absent.
- **AC-F2-008 — Reference exclusion:** No reference-architecture-example implementation, feature authority/state/history, feature-specific test, or reference-specific eval requirement is output, while independently manifested generic scaffolding remains eligible.
- **AC-F2-009 — Fresh child state:** The staged final Output Inventory has the exact approved repository id/type/purpose, omits `migrationStatus`, contains `bootstrapPresent = true`, satisfies every fresh-state invariant, contains zero feature instances, and does not classify the child as the public reference implementation or imply publication success.
- **AC-F2-010 — Provenance:** The staged final `.specops/bootstrap.json` is an explicit `GENERATE_DETERMINISTIC` output with no authored source; its bytes record only deterministic construction lineage from approved source/contract/implementation identities, approved constants, and the five Content Inputs, outside evidence, with every prohibited ambient, lifecycle, or success claim absent and the same bytes retained after publication.
- **AC-F2-011 — Destination safety:** The absolute canonical destination and owned sibling staging pass nonexistence, ancestry, reparse, overlap, portable collision, and no-overwrite checks without entering tracked bytes.
- **AC-F2-012 — Fail-safe publication:** Projection produces final tracked paths and bytes only in invocation-owned sibling staging; staged verification precedes non-mutating publication to a rechecked nonexistent destination; non-mutating post-publication verification follows; success requires all four approved steps; failure cannot be converted by tracked-state mutation; and cleanup authority cannot reach arbitrary paths.
- **AC-F2-013 — Verification boundary:** Phase F verifies every required static inventory, byte, metadata, topology, SpecOps, JSON, exclusion, and contamination invariant while making no Unity open/resolve/compile/test claim; Phase G remains separate.
- **AC-F2-014 — Determinism and hashing:** The stated reproducibility predicate holds for relative paths and tracked bytes; ordinary exact-byte SHA-256 is used for arbitrary files without misapplying the SpecOps JSON JCS profile.
- **AC-F2-015 — VCS neutrality:** Canonical generation neither requires nor initializes Git, projects no `.git` or history, and is unaffected by ambient Git state or configuration.
- **AC-F2-016 — Attribution:** Required source license, notice, attribution, and copyright content is preserved, and project identity transformation does not rewrite source authorship.

These criteria constrain observable results. They do not prescribe PowerShell function names, private types, implementation data structures, or test fixture layout.
