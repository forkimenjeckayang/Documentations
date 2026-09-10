# Changes from draft-11 to draft-21 — Token Status List

> Source: Document History appendix of `draft-ietf-oauth-status-list-21` + diff of `-11.txt` (4032 lines) vs `-21.txt` (4480 lines).
> Full texts: https://www.ietf.org/archive/id/draft-ietf-oauth-status-list-11.txt / ...-21.txt

## 0. TL;DR

- Spec adds **(TSL)** abbreviation consistently (draft-11 title was already “Token Status List”).
- Your v11 summary is functionally still correct for core flow (bits/lst, JWT/CWT, idx/uri, 0x00/0x01/0x02), but **10 versions behind** on normative details, IANA refinements, security/privacy, and CWT rules.
- If implementing today: follow `-21` for CWT tagging, validation order, `404` history code, `0x0B` removal, `exp`/`ttl` RECOMMENDED, and new registries.

## 1. Naming / Structure

| Area | draft-11 | draft-21 |
|------|----------|----------|
| Title | Token Status List (no TSL abbrev) | **Token Status List (TSL)** consistently, Abstract + Sec 1 |
| Sec 1 | Intro, Use Cases, Rationale, Design Goals, Prior Work, Status Mechanisms Registry (all already present) | Same structure; text refinements, SD-JWT (RFC 9901) + SD-CWT refs added in -18, intro nits in -16 |
| Sec 2/3 | Conventions + Terminology together | Split: Sec 2 Conventions, Sec 3 Terminology + new **Client** term (-13) + **Status** definition |
| Sec 10-14 | Sec 10 Privacy?/11 Implementation? layout differs; X.509 EKU inline | Sec 10 X.509 EKU (own section), 11 Security (+11.4/11.5/11.6 new), 12 Privacy, **13 Operational**, 14 IANA (extended) |
| Appendices | Size comparison tables + Test vectors + Document History (all present) | + **A ASN.1 module** (new in -14), **B Size Comparison** (formalized appendix, same numbers), **C Test vectors** (binary display), Document History continued |

## 2. Normative / Breaking Changes

1. **Validation order (Sec 8.3, -17):** MUST validate Referenced Token first; MUST NOT fetch Status List if invalid unless use case requires. In -11 this was guidance; now explicit Step 0.
2. **Index out-of-bounds (Sec 8.3, -16):** strengthened to **MUST reject** (was SHOULD in -11 summary checklist).
3. **CWT COSE message (Sec 5.2, -15):** limited to `COSE_Sign1_Tagged (18)` or `COSE_Mac0_Tagged (17)`. **MUST NOT** use CWT tag (RFC 8392 Sec 6). Example now includes `d2` tag explanation.
4. **Historical resolution (Sec 8.4, -16):** `406 Not Acceptable` → **`404 Not Found`** for unsupported time. Query `?time=` wording clarified. Still OPTIONAL, RECOMMENDED NOT to support.
5. **Status Types (Sec 7, -14):** removed `0x0B` from app-specific. Now: `0x03` + `0x0C-0x0F` app-specific (was `0x03`, `0x0B-0x0F` in -11). All others reserved. Re-emphasized expired + VALID = expired.
6. **JSON Status List (Sec 4.2, -12):** structure clarified to only contain JSON object (no bare array).
7. **Accept header (Sec 8.1, -12):** relaxed MUST → SHOULD (content negotiation per RFC 9110).
8. **exp / ttl (Sec 5.1/5.2, -13):** made **RECOMMENDED** consistently (fixed inconsistency where text said recommended but tables said optional). Guidance linked to Sec 13.7.
9. **Redirection (Sec 11.4, -13/-16):** new normative guidance: MAY return 3xx, SHOULD follow per RFC 9110 Sec 15.4, beware infinite-loop/DoS.
10. **EKU OID (Sec 10/14.9):** `id-kp-oauthStatusListSigning` → **`id-kp-oauthStatusSigning`** (`{ id-kp TBD }`, `1.3.6.1.5.5.7.3.TBD`). MAY be re-used by other registered status mechanisms (-12). New ASN.1 module `id-mod-oauth-status-signing-eku`.
11. **Content negotiation:** now explicitly refers to RFC 9110 (was generic HTTP).
12. **Media type contact:** changed to `oauth@ietf.org` (-16).
13. **Graphics:** reverted to ASCII (-19) for RFC XML compatibility.

## 3. IANA (Refinements, not new registries)

- Registries already existed in draft-11; **-20 extended requirements text** for all registries.
- `JWT Status Mechanisms` (Sec 14.2, `jwt-reg-review@ietf.org`, Spec Required) — initial `status_list` (unchanged).
- `CWT Status Mechanisms` (Sec 14.4, `cwt-reg-review@ietf.org`) — initial `status_list` (unchanged).
- **Existing:** `OAuth Status Types` (Sec 14.5, `oauth-ext-review@ietf.org`, 2-week review) — VALID `0x00`, INVALID `0x01`, SUSPENDED `0x02`, app-specific `0x03`, `0x0C-0x0F` (note `0x0B` removed in -14).
- Extended requirements text for all registries (-20).
- CWT claims 65535/65533/65534 still TBD (pending early allocation); JWT claims `status`, `status_list`, `ttl` unchanged.
- `status_list_aggregation_endpoint` OAuth metadata unchanged.
- CoAP Content-Format TBD for `application/statuslist+cwt` unchanged.

## 4. Security / Privacy (New Guidance)

- **New Sec 11.5:** `exp`+`ttl` abuse → DDoS; clients SHOULD bound-check.
- **New Sec 11.6:** signatures SHOULD (default); MAC only with trust + out-of-band keys / same entity / no third-party verification.
- **Privacy:** unique URIs (query/path/fragment) explicitly called out as tracking vector (-13). KYC example clarified. Collusion discussion strengthened (-16). Historical + aggregation mitigations (disable, random idx, decoys, multiple lists) emphasized.
- **Operational Sec 13:** split Linkability Mitigation from Lifecycle (-12), added growable lists, grouping-by-expiry privacy warning, format-mixing (CBOR token + JWT list allowed, profile-defined).

## 5. References / Examples

- **Added in -21 vs -11**: SD-JWT (RFC 9901, -17/-18), SD-CWT (`I-D.ietf-spice-sd-cwt`, -18), SD-JWT VC updated (`-08` → `-16`), ISO 18013-5 link (-19), RFC 8126 (IANA procedures, replaces RFC 5226, -20), RFC 9562 (UUID, -21). RFC 9110, RFC 9458, RFC 8725, RFC 9596 were already in -11.
- SD-JWT VC ref changed to SD-JWT in -17 then re-added alongside in -18 (current -21 lists JWT, SD-JWT, SD-JWT VC, CWT, SD-CWT, mdoc; -11 listed JWT, SD-JWT VC, CWT, mdoc).
- Removed non-normative ISO mdoc examples (-16), removed DL suspension example (-14).
- Test vectors: binary display only (-14), still `2^20` entries init, C.1 1-bit, C.2 2-bit, C.3 4-bit, C.4 8-bit (same examples `eNrbuRgAAhcBXQ`, `eNo76fITAAPfAgc` in both).
- Size appendix B: numbers identical in -11 and -21 (verified); Status List 10–100× smaller than UUID list; e.g. 1M @0.1% 2.2KB vs 16.4KB; @1% 13.7KB vs 157.7KB; @50% 122.1KB vs 7.6MB.

## 6. Version-by-Version (from Document History)

- **-12:** EKU re-use, Paul affiliation, Dan Moore feedback, JSON object-only, IANA desc clarifications, split Linkability/Lifecycle, relax Accept MUST→SHOULD.
- **-13:** Client term, exp/ttl RECOMMENDED fix, redirect+ttl security note, CORS version pin, KYC explain, link guidance to exp/ttl, RFC7515 ref, CWT raw note, unique-URI privacy.
- **-14:** binary test vectors, remove padding-byte graphic, remove `0x0B`, re-emphasize expired+VALID=expired, rename aggregation section, restructure COSE referenced token, add ASN.1, genart nits, remove cose_sign1 tag from examples, remove DL example.
- **-15:** limit CWT to Sign1/Mac0, tagging explicit, EKU desc field, typo fixes, IANA refs informative, remove unused ref.
- **-16:** history codes/query wording, grammar, SHOULDs non-normative, intro fixes, RFC9110 negotiation, redirect handling, media contact, collusion text, MUST reject OOB idx, remove mdoc examples.
- **-17:** SD-JWT VC → SD-JWT ref, clarify no status validation if Referenced Token invalid.
- **-18:** add SD-JWT VC + SD-CWT refs.
- **-19:** ASCII graphics, grammar/nits, ISO 18013-5 link.
- **-20:** extend IANA registry requirements.
- **-21:** editorial (line width, code block types). No normative change from -20; -20 already IESG-approved as Proposed Standard.

## 7. Action for This Repo

- Keep `draft-ietf-oauth-status-list-11/` as archive (done).
- Use `draft-ietf-oauth-status-list-21/TOKEN_STATUS_LIST_SPEC_SUMMARY.md` as current (done).
- If you have code: check CWT tag handling, `404` vs `406`, `0x0B` rejection, validation order, `exp`/`ttl` defaults, EKU OID string.
