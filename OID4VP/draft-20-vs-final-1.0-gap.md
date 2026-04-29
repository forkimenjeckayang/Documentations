# OID4VP Gap Document: Draft 20 vs Final 1.0

This document compares the simplified `draft-20.md` and `final-1.0.md` in this directory and highlights implementation-relevant gaps.

## 1) Executive Delta

- Final 1.0 replaces Draft 20's Presentation Exchange request model (`presentation_definition`) with **DCQL** (`dcql_query`).
- Final 1.0 changes response structure: `presentation_submission`/`descriptor_map` are removed from the core response contract; `vp_token` is now keyed by DCQL credential query `id`.
- Final 1.0 introduces richer request/transport features such as `request_uri_method`, `transaction_data`, and Request URI POST capability exchange (`wallet_metadata`, `wallet_nonce`).
- Final 1.0 introduces a full **Digital Credentials API** profile (Appendix A), including `expected_origins` and origin-based audience semantics.
- Final 1.0 replaces Draft 20 `client_id_scheme` framing with **Client Identifier Prefix** processing in `client_id`.
- Final 1.0 removes Draft 20 PE-by-reference path (`presentation_definition_uri`) and related PE-specific errors/metadata.
- Final 1.0 adds a substantial privacy model and stronger conformance/security guidance.
- Final 1.0 changes response protection from Draft 20 JARM sign/sign+encrypt options to an encrypted unsigned JWT profile (`direct_post.jwt` / `dc_api.jwt`).

## 2) Core Protocol Model Changes

### 2.1 Request expression model

**Draft 20**
- Uses `presentation_definition` / `presentation_definition_uri`.
- `scope` can act as alias to a Presentation Definition.

**Final 1.0**
- Uses `dcql_query` as primary request expression.
- Exactly one of `dcql_query` or scope-as-DCQL must be used.
- Adds explicit DCQL structures: credential query, credential set query, claims query, trusted authorities query.
- Adds claim selection semantics (`claims`, `claim_sets`) and credential combination semantics (`credential_sets`).
- Adds explicit holder-binding request control (`require_cryptographic_holder_binding`).
- Replaces DIF PE JSONPath with **Claims Path Pointer** (Section 7), a structured array (strings / `null` / non-negative integers) with deterministic processing and no scripting surface.
- Introduces **Trusted Authorities Query** (`trusted_authorities`) with discrete types: `aki`, `etsi_tl`, `openid_federation` for issuer/trust-framework filtering.
- Introduces format-specific DCQL `meta` parameters as first-class request fields:
  - W3C VC: `type_values`
  - mdoc: `doctype_value`
  - SD-JWT VC: `vct_values`
- Introduces format-aware claims-query fields (e.g., mdoc `intent_to_retain` is now a DCQL claims-query field instead of a DIF PE constraint).

**Gap impact**
- Verifier request builders and Wallet selection engines must migrate from PE semantics to DCQL semantics.

### 2.2 Response model

**Draft 20**
- Response includes required `vp_token` plus required `presentation_submission`.
- Uses `descriptor_map` paths for correlation.

**Final 1.0**
- Response includes required `vp_token` only (OID4VP-specific parameter set).
- `vp_token` is a JSON object: key = DCQL credential query ID, value = array of matching presentations.
- Optional credential query results can be omitted from `vp_token` if no match is returned.

**Gap impact**
- Verifier parsers must switch from descriptor-path mapping to DCQL-ID keyed parsing.

### 2.3 Client identification model

**Draft 20**
- Uses separate `client_id_scheme` request parameter.

**Final 1.0**
- Uses Client Identifier Prefix embedded in `client_id` (`<prefix>:<orig_client_id>`).
- Prefix set is reworked to `pre-registered`, `redirect_uri`, `openid_federation`, `decentralized_identifier`, `verifier_attestation`, `x509_san_dns`, `x509_hash` (and reserves `origin` for DC API context).
- Draft 20 schemes `entity_id`/`did`/`x509_san_uri` are no longer used as-is; their semantics are absorbed/reframed via new prefix naming and rules.

**Gap impact**
- Client identity validation and metadata lookup logic must be rewritten around prefix parsing and full `client_id` handling.

**Additional Final 1.0 prefix-parsing rules (often missed)**
- Pre-registered `client_id` values **MUST NOT** begin with a supported Client Identifier Prefix immediately followed by `:` (prevents collision with prefix taxonomy).
- If `client_id` contains `:` but the substring before the first `:` is not a recognized prefix, Wallet MAY treat it as a pre-registered client OR reject the request (implementation choice; both are normatively allowed).
- In OpenID4VP over DC API, Wallet MAY decide whether to enforce a prefix's normal Request Object signature validation rules based on its trust framework / policy / profile (i.e., DC API context can relax/override the per-prefix signature requirement that would apply in redirect-based flows).

## 3) Parameter and Error Delta Matrix

### 3.1 Added in Final 1.0 (major)

- `dcql_query`
- `request_uri_method` (`get` / `post`)
- `transaction_data`
- `verifier_info`
- `wallet_nonce` and `wallet_metadata` (Request URI POST interaction)
- `expected_origins` (DC API profile)
- `client_id_prefixes_supported` (wallet metadata)
- `encrypted_response_enc_values_supported` (verifier metadata/client_metadata)
- `invalid_request_uri_method` (error)
- `invalid_transaction_data` (error)
- `wallet_unavailable` (error)

### 3.2 Removed/Replaced from Draft 20 core path

- `presentation_definition` -> replaced by `dcql_query` model
- `presentation_definition_uri` -> replaced by DCQL-based requesting model
- `presentation_submission` / `descriptor_map` -> replaced by DCQL-ID keyed `vp_token`
- `client_id_scheme` -> replaced by Client Identifier Prefix in `client_id`
- `client_metadata_uri` -> removed from Final 1.0 core request model (metadata conveyed via `client_metadata` and/or prefix-specific trust sources)
- Wallet metadata `client_id_schemes_supported` -> `client_id_prefixes_supported`
- Verifier metadata `vp_formats` -> `vp_formats_supported`
- Wallet metadata `presentation_definition_uri_supported` removed with PE-by-reference path
- Errors `invalid_presentation_definition_uri` and `invalid_presentation_definition_reference` removed from core path
- Draft 20 schemes `entity_id`, `did`, and `x509_san_uri` replaced by Final 1.0 prefix taxonomy
- DIF PE `path_nested` mechanism removed (no longer needed without `descriptor_map`)
- Draft 20 Section 12.6 (DIF Presentation Exchange 2.0.0 considerations, including JSONPath/script-execution and Filters DoS guidance) is dropped because PE/JSONPath is no longer in the request path

### 3.3 Notable normative behavior shifts

- `response_mode` is required in Final 1.0 simplified text.
- Request Object JOSE `typ` is strictly required as `oauth-authz-req+jwt`.
- Unknown request parameters are ignored except `transaction_data` (unsupported wallets must error).
- Final 1.0 introduces explicit GET/POST request_uri retrieval behavior and related error handling.
- Final 1.0 adds explicit rules for presentations without cryptographic holder binding (state requirements and replay-risk tradeoff).
- `state` handling is tighter in Final 1.0: conditionally REQUIRED for non-holder-binding requests (except DC API), not just optional correlation guidance.
- Final 1.0 mandates use of full client identifier (including prefix) in client identification/security checks.
- Response encryption model is now explicitly encrypted JWT response handling (not Draft 20's JARM sign/sign+encrypt framing).
- If a Request Object contains `iss`, Wallet ignores it and uses `client_id` as authoritative identifier.
- `client_metadata` handling is tighter: authoritative external metadata wins, and unknown metadata members are ignored unless profile-defined.
- Audience semantics change in returned presentations:
  - In redirect/`direct_post` mode, `aud` MUST equal full Client Identifier including prefix (not bare `client_id`).
  - In DC API mode, `aud` MUST be `origin:<verifier-origin>` (origin-bound audience), not the client identifier.
- `wallet_nonce` is a new replay-protection mechanism for Request URI POST: Wallet supplies it; Verifier MUST echo it inside the signed Request Object; mismatch terminates processing.
- Wallet capability advertisement via Request URI POST adds prefix-aware rules:
  - `authorization_encryption_alg_values_supported`
  - `authorization_encryption_enc_values_supported`
  - `request_object_signing_alg_values_supported` (MUST NOT be advertised when active prefix forbids signed requests).

### 3.4 Additional deltas often missed

- Final 1.0 adds explicit verifier-side conformance obligations:
  - Verifier MUST NOT rely on Wallet-side DCQL filtering alone.
  - Verifier MUST perform independent security checks on returned credentials/presentations.
- Final 1.0 adds implementation correctness/conformance testing emphasis in security guidance.
- Final 1.0 strengthens privacy/error guidance for value matching and protocol errors (reduce leakage, typically require user interaction before sensitive error outcomes).

### 3.5 Finer-grained normative deltas (often-missed)

These are smaller normative items not always called out at the high-level migration view, but they affect concrete implementation/conformance behavior:

- Encrypted response (Section 8.3) JOSE binding rules:
  - Wallet selects Verifier public key from `client_metadata.jwks` (or prefix-allowed source).
  - Selected JWK `alg` MUST be present.
  - JWE header `alg` MUST equal chosen JWK `alg`.
  - If chosen JWK has `kid`, JWE header MUST include the same `kid`.
  - JWE `enc` is taken from `encrypted_response_enc_values_supported`; default is `A128GCM` if absent.
  - For ECDH-based JWE algorithms, `apu`/`apv` feed KDF and are bound via AEAD tag computation; HPKE-based JOSE approaches are explicitly allowed.
- `client_metadata.jwks` security rule: keys in `client_metadata.jwks` MUST NOT be used to verify signatures of signed Authorization Requests, and each JWK MUST include a unique `kid` within the request context.
- Request URI Error Response (Section 5.10.2): any HTTP error from the Request URI endpoint MUST cause the Wallet to terminate processing.
- `direct_post.jwt` encrypted-response error fallback (Section 8.3.1): if Wallet cannot generate an encrypted response, it MAY send an unencrypted error response per Section 8.2.
- `direct_post` reply from Verifier endpoint (Section 8.2) is normatively `HTTP 200` + `Content-Type: application/json` + JSON body; in Draft 20 only HTTP 200 was explicit.
- DC API error response shape (Appendix A.4): protocol errors are returned in `data` as `{"error": "<error_code>"}`; the Wallet-generated protocol error still resolves the DC API call (fulfilled promise) rather than appearing as a transport failure.
- DC API and `state`: `state` is not defined for the DC API flow, so Verifier MUST NOT assume `state` appears in the response.
- DC API `expected_origins` ignore rule: if `expected_origins` is included in an unsigned DC API request, Wallet MUST ignore it; it is REQUIRED only for signed DC API requests.
- DC API signed/unsigned `client_id` rule: in unsigned DC API requests, `client_id` MUST be omitted (and Wallet MUST ignore it if present); in signed DC API requests, `client_id` MUST be present.
- "Confidential client" terminology in Draft 20 is reframed in Final 1.0 as a "key management requirement": prefixes `openid_federation`, `decentralized_identifier`, `verifier_attestation`, `x509_san_dns`, `x509_hash` require Verifier capability to securely store private keys (impacting public-client/native-app architectures).
- Non-holder-binding state entropy: when at least one presentation without cryptographic holder binding is requested (and DC API is not in use), `state` MUST be a cryptographically strong pseudo-random value with at least 128 bits of entropy, fresh per request.
- `transaction_data.credential_ids` multi-ID rule: if multiple `credential_ids` are listed in a transaction-data object, Wallet MUST use only one referenced credential to authorize that transaction.
- `nonce` and `state` character set: both are limited to ASCII URL-safe characters (letters, digits, `-`, `.`, `_`, `~`) in Final 1.0.
- DCQL `id` character set: credential query and claim query `id` values are restricted to alphanumeric, `_`, `-`, and MUST be unique within their scope.
- DCQL extensibility rule: implementations MUST ignore unknown DCQL properties at any level.
- `dcql_query` vs scope-as-DCQL exclusivity is enforced as `invalid_request` (paralleling Draft 20's three-way PE exclusivity); `response_type=vp_token` without either is also `invalid_request`.
- `access_denied` error gets explicit OID4VP examples in Final 1.0:
  - Wallet lacks requested credentials,
  - End-User denied consent,
  - End-User authentication failed.
- Wallet POST to Request URI endpoint (Section 5.10) requires:
  - HTTP `POST` over `https`,
  - `Content-Type: application/x-www-form-urlencoded`,
  - `Accept: application/oauth-authz-req+jwt`,
  - UTF-8 body encoding.
- Request URI POST consistency rule: `client_id` in outer Authorization Request and `client_id` claim in returned Request Object MUST be identical (including prefix); mismatch terminates processing.
- mdoc transaction-data + KeyAuthorizations: if request includes a transaction-data type whose required data element is not authorized via mdoc KeyAuthorizations, Wallet MUST reject the request as unsupported transaction-data type.
- mdoc `OpenID4VPDCAPIHandoverInfo` origin rule: the request `origin` element MUST NOT be prefixed with `origin:` inside the handover structure (even though DC API audience uses the `origin:` prefix).
- mdoc handover JWK thumbprint rule: include verifier encryption-key thumbprint when using `dc_api.jwt` (or encrypted redirect responses); use `null` for unencrypted modes.
- SD-JWT VC transaction-data hashing default: if `transaction_data_hashes_alg` is absent in the request, default hash function for KB-JWT `transaction_data_hashes` is `sha-256`; implementations MUST support `sha-256`.
- SD-JWT VC transaction-data hashing input: hashes are computed over the original `transaction_data` string as received (no base64url decode before hashing).
- Verifier Info PoP models (Section 5.11.1): two PoP styles are normatively defined - claim-bound attestations (binding via claims, e.g., JWT `sub`) and key-bound attestations (Verifier signs PoP including request `nonce` and `client_id`).
- Trusted Authorities `aki` matching detail: value is base64url-encoded KeyIdentifier of X.509 AuthorityKeyIdentifier; raw bytes must match an AuthorityKeyIdentifier in some certificate in the credential's chain (full or partial chain allowed).
- Trusted Authorities `etsi_tl` matching detail: matches when chain contains at least one certificate covered by the referenced ETSI Trusted List (including cascading referenced lists).
- `verifier_info.credential_ids` semantics: if omitted, attestation applies to all requested credentials; if present, applies only to listed DCQL credential query IDs.
- `request_uri_method` MUST NOT be present if `request_uri` is absent (parameter-pairing rule, paralleling `response_uri`/`redirect_uri` exclusivity).
- DCQL Credential Query `multiple` parameter (Section 6.1): boolean (default `false`) controlling whether more than one credential may be returned for a single Credential Query; when `false`/omitted, the response array per `vp_token` key MUST contain exactly one presentation.
- Credential Set Query verifier UX rule (Section 6.2): Verifier SHOULD communicate purpose/context/reason of the query to the End-User before sending the request (UX/normative-SHOULD rather than just consent guidance).
- ISO mdoc value-matching conversion rule (Section 6.3): when matching `values` against ISO mdoc credentials, matching uses the JSON form of the CBOR value following RFC8949 Section 6.1; behavior is out of scope where conversion is undefined.
- `response_uri` policy reuse (Section 8.2): the `response_uri` value MUST be one the client would be allowed to use as a redirect URI under Section 5.9 (prefix) rules; spec text referring to Redirect URI also applies to Response URI in `direct_post` context.
- VP Token validation procedure (Section 8.6) is rewritten around DCQL-keyed `vp_token`:
  - Step 1: validate VP Token structure per Section 8.1 (DCQL-ID keyed object; per-key array cardinality matches `multiple`).
  - Step 2: per-presentation format-specific validation (integrity, authenticity, request conformance, holder-binding proof unless explicitly waived, replay protections, trust/policy/revocation).
  - Step 3: validate overall set against DCQL selection rules (Section 6.4).
  - Failure handling: discard failing single presentation, but reject entire VP Token on token-level or overall-response failures.
- Profile-requirement statement (Section 3): Final 1.0 explicitly states that OID4VP is a framework and **requires profiles for interoperability** (profiles must define which optional features are used, allowed parameter values such as credential format identifiers, and any extensions). Draft 20 did not formalize this profile dependency.
- Multi-scope DCQL ID uniqueness (Section 5.5): when multiple `scope` values that each map to a DCQL query are used together, the underlying DCQL queries may be combined; credential identifiers and claim identifiers across those combined DCQL queries **MUST** be unique (no collisions across the merged set), so the Verifier can unambiguously identify requested credentials in responses.
- DCQL claims-query duplication rule (Section 6.1): Verifier **MUST NOT** point to the same claim more than once in one Credential Query, and Wallet **SHOULD** ignore duplicate claim queries.
- DCQL `values` security posture (Section 6.4.1): Verifier **MUST** treat claim-query `values` restrictions as a **privacy best-effort only, not as a security control**; final value-filtering behavior can depend on Wallet/End-User choices, so authorization decisions cannot rely on `values` matching alone.

### 3.6 Privacy normative deltas (Section 15)

Final 1.0 adds a dedicated Privacy Considerations chapter with multiple distinct controls; the ones with the strongest implementation impact are:

- Section 15.1 User Consent: explicit informed End-User consent SHOULD be obtained before releasing any credential/presentation **or** returning an error.
- Section 15.3 Purpose Legitimacy: Verifier SHOULD ensure purpose is specific and communicated; Wallet SHOULD warn or stop if request appears unauthorized/excessive.
- Section 15.4.1 DCQL Value Matching:
  - Wallet MUST take precautions against value leakage,
  - response behavior MUST be indistinguishable between user non-consent and value mismatch,
  - End-User interaction is required before any response (including mismatch) to prevent silent probing.
- Section 15.5 Verifier-to-Verifier Unlinkability: Wallet anti-linking strategies (one-time use credential instances, limited-use policies tying same instance to same Verifier, batch issuance patterns) are normatively recommended.
- Section 15.6 No Fingerprinting:
  - Verifier SHOULD NOT fingerprint End-User via wallet metadata/interaction details,
  - Wallet SHOULD implement anti-fingerprinting controls when fetching Request Objects,
  - Wallet SHOULD limit side-channel disclosure via Response URI interactions (e.g., user-agent details).
- Section 15.8 Wallet-to-Verifier Communication:
  - Wallets SHOULD send minimal information and avoid extra HTTP fingerprinting headers (e.g., library/version) when calling `request_uri` / `response_uri`,
  - Wallets MUST NOT include PII in HTTP requests unless explicitly required and authorized.
- Section 15.8.1/15.8.2 Trust in Request URI:
  - Wallet SHOULD validate Request URI is properly associated with the Client Identifier and authorized for the request,
  - if linkage cannot be established, Wallet MUST refuse the request,
  - untrusted/unrecognized Request URI endpoints SHOULD be rejected or require End-User confirmation.
- Section 15.9 Error Responses: error responses SHOULD avoid sensitive/context-rich details that could reveal End-User data.
- Section 15.9.1 `wallet_unavailable`: when a non-wallet component returns `wallet_unavailable`, the End-User SHOULD be informed and consent before returning that error to the Verifier.
- Section 15.9.2 DC API error privacy: DC API protocol errors can leak possession information; Wallet SHOULD NOT return OID4VP protocol errors without End-User interaction (especially before consent for value-matching or issuer-selection constraints), and MAY substitute platform-level cancel to reduce leakage.
- Section 15.10 Trust in Issuers: online-resolution-based trusted-authority mechanisms can leak usage patterns; Wallets SHOULD NOT auto-fetch unfamiliar/untrusted URLs from the verifier request and SHOULD treat such URLs as identifiers rather than fetch targets; ecosystems SHOULD align trusted-authority mechanism privacy properties with their privacy goals.

## 4) Structural/Section-Level Gaps

Major additions in Final 1.0:

- Section 6: Digital Credentials Query Language (DCQL)
- Section 7: Claims Path Pointer
- Section 15: Privacy Considerations
- Appendix A: OpenID4VP over Digital Credentials API
- Appendix D: DCQL Query Examples
- Section 13.4: guidance for handling pre-final specification versions
- Expanded format appendix with stronger SD-JWT VC treatment
- New terminology added in Section 2 with implementation impact:
  - **Origin** (web origin = scheme + host + port; native app origin = linked web origin or platform-specific URI) — used by DC API audience binding.
  - **Digital Credentials API (DC API)** — covers W3C DC API on web and equivalent native APIs (e.g., Android Credential Manager).
  - **Credential Format Identifier** — first-class term replacing implicit "format" usage in Draft 20.
  - **Wallet typology** — Wallet may be local, self-hosted remote, or third-party remote (affects threat-model/architecture decisions).
- Expanded IANA registry coverage, including:
  - new OAuth parameters: `dcql_query`, `client_metadata`, `request_uri_method`, `transaction_data`, `wallet_nonce`, `response_uri`, `verifier_info`, `expected_origins`
  - new error registrations: `vp_formats_not_supported`, `invalid_request_uri_method`, `wallet_unavailable`
  - new client metadata params: `encrypted_response_enc_values_supported`, `vp_formats_supported`
  - new JOSE header registrations: `client_id` (and OID4VP use of `jwt`)
  - new URI scheme registration: `openid4vp` (provisional)
  - new JWT claim registration: `ld` (SD-JWT VCLD)

Major reworks in Final 1.0:

- Authorization Request section rewritten around DCQL + prefix model + request_uri_method.
- Response section rewritten around DCQL-keyed `vp_token` and transaction-data handling.
- Security section expanded with explicit conformance and full-client-identifier checks.
- Request/response security around encryption shifted to encrypted JWT profile semantics.

Additional Appendix A (DC API) constructs not previously highlighted:

- DC API exchange protocol identifier format `openid4vp-v<version>-<request-type>`, with concrete values:
  - `openid4vp-v1-unsigned`
  - `openid4vp-v1-signed`
  - `openid4vp-v1-multisigned`
- DC API serialization choice for signed requests:
  - JWS Compact Serialization (Appendix A.3.2.1) for single client identity context.
  - JWS JSON Serialization (Appendix A.3.2.2) for multi-signed/multi-client-identity scenarios, with normative rules for which parameters live in per-signature protected headers (`client_id`, `verifier_info`, prefix-specific params like `trust_chain`) versus the JWS payload.
- DC API response modes `dc_api` (unencrypted) and `dc_api.jwt` (encrypted JWT), where `response` member carries the encrypted JWT in `dc_api.jwt`.

## 5) Credential-Format Coverage Gap

**Draft 20 emphasis**
- W3C VC, mdoc, and AnonCreds are highlighted in examples/text.

**Final 1.0 emphasis**
- W3C VC, mdoc, and **IETF SD-JWT VC** are strongly profiled.
- Format-specific metadata/rules are more explicit (especially mdoc and SD-JWT VC transaction-data behavior).
- Draft 20's explicit AnonCreds emphasis is not carried forward as a first-class profiled appendix track in Final 1.0 simplified text.
- New SD-JWT VC format identifier `dc+sd-jwt` (replaces older SD-JWT VC identifier conventions assumed in Draft 20).
- New SD-JWT VC profile fields for transaction data:
  - request: `transaction_data_hashes_alg`
  - response (KB-JWT): `transaction_data_hashes`, `transaction_data_hashes_alg`
- Transaction data with SD-JWT VC requires cryptographic holder binding; Wallet MUST reject `transaction_data` when `require_cryptographic_holder_binding=false`.
- New mdoc-specific algorithm metadata: `issuerauth_alg_values`, `deviceauth_alg_values`.
- New mdoc SessionTranscript handover structures specific to OID4VP:
  - `OpenID4VPHandover` (redirect-based invocation)
  - `OpenID4VPDCAPIHandover` (DC API invocation)
- New SD-JWT VCLD profile (Appendix B.3.7) and new `ld` JWT claim for compact JSON-LD payloads.

**Additional format-specific normative deltas (often missed)**

- W3C VC claims-path scope (B.1.2): Claims Path Pointers in DCQL queries against W3C VC are evaluated against the **Verifiable Credential root**, not the Verifiable Presentation wrapper. Verifier query-builders that previously walked into `vp.verifiableCredential[i]` paths must change.
- mdoc presentation response encoding (B.2.5): each `vp_token` entry value for `mso_mdoc` is the **base64url-encoded** mdoc `DeviceResponse` CBOR structure (Draft 20 examples did not standardize a single transport encoding for the `vp_token` value at this level).
- mdoc handover SessionTranscript invariants (B.2.6.1, B.2.6.2):
  - `DeviceEngagementBytes` MUST be `null`.
  - `EReaderKeyBytes` MUST be `null`.
  - `Handover` MUST be `OpenID4VPHandover` (redirect) or `OpenID4VPDCAPIHandover` (DC API).
- mdoc metadata: new format-specific keys under `vp_formats_supported["mso_mdoc"]`:
  - `issuerauth_alg_values` (matches IssuerAuth COSE `alg`, or fully-specified alg+curve combination).
  - `deviceauth_alg_values` (matches DeviceSignature/DeviceMac COSE `alg`, fully-specified alg+curve combination, or HMAC 256/256 with private-use COSE alg identifiers `-65537`..`-65545` mapped to specific device-key curves: P-256, P-384, P-521, X25519, X448, brainpool variants — these are private-use values in this spec context that may later be superseded by IANA registration).
- SD-JWT VC metadata: new format-specific keys under `vp_formats_supported["dc+sd-jwt"]`:
  - `sd-jwt_alg_values` (fully-specified algorithm identifiers for issuer-signed SD-JWT).
  - `kb-jwt_alg_values` (fully-specified algorithm identifiers for the Key Binding JWT).
- SD-JWT VC `vct_values` inheritance: Wallet may return credentials that inherit from the specified `vct` types per SD-JWT VC inheritance rules (not just exact-match credential types).

## 6) Implementation Impact

### Verifier-side changes

- Replace PE request construction with DCQL query generation.
- Replace `presentation_submission` parser with DCQL-ID keyed `vp_token` parser.
- Implement prefix-based `client_id` processing and updated metadata fields.
- Add support for new request parameters (`request_uri_method`, `transaction_data`, `verifier_info`) as needed.
- Add support for new errors and handling rules.
- Remove PE-specific error handling and `presentation_definition_uri` retrieval logic.
- Add DC API support paths when targeting browser/native DC API invocation.
- Update Request Object handling to enforce JOSE `typ=oauth-authz-req+jwt` and `iss`-ignore behavior.
- Update response protection implementation from JARM assumptions to Final 1.0 encrypted unsigned JWT behavior.

### Wallet-side changes

- Implement DCQL processing (query interpretation, matching, selection).
- Implement `transaction_data` processing and rejection behavior.
- Implement request_uri POST capability exchange (`wallet_metadata`, `wallet_nonce`) where applicable.
- Implement updated prefix model and associated signature/metadata rules.
- Enforce `state` handling rules when non-holder-binding presentations are requested.
- Implement expanded privacy and consent requirements from Section 15.
- Implement stricter metadata precedence/ignore rules (`client_metadata` vs authoritative trust-source metadata).
- Implement DC API signed/unsigned differences (`client_id` omitted for unsigned; `expected_origins` required for signed).
- Implement prefix-fallback parsing rules (no-`:` -> pre-registered; unknown-`:`-prefix -> reject or treat as pre-registered; pre-registered IDs MUST NOT collide with reserved prefix names).
- Implement anti-fingerprinting controls on Request URI and Response URI HTTP calls (no library/version headers; no PII unless required and consented).
- Implement value-matching privacy controls (indistinguishable mismatch vs non-consent outcomes; require user interaction before any DC API protocol error).
- Implement anti-linking strategies (one-time / limited-use credential instances) where supported by issued credentials.
- Implement Request URI linkage validation when trust framework allows it; refuse request when linkage cannot be established.

### Testing/conformance updates

- Add DCQL semantic tests (query validity, claim matching, credential set logic).
- Add response shape tests for DCQL-ID keyed `vp_token`.
- Add prefix parsing and full-client-id security tests.
- Add request_uri_method GET/POST behavior tests.
- Add transaction_data positive/negative tests (`invalid_transaction_data`).
- Add DC API-specific tests (`expected_origins`, origin audience binding) if DC API is used.
- Remove/replace PE-oriented tests (`presentation_submission` and descriptor-map/path assertions).
- Add tests for Request Object `iss`-ignore behavior and mandatory JOSE `typ`.
- Add privacy/error-leakage tests for value-matching and protocol error timing/consent behavior.
- Add Claims Path Pointer processing tests (string/null/integer rules, error cases).
- Add Trusted Authorities Query tests (`aki`, `etsi_tl`, `openid_federation`).
- Add audience-binding tests for redirect mode (full prefixed `client_id`) and DC API mode (`origin:<origin>`).
- Add `wallet_nonce` echo/match tests for Request URI POST.
- Add mdoc handover tests for `OpenID4VPHandover` and `OpenID4VPDCAPIHandover`.
- Add DC API protocol identifier negotiation tests for `openid4vp-v1-unsigned`, `openid4vp-v1-signed`, and `openid4vp-v1-multisigned`.
- Add DC API JWS JSON Serialization (multisigned) parsing/validation tests, including per-signature header parameter placement rules.
- Add Wallet termination tests for Request URI HTTP error responses (Section 5.10.2).
- Add `direct_post.jwt` encryption-failure fallback tests (unencrypted error response path).
- Add encrypted response JOSE binding tests (`alg` match, `kid` match, `enc` default `A128GCM`).
- Add `client_metadata.jwks` misuse tests (must not verify request signatures).
- Add mdoc transaction-data + KeyAuthorizations rejection tests.
- Add SD-JWT VC `transaction_data_hashes` algorithm and input-canonicalization tests.
- Add prefix-fallback parsing tests (no `:`, unknown prefix, pre-registered ID colliding with reserved prefix name).
- Add W3C VC claims-path-scope tests (paths evaluated against VC root, not VP wrapper).
- Add mdoc `vp_token` base64url-encoded `DeviceResponse` carriage tests.
- Add mdoc handover SessionTranscript null-invariant tests (`DeviceEngagementBytes`, `EReaderKeyBytes`).
- Add mdoc metadata fully-specified alg + curve / private-use COSE alg identifier (`-65537`..`-65545`) tests for `deviceauth_alg_values`.
- Add SD-JWT VC `sd-jwt_alg_values` / `kb-jwt_alg_values` metadata negotiation tests.
- Add `response_uri` policy-reuse tests (response URI must satisfy redirect-URI policy of active prefix).
- Add `multiple` cardinality tests on `vp_token` per credential query (default false -> exactly one entry).
- Add ISO mdoc value-matching tests using JSON form of CBOR (RFC8949 Section 6.1) value conversion.
- Add VP Token validation pipeline tests aligned to Section 8.6 (structure -> per-presentation -> overall set -> failure handling).
- Add privacy-leakage tests: indistinguishable non-consent vs value-mismatch responses, and DC API protocol-error gating behind End-User interaction.
- Add anti-fingerprinting tests on Request URI/Response URI HTTP calls (no extra identifying headers, no PII without consent).

## 7) Migration Checklist (Draft 20 -> Final 1.0)

- Inventory all uses of `presentation_definition`, `presentation_definition_uri`, `presentation_submission`, and `descriptor_map`.
- Create DCQL equivalents for each existing presentation request pattern.
- Refactor verifier response processing to DCQL-ID keyed `vp_token`.
- Refactor client identity handling from `client_id_scheme` to prefix-based `client_id`.
- Update metadata contracts:
  - `vp_formats` -> `vp_formats_supported`
  - `client_id_schemes_supported` -> `client_id_prefixes_supported`
- Implement/validate new request and error behaviors:
  - `request_uri_method`
  - `transaction_data`
  - `invalid_request_uri_method`
  - `invalid_transaction_data`
  - `wallet_unavailable`
- Migrate client identifier schemes:
  - `entity_id` -> `openid_federation`
  - `did` -> `decentralized_identifier`
  - `x509_san_uri` -> Final 1.0 x509 prefix model (not retained as Draft 20 name)
- Add Privacy Considerations compliance checks (consent, minimization, unlinkability guidance).
- Audit `client_id` issuance and acceptance to enforce: pre-registered values must not collide with reserved Client Identifier Prefix names (no leading `<reserved-prefix>:`).
- Update VP Token validation pipeline to Section 8.6 model: structure check (DCQL-keyed, `multiple` cardinality), per-presentation format-specific validation, overall DCQL-set satisfaction check, with appropriate single-presentation discard vs full-token-rejection semantics.
- Update mdoc transport: encode `DeviceResponse` as base64url for `vp_token` entries; emit SessionTranscript with `DeviceEngagementBytes`/`EReaderKeyBytes` set to `null` and the appropriate OID4VP handover variant.
- Update mdoc metadata: declare `issuerauth_alg_values` / `deviceauth_alg_values`, including (where used) private-use COSE alg identifiers `-65537`..`-65545` for HMAC 256/256 device-auth combinations.
- Update SD-JWT VC metadata: declare `sd-jwt_alg_values` / `kb-jwt_alg_values`; honor `vct_values` inheritance.
- Update W3C VC matchers: evaluate DCQL Claims Path Pointers against VC root (not VP wrapper).
- Validate `response_uri` against the active prefix's redirect-URI policy when `direct_post`/`direct_post.jwt` is used.
- Apply `multiple` cardinality rule when serializing `vp_token` (omitted/false -> exactly one entry per credential query key).
- Define and adopt a Final 1.0 profile (interoperability is gated on profile choices: which optional features, allowed credential format identifiers, extensions).
- Remove deprecated PE paths and errors from code, docs, and conformance tests.
- Re-run interop and conformance testing against Final 1.0 behavior.

## 8) Risk Summary

- **High**: Treating Final 1.0 as an editorial update instead of protocol-model migration (PE -> DCQL).
- **High**: Keeping old response correlation logic based on `presentation_submission`.
- **High**: Incomplete migration of `client_id` identity semantics and prefix-specific validation.
- **Medium**: Missing new error/transport paths (`request_uri_method`, `transaction_data`).
- **Medium**: Shipping without Final 1.0 privacy controls and related UX/error behavior updates.
- **Medium**: Carrying forward DIF PE JSONPath assumptions instead of adopting the Claims Path Pointer model.
- **Medium**: Wrong audience binding (e.g., bare `client_id` instead of full prefix or DC API `origin:` form), which silently breaks replay protection checks.
- **Medium**: Reusing `client_metadata.jwks` keys to verify signed Authorization Requests (explicitly forbidden in Final 1.0).
- **Medium**: Treating Request URI HTTP errors as recoverable instead of terminating processing (Section 5.10.2).
- **Medium**: Hardcoding only JWS Compact Serialization for DC API and silently failing on `openid4vp-v1-multisigned` (JWS JSON Serialization) requests.
- **Medium**: Evaluating W3C VC DCQL claim paths against VP wrapper instead of VC root (silently no-matches valid credentials).
- **Medium**: Skipping the new privacy controls (value-matching indistinguishability, anti-fingerprinting, online trust-authority resolution gating) — passes spec text checks but fails privacy-conformance/audit reviews.
- **Medium**: Treating Final 1.0 as "no profile required" — Final 1.0 explicitly mandates profiles for interoperability; building against the framework alone yields ecosystem-incompatible deployments.
- **Low/Medium**: Assuming `state` is available in DC API responses for correlation (it is not defined for DC API).
- **Low/Medium**: Allowing pre-registered `client_id` values that begin with a reserved prefix + `:` (forbidden in Final 1.0; creates parsing ambiguity).
- **Low/Medium**: Hardcoding mdoc `vp_token` carriage as raw CBOR / hex instead of base64url-encoded `DeviceResponse`.
- **Low/Medium**: Returning more than one presentation per Credential Query when `multiple` is omitted/false (violates Section 8.1 cardinality rule).

## 9) Bottom Line

Draft 20 -> Final 1.0 is a substantive protocol shift. The largest migration items are DCQL adoption, response model changes, prefix-based client identity handling, and new transport/privacy/conformance requirements.
