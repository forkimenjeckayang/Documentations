# OID4VP Draft 20

## Part 1 - Introduction and Terminology (Simplified)

### 1) What this spec is for

This specification defines how to use **OAuth 2.0** to request and receive **Verifiable Presentations (VPs)** that are derived from **Verifiable Credentials (VCs)**.

In short:
- OAuth 2.0 provides the protocol flow ("rails")
- OID4VP adds a credential-presentation layer on top
- A Verifier can ask a Wallet to present credentials in a secure and developer-friendly way

The spec is format-agnostic and supports multiple VC ecosystems, including:
- W3C VC Data Model
- ISO mdoc (ISO 18013-5)
- AnonCreds

It can also be combined with:
- **OpenID Connect Core** (for existing OIDC deployments that want VP transport)
- **SIOPv2** (if Self-Issued ID Token features are needed)

### 1.1) Requirement keywords

Normative words are interpreted per RFC 2119:
`MUST`, `MUST NOT`, `REQUIRED`, `SHALL`, `SHALL NOT`, `SHOULD`, `SHOULD NOT`, `RECOMMENDED`, `NOT RECOMMENDED`, `MAY`, `OPTIONAL`.

### 2) Terminology used by this spec

This spec reuses terms from OAuth 2.0, OpenID Connect Core, JWT/JWS/JWE, and OAuth response mode specs.
Where definitions conflict, **this spec's definitions take precedence**.

Key terms:

- **Credential**: A set of one or more claims about a subject, issued by a Credential Issuer. (Different meaning from OpenID Core.)
- **Verifiable Credential (VC)**: An issuer-signed credential that can be cryptographically verified; format can vary (W3C VC, mdoc, AnonCreds, etc.).
- **W3C Verifiable Credential**: A VC specifically compliant with W3C VC Data Model.
- **Presentation**: Data shown to a Verifier, derived from one or more VCs (possibly from different issuers).
- **Verifiable Presentation (VP)**: A holder-signed artifact that is cryptographically verifiable and provides holder binding.
- **W3C Verifiable Presentation**: A VP compliant with W3C VC Data Model.

Actors:
- **Credential Issuer (Issuer)**: Issues VCs.
- **Holder**: Receives/stores VCs and presents them.
- **Verifier**: Requests/receives/validates VPs. In this spec, the Verifier acts as an **OAuth Client** toward the Wallet.
- **Wallet**: Used by Holder to manage credentials and keys. In this spec, the Wallet acts as an **OAuth Authorization Server** toward the Verifier.

Model:
- **Issuer-Holder-Verifier model**: Credentials are issued separately from presentation. A VC may be reusable (but does not have to be).

Holder binding types:
- **Holder Binding**: Proof that Holder legitimately possesses a VC.
- **Cryptographic Holder Binding**: Holder proves control of the same private key across issuance and presentation (format-specific mechanism).
- **Claim-based Holder Binding**: Holder proves possession via claims (example: name + date of birth, possibly via another VC); supports long-term/cross-device use.
- **Biometrics-based Holder Binding**: Holder proves possession via biometrics (e.g., fingerprint/face). Example: mobile driving license (mdoc).

Token term:
- **VP Token**: Artifact defined by this spec containing either one VP or an array of VPs (defined later in Section 6.1).

## Part 2 - Overview and Main Flows (Simplified)

### 3) High-level overview

OID4VP extends OAuth 2.0 so a Verifier can request credentials and receive them as **Verifiable Presentations** via a **VP Token**.

Core points:
- **VP Token** is the main new container introduced by this spec.
- A VP Token can include one or many VPs.
- VPs can be in one or multiple credential formats in the same transaction.
- The spec is format-agnostic (e.g., W3C VC, mdoc, AnonCreds).
- Existing OAuth 2.0 grant types and response types can still be used to fit different architectures.

The spec supports:
- Same-device and cross-device user journeys
- Returning responses by redirect or by HTTPS POST
- Large responses that do not fit URL length limits
- OIDC-based deployments, including optional SIOPv2 features

It is also compatible with related OAuth specifications and best-practice documents (for example, request object handling and mobile/security BCPs).

### 3.1) Same-device flow

Use case:
- The user interacts with the Verifier and Wallet on the same device.

How it works:
1. **Verifier -> Wallet**: Sends OAuth Authorization Request containing a **Presentation Definition** (from DIF Presentation Exchange), which describes what credentials/claims/formats are required.
2. Wallet evaluates available credentials, authenticates the user, and asks for consent.
3. **Wallet -> Verifier**: Sends Authorization Response containing `vp_token` with the requested VP(s).

Transport detail:
- In redirect-based response flows (e.g., response mode `fragment`), VP data is returned via redirect URI fragment.

### 3.2) Cross-device flow

Use case:
- The user interacts with Verifier on one device (A), while Wallet is on another device (B).

How it works:
1. Verifier creates an Authorization Request and presents it (often as a QR code).
2. Request usually includes only a **Request URI** (to keep QR small and enable signed/encrypted request objects).
3. Wallet performs HTTPS GET to the Request URI to fetch the full Request Object.
4. Retrieved Request Object includes the **Presentation Definition** and other authorization parameters.
5. Wallet finds matching credentials, authenticates user, and obtains consent.
6. Wallet returns Authorization Response containing `vp_token`.

Transport detail:
- Commonly uses `response_type=vp_token` + `response_mode=direct_post`.
- Response is sent by direct HTTPS POST to Verifier-controlled endpoint.

Important note:
- Request URI usage is optional and independent of same-device vs cross-device choice; it can be used in both flows.

## Part 3 - Scope of OID4VP Extensions (Simplified)

### 4) What OID4VP adds to OAuth 2.0

This section defines the main protocol extensions introduced by OID4VP.

1. **`presentation_definition` request parameter**
   - New Authorization Request parameter.
   - Uses DIF Presentation Exchange syntax.
   - Lets the Verifier express which credentials/claims/formats it needs.

2. **`vp_token` response parameter**
   - New response parameter used to return Verifiable Presentation(s) to the Verifier.
   - Can appear in Authorization Response or Token Response (depending on response type/flow).

3. **New response types**
   - `vp_token`
   - `vp_token id_token`
   - These allow returning VP(s) directly in the Authorization Response, either alone or together with a Self-Issued ID Token (SIOPv2).

4. **New response mode: `direct_post`**
   - Adds HTTPS POST-based delivery for responses.
   - Useful for cross-device scenarios and for large responses that may exceed redirect URL size limits.

5. **Use of `format` from DIF Presentation Exchange**
   - Used throughout the protocol to adapt behavior to specific credential formats.
   - Examples are provided for W3C VC, ISO mdoc, and AnonCreds.

6. **`client_id_scheme` request parameter**
   - New Authorization Request parameter.
   - Enables different ways to resolve and validate Verifier metadata, beyond basic OAuth 2.0 assumptions.

7. **Composability with other features**
   - Credential presentation via OID4VP can be combined with:
     - SIOPv2 user authentication
     - OAuth 2.0 access token issuance

## Part 4 - Authorization Request (Simplified)

### 5) Authorization Request fundamentals

OID4VP uses the OAuth 2.0 Authorization Request model, with OAuth security best-practice guidance applied.

The Verifier can send the request:
- directly (by value), or
- as a Request Object (JAR), by value or by reference (`request_uri` style approach from RFC 9101).

### How credential requirements are expressed

The Verifier describes required credentials using:
- `presentation_definition`, or
- `presentation_definition_uri`, or
- (in some deployments) a scope value that maps to a Presentation Definition.

Wallet behavior:
- Wallets **MUST** process Presentation Definition JSON per DIF Presentation Exchange.
- Wallets **MUST** evaluate/select candidate credentials using the DIF evaluation process.

### Client identity and metadata model

OID4VP adds a flexible Verifier identification mechanism via `client_id_scheme` so Wallets can interpret `client_id` correctly in different trust models.

Key points:
- A scheme may require signed authorization requests and/or extra parameters.
- Verifier metadata can be sent:
  - by value: `client_metadata`
  - by reference: `client_metadata_uri`
- Metadata fields follow OpenID Dynamic Client Registration / RFC 7591 style name-value conventions.
- Presentation Definition and Client Metadata can each be sent by value or by reference.

### New request parameters defined by OID4VP

- **`presentation_definition`** (string JSON object)
  - Contains Presentation Definition JSON.
  - **MUST** be present if neither `presentation_definition_uri` nor scope-based definition is present.

- **`presentation_definition_uri`** (HTTPS URL)
  - Points to Presentation Definition JSON resource.
  - **MUST** be present if neither `presentation_definition` nor scope-based definition is present.

- **`client_id_scheme`** (optional string)
  - Identifies how to interpret `client_id`.
  - If present, Wallet **MUST** process `client_id` in that scheme's namespace/context.
  - If absent, Wallet **MUST** follow default OAuth behavior (RFC 6749).
  - Same `client_id` under different schemes **MUST** be treated as different Verifiers.
  - Verifier should discover Wallet-supported schemes before sending request.

- **`client_metadata`** (optional JSON object, UTF-8)
  - Contains Verifier metadata.
  - **MUST NOT** be present if `client_metadata_uri` is present.

- **`client_metadata_uri`** (optional HTTPS URL)
  - Points to Verifier metadata JSON.
  - URL scheme **MUST** be `https`.
  - Resource **MUST** be reachable by the Wallet.
  - **MUST NOT** be present if `client_metadata` is present.

Encryption key advertisement:
- Verifier may provide key material (`jwks` or `jwks_uri` claims inside client metadata) for response encryption/key agreement.

### Important existing parameters with OID4VP-specific meaning

- **`nonce`** - **REQUIRED**
  - Used to bind returned VP(s) to the specific transaction and prevent replay/misbinding.

- **`scope`** - optional
  - Wallet may support predefined scope values that map to credential presentation requirements.

- **`response_mode`** - optional
  - Can request HTTPS delivery (`direct_post`) and can be relevant for signing/encryption handling.
  - Default is `fragment` if omitted.

### Example shape (non-normative)

A typical request includes:
- `response_type=vp_token`
- `client_id`
- `redirect_uri`
- one presentation definition mechanism
- `nonce`

### 5.1) `presentation_definition` parameter (Simplified)

`presentation_definition` carries a Presentation Definition JSON object (per DIF Presentation Exchange syntax).

It is the main way a Verifier tells the Wallet exactly what kind of credential evidence is acceptable.

What it can express:
- **Credential type requirements** (e.g., "must be an ID card credential")
- **Format constraints** (e.g., proof type, JWT algorithm, etc.)
- **Field-level constraints** on claims using JSON paths
- **Selective disclosure requirements** (only specific claims should be disclosed)
- **Alternative credential options** (e.g., "ID card OR passport")

Typical patterns shown by the examples:

1. **Simple type match**
   - Request one credential of a specific type by filtering on type-related claim fields.

2. **Selective disclosure**
   - Require minimal disclosure (for example: given name, family name, birthdate), instead of full credential content.

3. **Alternatives via submission requirements**
   - Define a group of acceptable credential descriptors.
   - Require Wallet to provide one from that group (pick/count rules).

### Format capability coordination rules

Wallet-side capability publication:
- Wallet should publish supported VC/VP formats in metadata via `vp_formats_supported`.

Verifier-side request capability:
- Verifier indicates supported formats via `vp_formats` metadata.

Critical processing rule:
- Wallet **MUST ignore** any `format` entry in `presentation_definition` if that format is not listed in Verifier metadata `vp_formats`.

Important note:
- If Verifier requests a VP that itself contains VC(s), Verifier must declare support for **both**:
  - the VC format(s), and
  - the VP format(s),
  in `vp_formats`.

### 5.2) `presentation_definition_uri` parameter (Simplified)

`presentation_definition_uri` lets the Verifier provide the Presentation Definition **by reference** (URL) instead of embedding JSON directly in the authorization request.

Required behavior:
- Wallet **MUST** fetch it using **HTTPS GET**.
- Wallet **MUST** call the URL **without adding extra parameters**.
- The referenced resource **MUST** be publicly retrievable for this flow (no extra auth/authorization challenge).
- URI scheme **MUST** be `https`.

Operationally:
- Wallet receives `presentation_definition_uri`.
- Wallet performs GET to that URL.
- Verifier returns JSON Presentation Definition.
- Wallet then processes it as normal.

### 5.3) Using `scope` to request credential presentation (Simplified)

Wallets may support credential presentation requests via OAuth `scope` values.

In this pattern:
- A scope value acts as an **alias** to a well-defined Presentation Definition.
- That alias must resolve clearly enough to produce consistent response content (including identifiers used in `presentation_submission` and expected VP content shape).

Important constraints:
- Exact scope names and mapping mechanisms are **out of scope** of this specification.
- Mapping may be standardized elsewhere or published in machine-readable Wallet metadata.
- Scope design should be collision-resistant (recommended).

Why this matters:
- Verifier must be able to predict `presentation_submission.definition_id` from the scope alias.
- Verifier must be able to predict `presentation_submission.descriptor_map.id` from the scope alias.
- Verifier must be able to predict expected credential types/formats in `vp_token` from the scope alias.

Example shape:
- Authorization request can use `scope=com.example.healthCardCredential_presentation` (or similar collision-resistant value) as the Presentation Definition alias, together with `response_type=vp_token` and a required `nonce`.

### 5.4) Response Type `vp_token` (Simplified)

OID4VP defines a new OAuth response type: `vp_token`.

Behavior when `response_type=vp_token`:
- Successful authorization response **MUST** include `vp_token`.
- Wallet **SHOULD NOT** include OAuth authorization code, access token, or token type in that success response.
- Default response mode is `fragment` (response parameters returned in redirect URI fragment).
- Other OAuth response modes may be used when supported.
- Success and error responses **SHOULD** use the chosen response mode (or default if none was supplied).

### 5.5) Passing Authorization Request across devices (Simplified)

For cross-device scenarios (e.g., Verifier screen + Wallet on phone), authorization request can be transferred via QR code.

Recommended pattern:
- Use `request_uri` + `response_mode=direct_post`.

Why:
- Authorization requests can be large.
- Embedding full request in QR code may not be practical.
- By-reference request retrieval keeps QR payload small.

### 5.6) `aud` in Request Object (Simplified)

When Verifier sends a Request Object (per RFC 9101), `aud` value depends on discovery model:

- **Dynamic discovery used**:
  - `aud` **MUST** equal Wallet issuer value.

- **Static discovery metadata used**:
  - `aud` **MUST** be `"https://self-issued.me/v2"`.

Important note:
- `"https://self-issued.me/v2"` is a symbolic audience value and can be used even when OID4VP is used standalone (not only in full SIOPv2 deployments).

### 5.7) Verifier metadata management via `client_id_scheme` (Simplified)

`client_id_scheme` defines how Wallet should interpret `client_id` and how Verifier metadata is discovered/validated.

This extends plain OAuth client identification with multiple trust models.

#### Supported `client_id_scheme` values in this draft

1. **`pre-registered`**
   - Default OAuth-style behavior.
   - Verifier is known to Wallet ahead of time.
   - Metadata comes from registration (RFC 7591) or out-of-band setup.

2. **`redirect_uri`**
   - `client_id` is the same value as Verifier redirect URI.
   - Authorization Request **MUST NOT** be signed.
   - `redirect_uri` parameter may be omitted by Verifier.
   - Verifier metadata **MUST** be provided via `client_metadata` or `client_metadata_uri`.

3. **`entity_id`**
   - `client_id` is an OpenID Federation Entity Identifier.
   - Wallet **MUST** follow OpenID Federation processing rules.
   - Automatic Registration from OpenID Federation **MUST** be used.
   - Request may include `trust_chain`.
   - Effective Verifier metadata is taken from resolved trust chain after policy processing.
   - `client_metadata` / `client_metadata_uri` in request, if present, **MUST be ignored**.

4. **`did`**
   - `client_id` is a DID.
   - Request **MUST** be signed with private key tied to that DID.
   - Wallet resolves DID Document via DID method resolution.
   - Verification key comes from DID Document `verificationMethod`.
   - JOSE header `kid` **MUST** identify which DID key signed the request.
   - Non-key metadata is provided via `client_metadata` / `client_metadata_uri`.

5. **`verifier_attestation`**
   - Verifier authenticates using a Verifier Attestation JWT (details in Section 10).
   - `client_id` **MUST** equal attestation JWT `sub`.
   - Request **MUST** be signed by key bound in attestation JWT `cnf`.
   - Attestation JWT **MUST** be included in Request Object JOSE header (`jwt` header parameter).
   - Wallet **MUST** validate attestation signature and trust its issuer (`iss`).
   - If trust cannot be established, Wallet **MUST** reject request.
   - If attestation contains `redirect_uris`, request `redirect_uri` **MUST** exactly match one entry.
   - Non-key metadata comes via `client_metadata` / `client_metadata_uri`.

6. **`x509_san_dns`**
   - `client_id` **MUST** be a DNS name.
   - It must match a `dNSName` SAN entry in leaf certificate.
   - Request **MUST** be signed with private key of leaf certificate (chain provided via JOSE `x5c`).
   - Wallet **MUST** validate signature and certificate trust chain.
   - Non-key metadata is obtained from `client_metadata`.
   - Redirect URI rule:
     - If Wallet has established strong trust for this client, it may allow flexible `redirect_uri`.
     - Otherwise, redirect URI FQDN **MUST** match `client_id`.

7. **`x509_san_uri`**
   - `client_id` **MUST** be a URI.
   - It must match a `uniformResourceIdentifier` SAN entry in leaf certificate.
   - Request signing and certificate validation requirements are same as `x509_san_dns`.
   - Non-key metadata is obtained from `client_metadata`.
   - Redirect URI rule:
     - If Wallet has established strong trust, it may allow flexible `redirect_uri`.
     - Otherwise, `redirect_uri` **MUST** match `client_id`.

### Confidential client requirement

For these schemes, Verifier **MUST** be a confidential client:
- `entity_id`
- `did`
- `verifier_attestation`
- `x509_san_dns`
- `x509_san_uri`

Implication:
- Native/public-client designs may need architectural changes to use these schemes securely.

### Extensibility

Other specifications may define additional `client_id_scheme` values.
Using collision-resistant names for new scheme values is recommended.

## Part 5 - Response Handling (Simplified)

### 6) When and where VP Token is returned

A VP Token is returned only when the corresponding authorization request asked for credential presentation using at least one of:
- `presentation_definition`
- `presentation_definition_uri`
- a `scope` value that represents a Presentation Definition

VP Token location depends on `response_type`:

- **`response_type=vp_token`**
  - VP Token is returned in **Authorization Response**.

- **`response_type=vp_token id_token`** (with `scope` including `openid`)
  - VP Token is returned in **Authorization Response**.
  - A Self-Issued ID Token (SIOPv2) is also returned.

- **`response_type=code`** (authorization code flow)
  - VP Token is returned in **Token Response**.

Equivalent mapping:
- `vp_token` -> Authorization Response
- `vp_token id_token` -> Authorization Response
- `code` -> Token Response

Important boundary:
- For any other response type value (or combinations), VP Token behavior is **unspecified** by this section.

### 6.1) Response parameters (Simplified)

When VP Token is returned, response **MUST** contain:
- `vp_token` (required)
- `presentation_submission` (required)

Other parameters such as `state`, `code`, `id_token`, and `iss` may also appear when relevant by their base specs.

#### `vp_token` rules

`vp_token` can be:
- a single VP (JSON string or JSON object), or
- an array of VPs (mixed JSON strings/objects, format-dependent).

Encoding/representation rules:
- Representation follows Annex E rules of OpenID4VCI for each credential/presentation format.
- If Annex E defines encoding rules for a format, those same rules apply here.
- If a format is already naturally JSON object/string, no extra encoding is required by this spec.
- If only one VP is returned, array syntax **MUST NOT** be used.

#### `presentation_submission` rules

`presentation_submission` follows DIF Presentation Exchange and maps requested descriptors to actual returned content.

Critical location rule:
- `presentation_submission` **MUST** be a separate top-level response parameter next to `vp_token`.
- Verifier/Client **MUST ignore** any `presentation_submission` found inside a VP payload.

Why separate parameter matters:
- Lets Wallet provide structure/format mapping metadata before deep VP parsing.
- Supports formats that cannot embed `presentation_submission` internally.

#### `descriptor_map.path` requirements

For each mapping object in `descriptor_map`:
- If VP Token contains exactly one VP, top-level `path` **MUST** be `$`.
- If VP Token contains multiple VPs, top-level `path` **MUST** be `$[n]` (index of selected VP).

Nested mapping:
- `path_nested` is used to locate the actual credential inside the selected VP.
- Each `descriptor_map` entry **MUST** include `path_nested` pointing to the credential location.
- Exact nested path syntax depends on credential/presentation format.

Practical interpretation of examples:
- Single VP case: descriptor points to `$`, then nested path points inside that VP (e.g., VC array element).
- Multi-VP case: descriptor points to `$[0]`, `$[1]`, etc., then nested path points inside each chosen VP.

### 6.2) Response Mode `direct_post` (Simplified)

`direct_post` lets the Wallet send authorization response data directly to a Verifier-controlled endpoint via HTTPS POST.

#### Why `direct_post` exists

Primary use cases:
- **Cross-device flow** where Wallet cannot complete a browser redirect back to Verifier UX device.
- **Large response payloads** that may exceed URL size limits in redirect-based modes (e.g., `fragment`).

This enables VP delivery without requiring the Wallet to run a backend callback service.

#### Protocol behavior

In `direct_post` mode:
- Wallet sends Authorization Response parameters in POST body.
- Content type is `application/x-www-form-urlencoded`.
- Endpoint is controlled by Verifier.
- Flow may end at POST, or continue if Verifier returns a follow-up redirect URI.

#### `response_uri` request parameter

`response_uri` is defined for use with `direct_post`.

Rules:
- Declared as optional in syntax, but it **MUST be present** when `response_mode=direct_post`.
- Wallet **MUST** POST Authorization Response to this URI.
- If `response_uri` is present, `redirect_uri` request parameter **MUST NOT** be present.
- If request uses `direct_post` and includes `redirect_uri`, Wallet **MUST** return `invalid_request`.

Operational note:
- Verifier frontend and response endpoint must correlate request and response.
- `state` may be used for this correlation.

Special scheme rule:
- If `client_id_scheme=redirect_uri` and `response_uri` is present, `client_id` **MUST** equal `response_uri`.

#### Verifier endpoint response requirements

After successfully processing Wallet POST:
- Response endpoint **MUST** return HTTPS status `200`.

Endpoint response may include:
- **`redirect_uri`** (response parameter, optional)
  - If present, Wallet **MUST** send user agent to that URI.
  - This supports continuing interaction on Wallet device and helps mitigate session fixation risk.

If endpoint response does not include the redirect parameter:
- Wallet is not required by this spec to do additional steps.

#### Security expectations for returned redirect URI

Verifier-chosen redirect URI must be absolute URI.
Verifier **MUST** include a fresh cryptographically random value in that URI so only intended recipient can retrieve/process resulting authorization result.

Recommendation in draft:
- Use at least 128 bits of cryptographic randomness.

Security note:
- `direct_post` without follow-up redirect can be less secure than redirect-based modes (session fixation considerations).

Implementation note:
- In `direct_post` (and `direct_post.jwt`), Wallet UI can adapt based on Verifier callback behavior after response submission.

### 6.3) Signed and encrypted responses (Simplified)

This section covers application-layer protection for Authorization Responses containing VP data (when response type is `vp_token` or `vp_token id_token`).

#### Why this matters

Signing and/or encrypting response data protects VP-related personal data, especially in front-channel returns (e.g., browser-mediated flows).

#### Supported protection patterns

Implementations may use JARM to:
- sign responses, or
- sign and encrypt responses.

This draft also allows:
- **encrypted but unsigned** authorization responses (JWE-only), by extending JARM-style handling.

Reason to allow encrypted-only:
- Avoids using a stable signing key that could become a correlation signal.
- Can simplify trust dependencies where signing-key authenticity is hard to establish.
- Security tradeoffs are addressed in security section (notably encrypted-unsigned considerations).

#### Rules for encrypted-only JWT responses (JWE without JWS)

If response JWT is only JWE, Wallet/Verifier processing **MUST** follow these rules:
- `iss`, `exp`, and `aud` **MUST be omitted** from JWT claims set.
- JARM claim-processing rules tied to those claims do not apply.
- JARM JWS-processing rules **MUST be ignored**.

#### Payload requirements

Regardless of signing choice, JWT response document **MUST** include:
- `vp_token`
- `presentation_submission`

These follow the same semantics defined in Section 6.1.

#### Key material sourcing

Encryption keys:
- Wallet obtains Verifier public key for response encryption from metadata mechanisms such as:
  - `jwks` / `jwks_uri` in `client_metadata`,
  - federation metadata (e.g., entity configuration when federation is used),
  - or equivalent supported mechanisms.

Signing keys:
- If Wallet signs authorization response, it **MUST** use a private key whose corresponding public key is published in Wallet metadata.

### 6.3.1) Response Mode `direct_post.jwt` (Simplified)

OID4VP defines `direct_post.jwt` to combine:
- direct HTTPS POST delivery (`direct_post` behavior), and
- JARM-style JWT authorization response packaging.

Behavior:
- Wallet sends Authorization Response to Verifier endpoint via HTTPS POST (not browser redirect return).
- POST body uses `application/x-www-form-urlencoded`.
- Body contains `response=<JWT>` parameter (per JARM response parameter model).

JWT payload content follows Section 6.3/JARM profile for the chosen signing/encryption mode and includes VP response content (`vp_token`, `presentation_submission`).

## Part 6 - Error Handling (Simplified)

### 6.4) Error response rules

Base error model follows OAuth 2.0 error handling, with OID4VP clarifications and additional error codes.

#### Clarified existing errors

- **`invalid_scope`**
  - Scope is invalid, unknown, or malformed.

- **`invalid_request`**
  - Request uses more than one credential-request mechanism simultaneously from:
    - `presentation_definition`
    - `presentation_definition_uri`
    - scope alias representing a presentation definition
  - Presentation Definition is not compliant with DIF Presentation Exchange.
  - Wallet does not support provided `client_id_scheme`.
  - `client_id` does not satisfy rules of declared scheme (example: missing required signature for a signed-required scheme such as `entity_id`).

- **`invalid_client`**
  - Request includes `client_metadata`/`client_metadata_uri` even though Wallet already recognizes client and has pre-registered metadata.
  - Request mixes mutually exclusive metadata/bootstrap models (e.g., first-seen dynamic metadata supply vs pre-registered identity model).

#### New OID4VP-specific errors

- **`vp_formats_not_supported`**
  - Wallet supports none of the Verifier-requested VP/VC formats (including those in `vp_formats` metadata).

- **`invalid_presentation_definition_uri`**
  - Presentation Definition URL cannot be reached.

- **`invalid_presentation_definition_reference`**
  - URL is reachable, but requested Presentation Definition cannot be resolved/found there.

### 6.5) VP Token validation (Simplified)

Verifier validation is mandatory and should follow this sequence:

1. **Map submissions to returned data**
   - Determine how many VPs were returned.
   - Use `presentation_submission.descriptor_map` to identify which requested credential is located in which VP/path.

2. **Validate each VP**
   - Verify VP integrity and authenticity using its format rules.
   - Verify holder binding according to that format's model.
   - Include replay-prevention checks required by this profile.

3. **Validate each VC**
   - Apply credential-format-specific checks (including signature verification on each VC).

4. **Match against request constraints**
   - Ensure returned credentials satisfy all Presentation Definition requirements from the authorization request.

5. **Apply verifier policy / trust framework checks**
   - Run policy-driven checks (for example revocation and trust framework requirements) when applicable.

Note:
- DIF Presentation Exchange defines additional relevant processing guidance for Presentation Definition and Presentation Submission.

## Part 7 - Wallet Invocation (Simplified)

### 7) How the Verifier can invoke the Wallet

Verifier can initiate Wallet interaction in three main ways:

1. **Custom URL scheme authorization endpoint**
   - Example pattern: `openid4vp://...`

2. **Domain-bound universal/app links**
   - Authorization endpoint is invoked through OS-level verified app/web link mechanisms.

3. **No direct app-link endpoint usage**
   - User manually opens Wallet and scans a QR code containing the authorization request.
   - In this case, neither custom URL scheme nor universal/app link is used for invocation.

## Part 8 - Metadata Exchange (Simplified)

### 8) Wallet metadata (authorization server metadata)

Purpose:
- Lets Verifier discover what credential/presentation formats, proof types, and crypto algorithms the Wallet supports.

#### 8.1 Additional Wallet metadata parameters

- **`presentation_definition_uri_supported`** (optional boolean)
  - Indicates Wallet supports by-reference Presentation Definition retrieval.
  - Default is `true` if omitted.

- **`vp_formats_supported`** (required object)
  - Declares credential/presentation formats supported by Wallet.
  - Format identifiers follow OpenID4VCI Annex E (plus profile-defined extensions).
  - Each format entry includes algorithm capability details via:
    - `alg_values_supported`: array of supported cryptographic suite identifiers.

- **`client_id_schemes_supported`** (optional array)
  - Lists supported `client_id_scheme` values.
  - Draft-defined values include: `pre-registered`, `redirect_uri`, `entity_id`, `did`.
  - Default is `pre-registered` if omitted.
  - Profiles may define more values.

#### 8.2 How Verifier obtains Wallet metadata

Verifier can obtain Wallet metadata by:
- dynamic discovery mechanisms (e.g., RFC 8414 / equivalent), or
- pre-obtained static metadata (out-of-band/provisioned setup).

### 9) Verifier metadata (client metadata)

OID4VP reuses client metadata model (RFC 7591-style) to carry Verifier capabilities to Wallet.

Purpose:
- Lets Wallet determine what credential/presentation formats and algorithms the Verifier can process.

#### 9.1 Additional Verifier metadata parameter

- **`vp_formats`** (required object)
  - Declares VC/VP formats and proof/algorithm capabilities supported by Verifier.
  - Expected values are illustrated in spec appendix examples.
  - Deployments may extend supported formats if all ecosystem parties (issuer/holder/verifier) understand them.

## Part 9 - Verifier Attestation (Simplified)

### 10) Verifier Attestation JWT

Verifier Attestation JWT provides a structured way for Wallets to authenticate Verifiers.

Model:
- A trusted attestation issuer issues an attestation JWT to the Verifier.
- Verifier identity is bound to a public key.
- Verifier must present:
  - the attestation JWT, and
  - proof-of-possession of the bound private key.
- In `client_id_scheme=verifier_attestation`, this proof-of-possession is provided by signing the authorization request with that key.

Trust establishment details between Wallet and attestation issuer are out of scope.

#### Required/optional claims in Verifier Attestation JWT

- **`iss`** (required)
  - Identifies attestation issuer.
  - May be used for key lookup/verification context.

- **`sub`** (required)
  - Must equal Verifier `client_id`.

- **`iat`** (optional, numeric date)
  - Issuance time.

- **`exp`** (required, numeric date)
  - Expiration time.
  - Wallet must reject expired attestations (allowing normal clock skew tolerance).

- **`nbf`** (optional)
  - Not-before constraint.

- **`cnf`** (required)
  - Confirmation claim per RFC 7800, containing a JWK.
  - Identifies key for which Verifier must prove possession.
  - Prevents simple replay of captured attestation by an attacker who lacks private key.

Additional registered JWT claims may be included.

#### Media type and JOSE header requirements

- Verifier Attestation JWT media type:
  - `application/verifier-attestation+jwt`

- Attestation JWT JOSE `typ` header:
  - must be `verifier-attestation+jwt`

#### Conveying attestation in signed objects

Attestation JWT may be carried in JOSE header of a signed object using:
- **`jwt`** JOSE header parameter (contains a JWT)

In OID4VP context, the JWT carried there must itself be a Verifier Attestation JWT with `typ=verifier-attestation+jwt`.

## Part 10 - Implementation Considerations (Simplified)

### 11) Implementation considerations

This section gives practical deployment guidance for Wallet configuration, trust/federation filtering, nesting behavior, and state handling.

### 11.1 Static Wallet configuration values

If Verifier cannot do dynamic discovery, it can rely on profile-defined or pre-agreed static Wallet settings.

#### 11.1.1 Profiles defining static values

Example profile called out in this draft:
- JWT VC Presentation Profile

#### 11.1.2 Static values bound to `openid4vp://`

A non-normative static configuration example is provided for a custom-scheme authorization endpoint:
- `authorization_endpoint` using `openid4vp:`
- `response_types_supported` includes `vp_token`
- `vp_formats_supported` includes JWT VP/VC formats with listed alg support
- `request_object_signing_alg_values_supported` declared

Practical meaning:
- Enables bootstrapping interoperability in environments where dynamic metadata retrieval is unavailable.

### 11.2 Support for federations / trust schemes

Use case:
- Verifier may request credentials issued by any issuer belonging to a trusted federation/scheme, not just one named issuer.

Approach described:
- Credential indicates federation/trust-scheme membership claims (for example via VC `termsOfUse`).
- Verifier includes matching criteria in `presentation_definition`.
- Wallet selects candidate credentials matching those criteria.
- Verifier can verify asserted membership through federation API/policy logic.

Illustrative identifiers referenced:
- OpenID Federation style identifiers (`urn:ietf:params:oauth:federation`, trust-mark variants).
- TRAIN trust-scheme identifier (`https://train.trust-scheme.de/info`), with federation identifiers by DNS naming in that model.

### 11.3 Nested Verifiable Presentations

Current draft position:
- Nested VP-inside-VP presentation is **not supported**.
- Although DIF PE allows deeper nesting in theory, this draft only relies on one nesting level (`path_nested`) to locate VC inside VP.

### 11.4 State management

`state` can be used to correlate authorization requests and responses (standard OAuth anti-mixup/session-linking usage).

Additional note:
- In `direct_post` flows, state handling and correlation concerns are especially important and should follow corresponding security guidance.

### 11.5 Response Mode `direct_post` reference design (Simplified)

This section is implementation guidance for Verifier internals (especially frontend vs response-endpoint split).  
It does not change Wallet-Verifier protocol semantics, but proposes a secure pattern aligned with security considerations.

#### Core idea

Use multiple high-entropy values with distinct purposes:
- **`nonce`**: binds VP/credential proof to the verifier session.
- **`request-id`**: sent as OAuth `state`, binds Wallet callback to initiated authorization request.
- **`transaction-id`**: backend handle proving frontend is authorized to fetch stored response data.
- **`response_code`**: one-time bridge from Wallet redirect back to frontend retrieval call.

#### Suggested flow

1. Verifier creates fresh random `nonce` and stores it in session.
2. Verifier initializes transaction at Response Endpoint.
3. Response Endpoint returns fresh `transaction-id` and `request-id`.
4. Verifier sends Authorization Request to Wallet with:
   - `response_uri`
   - `nonce`
   - `state=request-id`
5. Wallet authenticates user/collects consent, then POSTs authorization response (`vp_token`, `presentation_submission`, `state`) to `response_uri`.
6. Response Endpoint validates `state` as known `request-id`, stores response data under transaction context, creates fresh `response_code`, and may return `redirect_uri` containing that `response_code`.
7. If redirect URI is returned, Wallet redirects user-agent there; Verifier frontend extracts `response_code`.
8. Frontend calls Response Endpoint with session `transaction-id` + `response_code` to retrieve response data.
   - If no redirect URI was returned, frontend can poll endpoint by `transaction-id` until response arrives.
9. Response Endpoint returns stored `vp_token` + `presentation_submission`.
10. Verifier validates `nonce` in returned credential/presentation evidence against session nonce, processes result, then invalidates `transaction-id`, `request-id`, and `nonce`.

#### Security outcomes of this design

- Separates browser-facing and backend-facing secrets.
- Prevents unauthorized response retrieval via mandatory transaction binding.
- Reduces session fixation/mix-up risk through explicit state and one-time response correlation.
- Enforces single-use lifecycle by invalidating identifiers after consumption.

## Part 11 - Security Considerations (Simplified)

### 12.1 Preventing replay of VP Token

Threat:
- An attacker reuses a previously obtained VP Token (or individual VP) in a different authorization response to impersonate a user.

This draft requires explicit replay defenses.

#### Mandatory anti-replay model

Every presentation must be cryptographically bound to:
- **intended audience** = Verifier `client_id`
- **specific transaction** = request `nonce`

Both Wallet and Verifier have strict duties:

- **Verifier MUST**
  - generate fresh high-entropy nonce per authorization request,
  - store nonce in current session,
  - send it in request `nonce`,
  - validate each returned VP against original `client_id` and `nonce`.

- **Wallet MUST**
  - bind every returned VP to the request `client_id` and `nonce`.

Why each value matters:
- `client_id` binding detects disclosures to unintended relying parties.
- `nonce` binding detects cross-transaction injection/replay, especially important in front-channel flows.

#### Format-specific representation differences

How binding appears depends on VP format/proof scheme:
- some formats carry values as explicit claims,
- others embed them in proof inputs.

Verifier must interpret this based on `presentation_submission` format mapping.

Examples reflected by draft:
- In `jwt_vp_json`, `aud` can carry verifier/client audience and `nonce` carries transaction binding.
- In `ldp_vp`, proof fields such as `domain` (audience-like) and `challenge` (nonce-like) carry equivalent bindings.

### 12.2 Session fixation

Risk model:
- Attacker initiates flow on attacker-controlled verifier session, relays authorization request to victim, then tries to complete flow from attacker session.

Flow impact by response mode:
- `fragment` mode: inherently resistant in this scenario because response lands on same device/browser context as Wallet interaction.
- `direct_post` mode: exposed to session-fixation risk because response is sent out-of-band to backend endpoint.

Required/recommended controls for `direct_post`:
- Use `direct_post` with follow-up redirect to frontend when possible.
- Response endpoint **MUST** include fresh secret (`response_code`) in returned redirect URI.
- Response endpoint **MUST** require that `response_code` when frontend fetches authorization response data.
- Without redirect-based protection, verifier has weaker session context; additional hardening is recommended.

### 12.3 Security for Response Mode `direct_post`

#### 12.3.1 Validation of Response URI

Wallet must prevent response data leakage through bad response URIs.

- For pre-registered response URIs, Wallet **MUST** apply redirect URI validation best practices.
- Wallet may also rely on trusted client-id-scheme + client auth + signed/integrity-protected request to trust provided response URI.

#### 12.3.2 Protection of Response URI

Verifier should protect response endpoint from unsolicited/inadvertent requests:
- check received `state` matches a recent authorization request,
- optionally use JARM to authenticate request origin.

#### 12.3.3 Protection of Authorization Response data (internal interface)

Risk:
- Attackers may attempt to query verifier-internal response retrieval interface to steal VP data/PII.

Requirement:
- Implementations **MUST** protect this internal interface against unauthorized access.

Example controls:
- authentication/authorization between verifier components,
- dual-random-secret pattern:
  - one value for Wallet<->Verifier state linkage,
  - another value proving frontend/component authorization to retrieve stored response data.

### 12.4 User authentication using Verifiable Credentials

If verifier authenticates a user via a VC claim, that claim must be:
- stable over time for that user,
- locally unique within the issuer namespace,
- never reassigned to another user by that issuer.

It must be used together with issuer identifier to ensure global uniqueness and prevent cross-issuer impersonation via same claim value.

### 12.5 Encrypting an unsigned response

If response is encrypted but not integrity-protected at wrapper level, attacker may alter top-level response parameters (e.g., `presentation_submission`) and re-encrypt for verifier (public encryption key is typically known).

Even so:
- VP content integrity remains protected by VP/VC cryptographic proofs, so tampering inside VP token should still be detected by verifier validation.

### 12.6 DIF Presentation Exchange 2.0.0 considerations

#### 12.6.1 Fetching Presentation Definitions by reference

When fetching referenced presentation definitions, Wallets can reduce forgery risk by:
- allowlisting trusted domains/operators (for example federation-operated servers),
- optionally requiring signed presentation definitions from trusted authorities.

#### 12.6.2 JSONPath and arbitrary scripting

Implementers **MUST** ensure JSONPath processing in `presentation_definition` / `presentation_submission` cannot trigger arbitrary script execution.

Practical safeguard:
- use safe parser/evaluator design that does not delegate query execution to general-purpose language runtime eval behavior.

#### 12.6.3 Filters property

Use caution for complex filter mechanisms (e.g., regex/JSON Schema):
- bound computation/resource usage,
- prevent DoS-style expensive evaluations,
- avoid unintended data/resource access paths.

### 12.7 TLS requirements

- Implementations **MUST** follow BCP 195 TLS guidance.
- Whenever TLS is used, server certificate validation **MUST** be performed per RFC 6125.

## Appendix A - Examples Across Credential Formats (Simplified)

OpenID4VP is format-agnostic: it can request/return VPs and VCs in multiple credential formats, not only classic VC Data Model serializations.

Customization for non-default formats is done via Presentation Exchange extension points.

### A.1 W3C Verifiable Credentials

#### A.1.1 VC signed as JWT (no JSON-LD processing model)

This example family uses:
- `jwt_vc_json` for VC format identifier
- `jwt_vp_json` for VP format identifier

Crypto algorithm names should align with JOSE/IANA naming conventions.

#### A.1.1.1 Example VC payload shape

The sample VC is a JWT payload containing:
- issuer (`iss`)
- subject (`sub`)
- temporal/id claims (`nbf`, `jti`)
- `vc` object with type `IDCredential`
- credential subject claims (name, birthdate, address)

#### A.1.1.2 Presentation request pattern

The request is a normal `response_type=vp_token` authorization request with `nonce`.

Its `presentation_definition`:
- asks for one descriptor (`id_credential`),
- sets desired format to `jwt_vc_json`,
- filters on `$.vc.type` containing `IDCredential`.

Meaning:
- Wallet should return a credential of that declared type in JWT VC JSON format.

#### A.1.1.3 Presentation response pattern

Authorization response includes:
- `presentation_submission`
- `vp_token`

`presentation_submission.descriptor_map` indicates:
- descriptor `id_credential` is found in top-level VP (`path: "$"`),
- actual VC is inside VP at `$.vp.verifiableCredential[0]`,
- VP format is `jwt_vp_json`, VC format is `jwt_vc_json`.

Returned VP payload includes:
- `aud` set to verifier client identifier
- `nonce` set to original request nonce
- embedded VC JWT(s) in `vp.verifiableCredential`

Security significance:
- Verifier uses `aud` + `nonce` bindings to detect replay/injection, consistent with anti-replay guidance.

### A.3 ISO mobile Driving License (mDL)

This section shows how an ISO/IEC 18013-5 mobile driving license can be presented via OID4VP.

Key format points:
- Credential format identifier: `mso_mdoc`
- Typical payload encoding in this example: CBOR
- Signature suite naming should follow ISO 18013-5 conventions

#### A.3.1 Presentation request pattern

The authorization request structure is the same as other examples (`response_type=vp_token`, `client_id`, `redirect_uri`, `presentation_definition`, `nonce`).

What changes is `presentation_definition` content:
- `input_descriptor.format` requests `mso_mdoc`
- constraints request selected mDL data elements via ISO namespace paths
- `limit_disclosure: required` enforces selective disclosure
- `intent_to_retain` expresses whether verifier intends to retain each disclosed claim

Important mDL-specific behavior:
- For ISO mDL requests, verifier identifies requested attributes by docType/namespace/data-element conventions.
- `intent_to_retain` is included here to address ISO 18013-5 policy expectations.

#### A.3.2 Presentation response pattern

Response still uses:
- `presentation_submission`
- `vp_token`

For CBOR mDL response:
- `descriptor_map.format` is `mso_mdoc`
- `descriptor_map.path` is `$` (mdoc object directly at vp_token root)
- `path_nested` is generally not usable for claim-level selection in CBOR mdoc representation.

Note:
- For JSON-encoded mdoc variants, `path_nested` can be used.

#### mDL cryptographic structure (conceptual)

Returned mdoc contains two important signed areas:
- **`deviceSigned` / `deviceAuth`**
  - proves holder possession via device key (issuer bound this key at issuance).
- **`issuerSigned` / `issuerAuth`**
  - issuer signs claim digests and related issuance data.
  - disclosed claim values are provided per consented namespaces/elements.

Selective disclosure model in mDL:
- issuer signs digests of full claim set during issuance,
- holder reveals only chosen claim values at presentation time,
- verifier validates revealed values against issuer-signed digest commitments.

Additional note:
- Example pattern is also applicable to related ISO electronic identification credential models (e.g., ISO/IEC TR 23220-2 data-model-based credentials).

## Appendix B - IANA Considerations (Simplified)

### B.1 Response Types

The spec plans/defines registration of these OAuth authorization response types:
- `vp_token`
- `vp_token id_token`

Registration metadata references OpenID Foundation AB working group as change controller and points to the OID4VP specification document.

### B.2 Media Types

#### B.2.1 `application/verifier-attestation+jwt`

Defines media type for Verifier Attestation JWT:
- type/subtype: `application/verifier-attestation+jwt`
- encoding: JWT compact serialization conventions
- intended for apps issuing/presenting/verifying verifier attestations

Draft notes:
- several registration fields are placeholders/TODO in the provided text (e.g., published specification details, author/contact).

### B.3 JWS Headers

#### B.3.1 `jwt` header parameter registration

Registers JOSE/JWS header parameter:
- name: `jwt`
- meaning: header contains a JWT
- processing can depend on carried JWT `typ`
- usage location: JWS
- change controller: OpenID Foundation AB working group
- behavior source in this draft: Section 10

### A.4 Combining this specification with SIOPv2 (Simplified)

This flow combines:
- OID4VP for credential presentation (`presentation_submission` + `vp_token`)
- SIOPv2 for self-issued end-user authentication (`id_token`)

Goal:
- allow verifier to receive verifiable credentials and a pseudonymous self-issued identity assertion in the same transaction, using subject-controlled key material.

#### A.4.1 Request pattern

Non-normative combined request characteristics:
- `response_type=id_token`
- `scope=openid`
- `id_token_type=subject_signed`
- includes `presentation_definition`
- includes `nonce`

Interpretation:
- `scope=openid` + `id_token_type=subject_signed` makes this a SIOP-style request.
- Including `presentation_definition` means Wallet should also return VP-related parameters alongside ID token.

#### A.4.2 Response pattern

Combined response includes:
- `id_token`
- `presentation_submission`
- `vp_token`

So verifier gets authentication artifact and credential presentation artifacts together.

Self-Issued ID Token payload (example shape) includes typical claims like:
- `iss`, `sub`, `aud`, `nonce`, `iat`, `exp`

Security note:
- `aud` and `nonce` in the self-issued ID token should bind to verifier client identifier and request nonce, aligned with anti-replay protections used for VPs.
