#!/usr/bin/env bash

# Migrate the nginx CORS proxy from the sandbox ECS service to a new target ECS
# service and a new target ALB. No repository workflow is required.
#
# The script has four deliberately separate modes:
#   --dry-run   Read-only discovery and CREATE/REUSE plan
#   (no flag)   Create/reuse target ECR, ECS, and ALB; test without changing DNS
#   --cutover   Revalidate the target, then UPSERT production DNS to the target ALB
#   --rollback  Revalidate the source, then UPSERT production DNS back to source
#
# Before cutover, curl --connect-to sends TLS traffic to the new ALB while keeping
# proxy.solutions.adorsys.com as the SNI and Host name. This tests the real
# certificate and proxy behavior without a temporary Route 53 record.

set -Eeuo pipefail

readonly SOURCE_ACCOUNT_ID="${SOURCE_ACCOUNT_ID:-917848404243}"
readonly TARGET_ACCOUNT_ID="${TARGET_ACCOUNT_ID:-982081049921}"
readonly SOURCE_PROFILE="${SOURCE_PROFILE:-sandbox}"
readonly TARGET_PROFILE="${TARGET_PROFILE:-default}"
readonly SOURCE_REGION="${SOURCE_REGION:-eu-north-1}"
readonly TARGET_REGION="${TARGET_REGION:-eu-central-1}"

readonly SOURCE_CLUSTER="${SOURCE_CLUSTER:-Datev_Wallet}"
readonly SOURCE_SERVICE="${SOURCE_SERVICE:-nginx-cors}"
readonly SOURCE_TASK_DEFINITION="${SOURCE_TASK_DEFINITION:-cors_proxy:6}"
readonly SOURCE_REPOSITORY="${SOURCE_REPOSITORY:-nginx_datev_wallet}"
readonly SOURCE_IMAGE_DIGEST="${SOURCE_IMAGE_DIGEST:-sha256:2f7482aeaa9a2599e2bf09fcaf32fe3132bb6d2e43c9636349fb9f2dbba9167b}"
readonly SOURCE_ALB_NAME="${SOURCE_ALB_NAME:-corsproxy}"
readonly SOURCE_ALB_DNS="${SOURCE_ALB_DNS:-corsproxy-2023641953.eu-north-1.elb.amazonaws.com}"
readonly SOURCE_ALB_ZONE_ID="${SOURCE_ALB_ZONE_ID:-Z23TAZ6LKFMNIO}"

readonly TARGET_REPOSITORY="${TARGET_REPOSITORY:-nginx_datev_wallet}"
readonly TARGET_IMAGE_TAG="${TARGET_IMAGE_TAG:-migration-${SOURCE_IMAGE_DIGEST#sha256:}}"
readonly TARGET_CLUSTER="${TARGET_CLUSTER:-Datev_Wallet}"
readonly TARGET_SERVICE="${TARGET_SERVICE:-nginx-cors}"
readonly TARGET_TASK_FAMILY="${TARGET_TASK_FAMILY:-cors_proxy}"
readonly TARGET_CONTAINER_NAME="${TARGET_CONTAINER_NAME:-nginx-proxy}"
readonly TARGET_CONTAINER_PORT="${TARGET_CONTAINER_PORT:-8080}"
# This low-traffic proxy intentionally runs one task to reduce cost. Set
# TARGET_DESIRED_COUNT=2 (or higher) before running the script when task-level
# redundancy is required.
readonly TARGET_DESIRED_COUNT="${TARGET_DESIRED_COUNT:-1}"
readonly TARGET_LOG_GROUP="${TARGET_LOG_GROUP:-/ecs/cors_proxy}"
readonly TARGET_EXECUTION_ROLE="${TARGET_EXECUTION_ROLE:-ecsTaskExecutionRole-nginx-migration}"
readonly TARGET_ALB_NAME="${TARGET_ALB_NAME:-nginx-proxy-migration}"
readonly TARGET_GROUP_NAME="${TARGET_GROUP_NAME:-nginx-proxy-targets}"
readonly TARGET_ALB_SG_NAME="${TARGET_ALB_SG_NAME:-nginx-proxy-alb-sg}"
readonly TARGET_TASK_SG_NAME="${TARGET_TASK_SG_NAME:-nginx-proxy-task-sg}"
readonly TARGET_SSL_POLICY="${TARGET_SSL_POLICY:-ELBSecurityPolicy-TLS13-1-2-2021-06}"
readonly TARGET_VPC_ID="${TARGET_VPC_ID:-vpc-073150aef0868a8af}"
readonly CERTIFICATE_DOMAIN="${CERTIFICATE_DOMAIN:-*.solutions.adorsys.com}"
readonly CERTIFICATE_ARN="${CERTIFICATE_ARN:-arn:aws:acm:eu-central-1:982081049921:certificate/d556613f-db8a-44cb-b4f2-bf360443346a}"

readonly HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-Z02911502N07V5SNAMLHL}"
readonly HOSTED_ZONE_NAME="${HOSTED_ZONE_NAME:-solutions.adorsys.com.}"
readonly PROXY_DOMAIN="${PROXY_DOMAIN:-proxy.solutions.adorsys.com}"
readonly PROXY_RECORD_NAME="${PROXY_RECORD_NAME:-proxy.solutions.adorsys.com.}"

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LOG_DIR="${MIGRATION_LOG_DIR:-$REPO_ROOT/.migration-logs}"
readonly -a PUBLIC_SUBNETS=(
  "subnet-053b37b6b4a517afb"
  "subnet-003d0ccab3982e90a"
  "subnet-0f88842f7789cc09a"
)
readonly -a PRIVATE_SUBNETS=(
  "subnet-01ea66e1eadb764b8"
  "subnet-02f5858452931cb05"
  "subnet-0419198c0dda051f3"
)

MODE="deploy"
WORK_DIR=""
LOG_FILE=""
TARGET_ROLE_ARN=""
TARGET_ALB_SG_ID=""
TARGET_TASK_SG_ID=""
TARGET_GROUP_ARN=""
TARGET_ALB_ARN=""
TARGET_ALB_DNS=""
TARGET_ALB_ZONE_ID=""
TARGET_TASK_DEFINITION_ARN=""

usage() {
  cat <<'EOF'
Usage: scripts/migrate-nginx-proxy.sh [--dry-run | --cutover | --rollback]

Modes:
  --dry-run   Read-only preflight and target CREATE/REUSE plan.
  no option   Create/reuse the target stack and test it without changing DNS.
  --cutover   Revalidate the deployed target and UPSERT production DNS to it.
  --rollback  Revalidate the source and UPSERT production DNS back to it.
  -h, --help  Show this help.

Always run --dry-run before the normal deployment. Review the ignored log under
.migration-logs/. Run --cutover only after the normal deployment reports TARGET
READY. The source stack is never deleted by this script.
EOF
}

log() { printf '[nginx-proxy-migration] %s\n' "$*"; }
die() { printf '[nginx-proxy-migration] ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "${WORK_DIR:-}" && -d "$WORK_DIR" ]]; then
    rm -rf -- "$WORK_DIR"
  fi
}
trap cleanup EXIT

while (($# > 0)); do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --cutover) MODE="cutover" ;;
    --rollback) MODE="rollback" ;;
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
  LOG_FILE="$LOG_DIR/nginx-proxy-$MODE-$timestamp-$$.log"
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
    die "Profile '$SOURCE_PROFILE' resolves to $source_account, expected $SOURCE_ACCOUNT_ID"
  [[ "$target_account" == "$TARGET_ACCOUNT_ID" ]] ||
    die "Profile '$TARGET_PROFILE' resolves to $target_account, expected $TARGET_ACCOUNT_ID"
  [[ "$source_account" != "$target_account" ]] || die "Source and target accounts are identical"
  log "Verified source account $source_account and target account $target_account"
}

verify_authoritative_zone() {
  local zone zone_name
  local -a route53_ns=() public_ns=()
  zone="$(aws route53 get-hosted-zone --profile "$SOURCE_PROFILE" --id "$HOSTED_ZONE_ID")"
  zone_name="$(jq -r '.HostedZone.Name' <<<"$zone")"
  [[ "$zone_name" == "$HOSTED_ZONE_NAME" ]] || die "Unexpected hosted zone name: $zone_name"
  [[ "$(jq -r '.HostedZone.Config.PrivateZone' <<<"$zone")" == "false" ]] || die "Hosted zone is private"
  mapfile -t route53_ns < <(jq -r '.DelegationSet.NameServers[]' <<<"$zone" | sort)
  mapfile -t public_ns < <(dig +short NS "${HOSTED_ZONE_NAME%.}" | sed 's/\.$//' | sort)
  [[ "$(printf '%s\n' "${route53_ns[@]}")" == "$(printf '%s\n' "${public_ns[@]}")" ]] ||
    die "Hosted zone $HOSTED_ZONE_ID is not publicly authoritative"
  log "Verified authoritative Route 53 zone $HOSTED_ZONE_ID"
}

verify_source() {
  local service task image alb
  service="$(aws ecs describe-services --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
    --cluster "$SOURCE_CLUSTER" --services "$SOURCE_SERVICE")"
  jq -e '.services[0] | .status == "ACTIVE" and .desiredCount == .runningCount and .runningCount > 0 and .pendingCount == 0' \
    <<<"$service" >/dev/null || die "Source ECS service is not stable"
  [[ "$(jq -r '.services[0].taskDefinition | split("/")[-1]' <<<"$service")" == "$SOURCE_TASK_DEFINITION" ]] ||
    die "Source service no longer uses expected task definition $SOURCE_TASK_DEFINITION"

  task="$(aws ecs describe-task-definition --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
    --task-definition "$SOURCE_TASK_DEFINITION")"
  jq -e --arg image "$SOURCE_ACCOUNT_ID.dkr.ecr.$SOURCE_REGION.amazonaws.com/$SOURCE_REPOSITORY:latest" \
    --argjson port "$TARGET_CONTAINER_PORT" '
      .taskDefinition |
      .cpu == "1024" and .memory == "3072" and .networkMode == "awsvpc" and
      any(.containerDefinitions[]; .name == "nginx-proxy" and .image == $image and
        any(.portMappings[]; .containerPort == $port))
    ' <<<"$task" >/dev/null || die "Source task definition no longer matches the migration baseline"

  image="$(aws ecr describe-images --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
    --repository-name "$SOURCE_REPOSITORY" --image-ids imageTag=latest)"
  [[ "$(jq -r '.imageDetails[0].imageDigest' <<<"$image")" == "$SOURCE_IMAGE_DIGEST" ]] ||
    die "Source latest image digest changed; review before migration"

  alb="$(aws elbv2 describe-load-balancers --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" \
    --names "$SOURCE_ALB_NAME")"
  [[ "$(jq -r '.LoadBalancers[0].State.Code' <<<"$alb")" == "active" ]] || die "Source ALB is not active"
  [[ "$(jq -r '.LoadBalancers[0].DNSName' <<<"$alb")" == "$SOURCE_ALB_DNS" ]] || die "Source ALB DNS changed"
  [[ "$(jq -r '.LoadBalancers[0].CanonicalHostedZoneId' <<<"$alb")" == "$SOURCE_ALB_ZONE_ID" ]] ||
    die "Source ALB hosted-zone ID changed"
  log "Verified healthy source ECS service, ALB, and image digest $SOURCE_IMAGE_DIGEST"
}

verify_target_foundation() {
  local vpc subnets certificate distinct_azs
  vpc="$(aws ec2 describe-vpcs --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --vpc-ids "$TARGET_VPC_ID")"
  [[ "$(jq -r '.Vpcs[0].State' <<<"$vpc")" == "available" ]] || die "Target VPC is not available"

  subnets="$(aws ec2 describe-subnets --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --subnet-ids "${PUBLIC_SUBNETS[@]}" "${PRIVATE_SUBNETS[@]}")"
  [[ "$(jq --arg vpc "$TARGET_VPC_ID" '[.Subnets[] | select(.VpcId == $vpc and .State == "available")] | length' <<<"$subnets")" -eq 6 ]] ||
    die "One or more configured target subnets are unavailable or outside $TARGET_VPC_ID"
  distinct_azs="$(jq '[.Subnets[].AvailabilityZone] | unique | length' <<<"$subnets")"
  ((distinct_azs >= 2)) || die "Target subnets do not span at least two Availability Zones"

  certificate="$(aws acm describe-certificate --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --certificate-arn "$CERTIFICATE_ARN")"
  jq -e --arg domain "$CERTIFICATE_DOMAIN" '.Certificate | .Status == "ISSUED" and .DomainName == $domain' \
    <<<"$certificate" >/dev/null || die "Target ALB certificate is not the expected issued wildcard"
  log "Verified target VPC, six subnets, and issued ALB certificate"
}

resource_exists() {
  "$@" >/dev/null 2>&1
}

print_dry_run_plan() {
  local action
  action="CREATE"
  resource_exists aws ecr describe-repositories --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --repository-names "$TARGET_REPOSITORY" && action="REUSE"
  log "$action target ECR repository $TARGET_REPOSITORY"

  action="CREATE"
  resource_exists aws iam get-role --profile "$TARGET_PROFILE" --role-name "$TARGET_EXECUTION_ROLE" && action="REUSE"
  log "$action execution role $TARGET_EXECUTION_ROLE"

  action="CREATE"
  resource_exists aws logs describe-log-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --log-group-name-prefix "$TARGET_LOG_GROUP" &&
    [[ "$(aws logs describe-log-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --log-group-name-prefix "$TARGET_LOG_GROUP" --output json |
      jq --arg name "$TARGET_LOG_GROUP" '[.logGroups[] | select(.logGroupName == $name)] | length')" != "0" ]] && action="REUSE"
  log "$action log group $TARGET_LOG_GROUP"

  action="CREATE"
  [[ "$(aws ecs describe-clusters --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --clusters "$TARGET_CLUSTER" \
    --query 'clusters[?status==`ACTIVE`] | length(@)' --output text)" != "0" ]] && action="REUSE"
  log "$action ECS cluster $TARGET_CLUSTER"

  for name in "$TARGET_ALB_SG_NAME" "$TARGET_TASK_SG_NAME"; do
    action="CREATE"
    [[ "$(aws ec2 describe-security-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --filters Name=vpc-id,Values="$TARGET_VPC_ID" Name=group-name,Values="$name" \
      --query 'length(SecurityGroups)' --output text)" != "0" ]] && action="REUSE"
    log "$action security group $name"
  done

  action="CREATE"
  resource_exists aws elbv2 describe-target-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --names "$TARGET_GROUP_NAME" && action="REUSE"
  log "$action target group $TARGET_GROUP_NAME"
  action="CREATE"
  resource_exists aws elbv2 describe-load-balancers --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --names "$TARGET_ALB_NAME" && action="REUSE"
  log "$action new target ALB $TARGET_ALB_NAME"
  log "CREATE or REUSE task definition $TARGET_TASK_FAMILY and ECS service $TARGET_SERVICE"
  log "Production DNS will not be changed"
  log "DRY RUN RESULT: PASS - review this plan before the real deployment"
}

ensure_ecr_image() {
  local source_image target_image existing_digest docker_config
  source_image="$SOURCE_ACCOUNT_ID.dkr.ecr.$SOURCE_REGION.amazonaws.com/$SOURCE_REPOSITORY@$SOURCE_IMAGE_DIGEST"
  target_image="$TARGET_ACCOUNT_ID.dkr.ecr.$TARGET_REGION.amazonaws.com/$TARGET_REPOSITORY:$TARGET_IMAGE_TAG"

  if ! resource_exists aws ecr describe-repositories --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --repository-names "$TARGET_REPOSITORY"; then
    aws ecr create-repository --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --repository-name "$TARGET_REPOSITORY" --image-tag-mutability IMMUTABLE \
      --image-scanning-configuration scanOnPush=true --encryption-configuration encryptionType=AES256 >/dev/null
    log "Created target ECR repository $TARGET_REPOSITORY"
  else
    log "Reusing target ECR repository $TARGET_REPOSITORY"
  fi

  existing_digest="$(aws ecr describe-images --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --repository-name "$TARGET_REPOSITORY" --image-ids imageTag="$TARGET_IMAGE_TAG" \
    --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || true)"
  if [[ -n "$existing_digest" && "$existing_digest" != "None" ]]; then
    [[ "$existing_digest" == "$SOURCE_IMAGE_DIGEST" ]] ||
      die "Immutable target tag $TARGET_IMAGE_TAG exists with unexpected digest $existing_digest"
    log "Reusing target image $target_image with verified digest"
    return
  fi

  docker_config="$WORK_DIR/docker-config"
  mkdir -p -- "$docker_config"
  chmod 700 "$docker_config"
  aws ecr get-login-password --profile "$SOURCE_PROFILE" --region "$SOURCE_REGION" |
    docker --config "$docker_config" login --username AWS --password-stdin \
      "$SOURCE_ACCOUNT_ID.dkr.ecr.$SOURCE_REGION.amazonaws.com" >/dev/null
  aws ecr get-login-password --profile "$TARGET_PROFILE" --region "$TARGET_REGION" |
    docker --config "$docker_config" login --username AWS --password-stdin \
      "$TARGET_ACCOUNT_ID.dkr.ecr.$TARGET_REGION.amazonaws.com" >/dev/null
  docker --config "$docker_config" buildx imagetools create --tag "$target_image" "$source_image"

  existing_digest="$(aws ecr describe-images --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --repository-name "$TARGET_REPOSITORY" --image-ids imageTag="$TARGET_IMAGE_TAG" \
    --query 'imageDetails[0].imageDigest' --output text)"
  [[ "$existing_digest" == "$SOURCE_IMAGE_DIGEST" ]] || die "Target image digest verification failed: $existing_digest"
  log "Copied and verified complete OCI image $target_image"
}

ensure_execution_role() {
  local trust_file="$WORK_DIR/ecs-trust.json" role
  jq -n '{Version:"2012-10-17",Statement:[{Effect:"Allow",Principal:{Service:"ecs-tasks.amazonaws.com"},Action:"sts:AssumeRole"}]}' >"$trust_file"
  if role="$(aws iam get-role --profile "$TARGET_PROFILE" --role-name "$TARGET_EXECUTION_ROLE" 2>/dev/null)"; then
    jq -e '.Role.AssumeRolePolicyDocument.Statement | any(.Principal.Service == "ecs-tasks.amazonaws.com")' <<<"$role" >/dev/null ||
      die "Existing role $TARGET_EXECUTION_ROLE has an unexpected trust policy"
  else
    role="$(aws iam create-role --profile "$TARGET_PROFILE" --role-name "$TARGET_EXECUTION_ROLE" \
      --assume-role-policy-document "file://$trust_file" --description "Execution role for migrated nginx ECS task")"
    log "Created execution role $TARGET_EXECUTION_ROLE"
  fi
  aws iam attach-role-policy --profile "$TARGET_PROFILE" --role-name "$TARGET_EXECUTION_ROLE" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
  TARGET_ROLE_ARN="$(jq -r '.Role.Arn' <<<"$role")"
  log "Verified target execution role $TARGET_ROLE_ARN"
}

ensure_cluster_and_logs() {
  if [[ "$(aws logs describe-log-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --log-group-name-prefix "$TARGET_LOG_GROUP" --output json |
    jq --arg name "$TARGET_LOG_GROUP" '[.logGroups[] | select(.logGroupName == $name)] | length')" == "0" ]]; then
    aws logs create-log-group --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --log-group-name "$TARGET_LOG_GROUP"
    log "Created log group $TARGET_LOG_GROUP"
  fi
  aws logs put-retention-policy --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --log-group-name "$TARGET_LOG_GROUP" --retention-in-days 30

  if [[ "$(aws ecs describe-clusters --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --clusters "$TARGET_CLUSTER" \
    --query 'clusters[?status==`ACTIVE`] | length(@)' --output text)" == "0" ]]; then
    aws ecs create-cluster --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --cluster-name "$TARGET_CLUSTER" \
      --settings name=containerInsights,value=enabled >/dev/null
    log "Created ECS cluster $TARGET_CLUSTER"
  fi
}

find_security_group() {
  aws ec2 describe-security-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --filters Name=vpc-id,Values="$TARGET_VPC_ID" Name=group-name,Values="$1" \
    --query 'SecurityGroups[0].GroupId' --output text
}

# Inspect individual rules instead of nested IpPermissions projections. This gives
# reliable exact-match checks and avoids InvalidPermission.Duplicate on reruns.
security_group_rules() {
  aws ec2 describe-security-group-rules --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --filters Name=group-id,Values="$1" --output json
}

has_public_https_rule() {
  security_group_rules "$1" | jq -e '
    any(.SecurityGroupRules[]?;
      .IsEgress == false and .IpProtocol == "tcp" and
      .FromPort == 443 and .ToPort == 443 and .CidrIpv4 == "0.0.0.0/0")
  ' >/dev/null
}

has_alb_to_task_rule() {
  local task_sg_id="$1"
  local alb_sg_id="$2"
  security_group_rules "$task_sg_id" | jq -e --arg source "$alb_sg_id" --argjson port "$TARGET_CONTAINER_PORT" '
    any(.SecurityGroupRules[]?;
      .IsEgress == false and .IpProtocol == "tcp" and
      .FromPort == $port and .ToPort == $port and
      .ReferencedGroupInfo.GroupId == $source)
  ' >/dev/null
}

authorize_public_https_rule() {
  local error_file="$WORK_DIR/alb-sg-ingress.err"
  if aws ec2 authorize-security-group-ingress --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --group-id "$TARGET_ALB_SG_ID" --protocol tcp --port 443 --cidr 0.0.0.0/0 \
    >/dev/null 2>"$error_file"; then
    log "Created public HTTPS ingress on $TARGET_ALB_SG_ID"
    return
  fi
  if grep -q 'InvalidPermission.Duplicate' "$error_file" && has_public_https_rule "$TARGET_ALB_SG_ID"; then
    log "Public HTTPS ingress was created concurrently; verified and reusing it"
    return
  fi
  die "Cannot create public HTTPS ingress: $(<"$error_file")"
}

authorize_alb_to_task_rule() {
  local error_file="$WORK_DIR/task-sg-ingress.err"
  if aws ec2 authorize-security-group-ingress --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --group-id "$TARGET_TASK_SG_ID" --protocol tcp --port "$TARGET_CONTAINER_PORT" \
    --source-group "$TARGET_ALB_SG_ID" >/dev/null 2>"$error_file"; then
    log "Created ALB-to-task ingress on $TARGET_TASK_SG_ID"
    return
  fi
  if grep -q 'InvalidPermission.Duplicate' "$error_file" &&
    has_alb_to_task_rule "$TARGET_TASK_SG_ID" "$TARGET_ALB_SG_ID"; then
    log "ALB-to-task ingress was created concurrently; verified and reusing it"
    return
  fi
  die "Cannot create ALB-to-task ingress: $(<"$error_file")"
}

ensure_security_groups() {
  local sg
  sg="$(find_security_group "$TARGET_ALB_SG_NAME")"
  if [[ "$sg" == "None" ]]; then
    sg="$(aws ec2 create-security-group --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --group-name "$TARGET_ALB_SG_NAME" --description "HTTPS entry for migrated nginx proxy" \
      --vpc-id "$TARGET_VPC_ID" --query GroupId --output text)"
    aws ec2 create-tags --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --resources "$sg" \
      --tags Key=Name,Value="$TARGET_ALB_SG_NAME" Key=ManagedBy,Value=migrate-nginx-proxy.sh
  fi
  TARGET_ALB_SG_ID="$sg"

  sg="$(find_security_group "$TARGET_TASK_SG_NAME")"
  if [[ "$sg" == "None" ]]; then
    sg="$(aws ec2 create-security-group --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --group-name "$TARGET_TASK_SG_NAME" --description "ALB-only access to migrated nginx tasks" \
      --vpc-id "$TARGET_VPC_ID" --query GroupId --output text)"
    aws ec2 create-tags --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --resources "$sg" \
      --tags Key=Name,Value="$TARGET_TASK_SG_NAME" Key=ManagedBy,Value=migrate-nginx-proxy.sh
  fi
  TARGET_TASK_SG_ID="$sg"

  if has_public_https_rule "$TARGET_ALB_SG_ID"; then
    log "Reusing existing public HTTPS ingress on $TARGET_ALB_SG_ID"
  else
    authorize_public_https_rule
  fi
  if has_alb_to_task_rule "$TARGET_TASK_SG_ID" "$TARGET_ALB_SG_ID"; then
    log "Reusing existing ALB-to-task ingress on $TARGET_TASK_SG_ID"
  else
    authorize_alb_to_task_rule
  fi
  log "Verified ALB SG $TARGET_ALB_SG_ID and task SG $TARGET_TASK_SG_ID"
}

ensure_target_group_and_alb() {
  local tg alb listener
  if tg="$(aws elbv2 describe-target-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --names "$TARGET_GROUP_NAME" 2>/dev/null)"; then
    jq -e --arg vpc "$TARGET_VPC_ID" --argjson port "$TARGET_CONTAINER_PORT" '
      .TargetGroups[0] | .VpcId == $vpc and .Protocol == "HTTP" and .Port == $port and .TargetType == "ip"
    ' <<<"$tg" >/dev/null || die "Existing target group does not match required configuration"
  else
    tg="$(aws elbv2 create-target-group --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --name "$TARGET_GROUP_NAME" --protocol HTTP --port "$TARGET_CONTAINER_PORT" --vpc-id "$TARGET_VPC_ID" \
      --target-type ip --health-check-protocol HTTP --health-check-port traffic-port --health-check-path / \
      --matcher HttpCode=200 --healthy-threshold-count 5 --unhealthy-threshold-count 2 \
      --health-check-interval-seconds 30 --health-check-timeout-seconds 5)"
    log "Created target group $TARGET_GROUP_NAME"
  fi
  TARGET_GROUP_ARN="$(jq -r '.TargetGroups[0].TargetGroupArn' <<<"$tg")"

  if alb="$(aws elbv2 describe-load-balancers --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --names "$TARGET_ALB_NAME" 2>/dev/null)"; then
    jq -e --arg vpc "$TARGET_VPC_ID" '.LoadBalancers[0] | .VpcId == $vpc and .Type == "application" and .Scheme == "internet-facing"' \
      <<<"$alb" >/dev/null || die "Existing target ALB does not match required configuration"
  else
    alb="$(aws elbv2 create-load-balancer --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --name "$TARGET_ALB_NAME" --type application --scheme internet-facing --ip-address-type ipv4 \
      --subnets "${PUBLIC_SUBNETS[@]}" --security-groups "$TARGET_ALB_SG_ID")"
    log "Created new target ALB $TARGET_ALB_NAME"
  fi
  TARGET_ALB_ARN="$(jq -r '.LoadBalancers[0].LoadBalancerArn' <<<"$alb")"
  TARGET_ALB_DNS="$(jq -r '.LoadBalancers[0].DNSName' <<<"$alb")"
  TARGET_ALB_ZONE_ID="$(jq -r '.LoadBalancers[0].CanonicalHostedZoneId' <<<"$alb")"
  aws elbv2 wait load-balancer-available --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --load-balancer-arns "$TARGET_ALB_ARN"

  listener="$(aws elbv2 describe-listeners --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --load-balancer-arn "$TARGET_ALB_ARN")"
  if [[ "$(jq '[.Listeners[] | select(.Port == 443)] | length' <<<"$listener")" == "0" ]]; then
    aws elbv2 create-listener --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --load-balancer-arn "$TARGET_ALB_ARN" --protocol HTTPS --port 443 --ssl-policy "$TARGET_SSL_POLICY" \
      --certificates CertificateArn="$CERTIFICATE_ARN" \
      --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" >/dev/null
    log "Created HTTPS listener on the new target ALB"
  else
    jq -e --arg cert "$CERTIFICATE_ARN" --arg tg "$TARGET_GROUP_ARN" '
      [.Listeners[] | select(.Port == 443)][0] |
      .Protocol == "HTTPS" and any(.Certificates[]; .CertificateArn == $cert) and
      any(.DefaultActions[]; .Type == "forward" and .TargetGroupArn == $tg)
    ' <<<"$listener" >/dev/null || die "Existing HTTPS listener has unexpected certificate or target group"
  fi
  log "Verified target ALB $TARGET_ALB_DNS and target group $TARGET_GROUP_ARN"
}

ensure_task_definition() {
  local desired_file="$WORK_DIR/task-definition.json" latest="" desired_norm actual_norm target_image
  target_image="$TARGET_ACCOUNT_ID.dkr.ecr.$TARGET_REGION.amazonaws.com/$TARGET_REPOSITORY@$SOURCE_IMAGE_DIGEST"
  jq -n --arg family "$TARGET_TASK_FAMILY" --arg role "$TARGET_ROLE_ARN" --arg image "$target_image" \
    --arg name "$TARGET_CONTAINER_NAME" --arg group "$TARGET_LOG_GROUP" --arg region "$TARGET_REGION" \
    --argjson port "$TARGET_CONTAINER_PORT" '{
      family:$family, networkMode:"awsvpc", requiresCompatibilities:["FARGATE"], cpu:"1024", memory:"3072",
      executionRoleArn:$role, runtimePlatform:{cpuArchitecture:"X86_64",operatingSystemFamily:"LINUX"},
      containerDefinitions:[{name:$name,image:$image,essential:true,
        portMappings:[{containerPort:$port,hostPort:$port,protocol:"tcp",name:"nginx-proxy-8080-tcp",appProtocol:"http"}],
        logConfiguration:{logDriver:"awslogs",options:{"awslogs-group":$group,"awslogs-region":$region,"awslogs-stream-prefix":"ecs"}}
      }]
    }' >"$desired_file"

  if latest="$(aws ecs describe-task-definition --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --task-definition "$TARGET_TASK_FAMILY" 2>/dev/null)"; then
    # Compare only fields managed by this script. AWS adds empty fields such as
    # secretOptions, which must not cause a new task revision on every rerun.
    desired_norm="$(jq -S -c '{family,cpu,memory,networkMode,requiresCompatibilities,runtimePlatform,executionRoleArn,
      containerDefinitions:[.containerDefinitions[]|{name,image,essential,
        portMappings:[.portMappings[]|{containerPort,hostPort,protocol,name,appProtocol}],
        logConfiguration:{logDriver:.logConfiguration.logDriver,options:.logConfiguration.options}}]}' "$desired_file")"
    actual_norm="$(jq -S -c '.taskDefinition|{family,cpu,memory,networkMode,requiresCompatibilities,runtimePlatform,executionRoleArn,
      containerDefinitions:[.containerDefinitions[]|{name,image,essential,
        portMappings:[.portMappings[]|{containerPort,hostPort,protocol,name,appProtocol}],
        logConfiguration:{logDriver:.logConfiguration.logDriver,options:.logConfiguration.options}}]}' <<<"$latest")"
    if [[ "$desired_norm" == "$actual_norm" ]]; then
      TARGET_TASK_DEFINITION_ARN="$(jq -r '.taskDefinition.taskDefinitionArn' <<<"$latest")"
      log "Reusing matching task definition $TARGET_TASK_DEFINITION_ARN"
      return
    fi
  fi
  TARGET_TASK_DEFINITION_ARN="$(aws ecs register-task-definition --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --cli-input-json "file://$desired_file" --query 'taskDefinition.taskDefinitionArn' --output text)"
  log "Registered task definition $TARGET_TASK_DEFINITION_ARN"
}

ensure_service() {
  local service network service_matches
  network="awsvpcConfiguration={subnets=[$(IFS=,; echo "${PRIVATE_SUBNETS[*]}")],securityGroups=[$TARGET_TASK_SG_ID],assignPublicIp=DISABLED}"
  service="$(aws ecs describe-services --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --cluster "$TARGET_CLUSTER" --services "$TARGET_SERVICE")"
  if [[ "$(jq -r '.services | length' <<<"$service")" == "0" ]]; then
    aws ecs create-service --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --cluster "$TARGET_CLUSTER" --service-name "$TARGET_SERVICE" --task-definition "$TARGET_TASK_DEFINITION_ARN" \
      --desired-count "$TARGET_DESIRED_COUNT" --launch-type FARGATE --platform-version 1.4.0 \
      --network-configuration "$network" \
      --load-balancers targetGroupArn="$TARGET_GROUP_ARN",containerName="$TARGET_CONTAINER_NAME",containerPort="$TARGET_CONTAINER_PORT" \
      --deployment-configuration 'deploymentCircuitBreaker={enable=true,rollback=true},minimumHealthyPercent=100,maximumPercent=200' >/dev/null
    log "Created ECS service $TARGET_SERVICE with $TARGET_DESIRED_COUNT tasks"
  else
    [[ "$(jq -r '.services[0].loadBalancers[0].targetGroupArn' <<<"$service")" == "$TARGET_GROUP_ARN" ]] ||
      die "Existing ECS service uses an unexpected target group"
    # Avoid replacing healthy tasks when every script-managed service field
    # already matches. Update only when configuration has actually changed.
    service_matches="$(jq -r \
      --arg task "$TARGET_TASK_DEFINITION_ARN" \
      --arg sg "$TARGET_TASK_SG_ID" \
      --argjson desired "$TARGET_DESIRED_COUNT" \
      --argjson subnets "$(printf '%s\n' "${PRIVATE_SUBNETS[@]}" | jq -R . | jq -s 'sort')" '
        .services[0] |
        .taskDefinition == $task and
        .desiredCount == $desired and
        .networkConfiguration.awsvpcConfiguration.assignPublicIp == "DISABLED" and
        (.networkConfiguration.awsvpcConfiguration.securityGroups | sort) == [$sg] and
        (.networkConfiguration.awsvpcConfiguration.subnets | sort) == $subnets
      ' <<<"$service")"
    if [[ "$service_matches" == "true" ]]; then
      log "Reusing matching ECS service $TARGET_SERVICE without forcing a deployment"
    else
      aws ecs update-service --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
        --cluster "$TARGET_CLUSTER" --service "$TARGET_SERVICE" --task-definition "$TARGET_TASK_DEFINITION_ARN" \
        --desired-count "$TARGET_DESIRED_COUNT" --network-configuration "$network" >/dev/null
      log "Updated existing ECS service $TARGET_SERVICE"
    fi
  fi
  aws ecs wait services-stable --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --cluster "$TARGET_CLUSTER" --services "$TARGET_SERVICE"
}

discover_target() {
  local alb tg service role
  alb="$(aws elbv2 describe-load-balancers --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --names "$TARGET_ALB_NAME")" ||
    die "Target ALB does not exist; run the normal deployment first"
  TARGET_ALB_ARN="$(jq -r '.LoadBalancers[0].LoadBalancerArn' <<<"$alb")"
  TARGET_ALB_DNS="$(jq -r '.LoadBalancers[0].DNSName' <<<"$alb")"
  TARGET_ALB_ZONE_ID="$(jq -r '.LoadBalancers[0].CanonicalHostedZoneId' <<<"$alb")"
  [[ "$(jq -r '.LoadBalancers[0].State.Code' <<<"$alb")" == "active" ]] || die "Target ALB is not active"
  tg="$(aws elbv2 describe-target-groups --profile "$TARGET_PROFILE" --region "$TARGET_REGION" --names "$TARGET_GROUP_NAME")"
  TARGET_GROUP_ARN="$(jq -r '.TargetGroups[0].TargetGroupArn' <<<"$tg")"
  service="$(aws ecs describe-services --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
    --cluster "$TARGET_CLUSTER" --services "$TARGET_SERVICE")"
  jq -e --arg tg "$TARGET_GROUP_ARN" --argjson desired "$TARGET_DESIRED_COUNT" '
    .services[0] | .status == "ACTIVE" and .desiredCount == $desired and .runningCount == $desired and .pendingCount == 0 and
    .loadBalancers[0].targetGroupArn == $tg
  ' <<<"$service" >/dev/null || die "Target ECS service is not stable or uses an unexpected target group"
  role="$(aws iam get-role --profile "$TARGET_PROFILE" --role-name "$TARGET_EXECUTION_ROLE")"
  TARGET_ROLE_ARN="$(jq -r '.Role.Arn' <<<"$role")"
}

wait_for_healthy_targets() {
  local attempt health healthy total
  for attempt in {1..40}; do
    health="$(aws elbv2 describe-target-health --profile "$TARGET_PROFILE" --region "$TARGET_REGION" \
      --target-group-arn "$TARGET_GROUP_ARN")"
    total="$(jq '.TargetHealthDescriptions | length' <<<"$health")"
    healthy="$(jq '[.TargetHealthDescriptions[] | select(.TargetHealth.State == "healthy")] | length' <<<"$health")"
    # During a scale-down, ALB keeps the removed target in "draining" for its
    # deregistration delay. Require the desired number of healthy targets, but
    # do not fail merely because an additional old target is draining safely.
    if ((healthy == TARGET_DESIRED_COUNT)); then
      log "Verified $healthy desired healthy ALB target(s) ($total registered, including any draining targets)"
      return
    fi
    log "Waiting for healthy targets: healthy=$healthy total=$total attempt=$attempt/40"
    sleep 15
  done
  die "Target group did not become healthy"
}

test_endpoint_through_alb() {
  # Assign positional arguments before using them in derived paths. With `set -u`,
  # referencing label in the same `local` statement can see it as unbound.
  local alb_dns="$1"
  local label="$2"
  local root_body="$WORK_DIR/$label-root"
  local headers="$WORK_DIR/$label-options.headers"
  local status
  status="$(curl --silent --show-error --max-time 30 --connect-to "$PROXY_DOMAIN:443:$alb_dns:443" \
    --output "$root_body" --write-out '%{http_code}' "https://$PROXY_DOMAIN/")"
  [[ "$status" == "200" ]] || die "$label root test returned HTTP $status"
  status="$(curl --silent --show-error --max-time 30 --connect-to "$PROXY_DOMAIN:443:$alb_dns:443" \
    --dump-header "$headers" --output /dev/null --write-out '%{http_code}' --request OPTIONS \
    --header 'Origin: https://wallet.solutions.adorsys.com' --header 'Access-Control-Request-Method: GET' \
    "https://$PROXY_DOMAIN/cors/https%3A%2F%2Fexample.com")"
  [[ "$status" == "204" ]] || die "$label CORS preflight returned HTTP $status"
  grep -Eiq '^access-control-allow-origin:[[:space:]]*\*' "$headers" || die "$label lacks expected allow-origin header"
  grep -Eiq '^access-control-allow-credentials:[[:space:]]*true' "$headers" || die "$label lacks expected credentials header"
  grep -Eiq '^access-control-allow-methods:.*GET.*POST.*OPTIONS' "$headers" || die "$label lacks expected methods"
  grep -Eiq '^access-control-allow-headers:.*Authorization.*DPoP.*OAuth-Client-Attestation' "$headers" ||
    die "$label lacks required authorization/attestation headers"
  log "$label endpoint passed TLS, root, and CORS tests through $alb_dns"
}

current_dns_record() {
  aws route53 list-resource-record-sets --profile "$SOURCE_PROFILE" --hosted-zone-id "$HOSTED_ZONE_ID" \
    --start-record-name "$PROXY_RECORD_NAME" --start-record-type A --max-items 1 \
    --query "ResourceRecordSets[?Name=='$PROXY_RECORD_NAME' && Type=='A'] | [0]" --output json
}

upsert_dns_alias() {
  local dns_name="$1" zone_id="$2" description="$3" change_file="$WORK_DIR/dns-change.json" change_id
  jq -n --arg name "$PROXY_RECORD_NAME" --arg dns "dualstack.$dns_name." --arg zone "$zone_id" --arg comment "$description" '{
    Comment:$comment, Changes:[{Action:"UPSERT",ResourceRecordSet:{Name:$name,Type:"A",AliasTarget:{HostedZoneId:$zone,DNSName:$dns,EvaluateTargetHealth:true}}}]
  }' >"$change_file"
  change_id="$(aws route53 change-resource-record-sets --profile "$SOURCE_PROFILE" --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "file://$change_file" --query ChangeInfo.Id --output text)"
  aws route53 wait resource-record-sets-changed --profile "$SOURCE_PROFILE" --id "$change_id"
  log "Route 53 change is INSYNC: $description"
}

cutover() {
  local record current_dns backup
  discover_target
  wait_for_healthy_targets
  test_endpoint_through_alb "$TARGET_ALB_DNS" target
  record="$(current_dns_record)"
  current_dns="$(jq -r '.AliasTarget.DNSName // empty' <<<"$record" | sed 's/^dualstack\.//;s/\.$//')"
  if [[ "$current_dns" == "$TARGET_ALB_DNS" ]]; then
    log "Production DNS already points to target ALB; no DNS change required"
  else
    [[ "$current_dns" == "$SOURCE_ALB_DNS" ]] || die "Production DNS points to unexpected target '$current_dns'"
    backup="$LOG_DIR/nginx-proxy-dns-before-cutover-$(date -u +%Y%m%dT%H%M%SZ).json"
    printf '%s\n' "$record" >"$backup"
    chmod 600 "$backup"
    log "Saved rollback DNS record to $backup"
    upsert_dns_alias "$TARGET_ALB_DNS" "$TARGET_ALB_ZONE_ID" "Migrate $PROXY_DOMAIN to target nginx ALB"
  fi
  test_endpoint_through_alb "$TARGET_ALB_DNS" target
  log "CUTOVER RESULT: PASS - $PROXY_DOMAIN points to the target ALB"
  log "Keep the source stack for rollback during the monitoring period"
}

rollback() {
  local record current_dns
  test_endpoint_through_alb "$SOURCE_ALB_DNS" source
  record="$(current_dns_record)"
  current_dns="$(jq -r '.AliasTarget.DNSName // empty' <<<"$record" | sed 's/^dualstack\.//;s/\.$//')"
  if [[ "$current_dns" == "$SOURCE_ALB_DNS" ]]; then
    log "Production DNS already points to source ALB; no DNS change required"
  else
    upsert_dns_alias "$SOURCE_ALB_DNS" "$SOURCE_ALB_ZONE_ID" "Rollback $PROXY_DOMAIN to sandbox nginx ALB"
  fi
  test_endpoint_through_alb "$SOURCE_ALB_DNS" source
  log "ROLLBACK RESULT: PASS - $PROXY_DOMAIN points to the source ALB"
}

deploy() {
  ensure_ecr_image
  ensure_execution_role
  ensure_cluster_and_logs
  ensure_security_groups
  ensure_target_group_and_alb
  ensure_task_definition
  ensure_service
  discover_target
  wait_for_healthy_targets
  test_endpoint_through_alb "$SOURCE_ALB_DNS" source
  test_endpoint_through_alb "$TARGET_ALB_DNS" target
  cmp -s "$WORK_DIR/source-root" "$WORK_DIR/target-root" || die "Source and target root response bodies differ"
  log "Verified byte-identical source and target root responses"
  log "TARGET READY: target infrastructure passed all checks; production DNS was not changed"
  log "After approval, run: scripts/migrate-nginx-proxy.sh --cutover"
}

main() {
  require_command aws
  require_command curl
  require_command date
  require_command dig
  require_command docker
  require_command grep
  require_command jq
  require_command mapfile
  require_command mktemp
  require_command sed
  require_command sort
  require_command tee
  initialize_logging
  WORK_DIR="$(mktemp -d -t nginx-proxy-migration.XXXXXX)"
  chmod 700 "$WORK_DIR"
  verify_accounts
  verify_authoritative_zone
  verify_source
  verify_target_foundation

  case "$MODE" in
    dry-run) print_dry_run_plan ;;
    deploy) deploy ;;
    cutover) cutover ;;
    rollback) rollback ;;
    *) die "Internal error: unsupported mode $MODE" ;;
  esac
  log "Execution log: $LOG_FILE"
}

main
