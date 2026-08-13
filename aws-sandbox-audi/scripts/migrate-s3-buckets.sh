#!/usr/bin/env bash

# Idempotently copy the wallet buckets from the sandbox to the target account.
# This script never deletes or modifies source objects.
#
# Target access models:
#   wallet-react-app-main     private; CloudFront reads it through OAC
#   wallet-app-metadata-main direct public GetObject access; no CloudFront
#
# Run with --dry-run first. Real reruns compare content, metadata, and tags and
# skip objects that are already identical.

set -Eeuo pipefail

readonly SOURCE_ACCOUNT_ID="${SOURCE_ACCOUNT_ID:-917848404243}"
readonly TARGET_ACCOUNT_ID="${TARGET_ACCOUNT_ID:-982081049921}"
readonly SOURCE_PROFILE="${SOURCE_PROFILE:-sandbox}"
readonly TARGET_PROFILE="${TARGET_PROFILE:-default}"
readonly SOURCE_REGION="${SOURCE_REGION:-eu-north-1}"
readonly TARGET_REGION="${TARGET_REGION:-eu-central-1}"

readonly -a SOURCE_BUCKETS=(
  "wallet-react-app"
  "wallet-app-metadata"
)

readonly -a TARGET_BUCKETS=(
  "wallet-react-app-main"
  "wallet-app-metadata-main"
)

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG_DIR="${MIGRATION_LOG_DIR:-$REPO_ROOT/.migration-logs}"

DRY_RUN=false
MIGRATION_TMP_DIR=""
LOG_FILE=""
WALLET_CLOUDFRONT_DISTRIBUTION_ID="${WALLET_CLOUDFRONT_DISTRIBUTION_ID:-}"
BUCKET_COPIED_COUNT=0
BUCKET_UNCHANGED_COUNT=0
BUCKET_TAGS_UPDATED_COUNT=0
OBJECT_TAGS_CHANGED=false

usage() {
  cat <<'EOF'
Usage: scripts/migrate-s3-buckets.sh [--dry-run]
       [--wallet-cloudfront-distribution-id ID]

Creates and hardens the target S3 buckets, then copies objects from the sandbox
account to the default-profile account without changing source bucket policies.

Options:
  --dry-run  Run read-only preflight checks and print an explicit PASS or error.
  --wallet-cloudfront-distribution-id ID
             Grant the target wallet CloudFront distribution read-only access.
  -h, --help Show this help text.

Optional environment overrides:
  SOURCE_PROFILE, TARGET_PROFILE, SOURCE_REGION, TARGET_REGION,
  SOURCE_ACCOUNT_ID, TARGET_ACCOUNT_ID, MIGRATION_LOG_DIR,
  WALLET_CLOUDFRONT_DISTRIBUTION_ID

The wallet bucket stays private and optionally grants its target CloudFront OAC
read access. The metadata bucket intentionally recreates the source
PublicReadGetObject policy for its target bucket ARN. Unrelated target policy
statements are preserved.
EOF
}

log() {
  printf '[s3-migration] %s\n' "$*"
}

die() {
  printf '[s3-migration] ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${MIGRATION_TMP_DIR:-}" && -d "$MIGRATION_TMP_DIR" ]]; then
    rm -rf -- "$MIGRATION_TMP_DIR"
  fi
}

trap cleanup EXIT

initialize_logging() {
  local mode="run"
  local timestamp

  if [[ "$DRY_RUN" == true ]]; then
    mode="dry-run"
  fi

  # Logs can contain AWS identifiers and object keys. Keep them private and out
  # of Git; .migration-logs/ is listed in the repository's .gitignore.
  mkdir -p -- "$LOG_DIR"
  chmod 700 "$LOG_DIR"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  LOG_FILE="$LOG_DIR/s3-migration-$mode-$timestamp-$$.log"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"

  exec > >(tee -a -- "$LOG_FILE") 2>&1
  log "Log file: $LOG_FILE"
}

while (($# > 0)); do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      ;;
    --wallet-cloudfront-distribution-id)
      (($# >= 2)) || die "Missing value for --wallet-cloudfront-distribution-id"
      WALLET_CLOUDFRONT_DISTRIBUTION_ID="$2"
      shift
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

account_for_profile() {
  aws sts get-caller-identity \
    --profile "$1" \
    --query Account \
    --output text
}

verify_accounts() {
  local actual_source_account
  local actual_target_account

  actual_source_account="$(account_for_profile "$SOURCE_PROFILE")"
  actual_target_account="$(account_for_profile "$TARGET_PROFILE")"

  # Fail before any writes if either profile points to an unexpected account.
  [[ "$actual_source_account" == "$SOURCE_ACCOUNT_ID" ]] ||
    die "Profile '$SOURCE_PROFILE' resolves to $actual_source_account, expected $SOURCE_ACCOUNT_ID"

  [[ "$actual_target_account" == "$TARGET_ACCOUNT_ID" ]] ||
    die "Profile '$TARGET_PROFILE' resolves to $actual_target_account, expected $TARGET_ACCOUNT_ID"

  [[ "$actual_source_account" != "$actual_target_account" ]] ||
    die "Source and target profiles resolve to the same AWS account"
  log "Verified source account $actual_source_account and target account $actual_target_account"
  log "Using source Region $SOURCE_REGION and target Region $TARGET_REGION"
}

verify_source_bucket() {
  local bucket="$1"

  aws s3api head-bucket \
    --profile "$SOURCE_PROFILE" \
    --region "$SOURCE_REGION" \
    --bucket "$bucket" \
    --expected-bucket-owner "$SOURCE_ACCOUNT_ID" >/dev/null
}

target_bucket_is_owned_by_target() {
  local bucket="$1"

  aws s3api head-bucket \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$bucket" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID" >/dev/null 2>&1
}

target_bucket_preflight() {
  local bucket="$1"
  local bucket_region
  local head_output

  # S3 names are global. Reuse only a bucket owned by the expected target
  # account; otherwise confirm that the selected new name is available.
  if target_bucket_is_owned_by_target "$bucket"; then
    bucket_region="$(aws s3api get-bucket-location \
      --profile "$TARGET_PROFILE" \
      --region "$TARGET_REGION" \
      --bucket "$bucket" \
      --expected-bucket-owner "$TARGET_ACCOUNT_ID" \
      --query LocationConstraint \
      --output text)"

    if [[ "$bucket_region" == "None" ]]; then
      bucket_region="us-east-1"
    fi

    [[ "$bucket_region" == "$TARGET_REGION" ]] ||
      die "Target-owned bucket '$bucket' is in $bucket_region, expected $TARGET_REGION"

    log "Target preflight: OWNED by target account in $bucket_region: $bucket"
    return
  fi

  if head_output="$(aws s3api head-bucket \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$bucket" 2>&1)"; then
    die "Bucket '$bucket' is accessible but is not owned by expected target account $TARGET_ACCOUNT_ID"
  fi

  if grep -q '(404)' <<<"$head_output"; then
    log "Target preflight: AVAILABLE in the global namespace: $bucket"
    return
  fi

  die "Bucket '$bucket' is unavailable or its status cannot be confirmed: $head_output"
}

create_target_bucket() {
  local bucket="$1"

  if target_bucket_is_owned_by_target "$bucket"; then
    log "Target bucket already exists and is owned by the target account: $bucket"
    return
  fi

  log "Creating target bucket: $bucket"
  if [[ "$TARGET_REGION" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --profile "$TARGET_PROFILE" \
      --region "$TARGET_REGION" \
      --bucket "$bucket" >/dev/null
  else
    aws s3api create-bucket \
      --profile "$TARGET_PROFILE" \
      --region "$TARGET_REGION" \
      --bucket "$bucket" \
      --create-bucket-configuration "LocationConstraint=$TARGET_REGION" >/dev/null
  fi

  target_bucket_is_owned_by_target "$bucket" ||
    die "Bucket creation did not produce a target-owned bucket: $bucket"
}

harden_target_bucket() {
  local bucket="$1"
  local access_mode="$2"
  local public_access_configuration

  # Public ACLs are blocked for both buckets. Metadata uses a deliberate public
  # bucket policy; wallet application files remain private behind CloudFront.
  case "$access_mode" in
    private)
      public_access_configuration='BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
      ;;
    public-read-policy)
      public_access_configuration='BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false'
      ;;
    *)
      die "Unknown target access mode for '$bucket': $access_mode"
      ;;
  esac

  log "Applying target bucket controls: $bucket ($access_mode)"

  aws s3api put-public-access-block \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$bucket" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID" \
    --public-access-block-configuration "$public_access_configuration"

  aws s3api put-bucket-ownership-controls \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$bucket" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID" \
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'

  aws s3api put-bucket-encryption \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$bucket" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID" \
    --server-side-encryption-configuration \
      'Rules=[{ApplyServerSideEncryptionByDefault={SSEAlgorithm=AES256},BucketKeyEnabled=false}]'

  aws s3api put-bucket-versioning \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$bucket" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID" \
    --versioning-configuration 'Status=Enabled'
}

validate_cloudfront_distribution_for_bucket() {
  local bucket="$1"
  local distribution_id="$2"
  local distribution
  local expected_arn="arn:aws:cloudfront::$TARGET_ACCOUNT_ID:distribution/$distribution_id"

  # Grant access only after proving the distribution belongs to the target
  # account and uses this bucket as an origin.
  [[ "$distribution_id" =~ ^E[A-Z0-9]+$ ]] ||
    die "Invalid CloudFront distribution ID for '$bucket': $distribution_id"

  distribution="$(aws cloudfront get-distribution \
    --profile "$TARGET_PROFILE" \
    --id "$distribution_id")"

  [[ "$(jq -r '.Distribution.ARN' <<<"$distribution")" == "$expected_arn" ]] ||
    die "CloudFront distribution '$distribution_id' is not owned by target account $TARGET_ACCOUNT_ID"

  jq -e --arg origin_prefix "$bucket.s3" '
    [.Distribution.DistributionConfig.Origins.Items[]?.DomainName |
      startswith($origin_prefix)] | any
  ' <<<"$distribution" >/dev/null ||
    die "CloudFront distribution '$distribution_id' has no S3 origin for '$bucket'"

  log "Verified target CloudFront distribution $distribution_id for $bucket"
}

# The generated policy uses SourceArn so only the selected target distribution,
# rather than every CloudFront distribution, can read the wallet bucket.
configure_cloudfront_bucket_policy() {
  local bucket="$1"
  local distribution_id="$2"
  local policy_error_file="$MIGRATION_TMP_DIR/policy-$bucket.err"
  local current_policy
  local desired_statement
  local updated_policy

  if [[ -z "$distribution_id" ]]; then
    log "Bucket policy deferred for $bucket: no target CloudFront distribution ID supplied"
    return
  fi

  validate_cloudfront_distribution_for_bucket "$bucket" "$distribution_id"

  if current_policy="$(aws s3api get-bucket-policy \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$bucket" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID" \
    --query Policy \
    --output text 2>"$policy_error_file")"; then
    :
  elif grep -q 'NoSuchBucketPolicy' "$policy_error_file"; then
    current_policy='{"Version":"2012-10-17","Statement":[]}'
  else
    die "Cannot read target bucket policy for '$bucket': $(<"$policy_error_file")"
  fi

  desired_statement="$(jq -n \
    --arg bucket_arn "arn:aws:s3:::$bucket/*" \
    --arg source_arn "arn:aws:cloudfront::$TARGET_ACCOUNT_ID:distribution/$distribution_id" \
    '{
      Sid: "AllowCloudFrontReadOnlyFromMigration",
      Effect: "Allow",
      Principal: {Service: "cloudfront.amazonaws.com"},
      Action: "s3:GetObject",
      Resource: $bucket_arn,
      Condition: {StringEquals: {"AWS:SourceArn": $source_arn}}
    }')"

  updated_policy="$(jq -c --argjson desired "$desired_statement" '
    .Version = (.Version // "2012-10-17") |
    .Statement = (
      (if ((.Statement // []) | type) == "array"
       then (.Statement // [])
       else [.Statement]
       end |
       map(select(.Sid != "AllowCloudFrontReadOnlyFromMigration"))) + [$desired]
    )
  ' <<<"$current_policy")"

  if [[ "$(jq -S -c . <<<"$current_policy")" == "$(jq -S -c . <<<"$updated_policy")" ]]; then
    log "Bucket policy unchanged: $bucket already grants the requested CloudFront distribution access"
    return
  fi

  aws s3api put-bucket-policy \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$bucket" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID" \
    --policy "$updated_policy"

  log "Applied OAC-restricted CloudFront bucket policy: $bucket -> $distribution_id"
}

# Metadata does not use CloudFront. Its public policy is deliberately limited to
# GetObject on this target bucket's objects.
configure_metadata_public_read_policy() {
  local bucket="$1"
  local policy_error_file="$MIGRATION_TMP_DIR/policy-$bucket.err"
  local current_policy
  local desired_statement
  local updated_policy

  if current_policy="$(aws s3api get-bucket-policy \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$bucket" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID" \
    --query Policy \
    --output text 2>"$policy_error_file")"; then
    :
  elif grep -q 'NoSuchBucketPolicy' "$policy_error_file"; then
    current_policy='{"Version":"2012-10-17","Statement":[]}'
  else
    die "Cannot read target bucket policy for '$bucket': $(<"$policy_error_file")"
  fi

  desired_statement="$(jq -n \
    --arg bucket_arn "arn:aws:s3:::$bucket/*" \
    '{
      Sid: "PublicReadGetObject",
      Effect: "Allow",
      Principal: "*",
      Action: "s3:GetObject",
      Resource: $bucket_arn
    }')"

  updated_policy="$(jq -c --argjson desired "$desired_statement" '
    .Version = (.Version // "2012-10-17") |
    .Statement = (
      (if ((.Statement // []) | type) == "array"
       then (.Statement // [])
       else [.Statement]
       end |
       map(select(.Sid != "PublicReadGetObject"))) + [$desired]
    )
  ' <<<"$current_policy")"

  if [[ "$(jq -S -c . <<<"$current_policy")" == "$(jq -S -c . <<<"$updated_policy")" ]]; then
    log "Bucket policy unchanged: $bucket already has PublicReadGetObject"
    return
  fi

  aws s3api put-bucket-policy \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$bucket" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID" \
    --policy "$updated_policy"

  log "Applied metadata public-read bucket policy: $bucket (PublicReadGetObject)"
}

normalized_object_metadata() {
  jq -S -c '{
    CacheControl: (.CacheControl // null),
    ContentDisposition: (.ContentDisposition // null),
    ContentEncoding: (.ContentEncoding // null),
    ContentLanguage: (.ContentLanguage // null),
    ContentType: (.ContentType // null),
    Expires: (.Expires // null),
    WebsiteRedirectLocation: (.WebsiteRedirectLocation // null),
    Metadata: (.Metadata // {})
  }'
}

normalized_tags() {
  jq -S -c '{TagSet: ((.TagSet // []) | sort_by(.Key))}'
}

append_optional_put_argument() {
  local json="$1"
  local json_field="$2"
  local cli_option="$3"
  local -n destination_args="$4"
  local value

  value="$(jq -r --arg field "$json_field" '.[$field] // empty' <<<"$json")"
  if [[ -n "$value" ]]; then
    destination_args+=("$cli_option" "$value")
  fi
}

put_object_with_source_metadata() {
  local target_bucket="$1"
  local key="$2"
  local source_file="$3"
  local source_head="$4"
  local metadata_json
  local -a put_args=(
    aws s3api put-object
    --profile "$TARGET_PROFILE"
    --region "$TARGET_REGION"
    --bucket "$target_bucket"
    --key "$key"
    --body "$source_file"
    --expected-bucket-owner "$TARGET_ACCOUNT_ID"
  )

  append_optional_put_argument "$source_head" "CacheControl" "--cache-control" put_args
  append_optional_put_argument "$source_head" "ContentDisposition" "--content-disposition" put_args
  append_optional_put_argument "$source_head" "ContentEncoding" "--content-encoding" put_args
  append_optional_put_argument "$source_head" "ContentLanguage" "--content-language" put_args
  append_optional_put_argument "$source_head" "ContentType" "--content-type" put_args
  append_optional_put_argument "$source_head" "Expires" "--expires" put_args
  append_optional_put_argument "$source_head" "WebsiteRedirectLocation" "--website-redirect-location" put_args

  metadata_json="$(jq -c '.Metadata // {}' <<<"$source_head")"
  if [[ "$metadata_json" != "{}" ]]; then
    put_args+=(--metadata "$metadata_json")
  fi

  "${put_args[@]}" >/dev/null
}

sync_object_tags() {
  local source_bucket="$1"
  local target_bucket="$2"
  local key="$3"
  local source_tags
  local target_tags

  OBJECT_TAGS_CHANGED=false

  source_tags="$(aws s3api get-object-tagging \
    --profile "$SOURCE_PROFILE" \
    --region "$SOURCE_REGION" \
    --bucket "$source_bucket" \
    --key "$key" \
    --expected-bucket-owner "$SOURCE_ACCOUNT_ID")"

  target_tags="$(aws s3api get-object-tagging \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$target_bucket" \
    --key "$key" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID")"

  if [[ "$(normalized_tags <<<"$source_tags")" == "$(normalized_tags <<<"$target_tags")" ]]; then
    return
  fi

  OBJECT_TAGS_CHANGED=true

  if [[ "$(jq -r '(.TagSet // []) | length' <<<"$source_tags")" == "0" ]]; then
    aws s3api delete-object-tagging \
      --profile "$TARGET_PROFILE" \
      --region "$TARGET_REGION" \
      --bucket "$target_bucket" \
      --key "$key" \
      --expected-bucket-owner "$TARGET_ACCOUNT_ID" >/dev/null
  else
    aws s3api put-object-tagging \
      --profile "$TARGET_PROFILE" \
      --region "$TARGET_REGION" \
      --bucket "$target_bucket" \
      --key "$key" \
      --expected-bucket-owner "$TARGET_ACCOUNT_ID" \
      --tagging "$(jq -c '{TagSet: .TagSet}' <<<"$source_tags")" >/dev/null
  fi
}

# ETags are not always reliable equality checks. Download and compare bytes, then
# independently compare HTTP metadata and object tags.
copy_object_if_needed() {
  local source_bucket="$1"
  local target_bucket="$2"
  local key="$3"
  local file_id
  local source_file
  local target_file
  local source_head
  local target_head=""
  local content_matches=false
  local metadata_matches=false

  file_id="$(printf '%s' "$key" | sha256sum | awk '{print $1}')"
  source_file="$MIGRATION_TMP_DIR/source-$file_id"
  target_file="$MIGRATION_TMP_DIR/target-$file_id"

  source_head="$(aws s3api head-object \
    --profile "$SOURCE_PROFILE" \
    --region "$SOURCE_REGION" \
    --bucket "$source_bucket" \
    --key "$key" \
    --expected-bucket-owner "$SOURCE_ACCOUNT_ID")"

  aws s3api get-object \
    --profile "$SOURCE_PROFILE" \
    --region "$SOURCE_REGION" \
    --bucket "$source_bucket" \
    --key "$key" \
    --expected-bucket-owner "$SOURCE_ACCOUNT_ID" \
    "$source_file" >/dev/null

  if target_head="$(aws s3api head-object \
    --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" \
    --bucket "$target_bucket" \
    --key "$key" \
    --expected-bucket-owner "$TARGET_ACCOUNT_ID" 2>/dev/null)"; then
    if [[ "$(jq -r '.ContentLength' <<<"$source_head")" == "$(jq -r '.ContentLength' <<<"$target_head")" ]]; then
      aws s3api get-object \
        --profile "$TARGET_PROFILE" \
        --region "$TARGET_REGION" \
        --bucket "$target_bucket" \
        --key "$key" \
        --expected-bucket-owner "$TARGET_ACCOUNT_ID" \
        "$target_file" >/dev/null

      if cmp -s -- "$source_file" "$target_file"; then
        content_matches=true
      fi
    fi

    if [[ "$(normalized_object_metadata <<<"$source_head")" == "$(normalized_object_metadata <<<"$target_head")" ]]; then
      metadata_matches=true
    fi
  fi

  if [[ "$content_matches" == true && "$metadata_matches" == true ]]; then
    log "Unchanged: s3://$target_bucket/$key"
    ((BUCKET_UNCHANGED_COUNT += 1))
  else
    log "Copying: s3://$source_bucket/$key -> s3://$target_bucket/$key"
    put_object_with_source_metadata "$target_bucket" "$key" "$source_file" "$source_head"
    ((BUCKET_COPIED_COUNT += 1))
  fi

  sync_object_tags "$source_bucket" "$target_bucket" "$key"
  if [[ "$OBJECT_TAGS_CHANGED" == true ]]; then
    ((BUCKET_TAGS_UPDATED_COUNT += 1))
    log "Tags updated: s3://$target_bucket/$key"
  fi
  rm -f -- "$source_file" "$target_file"
}

copy_bucket() {
  local source_bucket="$1"
  local target_bucket="$2"
  local encoded_key
  local key
  local processed_count=0

  BUCKET_COPIED_COUNT=0
  BUCKET_UNCHANGED_COUNT=0
  BUCKET_TAGS_UPDATED_COUNT=0

  log "Reading source object list: $source_bucket"
  while IFS= read -r encoded_key; do
    [[ -n "$encoded_key" ]] || continue
    key="$(printf '%s' "$encoded_key" | base64 --decode)"
    copy_object_if_needed "$source_bucket" "$target_bucket" "$key"
    ((processed_count += 1))
  done < <(
    aws s3api list-objects-v2 \
      --profile "$SOURCE_PROFILE" \
      --region "$SOURCE_REGION" \
      --bucket "$source_bucket" \
      --expected-bucket-owner "$SOURCE_ACCOUNT_ID" \
      --output json |
      jq -r '.Contents[]?.Key | @base64'
  )

  log "Processed $processed_count objects for $source_bucket"
  log "Rerun summary for $target_bucket: copied=$BUCKET_COPIED_COUNT unchanged=$BUCKET_UNCHANGED_COUNT tags-updated=$BUCKET_TAGS_UPDATED_COUNT"
}

bucket_inventory() {
  local profile="$1"
  local owner="$2"
  local region="$3"
  local bucket="$4"

  aws s3api list-objects-v2 \
    --profile "$profile" \
    --region "$region" \
    --bucket "$bucket" \
    --expected-bucket-owner "$owner" \
    --query '[length(Contents || `[]`), sum(Contents[].Size || `[]`)]' \
    --output text
}

verify_bucket_copy() {
  local source_bucket="$1"
  local target_bucket="$2"
  local source_inventory
  local target_inventory

  source_inventory="$(bucket_inventory "$SOURCE_PROFILE" "$SOURCE_ACCOUNT_ID" "$SOURCE_REGION" "$source_bucket")"
  target_inventory="$(bucket_inventory "$TARGET_PROFILE" "$TARGET_ACCOUNT_ID" "$TARGET_REGION" "$target_bucket")"

  # Per-object bytes are checked during copying; this completeness gate also
  # requires matching object counts and total bytes.
  [[ "$source_inventory" == "$target_inventory" ]] ||
    die "Inventory mismatch for $source_bucket -> $target_bucket: source=[$source_inventory], target=[$target_inventory]"

  log "Verified object count and total bytes for $source_bucket -> $target_bucket: $source_inventory"
}

main() {
  local index
  local source_inventory
  local -a target_access_modes=(
    "private"
    "public-read-policy"
  )

  require_command aws
  require_command awk
  require_command base64
  require_command cmp
  require_command date
  require_command grep
  require_command jq
  require_command mktemp
  require_command sha256sum
  require_command tee

  initialize_logging
  verify_accounts

  for index in "${!SOURCE_BUCKETS[@]}"; do
    verify_source_bucket "${SOURCE_BUCKETS[$index]}"
    source_inventory="$(bucket_inventory \
      "$SOURCE_PROFILE" \
      "$SOURCE_ACCOUNT_ID" \
      "$SOURCE_REGION" \
      "${SOURCE_BUCKETS[$index]}")"
    log "Source inventory: ${SOURCE_BUCKETS[$index]}: $source_inventory"
    target_bucket_preflight "${TARGET_BUCKETS[$index]}"
    log "Mapping: ${SOURCE_BUCKETS[$index]} -> ${TARGET_BUCKETS[$index]}"
    if [[ "$index" -eq 0 ]]; then
      if [[ -n "$WALLET_CLOUDFRONT_DISTRIBUTION_ID" ]]; then
        validate_cloudfront_distribution_for_bucket \
          "${TARGET_BUCKETS[$index]}" \
          "$WALLET_CLOUDFRONT_DISTRIBUTION_ID"
        log "Policy plan: grant CloudFront $WALLET_CLOUDFRONT_DISTRIBUTION_ID read-only access to ${TARGET_BUCKETS[$index]}"
      else
        log "Policy plan: wallet remains private until its target CloudFront distribution ID is supplied"
      fi
    else
      log "Policy plan: ensure PublicReadGetObject for ${TARGET_BUCKETS[$index]} (no CloudFront)"
    fi
  done

  # Dry-run exits before bucket creation, policy changes, or object uploads.
  if [[ "$DRY_RUN" == true ]]; then
    log "DRY RUN RESULT: PASS - all read-only preflight checks succeeded."
    log "No buckets or objects were changed."
    log "Review this log before the real run: $LOG_FILE"
    exit 0
  fi

  log "Beginning write phase after successful preflight checks."
  MIGRATION_TMP_DIR="$(mktemp -d -t wallet-s3-migration.XXXXXX)"
  chmod 700 "$MIGRATION_TMP_DIR"

  for index in "${!SOURCE_BUCKETS[@]}"; do
    create_target_bucket "${TARGET_BUCKETS[$index]}"
    harden_target_bucket \
      "${TARGET_BUCKETS[$index]}" \
      "${target_access_modes[$index]}"
    if [[ "$index" -eq 0 ]]; then
      configure_cloudfront_bucket_policy \
        "${TARGET_BUCKETS[$index]}" \
        "$WALLET_CLOUDFRONT_DISTRIBUTION_ID"
    else
      configure_metadata_public_read_policy "${TARGET_BUCKETS[$index]}"
    fi
    copy_bucket "${SOURCE_BUCKETS[$index]}" "${TARGET_BUCKETS[$index]}"
    verify_bucket_copy "${SOURCE_BUCKETS[$index]}" "${TARGET_BUCKETS[$index]}"
  done

  log "S3 migration completed successfully. Source buckets were not modified."
  log "Execution log: $LOG_FILE"
}

main
