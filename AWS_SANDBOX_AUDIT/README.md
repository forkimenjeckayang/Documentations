# AWS Sandbox Migration Documentation

**Source account:** `917848404243` (profile `sandbox`)  
**Source workload Region:** `eu-north-1`  
**Target account:** `982081049921` (profile `default`)  
**Target workload Region:** `eu-central-1`  
**Last live source audit:** 2026-08-26 using read-only AWS CLI calls

**Last live migration verification:** 2026-08-26 after source retirement,
authoritative DNS cutover, public HTTPS/OIDC checks, and target health checks

This repository records the completed migration of the legacy wallet, nginx proxy,
and Keycloak workloads from the sandbox account to the target account. The target
uses its existing networking; no VPC was created or migrated.

## Documentation

Only three top-level documents are authoritative:

1. **README.md** — current state, evidence, quick verification, and script index.
2. **[MIGRATION-PLAN.md](MIGRATION-PLAN.md)** — migration design, dependencies,
   order, rollback, and completion criteria.
3. **[WORKFLOW-FREE-MIGRATION-RUNBOOK.md](WORKFLOW-FREE-MIGRATION-RUNBOOK.md)** —
   command-level migration procedures without repository workflows, including S3,
   CloudFront, ACM/DNS, EC2/PostgreSQL, ECR, and ECS.

Superseded snapshots remain under [archive](archive/README.md) for traceability and
must not be used as the current runbook.

For an approachable explanation of the ECS/Fargate architecture used by the
nginx migration, see the separate
[Understanding Amazon ECS on Fargate: components, workflow, and HTTPS setup](../ECS-FARGATE-HTTPS-GUIDE.md)
guide. It is background material, not a fourth authoritative migration document.

For a plain-language explanation of the parent/child DNS hierarchy, the
current sandbox delegation, and how to verify the later authority cutover, see
[DNS Authority and Delegation for `solutions.adorsys.com`](DNS-AUTHORITY-AND-DELEGATION.md).
It is background material, not an additional authoritative migration document.

Copy-ready repository follow-up work is collected in
[Post-migration GitHub issue drafts](POST-MIGRATION-GITHUB-ISSUES.md). It is an
operational planning artifact, not an additional authoritative runbook.

## Current Legacy-Sandbox State

| Component | Identifier | State verified 2026-08-26 |
|---|---|---|
| Route 53 | `Z02911502N07V5SNAMLHL` | Removed; no `solutions.adorsys.com` zone remains in sandbox |
| RDS | `kc-ssi` | Removed; no RDS DB instances remain in `eu-north-1` |
| Secrets Manager | `verifier-secrets` | Removed; no secrets, including planned deletions, remain in `eu-north-1` |
| EC2 | `Keycloak-demo` | Removed; only unrelated `fifa` remains running |
| ACM | `*.solutions.adorsys.com` | Removed from sandbox `eu-north-1` |
| ECS | `Datev_Wallet/nginx-cors` | Removed; no ECS clusters remain in `eu-north-1` |
| ECR | `nginx_datev_wallet` | Removed |
| S3 | `wallet-react-app`, `wallet-app-metadata` | Removed |
| CloudFront | `E32T5I17KDIDEL` | Removed; unrelated `event-app0` distribution remains |
| ALB/target groups | `corsproxy`, `keycloak-demo-LB` | Removed; no sandbox ALBs or target groups remain in `eu-north-1` |
| AMI/EBS | Keycloak migration source AMI/snapshot/volume | No matching AMI or unattached EBS volume remains |

This table covers the migrated Keycloak/wallet workload, not every resource in the
sandbox account. Unrelated hosted zones, S3 buckets, the `fifa` EC2 instance, its
Elastic IP, and the `event-app0` CloudFront distribution remain outside this scope.
The `adorsys-keycloak-backup-test` bucket, `/ecs/keycloakad` log group, and
`kc_wazuh`/`keycloak-wazuh` repositories are not managed by this team or this
migration. They were not migrated or deleted and are explicitly out of scope.

## Final Verification Evidence and Exceptions

- STS confirmed sandbox account `917848404243` and target account `982081049921`.
- The parent `adorsys.com` delegation and public resolvers return only the target
  zone's four name servers.
- Public wallet, proxy, and Keycloak OIDC discovery checks all returned HTTP 200.
- Target nginx ECS is `1 desired / 1 running / 0 pending`; both target ALB target
  groups report `healthy`.
- Target CloudFront `E1Z7SXTDZF3Z54`, target Keycloak EC2
  `i-006ca4ea5780923de`, target buckets, target certificates, and target ECR
  `nginx_datev_wallet` remain present.
- Source rollback is no longer available because the sandbox zone and runtime
  resources have been retired.

Point-in-time inventory can change. Repeat the checks below before making the
remaining target-zone DNS changes.

## Read-Only Source Verification

```bash
aws sts get-caller-identity --profile sandbox
aws rds describe-db-instances --profile sandbox --region eu-north-1
aws secretsmanager list-secrets --include-planned-deletion --profile sandbox --region eu-north-1
aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running,stopping,stopped --profile sandbox --region eu-north-1
aws acm list-certificates --profile sandbox --region eu-north-1
aws ecs list-clusters --profile sandbox --region eu-north-1
aws ecs describe-services --cluster Datev_Wallet --services nginx-cors --profile sandbox --region eu-north-1
aws ecr describe-repositories --profile sandbox --region eu-north-1
aws elbv2 describe-load-balancers --profile sandbox --region eu-north-1
aws s3api list-buckets --profile sandbox
aws route53 list-hosted-zones --profile sandbox
aws cloudfront list-distributions --profile sandbox
```

Interpretation:

- An empty RDS list confirms no DB instance currently exists in that Region.
- A secret with `DeletedDate` is scheduled for deletion, not fully deleted.
- An empty ECS cluster list confirms no sandbox ECS service remains in the Region.
- An empty ALB list does not prove target groups are gone; query them separately.
- S3 bucket inventory is account-global; distinguish in-scope buckets from
  unrelated account buckets.
- ECR and CloudWatch Logs can remain after ECS deletion and need separate review.

## Migration Scripts

| Script | Purpose |
|---|---|
| [`scripts/migrate-s3-buckets.sh`](scripts/migrate-s3-buckets.sh) | Idempotently create/configure target buckets, copy changed objects, and verify counts and bytes |
| [`scripts/prepare-target-certificates.sh`](scripts/prepare-target-certificates.sh) | Reuse or request target ALB and CloudFront certificates and ensure authoritative validation CNAMEs |
| [`scripts/create-wallet-cloudfront.sh`](scripts/create-wallet-cloudfront.sh) | Idempotently prepare the wallet OAC, wildcard-enabled target distribution, and cross-account ownership TXT without moving production traffic |
| [`scripts/migrate-nginx-proxy.sh`](scripts/migrate-nginx-proxy.sh) | Idempotently copy the nginx image, create/reuse target ECS and a new ALB, test without DNS changes, then perform an explicit cutover or rollback |
| [`scripts/migrate-keycloak-ec2.sh`](scripts/migrate-keycloak-ec2.sh) | Prepare/copy the Keycloak AMI; create/reuse the target foundation; validate/register the manually launched EC2 without changing DNS; then perform an explicit, guarded, idempotent cutover or rollback |
| [`scripts/prepare-route53-zone-migration.sh`](scripts/prepare-route53-zone-migration.sh) | Explicit `--dry-run`, target-only idempotent `--execute`, and direct-name-server `--verify` for hosted-zone authority migration; never changes the parent delegation or source zone |

Use each script's read-only inspection before a mutating mode. For Keycloak, run
`--dry-run` before `--prepare-ami`, and `--target-status` before
`--prepare-target`. Migration logs are written under `.migration-logs/`, use
restrictive permissions, and are excluded by `.gitignore`.
Generated AWS inventory and repository-detection outputs are also ignored because
they may contain task-definition environment data or sensitive AWS metadata.

### Keycloak Migration Order

1. Create, checksum, and copy the PostgreSQL rehearsal backup off the source EC2.
2. Run `migrate-keycloak-ec2.sh --dry-run`.
3. Run `--prepare-ami --execute --backup-confirmed` to create/share the source AMI
   and produce the encrypted target-owned AMI.
4. Run `--target-status`, then `--prepare-target --execute` to create/reuse the
   IAM/SSM profile, security groups, target group, new ALB, and HTTPS listener.
5. Manually launch EC2 with the AMI and exact settings printed by the script,
   including the selected key pair. The script does not launch EC2.
6. Connect through SSM, verify the copied files, restore PostgreSQL, and start
   Keycloak with `./keycloak-ssi.sh setup -d`.
7. Run `--register-target i-... --execute` to register the instance, wait for a
   healthy target, and test HTTPS without changing production DNS.
8. The workload owner accepts the configuration copied through the AMI and the
   restored PostgreSQL backup on the target as the final migration state. If the
   source configuration or database changes before cutover, repeat the relevant
   configuration and/or database transfer.
9. After application approval, run `--cutover --execute`. The script revalidates
   the target and OIDC discovery, saves the current alias, and atomically changes
   DNS. Use `--rollback --execute` only under the documented rollback rules.

## Migration Progress

| Workload | Status |
|---|---|
| Wallet S3 and CloudFront | Complete; production and storage are in target |
| Metadata S3 data/policy | Complete; target bucket and policy remain active |
| Target ACM certificates | Issued in `eu-central-1` and `us-east-1` |
| nginx ECS/ECR/new ALB | Complete; production and healthy target are in target |
| Keycloak EC2/PostgreSQL/new ALB | Complete; nginx now proxies to local target Keycloak `26.6.1`, not the retired sandbox EC2 |
| Route 53 hosted zone | Complete; target zone is authoritative and sandbox zone is removed |
| Sandbox runtime retirement | Complete for the migration-scoped EC2, ECS, ALBs, wallet S3, wallet CloudFront, ACM, RDS, secret, and nginx ECR resources |

## Current Migration Notes

- Target S3 buckets are `wallet-react-app-main` and
  `wallet-app-metadata-main` in `eu-central-1`.
- The wallet target bucket remains private and has an OAC-scoped policy for the
  target CloudFront distribution.
- The metadata target bucket uses its separate `PublicReadGetObject` policy and
  does not use CloudFront.
- The target `eu-central-1` and `us-east-1` wildcard certificates are both
  `ISSUED`. ACM gave both certificates the same validation CNAME because they cover
  the same domain in the same target account.
- The shared target validation CNAME now lives in authoritative target zone
  `Z05071841EFF9JQA59TZL` and must remain for managed renewal of both certificates.
- The parent delegation now lists only the target zone's four name servers. The
  sandbox zone `Z02911502N07V5SNAMLHL` was removed after propagation and service
  verification.
- Target CloudFront distribution `E1Z7SXTDZF3Z54` is deployed with OAC
  `ER4JW7O110RQV`, wildcard alias `*.solutions.adorsys.com`, exact alias
  `wallet.solutions.adorsys.com`, and a publicly resolving ownership TXT.
- Production wallet traffic is verified on target bucket `wallet-react-app-main`;
  direct S3 access remains blocked and source distribution `E32T5I17KDIDEL` owns
  no aliases. CloudFront/S3 cutover completed on 2026-08-12.
- nginx production cutover completed on 2026-08-13. The Route 53 alias for
  `proxy.solutions.adorsys.com` now targets
  `nginx-proxy-migration-1538385164.eu-central-1.elb.amazonaws.com` in the target
  account. Post-cutover checks returned root HTTP 200 and CORS preflight 204;
  target ECS and ALB health are `1/1`. The source service and ALB are removed.
- Keycloak host verification on 2026-08-14 confirmed one unencrypted 100-GiB gp3
  root EBS volume. Docker uses `/var/lib/docker` on that root filesystem, and the
  PostgreSQL volume is `oid4vci-deployment_db_data`. PostgreSQL runs in Docker;
  Keycloak runs on the EC2 host through `./keycloak-ssi.sh setup -d` and connects
  to the published database port `localhost:5433`.
- Keycloak production cutover completed on 2026-08-17. Route 53 now aliases
  `keycloak-demo.solutions.adorsys.com` to
  `keycloak-demo-migration-1394321177.eu-central-1.elb.amazonaws.com` in the target
  account. The change reached `INSYNC`; public OIDC discovery returns the expected
  production issuer, and target EC2 `i-006ca4ea5780923de` remains healthy.
- Final inspection found that the migrated target EC2's copied Nginx configuration
  still forwarded to the sandbox public IP. On 2026-08-25 the upstream was changed
  to `https://127.0.0.1:8443`; production now serves local target Keycloak `26.6.1`
  and its local PostgreSQL database.

## Target DNS Cleanup After Migration

The authoritative target zone currently has 12 records. Remove the following six
records only through a separately reviewed Route 53 change:

| Record | Why it can be removed |
|---|---|
| `wallet-migration.solutions.adorsys.com` CNAME | Temporary CloudFront test name; production uses `wallet` |
| `proxy-migration.solutions.adorsys.com` CNAME | Temporary nginx ALB test name; production uses `proxy` |
| `test-kc.solutions.adorsys.com` CNAME | Temporary Keycloak 26.7.2 sandbox test name; its sandbox ALB is gone |
| `_wallet.solutions.adorsys.com` TXT | Cross-account CloudFront move proof; the target distribution is deployed, owns the wallet aliases, and the source distribution is gone |
| `_f6b7758537e4053cb82aca563f36b245.solutions.adorsys.com` CNAME | Source ACM validation record; no sandbox `*.solutions.adorsys.com` certificate remains |
| `solutions.adorsys.com` TXT `hzcqp17swv` | Copied legacy token; based on the team's confirmation, no migrated AWS resource uses it, and no local project reference was found |

Keep the zone's NS/SOA records, the three production aliases, and
`_6878d810540ccb0bc9697193272cc087.solutions.adorsys.com`, which validates both
target certificates.

After removing `_wallet`, do not rerun `create-wallet-cloudfront.sh` as an
operational maintenance command. It is a completed migration-preparation script
tied to the deleted source zone and will fail its source-zone safety checks. Its
failure does not affect the existing target distribution.

The migration is operationally complete. Remaining work is the six-record target
DNS cleanup above. The unrelated sandbox resources are outside this migration and
must not be changed through this cleanup.
