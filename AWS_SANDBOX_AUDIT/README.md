# AWS Sandbox Migration Documentation

**Source account:** `917848404243` (profile `sandbox`)  
**Source workload Region:** `eu-north-1`  
**Target account:** `982081049921` (profile `default`)  
**Target workload Region:** `eu-central-1`  
**Last live source audit:** 2026-08-14 using read-only AWS CLI calls

**Last live migration verification:** 2026-08-17 after Keycloak production DNS
cutover, public HTTPS/OIDC verification, and target Route 53 record-parity checks

This repository documents the remaining legacy-sandbox resources and their
migration to the target AWS account. It does not create a new VPC; target resources
must use the networking already available in the target account.

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

Copy-ready repository follow-up work is collected in
[Post-migration GitHub issue drafts](POST-MIGRATION-GITHUB-ISSUES.md). It is an
operational planning artifact, not an additional authoritative runbook.

## Current Legacy-Sandbox State

| Component | Identifier | Last verified state |
|---|---|---|
| RDS | `kc-ssi` | Removed; no RDS DB instances remained in `eu-north-1` |
| Secrets Manager | `verifier-secrets` | Scheduled for deletion; recoverable until its deletion window ends |
| EC2 | `Keycloak-demo` | Running and healthy; hosts Keycloak and containerized PostgreSQL |
| ACM | `*.solutions.adorsys.com` | Source certificates active; target `eu-central-1` and `us-east-1` certificates issued |
| ECS | `Datev_Wallet/nginx-cors` | Active with one desired and one running Fargate task |
| ECR | `kc_wazuh`, `keycloak-wazuh`, `nginx_datev_wallet` | Three repositories remained at the last audit |
| S3 | `wallet-react-app`, `wallet-app-metadata` | Source buckets active; content copied to target `*-main` buckets |
| CloudFront | `E32T5I17KDIDEL` | Source wallet distribution active |
| ALB | `corsproxy`, `keycloak-demo-LB` | Source internet-facing load balancers active |

This table covers the legacy Keycloak/wallet workload, not every resource in the
sandbox account.

## Verification Evidence and Exceptions

- STS confirmed source account `917848404243` during the 2026-08-11 audit.
- RDS returned no DB instances in `eu-north-1`.
- `verifier-secrets` had a deletion timestamp, so “scheduled for deletion” is
  more accurate than “removed” until AWS completes the deletion.
- `Keycloak-demo` (`i-03eac5cc262731ede`, `t3.medium`) was running with both
  instance and system checks passing.
- A separate `fifa` instance existed but was outside the supplied migration scope.
- `Datev_Wallet/nginx-cors` used task definition `cors_proxy:6` and image
  `917848404243.dkr.ecr.eu-north-1.amazonaws.com/nginx_datev_wallet:latest`.
- The last audit found three ECR repositories, not zero. The archived baseline had
  14, so 11 removals are directly evidenced by the repository data.
- The two wallet buckets existed, while 15 other account buckets were outside this
  audit scope.
- The source wildcard ALB certificate was issued and attached to `corsproxy` and
  `keycloak-demo-LB`.

Point-in-time inventory can change. Repeat the checks below before a cutover or
source deletion.

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
```

Interpretation:

- An empty RDS list confirms no DB instance currently exists in that Region.
- A secret with `DeletedDate` is scheduled for deletion, not fully deleted.
- ECS is healthy here when desired and running counts are one and pending is zero.
- Do not remove `nginx_datev_wallet` while the ECS task references it.
- S3 bucket inventory is account-global; distinguish in-scope buckets from
  unrelated account buckets.

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
| Wallet S3 and CloudFront | Migrated; production on target and under monitoring |
| Metadata S3 data/policy | Migrated; consumer URL updates still require confirmation |
| Target ACM certificates | Issued in `eu-central-1` and `us-east-1` |
| nginx ECS/ECR/new ALB | Migrated; production DNS points to target ALB and workload is under monitoring |
| Keycloak EC2/PostgreSQL/new ALB | Migrated; production DNS points to the target ALB, target EC2 and OIDC are healthy, and the workload is under monitoring |
| Route 53 hosted zone | Target record copy and direct-name-server verification complete; sandbox remains authoritative until the parent delegation changes |

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
- The shared validation CNAME was added to the publicly authoritative sandbox
  Route 53 zone. It validated the `eu-central-1` ALB certificate and the separate
  `us-east-1` certificate required by CloudFront.
- Hosted-zone preparation completed on 2026-08-17. Target zone
  `Z05071841EFF9JQA59TZL` now has 11 records and full non-NS/non-SOA parity with
  sandbox zone `Z02911502N07V5SNAMLHL`. Direct queries to the target name servers
  returned answers for wallet, proxy, and Keycloak. Public authority remains on
  the sandbox zone; the parent DNS owner must lower the current 24-hour delegation
  TTL, wait for it to expire, and then delegate to the target name servers.
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
  target ECS and ALB health are `1/1`. The source service remains running for
  rollback during monitoring.
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

Follow the runbook’s validation gates before deleting any source resource.
