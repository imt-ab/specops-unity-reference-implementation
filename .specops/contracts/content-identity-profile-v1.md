# SpecOps JSON Content Identity Profile v1

## Status and Authority Boundary

This document is a normative calculation profile subordinate to current SpecOps architecture, governance, and evidence contracts. It defines how a supported JSON value is bound to a content identity. It is not architecture or governance authority, does not amend those authorities, does not prove producer or execution authenticity, and does not authorize release or publication.

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHOULD**, and **MAY** in this profile are to be interpreted as described by BCP 14 when they appear in all capitals.

## Profile Identifier

`specops-json-jcs-sha256-v1`

This identifier is immutable in calculation meaning. A calculation-affecting change requires a new profile identifier. A later clarification MAY retain this identifier only when it cannot alter calculation results.

## Scope

This profile applies only to supported JSON values. It defines two input modes, `FULL_JSON` and `EVAL_DEFINITION`, under the same profile identifier.

## Normative Dependencies

- [RFC 8785, JSON Canonicalization Scheme (JCS)](https://www.rfc-editor.org/rfc/rfc8785)
- SHA-256 as specified by [FIPS PUB 180-4](https://doi.org/10.6028/NIST.FIPS.180-4)
- UTF-8 as required for JCS output by RFC 8785

RFC 8785 incorporates the relevant JSON, I-JSON, Unicode, IEEE 754, and ECMAScript serialization requirements. This profile does not replace or approximate those rules.

## Input Requirements

Source JSON consumed directly by this profile MUST be valid UTF-8. A producer MUST reject malformed UTF-8 and MUST NOT substitute locale-dependent decoding. Source JSON beginning with a UTF-8 byte-order mark MUST be rejected, no identity may be produced, and producers MUST NOT silently strip or ignore the leading BOM. This is a profile-specific stricter input rule; it does not claim that RFC 8785 itself mandates rejection of a source BOM. Canonical output MUST remain UTF-8 without a byte-order mark.

The parsed value MUST satisfy the input constraints of RFC 8785, including its I-JSON requirements:

- object member names MUST be unique;
- string data MUST be valid Unicode data and MUST be preserved as-is;
- number data MUST be expressible as IEEE 754 double-precision values; and
- values that JCS cannot represent, including lone Unicode surrogates, NaN, and Infinity, MUST be rejected.

A producer MUST detect duplicate object member names before any lossy object-model conversion can discard or merge them. It MUST NOT silently normalize invalid input. It MUST NOT apply Unicode normalization such as NFC or NFD.

The profile operates on the parsed JSON value. Original insignificant whitespace and source object-member ordering are not inputs to the digest calculation.

## Canonicalization

A producer MUST canonicalize the calculation value exactly according to RFC 8785. It MUST use RFC 8785 string serialization, ECMAScript-compatible number serialization, recursive object-property sorting by unsigned UTF-16 code units, and unchanged array element ordering. Whitespace between JSON tokens MUST NOT be emitted.

The canonical representation MUST be encoded as UTF-8 without a byte-order mark.

## Digest Calculation

A producer MUST calculate SHA-256 over the UTF-8 bytes of the RFC 8785 canonical JSON representation. It MUST encode the digest as exactly 64 lowercase hexadecimal ASCII characters.

## FULL_JSON Mode

`FULL_JSON` is used when the content identity is stored outside the identified JSON artifact, including a release-manifest evidence member.

The producer MUST:

1. read the source as strict supported JSON under this profile;
2. reject duplicate member names and any input unsupported by RFC 8785 or this profile;
3. preserve the complete parsed JSON value, excluding no fields;
4. canonicalize that complete value using RFC 8785;
5. encode the canonical representation as UTF-8 without a byte-order mark;
6. calculate SHA-256 over those bytes; and
7. encode the digest as lowercase hexadecimal.

## EVAL_DEFINITION Mode

`EVAL_DEFINITION` is used for a complete persisted document conforming to `eval-definition.schema.json`, where `contentIdentity` is embedded in the definition being identified.

The producer MUST:

1. read the source as strict supported JSON under this profile;
2. reject duplicate member names and any input unsupported by RFC 8785 or this profile;
3. require the root value to be a JSON object;
4. require exactly one normal schema-valid root-level `contentIdentity` member to exist;
5. create the calculation value by removing only that root-level `contentIdentity` member;
6. retain every nested property named `contentIdentity`;
7. retain `description`;
8. retain `contractVersion`;
9. retain `definitionId`;
10. retain `definitionVersion`;
11. retain `targetScope`;
12. retain `governingReferences`;
13. retain `checks`;
14. preserve all array ordering;
15. perform no other semantic projection or exclusion;
16. canonicalize the remaining root object using RFC 8785;
17. encode the canonical representation as UTF-8 without a byte-order mark;
18. calculate SHA-256 over those bytes; and
19. encode the digest as lowercase hexadecimal.

The root-level `contentIdentity` member is the only excluded member. Its `algorithm` and `value` do not affect the calculation. A nested member with the same name remains included.

## Array Semantics

Array ordering is significant and MUST be preserved. Object properties nested inside arrays are sorted according to RFC 8785, but array elements are never reordered.

Consequently:

- different insignificant JSON whitespace produces the same identity;
- different source ordering of the same object members produces the same identity;
- different array ordering produces different canonical content and, except for a theoretical SHA-256 collision, a different digest;
- changing `description` changes the `EVAL_DEFINITION` identity;
- changing a `passCondition` changes the `EVAL_DEFINITION` identity;
- changing check order changes the `EVAL_DEFINITION` identity;
- changing any included governing reference changes the `EVAL_DEFINITION` identity;
- changing `targetScope` order changes the `EVAL_DEFINITION` identity; and
- changing only the root eval-definition `contentIdentity.algorithm` or `contentIdentity.value` does not change the `EVAL_DEFINITION` calculation identity.

## Duplicate-Key Policy

Duplicate object member names are unsupported and MUST cause rejection. Detection MUST occur before a parser or object model can collapse the duplicate members. No canonical representation or identity may be produced for such input.

## Unicode / Number Semantics

Strings and property names MUST follow RFC 8785 serialization and sorting exactly. Sorting is locale-independent and based on unsigned UTF-16 code units. Unicode string data MUST be preserved as-is; this profile defines no Unicode normalization.

Numbers MUST follow the RFC 8785 ECMAScript-compatible IEEE 754 double-precision serialization rules. A locale-dependent serializer, general-purpose pretty-printer, or implementation-specific number format is not a conforming substitute.

## Failure Semantics

A producer MUST fail closed and MUST NOT produce an identity when it cannot establish one unambiguous RFC-8785-conforming canonical representation. This includes malformed UTF-8 or JSON, duplicate object member names, invalid Unicode data, non-representable numbers, unsupported input types, and any canonicalization failure.

## Security / Trust Boundary

The identity binds supported JSON content under this profile and allows future tooling to detect a content mismatch. SHA-256 content binding does not establish execution, producer identity, producer authenticity, trusted provenance, or cryptographic attestation. A conforming digest alone is not evidence that a claimed process occurred.

## Non-JSON Artifacts

Non-JSON artifacts are outside this profile. It MUST NOT be applied to XML, Unity logs, binaries, arbitrary text, directories, Git trees, or archives. A separately identified future profile is required before such artifacts can carry canonical SpecOps content identity.

## Conformance Vectors

The companion file [`content-identity-profile-v1.vectors.json`](content-identity-profile-v1.vectors.json) provides machine-readable known-answer and rejection vectors. It is a conformance basis, not execution evidence or release evidence. A future implementation claiming this profile MUST pass the applicable vectors without treating its own output as the definition of expected behavior.

## Versioning

The meaning of `specops-json-jcs-sha256-v1` MUST NOT be silently reinterpreted. Any incompatible change to input acceptance, calculation-value construction, canonicalization, byte encoding, digest algorithm, or digest encoding requires a new profile identifier.
