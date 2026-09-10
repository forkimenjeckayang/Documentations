# Token Status List Specification Summary

> This document summarizes the Token Status List specification in an easy-to-understand way.

📄 **Source Specification**: [IETF OAuth Token Status List Draft-21](https://www.ietf.org/archive/id/draft-ietf-oauth-status-list-21.html)
🗓️ Published: 21 June 2026, Expires: 23 December 2026. Intended status: Proposed Standard. Currently: IESG approved (`-20`), `-21` in RFC Editor Queue.
> Archived v11 summary: `../draft-ietf-oauth-status-list-11/TOKEN_STATUS_LIST_SPEC_SUMMARY.md`. See `CHANGES_FROM_DRAFT_11_TO_21.md` for what changed.

---

## 1. Introduction & Overview

### What is a Token Status List?

A **Token Status List (TSL)** is a mechanism to track and communicate the status (e.g., valid, revoked, suspended) of many tokens efficiently. Instead of checking each token individually with the issuer, the status of thousands or millions of tokens can be encoded in a single, compact data structure.

> 🆕 vs draft-11: **(TSL)** abbreviation added consistently (draft-11 title was already “Token Status List”). Scope: statuses of tokens secured by JOSE or COSE, such as JWT, SD-JWT, SD-JWT VC, CWT, SD-CWT, and ISO mdoc (SD-JWT + SD-CWT refs added in -18).

### The Problem It Solves

When tokens (like JWTs, access tokens, or verifiable credentials) are issued, their validity can change over time — they might be revoked or suspended. Relying parties need a way to check this status without:
- Contacting the issuer for every single token validation (poor scalability)
- Revealing which specific token they're checking (privacy concern)

### Key Artifacts & Relationships

```
┌────────────────┐  describes status  ┌──────────────────┐
│  Status List   │──────────────────► │ Referenced Token │
│ (JSON or CBOR) │◄───────────────────│ (JOSE, COSE, ..) │
└─────┬──────────┘    references      └──────────────────┘
      │
      │ embedded in
      ▼
┌───────────────────┐
│ Status List Token │
│   (JWT or CWT)    │
└───────────────────┘
```

| Artifact | Description |
|----------|-------------|
| **Referenced Token** | The actual token whose status is being tracked (JWT, SD-JWT VC, CWT, mdoc, etc.) |
| **Status List** | A bit array (JSON or CBOR) where each position represents a token's status |
| **Status List Token** | The Status List wrapped in a cryptographically signed container (JWT or CWT) |

### How It Works (Simplified)

1. **At Issuance**: Each token is assigned an **index** (position in the bit array)
2. **Status Encoding**: The bit(s) at that index represent the token's current status
3. **Status Retrieval**: Anyone can fetch the Status List Token and look up the status by index

A Status List Token is integrity-protected (signed/MACed), so it can be hosted by third parties or used offline.

### Roles in the System

```
                    issue              present
                  Referenced          Referenced
                    Token               Token
┌────────┐        ┌────────┐         ┌───────────────┐
│ Issuer │───────►│ Holder │────────►│ Relying Party │
└───┬────┘        └────────┘         └───────┬───────┘
    │                                        │
    │ update status                          │
    ▼                                        │
┌──────────────┐                             │
│ Status Issuer│                             │
└───┬──────────┘                             │
    │ provide Status List                    │
    ▼                                        │
┌─────────────────┐    fetch Status List     │
│ Status Provider │◄─────────────────────────┘
└─────────────────┘
```

| Role | Responsibility |
|------|----------------|
| **Issuer** | Issues Referenced Tokens to Holders |
| **Status Issuer** | Creates/updates Status List Tokens (can be the Issuer or authorized delegate) |
| **Status Provider** | Hosts Status List Tokens at a public, resolvable endpoint |
| **Holder** | Receives and presents Referenced Tokens |
| **Relying Party (Verifier)** | Validates tokens and checks their status |
| **Client** | 🆕 Application that fetches Status List Token from Status Provider on behalf of Holder or Relying Party |

> 💡 **Note**: The Issuer, Status Issuer, and Status Provider roles can all be the same entity. If not further specified, the term Issuer may refer to all three.

### Example Use Cases

1. **Access Token Management**: Instead of token introspection (contacting issuer per token), relying parties fetch one Status List for many tokens — reduces Issuer interactions, improves scalability + herd anonymity
2. **Verifiable Credentials**: Track status of credentials in the Issuer-Holder-Verifier model (SD-JWT VC)

### Why This Approach? (Rationale)

| Previous Approach | Problem |
|-------------------|---------|
| Certificate Revocation Lists (CRLs) | Limited scalability |
| OCSP (Online Certificate Status Protocol) | Privacy risk — leaks which certificate is being checked |
| OCSP Stapling | Data may be outdated |
| Accumulator-based + Zero-Knowledge Proofs | Scalability issues, not yet standardized (as of 2026) |
| Short-lived tokens + re-issuance | Burden on issuer infrastructure |

**Token Status List balances**: scalability, security, and privacy by:
- Minimizing status to just bits (often 1 bit per token)
- Compressing the data
- Grouping many tokens together for "herd privacy"

### Design Goals

| Goal | Description |
|------|-------------|
| **Simplicity** | Easy, fast and secure to implement in all major languages; optimize common cases (e.g. revocation), avoid corner-case complexity |
| **Scalability** | Support millions of tokens (government/enterprise scale) |
| **Caching & Offline** | Enable caching policies and offline validation |
| **Format Support** | Works with JSON and CBOR tokens |
| **No trust framework** | Shall not specify key resolution or trust frameworks |
| **Extensibility** | Extension point for custom status types and mechanisms |

### Prior Work (Sec 1.4)

Representing statuses as bits in an array is old and well-known (already in draft-11):
- Smith et al.: Certificate Revocation Vectors based on xz-compressed bit vectors per expiration day
- W3C Bit String Status List: similarly uses compressed bit representation

### Status Mechanisms Registry (Sec 1.5)

This spec establishes IANA **Status Mechanisms** registries (JOSE + COSE) and registers the Status List mechanism (already in draft-11; requirements extended in -20). Other specs can register additional members with different security/privacy/scalability tradeoffs. Privacy/security considerations in this document apply only to the Status List mechanism.

### Conventions (Sec 2)

The key words **MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT, RECOMMENDED, NOT RECOMMENDED, MAY, OPTIONAL** are interpreted per BCP 14 (RFC 2119 + RFC 8174) when in all capitals.

---

## 2. Terminology (Glossary)

| Term | Definition |
|------|------------|
| **Issuer** | Entity that issues the Referenced Token. Also known as Provider |
| **Status Issuer** | Entity that issues the Status List Token (can be same as Issuer) |
| **Status Provider** | Entity that hosts Status List Token at a public endpoint (can be same as Status Issuer) |
| **Holder** | Entity that receives tokens from Issuer and presents them to Relying Parties |
| **Relying Party (Verifier)** | Entity that validates Referenced Tokens by fetching and checking Status List Tokens |
| **Status** | Current state/mode/condition/stage of entity represented by Referenced Token, as determined by Status Issuer |
| **Status List** | JSON/CBOR object containing a compressed byte array representing statuses of many tokens |
| **Status List Token** | JWT or CWT containing a cryptographically secured Status List |
| **Referenced Token** | Cryptographically secured data structure with a `status` claim pointing to its Status List entry. RECOMMENDED JSON+JOSE or CBOR+COSE. Examples: SD-JWT, ISO mdoc |
| **Client** | 🆕 Application fetching info (e.g. Status List Token) from Status Provider on behalf of Holder or Relying Party |
| **base64url** | URL-safe base64 encoding without padding (per RFC 7515) |

---

## 3. Status List Format

### 3.1 Core Concept: The Compressed Byte Array

The Status List is fundamentally a **compressed byte array** where each token's status is represented by bits at a specific index.

#### Bit Size Options

| Bits per Token | Statuses per Byte | Possible Status Values |
|----------------|-------------------|------------------------|
| **1 bit** | 8 tokens/byte | 2 values (0-1) |
| **2 bits** | 4 tokens/byte | 4 values (0-3) |
| **4 bits** | 2 tokens/byte | 16 values (0-15) |
| **8 bits** | 1 token/byte | 256 values (0-255) |

> 💡 The bit size is limited to 1, 2, 4, or 8 to keep bit manipulation within a single byte — simpler and less error-prone.

#### Algorithm to Create a Status List

```
1. CHOOSE bit size (1, 2, 4, or 8) — MUST be one of these
2. CREATE byte array: size = (number_of_tokens × bits) / 8 or greater
   → each byte holds 8/bits statuses (8, 4, 2, or 1)
3. SET status values at each index (index 0 .. n-1, contiguous bit blocks
   packed LSB (bit 0) → MSB (bit 7); see Sec 7 for values)
4. COMPRESS using DEFLATE (RFC 1951) with ZLIB format (RFC 1950);
   highest compression level RECOMMENDED
```

#### How Bits Map to Indices

- Bits are counted from **least significant bit (0)** to **most significant bit (7)**
- Index 0 starts at the LSB of byte 0; blocks packed contiguously into bytes

### 3.2 Example: 1-Bit Status List (16 tokens)

```
Statuses: [1,0,0,1,1,1,0,1,1,1,0,0,0,1,0,1]
           ↑                             ↑
        index 0                      index 15

Byte Layout:
┌─────────────────────────┐  ┌─────────────────────────┐
│  Byte 0 (indices 0-7)   │  │  Byte 1 (indices 8-15)  │
├─────────────────────────┤  ├─────────────────────────┤
│ bit: 7 6 5 4 3 2 1 0    │  │ bit: 7 6 5 4 3 2 1 0    │
│      1 0 1 1 1 0 0 1    │  │      1 0 1 0 0 0 1 1    │
│      ↑         ↑   ↑    │  │      ↑             ↑    │
│    idx7      idx1 idx0  │  │    idx15         idx8   │
├─────────────────────────┤  ├─────────────────────────┤
│      = 0xB9             │  │      = 0xA3             │
└─────────────────────────┘  └─────────────────────────┘

byte array: [0xb9, 0xa3]
compressed (hex): 78dadbb918000217015d
```

### 3.3 Example: 2-Bit Status List (12 tokens)

```
Statuses: [1,2,0,3,0,1,0,1,1,2,3,3]
           ↑                     ↑
        index 0              index 11

Byte 0 (indices 0-3): bits 7-6=3, 5-4=0, 3-2=2, 1-0=1 → 0xC9
Byte 1 (indices 4-7): 1, 0, 1, 0 → 0x44
Byte 2 (indices 8-11): 3, 3, 2, 1 → 0xF9

byte array: [0xc9, 0x44, 0xf9]
compressed (hex): 78da3be9f2130003df0207
```

### 3.4 JSON Representation

```json
{
  "status_list": {
    "bits": 1,
    "lst": "eNrbuRgAAhcBXQ",
    "aggregation_uri": "https://example.com/statuslists"
  }
}
```

| Field | Required | Description |
|-------|----------|-------------|
| `bits` | ✅ Yes | JSON Integer, bits per token (1, 2, 4, or 8) |
| `lst` | ✅ Yes | JSON String, base64url-encoded DEFLATE-compressed byte array |
| `aggregation_uri` | ❌ No | JSON String, URI to Status List Aggregation (see Sec 9) |

**1-bit example** (`[0xb9, 0xa3]`): `{"bits": 1, "lst": "eNrbuRgAAhcBXQ"}`
**2-bit example** (`[0xc9, 0x44, 0xf9]`): `{"bits": 2, "lst": "eNo76fITAAPfAgc"}`

> See Appendix C for more test vectors.

### 3.5 CBOR Representation

For CBOR-encoded Status Lists, the structure is a **map (Major Type 5)**:

| Field | CBOR Type | Required | Description |
|-------|-----------|----------|-------------|
| `bits` | Unsigned int (Major Type 0) | ✅ Yes | Number of bits per token (1, 2, 4, or 8) |
| `lst` | Byte string (Major Type 2) | ✅ Yes | Compressed byte array (raw bytes, not base64url) |
| `aggregation_uri` | Text string (Major Type 3) | ❌ No | URI for Status List Aggregation |

#### CDDL Definition

```cddl
StatusList = {
    bits: 1 / 2 / 4 / 8, ; The number of bits used per Referenced Token
    lst: bstr, ; Byte string that contains the Status List
    ? aggregation_uri: tstr ; link to the Status List Aggregation
}
```

#### CBOR Example (Hex)

```
Input: byte_array = [0xb9, 0xa3]
Encoded: a2646269747301636c73744a78dadbb918000217015d
```

**Annotated breakdown:**
```
a2                              # map(2)
  64                            #   string(4)
    62697473                    #     "bits"
  01                            #   uint(1)
  63                            #   string(3)
    6c7374                      #     "lst"
  4a                            #   bytes(10)
    78dadbb918000217015d        #     compressed data
```

---

## 4. Status List Token

The Status List Token is a **cryptographically signed container** that wraps the Status List. This enables:
- ✅ Third-party hosting
- ✅ Integrity protection
- ✅ Offline use cases

### 4.1 Status List Token in JWT Format

The Status List Token MUST be encoded as a JWT per RFC 7519.

#### JWT Header

| Claim | Required | Value |
|-------|----------|-------|
| `typ` | ✅ Yes | **`statuslist+jwt`** (exactly this value) |
| `alg` | ✅ Yes | Signing algorithm (e.g., ES256) |
| `kid` | Recommended | Key identifier |

#### JWT Claims (Payload)

| Claim | Required | Description |
|-------|----------|-------------|
| `sub` | ✅ Yes | URI of this Status List Token. **Must match** the `uri` in Referenced Tokens' `status_list` claim |
| `iat` | ✅ Yes | Issued-at timestamp |
| `exp` | Recommended | Expiration time. Consider guidance in Sec 13.7 |
| `ttl` | Recommended | Time-to-live in seconds for caching (positive number). Consider guidance in Sec 13.7 |
| `status_list` | ✅ Yes | The Status List object (with `bits` and `lst`) |

#### Example JWT

**Header:**
```json
{
  "alg": "ES256",
  "kid": "12",
  "typ": "statuslist+jwt"
}
```

**Payload:**
```json
{
  "exp": 2291720170,
  "iat": 1686920170,
  "status_list": {
    "bits": 1,
    "lst": "eNrbuRgAAhcBXQ"
  },
  "sub": "https://example.com/statuslists/1",
  "ttl": 43200
}
```

#### Validation Rules

| Rule | Description |
|------|-------------|
| ✅ Signature/MAC | MUST be secured; reject invalid signatures |
| ✅ JWT validity | Must be valid per RFC 7519 |
| ✅ `sub` matching | Must match URI referenced by token being checked |

### 4.2 Status List Token in CWT Format

MUST be encoded as CWT per RFC 8392. MUST NOT be tagged with CWT tag (RFC 8392 Sec 6). COSE message MUST be `COSE_Sign1_Tagged (18)` or `COSE_Mac0_Tagged (17)` per RFC 9052.

#### CWT Protected Header

| Claim | Code | Required | Value |
|-------|------|----------|-------|
| `type` | **16** | ✅ Yes | `application/statuslist+cwt` or registered CoAP Content-Format ID (Sec 14.8) per RFC 9596 |

#### CWT Claims Set

| Claim | Code | Required | Description |
|-------|------|----------|-------------|
| `subject` | **2** | ✅ Yes | URI of this Status List Token (must match Referenced Token's `uri`) |
| `issued at` | **6** | ✅ Yes | Issuance timestamp |
| `expiration time` | **4** | Recommended | When the token expires |
| `time to live` | **65534** | Recommended | Cache duration in seconds (unsigned int) |
| `status list` | **65533** | ✅ Yes | The Status List (CBOR format, Sec 4.3) |

```
Standard Claims:        Custom Claims:
  2  = subject            65533 = status_list
  4  = expiration         65534 = ttl
  6  = issued_at
  16 = type (header)
```

### 4.3 JWT vs CWT Comparison

| Aspect | JWT Format | CWT Format |
|--------|------------|------------|
| **Type** | `typ: "statuslist+jwt"` | `16: "application/statuslist+cwt"` |
| **Subject** | `sub` (string) | `2` (subject) |
| **Issued At** | `iat` (number) | `6` (issued at) |
| **Expiration** | `exp` (number) | `4` (expiration time) |
| **TTL** | `ttl` (number) | `65534` (unsigned int) |
| **Status List** | `status_list` (JSON object) | `65533` (CBOR map) |
| **Encoding** | Base64url JSON | CBOR binary |

---

## 5. Referenced Token

A **Referenced Token** is any token (JWT, SD-JWT, SD-JWT VC, CWT, SD-CWT, ISO mdoc) that includes a `status` claim pointing to its entry in a Status List.

### 5.1 The Status Claim

The `status` claim is a container that can reference **one or more status mechanisms**. This specification defines the `status_list` mechanism, but other mechanisms can coexist.

> 💡 Analogous to `cnf` claim in RFC 7800 Sec 3.1.

### 5.2 Referenced Token in JOSE/JWT Format

MAY be JWT (RFC 7519), SD-JWT (RFC 9901), SD-JWT VC, or other JOSE formats.

```json
{
  "status": {
    "status_list": {
      "idx": 0,
      "uri": "https://example.com/statuslists/1"
    }
  }
}
```

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `status` | ✅ Yes | JSON Object | MUST contain at least one status mechanism reference |
| `status_list` | ✅ Yes (when used) | JSON Object | MUST contain reference to Status List Token |
| `idx` | ✅ Yes | Non-negative Integer | Index in Status List (0 or greater) |
| `uri` | ✅ Yes | String (URI per RFC 3986) | URI of Status List Token to fetch |

SD-JWT VC uses the same `status` encoding alongside selective disclosure claims.

### 5.3 Referenced Token in COSE/CWT Format

| Claim | Code | Type | Description |
|-------|------|------|-------------|
| `status` | **65535** | CBOR map | Container for status mechanisms |
| `status_list` | text string key | CBOR map | Same as Sec 6.2, CBOR-encoded |
| `idx` | — | Unsigned int (Major Type 0) | Index in Status List |
| `uri` | — | Text string (Major Type 3) | URI of Status List Token (RFC 3986) |

```
65535 (status): {
  "status_list": {
    idx: 0,
    uri: "https://example.com/statuslists/1"
  }
}
```

### 5.4 ISO mdoc Support

ISO mdoc uses the Status List mechanism as another COSE-based Referenced Token type, using the same core `status` / `StatusListInfo` CBOR structure (`idx` + `uri`).

### 5.5 How It All Connects

```
┌─────────────────────────────────────┐
│         Referenced Token            │
│  (JWT, SD-JWT VC, CWT, ISO mdoc)    │
├─────────────────────────────────────┤
│  status: {                          │
│    status_list: {                   │
│      idx: 5,  ◄─────────────────────┼──── "Look at index 5"
│      uri: "https://.../statuslist/1"│
│    }           │                    │
│  }             │                    │
└────────────────┼────────────────────┘
                 │
                 │ fetch
                 ▼
┌─────────────────────────────────────┐
│       Status List Token             │
│  sub: "https://.../statuslist/1"    │◄── URI must match!
├─────────────────────────────────────┤
│  status_list: {                     │
│    bits: 1,                         │
│    lst: "eNrbuRg..."                │
│  }                                  │
│         │                           │
│         ▼                           │
│  Decompress & check bit at index 5  │
└─────────────────────────────────────┘
```

### 5.6 JWT vs CWT Comparison for Referenced Tokens

| Aspect | JWT (JOSE) | CWT (COSE) |
|--------|------------|------------|
| **Status claim** | `"status"` (string key) | `65535` (numeric key) |
| **Index** | `"idx"` (JSON integer) | `idx` (unsigned int) |
| **URI** | `"uri"` (JSON string) | `uri` (text string) |
| **Use cases** | JWT, SD-JWT VC | CWT, SD-CWT, ISO mdoc |

---

## 6. Status Types

Each token has **exactly one status** at any given time. If `bits` > 1, the whole value describes one status. Values 0-255. Issuer MUST choose adequate `bits`.

### 6.1 Defined Status Type Values

| Hex | Decimal | Name | Description |
|-----|---------|------|-------------|
| `0x00` | 0 | **VALID** | Token is valid, correct, legal |
| `0x01` | 1 | **INVALID** | Token is revoked, annulled, cancelled |
| `0x02` | 2 | **SUSPENDED** | Token is temporarily invalid (usually temporary) |

### 6.2 Reserved Values

| Range | Usage |
|-------|-------|
| `0x03` | Application-specific (permanently reserved) |
| `0x0C` - `0x0F` | 🆕 Application-specific (permanently reserved; `0x0B` removed vs draft-11) |
| All others | Reserved for future registration |

### 6.3 Bit Size Requirements

| Status Types Needed | Minimum `bits` Value |
|--------------------|---------------------|
| VALID, INVALID only | 1 bit (2 values) |
| VALID, INVALID, SUSPENDED | 2 bits (4 values) |
| Up to 16 statuses | 4 bits |
| Up to 256 statuses | 8 bits |

### 6.4 Important Processing Rule

> ⚠️ **Token validation rules take precedence over status!**
>
> If a token is expired (`exp` claim), it's rejected even if the Status List says `VALID (0x00)`.

---

## 7. Verification and Processing

Rules apply to both **Holders** and **Relying Parties** (described from RP role).

### 7.1 Status List Request

```http
GET /statuslists/1 HTTP/1.1
Host: example.com
Accept: application/statuslist+jwt
```

| Requirement | Details |
|-------------|---------|
| **Method** | HTTP GET to `uri` from Referenced Token |
| **Distribution** | Provider MUST return token on GET unless alternative agreed |
| **Accept Header** | `application/statuslist+jwt` or `application/statuslist+cwt` (content negotiation per RFC 9110) |
| **CORS** | SHOULD support CORS unless ecosystem opts out of browser clients |

### 7.2 Status List Response

```http
HTTP/1.1 200 OK
Content-Type: application/statuslist+jwt

eyJhbGciOiJFUzI1NiIsImtpZCI6IjEyIiwidHlwIjoic3RhdHVzbGlzdCtqd3QifQ...
```

| Requirement | Details |
|-------------|---------|
| **Success** | MUST use `2xx` |
| **Redirect** | MAY return `3xx`; clients SHOULD follow (see Sec 11.4, RFC 9110 Sec 15.4) |
| **Content-Type** | `application/statuslist+jwt` or `application/statuslist+cwt` |
| **Body** | Raw token: JWS Compact for JWT; binary per RFC 8392 Sec 9.2.1 for CWT |
| **Compression** | SHOULD use `Content-Encoding` (e.g. gzip) for JWT |
| **Caching** | `exp` and `ttl` inside token take priority over HTTP cache headers |

### 7.3 Complete Validation Algorithm

```
Step 0: VALIDATE REFERENCED TOKEN FIRST (MUST precede status)
        ├── Check signature, exp, expected attributes
        └── If invalid → REJECT; MUST NOT fetch Status List
            unless use case requires further evaluation

Step 1: CHECK STATUS CLAIM EXISTS
        ├── status + status_list + idx + uri present, well-formed
        └── If FAIL → no statement possible; SHOULD reject

Step 2: RESOLVE STATUS LIST TOKEN (fetch from uri)

Step 3: VALIDATE SIGNATURE + STRUCTURE
        ├── Per RFC 7519 Sec 7.2 (JWT) / RFC 8392 Sec 7.2 (CWT)
        ├── Check required claims (sub/2, iat/6, status_list/65533)
        └── If FAIL → REJECT

Step 4: CHECK ALL EXISTING CLAIMS
        ├── a. sub (or 2) MUST == uri in Referenced Token
        ├── b. iat (or 6): SHOULD check freshness policy
        ├── c. exp (or 4): if present, MUST check expiry
        ├── d. ttl: SHOULD refetch if (resolved_time + ttl < now)
        └── If FAIL → REJECT

Step 5: DECOMPRESS (DEFLATE + ZLIB)
Step 6: RETRIEVE STATUS at idx; if out-of-bounds → MUST reject
Step 7: EVALUATE (0x00 VALID, 0x01 INVALID, 0x02 SUSPENDED, else app-specific)
```

### 7.4 Validation Checklist

| # | Check | Action on Failure |
|---|-------|-------------------|
| 0 | Referenced Token signature/exp valid | REJECT, do not fetch |
| 1 | `status` + `status_list` present | SHOULD REJECT |
| 2 | Status List Token fetched (2xx, follow 3xx) | SHOULD REJECT |
| 3 | Status List Token signature + required claims valid | SHOULD REJECT |
| 4 | `sub` == `uri` | SHOULD REJECT |
| 5 | `iat` freshness (SHOULD) | Per local policy |
| 6 | `exp` not expired (MUST if present) | SHOULD REJECT |
| 7 | `ttl` fresh, else refetch | Fetch fresh copy |
| 8 | Decompression succeeds | SHOULD REJECT |
| 9 | `idx` within bounds | MUST reject |
| 10 | Status acceptable | Depends on value |

### 7.5 Historical Resolution (Optional)

```http
GET /statuslists/1?time=1686925000 HTTP/1.1
Host: example.com
Accept: application/statuslist+jwt
```

| Parameter | Description |
|-----------|-------------|
| `time` | Unix timestamp `time=<timestamp>` for desired point in time |

| HTTP Status | Meaning (draft-21) |
|-------------|--------------------|
| **200** | Success — MUST reject unless requested `time` within returned `iat` to `exp` |
| **501** | Not Implemented — server does not support `time` (SHOULD) |
| **404** | 🆕 Not Found — requested time not supported (SHOULD; was `406` in draft-11) |

> ⚠️ **Privacy Warning**: Historical resolution has significant privacy implications. RECOMMENDED NOT to support unless strongly justified.

---

## 8. Status List Aggregation (Optional)

Allows Issuer to publish **all Status List Token URIs**, enabling pre-fetching, caching, offline validation.

### 8.1 Discovery

```
1. Issuer Metadata ← .well-known, OAuth metadata, trust lists
2. aggregation_uri ← In the Status List itself
```

If Issuer is OAuth AS, RECOMMENDED to use `status_list_aggregation_endpoint` in RFC 8414 metadata. MAY limit to a particular token type.

### 8.2 Aggregation Response (JSON)

```json
{
  "status_lists": [
    "https://example.com/statuslists/1",
    "https://example.com/statuslists/2",
    "https://example.com/statuslists/3"
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `status_lists` | Array of strings | URIs to Status List Tokens |

**Media Type**: `application/json` (MUST)

### 8.3 Processing Note

> If one Status List Token fails validation, **SHOULD continue processing the others**.

### 8.4 X.509 EKU (Sec 10)

`id-kp-oauthStatusSigning ::= { id-kp TBD }` — explicitly delegates Status List signing authority in EKU. MAY be re-used by other status mechanisms registered in JWT/CWT Status Mechanisms registries.

---

## 9. Security Considerations

> Status List Tokens exist **only** in secured containers. Integrity/origin verifiable without transport security.

### 9.1 Correct Decoding (11.1)

> ⚠️ Incorrect parsing = checking wrong index!

| Aspect | Rule |
|--------|------|
| **Bit order** | LSB (0) to MSB (7) — "right to left" |
| **Byte order** | Natural incrementing — "left to right" |
| **Endianness** | Does NOT apply |

Use Appendix C test vectors to verify.

### 9.2 JWT/CWT Guidance (11.2)

Follow RFC 7519 + RFC 8725 (JWT BCP), RFC 8392 (CWT).

### 9.3 Key Resolution (11.3)

Same entity: same key (`x5c`/`x5t`/`kid` for JOSE; `x5chain`/`x5t`/`kid` for COSE) or same web resolution (`x5u`/`jwks`/`jwks_uri`). Different entities: same CA + Status Issuer cert with EKU `id-kp-oauthStatusSigning` (Sec 10).

### 9.4 Redirection 3xx (11.4) 🆕

Follow per RFC 9110 Sec 15.4; beware infinite-loop / DoS.

### 9.5 Expiration/Caching Abuse (11.5) 🆕

Malicious tiny `exp`/`ttl` → client floods Provider (DDoS). Clients SHOULD sanity-check both against local bounds.

### 9.6 Token Protection (11.6) 🆕

Asymmetric signatures = expected default (SHOULD if unsure). MAC (e.g. COSE Mac0) only with trust + out-of-band keys, same entity, or no third-party verification needed.

---

## 10. Privacy Considerations

### 10.1 Herd Privacy

```
Many tokens share ONE Status List
→ Issuer doesn't know WHICH token is being checked
→ Larger list = better privacy (but more data)
```

Mitigations for Issuer tracking: herd privacy, private relay / Oblivious HTTP (RFC 9458), third-party hosting (Provider ≠ Issuer).

Malicious issuer bypass (unique list/uri per token) can be detected by RPs comparing list sizes across tokens. Unique URIs (query/path/fragment) also tracked — 🆕 in draft-21.

### 10.2 RP Monitoring / Outsider Analysis

RP storing `uri`+`idx` and re-checking → profile. Mitigation: regular re-issuance with fresh index.

Outsiders analyzing public lists → total issued, revocation rates. Mitigations: random indices, decoy entries, multiple lists, disable aggregation/history.

### 10.3 Unlinkability

`(uri, idx)` is unique/traceable. Colluding RPs/Status Issuer can link Holder. Mitigation: batches of one-time-use tokens, random indices, decoys, multiple lists. Solves RP↔RP, NOT Issuer traceability.

### 10.4 Third-Party Hosting

```
Status Issuer (signs) → Status Provider (CDN) ← RP
✅ Issuer can't see requests ✅ Scalable ✅ Integrity via signature
```

### 10.5 Historical / Status Types

Historical `?time=` = strong privacy risk; RECOMMENDED not to support. Additional statuses beyond VALID/INVALID (e.g. SUSPENDED) leak info — consider revocation + re-issuance instead.

---

## 11. Implementation / Operational Considerations

### 11.1 Token Lifecycle

When ALL Referenced Tokens expire, Status List Token can be retired.

| Strategy | Requirement |
|----------|-------------|
| **Regular re-issuance** | Fresh index each time (mitigate linkability) |
| **Batch issuance** | Dedicated index per token; MAY span multiple lists |

### 11.2 Default Values and Double Allocation

Initialize with default (usually `0x00`): better compression, hides count, no update at issuance.

| Rule | Description |
|------|-------------|
| RECOMMENDED | Prevent double allocation (same `uri`+`idx` for different tokens) |
| MUST | Prevent any **unintended** double allocation |

### 11.3 Size

Factors: # tokens, revocation rate (~0%/100% = smallest; ~50% random = largest), lifetime. Recommendations: size-in-bits divisible by 8, split for constrained envs, group by expiry (watch correlation), MAY grow list.

### 11.4 External Issuer/Provider

Issuer ≠ Status Issuer: align on keys (Sec 11.3), `bits`, `ttl`. Issuer → Provider (CDN) for scalability + privacy; authenticity via signature.

### 11.5 Update Interval and Caching

| Claim | Meaning |
|-------|---------|
| `exp` | MUST NOT use after this |
| `ttl` | When new version MAY be available (from fetch time) |
| `iat` | Issuance; base for `iat+ttl` mode |

Use BOTH `exp` + `ttl` RECOMMENDED. Options: A (RECOMMENDED) `fetch_time+ttl` (load-spreading), B `iat+ttl` (freshest), C `exp` if no `ttl`. Always bound-check (Sec 11.5).

### 11.6 Hygiene / Format Mixing

Delete `status` claim / Status List Token after use; keep only needed payload. Format mixing (e.g. CBOR token + JWT list) allowed but ecosystems choose via profiles.

---

## 12. IANA Registrations Summary

### 12.1 JWT Claims

| Claim | Description |
|-------|-------------|
| `status` | Reference to mechanism from JWT Status Mechanisms Registry |
| `status_list` | Status list with token statuses |
| `ttl` | Time to live |

### 12.2 JWT Status Mechanisms Registry

Group `JWT` at `iana.org/assignments/jwt`. Policy: Specification Required + 3-week review on `jwt-reg-review@ietf.org`. Initial: `status_list` → Token Status List. (Existed in draft-11; requirements extended in -20.)

### 12.3 CWT Claims

| Claim | Key | Type |
|-------|-----|------|
| `status` | 65535 (TBD) | map |
| `status_list` | 65533 (TBD) | map |
| `ttl` | 65534 (TBD) | unsigned int |

### 12.4 CWT Status Mechanisms Registry

Same policy on `cwt-reg-review@ietf.org`. Initial: `status_list`. (Existed in draft-11; extended in -20.)

### 12.5 Status Types Registry

`OAuth Status Types` at `oauth-parameters`. Policy: Specification Required + 2-week review on `oauth-ext-review@ietf.org`. (Existed in draft-11; extended in -20.)

| Name | Value | Description |
|------|-------|-------------|
| VALID | `0x00` | Valid |
| INVALID | `0x01` | Revoked |
| SUSPENDED | `0x02` | Temporarily invalid |
| APPLICATION_SPECIFIC | `0x03`, `0x0C-0x0F` | Custom use |

### 12.6 OAuth Metadata

`status_list_aggregation_endpoint` → URL for aggregation.

### 12.7 Media Types / CoAP / X.509

`application/statuslist+jwt`, `application/statuslist+cwt` (contact: `oauth@ietf.org`). CoAP Content-Format ID TBD for CWT. X.509 EKU OID `1.3.6.1.5.5.7.3.TBD` (`id-kp-oauthStatusSigning`), module OID TBD, ASN.1 in Appendix A.

---

## Quick Reference Card

### The Complete Flow

```
1. ISSUANCE: Issuer → Referenced Token (status.status_list.idx/uri) → Holder
2. STATUS MANAGEMENT: Issuer → Status Issuer → Status List Token → Status Provider
3. PRESENTATION: Holder → Referenced Token → Relying Party
4. VALIDATION:
   a) Validate Referenced Token FIRST (signature, exp) → if invalid REJECT, don't fetch
   b) Extract idx + uri
   c) GET Status List Token (Accept: application/statuslist+jwt|cwt; follow 3xx safely)
   d) Validate (signature, sub==uri, exp/ttl)
   e) Decompress lst (ZLIB/DEFLATE)
   f) Read bits at idx; out-of-bounds → MUST REJECT
   g) Interpret (0x00 VALID, 0x01 INVALID, 0x02 SUSPENDED)
```

### Key Data Structures

```
Referenced Token (JWT):
{
  "status": {
    "status_list": {
      "idx": 12345,
      "uri": "https://issuer.example/statuslists/1"
    }
  }
}

Status List Token (JWT):
Header: { "typ": "statuslist+jwt", "alg": "ES256" }
Payload: {
  "sub": "https://issuer.example/statuslists/1",
  "iat": 1686920170,
  "exp": 2291720170,
  "ttl": 43200,
  "status_list": {
    "bits": 1,
    "lst": "eNrbuRgAAhcBXQ"
  }
}
CWT keys: status=65535, status_list=65533, ttl=65534, subject=2, exp=4, iat=6, type=16
```

### Bit Extraction Formula

```
byte_index = floor(idx * bits / 8)
bit_offset = (idx * bits) % 8
mask       = (2^bits - 1) << bit_offset
status = (lst[byte_index] & mask) >> bit_offset
```

---

*Last updated: draft-ietf-oauth-status-list-21 (21 June 2026). See CHANGES_FROM_DRAFT_11_TO_21.md for diff from -11.*
