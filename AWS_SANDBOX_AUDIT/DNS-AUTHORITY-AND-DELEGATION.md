# DNS Authority and Delegation for `solutions.adorsys.com`

**Purpose:** explain, in plain language, who controls DNS for
`solutions.adorsys.com`, why the sandbox account is currently authoritative,
and how to verify and later move that authority to the target AWS account.

**Verified:** 2026-08-19 with public, read-only DNS queries and Route 53 API
calls. Route 53 public hosted zones are global; the workload Regions
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
| **Route 53 hosted zone** | AWS's managed container for one DNS zone and its records. A public hosted zone answers internet DNS requests. | Sandbox and target each have their own public hosted zone for the same child name. |
| **DNS record** | One entry in a zone, such as an address, alias, text value, or delegation. | The wallet/proxy/Keycloak aliases and ACM validation CNAMEs are records. |
| **Name server (NS)** | A DNS server that can answer questions for a zone. An `NS` record lists those servers. | Each Route 53 hosted zone has four assigned `awsdns-*` name servers. |
| **Authoritative** | The source of truth for a zone. DNS resolvers trust its answers rather than a cached copy. | The sandbox child zone is currently authoritative because the parent delegates to its four servers. |
| **Parent zone** | The zone one level above another zone. It decides where the child zone is delegated. | `adorsys.com` is the parent of `solutions.adorsys.com`. |
| **Child zone** | A separately managed part of a parent domain. | `solutions.adorsys.com` is the child zone being moved. |
| **Delegation** | The parent creates an `NS` record for the child, telling resolvers where to ask next. | The `solutions.adorsys.com` NS record currently refers clients to sandbox. |
| **DNS resolver** | The DNS service used by a laptop, browser, office network, or ISP. It follows DNS delegations and caches results. | It first asks the parent where `solutions.adorsys.com` lives, then asks the delegated child servers. |
| **TTL** | “Time to live”: how long a resolver may cache a DNS answer, in seconds. | `86400` means a delegation can be cached for up to 24 hours. |
| **SOA record** | A zone's administrative record. It identifies the primary name server and timing settings. | Querying it with the `aa` flag proves a server is authoritative for `adorsys.com`. |
| **CNAME / Alias** | A record that directs one DNS name to another endpoint. Route 53 aliases can point to AWS resources. | The child zone directs wallet to CloudFront and proxy/Keycloak to target ALBs. |

### Important distinction: AWS account versus public DNS authority

Both AWS accounts can contain a Route 53 hosted zone named
`solutions.adorsys.com`. This is allowed, but only one becomes public at a
time. The AWS account that owns the **parent** `adorsys.com` zone chooses the
public child zone by publishing its four name servers in the child `NS` record.

The workload can run fully in the target account before that delegation
changes. Until it changes, public DNS still obtains the child records from the
sandbox hosted zone. This is why the target zone was copied and verified before
requesting the parent DNS change.

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
3. adorsys.com servers: “ask these four sandbox Route 53 servers for solutions.adorsys.com.”
4. Sandbox child-zone servers: “wallet.solutions.adorsys.com points to the target CloudFront distribution.”
5. The browser connects to CloudFront in the target AWS account.
```

Therefore, a production service can already be served by the target AWS
account while the sandbox account still controls the public `solutions` DNS
zone. The planned change affects step 3 only: it changes the referral from the
sandbox child name servers to the target child name servers. The application
URLs do not change.

## Current verified state

| Item | Current value |
|---|---|
| Parent zone | `adorsys.com` |
| Parent authoritative name servers | `ns-345.awsdns-43.com`, `ns-648.awsdns-17.net`, `ns-1035.awsdns-01.org`, `ns-1941.awsdns-50.co.uk` |
| Source/sandbox child hosted zone | `Z02911502N07V5SNAMLHL` |
| Current delegated child name servers | `ns-4.awsdns-00.com`, `ns-680.awsdns-21.net`, `ns-1025.awsdns-00.org`, `ns-1662.awsdns-15.co.uk` |
| Target child hosted zone | `Z05071841EFF9JQA59TZL` |
| Target name servers to delegate to | `ns-380.awsdns-47.com`, `ns-1808.awsdns-34.co.uk`, `ns-920.awsdns-51.net`, `ns-1061.awsdns-04.org` |

The target hosted zone has already been verified to have full parity with the
sandbox zone for non-`NS`/non-`SOA` records. It is ready, but it is not yet the
public authority.

## Why sandbox is authoritative now

The parent zone's delegation record currently contains the sandbox name
servers:

```text
solutions.adorsys.com. 86400 IN NS ns-1025.awsdns-00.org.
solutions.adorsys.com. 86400 IN NS ns-1662.awsdns-15.co.uk.
solutions.adorsys.com. 86400 IN NS ns-4.awsdns-00.com.
solutions.adorsys.com. 86400 IN NS ns-680.awsdns-21.net.
```

`86400` is the TTL in seconds (24 hours). This record is held in the parent
`adorsys.com` zone, not in either `solutions.adorsys.com` hosted zone.

Therefore public resolvers are referred to the sandbox Route 53 zone for
wallet, proxy, Keycloak, ACM validation CNAMEs, and all other child records.

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

The `AUTHORITY SECTION` is the parent server's referral to the sandbox name
servers. That is direct proof of the current delegation.

To check every parent name server, run:

```bash
for ns in $(dig +short NS adorsys.com); do
  echo "=== $ns ==="
  dig @"$ns" solutions.adorsys.com NS \
    +norecurse +noall +authority
done
```

### 4. Show the name servers assigned to each AWS hosted zone

```bash
aws route53 get-hosted-zone \
  --id Z02911502N07V5SNAMLHL \
  --profile sandbox \
  --query '{zone:HostedZone.Name,nameServers:DelegationSet.NameServers}'

aws route53 get-hosted-zone \
  --id Z05071841EFF9JQA59TZL \
  --profile default \
  --query '{zone:HostedZone.Name,nameServers:DelegationSet.NameServers}'
```

These commands identify the source and target name-server sets. They do not
change public authority; only the parent-zone `NS` record does that.

## Planned authority change

The administrator who controls the authoritative `adorsys.com` hosted zone
must replace the `NS` record named `solutions.adorsys.com`.

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

Never publish both sets together. Mixing sandbox and target name servers
would allow different resolvers to receive answers from different hosted zones,
which can produce inconsistent DNS results.

The parent zone may be in a separate central AWS account. Public DNS proves
the server and delegation, but it cannot reveal the owning AWS account. This
is why the change requires the parent DNS administrator and a service-desk
request.

## Safe cutover and rollback

1. Keep source and target child-zone records identical. This is already
   verified for the migration records.
2. If the parent DNS administrator can, lower the TTL of the child `NS` record
   to `300` seconds and wait for the prior `86400`-second TTL to expire.
3. Replace the complete sandbox NS set with the complete target NS set.
4. Keep both child hosted zones unchanged during propagation and monitoring.
5. Verify the delegation and application HTTPS endpoints.
6. Only after monitoring and explicit approval, retire the sandbox zone and
   source resources.

If a problem occurs before sandbox retirement, restore the four sandbox name
servers at the parent delegation record. Because the records in the sandbox
zone remain in place, this returns public DNS authority to the rollback zone.

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

For a complete migration, the direct parent query and public `NS` query should
both return the target four-name-server set. Public resolver caches may take up
to the old TTL to converge if the TTL was not lowered and allowed to expire
before the replacement.
