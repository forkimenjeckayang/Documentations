#!/usr/bin/env bash

# Prepare the target solutions.adorsys.com public hosted zone for a later
# authoritative-name-server cutover.
#
# What this script changes:
#   --execute copies missing or different non-NS/non-SOA records from the
#   authoritative sandbox zone into the target-account zone using UPSERT.
#
# What this script never changes:
#   - the source/sandbox hosted zone;
#   - the NS delegation in the parent adorsys.com zone;
#   - the automatically managed NS or SOA records in either child zone;
#   - any records by deletion.
#
# Run with no arguments first. The default mode is a read-only dry run.

set -Eeuo pipefail

readonly SOURCE_ACCOUNT_ID="${SOURCE_ACCOUNT_ID:-917848404243}"
readonly TARGET_ACCOUNT_ID="${TARGET_ACCOUNT_ID:-982081049921}"
readonly SOURCE_PROFILE="${SOURCE_PROFILE:-sandbox}"
readonly TARGET_PROFILE="${TARGET_PROFILE:-default}"
readonly SOURCE_ZONE_ID="${SOURCE_ZONE_ID:-Z02911502N07V5SNAMLHL}"
readonly TARGET_ZONE_ID="${TARGET_ZONE_ID:-Z05071841EFF9JQA59TZL}"
readonly ZONE_NAME="${ZONE_NAME:-solutions.adorsys.com.}"

# Expected production destinations. These guards prevent a later rerun from
# silently copying a reverted or stale sandbox alias into the target zone.
readonly WALLET_RECORD_NAME="${WALLET_RECORD_NAME:-wallet.solutions.adorsys.com.}"
readonly WALLET_ALIAS_DNS="${WALLET_ALIAS_DNS:-d2djz6pfk882cv.cloudfront.net.}"
readonly WALLET_ALIAS_ZONE_ID="${WALLET_ALIAS_ZONE_ID:-Z2FDTNDATAQYW2}"
readonly PROXY_RECORD_NAME="${PROXY_RECORD_NAME:-proxy.solutions.adorsys.com.}"
readonly PROXY_ALIAS_DNS="${PROXY_ALIAS_DNS:-dualstack.nginx-proxy-migration-1538385164.eu-central-1.elb.amazonaws.com.}"
readonly KEYCLOAK_RECORD_NAME="${KEYCLOAK_RECORD_NAME:-keycloak-demo.solutions.adorsys.com.}"
readonly KEYCLOAK_ALIAS_DNS="${KEYCLOAK_ALIAS_DNS:-dualstack.keycloak-demo-migration-1394321177.eu-central-1.elb.amazonaws.com.}"
readonly ALB_ALIAS_ZONE_ID="${ALB_ALIAS_ZONE_ID:-Z215JYRZR1TBD5}"

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG_DIR="${MIGRATION_LOG_DIR:-$REPO_ROOT/.migration-logs}"

MODE="dry-run"
MODE_WAS_SET="false"
LOG_FILE=""
WORK_DIR=""
SOURCE_RECORDS=""
TARGET_RECORDS=""
CHANGE_BATCH=""
CHANGE_COUNT=0
AUTHORITY_STATE=""

usage() {
  cat <<'EOF'
Usage:
  scripts/prepare-route53-zone-migration.sh --dry-run
  scripts/prepare-route53-zone-migration.sh --execute
  scripts/prepare-route53-zone-migration.sh --verify

Modes:
  --dry-run    Read-only plan. Show which records would be copied.
  --execute    UPSERT only missing/different non-NS/non-SOA records into the
               target zone, wait for Route 53, and verify both zones match.
  --verify     Read-only strict verification. Fail if the target is not ready.

No argument is also a read-only dry run for safety.

The script does not change the parent adorsys.com NS delegation and does not
modify or delete records in the sandbox zone.

Optional environment overrides:
  SOURCE_ACCOUNT_ID, TARGET_ACCOUNT_ID, SOURCE_PROFILE, TARGET_PROFILE,
  SOURCE_ZONE_ID, TARGET_ZONE_ID, ZONE_NAME, MIGRATION_LOG_DIR
EOF
}

log() {
  printf '[route53-zone-preparation] %s\n' "$*"
}

die() {
  printf '[route53-zone-preparation] ERROR: %s\n' "$*" >&2
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
      [[ "$MODE_WAS_SET" == "false" ]] || die "Choose only one mode"
      MODE="dry-run"
      MODE_WAS_SET="true"
      ;;
    --execute)
      [[ "$MODE_WAS_SET" == "false" ]] || die "Choose only one mode"
      MODE="execute"
      MODE_WAS_SET="true"
      ;;
    --verify)
      [[ "$MODE_WAS_SET" == "false" ]] || die "Choose only one mode"
      MODE="verify"
      MODE_WAS_SET="true"
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

initialize() {
  local timestamp

  mkdir -p -- "$LOG_DIR"
  chmod 700 "$LOG_DIR"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  LOG_FILE="$LOG_DIR/route53-zone-$MODE-$timestamp-$$.log"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
  exec > >(tee -a -- "$LOG_FILE") 2>&1

  WORK_DIR="$(mktemp -d)"
  SOURCE_RECORDS="$WORK_DIR/source-records.json"
  TARGET_RECORDS="$WORK_DIR/target-records.json"
  CHANGE_BATCH="$WORK_DIR/change-batch.json"

  log "Mode: $MODE"
  log "Log file: $LOG_FILE"
}

account_for_profile() {
  aws sts get-caller-identity --profile "$1" --query Account --output text
}

verify_accounts() {
  local source_account
  local target_account

  source_account="$(account_for_profile "$SOURCE_PROFILE")"
  target_account="$(account_for_profile "$TARGET_PROFILE")"

  [[ "$source_account" == "$SOURCE_ACCOUNT_ID" ]] ||
    die "Profile '$SOURCE_PROFILE' resolves to $source_account, expected $SOURCE_ACCOUNT_ID"
  [[ "$target_account" == "$TARGET_ACCOUNT_ID" ]] ||
    die "Profile '$TARGET_PROFILE' resolves to $target_account, expected $TARGET_ACCOUNT_ID"
  [[ "$source_account" != "$target_account" ]] ||
    die "Source and target profiles resolve to the same account"

  log "Verified source account $source_account and target account $target_account"
}

verify_zone() {
  local profile="$1"
  local zone_id="$2"
  local label="$3"
  local zone

  zone="$(aws route53 get-hosted-zone --profile "$profile" --id "$zone_id")"
  [[ "$(jq -r '.HostedZone.Name' <<<"$zone")" == "$ZONE_NAME" ]] ||
    die "$label zone $zone_id does not have expected name $ZONE_NAME"
  [[ "$(jq -r '.HostedZone.Config.PrivateZone' <<<"$zone")" == "false" ]] ||
    die "$label zone $zone_id is private"

  log "Verified $label public zone $zone_id"
}

zone_name_servers() {
  aws route53 get-hosted-zone --profile "$1" --id "$2" --query 'DelegationSet.NameServers' --output text |
    tr '\t' '\n' |
    sed 's/\.$//' |
    sort
}

detect_public_authority() {
  local source_servers
  local target_servers
  local public_servers

  source_servers="$(zone_name_servers "$SOURCE_PROFILE" "$SOURCE_ZONE_ID")"
  target_servers="$(zone_name_servers "$TARGET_PROFILE" "$TARGET_ZONE_ID")"
  public_servers="$(dig +short NS "${ZONE_NAME%.}" | sed 's/\.$//' | sort)"

  [[ -n "$public_servers" ]] ||
    die "Public DNS returned no NS records for ${ZONE_NAME%.}"

  if [[ "$public_servers" == "$source_servers" ]]; then
    AUTHORITY_STATE="source"
  elif [[ "$public_servers" == "$target_servers" ]]; then
    AUTHORITY_STATE="target"
  else
    AUTHORITY_STATE="unknown"
  fi

  log "Public authority: $AUTHORITY_STATE"
  [[ "$AUTHORITY_STATE" != "unknown" ]] ||
    die "Public NS records match neither the configured source nor target zone"
}

fetch_records() {
  aws route53 list-resource-record-sets --profile "$SOURCE_PROFILE" --hosted-zone-id "$SOURCE_ZONE_ID" --output json >"$SOURCE_RECORDS"

  aws route53 list-resource-record-sets --profile "$TARGET_PROFILE" --hosted-zone-id "$TARGET_ZONE_ID" --output json >"$TARGET_RECORDS"
}

verify_alias_target() {
  local records_file="$1"
  local name="$2"
  local expected_dns="$3"
  local expected_zone_id="$4"

  jq -e \
    --arg name "$name" \
    --arg dns "$expected_dns" \
    --arg zone_id "$expected_zone_id" '
      any(.ResourceRecordSets[];
        .Name == $name and
        .Type == "A" and
        .AliasTarget.DNSName == $dns and
        .AliasTarget.HostedZoneId == $zone_id
      )
    ' "$records_file" >/dev/null ||
    die "Refusing to copy: source A alias $name is not the verified target resource"
}

verify_source_production_targets() {
  verify_alias_target "$SOURCE_RECORDS" "$WALLET_RECORD_NAME" "$WALLET_ALIAS_DNS" "$WALLET_ALIAS_ZONE_ID"
  verify_alias_target "$SOURCE_RECORDS" "$PROXY_RECORD_NAME" "$PROXY_ALIAS_DNS" "$ALB_ALIAS_ZONE_ID"
  verify_alias_target "$SOURCE_RECORDS" "$KEYCLOAK_RECORD_NAME" "$KEYCLOAK_ALIAS_DNS" "$ALB_ALIAS_ZONE_ID"

  log "Verified source production aliases already point to the target CloudFront and ALBs"
}

build_change_batch() {
  jq -n --arg comment "Prepare target solutions.adorsys.com zone from sandbox before delegation" --slurpfile source "$SOURCE_RECORDS" --slurpfile target "$TARGET_RECORDS" '
      def same_identity($left; $right):
        $left.Name == $right.Name and
        $left.Type == $right.Type and
        ($left.SetIdentifier // "") == ($right.SetIdentifier // "");

      {
        Comment: $comment,
        Changes: [
          $source[0].ResourceRecordSets[]
          | select(.Type != "NS" and .Type != "SOA")
          | . as $source_record
          | (
              $target[0].ResourceRecordSets
              | map(select(same_identity(.; $source_record)))
              | first
            ) as $target_record
          | select($target_record == null or $target_record != $source_record)
          | {
              Action: "UPSERT",
              ResourceRecordSet: $source_record
            }
        ]
      }
    ' >"$CHANGE_BATCH"

  CHANGE_COUNT="$(jq '.Changes | length' "$CHANGE_BATCH")"
}

print_record_classification() {
  log "The script copies every non-NS/non-SOA record for safe zone parity."
  log "Production-required records:"
  log "  A wallet.solutions.adorsys.com -> target CloudFront"
  log "  A proxy.solutions.adorsys.com -> target nginx ALB"
  log "  A keycloak-demo.solutions.adorsys.com -> target Keycloak ALB"
  log "Certificate/ownership records preserved during migration:"
  log "  CNAME _6878... -> target ACM validation (must remain)"
  log "  CNAME _f6b... -> source ACM validation (retain for rollback)"
  log "  TXT _wallet... -> CloudFront cross-account ownership proof"
  log "  TXT solutions.adorsys.com -> copied legacy token; review separately after migration"
  log "Temporary test records preserved initially:"
  log "  CNAME wallet-migration.solutions.adorsys.com"
  log "  CNAME proxy-migration.solutions.adorsys.com"
  log "Temporary/rollback records may be removed only after delegation and monitoring"
}

print_plan() {
  if ((CHANGE_COUNT == 0)); then
    log "No target changes are required; all source non-NS/non-SOA records already match"
    return
  fi

  log "Planned target UPSERT operations: $CHANGE_COUNT"
  jq -r '
    .Changes[] |
    "  \(.Action) \(.ResourceRecordSet.Type) \(.ResourceRecordSet.Name)"
  ' "$CHANGE_BATCH"
}

verify_required_record() {
  local records_file="$1"
  local name="$2"
  local type="$3"

  jq -e --arg name "$name" --arg type "$type" '
      any(.ResourceRecordSets[];
        .Name == $name and .Type == $type
      )
    ' "$records_file" >/dev/null ||
    die "Required record is missing: $type $name"
}

verify_critical_target_records() {
  verify_required_record "$TARGET_RECORDS" "wallet.solutions.adorsys.com." "A"
  verify_required_record "$TARGET_RECORDS" "proxy.solutions.adorsys.com." "A"
  verify_required_record "$TARGET_RECORDS" "keycloak-demo.solutions.adorsys.com." "A"
  verify_required_record "$TARGET_RECORDS" "_6878d810540ccb0bc9697193272cc087.solutions.adorsys.com." "CNAME"

  log "Verified the three production aliases and target ACM validation CNAME in the target zone"
}

verify_parity() {
  local mismatch_count

  build_change_batch
  mismatch_count="$CHANGE_COUNT"
  ((mismatch_count == 0)) ||
    die "Target zone still has $mismatch_count missing or different source record(s)"

  verify_critical_target_records
  log "Verified full source-to-target parity for every non-NS/non-SOA record"
}

verify_direct_target_answers() {
  local target_server
  local name
  local answer

  target_server="$(zone_name_servers "$TARGET_PROFILE" "$TARGET_ZONE_ID" | head -n 1)"

  for name in wallet.solutions.adorsys.com proxy.solutions.adorsys.com keycloak-demo.solutions.adorsys.com; do
    answer="$(dig +short "@$target_server" "$name" A)"
    [[ -n "$answer" ]] || die "Target name server $target_server returned no A answer for $name"
    log "Direct target DNS answer verified: $name"
  done
}

apply_changes() {
  local change_id

  [[ "$AUTHORITY_STATE" == "source" ]] ||
    die "Refusing to copy from source after authority is no longer on the source zone"

  if ((CHANGE_COUNT == 0)); then
    log "Target zone already matches; no Route 53 write was made"
    return
  fi

  change_id="$(aws route53 change-resource-record-sets --profile "$TARGET_PROFILE" --hosted-zone-id "$TARGET_ZONE_ID" --change-batch "file://$CHANGE_BATCH" --query 'ChangeInfo.Id' --output text)"

  log "Submitted target-only Route 53 change $change_id"
  aws route53 wait resource-record-sets-changed --profile "$TARGET_PROFILE" --id "$change_id"
  log "Route 53 change is INSYNC"
}

main() {
  require_command aws
  require_command dig
  require_command jq
  require_command mktemp
  require_command sed
  require_command sort
  require_command tee

  initialize
  verify_accounts
  verify_zone "$SOURCE_PROFILE" "$SOURCE_ZONE_ID" "source"
  verify_zone "$TARGET_PROFILE" "$TARGET_ZONE_ID" "target"
  detect_public_authority
  fetch_records
  verify_source_production_targets
  build_change_batch
  print_record_classification
  print_plan

  case "$MODE" in
    dry-run)
      log "DRY RUN COMPLETE: no AWS records or delegation were changed"
      log "Next after review: rerun with --execute"
      ;;
    execute)
      apply_changes
      fetch_records
      verify_parity
      verify_direct_target_answers
      log "TARGET ZONE PREPARATION COMPLETE"
      log "No source record and no parent NS delegation was changed"
      log "Next: request the adorsys.com DNS owner to lower the delegation TTL"
      ;;
    verify)
      verify_parity
      verify_direct_target_answers
      log "VERIFY COMPLETE: target zone is ready for a later delegation change"
      ;;
  esac
}

main
