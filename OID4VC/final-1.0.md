# OpenID for Verifiable Credential Issuance 1.0

This document explains OpenID4VCI 1.0 in implementation-oriented language. Normative keywords retain their specification meaning, and examples are non-normative unless stated otherwise.

## 1. Introduction

OpenID for Verifiable Credential Issuance (OpenID4VCI) defines an OAuth-protected API for issuing Verifiable Credentials. It is format agnostic and supports formats such as:

- IETF SD-JWT VC;
- ISO mdoc (ISO/IEC 18013-5); and
- W3C Verifiable Credentials Data Model (VCDM).

Verifiable Credentials are similar to identity assertions like ID Tokens in OpenID Connect — both allow an Issuer to assert claims about an End-User. The key differences are:

- A Verifiable Credential follows a pre-defined schema (a **Credential type**).
- It **MAY** be bound to a specific Holder, for example through cryptographic key binding, so that only the legitimate holder can present it.
- It can be **presented to a Verifier without contacting the Issuer** — the Verifier only needs to verify the Credential's cryptographic signature, not reach back to the Issuer at presentation time.

The Wallet acts as an OAuth 2.0 Client. It obtains authorization and an Access Token through standard OAuth flows, then uses that token to call the Credential Endpoint. This design means existing OAuth 2.0 deployments and OpenID Connect Providers can be extended to become Credential Issuers, inheriting OAuth's proven security model, simplicity, and flexibility.

## 1.1 Errata Revisions

- Latest errata revision: `openid-4-verifiable-credential-issuance-1_0`.
- Originally approved Final text: `openid-4-verifiable-credential-issuance-1_0-final`.
- References from other documents should normally target the latest revision.

## 1.2 Requirements Notation

The capitalized words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **NOT RECOMMENDED**, **MAY**, and **OPTIONAL** have the BCP 14 meanings defined by RFC2119 and RFC8174.

## 2. Terminology

OAuth 2.0, OpenID Connect, JWT, JWS, and JOSE terminology applies. **Base64url-encoded** means URL-safe Base64 without padding. If another specification defines a term differently, the OpenID4VCI definition is authoritative here.

- **Credential Dataset**: A set of one or more claims about a subject, provided by a Credential Issuer. For example, a university degree dataset might contain the student's name, degree title, and graduation date.
- **Credential / Verifiable Credential (VC)**: An Issuer-signed, cryptographically verifiable instance of a Credential Configuration containing a particular Dataset. An Issuer may produce multiple Credential instances from the same Configuration and Dataset but with different cryptographic values (e.g., different signatures or key bindings). **Important:** The word "Credential" in this specification does not mean a password or OAuth login credential — it refers exclusively to a Verifiable Credential.
- **Credential Format**: The data model and encoding used to organize and represent a Credential's information. The format determines how claim data is structured, encoded, and verified. Examples include SD-JWT VC, ISO mdoc, and W3C VCDM. Definitions of Credential Formats themselves are outside the scope of this specification.
- **Credential Format Profile**: A set of format-specific parameters that define how a particular Credential Format is used within OpenID4VCI extension points (Issuer metadata, Credential Offers, Authorization Requests, and Credential Requests). Appendix A provides profiles for SD-JWT VC, mdoc, and W3C VCDM. Other specifications or deployments can define their own.
- **Credential Format Identifier**: An identifier that selects a specific Credential Format and implies the use of its corresponding Format Profile parameters.
- **Credential Configuration**: An Issuer's metadata description of one particular kind of Credential it offers. It includes the format, format-specific parameters (e.g., `vct` for SD-JWT VC or `doctype` for mdoc), how to request issuance, supported cryptographic methods and algorithms, and display information for the Wallet. Each Configuration is identified by a string that is unique within that Issuer.
- **Presentation**: Data derived from one or more Verifiable Credentials and presented to a specific Verifier. It can be in any Credential Format.
- **Credential Issuer (or Issuer)**: The entity that issues Verifiable Credentials. In OpenID4VCI, it acts as an OAuth 2.0 Resource Server (protected by Access Tokens). The Issuer might also serve as its own Authorization Server.
- **Holder**: The entity that receives Verifiable Credentials and has control over them to present them to Verifiers as Presentations.
- **Verifier**: The entity that requests, receives, and validates Presentations.
- **Issuer-Holder-Verifier Model**: A model where claims are issued as Verifiable Credentials independently of how they are later presented to Verifiers. This separation means an issued Credential can potentially be used in multiple presentations, though this is not required.
- **Holder Binding**: The ability of the Holder to prove legitimate possession of a Verifiable Credential.
- **Cryptographic Holder Binding (or Cryptographic Key Binding)**: The Holder proves possession by demonstrating control over the same private key during both issuance and presentation. The concrete mechanism depends on the Credential Format. For example, in SD-JWT VC, the Issuer includes a public key (or reference to one) in the Credential that matches the Holder's private key — the Holder must prove control of this key when presenting the Credential.
- **Claims-Based Holder Binding**: The Holder proves possession by demonstrating certain claims (e.g., name and date of birth), for example by presenting a separate Credential. This approach enables long-term, cross-device use because it does not depend on cryptographic key material stored on a specific device. A diploma is a common example.
- **Wallet**: An entity used by the Holder to request, receive, store, present, and manage Verifiable Credentials and cryptographic key material. There is no single deployment model: Credentials and keys can be managed locally on the device, through a remote self-hosted service, or via a remote third-party service. In OpenID4VCI, the Wallet acts as the OAuth 2.0 Client and obtains an Access Token to call the Credential Endpoint.
- **Deferred Credential Issuance**: Issuance of Credentials not directly in the Credential Response but after a waiting period. This allows the Issuer to perform offline business processes (such as manual review or background checks) before the Credential is ready for pickup.

## 3. Overview

## 3.1 Credential Issuer Components

The Credential Issuer API is comprised of the following endpoints and mechanisms:

- **Credential Endpoint** (**REQUIRED**): The core issuance endpoint. From it, one Credential or multiple Credentials with the same Credential Format and Credential Dataset can be issued in a single request (see Section 8).
- **Nonce Endpoint** (OPTIONAL): Returns a fresh `c_nonce` value that the Wallet incorporates into its proof of key possession in a subsequent Credential Request. This ensures the proof is fresh and not replayed (see Section 7).
- **Deferred Credential Endpoint** (OPTIONAL): Allows the Wallet to retrieve a Credential after a delay, when the Issuer needs time for offline processing such as manual review or background checks (see Section 9).
- **Credential Offers** (OPTIONAL): A mechanism for the Issuer to proactively communicate to the Wallet that certain Credentials are available, encouraging the Wallet to start the issuance flow (see Section 4).
- **Notification Endpoint** (OPTIONAL): Lets the Wallet report back to the Issuer about the outcome of issuance — whether Credentials were accepted, deleted, or failed (see Section 11).
- **Issuer Metadata**: Publishes discoverable information about the Issuer's endpoints, supported Credential Configurations, cryptographic methods, and display data (see Section 12.2).

When a Credential is to be cryptographically bound to the Holder, the Credential Request includes proof(s) of possession of the private key or key attestation(s). Multiple key proof types are supported.

## 3.2 OAuth Foundation

Each Credential Issuer acts as an OAuth 2.0 Resource Server, protected by an Access Token issued by an Authorization Server, as defined in RFC6749. The same Authorization Server can protect one or more Credential Issuers. The Wallet discovers which Authorization Server to use by reading the Credential Issuer's metadata (see Section 12.2).

All OAuth 2.0 Grant Types and extension mechanisms can be used alongside the Credential issuance API. OpenID4VCI extends OAuth specifically with:

- **New Grant Type** `urn:ietf:params:oauth:grant-type:pre-authorized_code`: Supports flows where the Issuer prepares and authorizes Credential issuance before the OAuth flow begins (see Section 3.5).
- **New authorization details type** `openid_credential` (RFC9396): Conveys the details about which Credentials (format, type, dataset) the Wallet wants to obtain (see Section 5.1.1).
- **New Client metadata parameter** `credential_offer_endpoint`: Allows the Wallet to publish an endpoint where it can receive Credential Offers from Issuers (see Section 12.1).
- **New Authorization Request parameter** `issuer_state`: Carries Issuer context from a Credential Offer into the Authorization Request (see Section 5.1.3).

Any OAuth 2.0 behavior not explicitly changed by this specification follows RFC6749 and applicable OAuth extensions.

## 3.3 Core Concepts

Dataset and Format are conceptually independent, but an Issuer may support only certain combinations. The End-User usually authorizes a Dataset and does not need to choose its encoding. One Dataset can be issued in several formats or as several instances.

### 3.3.1 Format Profiles

Format-specific extension points appear in Issuer metadata, Credential Offers, Authorization Requests, and Credential Requests. Appendix A defines profiles for the standard formats; other profiles may define new ones.

### 3.3.2 Batch Issuance

A single request to the Credential Endpoint can ask for a batch of one or more Verifiable Credentials. Each Credential in the batch can vary along three dimensions:

1. **Credential Format** — the encoding and data model (e.g., SD-JWT VC vs. mdoc).
2. **Credential Dataset** — the actual claim content (e.g., a specific degree or license).
3. **Cryptographic Data** — the Issuer signatures, hashes, and keys used for binding.

Within a single request, all returned Credentials **MUST** share the same Credential Format and Credential Dataset, but **SHOULD** contain different Cryptographic Data. For example, to achieve unlinkability between Credentials (so a Verifier cannot correlate presentations), each Credential in the batch should be bound to a different cryptographic key.

To issue Credentials with differing Formats or Datasets, the Wallet **MUST** send separate requests to the Credential Endpoint.

### 3.3.3 Flow Variations

The issuance process can have multiple characteristics that combine depending on the use case:

- **Authorization Code Flow or Pre-Authorized Code Flow**: The Issuer can obtain End-User information either through standard End-User authentication and consent at the Authorization Endpoint (Authorization Code Flow), or through out-of-band mechanisms that happen before the OAuth flow starts (Pre-Authorized Code Flow).
- **Wallet-initiated or Issuer-initiated**: The Wallet can start the issuance request on its own (e.g., the End-User browses available Credentials), or the Issuer can proactively send a Credential Offer to the Wallet.
- **Same-device or Cross-device Credential Offer**: The End-User may receive the Offer on the same device as the Wallet (e.g., clicking a link), or on a different device (e.g., scanning a QR code displayed on a desktop screen).
- **Immediate or Deferred**: The Issuer can return the Credential directly in the Credential Response (immediate), or indicate that it needs more time and the Wallet should come back later (deferred).

### 3.3.4 How a Credential Is Identified Throughout the Flow

Credentials being issued are identified differently at each stage of the protocol. Understanding this progression is important for correctly implementing the flow:

| Protocol stage | Identifier used | Explanation |
| --- | --- | --- |
| Credential Offer | `credential_configuration_ids` | The Issuer tells the Wallet which Credential Configurations it is offering |
| Authorization Request (authorization details) | `credential_configuration_id` | The Wallet tells the AS which Configuration it wants authorized |
| Token Response | `credential_identifiers` inside `authorization_details` | The AS tells the Wallet which specific Credential Datasets are issuable with this token |
| Credential Request (after identifiers returned) | `credential_identifier` | The Wallet picks one specific Dataset to request from the Credential Endpoint |
| Authorization Request (scope-based) | Issuer-defined scope value | The Wallet uses a scope to identify the desired Configuration |
| Credential Request (scope flow, no identifiers returned) | `credential_configuration_id` | If the AS did not return `credential_identifiers`, the Wallet falls back to the Configuration ID |

## 3.4 Authorization Code Flow

```mermaid
sequenceDiagram
    autonumber
    actor User as End-User
    participant Wallet
    participant AS as Authorization Server
    participant Issuer as Credential Issuer
    alt Wallet initiated
        User->>Wallet: Select/request Credential
    else Issuer initiated
        Issuer-->>Wallet: Credential Offer
    end
    Wallet->>Issuer: Fetch Credential Issuer metadata
    Wallet->>AS: Authorization Request<br/>(requested Credential type(s))
    Note over User,AS: End-User authentication and consent
    AS-->>Wallet: Authorization Response (code)
    Wallet->>AS: Token Request (code + PKCE verifier)
    AS-->>Wallet: Token Response (Access Token)
    Wallet->>Issuer: Credential Request<br/>(Access Token + optional proof(s))
    alt Immediate issuance
        Issuer-->>Wallet: Credential Response with Credential(s)
    else Deferred issuance
        Issuer-->>Wallet: 202 transaction_id + interval
    end
```

Step-by-step:

1. **(Initiation)** The flow begins in one of two ways:
   - **Wallet-initiated**: The End-User selects a Credential they want from the Wallet (either from a pre-configured list or guided by a Verifier's request for a Credential the Wallet does not yet have).
   - **Issuer-initiated**: The Credential Issuer generates a Credential Offer (e.g., as a QR code or link) containing its URL and information about the offered Credential(s). This is defined in Section 4.1.
2. **(Metadata Discovery)** The Wallet uses the Credential Issuer's URL to fetch Issuer metadata. It needs this to learn the supported Credential types and formats, discover the Authorization Endpoint and Credential Endpoint URLs, and understand proof requirements. See Section 12.2.
3. **(Authorization Request)** The Wallet sends an Authorization Request to the Authorization Endpoint, which processes it — typically authenticating the End-User and gathering consent. It is **RECOMMENDED** to use PKCE and Pushed Authorization Requests (PAR). See Section 5.
4. **(Authorization Response)** The Authorization Endpoint returns an Authorization Response containing the Authorization Code. Steps 3 and 4 happen through front-channel browser redirects. The Authorization Server may exchange additional messages with the End-User between these steps (e.g., for multi-factor authentication).
5. **(Token Exchange)** The Wallet sends a Token Request to the Token Endpoint with the Authorization Code. This back-channel step returns an Access Token. See Section 6.
6. **(Credential Issuance)** The Wallet sends a Credential Request to the Credential Endpoint with the Access Token and (optionally) proof(s) of possession of the key(s) to which the Credential should be bound. The Issuer validates both and either returns the Credential(s) immediately or defers issuance with a `transaction_id` and wait interval. See Section 8.

This flow is based on the OAuth 2.0 Authorization Code Grant, but OpenID4VCI can be used with other OAuth grant types as well.

## 3.5 Pre-Authorized Code Flow

```mermaid
sequenceDiagram
    autonumber
    actor User as End-User
    participant Wallet
    participant AS as Authorization Server
    participant Issuer as Credential Issuer
    User->>Issuer: Issuer-specific identification and consent
    Issuer-->>Wallet: Credential Offer<br/>(Pre-Authorized Code)
    Wallet->>Issuer: Fetch Issuer metadata
    User->>Wallet: Interact; enter tx_code if required
    Wallet->>AS: Token Request<br/>(Pre-Authorized Code + optional tx_code)
    AS-->>Wallet: Access Token
    Wallet->>Issuer: Credential Request
    Issuer-->>Wallet: Credential Response
```

In this flow, the Issuer has already conducted End-User authentication and authorization out of band (step 1) before the OAuth flow starts. Consequently, the flow does not use the Authorization Endpoint — the Wallet exchanges the Pre-Authorized Code directly at the Token Endpoint for an Access Token.

**Security warning:** Anyone who possesses a valid Pre-Authorized Code, without further security measures, would be able to receive a Credential from the Issuer. Implementers **MUST** apply suitable mitigations for their use case. One mechanism defined in this specification is the **Transaction Code**: the Issuer indicates in the Credential Offer that a Transaction Code is required and sends it to the End-User via a separate channel (e.g., SMS or e-mail). The Wallet then includes this code in the Token Request, and the Authorization Server verifies it. This binds the Pre-Authorized Code to a specific transaction and prevents replay by an attacker who merely captured the QR code. See Section 13.6 for more details.

## 4. Credential Offer Endpoint

This endpoint is used by a Credential Issuer that is already interacting with an End-User who wishes to initiate a Credential issuance. The Issuer uses it to pass available information relevant for Credential issuance to ensure a convenient and secure process.

The Issuer makes a Credential Offer by allowing the End-User to invoke the Wallet — for example, by clicking a link or scanning a QR code containing the Offer. Credential Issuers **MAY** also communicate Offers directly to a Wallet's backend, but any mechanism for doing so is currently outside the scope of this specification.

## 4.1 Credential Offer

The Credential Offer object is a JSON-encoded object containing the Offer parameters. It can be sent either **by value** or **by reference** using exactly one of two URI query parameters:

- `credential_offer`: Contains the Offer object directly (by value). **MUST NOT** be present when `credential_offer_uri` is present.
- `credential_offer_uri`: A string containing an HTTPS URL that points to a resource containing the Offer object (by reference). **MUST NOT** be present when `credential_offer` is present.

### 4.1.1 Offer Parameters

The JSON-encoded Credential Offer object contains these parameters:

- `credential_issuer` (**REQUIRED**): The URL of the Credential Issuer (as defined in Section 12.2.1). The Wallet uses this URL to fetch the Issuer's metadata following Section 12.2.2.
- `credential_configuration_ids` (**REQUIRED**): A non-empty array of unique strings, each identifying a key in the `credential_configurations_supported` map from Issuer metadata. The Wallet uses these strings to look up information about each offered Credential — including scope values that may be needed in the Authorization Request.
- `grants` (OPTIONAL): An object indicating which Grant Types the Issuer's Authorization Server is prepared to process for this Offer. Each grant is a name/value pair where the name is the Grant Type identifier and the value is an object with parameters determining how the Wallet uses that grant. If `grants` is absent or empty, the Wallet **MUST** determine supported Grant Types from the AS metadata. When multiple grants are present, the Wallet chooses which one to use.

Additional Credential Offer parameters **MAY** be defined and used. The Wallet **MUST** ignore any unrecognized parameters.

**Grant Type `authorization_code`:**

- `issuer_state` (OPTIONAL): A string value created by the Credential Issuer and opaque to the Wallet. It binds the subsequent Authorization Request to context from previous interactions. If the Wallet selects this grant and received this value, it **MUST** include it in the Authorization Request as the `issuer_state` parameter.
- `authorization_server` (OPTIONAL): Identifies which Authorization Server to use when `authorization_servers` in Issuer metadata has multiple entries. **MUST NOT** be used otherwise. The value **MUST** match one of the entries in the `authorization_servers` array.

**Grant Type `urn:ietf:params:oauth:grant-type:pre-authorized_code`:**

- `pre-authorized_code` (**REQUIRED**): The code representing the Issuer's authorization for the Wallet to obtain Credentials. This code **MUST** be short-lived and single-use.
- `tx_code` (OPTIONAL): An object whose presence — even if empty (`{}`) — indicates that a Transaction Code is required. It describes the requirements for the code that the End-User must provide alongside the Token Request. It is **RECOMMENDED** to send the Transaction Code to the End-User via a separate channel (e.g., SMS, e-mail). Sub-fields:
  - `input_mode`: `numeric` (only digits) or `text` (any characters); default is `numeric`.
  - `length`: Integer specifying the expected length, helping the Wallet render an appropriate input screen.
  - `description`: Guidance text for the End-User on how to obtain the code (maximum 300 characters). The Wallet is **RECOMMENDED** to display this next to the input screen.
- `authorization_server` (OPTIONAL): Same matching rule as for the authorization_code grant above.

```json
{
  "credential_issuer": "https://credential-issuer.example.com",
  "credential_configuration_ids": [
    "UniversityDegreeCredential",
    "org.iso.18013.5.1.mDL"
  ],
  "grants": {
    "urn:ietf:params:oauth:grant-type:pre-authorized_code": {
      "pre-authorized_code": "oaKazRN8I0IbtZ0C7JuMn5",
      "tx_code": {
        "length": 4,
        "input_mode": "numeric",
        "description": "Enter the one-time code sent by e-mail"
      }
    }
  }
}
```

### 4.1.2 Offer by Value

The JSON object is percent-encoded inside `credential_offer`:

```text
openid-credential-offer://?
  credential_offer=%7B%22credential_issuer%22%3A%22https%3A%2F%2Fcredential-issuer.example.com%22%2C...%7D
```

By-value Offers are convenient when small, but can make links or QR codes large.

### 4.1.3 Offer by Reference

Invocation:

```text
openid-credential-offer://?
  credential_offer_uri=https%3A%2F%2Fserver.example.com%2Fcredential-offer%2FGkurKxf5T0Y
```

The Wallet **MUST** GET the URI unless cached:

```http
GET /credential-offer/GkurKxf5T0Y HTTP/1.1
Host: server.example.com
Accept: application/json
```

```http
HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: no-store

{
  "credential_issuer": "https://credential-issuer.example.com",
  "credential_configuration_ids": ["UniversityDegreeCredential"],
  "grants": {
    "authorization_code": {
      "issuer_state": "eyJhbGciOiJSU0Et...FYUaBy"
    }
  }
}
```

The response **MUST** use `application/json`. Issuers **SHOULD** use unique URLs or prevent incorrect caching. A referenced Offer cannot be signed and **MUST NOT** use `application/jwt` with `alg: none`.

## 4.2 Credential Offer Response

The Wallet sends no Offer-specific response. UX control remains with the Wallet.

## 5. Authorization Endpoint

The Authorization Endpoint is used in the same manner as defined in RFC6749. Implementers **SHOULD** follow BCP240 (OAuth 2.0 Security Best Current Practice). When the Authorization Code grant type is used, it is **RECOMMENDED** to use PKCE (RFC7636, which prevents authorization code interception attacks) and Pushed Authorization Requests (RFC9126, which ensures the integrity and authenticity of the authorization request).

## 5.1 Authorization Request

An Authorization Request is a standard OAuth 2.0 Authorization Request that requests access to the Credential Endpoint (Section 8). There are two methods for specifying which Credential type(s) to issue:

1. **`authorization_details`** (Section 5.1.1): Uses RFC9396 authorization details of type `openid_credential` for fine-grained control.
2. **`scope`** (Section 5.1.2): Uses OAuth scope values, which are simpler but less expressive.

See Section 3.3.4 for a summary of how requested Credentials are identified throughout the flow.

### 5.1.1 Using `authorization_details`

Credential Issuers **MAY** support requesting authorization to issue a Credential using the `authorization_details` request parameter defined in RFC9396. This approach gives the Wallet explicit, structured control over exactly which Credentials to request.

This specification introduces a new authorization details type `openid_credential` with the following parameters:

- `type` (**REQUIRED**): String that **MUST** be set to `openid_credential`.
- `credential_configuration_id` (**REQUIRED**): String identifying a specific entry in the `credential_configurations_supported` map from Issuer metadata. The referenced object conveys all details of the requested Credential — format, format-specific parameters (like `vct` for SD-JWT VC or `doctype` for mdoc), and more.
- `claims` (OPTIONAL): A non-empty array of claims description objects as defined in Appendix B.1, allowing the Wallet to specify which particular claims it needs.

Additional fields **MAY** be defined. Unknown fields do not invalidate the authorization detail. Multiple `openid_credential` objects and other authorization-detail types may coexist in the same request.

```json
[
  {
    "type": "openid_credential",
    "credential_configuration_id": "UniversityDegreeCredential"
  }
]
```

If metadata contains `authorization_servers`, RFC9396 `locations` **MUST** identify the Issuer:

```json
[
  {
    "type": "openid_credential",
    "locations": ["https://credential-issuer.example.com"],
    "credential_configuration_id": "UniversityDegreeCredential"
  }
]
```

Authorization Request with PKCE (the authorization-details JSON is percent-encoded on the wire):

```http
GET /authorize?response_type=code&
  client_id=s6BhdRkqt3&
  code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&
  code_challenge_method=S256&
  authorization_details=...&
  redirect_uri=https%3A%2F%2Fwallet.example.org%2Fcb HTTP/1.1
Host: server.example.com
```

### 5.1.2 Using `scope`

Credential Issuers **MAY** support requesting authorization using the standard OAuth 2.0 `scope` parameter as a simpler alternative to authorization details.

**Discovering scope values:** When the Wallet does not know which scope value to use, it can discover it from:
- The `scope` field within a Credential Configuration in Issuer metadata (Section 12.2.4).
- When the flow starts with a Credential Offer, the Wallet can use the `credential_configuration_ids` to look up the corresponding Configuration objects and find their `scope` values.
- Normative text in a profile of this specification.

It is **RECOMMENDED** to use collision-resistant scope values. The Wallet **MAY** combine scopes discovered from Issuer metadata with scopes from Authorization Server metadata.

The Issuer **MUST** interpret each scope value as a request to access the Credential Endpoint for issuance of the Credential type identified by that scope. Multiple scope values **MAY** be present; each is processed independently. Unknown scopes **MUST** be ignored.

When the Issuer metadata contains an `authorization_servers` property, it is **RECOMMENDED** to include a `resource` parameter (RFC8707) whose value is the Credential Issuer's identifier, so the Authorization Server can differentiate between Credential Issuers.

```http
GET /authorize?response_type=code&
  scope=UniversityDegreeCredential&
  resource=https%3A%2F%2Fcredential-issuer.example.com&
  client_id=s6BhdRkqt3&
  code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&
  code_challenge_method=S256&
  redirect_uri=https%3A%2F%2Fwallet.example.org%2Fcb HTTP/1.1
Host: server.example.com
```

If a scope value related to Credential issuance and an `authorization_details` object of type `openid_credential` both appear in the same request, the Issuer **MUST** interpret them independently. However, if both request the same Credential type, the `authorization_details` object takes precedence.

### 5.1.3 `issuer_state`

This OPTIONAL value returns Offer context to the Issuer. The Issuer **MUST** treat it as untrusted because an attacker can inject it. Unknown Authorization Request parameters **MUST** be ignored.

### 5.1.4 Pushed Authorization Request

PAR protects confidentiality, integrity, authenticity, and large request data:

```http
POST /par HTTP/1.1
Host: server.example.com
Content-Type: application/x-www-form-urlencoded
OAuth-Client-Attestation: eyJ...
OAuth-Client-Attestation-PoP: eyJ...

response_type=code&client_id=CLIENT1234&
code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&
code_challenge_method=S256&
redirect_uri=https%3A%2F%2Fwallet.example.org%2Fcb&
authorization_details=...
```

```http
HTTP/1.1 201 Created
Content-Type: application/json
Cache-Control: no-cache, no-store

{
  "request_uri": "urn:ietf:params:oauth:request_uri:6esc_11ACC5bwc014ltc14eY22c",
  "expires_in": 60
}
```

The browser then carries only `client_id` and `request_uri` to `/authorize`.

## 5.2 Successful Authorization Response

```http
HTTP/1.1 302 Found
Location: https://wallet.example.org/cb?code=SplxlOBeZQQYbYS6WxSbIA
```

## 5.3 Authorization Error Response

```http
HTTP/1.1 302 Found
Location: https://wallet.example.org/cb?error=invalid_request&error_description=Unsupported%20response_type
```

Both responses follow RFC6749.

## 6. Token Endpoint

The Token Endpoint is where the Wallet exchanges an authorization grant (either an Authorization Code or a Pre-Authorized Code) for an Access Token, and optionally a Refresh Token. The Access Token is then used to call the Credential Endpoint. Implementers **SHOULD** follow BCP240 (OAuth 2.0 Security Best Current Practice).

## 6.1 Token Request

**Authorization Code Grant** — the standard OAuth flow. The Wallet sends the authorization code received from the Authorization Endpoint along with the PKCE code verifier:

```http
POST /token HTTP/1.1
Host: server.example.com
Content-Type: application/x-www-form-urlencoded

grant_type=authorization_code&
code=SplxlOBeZQQYbYS6WxSbIA&
code_verifier=dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk&
redirect_uri=https%3A%2F%2Fwallet.example.org%2Fcb
```

**Pre-Authorized Code Grant** — the Wallet uses `grant_type=urn:ietf:params:oauth:grant-type:pre-authorized_code` and adds:

- `pre-authorized_code`: **MUST** be present; it is the code received in the Credential Offer.
- `tx_code`: **MUST** be present if the Credential Offer contained a `tx_code` object (even an empty `{}`), because that signals the Authorization Server expects a Transaction Code. The `tx_code` parameter **MUST NOT** be used with other grant types.

Client Authentication is OPTIONAL for the Pre-Authorized Code grant. The `client_id` parameter is required only when the Client's chosen authentication method uses it. When the Authorization Server's metadata sets `pre-authorized_grant_anonymous_access_supported` to `true`, anonymous requests without `client_id` are allowed.

The scope of the Access Token returned in this flow should cover only the Credentials that were offered. If the Wallet needs Credentials from a different Credential Configuration not included in the Offer, it should obtain a separate Access Token.

### 6.1.1 Selecting a Configuration at the Token Endpoint

When using the Pre-Authorized Code flow, the Wallet may include `authorization_details` in the Token Request to indicate which specific Credential Configurations it wants to obtain from those offered. This is useful when the Credential Offer includes multiple Configurations and the Wallet only wants a subset.

```http
POST /token HTTP/1.1
Host: server.example.com
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:pre-authorized_code&
pre-authorized_code=SplxlOBeZQQYbYS6WxSbIA&
tx_code=493536&
authorization_details=...
```

The Wallet may repeat `authorization_details` it used in a prior Authorization Request, or include a subset of the originally offered Configurations. The Authorization Server is **RECOMMENDED** to accept a reduced subset of the originally requested Configurations. Unknown parameters **MUST** be ignored.

## 6.2 Successful Token Response

The Token Response follows standard OAuth 2.0, with the addition of `authorization_details` when authorization details were used.

- `authorization_details` is **REQUIRED** in the Token Response if `authorization_details` was used in the Authorization Request or Token Request. It is OPTIONAL when the Wallet used scopes instead.
- Each `authorization_details` object in the response contains `credential_identifiers` (**REQUIRED**): a non-empty array of strings. Each string is a `credential_identifier` that the Wallet can use in a subsequent Credential Request to identify a specific Credential Dataset that is issuable with this Access Token.

```http
HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: no-store

{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6Ikp..sHQ",
  "token_type": "Bearer",
  "expires_in": 86400,
  "authorization_details": [
    {
      "type": "openid_credential",
      "credential_configuration_id": "UniversityDegreeCredential",
      "credential_identifiers": [
        "CivilEngineeringDegree-2023",
        "ElectricalEngineeringDegree-2023"
      ]
    }
  ]
}
```

In this example, the Authorization Server tells the Wallet that with this Access Token, it can request either a "CivilEngineeringDegree-2023" or an "ElectricalEngineeringDegree-2023" Credential — both under the `UniversityDegreeCredential` Configuration. The Wallet uses one of these `credential_identifier` values in its next Credential Request.

Unknown response fields **MUST** be ignored.

## 6.3 Token Error Response

Errors follow standard OAuth 2.0 error response format (RFC6749). The following error codes have specific meanings in the context of OpenID4VCI:

| Error | Condition |
| --- | --- |
| `invalid_request` | The `tx_code` parameter was present when it should not have been, or was missing when the Credential Offer required it |
| `invalid_grant` | The Transaction Code is incorrect; or the Pre-Authorized Code is wrong, expired, or already used |
| `invalid_client` | The request was sent without a Client ID (anonymous), but the Authorization Server requires one for this grant |

```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
Cache-Control: no-store

{ "error": "invalid_request" }
```

## 7. Nonce Endpoint

The Nonce Endpoint provides fresh `c_nonce` values that the Wallet includes in its key-possession proofs when requesting a Credential. This mechanism prevents proof replay: each proof is tied to a specific nonce, ensuring an attacker cannot capture a proof and reuse it to obtain duplicate Credentials.

An Issuer that requires `c_nonce` in Credential key proofs **MUST** publish a Nonce Endpoint in its metadata.

## 7.1 Nonce Request

The Nonce Endpoint is not protected by an Access Token — anyone can request a nonce. The request has an empty body:

```http
POST /nonce HTTP/1.1
Host: credential-issuer.example.com
Content-Length: 0
```

## 7.2 Nonce Response

```http
HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: no-store
DPoP-Nonce: eyJ7S_zG.eyJH0-Z.HX4w-7v

{
  "c_nonce": "wKI4LT17ac15ES9bw8ac4"
}
```

- `c_nonce` (**REQUIRED**): An unpredictable string that the Wallet incorporates into its Credential key proof (e.g., as the `nonce` claim in a JWT proof). It ensures the proof is freshly generated for this specific issuance session.
- `DPoP-Nonce` (header): This is a **separate** value used for DPoP (Demonstrating Proof of Possession) token binding. It protects Access Token usage and is unrelated to the Credential key proof. The Wallet uses it in the DPoP proof header when calling the Credential Endpoint with a DPoP-bound Access Token.

The response **MUST** include `Cache-Control: no-store` to ensure the Wallet always gets a fresh nonce.

## 8. Credential Endpoint

The Credential Endpoint is the core issuance endpoint in OpenID4VCI. It is **REQUIRED**, must be protected by a valid Access Token, and **MUST** use TLS. A single request to this endpoint issues one or several Credentials that share the same Credential Configuration and Credential Dataset (but may have different cryptographic data for unlinkability).

```mermaid
sequenceDiagram
    autonumber
    participant Wallet
    participant CE as Credential Endpoint
    participant DE as Deferred Endpoint
    participant NE as Notification Endpoint
    Wallet->>CE: Credential Request<br/>(token, identifier, proof(s))
    alt Immediate
        CE-->>Wallet: 200 credentials + optional notification_id
    else Deferred
        CE-->>Wallet: 202 transaction_id + interval
        loop Until ready
            Wallet->>DE: transaction_id + token
            DE-->>Wallet: 202 pending or 200 credentials
        end
    end
    opt Notification
        Wallet->>NE: notification_id + event + token
        NE-->>Wallet: 204 No Content
    end
```

## 8.1 Holder Binding

An issued Credential **SHOULD** be cryptographically bound to the Holder (the possessing End-User). This is achieved by including one or more proof(s) of private-key possession or key attestation(s) in the Credential Request. The proof conveys the public key(s) that the Issuer should bind to the Credential.

Appendix F defines the supported proof types (JWT, Data Integrity VP, and Attestation). Section 14 discusses alternative binding models such as claims-based binding and bearer Credentials.

## 8.2 Credential Request

The Credential Request is a JSON object sent with `Content-Type: application/json` and an `Authorization` header carrying the Access Token.

**Credential Selector** — exactly one of the following parameters must be sent to identify which Credential to issue:

| Selector | When used |
| --- | --- |
| `credential_identifier` | **REQUIRED** when `credential_identifiers` were returned in the Token Response. When present, `credential_configuration_id` **MUST NOT** be used. The value must be one of the identifiers from the Token Response. |
| `credential_configuration_id` | **REQUIRED** when no `credential_identifiers` were returned in the Token Response (e.g., in scope-based flows without identifier support). When present, `credential_identifier` **MUST NOT** be used. |

**Key Proofs** — `proofs` is an object containing exactly one proof-type member (e.g., `"jwt"`) whose value is a non-empty array of proof strings or objects. The `proofs` parameter **MUST** be present when the Credential Configuration's metadata includes `proof_types_supported`. Each proof in the array:

- **MUST** specify the Credential Issuer Identifier as the audience, so the Issuer knows the proof was intended for it.
- **MUST** include the current `c_nonce` when the Issuer advertises a Nonce Endpoint, proving freshness.

| Proof type | Freshness field | Audience field |
| --- | --- | --- |
| JWT | `nonce` (in payload) | `aud` (in payload) |
| Data Integrity / Linked Data | `challenge` (in proof object) | `domain` (in proof object) |

Each proof key binds at most one returned Credential. Providing multiple proofs in the array is how the Wallet requests a batch of Credentials bound to different keys.

Single mdoc request:

```http
POST /credential HTTP/1.1
Host: credential-issuer.example.com
Content-Type: application/json
Authorization: Bearer czZCaGRSa3F0MzpnWDFmQmF0M2JW

{
  "credential_configuration_id": "org.iso.18013.5.1.mDL",
  "proofs": {
    "jwt": ["eyJ0eXAiOiJvcGVuaWQ0dmNpLXByb29mK2p3dCIs..."]
  }
}
```

Batch SD-JWT VC request using a Token Response identifier (two proof keys = requesting two Credential instances):

```json
{
  "credential_identifier": "CivilEngineeringDegree-2023",
  "proofs": {
    "jwt": [
      "eyJ0eXAiOiJvcGVuaWQ0dmNpLXByb29mK2p3dCIs...key-1...",
      "eyJ0eXAiOiJvcGVuaWQ0dmNpLXByb29mK2p3dCIs...key-2..."
    ]
  }
}
```

**Response Encryption** — if the Wallet wants the Credential Response to be encrypted, it includes a `credential_response_encryption` object containing:
- `jwk` (**REQUIRED**): The Wallet's encryption public key.
- `enc` (**REQUIRED**): The content encryption algorithm.
- `zip` (OPTIONAL): Compression algorithm. If absent, compression **MUST NOT** be used.

When response encryption is requested, the Credential Request itself **MUST** also be encrypted (against the Issuer's key from metadata). This prevents an attacker from injecting their own response-encryption key.

Request encryption follows the Issuer's `credential_request_encryption` metadata. It is mandatory when `encryption_required=true`; otherwise it is optional. Unencrypted requests use `application/json` as the Content-Type. Unknown request parameters **MUST** be ignored.

## 8.3 Credential Response

The Credential Endpoint returns one of two mutually exclusive response types:

**Immediate issuance** — the Credential(s) are ready and returned directly:

```http
HTTP/1.1 200 OK
Content-Type: application/json
Cache-Control: no-store

{
  "credentials": [
    { "credential": "LUpixVCWJk0eOt4CXQe1NXK....WZwmhmn9OQp6YxX0a2L" },
    { "credential": "YXNkZnNhZGZkamZqZGFza23....29tZTIzMjMyMzIzMjMy" }
  ],
  "notification_id": "3fwe98js"
}
```

**Deferred issuance** — the Issuer needs more time (e.g., for manual review) and returns a transaction identifier:

```http
HTTP/1.1 202 Accepted
Content-Type: application/json
Cache-Control: no-store

{
  "transaction_id": "8xLOxBtZp8",
  "interval": 3600
}
```

**Response parameter rules:**

- `credentials` and `transaction_id` are **mutually exclusive** — exactly one appears in any response.
- Each item in the `credentials` array requires a `credential` field. For binary Credential formats (e.g., ISO mdoc), the value is a base64url-encoded string.
- The Issuer **MAY** return fewer Credentials than the number of proofs submitted. The Wallet should not assume a 1:1 mapping.
- `transaction_id` is a string the Wallet uses to poll the Deferred Credential Endpoint. It **MUST** be invalidated by the Issuer after the Credential has been successfully retrieved.
- `interval` (**REQUIRED** when `transaction_id` is present): The minimum number of seconds the Wallet **MUST** wait before polling the Deferred Credential Endpoint.
- `notification_id` (OPTIONAL): Can only appear alongside `credentials`, not with `transaction_id`. The Wallet uses this value to later notify the Issuer about the outcome of Credential storage (see Section 11).
- When the Wallet requested an encrypted response, the Issuer **MUST** encrypt it. Otherwise, the response uses `application/json`.

### 8.3.1 Errors

Access Token errors (e.g., expired or invalid token) follow RFC6750 and return the appropriate HTTP status (typically 401).

Credential Request payload errors return HTTP 400 with a JSON body containing an `error` field. The defined error codes are:

| Error code | Meaning |
| --- | --- |
| `invalid_credential_request` | The request is malformed — missing required fields, wrong types, or other structural problems |
| `unknown_credential_configuration` | The `credential_configuration_id` does not match any Configuration the Issuer supports |
| `unknown_credential_identifier` | The `credential_identifier` is not recognized or was not issued in the Token Response |
| `invalid_proof` | The proof(s) of key possession failed verification (bad signature, wrong algorithm, etc.) |
| `invalid_nonce` | The `c_nonce` in the proof is expired or unknown. The Wallet should obtain a fresh nonce from the Nonce Endpoint and retry |
| `invalid_encryption_parameters` | The encryption parameters in the request are invalid or unsupported |
| `credential_request_denied` | The Issuer has denied the request for business or policy reasons. The Wallet **SHOULD** treat this as an unrecoverable error and not retry |

```http
HTTP/1.1 400 Bad Request
Content-Type: application/json
Cache-Control: no-store

{ "error": "unknown_credential_configuration" }
```

Credential Error Responses are **never** encrypted, even when the Wallet requested response encryption. An optional `error_description` field may provide additional detail using restricted ASCII characters.

## 9. Deferred Credential Endpoint

The Deferred Credential Endpoint allows the Wallet to retrieve a Credential that was not immediately available at the time of the initial Credential Request. This is useful when the Issuer needs time for offline processing — such as manual identity verification, background checks, or administrative approval — before the Credential can be issued.

This OPTIONAL endpoint **MUST** use TLS and requires an Access Token that is valid for the original issuance (i.e., the same token or a refreshed one from the same authorization).

## 9.1 Deferred Request

The Wallet sends a POST request with the `transaction_id` received from the Credential Endpoint:

```http
POST /deferred_credential HTTP/1.1
Host: credential-issuer.example.com
Content-Type: application/json
Authorization: Bearer czZCaGRSa3F0MzpnWDFmQmF0M2JW

{ "transaction_id": "8xLOxBtZp8" }
```

The request **MUST** include the `transaction_id` parameter. It may also contain fresh `credential_response_encryption` parameters if the Wallet wants to update its encryption key (e.g., because the original key has expired). If response-encryption parameters are present, the request itself **MUST** be encrypted to prevent key substitution attacks.

The `transaction_id` is invalidated after the Credential has been successfully delivered. Unknown fields in the request are ignored.

## 9.2 Deferred Response

**Credential ready:**

```http
HTTP/1.1 200 OK
Content-Type: application/json

{
  "credentials": [
    { "credential": "LUpixVCWJk0eOt4CXQe1NXK....WZwmhmn9OQp6YxX0a2L" }
  ],
  "notification_id": "3fwe98js"
}
```

**Still pending** — the Issuer is not yet ready and returns the same `transaction_id` with a new recommended wait interval:

```http
HTTP/1.1 202 Accepted
Content-Type: application/json

{ "transaction_id": "8xLOxBtZp8", "interval": 86400 }
```

The pending response **MUST** return the same transaction identifier so the Wallet can continue polling. If the Wallet supplied new encryption parameters, they replace the ones from the original request for the eventual Credential delivery.

## 9.3 Deferred Errors

- `invalid_transaction_id`: The transaction identifier is unknown, has already been consumed (Credential already delivered), or has expired. The Wallet should not retry with this identifier.
- `credential_request_denied`: The Issuer has determined that the Credential cannot be issued (e.g., the background check failed). The Wallet **SHOULD** stop polling and inform the End-User.

## 10. Encrypted Credential Requests and Responses

Application-layer encryption provides confidentiality **on top of** TLS. It is useful in architectures where intermediary components (such as proxies, load balancers, or split-Wallet backend servers) may have access to decrypted TLS traffic but should not see the Credential content.

The encryption process works as follows:

1. Encode the complete request or response message as a JWT payload and set the Content-Type to `application/jwt`.
2. Encrypt the JWT as a JWE (JSON Web Encryption).
3. The selected encryption JWK **MUST** contain an `alg` field. The JWE header's `alg` value must equal the JWK's `alg`.
4. If the JWK contains a `kid` (key identifier), the JWE header must repeat the same `kid` so the recipient can select the correct decryption key.
5. Select the `enc` (content encryption algorithm) from the applicable set of supported values published in Issuer metadata.
6. If `zip` is specified in the applicable metadata, compress the payload before encryption. If `zip` is not specified, compression **MUST NOT** be applied.

A message that was required to be encrypted (because `encryption_required=true` in metadata) but arrived unencrypted **SHOULD** be rejected by the recipient.

## 11. Notification Endpoint

The Notification Endpoint is an OPTIONAL, TLS-protected endpoint that lets the Wallet inform the Credential Issuer about what happened after the Credential(s) were issued. This is important because the Issuer has no other way to know whether the Wallet successfully stored the Credential, whether the End-User deleted it, or whether storage failed.

The Wallet sends the `notification_id` (returned by the Credential or Deferred Credential Endpoint along with the Credentials) and the applicable event. A valid Access Token is required. Notification calls are **idempotent** (sending the same notification multiple times has the same effect), but delivery is not guaranteed — the Issuer should not depend on receiving notifications for critical business logic.

## 11.1 Notification Request

The request body contains:

- `notification_id` (**REQUIRED**): The identifier returned by the Issuer alongside the Credentials.
- `event` (**REQUIRED**): A case-sensitive string indicating the outcome. Defined values:
  - `credential_accepted`: The Wallet successfully stored **all** Credentials associated with this notification.
  - `credential_deleted`: The End-User actively deleted the Credential(s) after they were stored.
  - `credential_failure`: The Wallet could not store the Credential(s) due to a technical or other failure.
- `event_description` (OPTIONAL): A human-readable explanation using restricted ASCII characters.

For batch issuance, any partial failure (even one Credential out of several failing to store) **MUST** be treated as an overall failure and reported as `credential_failure`.

```http
POST /notification HTTP/1.1
Host: credential-issuer.example.com
Content-Type: application/json
Authorization: Bearer czZCaGRSa3F0MzpnWDFmQmF0M2JW

{
  "notification_id": "3fwe98js",
  "event": "credential_accepted"
}
```

Failure example:

```json
{
  "notification_id": "3fwe98js",
  "event": "credential_failure",
  "event_description": "Could not store the Credential. Out of storage."
}
```

Unknown fields in the request are ignored.

## 11.2 Successful Notification Response

A successful response **MUST** use a 2xx HTTP status code. `204 No Content` is **RECOMMENDED** since there is no response body.

## 11.3 Notification Error Response

Access Token errors follow RFC6750 (typically 401). Other failures return HTTP 400 with one of:

- `invalid_notification_id`: The `notification_id` is unknown, already consumed, or malformed.
- `invalid_notification_request`: The request is structurally invalid (e.g., missing required fields).

```json
{ "error": "invalid_notification_id" }
```

## 12. Metadata

This section defines the metadata structures that enable Wallets and Credential Issuers to discover each other's capabilities. Metadata is the foundation that makes the protocol interoperable — without it, a Wallet would not know what Credentials an Issuer supports, which endpoints to call, or what cryptographic algorithms to use.

## 12.1 Client Metadata

This specification defines one additional Client Metadata parameter (beyond those in RFC7591) for Wallets acting as OAuth 2.0 Clients:

- `credential_offer_endpoint` (OPTIONAL): The URL of the Wallet's Credential Offer Endpoint — where the Issuer can send Credential Offers to this specific Wallet.

Additional Client metadata parameters **MAY** be defined and used as described in RFC7591. The Wallet **MUST** ignore any unrecognized parameters.

### 12.1.1 Client Metadata Retrieval

How to obtain Client Metadata is out of scope of this specification. Profiles of this specification **MAY** define static sets of Client Metadata values to be used.

If the Credential Issuer is unable to perform discovery of the Wallet's Credential Offer Endpoint (i.e., it does not know the Wallet-specific URL), the following custom URL scheme is used as a fallback: `openid-credential-offer://`. This enables the Issuer to construct a Credential Offer URI that any compatible Wallet can handle.

## 12.2 Credential Issuer Metadata

Credential Issuer Metadata contains information about the Issuer's technical capabilities, supported Credentials, and (internationalized) display information. It is the primary mechanism by which Wallets learn what an Issuer can do.

### 12.2.1 Credential Issuer Identifier

A Credential Issuer is identified by a case-sensitive URL using the `https` scheme. The URL contains scheme, host, and optionally port and path components, but **no** query or fragment components.

### 12.2.2 Metadata Retrieval

Credential Issuers publishing metadata **MUST** make a JSON document available at a well-known path. The path is formed by inserting `/.well-known/openid-credential-issuer` into the Credential Issuer Identifier **between the host component and the path component** (if any).

| Issuer Identifier | Metadata URL |
| --- | --- |
| `https://issuer.example.com/tenant` | `https://issuer.example.com/.well-known/openid-credential-issuer/tenant` |
| `https://tenant.issuer.example.com` | `https://tenant.issuer.example.com/.well-known/openid-credential-issuer` |

Communication with the Credential Issuer Metadata Endpoint **MUST** utilize TLS. The Wallet sends an HTTP GET request to the constructed URL:

```http
GET /.well-known/openid-credential-issuer HTTP/1.1
Host: credential-issuer.example.com
Accept: application/json, application/jwt
Accept-Language: fr-CH, fr;q=0.9, en;q=0.8
```

The Wallet is **RECOMMENDED** to send:
- An `Accept` header to signal whether it supports signed metadata (`application/jwt`).
- An `Accept-Language` header to indicate preferred display languages. Language values **MUST** use RFC3066 format.

The Credential Issuer **MUST** respond with HTTP 200 and return metadata as either:
- An **unsigned JSON document** using `application/json` (support is **REQUIRED**), or
- A **signed JWT** using `application/jwt` (support is OPTIONAL, see Section 12.2.3).

The Issuer **MUST** indicate the media type using the `Content-Type` header and is **RECOMMENDED** to match the Wallet's `Accept` preference when the requested type is supported.

For internationalization, it is up to the Issuer whether to return a subset of display data for the requested language(s) (indicated via `Content-Language` header) or to return all supported languages regardless of the request.

### 12.2.3 Signed Metadata

Signed metadata is secured using JWS (JSON Web Signature) and provides authenticity and integrity guarantees. This is useful when the Wallet needs assurance that the metadata was not tampered with by intermediaries.

**JOSE Header requirements:**
- `alg` (**REQUIRED**): A digital signature algorithm identifier from the IANA JOSE registry. It **MUST NOT** be `none` or a symmetric algorithm (MAC).
- `typ` (**REQUIRED**): **MUST** be `openidvci-issuer-metadata+jwt`, which explicitly types the metadata JWT as recommended by RFC8725.

**JWS Payload requirements:**
- `iss` (OPTIONAL): String identifying the party attesting to the claims in the signed metadata (this may differ from the Issuer itself, e.g., a trust framework operator).
- `sub` (**REQUIRED**): **MUST** match the Credential Issuer Identifier exactly.
- `iat` (**REQUIRED**): Integer timestamp when the metadata was issued (RFC7519 syntax).
- `exp` (OPTIONAL): Integer timestamp when the metadata expires.
- All metadata parameters **MUST** be included as top-level claims in the JWS payload.

The Wallet **MUST** establish trust in the signer of the metadata before processing it. If trust cannot be established, the Wallet **MUST** reject the signed metadata. The Wallet obtains the validation keys using JOSE header parameters such as `x5c`, `kid`, or `trust_chain`. The concrete trust establishment mechanisms are out of scope of this specification.

### 12.2.4 Metadata Parameters

The following parameters define the Credential Issuer's capabilities and endpoints:

**Core Endpoint Parameters:**

| Parameter | Req. | Description |
| --- | --- | --- |
| `credential_issuer` | **REQUIRED** | The Credential Issuer's Identifier (Section 12.2.1). **MUST** exactly match the Identifier that was used to construct the well-known URL. If they differ (simple string comparison, no normalization), the Wallet **MUST NOT** use the data. |
| `authorization_servers` | OPTIONAL | A non-empty array of Authorization Server identifiers (RFC8414). If omitted, the Issuer itself is the Authorization Server, and the Issuer's own Identifier is used to fetch AS metadata. When multiple entries are present, the Wallet can filter by examining `grant_types_supported` in each AS's metadata. If the Credential Offer contains an `authorization_server` hint, it **MUST** match one of these entries or the Wallet **MUST NOT** proceed. |
| `credential_endpoint` | **REQUIRED** | HTTPS URL of the Credential Endpoint (Section 8). |
| `nonce_endpoint` | OPTIONAL | HTTPS URL of the Nonce Endpoint (Section 7). If omitted, the Issuer does not require `c_nonce` in key proofs. |
| `deferred_credential_endpoint` | OPTIONAL | HTTPS URL of the Deferred Credential Endpoint (Section 9). If omitted, deferred issuance is not supported. |
| `notification_endpoint` | OPTIONAL | HTTPS URL of the Notification Endpoint (Section 11). If omitted, the Issuer does not accept notifications. |

**Encryption Parameters:**

- `credential_request_encryption` (OPTIONAL): Describes whether the Issuer supports encryption of Credential Requests on top of TLS.
  - `jwks` (**REQUIRED**): A JSON Web Key Set containing one or more public keys for the Wallet to use for request encryption. Each JWK **MUST** have a unique `kid`.
  - `enc_values_supported` (**REQUIRED**): Array of supported JWE content encryption algorithms (`enc` values).
  - `zip_values_supported` (OPTIONAL): Array of supported compression algorithms. If absent, no compression is supported.
  - `encryption_required` (**REQUIRED**): Boolean. If `true`, every Credential Request must be encrypted. If `false`, encryption is optional.

- `credential_response_encryption` (OPTIONAL): Describes whether the Issuer supports encryption of Credential Responses on top of TLS.
  - `alg_values_supported` (**REQUIRED**): Array of supported JWE key management algorithms (`alg` values).
  - `enc_values_supported` (**REQUIRED**): Array of supported JWE content encryption algorithms.
  - `zip_values_supported` (OPTIONAL): Array of supported compression algorithms.
  - `encryption_required` (**REQUIRED**): Boolean. If `true`, responses are always encrypted and the Wallet **MUST** provide encryption keys in the Credential Request. If `false`, the Wallet may choose.

**Batch Issuance:**

- `batch_credential_issuance` (OPTIONAL): Indicates that the Issuer supports more than one key proof in the `proofs` parameter (i.e., batch issuance).
  - `batch_size` (**REQUIRED**): Maximum array size for the `proofs` parameter. **MUST** be 2 or greater.

**Display Information:**

- `display` (OPTIONAL): Array of objects, each containing display properties for a certain language:
  - `name` (OPTIONAL): Display name for the Credential Issuer.
  - `locale` (OPTIONAL): Language tag (BCP47). There **MUST** be only one object per language.
  - `logo` (OPTIONAL): Object with `uri` (**REQUIRED**) and optional `alt_text`.

**Credential Configurations:**

`credential_configurations_supported` (**REQUIRED**): An object where each key is a unique Credential Configuration Identifier (used in Credential Offers and authorization requests) and each value describes one kind of Credential the Issuer can issue. Each Configuration contains:

- `format` (**REQUIRED**): Identifier for the Credential Format (e.g., `dc+sd-jwt`, `mso_mdoc`, `jwt_vc_json`). Determines which format-specific parameters apply (see Appendix A).
- `scope` (OPTIONAL): The OAuth scope value that can be used to request this Credential in an Authorization Request (Section 5.1.2). If absent, the Credential can only be requested using `authorization_details` — in this case, the AS metadata must list `openid_credential` in `authorization_details_types_supported`.
- `credential_signing_alg_values_supported` (OPTIONAL): Array of algorithm identifiers the Issuer uses to sign this Credential type.
- `cryptographic_binding_methods_supported` (OPTIONAL): Array of strings identifying how the Credential can be cryptographically bound to the Holder. **MUST** be present when Cryptographic Key Binding is required; omitted otherwise. Values include:
  - `jwk` — keys in JWK format
  - `cose_key` — keys as COSE Key objects (e.g., for ISO mdoc)
  - `did:<method-name>` — DID-based binding (e.g., `did:example`)
- `proof_types_supported` (OPTIONAL): Object describing which proof types the Issuer accepts. **MUST** be present when `cryptographic_binding_methods_supported` is present. Each key is a proof type identifier (see Appendix F), and each value contains:
  - `proof_signing_alg_values_supported` (**REQUIRED**): Array of algorithms the Wallet can use to sign the proof.
  - `key_attestations_required` (OPTIONAL): Object describing required key attestation properties (see Appendix D). Contains optional `key_storage` and `user_authentication` arrays.
- `credential_metadata` (OPTIONAL): Fallback display and claims information. Format-specific mechanisms (e.g., SD-JWT VC display metadata) always take precedence over this object. Contains:
  - `display` (OPTIONAL): Array of localized display objects with `name` (**REQUIRED**), optional `locale`, `logo`, `description`, `background_color`, `background_image`, and `text_color`.
  - `claims` (OPTIONAL): Array of claims description objects (see Appendix B.2).

Example SD-JWT VC Configuration:

```json
{
  "credential_issuer": "https://credential-issuer.example.com",
  "authorization_servers": ["https://auth.example.com"],
  "credential_endpoint": "https://credential-issuer.example.com/credential",
  "nonce_endpoint": "https://credential-issuer.example.com/nonce",
  "deferred_credential_endpoint": "https://credential-issuer.example.com/deferred_credential",
  "notification_endpoint": "https://credential-issuer.example.com/notification",
  "batch_credential_issuance": { "batch_size": 10 },
  "credential_configurations_supported": {
    "SD_JWT_VC_example": {
      "format": "dc+sd-jwt",
      "scope": "SD_JWT_VC_example",
      "vct": "https://credentials.example.com/identity_credential",
      "cryptographic_binding_methods_supported": ["jwk"],
      "credential_signing_alg_values_supported": ["ES256"],
      "proof_types_supported": {
        "jwt": {
          "proof_signing_alg_values_supported": ["ES256"]
        }
      },
      "credential_metadata": {
        "display": [
          {
            "name": "Identity Credential",
            "locale": "en-US",
            "logo": {
              "uri": "https://credential-issuer.example.com/logo.png",
              "alt_text": "Issuer logo"
            },
            "background_color": "#12107c",
            "text_color": "#FFFFFF"
          }
        ],
        "claims": [
          { "path": ["given_name"] },
          { "path": ["family_name"] },
          { "path": ["email"] }
        ]
      }
    }
  }
}
```

The Authorization Server **MUST** be able to determine from the Issuer metadata what claims are disclosed by the requested Credentials, so it can render meaningful End-User consent. Wallets **MUST** ignore unknown metadata parameters. An Authorization Server that only supports the Pre-Authorized Code grant type **MAY** omit the `response_types_supported` parameter in its metadata despite RFC8414 mandating it.

> **Note:** It can be challenging for a Credential Issuer that accepts tokens from multiple Authorization Servers to introspect an Access Token. Some approaches include using RFC9068 (JWT Access Tokens) or understanding the proprietary Access Token structures of each Authorization Server.

## 12.3 Authorization Server Metadata

This specification defines one new OAuth 2.0 Authorization Server metadata parameter (RFC8414):

- `pre-authorized_grant_anonymous_access_supported` (OPTIONAL, default: `false`): A boolean indicating whether the Authorization Server accepts a Token Request with a Pre-Authorized Code but **without** a `client_id`. When `true`, the Wallet may send an anonymous Token Request in the Pre-Authorized Code flow.

Additional Authorization Server metadata parameters **MAY** be defined. The Wallet **MUST** ignore any unrecognized parameters.

## 13. Security Considerations

This section outlines the key security threats and the mitigations available within the OpenID4VCI protocol. Implementers should carefully review each consideration and apply the appropriate mitigations for their deployment.

## 13.1 Formal Analysis

The security properties of some features in a previous revision of this specification have been formally analyzed (see the referenced security analysis). This provides a degree of assurance about the protocol's core security properties, though implementers should note it applies to an earlier revision and may not cover all current features.

## 13.2 OAuth Security Baseline

Implementers **SHOULD** follow the Best Current Practice for OAuth 2.0 Security (BCP240) and are **RECOMMENDED** to apply FAPI 2.0 Security Profile where applicable.

However, some parts of FAPI 2.0 may not be practical for native app Wallets:
- **Client Authentication**: The `private_key_jwt` and mTLS methods may be difficult to implement securely in native apps. The use of **Wallet Attestations** (Appendix E) is **RECOMMENDED** instead.
- **Sender-constrained Access Tokens**: mTLS sender-constraining may not be practical in native apps. The use of **DPoP** (RFC9449) is **RECOMMENDED** as an alternative.

## 13.3 Wallet–Issuer Trust

Credential Issuers often want to know what Wallet they are issuing Credentials to and how private keys are managed, for two main reasons:

1. The Issuer may want to ensure private keys are protected from exfiltration and replay, preventing an adversary from impersonating the Holder.
2. The Issuer may want to verify the Wallet adheres to certain policies, audits, or regulatory/commercial schemes.

Three mechanisms work together to address these needs:

- **Key Attestation** (Appendix D): The key storage component or Wallet Provider asserts the cryptographic public keys and their security policy. The Issuer validates this against the attestation's trust anchor.
- **Client Authentication**: The Wallet authenticates with the Authorization Server using any method from the OAuth Token Endpoint Authentication Methods registry. The AS specifies requirements via `token_endpoint_auth_method` metadata.
- **Wallet Attestation** (Appendix E): A signed proof from the Wallet Provider verifying the client's authenticity. This can be used as the client authentication method.

## 13.4 Split-Architecture Wallets

A Wallet may consist of multiple components with varying trust levels — commonly a server-side backend and a native application. While the server component offers advantages (reliability, centralized security controls), it also introduces risks:

- Harder to audit, especially by external experts
- Potential for opaque or unverified updates
- Higher susceptibility to insider threats

**Mitigations:**
- Apply the principle of **data minimization** — the server should see as little user data as possible.
- Use **application-layer encryption** (Section 10) end-to-end, from the device through the server component.
- A server that acts as the trust anchor (e.g., for Wallet or Key Attestations) **cannot also serve as a safeguard against itself** — it is inherently trusted.
- If the server has access to authorization codes, pre-authorization codes, or other sensitive tokens/proofs, and no additional mitigations are in place, it **MAY** be able to impersonate the application. Such sensitive elements **MUST NOT** be passed through an untrusted component.

## 13.5 Credential Offer Security

Credential Offers have **no authenticated origin and no message integrity protection**. The Wallet **MUST** consider all parameter values in the Offer as untrusted — the Credential Issuer is not considered trustworthy just because it sent an Offer. An attacker might use a Credential Offer to conduct a phishing or injection attack.

Specifically:
- The Wallet **MUST** perform the same validation checks on the Issuer as it would in a Wallet-initiated flow.
- The Wallet **MUST NOT** accept Credentials just because an Offer was used — all protocol steps must be executed normally.
- The Credential Issuer **MUST** ensure that any privacy-sensitive data released in the Offer is legally permissible.

## 13.6 Pre-Authorized Code Security

### 13.6.1 Replay Prevention

The Pre-Authorized Code flow is vulnerable to replay because, by design, the code is not bound to a particular session (unlike the Authorization Code flow with PKCE). This means an attacker can replay a captured Pre-Authorized Code at a different device. In a "shoulder surfing" scenario, the attacker scans the QR code while standing behind the legitimate End-User. Since Pre-Authorized Codes are shared as links or QR codes, they may also be forwarded beyond their intended recipient.

**Mitigation:** The Credential Issuer can set up a **Transaction Code** delivered to the End-User via a separate channel (e.g., SMS or email) that must be presented in the Token Request.

### 13.6.2 Transaction Code Phishing

An attacker could set up a fake Credential Issuer and, in parallel, trigger a Transaction Code from a legitimate service (e.g., a payment service) to the End-User's phone. The End-User would then be tricked into entering this code into the Wallet, which sends it to the attacker's Token Endpoint — giving the attacker access to the other service.

**Mitigations:**
- Wallets are **RECOMMENDED** to interact with trusted Credential Issuers only and reject Offers from unrecognized Issuer URLs.
- The Wallet **MAY** display the Token Endpoint URL to the End-User and ask for confirmation before submitting the Transaction Code.

## 13.7 Credential Lifecycle

The Credential Issuer is responsible for the lifecycle of its Credentials and will invalidate them when appropriate (e.g., upon detecting fraudulent behavior).

The Wallet is expected to detect signs of fraudulent behavior related to Credential management (e.g., device rooting, jailbreaking) and respond by:
- Requesting Credential revocation at the Issuer, and/or
- Invalidating the key material used for Cryptographic Key Binding.

## 13.8 Proof Replay

If an adversary obtains a key proof (Appendix F), they could replay it to a Credential Issuer to obtain a duplicate Credential — or multiple duplicates — issued to the same key.

**Primary defense:** The `c_nonce` parameter allows the Issuer to verify the freshness of a proof. It is **RECOMMENDED** that Issuers use the Nonce Endpoint (Section 7). A Wallet can continue using a given nonce until the Issuer rejects it; the Issuer determines the nonce's lifetime.

> **Note:** For an attacker to actually *present* a Credential bound to a replayed proof, they also need the victim's private key. Issuers are **RECOMMENDED** to assess how the Wallet protects private keys (using mechanisms in Appendix D).

> **Note on clock skew:** The Issuer **MAY** accept proofs with an `iat` time in the reasonably near future (seconds or minutes) to accommodate clock offsets. Alternatively, server-generated nonces containing the server's time can sidestep clock-skew issues entirely.

## 13.9 TLS

Implementations **MUST** follow BCP195 (current TLS best practices). Whenever TLS is used, a TLS server certificate check **MUST** be performed as specified in RFC6125.

## 13.10 Protecting Access Tokens

Access Tokens represent End-User authorization and consent to issue specific Credential(s). Long-lived Access Tokens (generally those with lifetimes exceeding 5 minutes) that give access to Credentials **MUST NOT** be issued unless they are **sender-constrained** (see Section 13.2 for DPoP recommendations).

If the Wallet stores Bearer Access Tokens, they **MUST** be stored in a secure manner — for example, encrypted using a key stored in a protected key store (e.g., Android Keystore, iOS Secure Enclave).

## 13.11 Application-Layer Encryption

Adding encryption beyond TLS can enhance data confidentiality, particularly when the Wallet or Issuer consists of multiple components with varying trust levels (e.g., a backend server and a client application). However, it adds complexity.

Key considerations:
- The Wallet component performing encryption **must establish trust** in the Issuer's key material — typically by retrieving keys directly from the Issuer's hosted metadata, or by verifying the signature on signed metadata.
- When application-layer encryption begins and terminates in the **same component** as TLS, it provides **no additional protection**.
- Application-layer encryption protects data confidentiality in transit but **does not** protect against Access Token theft, client impersonation, or other forms of unauthorized access. These require additional mitigations.

## 14. Implementation Considerations

This section provides practical guidance for implementers on topics that go beyond the normative protocol specification.

## 14.1 Claims-Based Binding

Credentials that are not cryptographically bound to the Holder (Section 8.1) should still be bound via the claims they contain. In this model, the Verifier confirms possession by requesting the presenter to show existing forms of identification (physical or digital) that contain the same claims — for example, a driving license or an online identity verification service. No cryptographic key material is involved.

## 14.2 Bearer Credentials

Some Credential Issuers may intentionally issue bearer Credentials with neither Cryptographic Key Binding nor Claims-based Holder Binding, because they are meant to be presented without proof of possession. Examples include low-assurance Credentials like coupons or tickets.

Another case is when the Credential Format itself provides binding without explicit Wallet-supplied key material. For example, with the **BBS Signature Scheme**, the issued Credential is itself a secret — only a derivation from the Credential is presented to the Verifier. The Credential is effectively bound to the Issuer's signature, which becomes a shared secret between the Issuer and the Holder.

## 14.3 Repeated Credential Requests

The Credential Endpoint can be accessed multiple times with the same Access Token, even for the same Credential type. The Issuer determines whether subsequent successful requests return the same Credential or an updated one (e.g., with a new expiration time or refreshed claims).

The Issuer **MAY** stop accepting the Access Token at its discretion, requiring the Wallet to re-authenticate or use a Refresh Token. However, the Issuer **SHOULD NOT** revoke previously issued, valid Credentials solely because a subsequent request succeeded — this ensures the Wallet can maintain a desired number of Credentials without causing unnecessary revocation and reissuance overhead.

Repeated requests can also be triggered by background processes or out-of-band Issuer signals (SMS, email, etc.).

## 14.4 Issuer Identifier Binding

The Credential Issuer Identifier in the metadata is always an HTTPS URL (Section 12.2.1). However, the Issuer Identifier within the issued Credential itself may use a different form — such as a DID in a W3C VC `issuer` property, or a certificate Subject in an ISO mdoc `x5chain` element.

When the Credential's Issuer Identifier is a DID, possible binding mechanisms include:
- Using the **Well-Known DID** specification to link a DID to a specific domain.
- Adding a `credential_issuer` claim to the Credential's issuer object.

The Wallet **MAY** check the binding between the Credential Issuer Identifier and the Issuer Identifier in the issued Credential.

## 14.5 Refreshing Credentials

After a Credential has been issued, its claim values or signature may need updating. There are two mechanisms:

1. **Without user interaction**: The Wallet uses a valid Access Token (or obtains a fresh one via Refresh Token) to request an updated Credential from the Credential Endpoint. This is transparent to the End-User.
2. **With user interaction**: The Issuer restarts the full issuance process. This is needed when the Wallet has no valid Access Token or Refresh Token. The Wallet may need to check for and replace an existing Credential of the same type to avoid duplicates.

Credential refresh can be initiated by the Wallet independently or triggered by an Issuer signal. How the Issuer sends such a signal is out of scope. It is up to the Issuer whether to update both the signature and claim values, or only the signature.

## 14.6 Batch Size

The Credential Issuer determines the number of Credentials returned in a response, regardless of how many proof keys the Wallet provided in the `proofs` parameter. The Wallet should not assume it will receive exactly as many Credentials as proofs submitted.

## 14.7 Pre-Final Dependencies

Implementers should be aware that this specification references several specifications that are not yet finalized:

| Dependency | Version |
| --- | --- |
| OpenID Federation | draft-43 |
| SD-JWT-based Verifiable Credentials (SD-JWT VC) | draft-11 |
| Attestation-Based Client Authentication | draft-07 |
| Token Status List | draft-12 |

While breaking changes to these dependencies are not expected, if they occur, OpenID4VCI implementations should continue using the specifically referenced versions above unless a profile or new version of this specification directs otherwise.

## 15. Privacy Considerations

When `authorization_details` (RFC9396) is used, the privacy considerations of that specification also apply. The privacy principles of ISO 29100 should be adhered to throughout the issuance flow.

## 15.1 Consent

The Credential Issuer **SHOULD** obtain the End-User's consent before issuing Credential(s) to the Wallet. It **SHOULD** be made clear to the End-User what information is being included in the Credential(s) and for what purpose.

## 15.2 Minimum Disclosure

To prevent Verifiers from obtaining claims unnecessary for the transaction at hand, when issuing Credentials intended to be used multiple times, Credential Issuers and Wallets **SHOULD** implement Credential Formats that support **selective disclosure** (where the Holder can choose which claims to reveal), or consider issuing a **separate Credential for each claim**.

## 15.3 Storage

To prevent leaks of End-User data — especially signed data which risks revealing private information to third parties — systems implementing this specification **SHOULD** minimize the amount of End-User data stored, including in log files. Any logging of End-User data should be carefully evaluated for necessity, and retention periods should be minimized.

- **Credential Issuers** **SHOULD NOT** store the Issuer-signed Credentials after issuance if they contain privacy-sensitive data.
- **Wallets** **SHOULD** store Credentials only in encrypted form, and wherever possible use **hardware-backed encryption** (e.g., Android Keystore, iOS Secure Enclave). Wallets **SHOULD NOT** store Credentials longer than needed.

## 15.4 Correlation

Issuance and presentation sessions can be linked based on unique values encoded in the Credential — End-User claims, identifiers, Issuer signatures, or binding keys — either by colluding Issuer/Verifier pairs, Verifier/Verifier pairs, or the same Verifier across sessions.

**Mitigations:**
- **Batch issuance**: Issue multiple Credentials with the same Dataset to enable using a unique Credential per presentation or per Verifier. Note: this only achieves Verifier-to-Verifier unlinkability.
- **Non-correlating cryptography**: Use cryptographic schemes that provide inherent non-correlation.
- **Randomized timestamps**: Claims containing time-related information (issuance/expiration dates) **SHOULD** be individually randomized within an appropriate window (e.g., within the last 24 hours) or rounded (e.g., to the start of the day).
- **Discard tracking values**: Issuers **SHOULD** specifically discard values usable for collusion with a Verifier, such as the Issuer's signature or the cryptographic key material used for binding.

**Additional correlation risks:**
- RFC9101 privacy considerations apply to the `credential_offer` and `credential_offer_uri` parameters (Section 4.1).
- Wallets **SHOULD NOT** include potentially sensitive information in the Authorization Request (e.g., clear-text session data in `state` or encoded in `redirect_uri`), as third parties may observe it through browser history.
- The Wallet Attestation `sub` claim **SHOULD NOT** be a unique identifier for a single client. It **SHOULD** identify a Wallet type shared by all instances of that Wallet implementation.

## 15.5 Identifying the Issuer

Information in the Credential identifying a particular Issuer (such as an Issuer Identifier, certificate, or public key) may inadvertently reveal sensitive information about the End-User.

For example:
- When a **military organization** or a **drug rehabilitation center** issues a vaccine credential, Verifiers can deduce the Holder's affiliation.
- When an Issuer issues only one type of Credential (e.g., the National Cancer Institute issuing only cancer registry Credentials), the Issuer's identity alone reveals the Credential's nature.

**Mitigation:** A group of organizations may elect to use a **common Credential Issuer** so that Credentials cannot be attributed to a particular organization through the Issuer's identifiers alone. A group signature scheme may also be used. When a common Issuer is used, appropriate guardrails must prevent one organization from issuing illegitimate Credentials on behalf of others.

## 15.6 Identifying the Wallet

There is a risk of leaking information about the Wallet to third parties when it reacts to a Credential Offer. An attacker may send Credential Offers using different custom URL schemes or claimed HTTPS URLs, observe whether the Wallet reacts (e.g., whether it retrieves Credential Issuer metadata from the attacker's server), and thereby learn which Wallet is installed.

**Mitigation:** The Wallet **SHOULD** require user interaction or establish trust in the Issuer before fetching `credential_offer_uri` content or acting on any Offer.

## 15.7 Untrusted Wallets

Because Wallets handle sensitive End-User data (Credentials, private keys, personal claims), Credential Issuers **SHOULD** authenticate Wallets and verify their compliance with applicable trust frameworks or regulations. The mechanisms described in Section 13.3 (Key Attestation, Client Authentication, and Wallet Attestation) can be used for this purpose.

---

## Appendix A. Credential Format Profiles

OpenID4VCI is deliberately format-agnostic. Rather than hard-coding support for one Credential format, it defines **Credential Format Profiles** — sets of format-specific parameters that plug into well-defined extension points in the Issuer Metadata, Credential Offer, Authorization Details, Credential Request, and Credential Response. Each profile is identified by a **Credential Format Identifier**.

This appendix defines profiles for the most commonly used formats. Other specifications or deployments **MAY** define their own profiles. It is **RECOMMENDED** that new profiles use the media type of the Credential Format as the Identifier (e.g., `dc+sd-jwt` is the media type for SD-JWT VC).

| Credential family | `format` | Main type field | Credential returned as |
|---|---|---|---|
| W3C VC secured as JWT | `jwt_vc_json` | `credential_definition.type` | JWT string |
| W3C VC with Data Integrity | `ldp_vc` | `credential_definition.@context` and `type` | JSON object |
| JSON-LD W3C VC secured as JWT | `jwt_vc_json-ld` | `credential_definition.@context` and `type` | JWT string |
| ISO mdoc | `mso_mdoc` | `doctype` | Base64url-encoded `IssuerSigned` CBOR |
| IETF SD-JWT VC | `dc+sd-jwt` | `vct` | SD-JWT VC string |

### A.1 W3C Verifiable Credentials

W3C Verifiable Credentials may or may not use JSON-LD, and when they do, implementations may process the `@context` property differently. This specification therefore defines **three separate profiles** to handle these variations precisely:

1. `jwt_vc_json` — VC secured as a JWT, **without** JSON-LD
2. `jwt_vc_json-ld` — VC secured as a JWT, **with** JSON-LD
3. `ldp_vc` — VC secured using Data Integrity proofs, **with** JSON-LD (requiring Linked Data canonicalization)

> **Note:** Data Integrity was formerly called "Linked Data Proofs" — this is why `ldp_vc` starts with "ldp".

For all three profiles, the Credential Offer, Authorization Details, Credential Request, and Issuer Metadata containers **MUST NOT** be processed using JSON-LD rules — only the Credential payload itself uses the format's rules.

#### A.1.1 JWT VC JSON (`jwt_vc_json`)

This profile carries a W3C VC in a JWT without using JSON-LD at all. The required `credential_definition.type` array identifies the W3C Credential type(s). Algorithm identifiers in `credential_signing_alg_values_supported` are case-sensitive strings and **SHOULD** be JWS Algorithm Names from the IANA JOSE registry.

```json
{
  "UniversityDegreeCredential": {
    "format": "jwt_vc_json",
    "scope": "UniversityDegreeCredential",
    "cryptographic_binding_methods_supported": ["did:example"],
    "credential_signing_alg_values_supported": ["ES256"],
    "credential_definition": {
      "type": ["VerifiableCredential", "UniversityDegreeCredential"]
    },
    "proof_types_supported": {
      "jwt": {
        "proof_signing_alg_values_supported": ["ES256"]
      }
    }
  }
}
```

In authorization details, the Wallet references the Configuration by its identifier — the format-specific fields do not need to be repeated:

```json
[
  {
    "type": "openid_credential",
    "credential_configuration_id": "UniversityDegreeCredential"
  }
]
```

The `credential` field in the Credential Response **MUST** be the compact JWT string. Credentials of this format are already base64url-encoded and **MUST NOT** be re-encoded (doing so could alter the signed representation):

```json
{
  "credentials": [
    {
      "credential": "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9..."
    }
  ]
}
```

#### A.1.2 Data Integrity VC (`ldp_vc`)

For a W3C VC secured using Data Integrity proofs with JSON-LD, Issuer Metadata requires **both** `@context` and `type` in `credential_definition`. The `@context` array enables the Wallet to check compatibility before requesting — if the Wallet does not support those contexts, it knows it cannot process this Credential. The Wallet may apply JSON-LD processing to the received Credential if needed.

Algorithm identifiers in `credential_signing_alg_values_supported` **SHOULD** be signature suite identifiers from the Linked Data Cryptographic Suite Registry.

```json
{
  "UniversityDegree_LDP_VC": {
    "format": "ldp_vc",
    "cryptographic_binding_methods_supported": ["did:example"],
    "credential_signing_alg_values_supported": ["Ed25519Signature2018"],
    "credential_definition": {
      "@context": [
        "https://www.w3.org/2018/credentials/v1",
        "https://www.w3.org/2018/credentials/examples/v1"
      ],
      "type": ["VerifiableCredential", "UniversityDegreeCredential"]
    }
  }
}
```

The Offer, Authorization Details, Credential Request, and Issuer Metadata containers **MUST NOT** be processed as JSON-LD — only the actual Credential payload uses the format's rules. The `credential` in the response is a **JSON object** (not a string) and **MUST NOT** be re-encoded in any way that would invalidate its proof:

```json
{
  "credentials": [
    {
      "credential": {
        "@context": ["https://www.w3.org/2018/credentials/v1"],
        "type": ["VerifiableCredential", "UniversityDegreeCredential"],
        "issuer": "https://example.edu/issuers/565049",
        "issuanceDate": "2010-01-01T00:00:00Z",
        "credentialSubject": {
          "id": "did:example:ebfeb1f712ebc6f1c276e12ec21",
          "degree": { "type": "BachelorDegree", "name": "Bachelor of Science and Arts" }
        },
        "proof": {
          "type": "Ed25519Signature2020",
          "created": "2022-02-25T14:58:43Z",
          "verificationMethod": "https://example.edu/issuers/565049#key-1",
          "proofPurpose": "assertionMethod",
          "proofValue": "zeEdUo..."
        }
      }
    }
  ]
}
```

#### A.1.3 JSON-LD JWT VC (`jwt_vc_json-ld`)

This profile combines the JSON-LD Credential definition (same as `ldp_vc`) with JWT-based signing (same response format as `jwt_vc_json`). It handles the case where a Credential uses JSON-LD contexts but is signed as a JWT rather than with a Data Integrity proof.

- **Issuer Metadata**: Follows the same rules as `ldp_vc` (Appendix A.1.2) — requires both `credential_definition.@context` and `credential_definition.type`. Algorithm identifiers follow the Linked Data Cryptographic Suite Registry.
- **Authorization Details**: Same structure as `ldp_vc` (Appendix A.1.2).
- **Credential Response**: The `credential` field is a **JWT string**, same as `jwt_vc_json` (Appendix A.1.1). It **MUST NOT** be re-encoded.

### A.2 ISO mdoc (`mso_mdoc`)

This profile covers Credentials conforming to ISO/IEC 18013-5 — the **Mobile Document (mdoc)** format, originally designed for mobile driving licences (mDLs) but applicable to any document type. The format identifier `mso_mdoc` refers to the Mobile Security Object (MSO), which cryptographically secures the mdoc data encoded as CBOR.

The required `doctype` field identifies the document type (e.g., `org.iso.18013.5.1.mDL`).

**Algorithm identifier note:** `credential_signing_alg_values_supported` contains COSE algorithm identifiers (typically numeric values). These can be either:
- The exact `alg` value from the IssuerAuth COSE header (e.g., `-7` for ECDSA with SHA-256), or
- A "fully specified" algorithm combining key type and hash (e.g., `-9` for ECDSA with P-256 and SHA-256)

Because of this, the `alg` value in the actual IssuerAuth COSE structure **MAY** differ from the listed metadata value — the metadata is primarily informational for the Wallet.

```json
{
  "org.iso.18013.5.1.mDL": {
    "format": "mso_mdoc",
    "doctype": "org.iso.18013.5.1.mDL",
    "cryptographic_binding_methods_supported": ["cose_key"],
    "credential_signing_alg_values_supported": [-7, -9],
    "proof_types_supported": {
      "jwt": {
        "proof_signing_alg_values_supported": ["ES256"]
      }
    }
  }
}
```

In authorization details, the Wallet identifies the Configuration the same format-independent way as other profiles:

```json
[
  {
    "type": "openid_credential",
    "credential_configuration_id": "org.iso.18013.5.1.mDL"
  }
]
```

The `credential` value in the response **MUST** be the **base64url-encoded** representation of the CBOR-encoded `IssuerSigned` structure (as defined in ISO 18013-5). The Wallet decodes it as CBOR, not as a JWT:

```json
{
  "credentials": [
    {
      "credential": "omppc3N1ZXJBdXRohEOhASahG...ArQwggKwMIICVqADAgEC"
    }
  ]
}
```

### A.3 IETF SD-JWT VC (`dc+sd-jwt`)

This profile covers Credentials complying with the IETF SD-JWT VC specification. SD-JWT VC supports **selective disclosure** — the Holder can reveal only a subset of claims when presenting to a Verifier, without the Issuer's involvement.

The required `vct` field is a string that identifies the Verifiable Credential type, as defined in the SD-JWT VC spec. Algorithm identifiers in `credential_signing_alg_values_supported` are case-sensitive JWS Algorithm Names from the IANA JOSE registry.

A `credential_metadata` object may provide fallback display and claim information. If the SD-JWT VC type metadata (fetched separately via the `vct` URI) provides display data, it takes precedence over `credential_metadata`.

```json
{
  "IdentityCredential": {
    "format": "dc+sd-jwt",
    "scope": "IdentityCredential",
    "vct": "https://credentials.example.com/identity_credential",
    "cryptographic_binding_methods_supported": ["jwk"],
    "credential_signing_alg_values_supported": ["ES256"],
    "proof_types_supported": {
      "jwt": {
        "proof_signing_alg_values_supported": ["ES256"]
      }
    },
    "credential_metadata": {
      "display": [
        {
          "name": "Identity Credential",
          "locale": "en-US"
        }
      ],
      "claims": [
        {"path": ["given_name"]},
        {"path": ["family_name"]},
        {"path": ["address", "country"]}
      ]
    }
  }
}
```

The issued `credential` in the response **MUST** be a string containing the SD-JWT VC in its compact serialization (JWS header + payload + signature, with optional `~`-separated disclosures appended). The Wallet **MUST NOT** re-encode it — the disclosures and separators are an integral part of the format:

```json
{
  "credentials": [
    {
      "credential": "eyJhbGciOiJFUzI1NiIsInR5cCI6ImRjK3NkLWp3dCJ9...~WyJzYWx0IiwiZ2l2ZW5fbmFtZSIsIkFydGh1ciJd~"
    }
  ]
}
```

The `~`-separated segments after the main JWT are the selective disclosure values. When the Holder presents this Credential, they can selectively include only the disclosures relevant to that presentation.

## Appendix B. Claims Description

Claims description objects are used in two places in this specification:
1. In **Authorization Details** — to tell the Issuer which specific claims the Wallet wants included in the Credential.
2. In **Issuer Metadata** — to describe the claims a Credential Configuration may contain and how to display them to the End-User.

A claims description object does **not** contain a claim value; it contains a *path pointer* to where a value would be found in the Credential structure.

### B.1 Claims in Authorization Details

A claims description object in authorization details defines the requirements for claims the Wallet wants in the Credential.

The following fields are defined (additional fields **MAY** be used):

- `path` (**REQUIRED**): A Claims Path Pointer (Appendix C) identifying the claim(s) in the Credential.
- `mandatory` (OPTIONAL, default: `false`): When `true`, the **Wallet** will only accept a Credential that includes this claim. When `false`, the Wallet will accept the Credential even if the claim is absent. This is the Wallet's constraint on what it considers acceptable.

```json
{
  "type": "openid_credential",
  "credential_configuration_id": "IdentityCredential",
  "claims": [
    {
      "path": ["given_name"],
      "mandatory": true
    },
    {
      "path": ["address", "country"],
      "mandatory": false
    }
  ]
}
```

### B.2 Claims in Issuer Metadata

A claims description object in Issuer Metadata describes how a claim is displayed to the End-User and whether the Issuer always includes it.

The following fields are defined:

- `path` (**REQUIRED**): A Claims Path Pointer (Appendix C) identifying the claim(s) in the Credential.
- `mandatory` (OPTIONAL, default: `false`): When `true`, the **Issuer** will always include this claim in the issued Credential, regardless of whether the Wallet requested it. When `false`, the Issuer will only include the claim if the Wallet requested it or the Issuer chose to. This is the Issuer's declaration about what it always provides.
- `display` (OPTIONAL): A non-empty array of localized display objects, each with:
  - `name` (OPTIONAL): Human-readable label for the claim.
  - `locale` (OPTIONAL): BCP47 language tag. There **MUST** be only one object per locale.

> **Important:** The `mandatory` field means different things in each context:
> - In **Authorization Details**: "The Wallet requires this claim"
> - In **Issuer Metadata**: "The Issuer will always include this claim"

```json
{
  "path": ["family_name"],
  "display": [
    {"name": "Surname", "locale": "en-US"},
    {"name": "Nachname", "locale": "de-DE"}
  ]
}
```

The order of entries in the `claims` array is also the recommended display order for the End-User.

### B.3 Invalid or Contradictory Descriptions

Processing **MUST** be aborted when claims descriptions repeat or contradict each other. Specifically, abort if:

- The same claim is addressed by two or more objects in the `claims` array (duplicate path).
- One object uses `null` in the path to select all elements of an array, and another object uses a non-negative integer to select a specific element of the same array — these conflict because one selects all while the other selects one.
- One object's path implies a claim is an array (by using `null` or a non-negative integer), and another object's path implies the same claim is an object (by using a string at that level).

For example, these two paths conflict because the first selects **all** nationality items while the second selects only item at index 0:

```json
[
  {"path": ["nationality", null]},
  {"path": ["nationality", 0]}
]
```

## Appendix C. Claims Path Pointer

A Claims Path Pointer is a mechanism for identifying one or more specific claims within a Verifiable Credential. It is represented as a non-empty JSON array evaluated from left to right against the Credential's data structure. Every element of the array is one of:

- A **string** — selects a member of the current object by key (claim name)
- A **non-negative integer** — selects an element of the current array by zero-based index
- **`null`** — selects **all** elements of the current array

If at any step: a component has the wrong type for the current node, an index is negative, an index is out of range, a member key does not exist in the current object, or the final selected set is empty — evaluation **MUST** be aborted and an error returned. Negative integers are **never valid** for JSON-based credentials and **MUST** also abort evaluation.

**Example credential:**

```json
{
  "given_name": "Arthur",
  "family_name": "Dent",
  "address": {
    "country": "GB"
  },
  "nationalities": ["GB", "Betelgeuse"]
}
```

| Path | Selected value |
|---|---|
| `["given_name"]` | `"Arthur"` |
| `["address", "country"]` | `"GB"` |
| `["nationalities", 0]` | `"GB"` (first element) |
| `["nationalities", null]` | both `"GB"` and `"Betelgeuse"` |
| `["address"]` | the entire address object |

**ISO mdoc paths** always begin with exactly two string components: the **namespace** (first) and the **data element identifier** (second). Subsequent components traverse nested maps or arrays within that data element. An integer is interpreted as a map key when the current selected element is a map, and as an array index when it is an array. `null` selects all array entries. If fewer than two components are provided, evaluation **MUST** abort.

## Appendix D. Key Attestations

A Key Attestation is a verifiable statement that demonstrates the authenticity and security properties of one or more cryptographic keys and the component that stores them. It answers the question: *"How well is this private key protected?"*

Key storage components vary in their ability to protect private keys from extraction and duplication, and in the user authentication methods required to use them. These components can be software-based or hardware-based, on-device, on external security tokens, or in remote key management services.

Key Attestations are issued either by the Wallet's key storage component itself (using platform mechanisms like iOS DeviceCheck or Android Play Integrity) or by the Wallet Provider after verifying those platform attestations. The Wallet Provider **MUST** validate the authenticity of platform attestations before creating a Key Attestation.

A Key Attestation **supplements** (not replaces) proof of possession: the proof-of-possession demonstrates *control* of the private key; the Key Attestation describes *how that key is protected*.

There are **two ways** to convey Key Attestations during Credential issuance:
1. **Embedded in the JWT proof**: The Wallet uses the `jwt` proof type and includes the Key Attestation in the `key_attestation` JOSE header parameter. The JWT proof itself is signed by one of the attested keys, providing both attestation and proof of possession in one step.
2. **As the `attestation` proof type**: The Wallet uses the `attestation` proof type directly — providing a Key Attestation without a separate proof of possession of any particular key. This can reduce End-User interaction since the keys being attested do not need to perform signature operations.

Credential Issuers communicate their Key Attestation requirements through the `key_attestations_required` metadata parameter or via out-of-band mechanisms.

```mermaid
sequenceDiagram
    participant Platform as Secure Platform
    participant Wallet
    participant AP as Attestation Provider
    participant Issuer as Credential Issuer

    Wallet->>Platform: Generate non-exportable key
    Platform-->>Wallet: Public key + platform attestation
    Wallet->>AP: Request common Key Attestation
    AP->>AP: Verify platform evidence and policy
    AP-->>Wallet: Signed key-attestation+jwt
    Wallet->>Issuer: Credential Request + proof + Key Attestation
    Issuer->>Issuer: Trust signer, validate status and requirements
    Issuer-->>Wallet: Credential bound to an attested key
```

### D.1 Key Attestation JWT

The compact JWS explicitly uses media type `key-attestation+jwt`.

JOSE header requirements:

- `alg`: **REQUIRED** asymmetric signature algorithm; `none` and MAC algorithms are forbidden.
- `typ`: **REQUIRED**, with value `key-attestation+jwt`.
- The verification key may be conveyed or selected through mechanisms such as `x5c`, `kid`, or `trust_chain`.

Payload claims:

| Claim | Requirement | Meaning |
|---|---|---|
| `iat` | Required | Time the attestation was issued |
| `exp` | Optional generally; required when embedded in a JWT proof | Expiration time |
| `attested_keys` | Required, non-empty | Public keys being attested |
| `key_storage` | Optional | Resistance level of private-key storage |
| `user_authentication` | Optional | Resistance level of user authentication protecting key use |
| `certification` | Optional | Certification information |
| `nonce` | Optional, or required by the selected flow | Fresh challenge supplied by the Issuer |
| `status` | Optional | Status mechanism for the attestation |

```text
{
  "typ": "key-attestation+jwt",
  "alg": "ES256",
  "x5c": ["MIIC...attestation-provider-certificate..."]
}
.
{
  "iat": 1735689600,
  "exp": 1735690200,
  "nonce": "wKI4LT17ac15ES9bw8ac4",
  "attested_keys": [
    {
      "kty": "EC",
      "crv": "P-256",
      "x": "...",
      "y": "..."
    }
  ],
  "key_storage": ["iso_18045_moderate"],
  "user_authentication": ["iso_18045_moderate"]
}
```

When a Key Attestation is carried inside a JWT proof, that JWT proof **MUST** be signed by one of the keys in `attested_keys`. The Issuer verifies both signatures and the relationship between them.

### D.2 Attack Potential Resistance Levels

The `key_storage` and `user_authentication` arrays use standardized string values to communicate the security level of the key storage component or authentication mechanism. These map to **ISO/IEC 18045** attack potential levels (VAN = Vulnerability Analysis):

| Value | ISO 18045 Level | Meaning |
|---|---|---|
| `iso_18045_high` | VAN.5 (High) | Resistant to attackers with high attack potential — specialist expertise, significant resources |
| `iso_18045_moderate` | VAN.4 (Moderate) | Resistant to attackers with moderate attack potential — proficient expertise, moderate resources |
| `iso_18045_enhanced-basic` | VAN.3 (Enhanced-Basic) | Resistant to attackers with enhanced-basic attack potential |
| `iso_18045_basic` | VAN.2 (Basic) | Resistant to attackers with basic attack potential |

Extensions to this list **MUST** choose collision-resistant values to avoid conflicts with future standardized values.

When ISO 18045 is not used (e.g., in ecosystem-specific trust frameworks), ecosystems **MAY** define their own values. If a value does not map to a well-known specification, it is **RECOMMENDED** that the value be a URL pointing to further information about the attack potential resistance model and its relationship to common assurance levels.

## Appendix E. Wallet Attestations

### E.1 Background and Purpose

Native Wallet applications (on iOS, Android, etc.) cannot securely store conventional client secrets or mutual TLS certificates the same way a server-side Confidential Client can. A secret stored in app storage can be extracted by a rooted device, or replicated if the app is cloned.

The **Wallet Attestation** solves this by having the **Wallet Provider** (who controls the published app) issue a signed statement asserting the authenticity and integrity of a specific Wallet instance. This statement is rooted in **platform attestations** (e.g., iOS App Attest, Android Play Integrity API) that the mobile OS provides and that cannot be forged.

The Authorization Server verifies the Wallet Attestation against the Wallet Provider's trust anchor, confirming:
- This is a genuine, unmodified instance of a legitimate Wallet application.
- The Wallet was built by the claimed Wallet Provider.
- The Wallet has not been tampered with (e.g., no sideloading, no hooking).

This mechanism allows Authorization Servers to authenticate Wallets across different mobile platforms in a unified, platform-agnostic fashion, and exposes only the minimum dataset needed. It also allows the Wallet app to interact directly with the Credential Issuer without involving the Wallet Provider's backend at runtime.

The Authorization Server **MUST** establish trust in the Wallet Attestation issuer (the Wallet Provider) and validate the attestation before accepting it as proof of Wallet authenticity.

```mermaid
sequenceDiagram
    participant Wallet
    participant WP as Wallet Provider
    participant AS as Authorization Server

    Wallet->>WP: Request Wallet Attestation (using platform attestation)
    WP->>WP: Verify platform attestation and app integrity
    WP-->>Wallet: Signed Client Attestation JWT
    Wallet->>Wallet: Create fresh Attestation PoP JWT
    Wallet->>AS: PAR or Token Request
    Note over Wallet,AS: OAuth-Client-Attestation + OAuth-Client-Attestation-PoP headers
    AS->>AS: Validate provider trust, claims, status, PoP signature
    AS-->>Wallet: OAuth response
```

Example request using Wallet Attestation headers:

```http
POST /par HTTP/1.1
Host: authorization-server.example.com
Content-Type: application/x-www-form-urlencoded
OAuth-Client-Attestation: eyJhbGciOiJFUzI1NiIsInR5cCI6Im9hdXRoLWNsaWVudC1hdHRlc3RhdGlvbitqd3QifQ...
OAuth-Client-Attestation-PoP: eyJhbGciOiJFUzI1NiIsInR5cCI6Im9hdXRoLWNsaWVudC1hdHRlc3RhdGlvbi1wb3Arand0In0...

response_type=code
&client_id=https%3A%2F%2Fwallet.example.org
&request_uri=urn%3Aietf%3Aparams%3Aoauth%3Arequest_uri%3Aabc123
```

### E.2 Wallet Attestation Format

The Wallet Attestation follows the "Client Attestation JWT" format defined in the Attestation-Based Client Authentication specification. OpenID4VCI adds the following optional JWT claims:

- `wallet_name` (OPTIONAL): A human-readable name for the Wallet implementation.
- `wallet_link` (OPTIONAL): A URL where further information about the Wallet and its provider can be found.
- `status` (OPTIONAL): A status mechanism for the Wallet Attestation (e.g., using a Token Status List to check revocation at runtime).

The Wallet Attestation can authenticate the Wallet at two points during Credential issuance:
1. In the **Pushed Authorization Request (PAR)** — before the End-User authenticates.
2. In the **Token Request** — when exchanging the Authorization Code for an Access Token.

To use the Wallet Attestation, the Wallet **MUST** also generate a **Client Attestation PoP JWT** (Proof of Possession) — a short-lived JWT signed by the key bound in the Wallet Attestation's `cnf` claim. This proves that the entity presenting the attestation controls the corresponding private key, preventing simple attestation theft and replay.

For privacy, the `sub` claim of the Wallet Attestation is the OAuth `client_id`, but it **SHOULD** be shared by all instances of the same Wallet implementation — it identifies a Wallet *type*, not a specific user's installation. See Section 15.4 for the privacy implications.

## Appendix F. Proof Types

The `proofs` object in a Credential Request is the extension point for key binding. A proof demonstrates that the Wallet controls the private key corresponding to the public key it wants the Issuer to bind into the Credential. This specification defines three proof types:

| Proof type | Value in `proofs` | Purpose |
|---|---|---|
| `jwt` | Non-empty array of proof JWT strings | Proof of possession using JOSE — the most common type |
| `di_vp` | Non-empty array of Data Integrity VP objects | Proof of possession using a W3C Verifiable Presentation |
| `attestation` | Array containing exactly one Key Attestation JWT | Attested key material *without* a separate proof of possession |

Only one proof-type member **MAY** appear inside `proofs` for a given request. Multiple proofs within one type (e.g., multiple JWTs) are used to request a batch of Credentials bound to different keys.

### F.1 JWT Proof

The JWT proof JOSE header contains:

- `typ`: **REQUIRED**, exactly `openid4vci-proof+jwt`.
- `alg`: **REQUIRED** asymmetric algorithm accepted for this Credential Configuration.
- exactly one applicable key-reference method such as `kid`, `jwk`, or `x5c`; these three are mutually exclusive.
- optionally `key_attestation` and/or `trust_chain`. If a `trust_chain` supplies the signature-validation key, `kid` is required to select that key.

The proof payload contains:

- `iss`: optional Client Identifier; omitted for an anonymous Pre-Authorized Code flow.
- `aud`: **REQUIRED**, equal to the Credential Issuer Identifier.
- `iat`: **REQUIRED** issuance time.
- `nonce`: **REQUIRED** when the Issuer advertises a Nonce Endpoint, and equal to the retrieved `c_nonce`.

Decoded example:

```text
{
  "typ": "openid4vci-proof+jwt",
  "alg": "ES256",
  "jwk": {
    "kty": "EC",
    "crv": "P-256",
    "x": "...",
    "y": "..."
  }
}
.
{
  "iss": "https://wallet.example.org",
  "aud": "https://credential-issuer.example.com",
  "iat": 1735689600,
  "nonce": "wKI4LT17ac15ES9bw8ac4"
}
```

Credential Request:

```http
POST /credential HTTP/1.1
Host: credential-issuer.example.com
Authorization: Bearer eyJhbGciOiJSUzI1NiJ9...
Content-Type: application/json

{
  "credential_configuration_id": "IdentityCredential",
  "proofs": {
    "jwt": [
      "eyJ0eXAiOiJvcGVuaWQ0dmNpLXByb29mK2p3dCIsImFsZyI6IkVTMjU2IiwiandrIjp7Li4ufX0.eyJhdWQiOiJodHRwczovL2NyZWRlbnRpYWwtaXNzdWVyLmV4YW1wbGUuY29tIiwiaWF0IjoxNzM1Njg5NjAwLCJub25jZSI6IndLSTRMVDE3YWMxNUVWOWJ3OGFjNCJ9.signature"
    ]
  }
}
```

The Issuer:
- Verifies the signature using the public key identified by `kid`, `jwk`, or `x5c` (exactly one **MUST** be present).
- Checks the signature algorithm against `proof_signing_alg_values_supported` in Issuer Metadata.
- Validates `aud` equals its Credential Issuer Identifier.
- Validates `nonce` when a Nonce Endpoint is advertised.
- If a `key_attestation` header is present and the Issuer accepts it, the JWT **MUST** be signed by one of the keys in `attested_keys`. The Issuer **SHOULD** issue at most one Credential per accepted attested key.

### F.2 Data Integrity VP Proof (`di_vp`)

The Wallet can prove control of a key using a Verifiable Presentation containing a Data Integrity proof.

```json
{
  "credential_identifier": "CivilEngineeringDegree-2023",
  "proofs": {
    "di_vp": [
      {
        "@context": ["https://www.w3.org/ns/credentials/v2"],
        "type": ["VerifiablePresentation"],
        "holder": "did:key:z6MkExample",
        "proof": [
          {
            "type": "DataIntegrityProof",
            "cryptosuite": "eddsa-2022",
            "proofPurpose": "authentication",
            "verificationMethod": "did:key:z6MkExample#z6MkExample",
            "challenge": "wKI4LT17ac15ES9bw8ac4",
            "domain": "https://credential-issuer.example.com",
            "proofValue": "z5hrb..."
          }
        ]
      }
    ]
  }
}
```

Validation rules include:

- `proof` is required and its cryptosuite must be supported by Issuer Metadata.
- `proofPurpose` is `authentication`.
- `domain` equals the Credential Issuer Identifier.
- `challenge` is present and equals `c_nonce` when a nonce is required.
- if `holder` is present, it matches the controller of `verificationMethod`.
- the Data Integrity proof verifies with the stated verification method.
- unrecognized VP properties are ignored unless another applicable specification says otherwise.

### F.3 Attestation Proof (`attestation`)

The `attestation` proof type carries exactly one Key Attestation JWT (Appendix D) and does **not** require a separate proof of possession of any of the attested keys. This is useful when the Wallet wants to avoid unnecessary key operations — for example, because the hardware-backed key does not need to sign anything at this step, or because one attestation covers multiple keys that will each bind a separate Credential.

If a Nonce Endpoint is advertised, the Key Attestation **MUST** contain the current `c_nonce` in its `nonce` claim. The attestation's signature algorithm must be permitted for this proof type.

The Issuer validates:
- The attestation signer's identity and trust status
- The `nonce` freshness (if applicable)
- The attestation's `exp` (required when used with a JWT proof type)
- The security characteristics of the attested keys against its requirements
- Returns at most one Credential per accepted attested key

Example:

```json
{
  "credential_configuration_id": "IdentityCredential",
  "proofs": {
    "attestation": [
      "eyJ0eXAiOiJrZXktYXR0ZXN0YXRpb24rand0IiwiYWxnIjoiRVMyNTYifQ..."
    ]
  }
}
```

### F.4 Common Proof-Verification Checklist

Regardless of proof type, the Issuer **MUST**:

1. **Reject missing required fields and invalid types** — treat structural failures as `invalid_proof`.
2. **Require the explicit proof type identifier** — the `typ` header must match the proof type (e.g., `openid4vci-proof+jwt`).
3. **Reject weak algorithms** — `none`, symmetric MACs, and algorithms not listed in `proof_signing_alg_values_supported` for this Credential Configuration.
4. **Verify the cryptographic signature** — using the public key actually identified by the proof (via `kid`, `jwk`, `x5c`, or DID resolution).
5. **Reject JWKs containing private key material** — a proof that exposes a private key must be rejected.
6. **Verify the audience/domain** — `aud` (JWT) or `domain` (Data Integrity VP) must equal the Credential Issuer Identifier.
7. **Verify the current nonce** — when the Nonce Endpoint is used, the `nonce` claim must match the issued `c_nonce`.
8. **Enforce proof freshness** — using `iat`, nonce policy, or both to prevent replay.

## Appendix G. IANA Considerations

This appendix lists the identifiers that this specification registers with IANA. These registrations ensure that independent implementations can interoperate using the same protocol names.

### G.1 OAuth and Well-Known Registrations

| Registry | Registered name | Usage |
|---|---|---|
| OAuth URI (Grant Types) | `urn:ietf:params:oauth:grant-type:pre-authorized_code` | Identifies the Pre-Authorized Code Grant Type in Token Requests |
| OAuth Authorization Request Parameter | `issuer_state` | Carries the Issuer's opaque state value in the Authorization Request; enables correlation to a Credential Offer |
| OAuth Token Request Parameter | `pre-authorized_code` | The Pre-Authorized Code value issued in the Credential Offer |
| OAuth Token Request Parameter | `tx_code` | The Transaction Code entered by the End-User from a separate channel |
| Authorization Server Metadata | `pre-authorized_grant_anonymous_access_supported` | Boolean. When `true`, the AS accepts Pre-Authorized Code Token Requests without a `client_id` |
| OAuth Dynamic Client Registration Metadata | `credential_offer_endpoint` | The Wallet's Credential Offer Endpoint URL — where Issuers can deliver Offers directly to the Wallet |
| Well-Known URI Suffix | `openid-credential-issuer` | Inserted into the Credential Issuer Identifier to construct the metadata discovery URL |

### G.2 Media Types

Three new MIME types are registered for the structured tokens defined in this specification:

| Media type | Purpose |
|---|---|
| `application/openid4vci-proof+jwt` | JWT carrying a Cryptographic Key Binding proof in a Credential Request |
| `application/key-attestation+jwt` | JWT asserting the security properties of cryptographic keys (Appendix D) |
| `application/openidvci-issuer-metadata+jwt` | Signed Credential Issuer Metadata document (Section 12.2.3) |

The corresponding JWT `typ` header values omit the `application/` prefix per RFC8725: `openid4vci-proof+jwt`, `key-attestation+jwt`, and `openidvci-issuer-metadata+jwt`. Explicit `typ` values allow receivers to detect and reject type confusion attacks.

### G.3 URI Scheme

The permanent URI scheme `openid-credential-offer` is used to invoke a Wallet application with a Credential Offer when no Wallet-specific HTTPS Credential Offer Endpoint has been discovered. It is the universal fallback for custom URL scheme handling on mobile platforms:

```text
openid-credential-offer://?credential_offer_uri=https%3A%2F%2Fissuer.example.com%2Foffers%2F123
```

The operating system routes this URI to the installed Wallet application, which then dereferences the `credential_offer_uri` to retrieve the Offer object.

## Appendix H. Use Cases

These non-normative use cases illustrate how the building blocks of this specification combine in practice. They are informative examples only — they do not add protocol requirements.

### H.1 Same-Device Diploma Issuance (Authorization Code Flow)

**Scenario:** A university graduate wants to add their diploma to a Wallet app on the same phone where they browse the university portal. This is the canonical same-device Authorization Code flow.

1. The graduate visits the university portal and selects "Add diploma to Wallet".
2. The portal displays a link (or taps the OS) containing or referencing a Credential Offer.
3. The OS opens the Wallet via the Credential Offer Endpoint.
4. The Wallet fetches Credential Issuer and Authorization Server Metadata.
5. The Wallet starts the Authorization Code flow, including `issuer_state` from the Offer if provided.
6. After user authentication and consent, the AS issues an Authorization Code.
7. The Wallet exchanges the code (with PKCE verifier) for an Access Token, then requests the diploma.

```mermaid
sequenceDiagram
    actor User
    participant Site as University Site
    participant Wallet
    participant AS as Authorization Server
    participant Issuer

    User->>Site: Select "Add diploma to Wallet"
    Site-->>Wallet: Credential Offer + issuer_state
    Wallet->>Issuer: Fetch Issuer Metadata
    Wallet->>AS: Authorization Request (+ issuer_state, PKCE challenge)
    AS->>User: Authenticate and obtain consent
    AS-->>Wallet: Authorization Code
    Wallet->>AS: Token Request + PKCE verifier
    AS-->>Wallet: Access Token
    Wallet->>Issuer: Credential Request + JWT key proof
    Issuer-->>Wallet: Diploma Credential
```

### H.2 Cross-Device Employer Credential with Transaction Code (Pre-Authorized Code Flow)

**Scenario:** An employee is at their desktop computer while their Wallet is on their phone. The employer uses the Pre-Authorized Code flow for a frictionless experience. A Transaction Code via SMS prevents a bystander from scanning the QR code and using it.

1. The employer portal renders a QR code embedding a Pre-Authorized Code Offer.
2. The employer sends a short Transaction Code to the employee's phone number via SMS (separate channel).
3. The employee scans the QR code with their Wallet and enters the Transaction Code when prompted.
4. The Wallet sends both values to the Token Endpoint and receives an Access Token.
5. The Wallet requests the Employment Credential with a key proof.

```mermaid
sequenceDiagram
    actor User
    participant Desktop as Employer Desktop Page
    participant Wallet as Phone Wallet
    participant AS as Authorization Server
    participant Issuer as Employer Issuer

    Desktop-->>User: QR Offer with Pre-Authorized Code
    Issuer-->>User: Transaction Code via SMS
    User->>Wallet: Scan QR and enter Transaction Code
    Wallet->>AS: Token Request (pre-authorized_code + tx_code)
    AS-->>Wallet: Access Token
    Wallet->>Issuer: Credential Request + key proof
    Issuer-->>Wallet: Employment Credential
```

The Pre-Authorized Code is short-lived and single-use. The Transaction Code is delivered through a separate channel and **MUST NOT** be embedded in the same QR code.

### H.3 Cross-Device Deferred Issuance (Deferred Credential Endpoint)

**Scenario:** A government agency issues criminal record certificates, but issuance requires a manual background check that cannot complete immediately. The Wallet submits the request and polls for the result.

The Wallet follows the Credential Offer, completes authorization, and submits a Credential Request. Instead of a Credential, the Issuer returns HTTP `202 Accepted` with a `transaction_id` and a minimum polling `interval` (in seconds):

```json
{
  "transaction_id": "8xLOxBtZp8",
  "interval": 3600
}
```

The Wallet waits at least `interval` seconds, then polls the Deferred Credential Endpoint using the same Access Token. If still processing, the Issuer returns another `202` with a potentially updated interval. When ready, it returns `200` with the `credentials` array and the `transaction_id` is invalidated.

### H.4 Wallet-Initiated Issuance During Presentation

**Scenario:** A Verifier requests a Credential the Wallet does not yet have. Rather than failing, the Wallet helps the user obtain it on the spot.

The Wallet identifies a trusted Issuer that can provide the required Credential, discovers its Credential configurations using Issuer Metadata, and starts a standard Wallet-initiated Authorization Code flow. The issuance and presentation transactions are **completely separate** — after issuance completes, the Wallet returns to the original presentation request and uses the newly issued Credential.

### H.5 Issuance Using Another Credential for User Verification

**Scenario:** An Issuer wants to verify the applicant's identity before issuing a new Credential. Rather than using a username/password, it asks the Wallet to present an existing Credential (e.g., a government-issued ID).

During the Authorization step, the Issuer (via the AS) triggers an OpenID4VP presentation request. The Wallet completes the presentation separately, and its result becomes input to the Issuer's authorization decision. The new Credential issuance still follows all normal OpenID4VCI rules.

```mermaid
flowchart LR
    A["Wallet requests new Credential"] --> B["Issuer authorization"]
    B --> C["Issuer requests existing Credential via OpenID4VP"]
    C --> D["Wallet completes presentation"]
    D --> E["Issuer validates identity claims"]
    E --> F["Authorization Code + Access Token"]
    F --> G["OpenID4VCI Credential Request"]
```

### H.6 Issuance After Wallet Installation

**Scenario:** A user taps a Credential Offer link but has no compatible Wallet installed. The platform or app store helps install one, and issuance must resume safely afterward.

After installation, the original Offer URI must be transferred safely to the newly installed Wallet. The Wallet **MUST** treat the Offer as untrusted input, independently discover and validate the Issuer, and perform the complete issuance flow. The fact that a Wallet was just installed **MUST NOT** be treated as implicit authorization to accept the Credential — all authorization steps must complete normally.

## Appendix I. Additional Examples

The following examples show complete, decoded representations of the structured tokens used in this specification. Wire values would be the corresponding compact JWS/JWT serializations.

### I.1 Signed Credential Issuer Metadata

This example shows how Issuer Metadata is packaged in a signed JWT (Section 12.2.3). The signer is a Trust Provider (not the Issuer itself) — demonstrating that `iss` and `credential_issuer` can differ. The Wallet must verify that `sub` matches `credential_issuer` and that both match the Identifier used to fetch the metadata.

Signed metadata is served with `Content-Type: application/jwt`. The protected header explicitly types the token:

```json
{
  "alg": "ES256",
  "typ": "openidvci-issuer-metadata+jwt",
  "kid": "issuer-metadata-signing-key-1"
}
```

The payload repeats all Issuer Metadata parameters as top-level claims, plus the JWT signing claims required by Section 12.2.3:

```json
{
  "iss": "https://trust-provider.example.com",
  "sub": "https://credential-issuer.example.com",
  "iat": 1735689600,
  "exp": 1735693200,
  "credential_issuer": "https://credential-issuer.example.com",
  "authorization_servers": [
    "https://authorization-server.example.com"
  ],
  "credential_endpoint": "https://credential-issuer.example.com/credential",
  "nonce_endpoint": "https://credential-issuer.example.com/nonce",
  "credential_configurations_supported": {
    "IdentityCredential": {
      "format": "dc+sd-jwt",
      "vct": "https://credentials.example.com/identity_credential",
      "cryptographic_binding_methods_supported": ["jwk"],
      "credential_signing_alg_values_supported": ["ES256"],
      "proof_types_supported": {
        "jwt": {
          "proof_signing_alg_values_supported": ["ES256"]
        }
      }
    }
  }
}
```

Before using this metadata, the Wallet:
1. Establishes trust in the signer (`iss`) — e.g., by verifying `kid` against a trusted trust framework.
2. Validates the JWS signature.
3. Checks `iat` and `exp` to confirm the metadata is current.
4. Verifies that `sub` and `credential_issuer` both equal the Credential Issuer Identifier used to fetch the metadata (simple string comparison).

The full wire value is: `base64url(header).base64url(payload).base64url(signature)`.

### I.2 Full Issuer Metadata with Encryption and Batch Issuance

This example combines all optional metadata capabilities: endpoint discovery, application-layer request and response encryption, batch issuance, localization, and an SD-JWT VC Credential Configuration with key attestation requirements.

```json
{
  "credential_issuer": "https://credential-issuer.example.com",
  "authorization_servers": [
    "https://authorization-server.example.com"
  ],
  "credential_endpoint": "https://credential-issuer.example.com/credential",
  "nonce_endpoint": "https://credential-issuer.example.com/nonce",
  "deferred_credential_endpoint": "https://credential-issuer.example.com/deferred_credential",
  "notification_endpoint": "https://credential-issuer.example.com/notification",
  "credential_request_encryption": {
    "jwks": {
      "keys": [
        {
          "kty": "EC",
          "crv": "P-256",
          "kid": "request-encryption-key-1",
          "alg": "ECDH-ES",
          "x": "...",
          "y": "..."
        }
      ]
    },
    "enc_values_supported": ["A256GCM"],
    "zip_values_supported": ["DEF"],
    "encryption_required": false
  },
  "credential_response_encryption": {
    "alg_values_supported": ["ECDH-ES"],
    "enc_values_supported": ["A256GCM"],
    "zip_values_supported": ["DEF"],
    "encryption_required": false
  },
  "batch_credential_issuance": {
    "batch_size": 10
  },
  "display": [
    {
      "name": "Example Identity Issuer",
      "locale": "en-US",
      "logo": {
        "uri": "https://credential-issuer.example.com/logo.png",
        "alt_text": "Example Identity Issuer logo"
      }
    }
  ],
  "credential_configurations_supported": {
    "IdentityCredential": {
      "format": "dc+sd-jwt",
      "scope": "IdentityCredential",
      "vct": "https://credentials.example.com/identity_credential",
      "cryptographic_binding_methods_supported": ["jwk"],
      "credential_signing_alg_values_supported": ["ES256"],
      "proof_types_supported": {
        "jwt": {
          "proof_signing_alg_values_supported": ["ES256"],
          "key_attestations_required": {
            "key_storage": ["iso_18045_moderate"],
            "user_authentication": ["iso_18045_moderate"]
          }
        }
      },
      "credential_metadata": {
        "display": [
          {
            "name": "Identity Credential",
            "locale": "en-US",
            "background_color": "#12107c",
            "text_color": "#FFFFFF"
          }
        ],
        "claims": [
          {
            "path": ["given_name"],
            "display": [
              {"name": "Given name", "locale": "en-US"}
            ]
          },
          {
            "path": ["family_name"],
            "display": [
              {"name": "Surname", "locale": "en-US"}
            ]
          }
        ]
      }
    }
  }
}
```

Key points to note in this example:

- `encryption_required: false` means the Issuer supports both request and response encryption but does not mandate it. The Wallet may opt into encryption by providing its JWK in the Credential Request.
- If the Wallet requests response encryption, it must also encrypt requests — otherwise an attacker could intercept the Credential Request and substitute their own response key.
- `batch_size: 10` means the Wallet may provide up to 10 key proofs in a single Credential Request, receiving up to 10 Credentials bound to different keys.
- The `key_attestations_required` constraint applies specifically to the `jwt` proof type for the `IdentityCredential` configuration — the Issuer requires at least `iso_18045_moderate` resistance for both key storage and user authentication.

### I.3 Signed Wallet Attestation

This example shows a decoded Wallet Attestation JWT (Appendix E). The Wallet Provider signs it using its private key (`wallet-provider-key-1`). The `cnf.jwk` is the Wallet instance's key — the Wallet must prove possession of the corresponding private key via a separate Client Attestation PoP JWT.

The `status` claim uses the Token Status List format to allow runtime revocation checks. If the Wallet's entry in the status list is revoked, Authorization Servers must reject the attestation even if the signature is valid.

```text
{
  "alg": "ES256",
  "typ": "oauth-client-attestation+jwt",
  "kid": "wallet-provider-key-1"
}
.
{
  "iss": "https://wallet-provider.example.com",
  "sub": "https://wallet.example.org",
  "iat": 1735689600,
  "exp": 1735776000,
  "cnf": {
    "jwk": {
      "kty": "EC",
      "crv": "P-256",
      "x": "...",
      "y": "..."
    }
  },
  "wallet_name": "Example Wallet",
  "wallet_link": "https://wallet.example.org",
  "status": {
    "status_list": {
      "idx": 42,
      "uri": "https://wallet-provider.example.com/status"
    }
  }
}
```

The Authorization Server validates:
1. The Wallet Provider's signature (using the public key for `kid`).
2. The `iss` is a trusted Wallet Provider for this context.
3. `iat` and `exp` confirm the attestation is current.
4. The `status` entry at index 42 is not revoked.
5. The Client Attestation PoP JWT is signed by the key in `cnf.jwk`, proving Wallet instance control.

> **Note:** The example values are shortened for readability. Implementations send the complete compact JWTs on the wire.
