# DNS Authority and Delegation for `solutions.adorsys.com`

**Purpose:** explain, in plain language, who controls DNS for
`solutions.adorsys.com`, how authority moved from sandbox to target, and how to
verify the current target authority.

**Verified:** 2026-08-26 with public, read-only DNS queries and Route 53 API
calls after the sandbox zone was deleted. Route 53 public hosted zones are global;
the workload Regions
(`eu-north-1` and `eu-central-1`) do not affect DNS authority.

## DNS terms in plain language

DNS is the internet's address book. A person opens a name such as
`wallet.solutions.adorsys.com`; DNS answers with the AWS endpoint that should
receive the request. It does not serve the website or Keycloak itself. It only
directs clients to the service that does.

| Term | Plain-language meaning | Meaning here |
|---|---|---|
| **Domain name** | A human-readable internet name. | `solutions.adorsys.com` is a domain below `adorsys.com`. |
| **DNS zone** | The set of DNS records that one owner manages for a domain or part of a domain. | There is a parent `adorsys.com` zone and separate child `solutions.adorsys.com` zones. |
| **Route 53 hosted zone** | AWS's managed container for one DNS zone and its records. A public hosted zone answers internet DNS requests. | The target account now owns the remaining public hosted zone for this child name. |
| **DNS record** | One entry in a zone, such as an address, alias, text value, or delegation. | The wallet/proxy/Keycloak aliases and ACM validation CNAMEs are records. |
| **Name server (NS)** | A DNS server that can answer questions for a zone. An `NS` record lists those servers. | Each Route 53 hosted zone has four assigned `awsdns-*` name servers. |
| **Authoritative** | The source of truth for a zone. DNS resolvers trust its answers rather than a cached copy. | The target child zone is authoritative because the parent delegates to its four servers. |
| **Parent zone** | The zone one level above another zone. It decides where the child zone is delegated. | `adorsys.com` is the parent of `solutions.adorsys.com`. |
| **Child zone** | A separately managed part of a parent domain. | `solutions.adorsys.com` is the child zone being moved. |
| **Delegation** | The parent creates an `NS` record for the child, telling resolvers where to ask next. | The `solutions.adorsys.com` NS record now refers clients to the target zone. |
| **DNS resolver** | The DNS service used by a laptop, browser, office network, or ISP. It follows DNS delegations and caches results. | It first asks the parent where `solutions.adorsys.com` lives, then asks the delegated child servers. |
| **TTL** | “Time to live”: how long a resolver may cache a DNS answer, in seconds. | `86400` means a delegation can be cached for up to 24 hours. |
| **SOA record** | A zone's administrative record. It identifies the primary name server and timing settings. | Querying it with the `aa` flag proves a server is authoritative for `adorsys.com`. |
| **CNAME / Alias** | A record that directs one DNS name to another endpoint. Route 53 aliases can point to AWS resources. | The child zone directs wallet to CloudFront and proxy/Keycloak to target ALBs. |

### Important distinction: AWS account versus public DNS authority

Both AWS accounts previously contained a Route 53 hosted zone named
`solutions.adorsys.com`. This was allowed, but only the set selected by the parent
was public. The AWS account that owns the **parent** `adorsys.com` zone chooses the
public child zone by publishing its four name servers in the child `NS` record.

The workloads were moved first, then the target zone was copied and verified, and
finally the parent delegation was changed. The sandbox zone was deleted only after
the target delegation and applications were verified.

## The DNS hierarchy

DNS is delegated from a parent zone to a child zone. For this migration, the
chain is:

```text
DNS root (.)
└── .com
    └── adorsys.com                     parent DNS zone
        └── solutions.adorsys.com       child DNS zone
            ├── wallet.solutions.adorsys.com
            ├── proxy.solutions.adorsys.com
            └── keycloak-demo.solutions.adorsys.com
```

The owner of the `adorsys.com` zone controls a special `NS` record named
`solutions.adorsys.com`. That record tells DNS resolvers which name servers
are allowed to answer for every name below `solutions.adorsys.com`.

This is separate from the DNS records within either AWS account. Creating a
hosted zone in the target account does **not** make it public automatically.
The parent delegation must point to it.

### What happens when someone opens a production URL today

For `https://wallet.solutions.adorsys.com/`, a resolver follows this path:

```text
1. Root DNS servers: “ask the .com name servers.”
2. .com name servers: “ask these four Route 53 servers for adorsys.com.”
3. adorsys.com servers: “ask these four target Route 53 servers for solutions.adorsys.com.”
4. Target child-zone servers: “wallet.solutions.adorsys.com points to the target CloudFront distribution.”
5. The browser connects to CloudFront in the target AWS account.
```

The target account now owns both the workloads and the authoritative child zone.
The application URLs did not change during the move.

## Current verified state

| Item | Current value |
|---|---|
| Parent zone | `adorsys.com` |
| Parent authoritative name servers | `ns-345.awsdns-43.com`, `ns-648.awsdns-17.net`, `ns-1035.awsdns-01.org`, `ns-1941.awsdns-50.co.uk` |
| Source/sandbox child hosted zone | `Z02911502N07V5SNAMLHL` — deleted |
| Current delegated child name servers | `ns-380.awsdns-47.com`, `ns-1808.awsdns-34.co.uk`, `ns-920.awsdns-51.net`, `ns-1061.awsdns-04.org` |
| Target child hosted zone | `Z05071841EFF9JQA59TZL` |
| Public authority | Target account `982081049921` |

The parent delegation and public recursive resolvers return the target set. Direct
queries to a target name server return the `aa` authoritative-answer flag.

## Why the target zone is authoritative now

The parent zone's delegation record contains the target name servers:

```text
solutions.adorsys.com. 86400 IN NS ns-380.awsdns-47.com.
solutions.adorsys.com. 86400 IN NS ns-1808.awsdns-34.co.uk.
solutions.adorsys.com. 86400 IN NS ns-920.awsdns-51.net.
solutions.adorsys.com. 86400 IN NS ns-1061.awsdns-04.org.
```

`86400` is the TTL in seconds (24 hours). This record is held in the parent
`adorsys.com` zone, not in either `solutions.adorsys.com` hosted zone.

Therefore public resolvers are referred to the target Route 53 zone for wallet,
proxy, Keycloak, ACM validation, and all other child records.

## Commands to verify the hierarchy

All commands below are read-only and require only `dig`. They can be run from
any machine with public DNS access.

### 1. Trace from the DNS root to `adorsys.com`

```bash
dig +trace NS adorsys.com
```

Expected chain:

```text
.  →  .com name servers  →  the four AWS Route 53 name servers for adorsys.com
```

The final `adorsys.com` response should list:

```text
ns-345.awsdns-43.com.
ns-648.awsdns-17.net.
ns-1035.awsdns-01.org.
ns-1941.awsdns-50.co.uk.
```

### 2. Prove a parent server is authoritative for `adorsys.com`

```bash
dig @ns-345.awsdns-43.com adorsys.com SOA \
  +norecurse +noall +comments +answer
```

Look for the `aa` flag:

```text
flags: qr aa;
```

`aa` means **authoritative answer**. The expected SOA begins with:

```text
adorsys.com. 300 IN SOA ns-1941.awsdns-50.co.uk. awsdns-hostmaster.amazon.com.
```

The SOA's first name server is the Route 53 primary name server named for the
zone. All four `awsdns-*` servers listed above are authoritative servers.

### 3. Read the child-zone delegation from that parent server

```bash
dig @ns-345.awsdns-43.com solutions.adorsys.com NS \
  +norecurse +noall +comments +authority
```

The `AUTHORITY SECTION` is the parent server's referral to the target name
servers. That is direct proof of the current delegation.

To check every parent name server, run:

```bash
for ns in $(dig +short NS adorsys.com); do
  echo "=== $ns ==="
  dig @"$ns" solutions.adorsys.com NS \
    +norecurse +noall +authority
done
```

### 4. Show the target AWS hosted zone and confirm the source is gone

```bash
aws route53 get-hosted-zone \
  --id Z05071841EFF9JQA59TZL \
  --profile default \
  --query '{zone:HostedZone.Name,nameServers:DelegationSet.NameServers}'

aws route53 list-hosted-zones \
  --profile sandbox \
  --query 'HostedZones[?Name==`solutions.adorsys.com.`]'
```

The target command returns its four name servers. The sandbox query now returns an
empty list. These commands inspect AWS resources; the direct parent query remains
the decisive public-authority test.

## Completed authority change

The administrator who controls the authoritative `adorsys.com` hosted zone
replaced the `NS` record named `solutions.adorsys.com`.

Replace all four sandbox values:

```text
ns-4.awsdns-00.com
ns-680.awsdns-21.net
ns-1025.awsdns-00.org
ns-1662.awsdns-15.co.uk
```

with all four target values:

```text
ns-380.awsdns-47.com
ns-1808.awsdns-34.co.uk
ns-920.awsdns-51.net
ns-1061.awsdns-04.org
```

The two sets were not published together. Mixing sandbox and target name servers
would allow different resolvers to receive answers from different hosted zones,
which can produce inconsistent DNS results.

The parent zone may be in a separate central AWS account. Public DNS proves
the server and delegation, but it cannot reveal the owning AWS account. This
is why the change requires the parent DNS administrator and a service-desk
request.

## Cutover result and rollback status

1. Source and target records were made equivalent.
2. The complete sandbox NS set was replaced with the complete target NS set.
3. Parent, public-resolver, and direct target-name-server checks passed.
4. Wallet, proxy, and Keycloak HTTPS checks passed.
5. The sandbox zone and migration-scoped runtime resources were retired.

The DNS rollback to sandbox is now closed because the sandbox hosted zone was
deleted. Recovery must use the target hosted zone and target-account service
recovery procedures.

## Post-change verification

Check the parent delegation directly. It must show only the target set:

```bash
dig @ns-345.awsdns-43.com solutions.adorsys.com NS \
  +norecurse +noall +comments +authority
```

Then check normal public resolution:

```bash
dig +short NS solutions.adorsys.com
dig +short A wallet.solutions.adorsys.com
dig +short A proxy.solutions.adorsys.com
dig +short A keycloak-demo.solutions.adorsys.com

curl -I https://wallet.solutions.adorsys.com/
curl -I https://proxy.solutions.adorsys.com/
curl -I https://keycloak-demo.solutions.adorsys.com/realms/master/.well-known/openid-configuration
```

For this completed migration, the direct parent query and public `NS` query both
return the target four-name-server set. Verification on 2026-08-26 also returned
HTTP 200 for wallet, proxy, and Keycloak OIDC discovery.

## Post-migration target-zone cleanup

Remove these obsolete records after a separately reviewed Route 53 change:

- `wallet-migration.solutions.adorsys.com` CNAME
- `proxy-migration.solutions.adorsys.com` CNAME
- `test-kc.solutions.adorsys.com` CNAME
- `_wallet.solutions.adorsys.com` TXT
- `_f6b7758537e4053cb82aca563f36b245.solutions.adorsys.com` CNAME
- `solutions.adorsys.com` TXT value `hzcqp17swv`

Keep the zone's NS/SOA records, the production `wallet`, `proxy`, and
`keycloak-demo` aliases, and target ACM validation CNAME `_6878...`.

The `_wallet` TXT was required to prove cross-account ownership during the
CloudFront alias move. The target distribution is now deployed with both the
wildcard and exact wallet aliases, and the source distribution is gone, so the
record is no longer part of live request routing. The apex TXT token is also a
removal candidate based on the team's confirmation that the migrated resources do
not use it and the absence of a local project reference. AWS cannot prove whether
an unknown external verifier once used an opaque TXT value; the former value is
therefore retained here for audit and recovery history.
