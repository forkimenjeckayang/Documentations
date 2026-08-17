#!/usr/bin/env bash

# Prepare the wallet CloudFront distribution in the target AWS account.
#
# Architecture:
#   authoritative sandbox Route 53 -> target CloudFront -> private target S3
#
# This is a preparation script, not a production-cutover script. It creates or
# reuses target resources and DNS ownership proof, but does not move the production
# wallet domain or modify the source distribution. This allows testing first and
# keeps the source available for rollback.
#
# Run with --dry-run first, review the private log under .migration-logs/, and then
# run without --dry-run to apply the preparation changes.

set -Eeuo pipefail

# Expected endpoints. Environment overrides are supported, while the account
# checks prevent accidental changes in an unexpected AWS account.

readonly TARGET_ACCOUNT_ID="${TARGET_ACCOUNT_ID:-982081049921}"
readonly TARGET_PROFILE="${TARGET_PROFILE:-default}"
readonly TARGET_REGION="${TARGET_REGION:-eu-central-1}"
readonly TARGET_BUCKET="${TARGET_BUCKET:-wallet-react-app-main}"
readonly OAC_NAME="${OAC_NAME:-wallet-react-app-main-oac}"
readonly DISTRIBUTION_COMMENT="${DISTRIBUTION_COMMENT:-wallet-react-app-main migration distribution}"
readonly CACHE_POLICY_ID="${CACHE_POLICY_ID:-658327ea-f89d-4fab-a63d-7e88639e58f6}"
readonly CALLER_REFERENCE="${CALLER_REFERENCE:-wallet-react-app-main-982081049921-v1}"
readonly CERTIFICATE_REGION="${CERTIFICATE_REGION:-us-east-1}"
readonly CERTIFICATE_DOMAIN="${CERTIFICATE_DOMAIN:-*.solutions.adorsys.com}"
readonly SOURCE_ACCOUNT_ID="${SOURCE_ACCOUNT_ID:-917848404243}"
readonly SOURCE_PROFILE="${SOURCE_PROFILE:-sandbox}"
readonly SOURCE_DISTRIBUTION_ID="${SOURCE_DISTRIBUTION_ID:-E32T5I17KDIDEL}"

# DNS remains in the sandbox because this zone is publicly authoritative. Route 53
# can still point to CloudFront in the target account.
readonly HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-Z02911502N07V5SNAMLHL}"
readonly HOSTED_ZONE_NAME="${HOSTED_ZONE_NAME:-solutions.adorsys.com.}"
readonly WALLET_DOMAIN="${WALLET_DOMAIN:-wallet.solutions.adorsys.com}"

# The wildcard supports target testing while the more-specific production alias
# remains attached to the source distribution.
readonly WILDCARD_ALIAS="${WILDCARD_ALIAS:-*.solutions.adorsys.com}"

# This TXT proves cross-account domain control to CloudFront. It is not an ACM
# validation record and does not carry application traffic.
readonly OWNERSHIP_TXT_NAME="${OWNERSHIP_TXT_NAME:-_wallet.solutions.adorsys.com.}"

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG_DIR="${MIGRATION_LOG_DIR:-$REPO_ROOT/.migration-logs}"
readonly ORIGIN_DOMAIN="$TARGET_BUCKET.s3.$TARGET_REGION.amazonaws.com"
readonly ORIGIN_ID="$TARGET_BUCKET-s3-origin"

DRY_RUN=false
WORK_DIR=""
LOG_FILE=""
OAC_ID=""
DISTRIBUTION_ID=""
DISTRIBUTION_DOMAIN=""
DISTRIBUTION_STATUS=""
CERTIFICATE_ARN=""
DNS_CHANGE_COUNT=0
ALIAS_STATE=""
TARGET_ALIAS_DISTRIBUTION_ID=""

usage() {
  cat <<'EOF'
Usage: scripts/create-wallet-cloudfront.sh [--dry-run]

Idempotently prepares the target-account CloudFront OAC and wallet distribution
for the private wallet-react-app-main S3 bucket.

The target distribution receives the temporary wildcard alias
*.solutions.adorsys.com and the issued target-account ACM certificate from
us-east-1. After creation, the script creates or verifies the cross-account
ownership TXT record in the authoritative sandbox Route 53 zone.

It does not move wallet.solutions.adorsys.com, change its production A record, or
modify the source distribution. It accepts both the preparation state (exact alias
on source) and completed-cutover state (exact alias on the matching target).

Options:
  --dry-run  Perform read-only checks and report CREATE or REUSE actions.
  -h, --help Show this help text.

Optional environment overrides:
  TARGET_PROFILE, TARGET_ACCOUNT_ID, TARGET_REGION, TARGET_BUCKET,
  OAC_NAME, DISTRIBUTION_COMMENT, CACHE_POLICY_ID, CALLER_REFERENCE,
  CERTIFICATE_REGION, CERTIFICATE_DOMAIN, SOURCE_PROFILE, SOURCE_ACCOUNT_ID,
  SOURCE_DISTRIBUTION_ID, HOSTED_ZONE_ID, HOSTED_ZONE_NAME, WALLET_DOMAIN,
  WILDCARD_ALIAS, OWNERSHIP_TXT_NAME, MIGRATION_LOG_DIR
EOF
}

log() {
  printf '[cloudfront-migration] %s\n' "$*"
}

die() {
  printf '[cloudfront-migration] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
    rm -rf -- "$WORK_DIR"
  fi
}

trap cleanup EXIT

while (($# > 0)); do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

initialize_logging() {
  local mode="run"
  local timestamp

  if [[ "$DRY_RUN" == true ]]; then
    mode="dry-run"
  fi

  # Logs can contain AWS identifiers, so use private permissions. The repository
  # excludes .migration-logs/ from Git.
  mkdir -p -- "$LOG_DIR"
  chmod 700 "$LOG_DIR"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  LOG_FILE="$LOG_DIR/cloudfront-creation-$mode-$timestamp-$$.log"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
  exec > >(tee -a -- "$LOG_FILE") 2>&1
  log "Log file: $LOG_FILE"
}

verify_target_account() {
  local actual_account

  actual_account="$(aws sts get-caller-identity \
    --profile "$TARGET_PROFILE" \
    --query Account \
    --output text)"

  [[ "$actual_account" == "$TARGET_ACCOUNT_ID" ]] ||
    die "Profile '$TARGET_PROFILE' resolves to $actual_account, expected $TARGET_ACCOUNT_ID"

  log "Verified target account $actual_account using profile $TARGET_PROFILE"
}

verify_source_account() {
  local actual_account

  actual_account="$(aws sts get-caller-identity \
    --profile "$SOURCE_PROFILE" \
    --query Account \
    --output text)"

  [[ "$actual_account" == "$SOURCE_ACCOUNT_ID" ]] ||
    die "Profile '$SOURCE_PROFILE' resolves to $actual_account, expected $SOURCE_ACCOUNT_ID"

  log "Verified source account $actual_account using profile $SOURCE_PROFILE"
}

verify_authoritative_zone() {
  local zone
  local zone_name
  local -a route53_name_servers=()
  local -a public_name_servers=()

  zone="$(aws route53 get-hosted-zone \
    --profile "$SOURCE_PROFILE" \
    --id "$HOSTED_ZONE_ID")"
  zone_name="$(jq -r '.HostedZone.Name' <<<"$zone")"

  [[ "$zone_name" == "$HOSTED_ZONE_NAME" ]] ||
    die "Hosted zone '$HOSTED_ZONE_ID' is '$zone_name', expected '$HOSTED_ZONE_NAME'"
  [[ "$(jq -r '.HostedZone.Config.PrivateZone' <<<"$zone")" == "false" ]] ||
    die "Hosted zone '$HOSTED_ZONE_ID' is private"

  # A hosted zone may exist without public delegation. Confirm that this zone's
  # name servers match public DNS before writing the ownership TXT.
  mapfile -t route53_name_servers < <(jq -r '.DelegationSet.NameServers[]' <<<"$zone" | sort)
  mapfile -t public_name_servers < <(dig +short NS "${HOSTED_ZONE_NAME%.}" | sed 's/\.$//' | sort)

  ((${#public_name_servers[@]} > 0)) ||
    die "No public name servers resolve for '${HOSTED_ZONE_NAME%.}'"
  [[ "$(printf '%s\n' "${route53_name_servers[@]}")" == "$(printf '%s\n' "${public_name_servers[@]}")" ]] ||
    die "Hosted zone '$HOSTED_ZONE_ID' is not publicly authoritative"

  log "Verified authoritative public zone $HOSTED_ZONE_ID using profile $SOURCE_PROFILE"
}

verify_source_alias_state() {
  local source_distributions
  local target_distributions
  local -a source_exact_matches=()
  local -a source_wildcard_matches=()
  local -a target_exact_matches=()

  source_distributions="$(aws cloudfront list-distributions \
    --profile "$SOURCE_PROFILE" \
    --output json)"
  target_distributions="$(aws cloudfront list-distributions \
    --profile "$TARGET_PROFILE" \
    --output json)"

  mapfile -t source_exact_matches < <(
    jq -r --arg alias "$WALLET_DOMAIN" '
      .DistributionList.Items[]? |
      select(any(.Aliases.Items[]?; . == $alias)) |
      .Id
    ' <<<"$source_distributions"
  )
  mapfile -t source_wildcard_matches < <(
    jq -r --arg alias "$WILDCARD_ALIAS" '
      .DistributionList.Items[]? |
      select(any(.Aliases.Items[]?; . == $alias)) |
      .Id
    ' <<<"$source_distributions"
  )
  mapfile -t target_exact_matches < <(
    jq -r --arg alias "$WALLET_DOMAIN" '
      .DistributionList.Items[]? |
      select(any(.Aliases.Items[]?; . == $alias)) |
      .Id
    ' <<<"$target_distributions"
  )

  ((${#source_wildcard_matches[@]} == 0)) ||
    die "Source account uses conflicting wildcard alias '$WILDCARD_ALIAS' on: ${source_wildcard_matches[*]}"

  if ((${#source_exact_matches[@]} == 1)); then
    [[ "${source_exact_matches[0]}" == "$SOURCE_DISTRIBUTION_ID" ]] ||
      die "Alias '$WALLET_DOMAIN' is on source distribution '${source_exact_matches[0]}', expected '$SOURCE_DISTRIBUTION_ID'"
    ((${#target_exact_matches[@]} == 0)) ||
      die "Alias '$WALLET_DOMAIN' unexpectedly appears in both accounts; target matches: ${target_exact_matches[*]}"

    ALIAS_STATE="pre-cutover"
    log "Verified pre-cutover state: production alias remains on source distribution $SOURCE_DISTRIBUTION_ID"
  elif ((${#source_exact_matches[@]} == 0)); then
    ((${#target_exact_matches[@]} == 1)) ||
      die "Alias '$WALLET_DOMAIN' is absent from source and expected on exactly one target distribution; found: ${target_exact_matches[*]:-none}"

    TARGET_ALIAS_DISTRIBUTION_ID="${target_exact_matches[0]}"
    ALIAS_STATE="post-cutover"
    log "Verified post-cutover state: production alias is absent from source and present on target distribution $TARGET_ALIAS_DISTRIBUTION_ID"
  else
    die "Alias '$WALLET_DOMAIN' appears on multiple source distributions: ${source_exact_matches[*]}"
  fi

  log "Verified source account has no conflicting wildcard alias $WILDCARD_ALIAS"
}

find_issued_certificate() {
  local certificates
  local -a matches=()

  # CloudFront requires its ACM certificate in us-east-1. The eu-central-1
  # certificate is separate and is used by regional Application Load Balancers.
  [[ "$CERTIFICATE_REGION" == "us-east-1" ]] ||
    die "CloudFront certificate Region must be us-east-1, not $CERTIFICATE_REGION"

  certificates="$(aws acm list-certificates \
    --profile "$TARGET_PROFILE" \
    --region "$CERTIFICATE_REGION" \
    --certificate-statuses ISSUED \
    --output json)"

  mapfile -t matches < <(
    jq -r --arg domain "$CERTIFICATE_DOMAIN" '
      .CertificateSummaryList[]? |
      select(.DomainName == $domain) |
      .CertificateArn
    ' <<<"$certificates"
  )

  if ((${#matches[@]} == 0)); then
    die "No ISSUED certificate for '$CERTIFICATE_DOMAIN' exists in target $CERTIFICATE_REGION; run scripts/prepare-target-certificates.sh first"
  fi
  if ((${#matches[@]} > 1)); then
    die "Multiple ISSUED certificates exist for '$CERTIFICATE_DOMAIN' in $CERTIFICATE_REGION: ${matches[*]}"
  fi

  CERTIFICATE_ARN="${matches[0]}"
  [[ "$CERTIFICATE_ARN" == "arn:aws:acm:us-east-1:$TARGET_ACCOUNT_ID:certificate/"* ]] ||
    die "Certificate ARN is not in the expected target account and CloudFront Region: $CERTIFICATE_ARN"
  log "Verified issued CloudFront certificate $CERTIFICATE_ARN"
}

verify_target_bucket() {
  local bucket_region
  local public_access

  aws s3api head-bucket \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$TARGET_BUCKET" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID" >/dev/null

  bucket_region="$(aws s3api get-bucket-location \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$TARGET_BUCKET" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID" \
    --query LocationConstraint \
    --output text)"

  if [[ "$bucket_region" == "None" ]]; then
    bucket_region="us-east-1"
  fi

  [[ "$bucket_region" == "$TARGET_REGION" ]] ||
    die "Bucket '$TARGET_BUCKET' is in $bucket_region, expected $TARGET_REGION"

  public_access="$(aws s3api get-public-access-block \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$TARGET_BUCKET" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID")"

  # S3 stays private. migrate-s3-buckets.sh later grants access only to this
  # CloudFront distribution through an OAC-scoped bucket policy.
  jq -e '
    .PublicAccessBlockConfiguration |
    .BlockPublicAcls == true and
    .IgnorePublicAcls == true and
    .BlockPublicPolicy == true and
    .RestrictPublicBuckets == true
  ' <<<"$public_access" >/dev/null ||
    die "Bucket '$TARGET_BUCKET' is not configured with all public-access blocks enabled"

  log "Verified private target bucket s3://$TARGET_BUCKET in $TARGET_REGION"
}


verify_ownership_txt_available() {
  local record_sets
  local count

  record_sets="$(aws route53 list-resource-record-sets \
    --profile "$SOURCE_PROFILE" \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --output json)"
  count="$(jq --arg name "$OWNERSHIP_TXT_NAME" '
    [.ResourceRecordSets[]? | select(.Name == $name and .Type == "TXT")] | length
  ' <<<"$record_sets")"

  [[ "$count" -eq 0 ]] ||
    die "Ownership TXT '$OWNERSHIP_TXT_NAME' already exists but no target wallet distribution exists; refusing to create resources until the stale or intentional record is reviewed"

  log "Verified ownership TXT name $OWNERSHIP_TXT_NAME is available"
}

ensure_ownership_txt() {
  local record_sets
  local record_set
  local expected_value
  local change_file
  local change_id

  [[ -n "$DISTRIBUTION_DOMAIN" ]] || die "Cannot manage ownership TXT without a target distribution domain"
  expected_value="\"$DISTRIBUTION_DOMAIN\""

  record_sets="$(aws route53 list-resource-record-sets \
    --profile "$SOURCE_PROFILE" \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --output json)"
  record_set="$(jq -c --arg name "$OWNERSHIP_TXT_NAME" '
    [.ResourceRecordSets[]? | select(.Name == $name and .Type == "TXT")]
  ' <<<"$record_sets")"

  if [[ "$(jq 'length' <<<"$record_set")" -gt 1 ]]; then
    die "Multiple TXT record sets unexpectedly match '$OWNERSHIP_TXT_NAME'"
  fi

  # Reuse an exact value, but never overwrite a TXT owned by something else.
  if [[ "$(jq 'length' <<<"$record_set")" -eq 1 ]]; then
    if jq -e --arg value "$expected_value" '.[0].ResourceRecords | any(.Value == $value)' <<<"$record_set" >/dev/null; then
      log "Verified ownership TXT $OWNERSHIP_TXT_NAME -> $DISTRIBUTION_DOMAIN"
      return
    fi
    die "Ownership TXT '$OWNERSHIP_TXT_NAME' exists with a different value; refusing to overwrite it"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log "Dry-run action: CREATE $OWNERSHIP_TXT_NAME TXT $DISTRIBUTION_DOMAIN in zone $HOSTED_ZONE_ID"
    return
  fi

  change_file="$WORK_DIR/ownership-txt-change.json"
  jq -n \
    --arg name "$OWNERSHIP_TXT_NAME" \
    --arg value "$expected_value" \
    --arg comment "CloudFront cross-account ownership proof for $WALLET_DOMAIN" '
    {
      Comment: $comment,
      Changes: [{
        Action: "CREATE",
        ResourceRecordSet: {
          Name: $name,
          Type: "TXT",
          TTL: 300,
          ResourceRecords: [{Value: $value}]
        }
      }]
    }' >"$change_file"

  change_id="$(aws route53 change-resource-record-sets \
    --profile "$SOURCE_PROFILE" \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "file://$change_file" \
    --query ChangeInfo.Id \
    --output text)"
  aws route53 wait resource-record-sets-changed \
    --profile "$SOURCE_PROFILE" \
    --id "$change_id"

  ((DNS_CHANGE_COUNT += 1))
  log "Created ownership TXT $OWNERSHIP_TXT_NAME -> $DISTRIBUTION_DOMAIN"
}

# The S3 origin identifies an earlier run. Finding and validating it makes this
# preparation idempotent instead of creating duplicate distributions.
find_distribution_by_origin() {
  local distributions
  local -a matches=()

  distributions="$(aws cloudfront list-distributions \
    --profile "$TARGET_PROFILE" \
    --output json)"

  mapfile -t matches < <(
    jq -r --arg domain "$ORIGIN_DOMAIN" '
      .DistributionList.Items[]? |
      select(any(.Origins.Items[]?; .DomainName == $domain)) |
      .Id
    ' <<<"$distributions"
  )

  if ((${#matches[@]} > 1)); then
    die "Multiple target distributions use origin '$ORIGIN_DOMAIN': ${matches[*]}"
  fi

  if ((${#matches[@]} == 1)); then
    DISTRIBUTION_ID="${matches[0]}"
  fi
}

validate_oac() {
  local oac_id="$1"
  local oac

  oac="$(aws cloudfront get-origin-access-control \
    --profile "$TARGET_PROFILE" \
    --id "$oac_id")"

  jq -e '
    .OriginAccessControl.OriginAccessControlConfig |
    .SigningProtocol == "sigv4" and
    .SigningBehavior == "always" and
    .OriginAccessControlOriginType == "s3"
  ' <<<"$oac" >/dev/null ||
    die "OAC '$oac_id' is not configured as S3/SigV4/always-sign"

  OAC_ID="$oac_id"
  log "Verified OAC $OAC_ID"
}

find_named_oac() {
  local oacs
  local -a matches=()

  oacs="$(aws cloudfront list-origin-access-controls \
    --profile "$TARGET_PROFILE" \
    --output json)"

  mapfile -t matches < <(
    jq -r --arg name "$OAC_NAME" '
      .OriginAccessControlList.Items[]? |
      select(.Name == $name) |
      .Id
    ' <<<"$oacs"
  )

  if ((${#matches[@]} > 1)); then
    die "Multiple OACs have the name '$OAC_NAME': ${matches[*]}"
  fi

  if ((${#matches[@]} == 1)); then
    validate_oac "${matches[0]}"
  fi
}

validate_existing_distribution() {
  local distribution
  local associated_oac

  distribution="$(aws cloudfront get-distribution \
    --profile "$TARGET_PROFILE" \
    --id "$DISTRIBUTION_ID")"

  jq -e \
    --arg origin_domain "$ORIGIN_DOMAIN" \
    --arg cache_policy "$CACHE_POLICY_ID" \
    --arg certificate_arn "$CERTIFICATE_ARN" \
    --arg wildcard_alias "$WILDCARD_ALIAS" \
    --arg wallet_domain "$WALLET_DOMAIN" '
      .Distribution.DistributionConfig as $c |
      ($c.DefaultRootObject == "index.html") and
      ($c.Enabled == true) and
      ($c.HttpVersion == "http2" or $c.HttpVersion == "http2and3") and
      ($c.IsIPV6Enabled == true) and
      ($c.DefaultCacheBehavior.ViewerProtocolPolicy == "redirect-to-https") and
      ($c.DefaultCacheBehavior.Compress == true) and
      ($c.DefaultCacheBehavior.CachePolicyId == $cache_policy) and
      ($c.DefaultCacheBehavior.AllowedMethods.Quantity == 2) and
      ($c.ViewerCertificate.ACMCertificateArn == $certificate_arn) and
      ($c.ViewerCertificate.SSLSupportMethod == "sni-only") and
      ($c.ViewerCertificate.MinimumProtocolVersion == "TLSv1.2_2021") and
      (any($c.Aliases.Items[]?; . == $wildcard_alias or . == $wallet_domain)) and
      (any($c.Origins.Items[]?;
        .DomainName == $origin_domain and
        .S3OriginConfig.OriginAccessIdentity == "" and
        (.OriginAccessControlId | length) > 0)) and
      (any($c.CustomErrorResponses.Items[]?;
        .ErrorCode == 403 and .ResponsePagePath == "/index.html" and
        .ResponseCode == "200" and .ErrorCachingMinTTL == 10)) and
      (any($c.CustomErrorResponses.Items[]?;
        .ErrorCode == 404 and .ResponsePagePath == "/index.html" and
        .ResponseCode == "200" and .ErrorCachingMinTTL == 10))
    ' <<<"$distribution" >/dev/null ||
    die "Existing distribution '$DISTRIBUTION_ID' does not match the required wallet behavior"

  associated_oac="$(jq -r --arg domain "$ORIGIN_DOMAIN" '
    .Distribution.DistributionConfig.Origins.Items[] |
    select(.DomainName == $domain) |
    .OriginAccessControlId
  ' <<<"$distribution")"

  [[ -n "$associated_oac" ]] ||
    die "Existing distribution '$DISTRIBUTION_ID' has no OAC on the wallet origin"

  validate_oac "$associated_oac"
  DISTRIBUTION_DOMAIN="$(jq -r '.Distribution.DomainName' <<<"$distribution")"
  DISTRIBUTION_STATUS="$(jq -r '.Distribution.Status' <<<"$distribution")"
  log "Existing matching distribution: $DISTRIBUTION_ID ($DISTRIBUTION_STATUS)"
}

create_oac() {
  local config_file="$WORK_DIR/oac-config.json"
  local result

  # OAC replaces public S3 access: CloudFront signs each origin request with
  # SigV4, and the S3 policy trusts only the target distribution.
  jq -n \
    --arg name "$OAC_NAME" \
    --arg description "Private S3 access for $TARGET_BUCKET" \
    '{
      Name: $name,
      Description: $description,
      SigningProtocol: "sigv4",
      SigningBehavior: "always",
      OriginAccessControlOriginType: "s3"
    }' >"$config_file"

  result="$(aws cloudfront create-origin-access-control \
    --profile "$TARGET_PROFILE" \
    --origin-access-control-config "file://$config_file")"

  OAC_ID="$(jq -r '.OriginAccessControl.Id' <<<"$result")"
  [[ -n "$OAC_ID" && "$OAC_ID" != "null" ]] || die "CloudFront did not return an OAC ID"
  log "Created OAC $OAC_ID ($OAC_NAME)"
}

render_distribution_config() {
  local config_file="$1"

  # Preserve required SPA behavior with a private S3 REST origin. Mapping 403/404
  # to index.html allows browser refreshes on client-side routes.
  jq -n \
    --arg caller_reference "$CALLER_REFERENCE" \
    --arg origin_id "$ORIGIN_ID" \
    --arg origin_domain "$ORIGIN_DOMAIN" \
    --arg oac_id "$OAC_ID" \
    --arg cache_policy "$CACHE_POLICY_ID" \
    --arg comment "$DISTRIBUTION_COMMENT" \
    --arg certificate_arn "$CERTIFICATE_ARN" \
    --arg wildcard_alias "$WILDCARD_ALIAS" '
    {
      CallerReference: $caller_reference,
      Aliases: {Quantity: 1, Items: [$wildcard_alias]},
      DefaultRootObject: "index.html",
      Origins: {
        Quantity: 1,
        Items: [{
          Id: $origin_id,
          DomainName: $origin_domain,
          OriginPath: "",
          CustomHeaders: {Quantity: 0},
          S3OriginConfig: {
            OriginAccessIdentity: "",
            OriginReadTimeout: 30
          },
          ConnectionAttempts: 3,
          ConnectionTimeout: 10,
          OriginShield: {Enabled: false},
          OriginAccessControlId: $oac_id
        }]
      },
      OriginGroups: {Quantity: 0},
      DefaultCacheBehavior: {
        TargetOriginId: $origin_id,
        TrustedSigners: {Enabled: false, Quantity: 0},
        TrustedKeyGroups: {Enabled: false, Quantity: 0},
        ViewerProtocolPolicy: "redirect-to-https",
        AllowedMethods: {
          Quantity: 2,
          Items: ["HEAD", "GET"],
          CachedMethods: {Quantity: 2, Items: ["HEAD", "GET"]}
        },
        SmoothStreaming: false,
        Compress: true,
        LambdaFunctionAssociations: {Quantity: 0},
        FunctionAssociations: {Quantity: 0},
        FieldLevelEncryptionId: "",
        CachePolicyId: $cache_policy,
        GrpcConfig: {Enabled: false}
      },
      CacheBehaviors: {Quantity: 0},
      CustomErrorResponses: {
        Quantity: 2,
        Items: [
          {
            ErrorCode: 403,
            ResponsePagePath: "/index.html",
            ResponseCode: "200",
            ErrorCachingMinTTL: 10
          },
          {
            ErrorCode: 404,
            ResponsePagePath: "/index.html",
            ResponseCode: "200",
            ErrorCachingMinTTL: 10
          }
        ]
      },
      Comment: $comment,
      Logging: {
        Enabled: false,
        IncludeCookies: false,
        Bucket: "",
        Prefix: ""
      },
      PriceClass: "PriceClass_All",
      Enabled: true,
      ViewerCertificate: {
        CloudFrontDefaultCertificate: false,
        ACMCertificateArn: $certificate_arn,
        SSLSupportMethod: "sni-only",
        MinimumProtocolVersion: "TLSv1.2_2021"
      },
      Restrictions: {
        GeoRestriction: {RestrictionType: "none", Quantity: 0}
      },
      WebACLId: "",
      HttpVersion: "http2",
      IsIPV6Enabled: true,
      ContinuousDeploymentPolicyId: "",
      Staging: false
    }' >"$config_file"
}

create_distribution() {
  local config_file="$WORK_DIR/distribution-config.json"
  local result

  render_distribution_config "$config_file"

  result="$(aws cloudfront create-distribution \
    --profile "$TARGET_PROFILE" \
    --distribution-config "file://$config_file")"

  DISTRIBUTION_ID="$(jq -r '.Distribution.Id' <<<"$result")"
  DISTRIBUTION_DOMAIN="$(jq -r '.Distribution.DomainName' <<<"$result")"
  DISTRIBUTION_STATUS="$(jq -r '.Distribution.Status' <<<"$result")"

  [[ -n "$DISTRIBUTION_ID" && "$DISTRIBUTION_ID" != "null" ]] ||
    die "CloudFront did not return a distribution ID"

  log "Created distribution $DISTRIBUTION_ID ($DISTRIBUTION_STATUS)"
}

print_result() {
  printf '\n'
  log "RESULT"
  printf 'CLOUDFRONT_DISTRIBUTION_ID=%s\n' "$DISTRIBUTION_ID"
  printf 'CLOUDFRONT_DOMAIN=%s\n' "$DISTRIBUTION_DOMAIN"
  printf 'CLOUDFRONT_STATUS=%s\n' "$DISTRIBUTION_STATUS"
  printf 'CLOUDFRONT_PREPARATION_ALIAS=%s\n' "$WILDCARD_ALIAS"
  printf 'OWNERSHIP_TXT=%s -> %s\n' "$OWNERSHIP_TXT_NAME" "$DISTRIBUTION_DOMAIN"
  if [[ "$ALIAS_STATE" == "pre-cutover" ]]; then
    printf '\nNext, validate and apply the S3 OAC policy:\n'
    printf 'scripts/migrate-s3-buckets.sh --dry-run --wallet-cloudfront-distribution-id %q\n' "$DISTRIBUTION_ID"
    printf 'scripts/migrate-s3-buckets.sh --wallet-cloudfront-distribution-id %q\n' "$DISTRIBUTION_ID"
    printf '\nWait for deployment, then create a temporary DNS alias such as\n'
    printf 'wallet-migration.solutions.adorsys.com -> %s and test through that hostname.\n' "$DISTRIBUTION_DOMAIN"
    printf 'aws cloudfront wait distribution-deployed --profile %q --id %q\n' "$TARGET_PROFILE" "$DISTRIBUTION_ID"
    printf '\nProduction is unchanged: %s still belongs to source distribution %s.\n' "$WALLET_DOMAIN" "$SOURCE_DISTRIBUTION_ID"
  else
    printf '\nPost-cutover state verified: %s belongs to target distribution %s.\n' "$WALLET_DOMAIN" "$DISTRIBUTION_ID"
    printf 'No CloudFront alias or production DNS cutover action is required.\n'
    printf 'Optional S3/OAC verification:\n'
    printf 'scripts/migrate-s3-buckets.sh --dry-run --wallet-cloudfront-distribution-id %q\n' "$DISTRIBUTION_ID"
  fi
  log "DNS records created by this run: $DNS_CHANGE_COUNT"
  log "Execution log: $LOG_FILE"
}

main() {
  require_command aws
  require_command date
  require_command dig
  require_command jq
  require_command mapfile
  require_command mktemp
  require_command sed
  require_command sort
  require_command tee

  initialize_logging
  WORK_DIR="$(mktemp -d -t wallet-cloudfront.XXXXXX)"
  chmod 700 "$WORK_DIR"

  # Complete all read-only safety gates before creating or reusing resources.
  # With --dry-run, execution stops before every AWS write.
  verify_target_account
  verify_source_account
  verify_authoritative_zone
  verify_source_alias_state
  find_issued_certificate
  verify_target_bucket
  find_distribution_by_origin

  # After cutover, prove that the exact alias and expected S3 origin belong to
  # the same target distribution before allowing reuse.
  if [[ "$ALIAS_STATE" == "post-cutover" ]]; then
    [[ -n "$DISTRIBUTION_ID" ]] ||
      die "Target alias is on $TARGET_ALIAS_DISTRIBUTION_ID, but no target distribution uses origin '$ORIGIN_DOMAIN'"
    [[ "$DISTRIBUTION_ID" == "$TARGET_ALIAS_DISTRIBUTION_ID" ]] ||
      die "Target alias is on $TARGET_ALIAS_DISTRIBUTION_ID, but wallet origin '$ORIGIN_DOMAIN' is on $DISTRIBUTION_ID"
  fi

  # Validate and reuse a previous matching distribution instead of duplicating it.
  if [[ -n "$DISTRIBUTION_ID" ]]; then
    validate_existing_distribution
    ensure_ownership_txt
    if [[ "$DRY_RUN" == true ]]; then
      log "DRY RUN RESULT: PASS - matching distribution will be reused"
      log "No AWS resources were changed"
    fi
    print_result
    exit 0
  fi

  verify_ownership_txt_available
  find_named_oac

  if [[ "$DRY_RUN" == true ]]; then
    if [[ -n "$OAC_ID" ]]; then
      log "Dry-run action: REUSE OAC $OAC_ID"
    else
      log "Dry-run action: CREATE OAC '$OAC_NAME'"
    fi
    log "Dry-run action: CREATE distribution for $ORIGIN_DOMAIN"
    log "Distribution will use preparation alias $WILDCARD_ALIAS and issued certificate $CERTIFICATE_ARN"
    log "Dry-run action after creation: CREATE or REUSE $OWNERSHIP_TXT_NAME TXT <new-distribution-domain> in authoritative zone $HOSTED_ZONE_ID"
    log "DRY RUN RESULT: PASS - creation preflight succeeded"
    log "No AWS resources, production DNS records, or source distributions were changed"
    log "Review this log before the real run: $LOG_FILE"
    exit 0
  fi

  if [[ -z "$OAC_ID" ]]; then
    create_oac
  fi
  create_distribution
  ensure_ownership_txt
  print_result
}

main
