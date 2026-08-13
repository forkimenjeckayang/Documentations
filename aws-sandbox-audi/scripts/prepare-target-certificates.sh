#!/usr/bin/env bash

# Prepare the two target-account wildcard certificates required by the migration:
#   eu-central-1 -> regional ALBs for nginx and Keycloak
#   us-east-1    -> the global CloudFront wallet distribution
#
# DNS validation records are written to the sandbox Route 53 zone because it is
# still publicly authoritative for solutions.adorsys.com. Certificates can belong
# to the target account while validation DNS remains in the source account.

set -Eeuo pipefail

readonly SOURCE_ACCOUNT_ID="${SOURCE_ACCOUNT_ID:-917848404243}"
readonly TARGET_ACCOUNT_ID="${TARGET_ACCOUNT_ID:-982081049921}"
readonly SOURCE_PROFILE="${SOURCE_PROFILE:-sandbox}"
readonly TARGET_PROFILE="${TARGET_PROFILE:-default}"
readonly CERTIFICATE_DOMAIN="${CERTIFICATE_DOMAIN:-*.solutions.adorsys.com}"
readonly HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-Z02911502N07V5SNAMLHL}"
readonly HOSTED_ZONE_NAME="${HOSTED_ZONE_NAME:-solutions.adorsys.com.}"

readonly -a CERTIFICATE_REGIONS=("eu-central-1" "us-east-1")
readonly -a CERTIFICATE_PURPOSES=("target ALBs" "CloudFront wallet")
readonly -a IDEMPOTENCY_TOKENS=("targetwildcard202608eucentral1" "targetwildcard202608useast1")

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG_DIR="${MIGRATION_LOG_DIR:-$REPO_ROOT/.migration-logs}"

DRY_RUN=false
LOG_FILE=""
WORK_DIR=""
CREATED_COUNT=0
DNS_CHANGE_COUNT=0
ISSUED_COUNT=0
PENDING_COUNT=0

usage() {
  cat <<'EOF'
Usage: scripts/prepare-target-certificates.sh [--dry-run]

Idempotently prepares both target-account wildcard certificates:

  eu-central-1  Target ALBs for Keycloak and nginx
  us-east-1     CloudFront wallet viewer certificate

It reuses pending/issued certificates, requests missing certificates, and ensures
every ACM validation CNAME exists in the currently authoritative Route 53 zone in
the sandbox account.

Options:
  --dry-run  Perform read-only discovery and print the planned writes.
  -h, --help Show this help text.

Optional environment overrides:
  SOURCE_PROFILE, TARGET_PROFILE, SOURCE_ACCOUNT_ID, TARGET_ACCOUNT_ID,
  CERTIFICATE_DOMAIN, HOSTED_ZONE_ID, HOSTED_ZONE_NAME, MIGRATION_LOG_DIR
EOF
}

log() {
  printf '[target-certificates] %s\n' "$*"
}

die() {
  printf '[target-certificates] ERROR: %s\n' "$*" >&2
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

  # Logs provide the certificate/validation audit trail. Keep them private and
  # excluded from Git under .migration-logs/.
  mkdir -p -- "$LOG_DIR"
  chmod 700 "$LOG_DIR"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  LOG_FILE="$LOG_DIR/target-certificates-$mode-$timestamp-$$.log"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
  exec > >(tee -a -- "$LOG_FILE") 2>&1
  log "Log file: $LOG_FILE"
}

account_for_profile() {
  aws sts get-caller-identity --profile "$1" --query Account --output text
}

verify_accounts() {
  local actual_source
  local actual_target

  actual_source="$(account_for_profile "$SOURCE_PROFILE")"
  actual_target="$(account_for_profile "$TARGET_PROFILE")"

  # Verify both profiles before requesting certificates or changing Route 53.
  [[ "$actual_source" == "$SOURCE_ACCOUNT_ID" ]] ||
    die "Profile '$SOURCE_PROFILE' resolves to $actual_source, expected $SOURCE_ACCOUNT_ID"
  [[ "$actual_target" == "$TARGET_ACCOUNT_ID" ]] ||
    die "Profile '$TARGET_PROFILE' resolves to $actual_target, expected $TARGET_ACCOUNT_ID"

  log "Verified authoritative-DNS account $actual_source and target certificate account $actual_target"
}

verify_authoritative_zone() {
  local zone
  local zone_name
  local -a route53_name_servers=()
  local -a public_name_servers=()

  zone="$(aws route53 get-hosted-zone --profile "$SOURCE_PROFILE" --id "$HOSTED_ZONE_ID")"
  zone_name="$(jq -r '.HostedZone.Name' <<<"$zone")"

  [[ "$zone_name" == "$HOSTED_ZONE_NAME" ]] ||
    die "Hosted zone '$HOSTED_ZONE_ID' is '$zone_name', expected '$HOSTED_ZONE_NAME'"
  [[ "$(jq -r '.HostedZone.Config.PrivateZone' <<<"$zone")" == "false" ]] ||
    die "Hosted zone '$HOSTED_ZONE_ID' is private"

  # A duplicate hosted zone may exist without public delegation. ACM sees only
  # public DNS, so validation must be written to the authoritative zone.
  mapfile -t route53_name_servers < <(jq -r '.DelegationSet.NameServers[]' <<<"$zone" | sort)
  mapfile -t public_name_servers < <(dig +short NS "${HOSTED_ZONE_NAME%.}" | sed 's/\.$//' | sort)

  ((${#public_name_servers[@]} > 0)) ||
    die "No public name servers resolve for '${HOSTED_ZONE_NAME%.}'"
  [[ "$(printf '%s\n' "${route53_name_servers[@]}")" == "$(printf '%s\n' "${public_name_servers[@]}")" ]] ||
    die "Hosted zone '$HOSTED_ZONE_ID' is not publicly authoritative"

  log "Verified authoritative public zone $HOSTED_ZONE_ID using profile $SOURCE_PROFILE"
}

# Reuse a pending or issued match. Multiple matches are ambiguous, so the script
# stops instead of selecting a certificate unpredictably.
find_certificate() {
  local region="$1"
  local certificates
  local -a matches=()

  certificates="$(aws acm list-certificates \
    --profile "$TARGET_PROFILE" \
    --region "$region" \
    --certificate-statuses PENDING_VALIDATION ISSUED \
    --includes keyTypes=RSA_2048 \
    --output json)"

  mapfile -t matches < <(
    jq -r --arg domain "$CERTIFICATE_DOMAIN" '
      .CertificateSummaryList[]? |
      select(.DomainName == $domain) |
      .CertificateArn
    ' <<<"$certificates"
  )

  if ((${#matches[@]} > 1)); then
    die "Multiple pending/issued certificates exist for '$CERTIFICATE_DOMAIN' in $region: ${matches[*]}"
  fi
  if ((${#matches[@]} == 1)); then
    printf '%s\n' "${matches[0]}"
  fi
}

# Region-specific ACM idempotency tokens protect retries from duplicate requests.
request_certificate() {
  local region="$1"
  local token="$2"

  aws acm request-certificate \
    --profile "$TARGET_PROFILE" \
    --region "$region" \
    --domain-name "$CERTIFICATE_DOMAIN" \
    --validation-method DNS \
    --key-algorithm RSA_2048 \
    --idempotency-token "$token" \
    --options CertificateTransparencyLoggingPreference=ENABLED \
    --query CertificateArn \
    --output text
}

describe_validation() {
  local region="$1"
  local certificate_arn="$2"
  local attempt
  local certificate

  # ACM may take a few seconds after a request to publish its validation CNAME.
  for attempt in {1..12}; do
    certificate="$(aws acm describe-certificate \
      --profile "$TARGET_PROFILE" \
      --region "$region" \
      --certificate-arn "$certificate_arn")"

    if [[ "$(jq -r '.Certificate.Status' <<<"$certificate")" == "ISSUED" ]] ||
      jq -e '.Certificate.DomainValidationOptions[0].ResourceRecord.Name? != null' <<<"$certificate" >/dev/null; then
      printf '%s\n' "$certificate"
      return
    fi
    sleep 5
  done

  die "ACM did not publish validation information for $certificate_arn within 60 seconds"
}

validation_record_state() {
  local name="$1"
  local value="$2"
  local existing
  local existing_name
  local existing_type
  local existing_value

  existing="$(aws route53 list-resource-record-sets \
    --profile "$SOURCE_PROFILE" \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --start-record-name "$name" \
    --start-record-type CNAME \
    --max-items 1)"

  existing_name="$(jq -r '.ResourceRecordSets[0].Name // empty' <<<"$existing")"
  existing_type="$(jq -r '.ResourceRecordSets[0].Type // empty' <<<"$existing")"
  existing_value="$(jq -r '.ResourceRecordSets[0].ResourceRecords[0].Value // empty' <<<"$existing")"

  # Never overwrite a conflicting value; it may validate another AWS resource.
  if [[ "$existing_name" != "$name" ]]; then
    printf 'missing\n'
  elif [[ "$existing_type" == "CNAME" && "$existing_value" == "$value" ]]; then
    printf 'exact\n'
  else
    printf 'conflict:%s:%s\n' "$existing_type" "$existing_value"
  fi
}

create_validation_record() {
  local region="$1"
  local name="$2"
  local value="$3"
  local change_file="$WORK_DIR/validation-$region.json"
  local change_id

  jq -n --arg region "$region" --arg name "$name" --arg value "$value" '
    {
      Comment: ("ACM validation for target wildcard certificate in " + $region),
      Changes: [{
        Action: "CREATE",
        ResourceRecordSet: {
          Name: $name,
          Type: "CNAME",
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

  ((DNS_CHANGE_COUNT += 1))
  log "Created authoritative validation CNAME for $region; Route 53 change: $change_id"
}

process_region() {
  local region="$1"
  local purpose="$2"
  local token="$3"
  local certificate_arn
  local certificate
  local status
  local validation_name
  local validation_value
  local record_state

  # Process Regions independently because ACM certificates are regional even
  # though both certificates cover the same wildcard domain.
  certificate_arn="$(find_certificate "$region")"

  if [[ -z "$certificate_arn" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      log "$region ($purpose): REQUEST '$CERTIFICATE_DOMAIN'; then create its authoritative validation CNAME"
      return
    fi
    certificate_arn="$(request_certificate "$region" "$token")"
    [[ -n "$certificate_arn" && "$certificate_arn" != "None" ]] ||
      die "ACM did not return a certificate ARN for $region"
    ((CREATED_COUNT += 1))
    log "$region ($purpose): requested $certificate_arn"
  else
    log "$region ($purpose): reusing $certificate_arn"
  fi

  certificate="$(describe_validation "$region" "$certificate_arn")"
  status="$(jq -r '.Certificate.Status' <<<"$certificate")"
  validation_name="$(jq -r '.Certificate.DomainValidationOptions[0].ResourceRecord.Name // empty' <<<"$certificate")"
  validation_value="$(jq -r '.Certificate.DomainValidationOptions[0].ResourceRecord.Value // empty' <<<"$certificate")"

  [[ "$status" == "PENDING_VALIDATION" || "$status" == "ISSUED" ]] ||
    die "$region certificate has unexpected status $status"
  [[ -n "$validation_name" && -n "$validation_value" ]] ||
    die "$region certificate has no DNS validation record"

  record_state="$(validation_record_state "$validation_name" "$validation_value")"
  case "$record_state" in
    exact)
      log "$region: authoritative validation CNAME is already correct"
      ;;
    missing)
      if [[ "$DRY_RUN" == true ]]; then
        log "$region: CREATE $validation_name CNAME $validation_value in zone $HOSTED_ZONE_ID"
      else
        create_validation_record "$region" "$validation_name" "$validation_value"
      fi
      ;;
    conflict:*)
      die "$region validation name '$validation_name' already has a conflicting record: ${record_state#conflict:}"
      ;;
  esac

  if [[ "$status" == "ISSUED" ]]; then
    ((ISSUED_COUNT += 1))
  else
    ((PENDING_COUNT += 1))
  fi

  printf 'TARGET_CERTIFICATE_REGION=%s\n' "$region"
  printf 'TARGET_CERTIFICATE_PURPOSE=%s\n' "$purpose"
  printf 'TARGET_CERTIFICATE_ARN=%s\n' "$certificate_arn"
  printf 'TARGET_CERTIFICATE_STATUS=%s\n' "$status"
  printf 'VALIDATION_NAME=%s\n' "$validation_name"
  printf 'VALIDATION_VALUE=%s\n' "$validation_value"
}

main() {
  local index

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
  WORK_DIR="$(mktemp -d -t target-certificates.XXXXXX)"
  chmod 700 "$WORK_DIR"

  verify_accounts
  verify_authoritative_zone

  for index in "${!CERTIFICATE_REGIONS[@]}"; do
    printf '\n'
    process_region \
      "${CERTIFICATE_REGIONS[$index]}" \
      "${CERTIFICATE_PURPOSES[$index]}" \
      "${IDEMPOTENCY_TOKENS[$index]}"
  done

  printf '\n'
  # Dry-run performs discovery only and makes no ACM or Route 53 changes.
  if [[ "$DRY_RUN" == true ]]; then
    log "DRY RUN RESULT: PASS - both target certificate plans are valid"
    log "No AWS resources were changed"
  else
    log "RESULT: requested=$CREATED_COUNT dns-records-created=$DNS_CHANGE_COUNT issued=$ISSUED_COUNT pending=$PENDING_COUNT"
    if ((PENDING_COUNT > 0)); then
      log "Re-run this script until both certificates report ISSUED"
    else
      log "Both target certificates are ISSUED"
      printf '\nNext migration steps:\n'
      printf 'scripts/create-wallet-cloudfront.sh --dry-run\n'
      printf 'scripts/create-wallet-cloudfront.sh\n'
      printf '\nThen use the printed distribution ID with:\n'
      printf 'scripts/migrate-s3-buckets.sh --dry-run --wallet-cloudfront-distribution-id <target-distribution-id>\n'
      printf 'scripts/migrate-s3-buckets.sh --wallet-cloudfront-distribution-id <target-distribution-id>\n'
    fi
  fi
  log "Log file: $LOG_FILE"
}

main
