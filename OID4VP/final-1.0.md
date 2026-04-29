# OID4VP Final Version 1.0

## 1. Introduction (Simplified)

OpenID for Verifiable Presentations (OID4VP) defines how to request and deliver **Credential Presentations** using an OAuth 2.0-based flow.

### What it supports
- It is format-agnostic: Credentials and Presentations can use multiple formats, including:
  - W3C Verifiable Credentials Data Model (VC Data Model)
  - ISO mdoc (ISO/IEC 18013-5)
  - IETF SD-JWT VC

### Why OAuth 2.0 is the base
- OID4VP is built on OAuth 2.0 because OAuth already provides secure, widely implemented protocol rails.
- This allows implementers to support, through one interface:
  - credential presentation, and
  - traditional OAuth access token issuance for API access based on credentials in a wallet.

### Relationship with OpenID Connect and SIOPv2
- Existing OpenID Connect deployments can extend their systems with OID4VP to carry Credential Presentations.
- OID4VP can be combined with SIOPv2 when OpenID-specific features are needed, such as issuing Self-Issued ID Tokens.

### Use with Digital Credentials API (DC API)
- The spec also defines how OID4VP works with the W3C Digital Credentials API.
- Requirements for this integration are in **Appendix A**.
- Appendix A is designed to be self-contained: implementers focused only on OID4VP over DC API can follow Appendix A and ignore other sections unless Appendix A explicitly points to them.

## 2. Terminology (Simplified)

### Reused terms from other specs
This spec reuses terminology from:
- OAuth 2.0 (RFC6749): e.g., Access Token, Authorization Request/Response, Client, Grant Type, Response Type, Token Request/Response.
- OpenID Connect Core: End-User, Entity.
- RFC9101: Request Object, Request URI.
- RFC7519: JWT.
- RFC7515: JOSE Header and Base64url encoding (URL-safe base64 without padding, per RFC7515 Section 2).
- RFC7516: JWE.
- OAuth 2.0 Multiple Response Type Encoding Practices: Response Mode.

If a term conflicts with another spec, the definition in this OID4VP spec takes precedence.

### Core OID4VP terms
- **Biometrics-based Holder Binding**: Holder proves possession using biometric traits (for example face/fingerprint). Example: mobile driving license (ISO 18013-5) with holder portrait.
- **Claims-based Holder Binding**: Holder proves possession via claims (such as name and DOB), often by presenting another credential. Supports long-term and cross-device use because it does not rely on one device key.
- **Credential**: One or more claims about a subject issued by a Credential Issuer. In this spec, usually a Verifiable Credential. (Different meaning than "Credential" in OpenID Connect Core.)
- **Credential Format Identifier**: Identifier of a specific credential format in OID4VP, including format-specific parameters.
- **Credential Issuer (Issuer)**: Entity that issues credentials.
- **Cryptographic Holder Binding**: Holder proves control of the private key tied to credential issuance/presentation (mechanism depends on format).
- **Digital Credentials API (DC API)**: W3C Digital Credentials API on web platforms and equivalent native APIs (e.g., Android Credential Manager).
- **Holder**: Entity that receives credentials and controls them for presentation to verifiers.
- **Holder Binding / Key Binding**: Any method for the holder to prove legitimate possession of a credential.
- **Issuer-Holder-Verifier Model**: Claims are issued as credentials separately from later presentation; one issued credential can be reused multiple times.
- **Origin**: Platform-asserted identifier of calling website/app.  
  - Web origin = scheme + host + port (default port omitted), e.g., `https://verify.example.com`.  
  - Native app origin can be linked web origin or platform-specific URI.
- **Presentation**: Data derived from a credential and shown to a verifier. Usually verifiable presentations with holder binding, but can be without holder binding in some cases.
- **VP Token**: Artifact returned in authorization response containing one or more presentations (structure defined later in the spec).
- **Verifier**: Entity that requests, receives, and validates presentations. In OAuth terms, this is a specific type of Client.
- **Verifiable Credential (VC)**: Issuer-signed credential whose authenticity is cryptographically verifiable (format-agnostic; includes VCDM, mdoc, SD-JWT VC, etc.).
- **Verifiable Presentation (VP)**: Presentation that includes cryptographic proof of holder binding (also format-agnostic; includes VCDM, mdoc, SD-JWT VC, etc.).
- **Wallet**: Holder-controlled entity for receiving, storing, managing, and presenting credentials and keys. Can be local, self-hosted remote, or third-party remote.

## 3. Overview (Simplified)

OID4VP defines how a Verifier requests and receives Credential Presentations.

### Transport models
- **OAuth-style baseline**: HTTPS messages + redirects (aligned with OAuth 2.0).
- **DC API model**: OpenID4VP messages can also be exchanged through the Digital Credentials API instead of HTTPS redirects.

### Main protocol extension
- OID4VP introduces a new response type: **`vp_token`**.
- With `vp_token`, the Verifier receives a **VP Token** container holding one or more:
  - Verifiable Presentations (with holder binding), and/or
  - Presentations (possibly without holder binding, where allowed).
- So the primary output of this interaction is presentation data, not an OAuth access token.

### Credential format support
- The framework is format-agnostic and supports credential formats used in the Issuer-Holder-Verifier model, including VCDM, mdoc, and SD-JWT VC.
- A single transaction can include credentials/presentations from multiple formats.
- Main spec examples use W3C VC; additional format examples are in Appendix B.

### Device and response-delivery flexibility
- Supports same-device and cross-device flows (Verifier and Holder may interact on different devices from where credentials are stored).
- Supports sending responses by:
  - redirect, or
  - HTTP POST.  
  HTTP POST is useful for cross-device delivery and for large responses that may exceed URL length limits.

### Interoperability note (important)
- OID4VP is a framework and requires **profiles** for interoperability.
- A profile should define at least:
  - which optional features are used/required (for example response encryption),
  - allowed parameter values (for example credential format identifiers),
  - and optionally extra extensions.

## 3.1 Same Device Flow (Simplified)

This flow is for the case where:
- the End-User interacts with the Verifier on a device, and
- the Wallet is on that same device.

The baseline exchange uses redirects between Verifier and Wallet.

If response mode is `fragment`, the returned presentations are carried in the fragment of the redirect URI.

> Note: The reference diagram is simplified and does not show every optional feature in the specification.

### Step (1): Authorization Request (Verifier -> Wallet)
- The Verifier sends an Authorization Request containing a **DCQL** query (Section 6).
- DCQL expresses what the Verifier needs, for example:
  - credential type(s),
  - accepted format(s),
  - and specific claims (including selective disclosure needs).
- The Wallet evaluates available credentials against this request.
- The Wallet authenticates the End-User and collects consent for what will be presented.

### Step (2): Authorization Response (Wallet -> Verifier)
- The Wallet prepares presentation data for the credentials the End-User approved.
- The Wallet returns an Authorization Response to the Verifier.
- The resulting presentations are delivered in the **`vp_token`** parameter.

## 3.2 Cross Device Flow (Simplified)

This flow is for the case where:
- the End-User interacts with the Verifier on one device (device A), and
- the Wallet is on a different device (device B).

### Core pattern
- The Verifier typically encodes the initial request as a **QR code**.
- The Wallet scans the QR code.
- The final Authorization Response is sent directly to the Verifier using HTTP POST.

This flow uses:
- response type **`vp_token`**, and
- response mode **`direct_post`**.

### Why `request_uri` is used
- To keep QR codes small, the initial Authorization Request only carries minimal data (not the full request payload), including:
  - client identifier, and
  - `request_uri` (per RFC9101).
- The Wallet then retrieves the full Request Object from that URI.
- This also supports signed and optionally encrypted Request Objects without bloating the QR payload.

> Note: The reference diagram is simplified and does not show all parameters or optional features.
>
> Note: `request_uri` usage (RFC9101) is independent of other extension choices and can also be used in same-device flows.

### Step (1): Initial Authorization Request (Verifier -> Wallet)
- The Verifier sends an Authorization Request pointing to a `request_uri` where the full Request Object can be obtained.

### Step (2): Wallet fetches Request Object (Wallet -> Verifier)
- The Wallet sends HTTP GET to the `request_uri`.

### Step (2.5): Request Object returned (Verifier -> Wallet)
- The Verifier returns the Request Object with Authorization Request parameters.
- The Request Object includes a **DCQL** query describing requested credential requirements, such as:
  - credential types,
  - accepted formats,
  - specific claims/selective disclosure needs.
- The Wallet checks available credentials, authenticates the End-User, and gathers consent.

### Step (3): Authorization Response via direct POST (Wallet -> Verifier)
- The Wallet prepares presentations for credentials approved by the End-User.
- The Wallet sends the Authorization Response to the Verifier via HTTP POST.
- The presentations are carried in **`vp_token`**.

## 4. Scope (Simplified)

OID4VP extends OAuth 2.0 with new capabilities for credential presentation.

### Main additions in scope
- **DCQL (Digital Credentials Query Language)**: a new query language for flexible presentation requests (details in Section 6).
- **`dcql_query` request parameter**: new Authorization Request parameter carrying a JSON-encoded DCQL query (details in Section 5).
- **`vp_token` response parameter**: new parameter to return presentations (with or without holder binding), in Authorization or Token Response depending on response type (details in Section 8).
- **New response types**:
  - `vp_token`
  - `vp_token id_token`  
  These request credential presentations in the Authorization Response, optionally alongside a Self-Issued ID Token (SIOPv2).
- **New response mode `direct_post`**: supports cross-device delivery and large responses that may not fit in redirect URLs (details in Section 8.2).
- **`format` parameter usage across protocol**: enables format-specific customization for different credential ecosystems (examples include VC Data Model, mdoc, SD-JWT VC in Appendix B).
- **Client Identifier Prefix concept**: allows deployments to use mechanisms outside RFC6749 scope to obtain and validate Verifier metadata.
- **OID4VP over Digital Credentials API mechanism**: specified in Appendix A.
- **Composability with other flows**: credential presentation can be combined with:
  - End-User authentication via SIOPv2, and
  - OAuth 2.0 Access Token issuance.

## 5. Authorization Request (Simplified)

OID4VP Authorization Requests follow OAuth 2.0 (RFC6749), with RFC9700 recommendations where applicable.

### Request Object / JAR behavior
- Verifier MAY send the Authorization Request as a JAR Request Object (by value or by reference), per RFC9101.
- Verifier **MUST** set Request Object JOSE header `typ` to `oauth-authz-req+jwt`.
- Wallet **MUST NOT** process a Request Object if `typ` is missing or has another value.

### `client_id` vs `iss` in Request Object
- `client_id` is required by this spec.
- `iss` MAY still appear for compatibility with existing JAR implementations.
- If `iss` is present, Wallet **MUST ignore** it.

### Capability exchange hook via `request_uri_method=post`
- This spec adds a mechanism so Wallet can share technical capabilities to help Verifier tailor requests.
- Verifier can set `request_uri_method=post` (with `request_uri`) to signal Wallet may POST capabilities to the request URI endpoint (details in Section 5.10).
- Wallets that do not support this feature MAY continue with normal JAR behavior.

### Credential request expression
- Verifier expresses requested credential requirements using `dcql_query`.
- Wallet implementations **MUST** evaluate DCQL and select candidate credentials using Section 6.4 evaluation rules.

### Client Identifier Prefix and metadata handling
- Verifier uses a Client Identifier Prefix in `client_id` to tell Wallet how to interpret client identity and related data.
- This enables deployment-specific metadata validation/lookup mechanisms beyond RFC6749.
- Depending on prefix rules, Verifier may need signed requests and/or extra parameters that Wallet must process.
- Verifier can send `client_metadata` JSON to communicate metadata values.

### Unknown parameters behavior
- Extra parameters MAY be defined (per RFC6749 extensibility).
- Wallet **MUST ignore** unknown parameters, **except** `transaction_data`.
- Wallets that do not support `transaction_data` **MUST reject** requests containing it.

## 5.1 New Parameters (Simplified)

### `dcql_query`
- JSON object containing a DCQL query (Section 6).
- Exactly one of the following must be used:
  - `dcql_query`, or
  - `scope` representing a DCQL query.
- They **MUST NOT** both be present in the same Authorization Request.
- In `application/x-www-form-urlencoded` requests, object parameters are transmitted as JSON-serialized strings.

### `client_metadata` (OPTIONAL)
- UTF-8 JSON object with Verifier metadata.
- Supported metadata fields:
  - `jwks` (OPTIONAL): JWK Set (RFC7591) with public keys for purposes such as response encryption key agreement or VP generation needs.
    - May contain ephemeral request-specific keys.
    - Keys here **MUST NOT** be used to verify signatures of signed Authorization Requests.
    - Each JWK **MUST** include a unique `kid` within the request context.
  - `encrypted_response_enc_values_supported` (OPTIONAL): non-empty list of JWE `enc` algorithms for response encryption.
    - If response mode requires encrypted responses (e.g., `dc_api.jwt`, `direct_post.jwt`), this parameter **MUST** be present unless default `A128GCM` is the only value used.
    - Otherwise it **SHOULD** be absent.
  - `vp_formats_supported` (REQUIRED when not otherwise available): as defined in Section 11.1.
- If Wallet has authoritative client data from other trusted sources (for example federation statements), that authoritative data takes precedence over `client_metadata`.
- Other metadata keys **MUST** be ignored unless a profile explicitly allows them in `client_metadata`.

### `request_uri_method` (OPTIONAL)
- String controlling how Wallet fetches `request_uri`.
- Valid values (case-sensitive): `get`, `post`.
  - `get`: Wallet **MUST** fetch Request Object using HTTP GET (RFC9101 behavior).
  - `post`: supporting Wallet **MUST** use HTTP POST as defined in Section 5.10.
- If missing, Wallet **MUST** process `request_uri` per RFC9101 default behavior.
- Wallets without POST support will use GET.
- `request_uri_method` **MUST NOT** be present if `request_uri` is absent.
- If Verifier sets `request_uri_method=post` and has no other way to share capabilities, it **SHOULD** include `client_metadata` so Wallet can send only relevant `wallet_metadata` in the Request URI POST flow.

### `transaction_data` (OPTIONAL)
- Non-empty array of strings.
- Each string is a base64url-encoded JSON object representing typed transaction details to be authorized by End-User (Section 8.4).
- Wallet **MUST** return error if any transaction item:
  - has an unrecognized `type`, or
  - does not conform to that type's definition.
- Common fields for each decoded transaction object:
  - `type` (REQUIRED): transaction data type identifier.
    - Specific type values are out of scope here.
    - Collision-resistant type naming is RECOMMENDED.
  - `credential_ids` (REQUIRED): non-empty array of DCQL credential query IDs that may authorize this transaction.
    - If multiple IDs are listed, Wallet **MUST** use only one referenced credential for transaction authorization.
- Type-specific documents define what credentials can authorize a given transaction type.
- How issuers express credential authorization capability is out of scope.

Non-normative decoded example:
```json
{
  "type": "example_type",
  "credential_ids": ["id_card_credential"]
}
```

### `verifier_info` (OPTIONAL)
- Non-empty array of attestations about the Verifier relevant to credential request evaluation.
- Intended uses: support authorization decisions, wallet policy enforcement, and richer consent UX.
- Each entry contains:
  - `format` (REQUIRED): format identifier defining attestation encoding/processing rules (collision-resistant values are recommended).
  - `data` (REQUIRED): object or string containing attestation content (e.g., JWT); schema is format-specific.
  - `credential_ids` (OPTIONAL): non-empty array of DCQL credential query IDs this attestation applies to; if omitted, applies to all requested credentials.
- Wallet decides whether to use `verifier_info` based on trust frameworks, issuer/ecosystem policies, and profile rules.
- If Wallet uses it, Wallet **MUST** validate signatures and verify binding.
- See Section 5.11 for more details.

Non-normative example:
```json
{
  "format": "jwt",
  "data": "eyJhbGciOiJFUzI1...EF0RBtvPClL71TWHlIQ",
  "credential_ids": ["id_card"]
}
```

## 5.2 Existing Parameters (Simplified)

OID4VP reuses standard Authorization Request parameters, with additional rules:

### `nonce`
- **REQUIRED**.
- Used to securely bind returned Verifiable Presentation(s) to this specific transaction.
- Verifier **MUST**:
  - generate a fresh, cryptographically random nonce with sufficient entropy for each Authorization Request,
  - store it with the current session,
  - send it in the Authorization Request.
- Allowed characters are ASCII URL-safe only:
  - uppercase/lowercase letters,
  - digits,
  - `-`, `.`, `_`, `~`.
- See Section 14.1 for details.

### `scope`
- **OPTIONAL** (RFC6749).
- Wallet MAY support requesting presentations via predefined scope values.
- See Section 5.5 for profile behavior/details.

### `response_mode`
- **REQUIRED**.
- Defined by OAuth response-mode specs, with OID4VP-specific usage:
  - can request HTTPS push-style response delivery via `direct_post` (Section 8.2),
  - can request encrypted responses (Section 8.3).

### `client_id`
- **REQUIRED**.
- Uses RFC6749 semantics plus OID4VP requirements for Client Identifier Prefixes (Section 5.9).
- Client Identifier may be issued/defined by parties other than Wallet.
- Uniqueness is considered in combination of:
  - Client Identifier Prefix + Client Identifier.

### `state`
- **REQUIRED** only under conditions in Section 5.3; otherwise **OPTIONAL**.
- If used, value characters are limited to ASCII URL-safe set:
  - uppercase/lowercase letters,
  - digits,
  - `-`, `.`, `_`, `~`.

## 5.3 Requesting Presentations Without Holder Binding Proofs (Simplified)

OID4VP mainly targets Verifiable Presentations with cryptographic holder binding.
Still, it also supports requests for presentations **without** cryptographic holder binding proof.

### When this is used
- Low-security credentials that do not support holder binding (example: cinema ticket).
- Credentials bound by biometrics.
- Credentials bound by claims (example: diploma).
- Cases where credential supports holder binding, but Verifier chooses not to require it.

### Security consequence
- If Verifier accepts presentations without holder binding proof, it accepts replay risk.
- Additional security considerations are in Section 14.1.

### How to request it
- Verifier uses DCQL parameter **`require_cryptographic_holder_binding`** (see Section 6 and Appendix B).

### Request-response binding requirements in this case
In normal holder-binding flows, `nonce` helps bind request and response and protects against replay in the holder-binding proof.
When no cryptographic holder-binding proof is requested, `nonce` is not returned in response for that purpose, so request/response correlation must rely on `state`.

If at least one presentation without holder binding is requested, Verifier **MUST** (unless DC API is used):
- include `state` in the Authorization Request (RFC6749 Section 4.1.1),
- ensure `state` is a cryptographically strong pseudo-random value with at least 128 bits entropy,
- generate a fresh `state` for each Authorization Request,
- store `state` in Verifier session state,
- verify the same `state` value is returned in Authorization Response.

Exception:
- When using Digital Credentials API, internal platform mechanisms maintain request/response binding.

Additional note:
- For `direct_post` response mode, also apply Section 14.3 considerations.

## 5.4 Examples (Simplified)

Verifier can send Authorization Request in three ways:
- URL with encoded request parameters.
- Request Object passed by value (`request` parameter).
- Request Object passed by reference (`request_uri` parameter).

The last two are JAR options from RFC9101.

### Example pattern 1: URL-encoded request parameters
- Typical request includes values such as:
  - `response_type=vp_token`
  - `client_id`
  - `redirect_uri`
  - `dcql_query`
  - `transaction_data` (if used)
  - `nonce`

### Example pattern 2: Request Object by value
- Request carries a signed, base64url-encoded Request Object in `request=...`.
- Decoded payload can include:
  - standard request fields (`aud`, `response_type`, `client_id`, `redirect_uri`, `nonce`),
  - `dcql_query` describing credential/claim requirements.
- Example shown in spec uses signed JWT Request Object (e.g., RS256).

### Example pattern 3: Request Object by reference
- Initial request includes:
  - `client_id`
  - `request_uri`
  - optional `request_uri_method=post`
- Wallet fetches full Request Object from `request_uri`.
- If `request_uri_method=post` is used, Wallet may send an HTTP POST including wallet capability information (e.g., `wallet_metadata` and `wallet_nonce`) to retrieve a verifier-tailored Request Object.

All examples in this section are non-normative.

## 5.5 Using `scope` to Request Presentations (Simplified)

Wallets MAY support presentation requests via OAuth 2.0 `scope` values.

### Core rule
- Each scope value used for this purpose **MUST** map to (be an alias of) a well-defined DCQL query.

### Multiple scopes and identifier uniqueness
- If multiple scope values are used together, DCQL queries behind those scopes may be combined.
- Therefore, credential identifiers and claim identifiers in those mapped DCQL queries **MUST** be unique across the combined set.
- Goal: avoid ID collisions and allow Verifier to unambiguously identify requested credentials in responses.

### What this spec does not define
- Exact scope values and their mapping to DCQL are out of scope.
- Implementations/ecosystems can define mappings through:
  - separate normative/profile specifications, or
  - machine-readable wallet metadata that maps scope -> equivalent DCQL.

### Recommendation
- Use collision-resistant scope values.

### Example intent
- A request can use `scope=<presentation_scope_alias>` instead of explicit `dcql_query` (non-normative example shown in spec).

## 5.6 Response Type `vp_token` (Simplified)

OID4VP defines response type **`vp_token`**.

### Required behavior
- If Authorization Request has `response_type=vp_token`, a successful response **MUST** include `vp_token`.
- In successful response to this grant, Wallet **SHOULD NOT** return:
  - OAuth Authorization Code,
  - Access Token,
  - Access Token Type.

### Response mode behavior
- Default response mode for `vp_token` is **`fragment`**.
- So by default, Authorization Response parameters are returned in redirect URI fragment.
- `vp_token` can also be used with other response modes defined by OAuth response-mode specs.
- Both success and error responses **SHOULD** use:
  - the supplied response mode, or
  - default mode if none is supplied.

See Section 8 for response details tied to `response_type`.

## 5.7 Passing Authorization Request Across Devices (Simplified)

When request is shown on one device and Wallet/credentials are on another device, Authorization Request can be transferred via QR code.

Recommendation:
- Use `request_uri` together with response mode `direct_post`.
- Reason: full Authorization Requests can be too large to fit directly in a QR payload.

## 5.8 `aud` of a Request Object (Simplified)

If Verifier sends a Request Object (RFC9101), `aud` depends on discovery mode:
- With Dynamic Discovery: `aud` **MUST** equal Wallet issuer (`iss`) value.
- With Static Discovery metadata: `aud` **MUST** be `"https://self-issued.me/v2"`.

Note:
- `"https://self-issued.me/v2"` is a symbolic value and can be used even when OID4VP is used without SIOPv2.

## 5.9 Client Identifier Prefix and Verifier Metadata Management (Simplified)

OID4VP introduces **Client Identifier Prefix** to define how Wallet interprets `client_id` and associated metadata for:
- client identification,
- client authentication,
- client authorization.

### Purpose
- Enables deployment-specific mechanisms for obtaining/validating Verifier metadata beyond RFC6749.
- Name uses "Client" terminology because Verifier acts as OAuth Client in this protocol.

### How it is conveyed
- Prefix MAY be included in `client_id` value by Verifier.
- If no prefix is provided, fallback/default behavior remains pre-registered client style per RFC6749.

### Effects of a prefix
- Specific prefix rules may require:
  - signed Authorization Requests for authentication, and/or
  - additional parameters that Wallet must process.

## 5.9.1 Syntax (Simplified)

Client Identifier Prefix syntax is:

`<client_id_prefix>:<orig_client_id>`

- `<client_id_prefix>` = prefix defining interpretation/auth rules.
- `<orig_client_id>` = client identifier within that prefix namespace.

### Parsing and interpretation rules
- Wallet **MUST** inspect `client_id` for a `:` character.
- If `:` exists and text before it is a recognized/supported prefix, Wallet **MUST** process `client_id` under that prefix's rules.
- Prefix is the substring before the **first** `:`.
- Implementations should not assume the whole value is a valid URI just because `:` exists.
- Parsing must follow the rules defined for the selected prefix type (Section 5.9.3).

### Example behavior
- `client_id=verifier_attestation:example-client`
  - Prefix: `verifier_attestation`
  - Client identifier in that namespace: `example-client`
- The **full** string (`verifier_attestation:example-client`) is used as client identifier throughout OAuth flow, including as audience/intended receiver where applicable.

### Operational note
- Verifier should know which Client Identifier Prefixes a Wallet supports before sending request, so it can choose a supported prefix.

### Metadata note
- Depending on prefix rules, Verifier can include `client_metadata` JSON with name/value pairs.

## 5.9.2 Fallback (Simplified)

### No prefix present
- If `client_id` has no `:` character, Wallet **MUST** treat it as a pre-registered client (RFC6749 default model).
- So client must be known to Wallet before request.
- Verifier metadata is obtained via RFC7591 mechanisms or out-of-band means.

Example intent:
- `client_id=example-client` -> interpreted as pre-registered client.

### Unknown prefix-like value
- If `:` is present but text before it is not a recognized/supported prefix:
  - Wallet may treat it as pre-registered client, or
  - Wallet may reject the request.

### Naming constraint for pre-registered clients
- Pre-registered client IDs **MUST NOT** begin with a supported Client Identifier Prefix followed immediately by `:`.

## 5.9.3 Defined Client Identifier Prefixes (Simplified)

This spec defines these prefixes and processing rules.

Important DC API note:
- In OpenID4VP over DC API (Appendix A), Wallet may decide whether to enforce Request Object signature validation according to a prefix's normal rules, based on trust framework/policies/profile choices.

### `redirect_uri`
- Meaning: value after prefix is Verifier redirect URI (or response URI for `direct_post`).
- Verifier MAY omit explicit `redirect_uri` parameter (or `response_uri` in `direct_post`) because it is encoded in `client_id`.
- All Verifier metadata **MUST** be provided via `client_metadata`.
- Requests with this prefix cannot be signed in a trustable way (no trusted key source for Wallet), so deployments requiring signed requests cannot use this prefix.

### `openid_federation`
- Meaning: value after prefix is OpenID Federation Entity Identifier.
- Wallet **MUST** apply OpenID Federation processing rules.
- Request MAY include `trust_chain`.
- Final Verifier metadata comes from trust chain after policy application.
- `client_metadata`, if present, **MUST** be ignored with this prefix.

### `decentralized_identifier`
- Meaning: value after prefix is a DID.
- Request **MUST** be signed by key associated with that DID.
- Wallet **MUST** obtain verification key from DID Document `verificationMethod`.
- JOSE header `kid` **MUST** identify which key in DID Document was used.
- Wallet **MUST** resolve DID per DID method resolution rules.
- Verifier metadata other than public key **MUST** come from `client_metadata`.

### `verifier_attestation`
- Verifier authenticates using attestation JWT bound to a public key (Section 12).
- Value after prefix **MUST** equal `sub` claim in Verifier Attestation JWT.
- Request **MUST** be signed by private key corresponding to key in attestation JWT `cnf`.
- Verifier attestation JWT **MUST** be included in Request Object JOSE header `jwt`.
- Wallet **MUST** validate attestation JWT signature.
- Attestation JWT `iss` **MUST** identify a trusted attestation issuer; if trust cannot be established, Wallet **MUST** reject.
- If attestation includes `redirect_uris`, Wallet **MUST** require exact match of request `redirect_uri` with one listed value.
- Verifier metadata other than public key **MUST** come from `client_metadata`.

### `x509_san_dns`
- Value after prefix **MUST** be DNS name.
- That DNS name **MUST** match a `dNSName` SAN in leaf certificate sent with request.
- Request **MUST** be signed with private key matching leaf cert public key.
- Certificate chain is supplied via JOSE header `x5c`.
- Wallet **MUST** validate request signature and X.509 trust chain.
- Verifier metadata other than public key **MUST** come from `client_metadata`.
- Unless using DC API:
  - if Wallet trusts authenticated client identifier (e.g., trusted list), it may allow flexible `redirect_uri`;
  - otherwise FQDN of `redirect_uri` **MUST** match DNS name in client ID (without prefix).

### `x509_hash`
- Value after prefix **MUST** be hash of leaf certificate sent with request.
- Request **MUST** be signed with private key matching leaf cert public key.
- Certificate chain is supplied in JOSE header `x5c`.
- `x509_hash` value = base64url-encoded SHA-256 hash of DER-encoded leaf certificate.
- Wallet **MUST** validate request signature and X.509 trust chain.
- Verifier metadata other than public key **MUST** come from `client_metadata`.

### `origin` (reserved)
- Defined in Appendix A.2.
- Wallet **MUST NOT** accept this prefix in requests.
- In OpenID4VP over DC API, presentation audience is always `origin:<origin-value>` (example: `origin:https://verifier.example.com/`).

### Key management requirement
- Prefixes `openid_federation`, `decentralized_identifier`, `verifier_attestation`, `x509_san_dns`, and `x509_hash` require Verifier capability to securely store private keys.
- This can affect native-app architectures, since such apps are often public clients.

### Extensibility
- Other specs may define additional prefixes.
- Collision-resistant prefix names are RECOMMENDED.

## 5.10 Request URI Method `post` (Simplified)

This section defines how Wallet calls the Verifier's Request URI endpoint when `request_uri_method=post` is used.

### HTTP requirements
- Request **MUST** use HTTP `POST`.
- Scheme **MUST** be `https`.
- `Content-Type` **MUST** be `application/x-www-form-urlencoded`.
- `Accept` header **MUST** be `application/oauth-authz-req+jwt`.
- Body names/values **MUST** be UTF-8 encoded.

### Defined request parameters to Request URI endpoint
- `wallet_metadata` (OPTIONAL):
  - string containing JSON object with wallet metadata parameters (Section 10).
- `wallet_nonce` (OPTIONAL):
  - value used to mitigate replay of Authorization Request.
  - when present, Verifier **MUST** copy/use this value as `wallet_nonce` in signed Authorization Request Object.
  - value can be a fresh, high-entropy, cryptographically random value (base64url is suitable).

### Capability signaling guidance
- If Wallet requires encrypted Request Object, it **SHOULD** provide encryption public keys via `jwks` in `wallet_metadata`.
- If Wallet requires encrypted Authorization Response, it **SHOULD** provide supported encryption algorithms using:
  - `authorization_encryption_alg_values_supported`
  - `authorization_encryption_enc_values_supported`
- If current Client Identifier Prefix allows signed Request Objects, Wallet **SHOULD** include supported request signing algorithms via:
  - `request_object_signing_alg_values_supported`
- If prefix does **not** allow signed Request Objects, Wallet **MUST NOT** include `request_object_signing_alg_values_supported`.

### Extensibility/robustness
- Additional parameters may be used.
- Verifier **MUST** ignore unknown parameters.

All examples in this section are non-normative.

## 5.10.1 Request URI Response (Simplified)

### Response format requirements
- Verifier response from Request URI endpoint **MUST** be HTTP with:
  - `Content-Type: application/oauth-authz-req+jwt`
  - body containing signed (optionally encrypted) Request Object per RFC9101.
- Returned Request Object **MUST** satisfy Section 5 requirements.

### Wallet processing requirements
- Wallet **MUST** process Request Object per RFC9101.
- If Wallet sent `wallet_nonce` in POST request:
  - Request Object **MUST** contain matching `wallet_nonce` claim.
  - If missing or mismatched, Wallet **MUST** terminate processing.

### Parameter source and consistency rules
- Wallet **MUST** extract Authorization Request parameters from the Request Object.
- Wallet **MUST only** use parameters from that Request Object, even if same names were in outer Authorization Request query.
- `client_id` in outer Authorization Request parameter and `client_id` claim in Request Object **MUST** be identical (including prefix).
- If any of these checks fail, Wallet **MUST** terminate processing.

### Final validation
- After successful extraction/checks, Wallet validates request under OAuth 2.0 (RFC6749).

## 5.10.2 Request URI Error Response (Simplified)

- If Verifier returns any HTTP error response from Request URI endpoint, Wallet **MUST** terminate the process.

## 5.11 Verifier Info (Simplified)

`verifier_info` allows Verifier to include extra attested context/metadata in Authorization Request, typically backed by trusted third parties.

### Purpose
- Supports wallet policy decisions.
- Helps eligibility/authorization checks.
- Improves End-User consent UX with richer context.

### Structure and semantics
- Each Verifier Info object includes:
  - a type/format identifier,
  - associated data,
  - optional references to credential identifiers.
- Exact attestation semantics are profile/ecosystem-defined.

### Typical examples
- Registration certificate proving verifier is officially registered to request certain credentials.
- Signed policy statement (usage, retention, access rights, etc.).
- Domain-role confirmation (for example, regulated payment service provider status).

### Processing expectations
- `verifier_info` is optional.
- Wallet MAY use it for decisions or user messaging.
- Wallet SHOULD ignore unsupported/unrecognized Verifier Info types.

## 5.11.1 Proof of Possession (Simplified)

This specification supports two PoP models for verifier attestations:

### 1) Claim-bound attestations
- Attestation itself is not verifier-signed but is bound to verifier by claims.
- Binding mechanism depends on attestation type definition.
- Example: in JWT-based attestation, `sub` can reference certificate distinguished name used to sign request.
- Binding may also include `client_id`.

### 2) Key-bound attestations
- Verifier signs a proof-of-possession object using key contained in or related to attestation.
- To bind proof to current request, signature object should include request `nonce` and `client_id`.
- Attestation and its PoP must be carried together in attachment.

### Wallet validation rule
- If profile defines PoP validation requirements, Wallet **MUST** validate accordingly.
- Wallet must ignore or reject attachments that fail required validation.

## 6. Digital Credentials Query Language (DCQL) (Simplified)

DCQL is a JSON query language used by Verifier to request credential presentations that match specific requirements.

- Verifier can express constraints on:
  - which credentials are requested, and
  - which claim combinations are acceptable.
- Wallet evaluates query against held credentials and returns matching presentations.

### DCQL top-level object
A valid DCQL query is a JSON object with:

- `credentials` (**REQUIRED**): non-empty array of Credential Queries (Section 6.1).
- `credential_sets` (OPTIONAL): non-empty array of Credential Set Queries (Section 6.2) adding constraints on combinations of requested credentials to return.

Extensibility rule:
- Future extensions may add properties at top-level or deeper levels.
- Implementations **MUST ignore** unknown properties.

## 6.1 Credential Query (Simplified)

A Credential Query requests presentation of one or more matching credentials.

Each object in `credentials` includes:

- `id` (**REQUIRED**):
  - identifier used in response and in `credential_sets` references.
  - non-empty string using only alphanumeric, `_`, `-`.
  - must be unique within Authorization Request (`id` must not repeat).

- `format` (**REQUIRED**):
  - requested credential format identifier (defined in Appendix B).

- `multiple` (OPTIONAL):
  - boolean allowing multiple credentials for this query.
  - default is `false`.

- `meta` (**REQUIRED**):
  - object with format-specific constraints over credential metadata/validity.
  - if empty, no specific metadata/validity constraints are imposed.

- `trusted_authorities` (OPTIONAL):
  - non-empty array of Trusted Authorities Query objects (Section 6.1.1).
  - each returned credential **SHOULD** match at least one listed trusted-authority condition, if this parameter is present.
  - verifier still must independently validate trust of received issuer; this field mainly supports data minimization.

- `require_cryptographic_holder_binding` (OPTIONAL):
  - boolean, default `true`.
  - `true`: cryptographic holder binding proof required.
  - `false`: verifier accepts credential without cryptographic holder binding proof.

- `claims` (OPTIONAL):
  - non-empty array of claim query objects (Section 6.3).
  - verifier **MUST NOT** point to same claim more than once in one query.
  - wallet **SHOULD** ignore duplicate claim queries.

- `claim_sets` (OPTIONAL):
  - non-empty array of arrays of identifiers referencing elements in `claims`.
  - defines requested combinations of claims (selection rules in Section 6.4.1).

Additional note:
- Multiple Credential Queries in one request may target presentation of the same underlying credential.

## 6.1.1 Trusted Authorities Query (Simplified)

Trusted Authorities Query helps identify acceptable issuer authority/trust-framework context.

- A credential matches this query if it matches at least one provided value in one provided type (matching rules depend on type).
- Direct issuer matching can sometimes also be done via claim-value matching (e.g., `iss` in SD-JWT) where trusted_authorities mechanisms are not applicable, but this may be less reliable due to value-matching constraints.

Each `trusted_authorities` entry includes:

- `type` (**REQUIRED**): trusted-authority query type identifier.
- `values` (**REQUIRED**): non-empty array of type-specific strings used for matching issuer/trust framework/federation context.

Privacy note:
- Different trusted-authority types may have different privacy implications (see Section 15.10).

### 6.1.1.1 Type `aki` (Authority Key Identifier)
- `type`: `"aki"`.
- Each value is base64url-encoded KeyIdentifier of X.509 AuthorityKeyIdentifier (RFC5280 4.2.1.1).
- Raw bytes must match AuthorityKeyIdentifier in some certificate in credential's certificate chain.
- Chain may have one certificate or more, and credential may include full or partial chain.

Non-normative example:
```json
{
  "type": "aki",
  "values": ["s9tIpPmhxdiuNkHMEWNpYim8S8Y"]
}
```

### 6.1.1.2 Type `etsi_tl` (ETSI Trusted List)
- `type`: `"etsi_tl"`.
- Each value is identifier/URL of ETSI Trusted List (ETSI TS 119 612).
- Matching credential trust chain must contain at least one certificate matching entries in that trusted list (or its cascading referenced lists).

Non-normative example:
```json
{
  "type": "etsi_tl",
  "values": ["https://lotl.example.com"]
}
```

### 6.1.1.3 Type `openid_federation`
- `type`: `"openid_federation"`.
- Each value is OpenID Federation Entity Identifier.
- Matching requires a valid constructible trust path that includes that entity identifier (commonly a trust anchor).

Non-normative example:
```json
{
  "type": "openid_federation",
  "values": ["https://trustanchor.example.com"]
}
```

## 6.2 Credential Set Query (Simplified)

A Credential Set Query describes one use case at Verifier and the credential combinations that can satisfy it.

Each entry in `credential_sets` includes:

- `options` (**REQUIRED**):
  - non-empty array;
  - each element is a non-empty array of identifiers referencing entries in `credentials`;
  - each such inner array represents one acceptable credential combination.

- `required` (OPTIONAL):
  - boolean indicating whether this credential set is mandatory for satisfying the use case;
  - default is `true`.

UX recommendation:
- Before sending the request, Verifier **SHOULD** communicate to End-User the purpose/context/reason for the query.

## 6.3 Claims Query (Simplified)

Each entry in `claims` includes:

- `id`:
  - **REQUIRED** if `claim_sets` exists in same Credential Query;
  - OPTIONAL otherwise.
  - when used: non-empty string with alphanumeric, `_`, `-` only.
  - within one `claims` array, same `id` **MUST NOT** repeat.

- `path` (**REQUIRED**):
  - non-empty array representing claim path pointer into credential (Section 7).

- `values` (OPTIONAL):
  - non-empty array of allowed literal values (string/integer/boolean).
  - if present, Wallet **SHOULD** return claim only when both type and value exactly match at least one listed value.
  - processing details are in Section 6.4.1.

ISO mdoc value-matching note:
- If matching ISO mdoc credentials and Wallet supports value matching, matching must use JSON form of the CBOR value.
- Conversion should follow RFC8949 Section 6.1 guidance.
- If conversion behavior is unclear, behavior is out of scope.

## 6.4 Selecting Claims and Credentials (Simplified)

This section defines claim/credential selection logic.

### Privacy and selective disclosure baseline
- For selectively disclosable formats, rules are designed to minimize data disclosure.
- Wallet **MUST NOT** send selectively disclosable claims not selected by these rules.
- A presentation may contain additional claims if:
  - same credential is selected with additional claims in another Credential Query in same request, or
  - those additional claims are not selectively disclosable.

## 6.4.1 Selecting Claims (Simplified)

Rules for `claims` and `claim_sets`:

1. If `claims` is absent:
   - Verifier requests no selectively disclosable claims.
   - Wallet **MUST** return only mandatory-to-present claims for the format (e.g., SD-JWT + Key Binding JWT pieces for SD-JWT VC).

2. If `claims` present and `claim_sets` absent:
   - Verifier requests all claims listed in `claims`.

3. If both `claims` and `claim_sets` present:
   - Verifier requests one combination from `claim_sets`.
   - Order in `claim_sets` expresses Verifier preference.
   - Wallet **SHOULD** return first satisfiable option.
   - If Wallet cannot satisfy any option, Wallet **MUST NOT** return any claims.

4. `claim_sets` **MUST NOT** be present if `claims` is absent.

### Value-restriction behavior
- If a claim query includes `values` restriction and value does not match, Wallet **SHOULD NOT** return that claim (treat as if absent).
- In some implementations this may not be possible (e.g., value unavailable before consent/routing boundaries).
- Final behavior can depend on Wallet and/or End-User choices.
- Therefore Verifier **MUST** treat `values` restrictions as privacy best-effort only, not as a security control.

### Purpose of `claim_sets`
- Expresses alternative claim combinations that can satisfy request for one credential.
- Ordering signals Verifier preference (first = most preferred).
- Verifiers **SHOULD** order options by least disclosure principles (e.g., `age_over_18` before `birth_date`).
- `claim_sets` is not intended as End-User choice UI model (see Section 6.4.3).
- Wallet is recommended to return first satisfiable option, but may deviate for valid reasons (e.g., poor verifier ordering or wallet UX/operational needs).

### Failure to satisfy requested claims
- If Wallet cannot deliver all required claims per these rules, it **MUST NOT** return that credential.

### Non-selective-disclosure formats
- For formats without selective disclosure, absence of both `claims` and `claim_sets` means request for full credential (all claims mandatory by format).

## 6.4.2 Selecting Credentials (Simplified)

Rules for credential selection using `credentials` and `credential_sets`:

- If `credential_sets` is absent:
  - Verifier requests presentations for **all** Credential Queries in `credentials`.

- If `credential_sets` is present:
  - Wallet must satisfy **all** Credential Set Queries where `required=true` or omitted.
  - Wallet may additionally satisfy optional sets (`required=false`).
  - To satisfy one Credential Set Query, Wallet **MUST** return a credential combination matching one of its `options`.

- Any credential that does not satisfy constraints in its corresponding Credential Query **MUST NOT** be returned (treat as unavailable).

- If Wallet cannot satisfy all non-optional credential requirements, it **MUST NOT** return any credentials.

## 6.4.3 User Interface Considerations (Simplified)

- The specification defines request/selection mechanics, not wallet UI behavior.
- It does not mandate how End-User choice is presented.
- In practice, if multiple `options` sets can satisfy request, Wallet is typically expected to let End-User choose which credential combination to present.

## 7. Claims Path Pointer (Simplified)

A claims path pointer identifies one or more claims inside a credential.

- It **MUST** be a non-empty array of:
  - strings,
  - `null`,
  - non-negative integers.
- Processing a pointer means applying it to a credential and obtaining referenced claim(s).

## 7.1 Semantics for JSON-based Credentials (Simplified)

When applied to JSON credentials:

- String component -> select object property by key.
- `null` component -> select all elements of current array(s).
- Non-negative integer -> select array element at that index.

Path building intuition:
- append string for object field selection,
- append integer for specific array index,
- append `null` for all array elements.

## 7.1.1 Processing (Simplified)

Processing is left-to-right:

1. Start with credential root (top-level JSON object).
2. For each path component:
   - string:
     - current selected elements must be objects, else error;
     - select matching key in each selected object;
     - if key missing in one selected object, remove that element from selection.
   - `null`:
     - current selected elements must be arrays, else error;
     - select all array elements from each selected array.
   - non-negative integer:
     - current selected elements must be arrays, else error;
     - select indexed element from each array;
     - if index missing in one array, remove that array from selection.
   - anything else -> error.
3. If selection becomes empty at any point -> error.
4. Result is final selected JSON element set.

## 7.2 Semantics for ISO mdoc-based Credentials (Simplified)

For ISO mdoc, claims path pointer is exactly two strings:

1. namespace
2. data element identifier

## 7.2.1 Processing (Simplified)

- If pointer does not have exactly two string components -> error.
- Select namespace from first component; if missing -> error.
- Select data element from second component; if missing -> error.
- Result is selected data element value as CBOR data item.

## 7.3 Claims Path Pointer Example (Simplified)

For a JSON credential containing fields like `name`, `address`, `degrees[]`, `nationalities[]`:

- `["name"]` -> selects `name`.
- `["address"]` -> selects full `address` object.
- `["address", "street_address"]` -> selects nested street address.
- `["degrees", null, "type"]` -> selects all `type` values in `degrees`.
- `["nationalities", 1]` -> selects second nationality.

## 7.4 DCQL Example (Simplified)

Non-normative example intent:
- request one `dc+sd-jwt` credential,
- constrain type via `meta.vct_values`,
- request claims `last_name`, `first_name`, and `address.street_address`.

```json
{
  "credentials": [
    {
      "id": "my_credential",
      "format": "dc+sd-jwt",
      "meta": {
        "vct_values": ["https://credentials.example.com/identity_credential"]
      },
      "claims": [
        {"path": ["last_name"]},
        {"path": ["first_name"]},
        {"path": ["address", "street_address"]}
      ]
    }
  ]
}
```

More complex examples are in Appendix D.

## 8. Response (Simplified)

A VP Token is returned only if the related Authorization Request included:
- `dcql_query`, or
- `scope` representing a DCQL query.

Where VP Token appears depends on `response_type`:

- `vp_token` -> VP Token in **Authorization Response**
- `vp_token id_token` (+ `scope` includes `openid`) -> VP Token + Self-Issued ID Token in **Authorization Response**
- `code` -> VP Token in **Token Response**

Behavior for other response type combinations is unspecified.

## 8.1 Response Parameters (Simplified)

When VP Token is returned, response includes:

- `vp_token` (**REQUIRED**):
  - JSON object where:
    - each key = DCQL Credential Query `id`,
    - each value = array of one or more matching presentations.
  - If query `multiple` is omitted or `false`, array **MUST** contain exactly one presentation.
  - For optional Credential Queries with no match, there **MUST NOT** be an entry in `vp_token`.
  - Each presentation value is string or object depending on credential format (Appendix B).

Other parameters (e.g., `code`, `id_token`, `iss`) may also appear as defined in respective specs.

Extensibility rule:
- Additional response parameters may exist.
- Client **MUST** ignore unrecognized parameters.

### 8.1.1 Examples (Simplified)

Single presentation (example intent):
```json
{
  "my_credential": ["eyJhbGci...QMA"]
}
```

Multiple presentations when `multiple=true`:
```json
{
  "my_credential": ["eyJhbGci...QMA", "eyJhbGci...QMA"]
}
```

## 8.2 Response Mode `direct_post` (Simplified)

`direct_post` lets Wallet send Authorization Response to Verifier-controlled endpoint via HTTP POST.

### Why it exists
- Cross-device flows where redirect to verifier frontend is not sufficient.
- Responses too large for URL-based redirect modes (e.g., fragment).
- Enables delivery without requiring Wallet backend.

### Core behavior
- Authorization Response is sent via HTTP POST to verifier endpoint.
- Body **MUST** use `application/x-www-form-urlencoded`.
- Parameters in body **MUST** be UTF-8 encoded.

### `response_uri` request parameter
- **REQUIRED** when `response_mode=direct_post`.
- Wallet **MUST** post Authorization Response to this URL.
- When `response_uri` is present, `redirect_uri` in Authorization Request **MUST NOT** be present.
- If `redirect_uri` is present with `direct_post`, Wallet **MUST** return `invalid_request`.
- `response_uri` value must be one the client would be allowed to use as redirect URI under Section 5.9 rules.

Interpretation note:
- Spec text that refers to Redirect URI also applies to Response URI in `direct_post` context.

State/correlation note:
- Verifier frontend and response endpoint must correlate request/response.
- `state` can be used for this (see Section 13.3).

Unknown-parameter rule:
- Additional request parameters may exist with `direct_post`.
- Wallet **MUST** ignore unrecognized parameters.

### direct_post response posting examples (intent)
- Success POST body can include `vp_token` and `state`.
- Error POST body can include `error`, `error_description`, and `state`.

### Verifier endpoint reply back to Wallet
- After processing success/error POST, Response URI endpoint **MUST** reply:
  - HTTP 200
  - `Content-Type: application/json`
  - JSON body.

Defined JSON response parameter:
- `redirect_uri` (OPTIONAL):
  - if present, Wallet **MUST** redirect user agent to it.
  - used to continue flow on wallet device and can help mitigate session fixation risks.
  - may be returned for success or error cases.

Additional JSON response parameters may exist; Wallet **MUST** ignore unknown ones.

### Security requirements for returned `redirect_uri`
- `redirect_uri` must be absolute URI (RFC3986).
- Chosen by Verifier.
- Verifier **MUST** include fresh cryptographically random value in URL so only intended receiver can fetch/process response.
- Value can be in path, fragment, or query.
- 128-bit+ randomness is RECOMMENDED.

If verifier JSON reply does not include `redirect_uri`, Wallet has no further required step.

Security note:
- `direct_post` without `redirect_uri` can be less secure than redirect-based modes (see Section 14.2).

UX note:
- In `direct_post` / `direct_post.jwt`, Wallet UI may adapt based on verifier callback after submission.

## 8.3 Encrypted Responses (Simplified)

OID4VP allows application-layer encryption of Authorization Responses containing `vp_token` (e.g., for `vp_token` or `vp_token id_token` response types).

Purpose:
- Reduce risk of personal data leakage, especially in front-channel scenarios (e.g., browser).

### Encryption model
- Implementations **MUST** use an unsigned encrypted JWT (JWE-based) per JWT/JWA rules.
- Encrypted payload is a JSON object containing Authorization Response parameters.
- Response payload **MUST** include Section 8.1 response members as top-level JSON fields.

### How Wallet chooses encryption key and algorithms
- Wallet gets Verifier public keys from client metadata (e.g., `client_metadata.jwks`) or other mechanisms allowed by the active Client Identifier Prefix.
- Wallet chooses a suitable key based on JWK properties (e.g., `kty`, `use`, `alg`, etc.).
- In selected JWK, `alg` **MUST** be present.
- JWE header `alg` **MUST** equal chosen JWK `alg`.
- If chosen JWK has `kid`, JWE header **MUST** include same `kid` value.
- JWE `enc` is taken from `encrypted_response_enc_values_supported` in client metadata.
  - If not explicitly set, default `A128GCM` applies.

### Notes
- For ECDH-based JWE algorithms, `apu` and `apv` feed KDF and are bound via AEAD tag computation.
- JOSE encryption options may include HPKE-based approaches where supported by related JOSE work.

All concrete JSON/JWE snippets in this section are non-normative examples.

## 8.3.1 Response Mode `direct_post.jwt` (Simplified)

This mode combines:
- `direct_post` transport behavior (Section 8.2), and
- encrypted JWT response payload behavior (Section 8.3).

### Behavior
- Wallet sends Authorization Response via HTTP POST to Verifier endpoint.
- POST body uses `application/x-www-form-urlencoded` with UTF-8 encoding.
- Wallet sends a `response` parameter whose value is the encrypted JWT.

### Error fallback
- If Wallet cannot generate encrypted response, it **MAY** send an unencrypted error response as defined in Section 8.2.

All shown request/response examples are non-normative.

## 8.4 Transaction Data (Simplified)

Transaction data creates a binding between:
- user identification/authentication (via presented credential), and
- user authorization action (e.g., payment approval, document signing such as QES).

Core idea:
- Transaction data used for authorization is signed with the same user-controlled key used for proof of possession of presented credential.

Wallet requirements:
- If request includes `transaction_data`, Wallet **MUST** include a representation or reference to that data in the relevant credential presentation.
- Exact representation is transaction-data-type specific.
- Credential-format guidance may define recommended handling (e.g., Appendix B).
- If Wallet does not support `transaction_data`, it **MUST** return an error when such request is received.

## 8.5 Error Response (Simplified)

Base error behavior follows RFC6749, with OID4VP clarifications and additions.

### Clarified existing error codes

- `invalid_scope`:
  - requested scope is invalid, unknown, or malformed.

- `invalid_request` (examples):
  - both `dcql_query` and scope-as-DCQL are present;
  - `response_type=vp_token` without `dcql_query` or scope-as-DCQL;
  - unsupported Client Identifier Prefix;
  - `client_id`/prefix mismatch or prefix-rule violations (e.g., required signed request not signed).

- `invalid_client` (examples):
  - `client_metadata` supplied even though Wallet already recognizes client and has associated metadata;
  - pre-registered metadata found via `client_id`, but `client_metadata` still sent.

- `access_denied` (examples):
  - Wallet lacks requested credentials;
  - End-User denied consent;
  - End-User authentication failed.

### Additional OID4VP error codes

- `vp_formats_not_supported`:
  - Wallet supports none of requested credential/presentation formats.

- `invalid_request_uri_method`:
  - `request_uri_method` is neither `get` nor `post` (case-sensitive).

- `invalid_transaction_data`:
  - at least one transaction-data object has issues such as:
    - unknown/unsupported type,
    - unknown fields for known type,
    - wrong field types,
    - invalid field values,
    - missing required fields,
    - non-matching `credential_ids`,
    - referenced credential(s) unavailable in Wallet.

- `wallet_unavailable`:
  - Wallet cannot be invoked/respond (e.g., platform routing cannot launch wallet from claimed HTTPS URI), while another component handles request and returns error to Verifier.

## 8.6 VP Token Validation (Simplified)

Verifier **MUST** validate VP Token as follows:

1. Validate VP Token structure per Section 8.1.
2. For each returned presentation, verify per credential format:
   - integrity and authenticity of presentation/credential,
   - conformance with request criteria (e.g., required claims),
   - cryptographic holder-binding proof unless explicitly not required,
   - holder-binding replay protections (Section 14.1) when VP is expected,
   - trust/policy checks (e.g., framework requirements, revocation checks), if applicable.
3. Validate overall presentation set satisfies request constraints per Section 6.4.

Failure handling:
- If checks for one presentation fail, that presentation **MUST** be discarded.
- If VP Token-level or overall-response checks fail, VP Token **MUST** be rejected.

## 9. Wallet Invocation (Simplified)

Verifier can invoke Wallet using:
- custom URL scheme as `authorization_endpoint` (e.g., `openid4vp://`, see Section 13.1.2),
- URL-based `authorization_endpoint` (including domain-bound universal/app links).

For cross-device flows:
- either mechanism may be presented as QR code for user scanning (with Wallet app or camera app).

Alternative invocation:
- Wallet can also be invoked from web/native apps via Digital Credentials API (Appendix A).
- DC API can improve privacy, security, and UX, especially when user has multiple wallets.

## 10. Wallet Metadata (Authorization Server Metadata) (Simplified)

OID4VP defines metadata so Verifier can discover Wallet capabilities, especially:
- supported credential formats,
- proof types,
- cryptographic algorithms for exchange.

## 10.1 Additional Wallet Metadata Parameters (Simplified)

New metadata parameters are defined following RFC8414.

### `vp_formats_supported`
- **REQUIRED**.
- Object where:
  - key = Credential Format Identifier,
  - value = format-specific supported parameters.
- Concrete format values are defined in Appendix B.
- Deployments may extend formats if Issuer/Holder/Verifier ecosystems all understand them.

Example intent:
```json
"vp_formats_supported": {
  "jwt_vc_json": {
    "alg_values": ["ES256K", "ES384"]
  }
}
```

### `client_id_prefixes_supported`
- OPTIONAL, non-empty array of supported Client Identifier Prefix strings.
- Pre-registered values defined by this spec include:
  - `pre-registered` (no prefix behavior),
  - `redirect_uri`,
  - `openid_federation`,
  - `verifier_attestation`,
  - `decentralized_identifier`,
  - `x509_san_dns`,
  - `x509_hash`.
- If omitted, default is `pre-registered`.
- Profiles/extensions may define additional values.

### Extensibility rule
- Additional wallet metadata parameters may be used per RFC8414.
- Verifier **MUST** ignore unrecognized parameters.

## 10.2 Obtaining Wallet Metadata (Simplified)

Verifier has multiple ways to obtain Wallet metadata:

- **Dynamic retrieval**:
  - e.g., via RFC8414 discovery or other out-of-band mechanisms.

- **Static/pre-obtained metadata**:
  - Verifier may use metadata collected/configured ahead of time.
  - See Section 13.1.2 for example context.

## 11. Verifier Metadata (Client Metadata) (Simplified)

Verifier metadata is conveyed using Client Metadata model from RFC7591 Section 2.

Purpose:
- lets Wallet determine verifier-supported:
  - credential formats,
  - proof types,
  - cryptographic algorithms used in exchange.

## 11.1 Additional Verifier Metadata Parameters (Simplified)

OID4VP defines the following verifier-side client metadata parameter:

### `vp_formats_supported`
- **REQUIRED**.
- Object where:
  - key = Credential Format Identifier,
  - value = format-specific parameters supported by Verifier.
- Concrete allowed format details are in Appendix B.
- Ecosystems can extend formats if Issuer/Holder/Verifier all understand them.

### Extensibility rule
- Additional verifier metadata parameters may be defined per RFC7591.
- Wallet **MUST** ignore unrecognized parameters.

## 12. Verifier Attestation JWT (Simplified)

Verifier Attestation JWT is a dedicated JWT mechanism for Wallet to authenticate Verifier in a secure, flexible way.

- Attestation is issued by a party trusted by Wallet for verifier authentication/authorization.
- Trust establishment model is out of scope.
- Verifier is bound to a public key and **MUST** present:
  - Verifier Attestation JWT, and
  - proof of possession of corresponding private key.
- With `verifier_attestation` Client Identifier Prefix, signed authorization request with that key serves as proof of possession.

### Required / defined claims

- `iss` (**REQUIRED**):
  - identifies attestation issuer.
  - may be used to locate issuer public key.
  - trust model/key retrieval details are out of scope.

- `sub` (**REQUIRED**):
  - **MUST** equal `client_id` of client making credential request.

- `iat` (OPTIONAL):
  - issued-at time (RFC7519 numeric date).

- `exp` (**REQUIRED**):
  - expiration time (RFC7519 numeric date).
  - Wallet **MUST** reject expired attestation (allowing clock skew).

- `nbf` (OPTIONAL):
  - not-before time.

- `cnf` (**REQUIRED**):
  - confirmation claim per RFC7800.
  - **MUST** contain a JWK as defined in RFC7800 Section 3.2.
  - identifies public key for which Verifier must prove possession of matching private key.
  - supports long-lived verifier attestations while mitigating replay/impersonation risks.

Additional claims may be used per RFC7519; Wallet **MUST** ignore unknown claims.

### Media type and JOSE `typ`
- A compliant Verifier Attestation JWT uses media type:
  - `application/verifier-attestation+jwt` (Appendix E.6.1).
- Verifier Attestation JWT **MUST** set JOSE header `typ` to:
  - `verifier-attestation+jwt`.

### Conveying attestation in JOSE header
- Verifier Attestation JWT may be carried in JOSE header of a signed JWS object.
- This spec defines JOSE header parameter:
  - `jwt`: **MUST** contain a JWT.
- In this OID4VP context, that JWT **MUST** have `typ=verifier-attestation+jwt`.

## 13. Implementation Considerations (Simplified)

## 13.1 Static Configuration Values of Wallets (Simplified)

This section points to profiles that define static wallet configuration and gives one example set for environments where dynamic discovery is not possible.

### 13.1.1 Profiles defining static config
Examples listed by the spec:
- OpenID4VC High Assurance Interoperability Profile 1.0
- JWT VC Presentation Profile

### 13.1.2 Example static config bound to `openid4vp://`
Non-normative example shows static values such as:
- `authorization_endpoint: "openid4vp:"`
- `response_types_supported: ["vp_token"]`
- `vp_formats_supported` (example entries for `dc+sd-jwt`, `mso_mdoc`)
- `request_object_signing_alg_values_supported` (example: `ES256`)

Use case:
- Verifier can rely on this style of preconfigured metadata when dynamic wallet discovery is unavailable.

## 13.2 Nested Presentations (Simplified)

- OID4VP does **not** support presenting a Presentation nested inside another Presentation.

## 13.3 Response Mode `direct_post` Reference Design (Simplified)

The internal architecture between Verifier frontend and Verifier response endpoint is implementation-specific.
This section gives one secure reference pattern.

### Core reference flow (high level)
1. Verifier creates fresh nonce (at least 16 random bytes), stores in session, base64url-encodes it.
2. Verifier initializes transaction at response endpoint.
3. Response endpoint returns fresh `transaction-id` and `request-id`.
4. Verifier sends Authorization Request to Wallet using:
   - `response_uri`,
   - `nonce`,
   - `state=request-id`,
   - credential query.
5. Wallet authenticates user/collects consent and posts Authorization Response (`vp_token`, `state`) to `response_uri`.
6. Response endpoint validates `state` (`request-id`), stores response under `transaction-id`, creates fresh `response_code`, and may return `redirect_uri` including `response_code`.
7. If `redirect_uri` was returned, Wallet redirects user agent there.
8. Verifier calls response endpoint with session `transaction-id` + `response_code` to fetch response data.
   - If no `redirect_uri` was returned, Verifier can poll by `transaction-id`.
9. Response endpoint returns VP Token to Verifier.
10. Verifier checks nonce in returned credential(s) against session nonce, then consumes token and invalidates `transaction-id`, `request-id`, and nonce.

Security intent of IDs:
- `request-id`: correlate incoming wallet POST to initiated request.
- `transaction-id`: ensure only correct verifier session can retrieve response data.
- `response_code`: bind redirect callback to stored response.

## 13.4 Pre-Final Specifications (Simplified)

OID4VP currently references some dependencies still in draft versions, including:
- OpenID Federation 1.0 draft-43
- SIOPv2 draft-13
- SD-JWT draft-22
- SD-JWT VC draft-09
- JOSE Fully-Specified Algorithms draft-13

Implementation guidance:
- If referenced specs evolve, implementations should continue using the explicitly referenced versions above unless updated by:
  - an OID4VP profile, or
  - a newer OID4VP specification version.

## 14. Security Considerations (Simplified)

## 14.1 Preventing Replay of Verifiable Presentations (Simplified)

Replay threat:
- An attacker may try to reuse/inject previously obtained presentation material in another authorization flow to impersonate a user.

Holder binding is the primary defense mechanism.

### 14.1.1 Presentations without Holder Binding Proofs

- Presentations without holder binding (Section 5.3) do not provide replay protection by design.
- Verifier accepting them accepts risk that:
  - credential might have been acquired via third-party relay/misuse,
  - presenter might not be credential subject.
- Depending on use case and external controls, this risk may be acceptable.

### 14.1.2 Verifiable Presentations

For verifiable presentations, replay controls in this section are mandatory.

#### Required binding model
- Wallet proof of possession **MUST** bind each presentation to:
  - intended audience (`client_id` of Verifier),
  - specific transaction (`nonce` from Authorization Request).
- Verifier **MUST** verify those bindings.

#### Required Wallet behavior
- Wallet **MUST** link every verifiable presentation in `vp_token` to corresponding `client_id` and `nonce` from request.

#### Required Verifier behavior
- Verifier **MUST** validate each individual verifiable presentation.
- Verifier **MUST** confirm binding to original `client_id` and `nonce`.
- If any verifiable presentation has wrong/missing expected nonce binding, response **MUST** be rejected.

#### Why both are needed
- `client_id` binding prevents replay to unintended relying party.
- `nonce` binding prevents transaction-level injection/replay, especially important in front-channel paths.

Format note:
- Different VP formats/proof systems encode these bindings differently (claims vs proof inputs, different names).
- Verifier controls requested format and must validate according to that format's binding representation.

## 14.2 Session Fixation (Simplified)

Attack idea:
- Attacker starts flow in own verifier session, relays request to victim device, then attempts to complete attacker-side session using victim-produced response.

### Mode differences
- `fragment` mode is generally resistant because response returns to wallet-side browser/session on same device, so attacker usually cannot obtain resulting VP token.
- `direct_post` is more exposed because response is sent out-of-band to verifier response endpoint.

### Required mitigation with `direct_post` + redirect
When using `direct_post` with redirect continuation:
- Response endpoint **MUST** embed fresh secret (`response_code`) in returned `redirect_uri`.
- Response endpoint **MUST** require frontend to present matching `response_code` when fetching Authorization Response data.
- This blocks fixation as long as attacker cannot obtain that response code.

### Scope limitations of this mitigation
- Not applicable in many cross-device flows (wallet browser lacks original frontend session).
- Not applicable when wallet/browser context differs from original verifier-frontend browser on same device.
- Appendix A (DC API invocation model) can reduce many of these issues.
- Section 13.3 gives implementation guidance.

### If `direct_post` is used without redirect-based protection
- Verifier lacks session context to detect fixation reliably.
- Verifiers are **RECOMMENDED** to add extra hardening controls.
- Further attack/mitigation guidance: OAuth cross-device security work.

## 14.3 Response Mode `direct_post` (Simplified)

### 14.3.1 Validation of Response URI
- Wallet **MUST** prevent Authorization Response data leakage via Response URIs.
- With pre-registered Response URIs, Wallet **MUST** follow redirect URI validation best practices from RFC9700.
- Wallet may also establish trust in provided Response URI via:
  - Client Identifier Prefix model,
  - client authentication,
  - request integrity protection.

### 14.3.2 Protection of Response URI endpoint
- Verifier **SHOULD** protect Response URI endpoint against unsolicited/inadvertent requests by checking received `state` maps to a recent Authorization Request.

### 14.3.3 Protection of Authorization Response data
- Verifier Response URI commonly exposes an internal interface for other verifier components to fetch stored Authorization Response data.
- Without protection, attacker might query this interface and exfiltrate valid presentations (including personal data).
- Implementations **MUST** include security controls preventing unauthorized access.
- Example control patterns:
  - authenticated communication between verifier components,
  - two independent cryptographically random values:
    - one for Wallet<->Verifier state management,
    - one proving legitimate verifier component when fetching stored response data.

## 14.4 End-User Authentication using Credentials (Simplified)

If client authenticates End-User using credential claim, that claim **MUST** be:
- stable for that End-User,
- locally unique within issuer scope,
- never reassigned to another End-User by that issuer.

Additionally:
- claim **MUST** be used together with Credential Issuer identifier to ensure global uniqueness and prevent issuer-mixup impersonation attacks.

## 14.5 Encrypting an Unsigned Response (Simplified)

- Encrypted Authorization Response without additional signature/integrity layer can be rewritten/re-encrypted by attacker using verifier public key.
- This can include parameter tampering and VP Token injection attempts.
- VP Token content integrity protection still allows verifier to detect tampering inside VP Token itself.
- Replay/injection validation controls in Section 14.1 remain critical.

## 14.6 TLS Requirements (Simplified)

- Implementations **MUST** follow BCP195.
- Whenever TLS is used, server certificate validation **MUST** be performed per RFC6125.

## 14.7 Implementation Correctness and Conformance Testing (Simplified)

Security depends on complete and correct implementation of both OID4VP and dependent specs.

OpenID Foundation conformance resources:
- [OID4VP conformance testing](https://openid.net/certification/conformance-testing-for-openid-for-verifiable-presentations/)

## 14.8 Always Use Full Client Identifier (Simplified)

- Wallet **MUST** always use full Client Identifier (including prefix when present) for client identification in wallet context and responses.
- This is important wherever RFC6749 client identification applies and in presentation context.
- Goal: prevent confusion/mixup attacks between prefixed and non-prefixed client IDs.

## 14.9 Security Checks on Returned Credentials and Presentations (Simplified)

- Even though Wallet can apply claim/credential constraints from DCQL, Verifier **MUST NOT** rely on Wallet enforcement.
- Verifier **MUST** perform its own security checks on returned credentials and presentations.

## 15. Privacy Considerations (Simplified)

Many privacy properties depend on credential format/proof type.
This section focuses on protocol-level and cross-cutting privacy risks (wallet behavior, verifier behavior, ecosystem trust patterns).

Wallet providers and Verifiers should apply these controls to reduce:
- data leakage,
- user tracking,
- linkage/fingerprinting harms.

## 15.1 User Consent (Simplified)

- Wallets **SHOULD** obtain explicit informed End-User consent before releasing any credential/presentation or returning an error.
- Wallet transaction history/data **SHOULD NOT** be accessible to anyone except End-User unless consent or other legal basis exists.

## 15.2 Privacy Notice (Simplified)

- Wallets **SHOULD** make privacy notices easily available to End-User.

## 15.3 Purpose Legitimacy (Simplified)

- Verifier **SHOULD** ensure purpose for requested data is specific and communicated before collection.
- If Wallet indicates Verifier may be requesting unauthorized/excessive data, Wallet **SHOULD** warn End-User or may stop processing.

## 15.4 Selective Disclosure (Simplified)

- Selective disclosure supports data minimization by sharing only needed claims.
- DCQL enables this by allowing claim-level request definitions.
- Some credential formats implement selective disclosure using salted-hash-style designs.

### 15.4.1 DCQL Value Matching (Simplified)

Value matching can leak information even from match/non-match behavior.
Wallets **MUST** take precautions against value leakage, including:

- making responses indistinguishable between:
  - user non-consent, and
  - value mismatch outcomes;
- preventing repeated/silent probing by requiring End-User interaction before any response, including mismatch cases.

Important:
- Error responses themselves can leak processing outcomes and must be handled carefully.

### 15.4.2 Strictly Necessary Claims (Simplified)

- Verifiers **SHOULD** request only minimal required claims/credentials for stated purpose.

## 15.5 Verifier-to-Verifier Unlinkable Presentations (Simplified)

Even with selective disclosure, presentations can remain linkable (e.g., issuer signatures, key bindings, repeated credential instances).

Wallet anti-linking strategies include:
- one-time use credential instances (discard after presentation),
- limited-use policies (e.g., present same instance only to same verifier).

Batch issuance and one-time presentation patterns can improve unlinkability properties (as discussed in referenced SD-JWT guidance/OpenID4VCI context).

## 15.6 No Fingerprinting of End-User (Simplified)

- Verifier **SHOULD NOT** fingerprint End-User via wallet metadata/interaction details.
- Wallet **SHOULD** implement anti-fingerprinting controls when fetching Request Objects.
- Wallet **SHOULD** limit side-channel disclosure via Response URI interactions (e.g., user-agent details).

## 15.7 Information Security (Simplified)

- Wallet providers and Verifiers **SHOULD** apply operational/technical/governance controls for confidentiality, integrity, lifecycle protection of PII.
- Controls should address unauthorized access, modification, disclosure, loss, and destruction risks.

## 15.8 Wallet-to-Verifier Communication (Simplified)

- Wallets **SHOULD** send minimal information and avoid extra HTTP fingerprinting headers (e.g., library/version identifiers) when calling `request_uri` / `response_uri`.
- Wallets **MUST NOT** include PII in HTTP requests unless:
  - explicitly required for flow, and
  - authorized by End-User.

### 15.8.1 Establishing Trust in Request URI (Simplified)

- In trust frameworks, Wallets **SHOULD** validate Request URI is properly associated with Client Identifier and authorized for request.
- Untrusted/unrecognized Request URI endpoints **SHOULD** be rejected or require End-User confirmation.

### 15.8.2 Authorization Requests with Request URI (Simplified)

- If trust framework allows Wallet to verify Request URI ownership for client:
  - Wallet is **RECOMMENDED** to validate verifier authenticity/authorization and Request URI linkage.
  - If linkage cannot be established, Wallet **MUST** refuse request.

## 15.9 Error Responses (Simplified)

- Error responses **SHOULD** avoid sensitive/context-rich details that could reveal End-User data.

### 15.9.1 `wallet_unavailable` error (Simplified)

- If a non-wallet component is invoked and returns `wallet_unavailable`, End-User **SHOULD** be informed and consent before returning that error to Verifier.

### 15.9.2 Digital Credentials API Error Responses (Simplified)

In DC API-specific flows, protocol errors can reveal sensitive possession information (because wallet selection may imply request satisfiability).

Leakage severity increases with narrowness of request:
- broad request -> reveals possession within large credential set,
- single-document request -> reveals possession of specific credential type,
- single-trusted-authority request -> reveals credential from that authority,
- value-matching request -> can reveal specific claim value.

Implementation guidance:
- Wallets should balance operational error transparency against privacy leakage.
- Wallet **SHOULD NOT** return OID4VP protocol errors without End-User interaction.
- Implementations may cancel flow (platform-level abort) instead of protocol error to reduce leakage.
- Wallet **SHOULD NOT** return protocol errors before End-User consent when:
  - processing value matching, or
  - issuer-selection constraints,
  because both can leak sensitive possession/value information and enable repeated probing.

## 15.10 Establishing Trust in Issuers (Simplified)

Trusted-authority mechanisms can be:
- self-contained (no online lookup needed), or
- online-resolution-based (fetch additional data).

Privacy implication:
- online resolution can leak usage patterns and potentially identify End-User behavior.

Guidance:
- Wallets **SHOULD NOT** fetch URLs from verifier request when URLs are unfamiliar/untrusted.
- Privacy is improved if such URLs are treated as identifiers, not fetched automatically.
- Ecosystems using trusted-authority mechanisms **SHOULD** align mechanism privacy properties with ecosystem privacy goals.

## Appendix A. OpenID4VP over the Digital Credentials API (Simplified)

This appendix defines how OID4VP is used over the Digital Credentials API (DC API).

DC API here includes:
- W3C Digital Credentials API on web platform,
- equivalent native platform APIs (e.g., Android Credential Manager).

Key idea:
- DC API transports verifier request + authenticated verifier origin (from platform/user agent) to selected Wallet.
- OID4VP can run over this transport while still enabling advanced OID4VP security features.

Main implementation benefits highlighted by the spec:
- better privacy than URL-scheme invocation,
- smoother UX (flow resumes in original app/browser context),
- secure cross-device transports with proximity protections handled by platform,
- origin information from platform improves phishing resistance.

## A.1 Protocol (Simplified)

DC API exchange protocol identifier format:

`openid4vp-v<version>-<request-type>`

Purpose:
- explicit version + request type selection (no implicit parameter inference needed).

For this specification version:
- `<version>` **MUST** be `1`.
- `<request-type>` values:
  - unsigned requests -> `unsigned`
  - signed requests -> `signed`
  - multi-signed requests -> `multisigned`

Defined protocol values:
- `openid4vp-v1-unsigned`
- `openid4vp-v1-signed`
- `openid4vp-v1-multisigned`

## A.2 Request (Simplified)

Verifier MAY send OID4VP request (Section 5 model) via DC API.

Supported request parameters over W3C DC API include:
- `client_id`
- `response_type`
- `response_mode`
- `nonce`
- `client_metadata`
- `request`
- `transaction_data`
- `dcql_query`
- `verifier_info`
- plus parameters defined by active Client Identifier Prefix profile (e.g., federation-specific parameters).

### Unsigned vs signed request differences

Unsigned requests (Appendix A.3.1):
- `client_id` **MUST** be omitted.
- If `client_id` appears anyway, Wallet **MUST** ignore it.

Signed requests (Appendix A.3.2):
- `client_id` **MUST** be present (used by Wallet to apply prefix/client authentication/metadata logic).

### `response_mode` for DC API
- Use `dc_api` when response is not encrypted.
- Use `dc_api.jwt` when response is encrypted (Section 8.3 model).
  - In `dc_api.jwt`, Wallet returns `response` containing encrypted JWT wrapping Authorization Response.

### `expected_origins` parameter (new for DC API)

- `expected_origins`:
  - **REQUIRED** for signed requests (Appendix A.3.2) over DC API.
  - non-empty array of verifier Origin strings.
  - Wallet **MUST** compare platform-provided Origin against this list to detect replay/malicious verifier re-use.
  - If no match, Wallet **MUST** return error (SHOULD use `invalid_request`).
- Not for unsigned requests:
  - if present in unsigned requests, Wallet **MUST** ignore it.

### Extensibility and unknown parameters
- Additional request parameters may be used.
- Wallet **MUST** ignore unrecognized parameters.
- Example implication: since `state` is not defined for DC API flow, Verifier cannot assume it appears in response.

Transport details of request + origin from platform to Wallet are platform-specific and out of scope.

## A.3 Signed and Unsigned Requests (Simplified)

Any request compliant with this appendix can be used over DC API.
Depending on verifier identification/authentication method, request may be unsigned or signed.

## A.3.1 Unsigned Request (Simplified)

- Verifier may send OpenID4VP request parameters directly as members in API `request` member.

## A.3.2 Signed Request (Simplified)

- Verifier may send signed request when verifier identification/authentication is required.
- Signed requests let Wallet authenticate verifier using trust frameworks beyond browser Web PKI.
- Web origin can still be used as additional security signal.
- External trust framework may map client identifiers to allowed web origins.

Signed Request Object may include all A.2 parameters **except** `request`.

Serialization guidance:
- Verifier **SHOULD** use JWS Compact Serialization.
- Verifier **MAY** use JWS JSON Serialization for multi-framework / multi-client-id scenarios.

## A.3.2.1 JWS Compact Serialization (Simplified)

Use when verifier can work with one trust framework/client identity context.

- All request parameters are in Request Object payload.
- JWS compact token is passed as API `request` value.
- Supports one effective client identity/signature context for the request.

## A.3.2.2 JWS JSON Serialization (Simplified)

Use when verifier needs multiple client identities/signatures over same request (e.g., multiple trust frameworks, different attestations).

Rules:
- The following parameters, when used, **MUST** appear only in each signature's protected header:
  - `client_id`
  - `verifier_info`
  - client-id-prefix-specific parameters (e.g., `trust_chain` for `openid_federation`)
- All other request parameters **MUST** be in JWS payload.
- Each `signatures` entry contains header + signature specific to one client identifier context.
- Signature computation follows RFC7515 rules.

## A.4 Response (Simplified)

Each DC API request results in:
- a response returned via DC API, or
- a canceled flow.

When response is returned:
- it is provided through DigitalCredential `data` object with OpenID4VP response parameters.

### Error responses over DC API
- Protocol errors are returned in `data` as object:
  - `{ "error": "<error_code>" }`
- Error code values follow Section 8.5.
- Wallet-generated protocol error still resolves the DC API call (fulfilled promise), not necessarily a transport failure.
- Privacy implications of DC API errors are discussed in Section 15.9.2.

### Audience binding in DC API mode
- Security properties normally tied to `client_id` are achieved by origin binding.
- Audience in response (e.g., `aud` in key-binding JWT) **MUST** be verifier origin with `origin:` prefix.
  - example: `origin:https://verifier.example.com/`
- This rule applies even for signed requests.
- Therefore, in DC API mode, `client_id` is **not** used as response audience.

## A.5 Security Considerations (Simplified)

The following main-spec security considerations also apply to OpenID4VP over DC API:

- replay prevention (Section 14.1), with DC API-specific difference:
  - bind response to verifier **origin** (not client identifier).
- end-user authentication using credentials (Section 14.4).
- encrypting unsigned response considerations (Section 14.5).
- TLS requirements (Section 14.6).
- always use full client identifier for signed requests (Section 14.8).
- verifier security checks on returned credentials/presentations (Section 14.9).
- DCQL value-matching security/privacy handling (Section 15.4.1).

## A.6 Privacy Considerations (Simplified)

The following main-spec privacy considerations also apply to OpenID4VP over DC API:

- selective disclosure considerations (Section 15.4).
- privacy implications of issuer-trust establishment mechanisms (Section 15.10).

## Appendix B. Credential Format-Specific Parameters and Rules (Simplified)

OID4VP is credential-format agnostic.
This appendix defines format-specific parameters/rules for selected known formats.
Other specs/profiles can define format-specific rules for additional credential formats.

## B.1 W3C Verifiable Credentials (Simplified)

This subsection covers W3C VC / VP behaviors for credentials compliant with VC Data Model.

Holder-binding rule:
- If `require_cryptographic_holder_binding=true` in Credential Query:
  - Wallet **MUST** return a Verifiable Presentation of a Verifiable Credential.
- Otherwise:
  - Wallet returns Verifiable Credential without holder-binding proof.

## B.1.1 `meta` parameters in Credential Query (Simplified)

W3C VC-specific `meta` parameter:

- `type_values` (**REQUIRED**):
  - non-empty array of string arrays.
  - each inner array defines one acceptable set of fully expanded VC `type` IRIs.
  - for one inner array to match, all its listed types **MUST** be present in credential `type` (order irrelevant; extra credential types allowed).
  - multiple inner arrays represent alternatives (OR across arrays).

Type expansion behavior:
- Type values are interpreted after applying `@context` expansion (JSON-LD semantics).
- If a type is not defined by any context, it remains unchanged (relative IRI may remain).
- JSON-LD processing may be skipped if implementation can produce equivalent fully expanded results.

## B.1.2 Claims Matching (Simplified)

For W3C VC format:
- Claim paths in query are evaluated against the **Verifiable Credential root**, not Verifiable Presentation wrapper.

## B.1.3 Formats and Examples (Simplified)

## B.1.3.1 VC signed as JWT (non-JSON-LD mode example context)

This variant illustrates W3C VC represented as JWT-secured credential without relying on JSON-LD processing for signing model.

### B.1.3.1.1 Format identifier and algorithms

- Credential Format Identifier: `jwt_vc_json`.
- Algorithm identifiers should use IANA JOSE Algorithms Registry names.

### B.1.3.1.2 Example credential

Non-normative example payload shows:
- issuer (`iss`), subject (`sub`), timestamps, `jti`,
- `vc` object with `@context`, `type`,
- `credentialSubject` claims such as names, birthdate, address.

### B.1.3.1.3 Metadata

For Wallet/Verifier metadata:
- `vp_formats_supported` must include `jwt_vc_json` key when this format is supported.
- value is object with:
  - `alg_values` (OPTIONAL): non-empty array of supported JOSE `alg` identifiers for JWT-secured VC/VP.
  - if present, JOSE header `alg` in presented VC/VP **MUST** match one listed value.

### B.1.3.1.4 Presentation request

Requirements are expressed in `dcql_query`, for example:
- format = `jwt_vc_json`,
- `meta.type_values` to constrain VC type,
- requested claims via claim paths (e.g., family/given name).

### B.1.3.1.5 Presentation response

For returned Verifiable Presentation:
- `nonce` claim **MUST** equal Authorization Request `nonce`.
- `aud` claim **MUST** equal Client Identifier,
  - except DC API requests where `aud` **MUST** be `origin:<verifier-origin>` (Appendix A.4).

Response structure:
- VP Token maps credential query `id` to presentation array.
- Presentation payload includes binding claims (`aud`, `nonce`) and embedded `verifiableCredential`.

## B.2 Mobile Documents / mdoc (ISO/IEC 18013 and 23220 series) (Simplified)

ISO mdoc format originates from ISO/IEC 18013-5 (mDL) and is reusable for other document types, with shared core structures across 18013-5 and 23220 profiles.

- Core structures are CBOR-encoded and protected with COSE_Sign1.
- Credential Format Identifier for mdoc is:
  - `mso_mdoc`

## B.2.1 Transaction Data (Simplified)

Recommendations:
- each transaction-data type should define the mdoc data element triplet to carry processed transaction data:
  - NameSpace,
  - DataElementIdentifier,
  - DataElementValue
- and should define processing rules (including hashing, output structure as needed).

If document type supports transaction data protected via mdoc authentication (DeviceSigned):
- supported transaction-data types are document-type specific,
- issuers authorize relevant data elements via KeyAuthorizations.

Wallet rule:
- if request includes transaction-data type whose required data element is unauthorized, Wallet **MUST** reject request as unsupported transaction data type.

## B.2.2 Metadata (Simplified)

For metadata (`vp_formats_supported`) with key `mso_mdoc`, value can include:

- `issuerauth_alg_values` (OPTIONAL, non-empty):
  - accepted issuer-auth algorithms.
  - credential satisfies this requirement if either:
    1) value matches `alg` in IssuerAuth COSE header, or
    2) value is fully-specified algorithm identifier and matches combination of COSE alg + signing-key curve.

- `deviceauth_alg_values` (OPTIONAL, non-empty):
  - accepted device-auth algorithms.
  - credential satisfies if either:
    1) value matches `alg` in DeviceSignature or DeviceMac COSE header, or
    2) value is fully-specified identifier matching DeviceSignature alg+curve combination, or
    3) DeviceMac uses HMAC 256/256 and device key curve maps to one of defined private-use identifiers:
       `-65537` .. `-65545` (P-256, P-384, P-521, X25519, X448, brainpool variants).

Note:
- Those negative values are private-use identifiers in this spec context and may later be superseded by IANA registration.

## B.2.3 `meta` parameter in Credential Query (Simplified)

mdoc-specific `meta` field:
- `doctype_value` (**REQUIRED**):
  - string with allowed `doctype` for requested credential,
  - must be valid doctype identifier per ISO 18013-5 rules.

## B.2.4 Claims Query parameter (Simplified)

mdoc-specific claims-query field:
- `intent_to_retain` (OPTIONAL boolean):
  - equivalent to ISO 18013-5 IntentToRetain semantics.

## B.2.5 Presentation Response (Simplified)

VP Token entry value contains:
- base64url-encoded mdoc `DeviceResponse` CBOR structure.

High-level:
- DeviceResponse includes signature/MAC over SessionTranscript,
- SessionTranscript includes OpenID4VP-specific handover structure.

## B.2.6 Handover and SessionTranscript Definitions (Simplified)

### B.2.6.1 Invocation via Redirects

When invoked via redirects, SessionTranscript (ISO 18013-5 base structure) is used with required overrides:
- `DeviceEngagementBytes` **MUST** be `null`.
- `EReaderKeyBytes` **MUST** be `null`.
- `Handover` **MUST** be `OpenID4VPHandover`.

`OpenID4VPHandover` structure:
- element 1: fixed string `"OpenID4VPHandover"` (**MUST**),
- element 2: byte string SHA-256 hash of CBOR bytes of `OpenID4VPHandoverInfo` (**MUST**).

`OpenID4VPHandoverInfo` elements:
1. `client_id` (including prefix when present) (**MUST**),
2. `nonce` (**MUST**),
3. JWK thumbprint bytes (**MUST** be thumbprint of encryption key if response encrypted, else `null`),
4. `redirect_uri` or `response_uri` depending on response mode (**MUST**).

Parameter source rule:
- unless specified otherwise, values above come from:
  - Authorization Request query params for unsigned requests, or
  - signed Request Object for signed requests.

### B.2.6.2 Invocation via Digital Credentials API

When invoked via DC API, SessionTranscript is used with:
- `DeviceEngagementBytes` **MUST** be `null`.
- `EReaderKeyBytes` **MUST** be `null`.
- `Handover` **MUST** be `OpenID4VPDCAPIHandover`.

`OpenID4VPDCAPIHandover` structure:
- element 1: fixed string `"OpenID4VPDCAPIHandover"` (**MUST**),
- element 2: byte string SHA-256 hash of CBOR bytes of `OpenID4VPDCAPIHandoverInfo` (**MUST**).

`OpenID4VPDCAPIHandoverInfo` elements:
1. request `origin` string (**MUST**, and **MUST NOT** be prefixed with `origin:`),
2. `nonce` (**MUST**),
3. JWK thumbprint bytes:
   - for `dc_api.jwt`: **MUST** be thumbprint of verifier encryption key,
   - for `dc_api`: **MUST** be `null`.

Security rationale:
- For unsigned requests, including JWK thumbprint in SessionTranscript helps verifier detect third-party re-encryption attempts; it does not prevent the attack but makes it detectable.

All hex/CBOR/JWK data structures shown in this section are non-normative examples.

## B.3 IETF SD-JWT VC (Simplified)

This section defines presenting credentials compliant with SD-JWT VC using OID4VP.

Holder-binding behavior:
- If `require_cryptographic_holder_binding=true`:
  - Wallet **MUST** return SD-JWT with Key Binding JWT (SD-JWT+KB).
  - SD-JWTs lacking holder-binding support (no `cnf`) cannot be returned.
- If `require_cryptographic_holder_binding=false`:
  - Wallet **MAY** return SD-JWT without KB-JWT.

## B.3.1 Format Identifier (Simplified)

- Credential Format Identifier: `dc+sd-jwt`

## B.3.2 Example Credential (Simplified)

Non-normative examples show:
- unsecured SD-JWT VC payload (e.g., `vct`, identity claims),
- SD-JWT form with selectively disclosable claims via `_sd`,
- issuer/time claims and holder-binding key (`cnf.jwk`),
- corresponding disclosures and hash bindings.

## B.3.3 Transaction Data (Simplified)

Recommendations:
- each transaction-data type should define top-level claim for KB-JWT carrying processed transaction data,
- and define processing rules (hashing and expected structure if needed).

Normative rule:
- transaction-data mechanism requires cryptographic holder binding.
- Wallets **MUST** reject requests including transaction data where `require_cryptographic_holder_binding=false`.

### B.3.3.1 Profile for transaction data hashing (Simplified)

Request-side additional field:
- `transaction_data_hashes_alg` (OPTIONAL):
  - non-empty array of hash algorithm identifiers.
  - one must be used to compute response hashes.
  - if absent, default is `sha-256`.
  - implementations **MUST** support `sha-256`.

Response-side KB-JWT fields:
- `transaction_data_hashes`:
  - non-empty array of base64url hashes.
  - each hash computed over original `transaction_data` string as received (no base64url decode before hashing).
  - if request specified `transaction_data_hashes_alg`, selected hash function **MUST** be one of those values.
  - otherwise hash function **MUST** be `sha-256`.
- `transaction_data_hashes_alg`:
  - **REQUIRED** when this parameter was present in request.
  - indicates hash algorithm used for `transaction_data_hashes`.

## B.3.4 Metadata (Simplified)

For metadata object `vp_formats_supported["dc+sd-jwt"]`:
- `sd-jwt_alg_values` (OPTIONAL, non-empty):
  - fully specified algorithm identifiers for issuer-signed SD-JWT.
- `kb-jwt_alg_values` (OPTIONAL, non-empty):
  - fully specified algorithm identifiers for Key Binding JWT.

## B.3.5 `meta` parameter in Credential Query (Simplified)

SD-JWT VC-specific `meta` field:
- `vct_values` (**REQUIRED**):
  - non-empty array of allowed credential type identifiers (`vct` values).
  - values must be valid SD-JWT VC type identifiers.
  - Wallet may return credentials inheriting from specified types per SD-JWT VC inheritance rules.

## B.3.6 Presentation Response (Simplified)

Binding requirements in Key Binding JWT:
- `nonce` **MUST** equal Authorization Request `nonce`.
- `aud` **MUST** equal Client Identifier,
  - except DC API where `aud` **MUST** be `origin:<verifier-origin>` (Appendix A.4).

Non-normative examples show KB-JWT payload including:
- `nonce`, `aud`, `iat`,
- `sd_hash`,
- optional `transaction_data_hashes`.

## B.3.7 SD-JWT VCLD (Simplified)

SD-JWT VCLD extends SD-JWT VC to carry Linked Data (JSON-LD) models while keeping selective disclosure flow.

When this spec says SD-JWT VC, SD-JWT VCLD may also be used.

### B.3.7.1 Format rules (Simplified)

SD-JWT VCLD must satisfy all SD-JWT VC requirements plus:

Use JWT/SD-JWT registered claims for key semantics:
- `vct` -> credential type,
- `exp`/`nbf` -> validity window,
- `iss` -> issuer,
- `status` -> status lookup information.

Additional claim:
- `ld` (OPTIONAL):
  - compact JSON-LD object carrying linked-data business content.

### B.3.7.2 Processing model (Simplified)

Suggested two-step processing:

1) **SD-JWT VC security processing**:
   - verify signatures, validity, status, schema/type metadata where applicable, trust-framework issuer authorization checks.

2) **Business logic processing**:
   - if `ld` exists, use it as business object;
   - otherwise use entire SD-JWT VC as business object;
   - apply use-case-specific validation (e.g., additional schema/SHACL checks).

Security assumption:
- business logic stage assumes security-critical checks already completed in stage 1.

### B.3.7.3 Examples (Simplified)

Non-normative examples show:
- unsecured SD-JWT VCLD payload with `vct` + `ld`,
- transformed SD-JWT payload with selective disclosure in `ld.credentialSubject._sd`,
- issuer/time claims, `_sd_alg`, and `cnf.jwk`.

Issuer note:
- issuer decides which claims are selectively disclosable.

## Appendix C. Combining OID4VP with SIOPv2 (Simplified)

This appendix shows how to combine:
- OID4VP credential presentation, and
- SIOPv2 self-issued authentication
in one flow.

Goal:
- request credentials and pseudonymously authenticate End-User using subject-controlled keys.

## C.1 Request (Simplified)

Combined request uses:
- `response_type=vp_token id_token`
- `scope=openid`
- `id_token_type=subject_signed`
- plus normal OID4VP parameters (`client_id`, redirect/response URI, `dcql_query`, `nonce`, etc.).

Meaning:
- Wallet is asked to return both:
  - `vp_token` (credential presentations), and
  - `id_token` (self-issued ID Token per SIOPv2).

## C.2 Response (Simplified)

Response includes both parameters:
- `id_token`
- `vp_token`

For Self-Issued ID Token payload:
- `nonce` and `aud` are bound similarly to VP replay protections:
  - `nonce` = request nonce,
  - `aud` = verifier client identifier.

This preserves anti-replay consistency across authentication token and presentations.

## Appendix D. DCQL Query Examples (Simplified)

Appendix D provides non-normative DCQL patterns illustrating common request designs.

### Example pattern 1: single mdoc credential + selected claims
- Request one `mso_mdoc` credential with `doctype_value`.
- Ask for specific mdoc claim paths (e.g., vehicle holder, first name).

### Example pattern 2: multiple mandatory credentials
- Request multiple credentials (e.g., SD-JWT PID + mdoc credential).
- No `credential_sets` alternatives -> all requested credential queries must be satisfied.

### Example pattern 3: alternative credential sets + optional set
- Use `credential_sets.options` to allow alternatives:
  - e.g., `pid` OR `other_pid` OR (`pid_reduced_cred_1` + `pid_reduced_cred_2`).
- Include optional set with `required=false` (e.g., `nice_to_have`).

### Example pattern 4: substitutable credentials by document type
- Build equivalent identity/address options from different document types (mDL vs photo ID).
- Use `credential_sets` to accept either source for each logical requirement.

### Example pattern 5: mandatory claims + fallback claim combinations
- Use `claim_sets` to express claim alternatives:
  - mandatory core claims always included,
  - optional branch A preferred, branch B fallback.
- Order in `claim_sets` expresses verifier preference.

### Example pattern 6: value-constrained claim matching
- Use claim `values` to request specific allowed values (e.g., surname/postal code constraints).
- As specified elsewhere, value matching is privacy-oriented best effort and must not be sole security control.

## Appendix E. IANA Considerations (Simplified)

This appendix lists protocol registrations introduced by OID4VP in IANA registries.

## E.1 OAuth Authorization Endpoint Response Types Registry (Simplified)

Registered response types:
- `vp_token` (Section 8)
- `vp_token id_token` (Section 8)

Both are controlled by the OpenID Foundation Digital Credentials Protocols WG.

## E.2 OAuth Parameters Registry (Simplified)

Registered OAuth parameters include:
- `dcql_query` (authorization request)
- `client_metadata` (authorization request)
- `request_uri_method` (authorization request)
- `transaction_data` (authorization request)
- `wallet_nonce` (authorization request, token response)
- `response_uri` (authorization request)
- `vp_token` (authorization response, token response)
- `verifier_info` (authorization request)
- `expected_origins` (authorization request; DC API context)

Each registration references corresponding normative section (primarily Section 5, 8, and Appendix A.2).

## E.3 OAuth Extensions Error Registry (Simplified)

Registered OAuth extension errors:
- `vp_formats_not_supported`
- `invalid_request_uri_method`
- `wallet_unavailable`

Usage locations include authorization endpoint and, where specified, token endpoint.

## E.4 OAuth Authorization Server Metadata Registry (Simplified)

Registered AS metadata parameter:
- `vp_formats_supported` (wallet-supported credential formats metadata, Section 10).

## E.5 OAuth Dynamic Client Registration Metadata Registry (Simplified)

Registered client metadata parameters:
- `encrypted_response_enc_values_supported` (response content-encryption alg support, Section 5.1)
- `vp_formats_supported` (verifier-supported credential formats, Section 11.1)

## E.6 Media Types Registry (Simplified)

Registered media type:
- `application/verifier-attestation+jwt`

Key notes:
- used for Verifier Attestation JWTs,
- uses JWS Compact Serialization,
- normative definition linked to Section 12.

## E.7 JOSE Header Parameters Registry (Simplified)

Registered/covered JWS header parameters:
- `jwt`:
  - header carries a JWT;
  - processing may depend on embedded JWT `typ`;
  - OID4VP-specific use described in Section 12.
- `client_id`:
  - OAuth client identifier header parameter (referencing RFC6749 registration context).

## E.8 URI Schemes Registry (Simplified)

Registered URI scheme:
- `openid4vp`
  - provisional status,
  - used as custom Wallet invocation scheme,
  - reference: Section 13.1.2.

## E.9 JWT Claims Registration (Simplified)

Registered JWT claim:
- `ld`
  - compact JSON-LD object claim used in SD-JWT VCLD context,
  - reference: Appendix B.3.7.

