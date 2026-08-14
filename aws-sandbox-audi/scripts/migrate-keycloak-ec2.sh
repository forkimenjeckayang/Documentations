#!/usr/bin/env bash

# Prepare the Keycloak EC2 machine image for the account migration.
#
# This script automates the AWS-side image and target-foundation work:
#   1. Verify the source instance and both AWS accounts.
#   2. Create or reuse a live, no-reboot source AMI.
#   3. Share the private AMI and its unencrypted snapshots with the target account.
#   4. Copy or reuse an encrypted, target-owned AMI in eu-central-1.
#   5. Optionally revoke the temporary source sharing after the target copy exists.
#   6. Create/reuse the target IAM profile, security groups, target group, ALB,
#      and HTTPS listener without launching EC2 or changing DNS.
#   7. Validate and register a manually launched target EC2 instance.
#
# It deliberately does NOT stop Keycloak, create/restore PostgreSQL dumps, launch
# an EC2 instance, or change DNS. Database work and the manual EC2 launch require
# separate validation. The source instance is never stopped, rebooted, terminated,
# or otherwise modified by this script.

set -Eeuo pipefail

readonly SOURCE_ACCOUNT_ID="${SOURCE_ACCOUNT_ID:-917848404243}"
readonly TARGET_ACCOUNT_ID="${TARGET_ACCOUNT_ID:-982081049921}"
readonly SOURCE_PROFILE="${SOURCE_PROFILE:-sandbox}"
readonly TARGET_PROFILE="${TARGET_PROFILE:-default}"
readonly SOURCE_REGION="${SOURCE_REGION:-eu-north-1}"
readonly TARGET_REGION="${TARGET_REGION:-eu-central-1}"
readonly SOURCE_INSTANCE_ID="${SOURCE_INSTANCE_ID:-i-03eac5cc262731ede}"
readonly SOURCE_AMI_NAME="${SOURCE_AMI_NAME:-keycloak-demo-migration-baseline-20260814}"
readonly TARGET_AMI_NAME="${TARGET_AMI_NAME:-keycloak-demo-migration-target-20260814}"
readonly MIGRATION_TAG="${MIGRATION_TAG:-keycloak-demo-account-migration}"

readonly TARGET_VPC_ID="${TARGET_VPC_ID:-vpc-073150aef0868a8af}"
readonly TARGET_EC2_SUBNET_ID="${TARGET_EC2_SUBNET_ID:-subnet-01ea66e1eadb764b8}"
readonly TARGET_ROLE_NAME="${TARGET_ROLE_NAME:-keycloak-demo-ec2-role}"
readonly TARGET_INSTANCE_PROFILE_NAME="${TARGET_INSTANCE_PROFILE_NAME:-keycloak-demo-ec2-role}"
readonly TARGET_ALB_SG_NAME="${TARGET_ALB_SG_NAME:-keycloak-demo-alb-sg}"
readonly TARGET_EC2_SG_NAME="${TARGET_EC2_SG_NAME:-keycloak-demo-ec2-sg}"
readonly TARGET_GROUP_NAME="${TARGET_GROUP_NAME:-keycloak-demo-targets}"
readonly TARGET_ALB_NAME="${TARGET_ALB_NAME:-keycloak-demo-migration}"
readonly TARGET_CERTIFICATE_ARN="${TARGET_CERTIFICATE_ARN:-arn:aws:acm:eu-central-1:982081049921:certificate/d556613f-db8a-44cb-b4f2-bf360443346a}"
readonly TARGET_SSL_POLICY="${TARGET_SSL_POLICY:-ELBSecurityPolicy-TLS13-1-2-2021-06}"
readonly TARGET_DOMAIN="${TARGET_DOMAIN:-keycloak-demo.solutions.adorsys.com}"
readonly TARGET_PORT="${TARGET_PORT:-80}"
readonly TARGET_HEALTH_PATH="${TARGET_HEALTH_PATH:-/realms/master}"
readonly IMAGE_WAIT_TIMEOUT_SECONDS="${IMAGE_WAIT_TIMEOUT_SECONDS:-14400}"
readonly IMAGE_WAIT_INTERVAL_SECONDS="${IMAGE_WAIT_INTERVAL_SECONDS:-30}"
readonly SSM_POLICY_ARN="arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
readonly -a TARGET_ALB_SUBNETS=(
  "subnet-053b37b6b4a517afb"
  "subnet-003d0ccab3982e90a"
  "subnet-0f88842f7789cc09a"
)

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG_DIR="${MIGRATION_LOG_DIR:-$REPO_ROOT/.migration-logs}"

MODE="dry-run"
EXECUTE="false"
BACKUP_CONFIRMED="false"
LOG_FILE=""
SOURCE_AMI_ID=""
TARGET_AMI_ID=""
TARGET_INSTANCE_ID="${TARGET_INSTANCE_ID:-}"
TARGET_ALB_SG_ID=""
TARGET_EC2_SG_ID=""
TARGET_GROUP_ARN=""
TARGET_ALB_ARN=""
TARGET_ALB_DNS=""
TARGET_ALB_ZONE_ID=""
TARGET_LISTENER_ARN=""

usage() {
  cat <<'EOF'
Usage: scripts/migrate-keycloak-ec2.sh [mode] [confirmation flags]

Modes:
  --dry-run       Read-only validation and CREATE/REUSE plan. This is the default.
  --prepare-ami   Create/reuse, share, copy, encrypt, and verify the migration AMIs.
  --status          Read-only status of source AMI, sharing, and target AMI.
  --prepare-target  Create/reuse target IAM, SGs, target group, ALB, and listener.
  --target-status   Read-only status of target foundation and optional EC2.
  --register-target <instance-id>
                    Validate/register the manually launched EC2 and test the ALB.
  --revoke-share    Remove target-account access to source AMI and snapshots.

Confirmation flags:
  --execute           Required with every mutating mode.
  --backup-confirmed  Required with --prepare-ami. Confirms that a checked,
                      off-instance PostgreSQL dump exists before imaging.
  -h, --help          Show this help.

Recommended sequence:
  1. Create and copy an off-instance PostgreSQL dump from the source EC2.
  2. Run: ./scripts/migrate-keycloak-ec2.sh --dry-run
  3. Review the ignored log under .migration-logs/.
  4. Run: ./scripts/migrate-keycloak-ec2.sh --prepare-ami --execute --backup-confirmed
  5. Run: ./scripts/migrate-keycloak-ec2.sh --prepare-target --execute
  6. Manually launch EC2 using the exact settings printed by the script.
  7. Restore PostgreSQL and start Keycloak on the isolated target.
  8. Run: ./scripts/migrate-keycloak-ec2.sh --register-target i-... --execute
  9. After the target copy is proven independent, optionally run:
     ./scripts/migrate-keycloak-ec2.sh --revoke-share --execute

The AMI names can be versioned through SOURCE_AMI_NAME and TARGET_AMI_NAME.
Reusing the same names makes repeated runs idempotent.
EOF
}

log() { printf '[keycloak-ec2-migration] %s\n' "$*"; }
die() { printf '[keycloak-ec2-migration] ERROR: %s\n' "$*" >&2; exit 1; }

while (($# > 0)); do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --prepare-ami) MODE="prepare-ami" ;;
    --status) MODE="status" ;;
    --prepare-target) MODE="prepare-target" ;;
    --target-status) MODE="target-status" ;;
    --register-target)
      MODE="register-target"
      shift
      (($# > 0)) || die "--register-target requires an EC2 instance ID"
      TARGET_INSTANCE_ID="$1"
      ;;
    --revoke-share) MODE="revoke-share" ;;
    --execute) EXECUTE="true" ;;
    --backup-confirmed) BACKUP_CONFIRMED="true" ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "Unknown argument: $1" ;;
  esac
  shift
done

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

initialize_logging() {
  local timestamp
  mkdir -p -- "$LOG_DIR"
  chmod 700 "$LOG_DIR"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  LOG_FILE="$LOG_DIR/keycloak-ec2-$MODE-$timestamp-$$.log"
  touch "$LOG_FILE"
  chmod 600 "$LOG_FILE"
  exec > >(tee -a -- "$LOG_FILE") 2>&1
  log "Mode: $MODE"
  log "Log file: $LOG_FILE"
}

verify_accounts() {
  local source_account target_account
  source_account="$(aws sts get-caller-identity --profile "$SOURCE_PROFILE" --query Account --output text)"
  target_account="$(aws sts get-caller-identity --profile "$TARGET_PROFILE" --query Account --output text)"
  [[ "$source_account" == "$SOURCE_ACCOUNT_ID" ]] ||
    die "Profile '$SOURCE_PROFILE' resolves to $source_account; expected $SOURCE_ACCOUNT_ID"
  [[ "$target_account" == "$TARGET_ACCOUNT_ID" ]] ||
    die "Profile '$TARGET_PROFILE' resolves to $target_account; expected $TARGET_ACCOUNT_ID"
  [[ "$source_account" != "$target_account" ]] || die "Source and target accounts are identical"
  log "Verified source account $source_account and target account $target_account"
}

verify_source_instance() {
  local instance volume_id volume
  instance="$(aws ec2 describe-instances --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
    --instance-ids "$SOURCE_INSTANCE_ID")"

  jq -e '
    .Reservations[0].Instances[0] |
    .State.Name == "running" and
    .Architecture == "x86_64" and
    .InstanceType == "t3.medium" and
    .RootDeviceName == "/dev/sda1" and
    (.BlockDeviceMappings | length) == 1
  ' <<<"$instance" >/dev/null ||
    die "Source instance no longer matches the verified running t3.medium, x86_64, one-volume baseline"

  volume_id="$(jq -r '.Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' <<<"$instance")"
  volume="$(aws ec2 describe-volumes --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
    --volume-ids "$volume_id")"
  jq -e '.Volumes[0] | .State == "in-use" and .Size == 100 and .VolumeType == "gp3"' \
    <<<"$volume" >/dev/null || die "Source root volume no longer matches the verified 100-GiB gp3 baseline"

  if [[ "$(jq -r '.Volumes[0].Encrypted' <<<"$volume")" == "true" ]]; then
    die "Source root volume is now encrypted; cross-account KMS sharing must be designed before continuing"
  fi
  log "Verified running source $SOURCE_INSTANCE_ID and unencrypted 100-GiB gp3 root volume $volume_id"
}

find_source_ami() {
  SOURCE_AMI_ID="$(aws ec2 describe-images --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
    --owners self --filters "Name=name,Values=$SOURCE_AMI_NAME" \
    --query 'reverse(sort_by(Images,&CreationDate))[0].ImageId' --output text)"
  [[ "$SOURCE_AMI_ID" != "None" ]] || SOURCE_AMI_ID=""
}

find_target_ami() {
  TARGET_AMI_ID="$(aws ec2 describe-images --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --owners self --filters "Name=name,Values=$TARGET_AMI_NAME" \
    --query 'reverse(sort_by(Images,&CreationDate))[0].ImageId' --output text)"
  [[ "$TARGET_AMI_ID" != "None" ]] || TARGET_AMI_ID=""
}

source_snapshot_ids() {
  aws ec2 describe-images --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
    --image-ids "$SOURCE_AMI_ID" --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text
}

target_snapshot_ids() {
  aws ec2 describe-images --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --image-ids "$TARGET_AMI_ID" --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text
}

# The built-in EC2 image waiter stops after about ten minutes, which is often too
# short for this 100-GiB root volume. Poll explicitly so operators can see snapshot
# progress. A rerun remains safe because AMIs are discovered by their stable name.
wait_for_image_available() {
  local profile="$1" region="$2" image_id="$3" label="$4"
  local deadline image state reason snapshot_data snapshot_summary
  local -a snapshot_ids=()

  [[ "$IMAGE_WAIT_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
    die "IMAGE_WAIT_TIMEOUT_SECONDS must be a positive integer"
  [[ "$IMAGE_WAIT_INTERVAL_SECONDS" =~ ^[1-9][0-9]*$ ]] ||
    die "IMAGE_WAIT_INTERVAL_SECONDS must be a positive integer"
  deadline=$((SECONDS + IMAGE_WAIT_TIMEOUT_SECONDS))

  while true; do
    image="$(aws ec2 describe-images --profile "$profile" --region "$region" \
      --image-ids "$image_id")"
    state="$(jq -r '.Images[0].State // "missing"' <<<"$image")"
    reason="$(jq -r '.Images[0].StateReason.Message // empty' <<<"$image")"

    case "$state" in
      available)
        log "$label AMI $image_id is available"
        return 0
        ;;
      pending)
        read -r -a snapshot_ids <<<"$(jq -r \
          '.Images[0].BlockDeviceMappings[].Ebs.SnapshotId // empty' <<<"$image")"
        if ((${#snapshot_ids[@]} > 0)); then
          snapshot_data="$(aws ec2 describe-snapshots --profile "$profile" \
            --region "$region" --snapshot-ids "${snapshot_ids[@]}")"
          snapshot_summary="$(jq -r \
            '[.Snapshots[] | "\(.SnapshotId)=\(.State)/\(.Progress)"] | join(", ")' \
            <<<"$snapshot_data")"
        else
          snapshot_summary="snapshot allocation pending"
        fi
        log "$label AMI $image_id is pending; $snapshot_summary"
        ;;
      failed | error | invalid | deregistered | disabled | missing)
        die "$label AMI $image_id entered state '$state'${reason:+: $reason}"
        ;;
      *)
        die "$label AMI $image_id returned unexpected state '$state'${reason:+: $reason}"
        ;;
    esac

    if ((SECONDS >= deadline)); then
      die "$label AMI $image_id is still pending after ${IMAGE_WAIT_TIMEOUT_SECONDS}s; rerun the same command later to reuse it"
    fi
    sleep "$IMAGE_WAIT_INTERVAL_SECONDS"
  done
}

show_plan() {
  find_source_ami
  find_target_ami

  if [[ -n "$SOURCE_AMI_ID" ]]; then
    log "REUSE source AMI $SOURCE_AMI_ID ($SOURCE_AMI_NAME)"
  else
    log "CREATE live no-reboot source AMI $SOURCE_AMI_NAME from $SOURCE_INSTANCE_ID"
  fi

  log "ENSURE private launch permission for target account $TARGET_ACCOUNT_ID"
  log "ENSURE private create-volume permission on every unencrypted source snapshot"

  if [[ -n "$TARGET_AMI_ID" ]]; then
    log "REUSE target AMI $TARGET_AMI_ID ($TARGET_AMI_NAME)"
  else
    log "COPY target-owned encrypted AMI $TARGET_AMI_NAME into $TARGET_REGION"
  fi

  log "NO CHANGE to the source EC2 lifecycle, Keycloak process, PostgreSQL container, ALB, or DNS"
}

create_or_reuse_source_ami() {
  local state image
  find_source_ami
  if [[ -z "$SOURCE_AMI_ID" ]]; then
    log "Creating no-reboot source AMI; the source instance remains running"
    SOURCE_AMI_ID="$(aws ec2 create-image --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
      --instance-id "$SOURCE_INSTANCE_ID" \
      --name "$SOURCE_AMI_NAME" \
      --description "Live Keycloak host migration baseline; PostgreSQL logical dump is authoritative" \
      --no-reboot \
      --tag-specifications \
        "ResourceType=image,Tags=[{Key=Name,Value=$SOURCE_AMI_NAME},{Key=Migration,Value=$MIGRATION_TAG},{Key=Stage,Value=source-baseline}]" \
        "ResourceType=snapshot,Tags=[{Key=Name,Value=$SOURCE_AMI_NAME},{Key=Migration,Value=$MIGRATION_TAG},{Key=Stage,Value=source-baseline}]" \
      --query ImageId --output text)"
    log "Created source AMI $SOURCE_AMI_ID"
  else
    state="$(aws ec2 describe-images --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
      --image-ids "$SOURCE_AMI_ID" --query 'Images[0].State' --output text)"
    [[ "$state" == "pending" || "$state" == "available" ]] ||
      die "Existing source AMI $SOURCE_AMI_ID is in unsupported state $state"
    log "Reusing source AMI $SOURCE_AMI_ID in state $state"
  fi

  log "Waiting for source AMI $SOURCE_AMI_ID to become available"
  wait_for_image_available "$SOURCE_PROFILE" "$SOURCE_REGION" \
    "$SOURCE_AMI_ID" "Source"
  image="$(aws ec2 describe-images --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
    --image-ids "$SOURCE_AMI_ID")"
  jq -e --arg owner "$SOURCE_ACCOUNT_ID" '
    .Images[0] |
    .State == "available" and .OwnerId == $owner and
    .Architecture == "x86_64" and .RootDeviceName == "/dev/sda1" and
    any(.BlockDeviceMappings[];
      .DeviceName == "/dev/sda1" and .Ebs.VolumeSize == 100 and .Ebs.Encrypted == false)
  ' <<<"$image" >/dev/null || die "Source AMI does not preserve the verified root-volume baseline"
  log "Source AMI $SOURCE_AMI_ID is available and matches the source baseline"
}

ensure_source_sharing() {
  local snapshot_id encrypted_count
  local -a snapshots=()
  read -r -a snapshots <<<"$(source_snapshot_ids)"
  ((${#snapshots[@]} > 0)) || die "Source AMI $SOURCE_AMI_ID has no EBS snapshots"

  encrypted_count="$(aws ec2 describe-snapshots --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
    --snapshot-ids "${snapshots[@]}" --query 'length(Snapshots[?Encrypted==`true`])' --output text)"
  [[ "$encrypted_count" == "0" ]] ||
    die "Source AMI contains encrypted snapshots; do not attempt sharing without a customer-managed KMS design"

  aws ec2 modify-image-attribute --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
    --image-id "$SOURCE_AMI_ID" --launch-permission "Add=[{UserId=$TARGET_ACCOUNT_ID}]"
  log "Ensured private AMI launch permission for target account $TARGET_ACCOUNT_ID"

  for snapshot_id in "${snapshots[@]}"; do
    aws ec2 modify-snapshot-attribute --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
      --snapshot-id "$snapshot_id" --attribute createVolumePermission \
      --operation-type add --user-ids "$TARGET_ACCOUNT_ID"
    log "Ensured private snapshot permission on $snapshot_id"
  done
}

copy_or_reuse_target_ami() {
  local state snapshot_id encrypted_count image
  local -a snapshots=()
  find_target_ami
  if [[ -z "$TARGET_AMI_ID" ]]; then
    log "Copying source AMI $SOURCE_AMI_ID to an encrypted target-owned AMI in $TARGET_REGION"
    TARGET_AMI_ID="$(aws ec2 copy-image --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --source-region "$SOURCE_REGION" --source-image-id "$SOURCE_AMI_ID" \
      --name "$TARGET_AMI_NAME" \
      --description "Target-owned encrypted Keycloak migration image" \
      --encrypted --query ImageId --output text)"
    aws ec2 create-tags --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --resources "$TARGET_AMI_ID" \
      --tags "Key=Name,Value=$TARGET_AMI_NAME" "Key=Migration,Value=$MIGRATION_TAG" "Key=Stage,Value=target-copy"
    log "Started target AMI copy $TARGET_AMI_ID"
  else
    state="$(aws ec2 describe-images --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --image-ids "$TARGET_AMI_ID" --query 'Images[0].State' --output text)"
    [[ "$state" == "pending" || "$state" == "available" ]] ||
      die "Existing target AMI $TARGET_AMI_ID is in unsupported state $state"
    log "Reusing target AMI $TARGET_AMI_ID in state $state"
  fi

  log "Waiting for target AMI $TARGET_AMI_ID to become available"
  wait_for_image_available "$TARGET_PROFILE" "$TARGET_REGION" \
    "$TARGET_AMI_ID" "Target"

  image="$(aws ec2 describe-images --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --image-ids "$TARGET_AMI_ID")"
  jq -e --arg owner "$TARGET_ACCOUNT_ID" '
    .Images[0] |
    .State == "available" and .OwnerId == $owner and
    .Architecture == "x86_64" and .RootDeviceName == "/dev/sda1" and
    any(.BlockDeviceMappings[];
      .DeviceName == "/dev/sda1" and .Ebs.VolumeSize == 100 and .Ebs.Encrypted == true)
  ' <<<"$image" >/dev/null ||
    die "Target AMI does not preserve the verified architecture, root size, ownership, and encryption baseline"

  read -r -a snapshots <<<"$(target_snapshot_ids)"
  ((${#snapshots[@]} > 0)) || die "Target AMI $TARGET_AMI_ID has no EBS snapshots"
  encrypted_count="$(aws ec2 describe-snapshots --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --snapshot-ids "${snapshots[@]}" --query 'length(Snapshots[?Encrypted==`true`])' --output text)"
  [[ "$encrypted_count" == "${#snapshots[@]}" ]] || die "One or more target snapshots are not encrypted"

  for snapshot_id in "${snapshots[@]}"; do
    aws ec2 create-tags --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --resources "$snapshot_id" \
      --tags "Key=Name,Value=$TARGET_AMI_NAME" "Key=Migration,Value=$MIGRATION_TAG" "Key=Stage,Value=target-copy"
  done
  log "Verified target-owned encrypted AMI $TARGET_AMI_ID and ${#snapshots[@]} encrypted snapshot(s)"
}

show_status() {
  local state permissions snapshot_id snapshot_permissions
  local -a snapshots=()
  find_source_ami
  find_target_ami

  if [[ -z "$SOURCE_AMI_ID" ]]; then
    log "Source AMI: not created"
  else
    state="$(aws ec2 describe-images --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
      --image-ids "$SOURCE_AMI_ID" --query 'Images[0].State' --output text)"
    permissions="$(aws ec2 describe-image-attribute --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
      --image-id "$SOURCE_AMI_ID" --attribute launchPermission \
      --query "contains(LaunchPermissions[].UserId, '$TARGET_ACCOUNT_ID')" --output text)"
    log "Source AMI: $SOURCE_AMI_ID ($state); shared with target: $permissions"
    read -r -a snapshots <<<"$(source_snapshot_ids)"
    for snapshot_id in "${snapshots[@]}"; do
      snapshot_permissions="$(aws ec2 describe-snapshot-attribute --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
        --snapshot-id "$snapshot_id" --attribute createVolumePermission \
        --query "contains(CreateVolumePermissions[].UserId, '$TARGET_ACCOUNT_ID')" --output text)"
      log "Source snapshot: $snapshot_id; shared with target: $snapshot_permissions"
    done
  fi

  if [[ -z "$TARGET_AMI_ID" ]]; then
    log "Target AMI: not copied"
  else
    state="$(aws ec2 describe-images --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --image-ids "$TARGET_AMI_ID" --query 'Images[0].State' --output text)"
    log "Target AMI: $TARGET_AMI_ID ($state); owner: $TARGET_ACCOUNT_ID; region: $TARGET_REGION"
  fi
}


resource_exists() {
  "$@" >/dev/null 2>&1
}

verify_target_network_and_certificate() {
  local vpc subnet route_table nat_id nat certificate public_subnet

  vpc="$(aws ec2 describe-vpcs --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --vpc-ids "$TARGET_VPC_ID")"
  jq -e '.Vpcs[0].State == "available" and .Vpcs[0].CidrBlock == "10.0.0.0/16"'     <<<"$vpc" >/dev/null || die "Target VPC $TARGET_VPC_ID is unavailable or no longer matches 10.0.0.0/16"

  subnet="$(aws ec2 describe-subnets --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --subnet-ids "$TARGET_EC2_SUBNET_ID")"
  jq -e --arg vpc "$TARGET_VPC_ID" '
    .Subnets[0] |
    .State == "available" and .VpcId == $vpc and
    .AvailabilityZone == "eu-central-1a" and .MapPublicIpOnLaunch == false
  ' <<<"$subnet" >/dev/null ||
    die "Target EC2 subnet $TARGET_EC2_SUBNET_ID is not the verified private eu-central-1a subnet"

  route_table="$(aws ec2 describe-route-tables --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --filters "Name=association.subnet-id,Values=$TARGET_EC2_SUBNET_ID")"
  nat_id="$(jq -r '
    [.RouteTables[].Routes[] |
      select(.DestinationCidrBlock == "0.0.0.0/0" and .State == "active") |
      .NatGatewayId // empty] | first // empty
  ' <<<"$route_table")"
  [[ -n "$nat_id" ]] || die "Private EC2 subnet has no active default route through a NAT gateway"
  nat="$(aws ec2 describe-nat-gateways --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --nat-gateway-ids "$nat_id")"
  [[ "$(jq -r '.NatGateways[0].State' <<<"$nat")" == "available" ]] ||
    die "NAT gateway $nat_id is not available"

  for public_subnet in "${TARGET_ALB_SUBNETS[@]}"; do
    subnet="$(aws ec2 describe-subnets --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --subnet-ids "$public_subnet")"
    jq -e --arg vpc "$TARGET_VPC_ID" '.Subnets[0] | .State == "available" and .VpcId == $vpc'       <<<"$subnet" >/dev/null || die "ALB subnet $public_subnet is unavailable or outside $TARGET_VPC_ID"
    route_table="$(aws ec2 describe-route-tables --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --filters "Name=association.subnet-id,Values=$public_subnet")"
    jq -e 'any(.RouteTables[].Routes[];
      .DestinationCidrBlock == "0.0.0.0/0" and .State == "active" and
      ((.GatewayId // "") | startswith("igw-"))
    )' <<<"$route_table" >/dev/null || die "ALB subnet $public_subnet has no active internet-gateway route"
  done

  certificate="$(aws acm describe-certificate --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --certificate-arn "$TARGET_CERTIFICATE_ARN")"
  jq -e '.Certificate |
    .Status == "ISSUED" and .DomainName == "*.solutions.adorsys.com"
  ' <<<"$certificate" >/dev/null || die "Target wildcard certificate is not issued"

  log "Verified target VPC, private EC2 subnet, NAT egress, three public ALB subnets, and issued certificate"
}

verify_target_ami_available() {
  local image
  find_target_ami
  [[ -n "$TARGET_AMI_ID" ]] || die "Target AMI does not exist; run --prepare-ami first"
  image="$(aws ec2 describe-images --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --image-ids "$TARGET_AMI_ID")"
  jq -e --arg owner "$TARGET_ACCOUNT_ID" '
    .Images[0] |
    .State == "available" and .OwnerId == $owner and
    .Architecture == "x86_64" and .RootDeviceName == "/dev/sda1" and
    any(.BlockDeviceMappings[];
      .DeviceName == "/dev/sda1" and .Ebs.VolumeSize == 100 and .Ebs.Encrypted == true)
  ' <<<"$image" >/dev/null || die "Target AMI is not available, target-owned, x86_64, 100-GiB, and encrypted"
  log "Verified target AMI $TARGET_AMI_ID"
}

ensure_target_instance_profile() {
  local trust_policy role profile role_count profile_role
  trust_policy='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

  if ! resource_exists aws iam get-role --profile "$TARGET_PROFILE" --role-name "$TARGET_ROLE_NAME"; then
    aws iam create-role --profile "$TARGET_PROFILE" --role-name "$TARGET_ROLE_NAME"       --description "SSM access for the migrated Keycloak EC2 instance"       --assume-role-policy-document "$trust_policy" >/dev/null
    log "Created IAM role $TARGET_ROLE_NAME"
  else
    log "Reusing IAM role $TARGET_ROLE_NAME"
  fi

  role="$(aws iam get-role --profile "$TARGET_PROFILE" --role-name "$TARGET_ROLE_NAME")"
  jq -e '.Role.AssumeRolePolicyDocument.Statement |
    any(.[]; .Effect == "Allow" and .Principal.Service == "ec2.amazonaws.com" and
      ((.Action == "sts:AssumeRole") or
       ((.Action | type) == "array" and (.Action | index("sts:AssumeRole") != null))))
  ' <<<"$role" >/dev/null || die "Existing IAM role $TARGET_ROLE_NAME does not trust EC2"

  aws iam attach-role-policy --profile "$TARGET_PROFILE" --role-name "$TARGET_ROLE_NAME"     --policy-arn "$SSM_POLICY_ARN"
  log "Ensured AmazonSSMManagedInstanceCore on $TARGET_ROLE_NAME"

  if ! resource_exists aws iam get-instance-profile --profile "$TARGET_PROFILE"     --instance-profile-name "$TARGET_INSTANCE_PROFILE_NAME"; then
    aws iam create-instance-profile --profile "$TARGET_PROFILE"       --instance-profile-name "$TARGET_INSTANCE_PROFILE_NAME" >/dev/null
    log "Created instance profile $TARGET_INSTANCE_PROFILE_NAME"
  else
    log "Reusing instance profile $TARGET_INSTANCE_PROFILE_NAME"
  fi

  profile="$(aws iam get-instance-profile --profile "$TARGET_PROFILE"     --instance-profile-name "$TARGET_INSTANCE_PROFILE_NAME")"
  role_count="$(jq '.InstanceProfile.Roles | length' <<<"$profile")"
  if [[ "$role_count" == "0" ]]; then
    aws iam add-role-to-instance-profile --profile "$TARGET_PROFILE"       --instance-profile-name "$TARGET_INSTANCE_PROFILE_NAME" --role-name "$TARGET_ROLE_NAME"
    log "Added role $TARGET_ROLE_NAME to instance profile $TARGET_INSTANCE_PROFILE_NAME"
  else
    profile_role="$(jq -r '.InstanceProfile.Roles[0].RoleName' <<<"$profile")"
    [[ "$role_count" == "1" && "$profile_role" == "$TARGET_ROLE_NAME" ]] ||
      die "Instance profile $TARGET_INSTANCE_PROFILE_NAME contains an unexpected role"
  fi
}

get_security_group_id() {
  local name id
  name="$1"
  id="$(aws ec2 describe-security-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --filters "Name=vpc-id,Values=$TARGET_VPC_ID" "Name=group-name,Values=$name"     --query 'SecurityGroups[0].GroupId' --output text)"
  [[ "$id" != "None" ]] || id=""
  printf '%s' "$id"
}

ensure_target_security_groups() {
  local alb_group ec2_group

  TARGET_ALB_SG_ID="$(get_security_group_id "$TARGET_ALB_SG_NAME")"
  if [[ -z "$TARGET_ALB_SG_ID" ]]; then
    TARGET_ALB_SG_ID="$(aws ec2 create-security-group --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --vpc-id "$TARGET_VPC_ID" --group-name "$TARGET_ALB_SG_NAME"       --description "HTTPS entry for migrated Keycloak"       --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$TARGET_ALB_SG_NAME},{Key=Migration,Value=$MIGRATION_TAG}]"       --query GroupId --output text)"
    log "Created ALB security group $TARGET_ALB_SG_ID"
  else
    log "Reusing ALB security group $TARGET_ALB_SG_ID"
  fi

  TARGET_EC2_SG_ID="$(get_security_group_id "$TARGET_EC2_SG_NAME")"
  if [[ -z "$TARGET_EC2_SG_ID" ]]; then
    TARGET_EC2_SG_ID="$(aws ec2 create-security-group --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --vpc-id "$TARGET_VPC_ID" --group-name "$TARGET_EC2_SG_NAME"       --description "ALB-only HTTP entry for migrated Keycloak EC2"       --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$TARGET_EC2_SG_NAME},{Key=Migration,Value=$MIGRATION_TAG}]"       --query GroupId --output text)"
    log "Created EC2 security group $TARGET_EC2_SG_ID"
  else
    log "Reusing EC2 security group $TARGET_EC2_SG_ID"
  fi

  alb_group="$(aws ec2 describe-security-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --group-ids "$TARGET_ALB_SG_ID")"
  if ! jq -e 'any(.SecurityGroups[0].IpPermissions[];
      .IpProtocol == "tcp" and .FromPort == 443 and .ToPort == 443 and
      any(.IpRanges[]?; .CidrIp == "0.0.0.0/0")
    )' <<<"$alb_group" >/dev/null; then
    aws ec2 authorize-security-group-ingress --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --group-id "$TARGET_ALB_SG_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0 >/dev/null
    log "Added public HTTPS ingress to $TARGET_ALB_SG_ID"
  fi

  ec2_group="$(aws ec2 describe-security-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --group-ids "$TARGET_EC2_SG_ID")"
  if ! jq -e --arg source "$TARGET_ALB_SG_ID" --argjson port "$TARGET_PORT" '
    any(.SecurityGroups[0].IpPermissions[];
      .IpProtocol == "tcp" and .FromPort == $port and .ToPort == $port and
      any(.UserIdGroupPairs[]?; .GroupId == $source)
    )' <<<"$ec2_group" >/dev/null; then
    aws ec2 authorize-security-group-ingress --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --group-id "$TARGET_EC2_SG_ID" --protocol tcp --port "$TARGET_PORT"       --source-group "$TARGET_ALB_SG_ID" >/dev/null
    log "Added ALB-only port $TARGET_PORT ingress to $TARGET_EC2_SG_ID"
  fi

  alb_group="$(aws ec2 describe-security-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --group-ids "$TARGET_ALB_SG_ID")"
  ec2_group="$(aws ec2 describe-security-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --group-ids "$TARGET_EC2_SG_ID")"
  jq -e '.SecurityGroups[0].IpPermissions | length == 1' <<<"$alb_group" >/dev/null ||
    die "ALB security group contains unexpected additional inbound rules"
  jq -e '.SecurityGroups[0].IpPermissions | length == 1' <<<"$ec2_group" >/dev/null ||
    die "EC2 security group contains unexpected additional inbound rules"
  log "Verified least-privilege target security groups"
}

ensure_target_group() {
  local group
  if group="$(aws elbv2 describe-target-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --names "$TARGET_GROUP_NAME" 2>/dev/null)"; then
    TARGET_GROUP_ARN="$(jq -r '.TargetGroups[0].TargetGroupArn' <<<"$group")"
    log "Reusing target group $TARGET_GROUP_NAME"
  else
    TARGET_GROUP_ARN="$(aws elbv2 create-target-group --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --name "$TARGET_GROUP_NAME" --protocol HTTP --port "$TARGET_PORT"       --vpc-id "$TARGET_VPC_ID" --target-type instance --protocol-version HTTP1       --health-check-enabled --health-check-protocol HTTP --health-check-port traffic-port       --health-check-path "$TARGET_HEALTH_PATH" --matcher HttpCode=200       --health-check-interval-seconds 30 --health-check-timeout-seconds 5       --healthy-threshold-count 2 --unhealthy-threshold-count 3       --query 'TargetGroups[0].TargetGroupArn' --output text)"
    aws elbv2 add-tags --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --resource-arns "$TARGET_GROUP_ARN"       --tags "Key=Name,Value=$TARGET_GROUP_NAME" "Key=Migration,Value=$MIGRATION_TAG"
    log "Created target group $TARGET_GROUP_NAME"
  fi

  group="$(aws elbv2 describe-target-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --target-group-arns "$TARGET_GROUP_ARN")"
  jq -e --arg vpc "$TARGET_VPC_ID" --arg path "$TARGET_HEALTH_PATH" --argjson port "$TARGET_PORT" '
    .TargetGroups[0] |
    .VpcId == $vpc and .Protocol == "HTTP" and .Port == $port and
    .TargetType == "instance" and .HealthCheckProtocol == "HTTP" and
    .HealthCheckPath == $path and .Matcher.HttpCode == "200"
  ' <<<"$group" >/dev/null || die "Existing target group does not match the verified Keycloak route"
  log "Verified target group HTTP:$TARGET_PORT health $TARGET_HEALTH_PATH=200"
}

ensure_target_alb() {
  local alb expected_subnets
  expected_subnets="$(printf '%s
' "${TARGET_ALB_SUBNETS[@]}" | jq -R . | jq -s .)"

  if alb="$(aws elbv2 describe-load-balancers --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --names "$TARGET_ALB_NAME" 2>/dev/null)"; then
    log "Reusing target ALB $TARGET_ALB_NAME"
  else
    alb="$(aws elbv2 create-load-balancer --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --name "$TARGET_ALB_NAME" --type application --scheme internet-facing       --ip-address-type ipv4 --security-groups "$TARGET_ALB_SG_ID"       --subnets "${TARGET_ALB_SUBNETS[@]}"       --tags "Key=Name,Value=$TARGET_ALB_NAME" "Key=Migration,Value=$MIGRATION_TAG")"
    log "Created target ALB $TARGET_ALB_NAME"
  fi

  TARGET_ALB_ARN="$(jq -r '.LoadBalancers[0].LoadBalancerArn' <<<"$alb")"
  log "Waiting for target ALB to become available"
  aws elbv2 wait load-balancer-available --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" --load-balancer-arns "$TARGET_ALB_ARN"
  alb="$(aws elbv2 describe-load-balancers --profile "$TARGET_PROFILE" \
    --region "$TARGET_REGION" --load-balancer-arns "$TARGET_ALB_ARN")"
  TARGET_ALB_DNS="$(jq -r '.LoadBalancers[0].DNSName' <<<"$alb")"
  TARGET_ALB_ZONE_ID="$(jq -r '.LoadBalancers[0].CanonicalHostedZoneId' <<<"$alb")"

  jq -e --arg vpc "$TARGET_VPC_ID" --arg sg "$TARGET_ALB_SG_ID" --argjson subnets "$expected_subnets" '
    .LoadBalancers[0] |
    .State.Code == "active" and .Scheme == "internet-facing" and .Type == "application" and
    .VpcId == $vpc and (.SecurityGroups == [$sg]) and
    (([.AvailabilityZones[].SubnetId] | sort) == ($subnets | sort))
  ' <<<"$alb" >/dev/null || die "Existing target ALB does not match the verified target design"
  log "Verified target ALB $TARGET_ALB_DNS"
}

ensure_target_listener() {
  local listeners listener
  listeners="$(aws elbv2 describe-listeners --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --load-balancer-arn "$TARGET_ALB_ARN")"
  TARGET_LISTENER_ARN="$(jq -r '[.Listeners[] | select(.Port == 443)][0].ListenerArn // empty' <<<"$listeners")"

  if [[ -z "$TARGET_LISTENER_ARN" ]]; then
    TARGET_LISTENER_ARN="$(aws elbv2 create-listener --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --load-balancer-arn "$TARGET_ALB_ARN" --protocol HTTPS --port 443       --certificates "CertificateArn=$TARGET_CERTIFICATE_ARN" --ssl-policy "$TARGET_SSL_POLICY"       --default-actions "Type=forward,TargetGroupArn=$TARGET_GROUP_ARN"       --query 'Listeners[0].ListenerArn' --output text)"
    log "Created HTTPS listener on target ALB"
  else
    log "Reusing HTTPS listener on target ALB"
  fi

  listener="$(aws elbv2 describe-listeners --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --listener-arns "$TARGET_LISTENER_ARN")"
  jq -e --arg cert "$TARGET_CERTIFICATE_ARN" --arg policy "$TARGET_SSL_POLICY" --arg tg "$TARGET_GROUP_ARN" '
    .Listeners[0] |
    .Protocol == "HTTPS" and .Port == 443 and .SslPolicy == $policy and
    any(.Certificates[]; .CertificateArn == $cert) and
    any(.DefaultActions[]; .Type == "forward" and .TargetGroupArn == $tg)
  ' <<<"$listener" >/dev/null || die "Existing HTTPS listener does not match certificate, policy, and target group"
  log "Verified HTTPS listener and wildcard certificate"
}

show_manual_launch_settings() {
  log "TARGET FOUNDATION READY; manually launch one EC2 instance with:"
  log "  AMI: $TARGET_AMI_ID ($TARGET_AMI_NAME)"
  log "  Name tag: Keycloak-demo-migration"
  log "  Migration tag: $MIGRATION_TAG"
  log "  Instance type: t3.medium"
  log "  VPC: $TARGET_VPC_ID"
  log "  Private subnet: $TARGET_EC2_SUBNET_ID"
  log "  Auto-assign public IP: disabled"
  log "  Security group: $TARGET_EC2_SG_ID ($TARGET_EC2_SG_NAME)"
  log "  IAM instance profile: $TARGET_INSTANCE_PROFILE_NAME"
  log "  Root: 100 GiB gp3, encrypted"
  log "  IMDSv2: required; response hop limit: 2"
  log "  Termination protection: enabled"
  log "  Key pair: optional; select one only if your approved access method needs it"
  log "The AMI carries enabled host Nginx, so Nginx should start automatically after boot."
  log "Do not register the instance until PostgreSQL is restored and ./keycloak-ssi.sh setup -d succeeds."
}

prepare_target_foundation() {
  verify_target_ami_available
  verify_target_network_and_certificate
  ensure_target_instance_profile
  ensure_target_security_groups
  ensure_target_group
  ensure_target_alb
  ensure_target_listener
  show_manual_launch_settings
  log "No EC2 instance was launched and no DNS record was changed"
}

discover_target_foundation() {
  local alb listener
  TARGET_ALB_SG_ID="$(get_security_group_id "$TARGET_ALB_SG_NAME")"
  TARGET_EC2_SG_ID="$(get_security_group_id "$TARGET_EC2_SG_NAME")"

  TARGET_GROUP_ARN="$(aws elbv2 describe-target-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --names "$TARGET_GROUP_NAME" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)"
  [[ "$TARGET_GROUP_ARN" != "None" ]] || TARGET_GROUP_ARN=""

  if alb="$(aws elbv2 describe-load-balancers --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --names "$TARGET_ALB_NAME" 2>/dev/null)"; then
    TARGET_ALB_ARN="$(jq -r '.LoadBalancers[0].LoadBalancerArn' <<<"$alb")"
    TARGET_ALB_DNS="$(jq -r '.LoadBalancers[0].DNSName' <<<"$alb")"
    TARGET_ALB_ZONE_ID="$(jq -r '.LoadBalancers[0].CanonicalHostedZoneId' <<<"$alb")"
    listener="$(aws elbv2 describe-listeners --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --load-balancer-arn "$TARGET_ALB_ARN")"
    TARGET_LISTENER_ARN="$(jq -r '[.Listeners[] | select(.Port == 443)][0].ListenerArn // empty' <<<"$listener")"
  fi
}

find_target_instance_by_tag() {
  local instances
  [[ -n "$TARGET_INSTANCE_ID" ]] && return 0
  instances="$(aws ec2 describe-instances --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --filters "Name=tag:Migration,Values=$MIGRATION_TAG"       "Name=instance-state-name,Values=pending,running,stopping,stopped")"
  TARGET_INSTANCE_ID="$(jq -r '
    [.Reservations[].Instances[]] | sort_by(.LaunchTime) | last | .InstanceId // empty
  ' <<<"$instances")"
}

show_target_status() {
  local state ping
  find_target_ami
  discover_target_foundation
  find_target_instance_by_tag

  if [[ -n "$TARGET_AMI_ID" ]]; then
    state="$(aws ec2 describe-images --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --image-ids "$TARGET_AMI_ID" --query 'Images[0].State' --output text)"
    log "Target AMI: $TARGET_AMI_ID ($state)"
  else
    log "Target AMI: missing"
  fi

  resource_exists aws iam get-role --profile "$TARGET_PROFILE" --role-name "$TARGET_ROLE_NAME" &&
    log "IAM role: present ($TARGET_ROLE_NAME)" || log "IAM role: missing"
  resource_exists aws iam get-instance-profile --profile "$TARGET_PROFILE"     --instance-profile-name "$TARGET_INSTANCE_PROFILE_NAME" &&
    log "Instance profile: present ($TARGET_INSTANCE_PROFILE_NAME)" || log "Instance profile: missing"

  [[ -n "$TARGET_ALB_SG_ID" ]] && log "ALB security group: $TARGET_ALB_SG_ID" || log "ALB security group: missing"
  [[ -n "$TARGET_EC2_SG_ID" ]] && log "EC2 security group: $TARGET_EC2_SG_ID" || log "EC2 security group: missing"
  [[ -n "$TARGET_GROUP_ARN" ]] && log "Target group: $TARGET_GROUP_ARN" || log "Target group: missing"
  [[ -n "$TARGET_ALB_ARN" ]] && log "ALB: $TARGET_ALB_DNS" || log "ALB: missing"
  [[ -n "$TARGET_LISTENER_ARN" ]] && log "HTTPS listener: $TARGET_LISTENER_ARN" || log "HTTPS listener: missing"

  if [[ -n "$TARGET_INSTANCE_ID" ]]; then
    state="$(aws ec2 describe-instances --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --instance-ids "$TARGET_INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text)"
    ping="$(aws ssm describe-instance-information --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --filters "Key=InstanceIds,Values=$TARGET_INSTANCE_ID"       --query 'InstanceInformationList[0].PingStatus' --output text)"
    log "Target EC2: $TARGET_INSTANCE_ID ($state); SSM: $ping"
    if [[ -n "$TARGET_GROUP_ARN" ]]; then
      aws elbv2 describe-target-health --profile "$TARGET_PROFILE" --region "$TARGET_REGION"         --target-group-arn "$TARGET_GROUP_ARN" --targets "Id=$TARGET_INSTANCE_ID,Port=$TARGET_PORT"         --query 'TargetHealthDescriptions[0].TargetHealth' --output json
    fi
  else
    log "Target EC2: not found; pass TARGET_INSTANCE_ID=i-... if it was launched without the Migration tag"
  fi
}

validate_target_instance() {
  local instance root_volume_id volume termination_protection profile_arn
  [[ "$TARGET_INSTANCE_ID" =~ ^i-[0-9a-f]+$ ]] || die "Invalid target instance ID: $TARGET_INSTANCE_ID"
  verify_target_ami_available
  discover_target_foundation
  [[ -n "$TARGET_EC2_SG_ID" && -n "$TARGET_GROUP_ARN" && -n "$TARGET_ALB_ARN" && -n "$TARGET_LISTENER_ARN" ]] ||
    die "Target foundation is incomplete; run --prepare-target --execute first"

  instance="$(aws ec2 describe-instances --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --instance-ids "$TARGET_INSTANCE_ID")"
  jq -e --arg image "$TARGET_AMI_ID" --arg vpc "$TARGET_VPC_ID"     --arg subnet "$TARGET_EC2_SUBNET_ID" --arg sg "$TARGET_EC2_SG_ID"     --arg profile "$TARGET_INSTANCE_PROFILE_NAME" --arg migration "$MIGRATION_TAG" '
    .Reservations[0].Instances[0] |
    .State.Name == "running" and .ImageId == $image and .Architecture == "x86_64" and
    .InstanceType == "t3.medium" and .VpcId == $vpc and .SubnetId == $subnet and
    (.PublicIpAddress == null) and
    (.SecurityGroups | any(.GroupId == $sg)) and
    (.IamInstanceProfile != null and (.IamInstanceProfile.Arn | endswith("/" + $profile))) and
    .MetadataOptions.HttpTokens == "required" and
    .MetadataOptions.HttpPutResponseHopLimit == 2 and
    (.Tags | any(.Key == "Migration" and .Value == $migration))
  ' <<<"$instance" >/dev/null || die "Target EC2 does not match the required AMI, type, network, SG, profile, IMDS, and tags"

  root_volume_id="$(jq -r '
    .Reservations[0].Instances[0] as $i |
    $i.BlockDeviceMappings[] | select(.DeviceName == $i.RootDeviceName) | .Ebs.VolumeId
  ' <<<"$instance")"
  volume="$(aws ec2 describe-volumes --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --volume-ids "$root_volume_id")"
  jq -e '.Volumes[0] | .State == "in-use" and .Encrypted == true and
    .VolumeType == "gp3" and .Size >= 100
  ' <<<"$volume" >/dev/null || die "Target root EBS volume is not encrypted gp3 with at least 100 GiB"

  termination_protection="$(aws ec2 describe-instance-attribute --profile "$TARGET_PROFILE"     --region "$TARGET_REGION" --instance-id "$TARGET_INSTANCE_ID"     --attribute disableApiTermination --query 'DisableApiTermination.Value' --output text)"
  [[ "$termination_protection" == "True" || "$termination_protection" == "true" ]] ||
    log "WARNING: termination protection is not enabled on $TARGET_INSTANCE_ID"

  profile_arn="$(jq -r '.Reservations[0].Instances[0].IamInstanceProfile.Arn' <<<"$instance")"
  log "Verified target EC2 $TARGET_INSTANCE_ID, encrypted root $root_volume_id, and profile $profile_arn"
}

register_and_test_target() {
  local target_health
  require_command curl
  validate_target_instance

  aws elbv2 register-targets --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --target-group-arn "$TARGET_GROUP_ARN" --targets "Id=$TARGET_INSTANCE_ID,Port=$TARGET_PORT"
  log "Registered $TARGET_INSTANCE_ID:$TARGET_PORT in $TARGET_GROUP_NAME"

  if ! aws elbv2 wait target-in-service --profile "$TARGET_PROFILE" --region "$TARGET_REGION"     --target-group-arn "$TARGET_GROUP_ARN" --targets "Id=$TARGET_INSTANCE_ID,Port=$TARGET_PORT"; then
    target_health="$(aws elbv2 describe-target-health --profile "$TARGET_PROFILE" --region "$TARGET_REGION"       --target-group-arn "$TARGET_GROUP_ARN" --targets "Id=$TARGET_INSTANCE_ID,Port=$TARGET_PORT")"
    jq '.TargetHealthDescriptions[0].TargetHealth' <<<"$target_health"
    die "Target did not become healthy; verify Nginx port 80 and $TARGET_HEALTH_PATH"
  fi
  log "Verified healthy target $TARGET_INSTANCE_ID:$TARGET_PORT"

  curl --fail --silent --show-error --noproxy '*'     --connect-to "$TARGET_DOMAIN:443:$TARGET_ALB_DNS:443"     "https://$TARGET_DOMAIN$TARGET_HEALTH_PATH" >/dev/null ||
    die "HTTPS test through target ALB failed"
  log "Verified HTTPS target ALB with production SNI/Host and no DNS change"
  log "TARGET READY: $TARGET_ALB_DNS (hosted-zone ID $TARGET_ALB_ZONE_ID)"
  log "Production DNS was not changed"
}


revoke_source_sharing() {
  local snapshot_id
  local -a snapshots=()
  find_source_ami
  find_target_ami
  [[ -n "$SOURCE_AMI_ID" ]] || die "Source AMI does not exist"
  [[ -n "$TARGET_AMI_ID" ]] || die "Target AMI does not exist; refusing to revoke source sharing"
  [[ "$(aws ec2 describe-images --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --image-ids "$TARGET_AMI_ID" --query 'Images[0].State' --output text)" == "available" ]] ||
    die "Target AMI $TARGET_AMI_ID is not available; refusing to revoke source sharing"

  read -r -a snapshots <<<"$(source_snapshot_ids)"
  aws ec2 modify-image-attribute --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
    --image-id "$SOURCE_AMI_ID" --launch-permission "Remove=[{UserId=$TARGET_ACCOUNT_ID}]"
  for snapshot_id in "${snapshots[@]}"; do
    aws ec2 modify-snapshot-attribute --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
      --snapshot-id "$snapshot_id" --attribute createVolumePermission \
      --operation-type remove --user-ids "$TARGET_ACCOUNT_ID"
  done
  log "Revoked target access to source AMI $SOURCE_AMI_ID and ${#snapshots[@]} source snapshot(s)"
  log "Target-owned AMI $TARGET_AMI_ID remains available and is not modified"
}

main() {
  require_command aws
  require_command jq
  require_command tee
  initialize_logging
  verify_accounts

  case "$MODE" in
    dry-run)
      verify_source_instance
      show_plan
      log "DRY RUN COMPLETE: review this log before using --prepare-ami"
      ;;
    status)
      show_status
      ;;
    prepare-ami)
      [[ "$EXECUTE" == "true" ]] || die "--prepare-ami requires --execute"
      [[ "$BACKUP_CONFIRMED" == "true" ]] ||
        die "--prepare-ami requires --backup-confirmed after an off-instance PostgreSQL dump is verified"
      verify_source_instance
      create_or_reuse_source_ami
      ensure_source_sharing
      copy_or_reuse_target_ami
      show_status
      log "AMI PREPARATION COMPLETE"
      log "Next: run --prepare-target --execute; do not change production DNS"
      ;;
    target-status)
      show_target_status
      ;;
    prepare-target)
      [[ "$EXECUTE" == "true" ]] || die "--prepare-target requires --execute"
      prepare_target_foundation
      ;;
    register-target)
      [[ "$EXECUTE" == "true" ]] || die "--register-target requires --execute"
      register_and_test_target
      ;;
    revoke-share)
      [[ "$EXECUTE" == "true" ]] || die "--revoke-share requires --execute"
      revoke_source_sharing
      show_status
      ;;
    *) die "Unsupported mode: $MODE" ;;
  esac
}

main "$@"
