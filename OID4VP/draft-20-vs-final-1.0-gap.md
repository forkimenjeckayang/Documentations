# OID4VP Gap Analysis: Draft 20 → Final 1.0

This document compares **Draft 20** (`draft-20.md`) and **Final 1.0** (`final-1.0.md`) of the OpenID for Verifiable Presentations specification. The focus is on the deltas a Verifier or Wallet implementer needs to know to migrate.

> **Scope note**: This doc covers **main spec content (Sections 1–15)** in §1–§11, and **format-specific / DC API appendix gaps** in **§12**. The §12 coverage is **scoped to the formats and transports relevant to this profile**: JWT VC (`jwt_vc_json`), SD-JWT VC (`dc+sd-jwt`), and the DC API. **mdoc (Appendix B.2) is intentionally excluded** because it is not supported by this profile's Issuer. See `final-1.0.md` Appendix B.2 directly if mdoc support is added later.

---

## 1. Executive Summary

Draft 20 → Final 1.0 is a **substantive protocol-model migration**, not an editorial update. The five biggest shifts:

1. **Request expression**: DIF Presentation Exchange (`presentation_definition`) is replaced by **DCQL** (`dcql_query`) — a new JSON-encoded query language with deterministic Claims Path Pointer evaluation and no JSONPath/scripting surface.
2. **Response shape**: `presentation_submission` / `descriptor_map` are gone. `vp_token` is now a **JSON object keyed by DCQL credential query `id`**, with arrays of presentations as values.
3. **Client identification**: The separate `client_id_scheme` parameter is gone. The trust model is now embedded directly in `client_id` as a **Client Identifier Prefix** (`<prefix>:<orig_client_id>`).
4. **Response protection**: JARM-style "sign or sign+encrypt" is gone. Final 1.0 mandates an **unsigned encrypted JWT** profile (`direct_post.jwt` for redirect flows, `dc_api.jwt` for DC API).
5. **Profile dependency**: Final 1.0 explicitly **requires profiles for interoperability** — defining which optional features are mandatory, which credential format identifiers are allowed, and any extensions. Draft 20 left this implicit.

Other major additions in Final 1.0: **Request URI POST capability exchange** (`request_uri_method=post` with `wallet_metadata` / `wallet_nonce`), **Transaction Data**, **Verifier Info attestations**, presentations **without cryptographic Holder Binding**, **Trusted Authorities Query**, a full **Digital Credentials API** profile (Appendix A), and a dedicated **Privacy Considerations** chapter (Section 15).

---

## 2. Core Protocol Model Changes

### 2.1 Request Expression: PE → DCQL

| Aspect | Draft 20 | Final 1.0 |
|---|---|---|
| Primary parameter | `presentation_definition` | `dcql_query` |
| By-reference variant | `presentation_definition_uri` | **Removed** |
| Scope alias | scope → Presentation Definition | scope → DCQL query |
| Query language | DIF Presentation Exchange v2 | **DCQL** (Section 6) |
| Path syntax | DIF PE JSONPath (e.g. `$.vc.type`) | **Claims Path Pointer** (Section 7) — array of strings / `null` / non-negative integers, deterministic, no scripting |
| Constraint mechanism | DIF PE `filter` (regex / JSON Schema) | DCQL `values` (literal-array equality only) |
| Format binding | DIF PE `format` field on input descriptor | DCQL `format` + format-specific `meta` (e.g. `vct_values`, `doctype_value`, `type_values`) |
| Holder binding control | Implicit | Explicit `require_cryptographic_holder_binding` boolean |
| Issuer/trust filtering | Done via `filter` on issuer claims | First-class **Trusted Authorities Query** (Section 6.1.1) |
| Alternatives | DIF PE `submission_requirements` (rule:pick, count, from group) | DCQL `credential_sets.options` + `claim_sets` arrays |

**Implementation impact**:
- Verifier request builders **must rewrite** every Presentation Definition into DCQL.
- Wallet selection engines **must replace** DIF PE evaluation logic with DCQL evaluation rules (Section 6.4).
- Any code parsing JSONPath strings must be replaced by Claims Path Pointer array processing — a **safer** surface (no scripting risk).
- `filter` users who relied on regex / JSON Schema must accept that DCQL `values` is **literal-equality only** and is **privacy best-effort, not a security control** (per Section 6.4.1).

### 2.2 Response Shape: `presentation_submission` → DCQL-keyed `vp_token`

| Aspect | Draft 20 | Final 1.0 |
|---|---|---|
| Required response parameters | `vp_token` **and** `presentation_submission` | **Only** `vp_token` |
| `vp_token` shape | A single VP **or** an array of VPs (mixed strings / objects) | **Always** a JSON object: `{ "<dcql_id>": [<presentation>, ...] }` |
| Cardinality control | Implicit (single-VP cannot be wrapped in array) | Explicit `multiple` flag on each Credential Query |
| Mapping mechanism | `descriptor_map` with `path` (`$` or `$[n]`) and `path_nested` | Built into `vp_token` keys (no separate map) |
| Optional credential queries | All requested data must be in response | Optional Credential Queries with no match are **omitted** from `vp_token` |

**Implementation impact**:
- Verifier parsers **must switch** from "find descriptor → walk `path` → walk `path_nested`" to "look up `vp_token[<dcql_id>]` → process array".
- The `multiple` flag becomes the cardinality contract: when omitted/false, the array MUST contain exactly **one** presentation.
- Any code asserting that `presentation_submission` exists must be removed.

### 2.3 Client Identification: `client_id_scheme` → Client Identifier Prefix

| Aspect | Draft 20 | Final 1.0 |
|---|---|---|
| Mechanism | Separate `client_id_scheme` request parameter | Prefix embedded in `client_id`: `<prefix>:<orig_client_id>` |
| Identifier in OAuth flow | Bare client ID | **Full prefixed** identifier (used everywhere in OAuth and in proof bindings — see 4.2) |
| Defined values | `pre-registered`, `redirect_uri`, `entity_id`, `did`, `verifier_attestation`, `x509_san_dns`, `x509_san_uri` | `pre-registered`, `redirect_uri`, **`openid_federation`**, **`decentralized_identifier`**, `verifier_attestation`, `x509_san_dns`, **`x509_hash`**, `origin` (reserved for DC API) |
| Renames from Draft 20 | — | `entity_id` → `openid_federation`, `did` → `decentralized_identifier`, `x509_san_uri` → **dropped** (replaced by `x509_hash`) |
| Wallet metadata | `client_id_schemes_supported` | `client_id_prefixes_supported` |
| Fallback rule | If `client_id_scheme` absent → RFC 6749 default | If `client_id` has no `:` → pre-registered. If `:` present but unknown prefix → Wallet **MAY** treat as pre-registered **or** reject. Pre-registered values **MUST NOT** start with a known-prefix-then-`:` (collision avoidance). |

**Implementation impact**:
- Client identity validation logic **must be rewritten** around `:`-prefix parsing + per-prefix rules.
- Existing `entity_id` / `did` deployments must rename to `openid_federation` / `decentralized_identifier`.
- `x509_san_uri` deployments must migrate to `x509_hash` (which uses a base64url SHA-256 hash of the DER cert as the identifier — different shape from the DNS/URI variants).
- Verifier client registries **must reject** new pre-registered IDs that begin with `<known-prefix>:` to prevent ambiguity.

### 2.4 Response Protection: JARM → Encrypted Unsigned JWT

| Aspect | Draft 20 | Final 1.0 |
|---|---|---|
| Mechanism | JARM ([JARM]) — sign **or** sign+encrypt | **Unsigned encrypted JWT** ([RFC7516]/[RFC7518]) |
| Encrypted-only allowed | Only as a JARM extension | **Mandated** profile |
| Response mode for encrypted POST | `direct_post.jwt` (JARM-based) | `direct_post.jwt` (encrypted JWT) **and** `dc_api.jwt` (DC API encrypted JWT) |
| `iss` / `exp` / `aud` in JWT | Required by JARM signed mode | **MUST be omitted** from JWT Claims Set |
| Encryption key source | Wallet metadata | `client_metadata.jwks` (or prefix-allowed source); selected JWK `alg` + `kid` are bound to JWE header |
| `enc` algorithm source | JARM-style negotiation | `encrypted_response_enc_values_supported` (default `A128GCM` if absent) |
| Restriction on `client_metadata.jwks` | — | Keys **MUST NOT** be used to verify Authorization Request signatures; each JWK **MUST** have a unique `kid` per request |

**Implementation impact**:
- Verifiers must publish encryption keys in `client_metadata.jwks` with `alg` set on each key, and unique `kid`s.
- Wallets must select a JWK whose `alg` matches what they support, set the JWE header `alg` to the same value, copy the `kid` into the JWE header, and use `enc` from `encrypted_response_enc_values_supported`.
- JARM JWS-processing code paths can be retired.

---

## 3. New Mechanisms in Final 1.0 (no Draft 20 equivalent)

### 3.1 Request URI POST Capability Exchange (Section 5.10)

A Verifier sets `request_uri_method=post`, and the Wallet POSTs to `request_uri` with its own capabilities (`wallet_metadata`, `wallet_nonce`) so the Verifier can tailor the Request Object — including the right `enc` algorithm, the right signing alg, and the encryption JWKs.

**Wallet rules**:
- POST to `request_uri` over **HTTPS** with `Content-Type: application/x-www-form-urlencoded`, `Accept: application/oauth-authz-req+jwt`, UTF-8 body.
- Send `wallet_metadata` (subset of Section 10 Wallet metadata) and `wallet_nonce`.
- Verifier **MUST** echo `wallet_nonce` in the signed Request Object's `wallet_nonce` claim; mismatch → Wallet **MUST** terminate processing.
- If active Client Identifier Prefix forbids signed requests, Wallet **MUST NOT** advertise `request_object_signing_alg_values_supported`.
- HTTP error from Request URI endpoint → Wallet **MUST** terminate (Section 5.10.2).

**Verifier rules**:
- `request_uri_method` **MUST NOT** be present if `request_uri` is absent.
- `client_id` in the outer Authorization Request and `client_id` claim in the returned Request Object **MUST** be identical (including prefix); mismatch → Wallet terminates.
- If the POST capability exchange is used, the Verifier **SHOULD** include `client_metadata` so the Wallet can decide which subset of `wallet_metadata` to send.

### 3.2 Transaction Data (Section 5.1, 8.4)

A new request parameter that **binds presentation to authorization** of a specific transaction (e.g., payment, QES document signing). Each `transaction_data` element is a base64url-encoded JSON object with at least `type` and `credential_ids`.

**Rules**:
- Wallet that does not support `transaction_data` **MUST** reject any request containing it (this is the **only** unknown-parameter exception — all other unknowns are silently ignored).
- New error code: **`invalid_transaction_data`** for malformed/unsupported entries.
- For SD-JWT VC: `transaction_data` **requires** `require_cryptographic_holder_binding=true`. Default hash for `transaction_data_hashes` is `sha-256` and implementations **MUST** support it.
- If a `transaction_data` object lists multiple `credential_ids`, the Wallet **MUST** use **only one** of the referenced credentials to authorize the transaction.

### 3.3 Verifier Info (Section 5.11)

A new request parameter `verifier_info` carries an array of **attestations about the Verifier** (registration certificates, policy statements, role attestations) issued by trusted third parties. The Wallet MAY use these for authorization decisions, policy enforcement, or richer consent UX — and MUST validate signatures + binding if it does.

**Two PoP models**:
- **Claim-bound**: the attestation isn't Verifier-signed but is bound via claims (e.g., JWT `sub` = certificate DN, possibly + `client_id`).
- **Key-bound**: a Verifier signature over a PoP object that includes the request `nonce` and `client_id`.

The optional `credential_ids` field scopes the attestation to specific Credential Queries (omitted ⇒ applies to all).

### 3.4 Presentations without Cryptographic Holder Binding (Section 5.3)

A Verifier **MAY** request Credentials without a holder-binding proof — useful for low-security credentials (cinema tickets), biometrically-bound credentials, and claim-bound credentials (diplomas).

Mechanism: `require_cryptographic_holder_binding: false` on the DCQL Credential Query.

**Critical security rule**: Without holder binding, `nonce` is **not** echoed in the response, so request-response correlation falls back to `state`. When at least one such Credential is requested (and DC API is **not** in use), the Verifier **MUST**:
- include `state` in the Authorization Request,
- ensure it is cryptographically random with **at least 128 bits** of entropy,
- generate a fresh value per request,
- store it in session,
- verify the same `state` is returned.

### 3.5 Trusted Authorities Query (Section 6.1.1)

DCQL Credential Queries can include `trusted_authorities` to filter accepted issuers / trust frameworks. Three first-class types:

- `aki` — base64url-encoded X.509 AuthorityKeyIdentifier; matches against AKI in any cert in the credential's chain.
- `etsi_tl` — identifier/URL of an ETSI Trusted List; matches via a cert in the chain belonging to that list (or its cascading lists).
- `openid_federation` — Entity Identifier of a Trust Anchor; valid trust path must be constructible.

**Privacy note**: Online-resolution-based mechanisms can leak End-User behavior — Wallets **SHOULD NOT** auto-fetch unfamiliar URLs (Section 15.10).

### 3.6 Digital Credentials API Profile (Appendix A — referenced only)

Final 1.0 adds a full self-contained DC API profile with:
- New response modes `dc_api` (unencrypted) and `dc_api.jwt` (encrypted).
- New request parameter `expected_origins` (REQUIRED for signed requests, ignored if present in unsigned).
- **Origin-based audience semantics**: in DC API mode, presentation `aud` is `origin:<verifier-origin>` (e.g. `origin:https://verifier.example.com/`), **not** the Client Identifier — even for signed requests.
- Signed-request serializations: JWS Compact (single Client Identity) and JWS JSON (multi-Client-Identity / multi-trust-framework).
- Protocol identifiers: `openid4vp-v1-unsigned`, `openid4vp-v1-signed`, `openid4vp-v1-multisigned`.
- `state` is **not defined** for DC API responses — Verifiers must not depend on it for correlation.

> See `final-1.0.md` Appendix A for parameter, serialization, and example detail.

---

## 4. Behavioral Changes (same parameters, different rules)

### 4.1 Audience Binding

| Mode | Draft 20 | Final 1.0 |
|---|---|---|
| Redirect / `direct_post` | `aud` (or `domain` for LD) = bare `client_id` | `aud` (or `domain` for LD) = **full prefixed Client Identifier**, e.g. `x509_san_dns:client.example.org` |
| DC API | (not defined) | `aud` = `origin:<verifier-origin>` (origin-bound; `client_id` not used as audience) |

**Implementation impact**: Wallets that strip the prefix when emitting `aud` will silently fail Verifier replay-protection checks. Verifiers must accept the prefixed form.

### 4.2 Always Use the Full Client Identifier (Section 14.8)

The Wallet **MUST** use the full `<prefix>:<orig>` Client Identifier — including in:
- the OAuth flow (every place RFC 6749 references `client_id`),
- the presentation's audience binding (`aud` in JWT proofs, `domain` in LD proofs),
- any logging / display that identifies the Client.

Confusing prefixed vs non-prefixed identifiers is treated as an attack surface.

### 4.3 `state` Requirements

| Case | Draft 20 | Final 1.0 |
|---|---|---|
| Default | OPTIONAL (correlation) | OPTIONAL |
| Without holder binding | (not addressed) | **REQUIRED**, ≥128-bit entropy, fresh per request, verified on response (except DC API) |
| Character set | Not constrained | ASCII URL-safe only: letters, digits, `-`, `.`, `_`, `~` |

### 4.4 `response_mode` Is REQUIRED

Final 1.0 makes `response_mode` a **REQUIRED** Authorization Request parameter (Section 5.2). Draft 20 listed it as OPTIONAL with a default of `fragment`.

### 4.5 Verifier MUST Do Its Own Checks (Section 14.9)

Final 1.0 explicitly forbids the Verifier from relying on Wallet-side enforcement of DCQL constraints. The Verifier **MUST** independently:
- validate every returned VP integrity / authenticity,
- verify replay-protection bindings,
- confirm the returned credentials satisfy the request,
- run trust-framework / revocation policy checks.

### 4.6 `nonce` Character Set and Entropy

Final 1.0: `nonce` **MUST** contain only ASCII URL-safe characters (letters, digits, `-`, `.`, `_`, `~`) and be cryptographically random with sufficient entropy per request. Same character-set restriction applies to `state`.

### 4.7 Request Object `iss` vs `client_id`

Final 1.0: if a Request Object contains both `iss` and `client_id`, the Wallet **MUST ignore** `iss` and use `client_id` as the authoritative identifier. (Allowed for compatibility with existing JAR libraries that auto-set `iss`, but the Wallet treats `client_id` as truth.)

### 4.8 Request Object `typ` Is Strictly Required

Final 1.0: the Request Object's JOSE `typ` header **MUST** be `oauth-authz-req+jwt`. Wallets **MUST NOT** process Request Objects where `typ` is missing or has any other value.

### 4.9 `client_metadata` Precedence and Unknown Members

- Authoritative metadata from external trust sources (e.g., OpenID Federation Entity Statement) **takes precedence** over `client_metadata`.
- Unknown metadata members **MUST** be ignored unless a profile explicitly defines them.
- `client_metadata.jwks` keys **MUST NOT** be used to verify Authorization Request signatures (encryption-only).

### 4.10 Unknown Parameters Behavior

Final 1.0: Wallets **MUST** ignore unknown request parameters — **except** `transaction_data`. A Wallet that does not support `transaction_data` **MUST** reject any request containing it.

### 4.11 Additional Specific Rules (Often Missed)

These are smaller, scoped rules in Final 1.0 main spec that nonetheless affect concrete behavior. They have **no Draft 20 equivalent**.

| # | Rule | Section | Implementation impact |
|---|---|---|---|
| 1 | **`response_uri` policy reuse** — the `response_uri` value **MUST** be one the Verifier would be allowed to use as `redirect_uri` under Section 5.9 (Client Identifier Prefix) rules. Spec text referring to Redirect URI also applies to Response URI. | §8.2 | Verifier must validate its `response_uri` against the active prefix's redirect-URI rules (e.g., `x509_san_dns` FQDN match, attestation `redirect_uris` list match). |
| 2 | **Encryption-failure fallback** — if a Wallet cannot generate an encrypted `direct_post.jwt` / `dc_api.jwt` response, it **MAY** send an **unencrypted error response** per §8.2 (i.e., normal `direct_post` error path). | §8.3.1 | Wallets need a fallback code path; Verifiers must accept unencrypted errors even when they advertised encrypted-only. |
| 3 | **DCQL `id` character set + uniqueness** — Credential Query `id` and Claim Query `id` values **MUST** be non-empty strings of alphanumeric / `_` / `-` only, and **MUST NOT** repeat within their scope (request-wide for credential `id`, query-local for claim `id`). | §6.1, §6.3 | Verifier query builders must enforce identifier syntax and uniqueness at construction time. |
| 4 | **DCQL extensibility — ignore unknowns** — Implementations **MUST** ignore unknown DCQL properties **at any level** (top-level, Credential Query, Credential Set Query, Claims Query, Trusted Authorities Query). | §6 intro | Wallet DCQL parsers must be tolerant of forward-compatible extensions; do not error on unknown keys. |
| 5 | **Duplicate claim queries** — A Verifier **MUST NOT** point to the same claim more than once in a single Credential Query; Wallets **SHOULD** ignore duplicate claim queries. | §6.1 | Verifier must dedupe claim paths; Wallet need not error but should silently drop duplicates. |
| 6 | **Verifier purpose-communication SHOULD** — Before sending the Authorization Request, the Verifier **SHOULD** communicate the **purpose / context / reason** of the query to the End-User. | §6.2 | Verifier UX must include a purpose statement before triggering the flow (separate from §15.3 privacy SHOULD). |
| 7 | **Pre-Final referenced specs** — Final 1.0 references several non-final dependencies: OpenID Federation 1.0 draft-43, SIOPv2 draft-13, SD-JWT draft-22, SD-JWT VC draft-09, JOSE Fully-Specified Algorithms draft-13. Implementations **SHOULD** continue using the explicitly referenced versions even if upstream specs change, unless updated by a profile or a newer OID4VP version. | §13.4 | Pin these dependency versions in your build system; do **not** auto-bump to upstream "final" releases without re-validating against an OID4VP profile. |
| 8 | **Verifier `direct_post` reply format** — The Verifier's Response URI **MUST** reply with `HTTP 200`, `Content-Type: application/json`, and a JSON body. Draft 20 only stated `HTTP 200` explicitly. | §8.2 | Wallets parse the response strictly as JSON; Verifiers must set `Content-Type: application/json` (not e.g. `text/plain`). |
| 9 | **`access_denied` error triggers** — Final 1.0 explicitly enumerates three triggers for `access_denied`: Wallet lacks the requested credentials, End-User denied consent, End-User authentication failed. Draft 20 inherited the OAuth 2.0 default without OID4VP-specific enumeration. | §8.5 | Wallets and Verifiers should both surface a consistent `access_denied` taxonomy in logs and UX. |

---

## 5. Parameter / Error / Metadata Delta

### 5.1 Added Authorization Request Parameters

| Parameter | Section | Purpose |
|---|---|---|
| `dcql_query` | 5.1 | DCQL query (replaces `presentation_definition`) |
| `request_uri_method` | 5.1 | `get` / `post` for Request URI retrieval |
| `transaction_data` | 5.1, 8.4 | User-authorization binding |
| `verifier_info` | 5.1, 5.11 | Attestations about the Verifier |
| `wallet_nonce` | 5.10 | Replay protection for Request URI POST |
| `wallet_metadata` | 5.10 | Wallet capability advertisement during Request URI POST |
| `expected_origins` | Appendix A | Required for signed DC API requests |
| `response_uri` | 8.2 | Where Wallet POSTs Authorization Response in `direct_post` |

### 5.2 Removed / Replaced Authorization Request Parameters

| Draft 20 | Status in Final 1.0 |
|---|---|
| `presentation_definition` | **Removed** — replaced by `dcql_query` |
| `presentation_definition_uri` | **Removed** — DCQL has no by-reference path |
| `client_id_scheme` | **Removed** — replaced by Client Identifier Prefix in `client_id` |
| `client_metadata_uri` | **Removed** — metadata conveyed via `client_metadata` and/or prefix-specific trust sources |
| `presentation_submission` (response) | **Removed** — `vp_token` is now DCQL-keyed |

### 5.3 Renamed Metadata

| Draft 20 | Final 1.0 |
|---|---|
| Verifier `vp_formats` | `vp_formats_supported` |
| Wallet `client_id_schemes_supported` | `client_id_prefixes_supported` |
| Wallet `presentation_definition_uri_supported` | **Removed** (PE-by-reference path is gone) |

### 5.4 New Metadata Fields

| Field | Used by | Purpose |
|---|---|---|
| `encrypted_response_enc_values_supported` | Verifier (`client_metadata`) | Lists JWE `enc` algorithms accepted; required for `direct_post.jwt` / `dc_api.jwt` unless using default `A128GCM` |
| `client_id_prefixes_supported` | Wallet | Lists supported Client Identifier Prefix values |
| Format-specific algorithm fields | Both | `sd-jwt_alg_values`, `kb-jwt_alg_values` (SD-JWT VC); `issuerauth_alg_values`, `deviceauth_alg_values` (mdoc) — see Appendix B |

### 5.5 Error Code Delta

**Added in Final 1.0**:

| Error code | Triggers |
|---|---|
| `invalid_request_uri_method` | `request_uri_method` is neither `get` nor `post` (case-sensitive) |
| `invalid_transaction_data` | Unknown type, unknown fields, wrong types, invalid values, missing required fields, `credential_ids` mismatch, or referenced credential unavailable |
| `wallet_unavailable` | Returned by a non-Wallet component when the Wallet cannot be invoked |

**Clarified `access_denied` triggers** (newly explicit):
- Wallet lacks the requested credentials,
- End-User denied consent,
- Wallet failed to authenticate the End-User.

**Removed from Draft 20 core path**:
- `invalid_presentation_definition_uri` (PE-by-reference is gone)
- `invalid_presentation_definition_reference` (same reason)

**`invalid_request` triggers also changed**: Final 1.0 fires it when both `dcql_query` and scope-as-DCQL are present, when neither is present (with `response_type=vp_token`), or when `client_id` violates its declared prefix's rules.

---

## 6. Security Considerations Delta (Section 12 → Section 14)

| Topic | Draft 20 (§12) | Final 1.0 (§14) | Change |
|---|---|---|---|
| Replay prevention | §12.1 | §14.1 | Same model (audience + nonce binding); LD example updated to `DataIntegrityProof` / `cryptosuite: ecdsa-rdfc-2019` (was `RsaSignature2018`); `domain` now carries **full prefixed Client Identifier** |
| Session fixation | §12.2 | §14.2 | Same `response_code` mitigation; new explicit limitation analysis (cross-device, multiple-browsers); explicit pointer to DC API as alternative |
| Encrypted unsigned response | §12.5 | §14.5 | Same threat model; rules tightened in §8.3 |
| Verifier own checks | (implicit) | **§14.9 — explicit MUST** | New normative section |
| Always full Client Identifier | (implicit) | **§14.8 — explicit MUST** | New normative section |
| Conformance testing | (not addressed) | **§14.7 — new** | Final 1.0 explicitly references the **OpenID Foundation conformance tools** (https://openid.net/certification/conformance-testing-for-openid-for-verifiable-presentations/) and stresses that security depends on **complete and correct** implementations. Verifier and Wallet teams should plan for certified conformance testing as a release gate. |
| TLS / BCP195 | §12.7 | §14.6 | Same |
| DIF PE JSONPath / `filter` DoS guidance | **§12.6** | **Removed** — PE/JSONPath no longer in request path |

---

## 7. Privacy Considerations (Entirely New — Section 15)

Draft 20 had **no** dedicated Privacy chapter. Final 1.0 adds Section 15 with normative SHOULD/MUST guidance:

| Subsection | Key implementation impact |
|---|---|
| 15.1 User Consent | Wallet **SHOULD** obtain explicit informed consent **before releasing any credential or returning any error** |
| 15.2 Privacy Notice | Wallets **SHOULD** make their privacy notices readily available to the End-User |
| 15.3 Purpose Legitimacy | Verifier **SHOULD** make the purpose specific and visible; Wallet **SHOULD** warn / stop on apparently excessive requests |
| 15.4.1 DCQL Value Matching | Wallet **MUST** make response indistinguishable between user non-consent and value mismatch; **MUST** require user interaction before any response (including mismatch) |
| 15.4.2 Strictly Necessary Claims | Verifiers **SHOULD** use DCQL queries that request only the **minimal set of claims and credentials** needed to fulfill the stated purpose |
| 15.5 Verifier-to-Verifier Unlinkability | Recommends one-time-use credential instances, limited-use policies, batch issuance |
| 15.6 No Fingerprinting | Verifier **SHOULD NOT** fingerprint via wallet metadata; Wallet **SHOULD** strip identifying HTTP headers |
| 15.7 Information Security | Wallet providers and Verifiers **SHOULD** apply operational, functional, and strategic-level controls to ensure integrity, confidentiality, and lifecycle protection of PII (unauthorized access, modification, disclosure, loss, destruction) |
| 15.8 Wallet→Verifier Communication | Wallets **MUST NOT** include PII in HTTP requests unless explicitly required and authorized |
| 15.8.1 / 15.8.2 Trust in Request URI | Wallet **SHOULD** validate Request URI ↔ Client Identifier linkage; **MUST** refuse if linkage cannot be established |
| 15.9 Error Responses (general) | Error responses **SHOULD** avoid sensitive or detailed contextual information that could be used to infer End-User data |
| 15.9.1 `wallet_unavailable` | Inform End-User and obtain consent before returning this error |
| 15.9.2 DC API Error Privacy | DC API errors leak possession info; Wallet **SHOULD NOT** return any OID4VP protocol error without End-User interaction; **SHOULD NOT** return errors before consent for value-matching or issuer-selection requests |
| 15.10 Trust in Issuers | Wallets **SHOULD NOT** auto-fetch unfamiliar URLs from the request; treat as identifiers only |

These are **conformance-relevant** — privacy audits and ecosystem profile compliance will catch implementations that ignore them.

---

## 8. Verifier Migration Checklist

### Request building
- [ ] Inventory all uses of `presentation_definition`, `presentation_definition_uri`, `presentation_submission`, `descriptor_map`.
- [ ] Rewrite each Presentation Definition into a DCQL query (`dcql_query`).
- [ ] Replace DIF PE `filter` (regex / JSON Schema) with DCQL `values` arrays where possible — **and** add server-side post-validation, since `values` is privacy best-effort only.
- [ ] Add `require_cryptographic_holder_binding: false` to Credential Queries that intentionally accept non-VP credentials.
- [ ] Where Issuer trust filtering was done via PE `filter`, migrate to `trusted_authorities`.

### Client identity
- [ ] Migrate `client_id_scheme` parameter to Client Identifier Prefix in `client_id`:
  - `entity_id` → `openid_federation`
  - `did` → `decentralized_identifier`
  - `x509_san_uri` → `x509_hash` (different identifier shape)
  - others retain naming
- [ ] Audit pre-registered `client_id` values: **MUST NOT** start with `<known-prefix>:`.
- [ ] Update audience binding: `aud` (JWT) / `domain` (LD) **MUST** carry the full prefixed identifier.

### Response handling
- [ ] Replace `presentation_submission` parser with DCQL-ID-keyed `vp_token` parser.
- [ ] Honor the `multiple` flag: when omitted/false, the per-key array **MUST** contain exactly one presentation.
- [ ] Tolerate omitted Credential Queries (optional queries with no match are absent from `vp_token`).
- [ ] Implement Section 8.6 validation pipeline: structure → per-presentation format-specific → overall DCQL set.

### Response protection
- [ ] Replace JARM sign / sign+encrypt code with unsigned-encrypted-JWT code.
- [ ] Publish encryption JWKs in `client_metadata.jwks` with `alg` set on each key, unique `kid`s.
- [ ] List supported `enc` algorithms in `encrypted_response_enc_values_supported` (or rely on default `A128GCM`).
- [ ] Use `direct_post.jwt` for redirect flows, `dc_api.jwt` for DC API.

### Request transport
- [ ] Implement / accept `request_uri_method=post` and echo `wallet_nonce` in the signed Request Object.
- [ ] Make `client_id` in the outer request and the Request Object's `client_id` claim identical (including prefix).
- [ ] Set Request Object JOSE `typ` to `oauth-authz-req+jwt`.

### Errors and metadata
- [ ] Add handlers for new errors: `invalid_request_uri_method`, `invalid_transaction_data`, `wallet_unavailable`.
- [ ] Remove handlers for `invalid_presentation_definition_uri`, `invalid_presentation_definition_reference`.
- [ ] Rename advertised metadata: `vp_formats` → `vp_formats_supported`.
- [ ] Verify `response_uri` satisfies the active Client Identifier Prefix's redirect-URI rules (§4.11 #1).
- [ ] Set `Content-Type: application/json` on all Response URI replies; respond with `HTTP 200` + JSON body (§4.11 #8).

### DCQL hygiene
- [ ] Enforce DCQL `id` syntax (alphanumeric / `_` / `-`) and uniqueness rules at query-build time (§4.11 #3).
- [ ] Dedupe claim paths within each Credential Query (§4.11 #5).
- [ ] Communicate the request **purpose / context / reason** to the End-User before sending (§4.11 #6, also relevant to §15.3 privacy).

### DC API (only if used)
- [ ] Set `response_mode=dc_api` (unencrypted) or `dc_api.jwt` (encrypted).
- [ ] Send `expected_origins` for signed requests; do not include `client_id` in unsigned requests.
- [ ] Bind `aud` in returned presentations to `origin:<verifier-origin>`.
- [ ] Choose between JWS Compact (single trust framework) and JWS JSON (multi-trust-framework) serialization for signed requests.

### Profile and conformance
- [ ] Adopt or define a Final 1.0 profile that locks down which optional features are mandatory, allowed credential format identifiers, and any extensions. Without a profile, ecosystem interoperability is not guaranteed.
- [ ] Plan for **OpenID Foundation conformance testing** as a release gate (§14.7). Use the official tools at https://openid.net/certification/conformance-testing-for-openid-for-verifiable-presentations/.
- [ ] Use DCQL queries that request **only the minimal set of claims and credentials** needed for the stated purpose (§15.4.2 — privacy normative SHOULD).

---

## 9. Wallet Migration Checklist

### Request processing
- [ ] Implement DCQL processing: query interpretation, claim matching, credential selection per Section 6.4.
- [ ] Implement Claims Path Pointer evaluation (Section 7) for JSON and mdoc credentials — replacing any JSONPath code.
- [ ] Reject any unsupported `transaction_data` request (do **not** silently ignore).
- [ ] Implement Trusted Authorities Query matching (`aki`, `etsi_tl`, `openid_federation`).

### Client identity
- [ ] Implement `:`-prefix parsing in `client_id` with the unknown-prefix fallback rules:
  - no `:` → pre-registered;
  - `:` present, prefix recognized → apply prefix rules;
  - `:` present, prefix unknown → MAY treat as pre-registered **or** reject (implementer choice — both normative).
- [ ] Use **full prefixed** Client Identifier everywhere — OAuth flow, audience bindings, logs.
- [ ] If using `verifier_attestation` prefix: validate attestation JWT, verify `iss` is trusted, enforce `redirect_uris` exact match if present.

### Request URI POST flow
- [ ] If supporting `request_uri_method=post`: POST over HTTPS with the documented headers; send `wallet_nonce`; verify it is echoed in the returned Request Object.
- [ ] Treat any HTTP error from the Request URI endpoint as a hard termination (Section 5.10.2).
- [ ] Validate that `client_id` in the outer Authorization Request matches `client_id` in the Request Object.

### Holder-binding rules
- [ ] Read `require_cryptographic_holder_binding` per Credential Query.
- [ ] When at least one Credential Query has `require_cryptographic_holder_binding: false`: enforce the `state` rules (≥128-bit entropy, fresh, echoed).
- [ ] In SD-JWT VC: reject `transaction_data` if the Credential Query has `require_cryptographic_holder_binding: false`.

### Response building
- [ ] Build `vp_token` as `{ "<dcql_id>": [<presentation>, ...] }`; no `presentation_submission`.
- [ ] Honor `multiple` cardinality: when omitted/false, return exactly one presentation per Credential Query.
- [ ] Bind every VP to the request's `client_id` (full prefixed) and `nonce` — except in DC API, where audience is `origin:<verifier-origin>`.
- [ ] When using `direct_post.jwt`: encrypt with the JWK chosen from `client_metadata.jwks`; set JWE `alg` from JWK `alg`, copy `kid`, and pull `enc` from `encrypted_response_enc_values_supported` (default `A128GCM`).

### Privacy controls (new)
- [ ] Require user interaction before **any** OID4VP protocol error response in DC API — especially for value-matching and issuer-selection requests.
- [ ] Make value-mismatch responses indistinguishable from non-consent responses.
- [ ] Strip identifying HTTP headers (library/version) from outgoing `request_uri` and `response_uri` calls; never include PII without explicit user authorization.
- [ ] Validate Request URI ↔ Client Identifier linkage when the trust framework allows; refuse otherwise.
- [ ] Do **not** auto-fetch URLs from `trusted_authorities` values that are unfamiliar / untrusted.
- [ ] Make the Wallet's privacy notice readily available to the End-User (§15.2).
- [ ] Apply operational / functional / strategic security controls protecting PII through its lifecycle (§15.7).

### Metadata
- [ ] Rename `client_id_schemes_supported` → `client_id_prefixes_supported`.
- [ ] Rename `vp_formats` → `vp_formats_supported`.
- [ ] Drop `presentation_definition_uri_supported`.

### Robustness and forward-compatibility
- [ ] DCQL parser **MUST** ignore unknown properties at every level (top-level, Credential Query, Credential Set Query, Claims Query, Trusted Authorities Query) — never error on them (§4.11 #4).
- [ ] Implement encryption-failure fallback: if generating `direct_post.jwt` / `dc_api.jwt` encrypted response fails, fall back to an unencrypted error response per §8.2 (§4.11 #2).
- [ ] Pin referenced dependency-spec versions (OpenID Federation draft-43, SIOPv2 draft-13, SD-JWT draft-22, SD-JWT VC draft-09, JOSE Fully-Specified Algorithms draft-13); do not auto-bump (§4.11 #7).

---

## 10. Risk Summary

| Severity | Risk | Mitigation |
|---|---|---|
| **High** | Treating Final 1.0 as an editorial update of Draft 20 | This is a protocol-model migration — inventory all PE / `client_id_scheme` / JARM dependencies first. |
| **High** | Keeping `presentation_submission` / `descriptor_map` correlation logic | Replace with DCQL-ID-keyed `vp_token` lookups. |
| **High** | Not migrating `client_id_scheme` to Client Identifier Prefix | Rewrite client identity validation around prefix parsing. |
| **High** | Audience binding using bare `client_id` instead of full prefixed identifier | Silently breaks replay-protection checks; verify presentation `aud` (JWT) / `domain` (LD) values. |
| **Medium** | Reusing `client_metadata.jwks` keys to verify Authorization Request signatures | Explicitly forbidden in Final 1.0 — these keys are encryption-only. |
| **Medium** | Treating Request URI HTTP errors as recoverable | Section 5.10.2 mandates termination. |
| **Medium** | Carrying forward DIF PE `filter` (regex / JSON Schema) and assuming security parity with `values` | DCQL `values` is privacy best-effort; always validate server-side. |
| **Medium** | Skipping new privacy controls (Section 15) | Passes spec text checks but fails privacy-conformance audits. |
| **Medium** | Treating Final 1.0 as "no profile required" | Final 1.0 mandates profiles for interoperability. |
| **Medium** | Allowing pre-registered `client_id` values that begin with `<known-prefix>:` | Creates parsing ambiguity; reject at registration. |
| **Medium** | Ignoring `multiple` cardinality on `vp_token` | Section 8.1 requires exactly one presentation per key when `multiple` is omitted/false. |
| **Low/Medium** | Assuming `state` is available in DC API responses | DC API does not define `state` for correlation. |
| **Low/Medium** | Hardcoding `direct_post.jwt` as JARM-signed instead of unsigned-encrypted | Final 1.0 mandates the unsigned encrypted JWT profile. |

---

## 11. Appendix-Level Gaps (Scoped: DC API + JWT VC + SD-JWT VC)

Most of the gap analysis above covers main-spec content (Sections 1–15). This section captures the **implementation-relevant deltas in the appendices** for **this profile's scope only**:

- **Included**: Appendix A (Digital Credentials API), Appendix B.1 (W3C VC `jwt_vc_json`), Appendix B.3 (SD-JWT VC `dc+sd-jwt`), brief note on B.3.7 (SD-JWT VCLD).
- **Excluded**: Appendix B.2 (mdoc) — not supported by this profile's Issuer; if added later, read `final-1.0.md` Appendix B.2 directly.
- **Excluded**: Appendix D (DCQL examples — informational only) and Appendix E (IANA registries — publication only).

### 11.1 Digital Credentials API (Appendix A) — relevant when DC API transport is used

Final 1.0 introduces a full **self-contained profile** for OpenID4VP over the W3C Digital Credentials API (and equivalent native APIs like Android Credential Manager). Draft 20 had **no equivalent** — DC API support is entirely new.

> **Note for this profile**: the current cross-device QR-based flow does **not** use DC API. This section is **forward-looking** — read it before adding browser-based or native-app verifier flows.

| Item | Section | Rule |
|---|---|---|
| New response modes | A.2 | `dc_api` (unencrypted) and `dc_api.jwt` (encrypted JWT response per §8.3). |
| Protocol identifiers | A.1 | `openid4vp-v1-unsigned`, `openid4vp-v1-signed`, `openid4vp-v1-multisigned` — explicit version + request-type taxonomy. |
| **Origin-based audience** | A.4 | The presentation `aud` (or `domain` in LD proofs) **MUST** be `origin:<verifier-origin>` (e.g. `origin:https://verifier.example.com/`). **Even for signed requests**. The Client Identifier is **not** used as audience. |
| **`expected_origins`** parameter | A.2 | **REQUIRED** for signed DC API requests; **MUST be ignored** if present in unsigned. Wallet **MUST** match the platform-asserted Origin against this list. |
| `client_id` in unsigned vs signed | A.2 / A.3 | **Unsigned**: `client_id` **MUST** be omitted (Wallet ignores it if present). **Signed**: `client_id` **MUST** be present. |
| Signed-request serializations | A.3.2 | **JWS Compact** for single-trust-framework / single-Client-Identifier; **JWS JSON** for multi-trust-framework / multi-Client-Identifier (per-signature `client_id`, `verifier_info`, prefix-specific params live in **per-signature protected headers**, not the payload). |
| Error response shape | A.4 | Returned in `data` as `{ "error": "<code>" }`. Wallet-generated protocol errors **resolve** the DC API promise (not reject). |
| `state` in DC API | A.2 | `state` is **not defined** for DC API. Verifier **MUST NOT** assume it appears in the response. |
| Signature-validation policy | A.3, 5.9.3 | Wallet **MAY** decide whether to enforce a Client Identifier Prefix's normal Request Object signature validation rules in DC API context, based on trust framework / policy / profile. |
| `origin` Client Identifier Prefix | 5.9.3 | Reserved for DC API context; Wallet **MUST NOT** accept this prefix in requests. |

### 11.2 W3C VC signed as JWT (`jwt_vc_json`) — Appendix B.1

This profile uses `jwt_vc_json`. The format identifier is unchanged from Draft 20, but DCQL introduces format-specific request/metadata rules.

| Item | Section | Rule | Action |
|---|---|---|---|
| **DCQL `meta.type_values`** | B.1.1 | **REQUIRED** in every `jwt_vc_json` Credential Query. Non-empty array of string arrays — each inner array is a fully-expanded type IRI list (after `@context` expansion). All listed types in one inner array **MUST** be present in the credential's `type` (any order, extra types allowed); multiple inner arrays are alternatives. | Replaces Draft 20 PE constraints filtering on `$.vc.type`. Verifier query builders must construct `type_values` arrays. |
| Type expansion behavior | B.1.1 | After `@context` expansion. Types not defined by any `@context` remain unchanged (relative IRIs match as-is). JSON-LD processing **MAY** be skipped if equivalent expansion is achieved. | Implementation choice — full JSON-LD or static-expansion shortcut, but result must be equivalent. |
| **Claims-path scope** | B.1.2 | Claims Path Pointers in DCQL queries against W3C VC are evaluated against the **Verifiable Credential root** — **NOT** the Verifiable Presentation wrapper. | **Silent breaker**: Verifier query builders that walk paths starting at `vp.verifiableCredential[i]` will get empty results. Use VC-root paths like `["credentialSubject", "given_name"]`. |
| Metadata `alg_values` | B.1.3.1.3 | `vp_formats_supported.jwt_vc_json.alg_values` (OPTIONAL, non-empty) — supported JOSE `alg` for the JWT VC/VP. If present, the presented VC/VP `alg` JOSE header **MUST** match one of these. | Both Verifier and Wallet declare; mismatch fails negotiation. |
| Presentation Response binding | B.1.3.1.5 | VP payload **MUST** include `nonce` = request `nonce` and `aud` = **full prefixed Client Identifier** (e.g. `x509_san_dns:client.example.org`). For DC API mode, `aud` is `origin:<origin>` instead. | Wallet must echo `nonce` and use prefixed `client_id` as `aud`. |

### 11.3 SD-JWT VC (`dc+sd-jwt`) — Appendix B.3

This profile uses SD-JWT VC. There ARE substantive Final 1.0 deltas here — the format identifier itself changed and KB-JWT binding rules are codified.

| Item | Section | Rule | Action |
|---|---|---|---|
| **Format identifier `dc+sd-jwt`** | B.3.1 | Final 1.0 standardizes on **`dc+sd-jwt`**. Older SD-JWT VC identifier conventions used by Draft 20-era implementations (e.g., `vc+sd-jwt`) are not used here. | **Critical migration item**: rename the format identifier in your DCQL Credential Queries, in `vp_formats_supported` keys, and in any persistence/cache. Old identifier → no Wallet matches. |
| Holder-binding gating | B.3 intro | If `require_cryptographic_holder_binding: true` (default), Wallet **MUST** return SD-JWT + Key Binding JWT (SD-JWT+KB). SD-JWTs **without** a `cnf` claim cannot be returned in this case. If `false`, Wallet **MAY** return SD-JWT without KB-JWT. | Verifier must decide per-request; Wallet must match credential's `cnf` capability against the request flag. |
| **DCQL `meta.vct_values`** | B.3.5 | **REQUIRED** in every `dc+sd-jwt` Credential Query — non-empty array of allowed `vct` type identifiers. Wallet **MAY** return credentials that **inherit** from any specified type per SD-JWT VC inheritance rules (not just exact match). | Verifier query builders must declare `vct_values`; Wallet matchers must implement SD-JWT VC inheritance. |
| **KB-JWT binding** | B.3.6 | Key Binding JWT **MUST** include: `nonce` = request `nonce`, `aud` = **full prefixed Client Identifier** (or `origin:<origin>` in DC API mode), `iat`, `sd_hash` (SHA-256 hash over the SD-JWT presentation = issuer JWT + selected disclosures). | Wallet must compute `sd_hash` over the **specific selectively-disclosed view** being sent. Verifier validates by recomputing. |
| Metadata fields | B.3.4 | `vp_formats_supported["dc+sd-jwt"]` includes (OPTIONAL non-empty arrays): `sd-jwt_alg_values` (issuer-signed JWT algs) and `kb-jwt_alg_values` (KB-JWT algs). Use **fully-specified algorithm identifiers** per [I-D.ietf-jose-fully-specified-algorithms]. | Both parties declare; algorithms not in the intersection cannot be used. |
| **Transaction data + holder binding** | B.3.3 | Transaction-data mechanism **requires** `require_cryptographic_holder_binding: true`. Wallets **MUST reject** any request that includes `transaction_data` against a Credential Query with `require_cryptographic_holder_binding: false`. | Hard invariant — enforce at request-validation time, not at presentation time. |
| **`transaction_data_hashes` in KB-JWT** | B.3.3.1 | When `transaction_data` is present, the response KB-JWT **MUST** include `transaction_data_hashes`: a non-empty array of base64url-encoded hashes. **Hash input is the original `transaction_data` string as received** (do not base64url-decode before hashing). | Bytes-in / bytes-out — preserve the exact wire bytes. |
| `transaction_data_hashes_alg` | B.3.3.1 | Request **MAY** specify `transaction_data_hashes_alg` (non-empty array of hash IDs from IANA "Named Information Hash Algorithm" registry). If absent, default is **`sha-256`**. Implementations **MUST** support `sha-256`. If the request specified the param, the response KB-JWT **MUST** echo the chosen algorithm in the same parameter. | Default `sha-256`; if a non-default is negotiated, echo it back. |

### 11.4 SD-JWT VCLD (Appendix B.3.7) — only if you adopt the JSON-LD variant

Final 1.0 introduces **SD-JWT VCLD**, an extension of SD-JWT VC that carries Linked Data (JSON-LD) content while keeping selective disclosure. This profile may not need it today, but it's relevant if linked-data semantics are required.

| Item | Section | Rule |
|---|---|---|
| `ld` JWT claim | B.3.7.1 | A new OPTIONAL top-level claim carrying compact JSON-LD business content. |
| Required claims for VCLD | B.3.7.1 | Use SD-JWT-registered claims: `vct` (type), `exp`/`nbf` (validity), `iss`, `status`. |
| Two-step processing model | B.3.7.2 | Step 1 — SD-JWT VC security processing (signatures, validity, status, schema). Step 2 — business processing (use `ld` if present, else use the full SD-JWT VC). |
| Inherits all SD-JWT VC rules | — | Where this spec says "SD-JWT VC", "SD-JWT VCLD" can also be used. |

### 11.5 Migration Checklist Additions (this profile)

Add the following to the existing Verifier and Wallet checklists:

#### Verifier (additions)
- [ ] Replace any old SD-JWT VC format identifier with **`dc+sd-jwt`** in DCQL queries, metadata, and persistence (§11.3).
- [ ] In `jwt_vc_json` Credential Queries, set `meta.type_values` correctly (replaces Draft 20 PE `$.vc.type` filter) (§11.2).
- [ ] In `dc+sd-jwt` Credential Queries, set `meta.vct_values` (REQUIRED) and accept inheritance per SD-JWT VC rules (§11.3).
- [ ] Use **VC-root paths** (e.g., `["credentialSubject", "given_name"]`) in DCQL claims paths for W3C VC — not `vp.verifiableCredential[i]` paths (§11.2).
- [ ] Declare both `sd-jwt_alg_values` and `kb-jwt_alg_values` in `vp_formats_supported["dc+sd-jwt"]` using fully-specified algorithm identifiers (§11.3).
- [ ] Reject any `transaction_data` request that targets a Credential Query with `require_cryptographic_holder_binding: false` (§11.3 — Wallet enforces, but Verifier should not construct such requests).
- [ ] Validate KB-JWT in returned SD-JWT presentations: recompute `sd_hash`, verify `nonce`, verify `aud` = full prefixed Client Identifier (§11.3).

#### Wallet (additions)
- [ ] Implement `dc+sd-jwt` format support (parse, evaluate DCQL `vct_values` with inheritance, produce SD-JWT presentations + KB-JWT) (§11.3).
- [ ] Build the KB-JWT with `nonce`, **full prefixed** `aud`, `iat`, and `sd_hash` over the specific selectively-disclosed view (§11.3).
- [ ] **MUST reject** `transaction_data` requests if the Credential Query has `require_cryptographic_holder_binding: false` (§11.3).
- [ ] Compute `transaction_data_hashes` over the **received `transaction_data` strings as-is** (no base64url decode before hashing). Default algorithm `sha-256`; honor `transaction_data_hashes_alg` if specified (§11.3).
- [ ] For W3C VC: evaluate Claims Path Pointers against the VC root, not the VP wrapper (§11.2).
- [ ] If/when DC API support is added later: implement `expected_origins` validation, origin-based audience binding, and JWS Compact / JWS JSON serialization handling (§11.1 — forward-looking).

---

## 12. Bottom Line

Draft 20 → Final 1.0 is a **protocol-model migration**. The four central shifts — DCQL replacing PE, DCQL-keyed `vp_token` replacing `presentation_submission`, Client Identifier Prefix replacing `client_id_scheme`, and unsigned encrypted JWT replacing JARM — touch nearly every layer of a Verifier and Wallet implementation.

Plan migration in this order:

1. **Inventory** all Draft 20 dependencies (PE structures, response correlation, `client_id_scheme`, JARM).
2. **Rewrite request construction and response parsing** (DCQL + `vp_token` keyed lookup).
3. **Reframe client identity** around Client Identifier Prefix and full-identifier usage everywhere.
4. **Switch response protection** to unsigned encrypted JWT (`direct_post.jwt` / `dc_api.jwt`).
5. **Add new mechanisms** as needed: `request_uri_method=post`, `transaction_data`, `verifier_info`, presentations without holder binding, Trusted Authorities Query.
6. **Adopt or define a profile** — interoperability is gated on it.
7. **Implement Section 15 privacy controls** — they are normative.
8. **(If applicable)** Layer in DC API (Appendix A) — origin-bound audience, signed/unsigned variants, multi-signed JWS JSON.
9. **Re-run conformance tests** against Final 1.0; OpenID Foundation provides certified conformance tools (Section 14.7).
