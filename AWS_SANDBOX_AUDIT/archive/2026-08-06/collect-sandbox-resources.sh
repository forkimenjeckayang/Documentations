#!/bin/bash

# AWS Sandbox Resource Collection Script
# Profile: sandbox
# Region: eu-north-1

set -e

PROFILE="sandbox"
REGION="eu-north-1"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RAW_DATA_FILE="${OUTPUT_DIR}/sandbox-raw-data-${TIMESTAMP}.json"
REPORT_FILE="${OUTPUT_DIR}/aws-sandbox-resources-audit.md"

echo "Starting AWS Sandbox Resource Audit..."
echo "Profile: $PROFILE"
echo "Region: $REGION"
echo ""

# Check credentials first
echo "Verifying credentials..."
if ! aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" &>/dev/null; then
    echo "ERROR: Credentials are invalid or expired for profile '$PROFILE'"
    echo "Please refresh your credentials and try again."
    echo ""
    echo "Try one of these commands:"
    echo "  aws sso login --profile $PROFILE"
    echo "  aws configure --profile $PROFILE"
    exit 1
fi

ACCOUNT_INFO=$(aws sts get-caller-identity --profile "$PROFILE" --region "$REGION")
echo "✓ Credentials verified"
echo "$ACCOUNT_INFO"
echo ""

# Initialize JSON output
echo "{" > "$RAW_DATA_FILE"
echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"," >> "$RAW_DATA_FILE"
echo "  \"profile\": \"$PROFILE\"," >> "$RAW_DATA_FILE"
echo "  \"region\": \"$REGION\"," >> "$RAW_DATA_FILE"
echo "  \"account\": $ACCOUNT_INFO," >> "$RAW_DATA_FILE"

# Collect ECS Clusters
echo "Collecting ECS Clusters..."
ECS_CLUSTERS=$(aws ecs list-clusters --profile "$PROFILE" --region "$REGION" --output json)
echo "  \"ecs_clusters\": $ECS_CLUSTERS," >> "$RAW_DATA_FILE"

# Collect ECS Services and Tasks
echo "  \"ecs_services\": [" >> "$RAW_DATA_FILE"
CLUSTER_ARNS=$(echo "$ECS_CLUSTERS" | jq -r '.clusterArns[]' 2>/dev/null || echo "")
FIRST_CLUSTER=true
for cluster_arn in $CLUSTER_ARNS; do
    cluster_name=$(basename "$cluster_arn")
    echo "  Collecting services for cluster: $cluster_name..."
    
    if [ "$FIRST_CLUSTER" = false ]; then
        echo "," >> "$RAW_DATA_FILE"
    fi
    FIRST_CLUSTER=false
    
    SERVICES=$(aws ecs list-services --cluster "$cluster_arn" --profile "$PROFILE" --region "$REGION" --output json)
    SERVICE_ARNS=$(echo "$SERVICES" | jq -r '.serviceArns[]' 2>/dev/null || echo "")
    
    if [ -n "$SERVICE_ARNS" ]; then
        SERVICE_DETAILS=$(aws ecs describe-services --cluster "$cluster_arn" --services $SERVICE_ARNS --profile "$PROFILE" --region "$REGION" --output json)
        echo "    {\"cluster\": \"$cluster_name\", \"services\": $SERVICE_DETAILS}" >> "$RAW_DATA_FILE"
    else
        echo "    {\"cluster\": \"$cluster_name\", \"services\": {\"services\": []}}" >> "$RAW_DATA_FILE"
    fi
done
echo "" >> "$RAW_DATA_FILE"
echo "  ]," >> "$RAW_DATA_FILE"

# Collect ECS Task Definitions
echo "Collecting ECS Task Definitions..."
TASK_DEF_FAMILIES=$(aws ecs list-task-definition-families --profile "$PROFILE" --region "$REGION" --output json)
echo "  \"ecs_task_definitions\": $TASK_DEF_FAMILIES," >> "$RAW_DATA_FILE"

# Collect ECR Repositories
echo "Collecting ECR Repositories..."
ECR_REPOS=$(aws ecr describe-repositories --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null || echo '{"repositories":[]}')
echo "  \"ecr_repositories\": $ECR_REPOS," >> "$RAW_DATA_FILE"

# Collect Load Balancers
echo "Collecting Application Load Balancers..."
ALBS=$(aws elbv2 describe-load-balancers --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null || echo '{"LoadBalancers":[]}')
echo "  \"load_balancers\": $ALBS," >> "$RAW_DATA_FILE"

# Collect Target Groups
echo "Collecting Target Groups..."
TARGET_GROUPS=$(aws elbv2 describe-target-groups --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null || echo '{"TargetGroups":[]}')
echo "  \"target_groups\": $TARGET_GROUPS," >> "$RAW_DATA_FILE"

# Collect Listeners
echo "Collecting ALB Listeners..."
echo "  \"listeners\": [" >> "$RAW_DATA_FILE"
ALB_ARNS=$(echo "$ALBS" | jq -r '.LoadBalancers[]?.LoadBalancerArn' 2>/dev/null || echo "")
FIRST_ALB=true
for alb_arn in $ALB_ARNS; do
    if [ "$FIRST_ALB" = false ]; then
        echo "," >> "$RAW_DATA_FILE"
    fi
    FIRST_ALB=false
    
    LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn "$alb_arn" --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null || echo '{"Listeners":[]}')
    echo "    {\"load_balancer\": \"$alb_arn\", \"listeners\": $LISTENERS}" >> "$RAW_DATA_FILE"
done
echo "" >> "$RAW_DATA_FILE"
echo "  ]," >> "$RAW_DATA_FILE"

# Collect EC2 Instances
echo "Collecting EC2 Instances..."
EC2_INSTANCES=$(aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" --output json)
echo "  \"ec2_instances\": $EC2_INSTANCES," >> "$RAW_DATA_FILE"

# Collect S3 Buckets
echo "Collecting S3 Buckets..."
S3_BUCKETS=$(aws s3api list-buckets --profile "$PROFILE" --output json)
echo "  \"s3_buckets\": $S3_BUCKETS," >> "$RAW_DATA_FILE"

# Collect RDS Instances
echo "Collecting RDS Instances..."
RDS_INSTANCES=$(aws rds describe-db-instances --profile "$PROFILE" --region "$REGION" --output json)
echo "  \"rds_instances\": $RDS_INSTANCES," >> "$RAW_DATA_FILE"

# Collect Route53 Hosted Zones
echo "Collecting Route53 Hosted Zones..."
HOSTED_ZONES=$(aws route53 list-hosted-zones --profile "$PROFILE" --output json 2>/dev/null || echo '{"HostedZones":[]}')
echo "  \"route53_zones\": $HOSTED_ZONES," >> "$RAW_DATA_FILE"

# Collect VPC Information
echo "Collecting VPC Information..."
VPCS=$(aws ec2 describe-vpcs --profile "$PROFILE" --region "$REGION" --output json)
echo "  \"vpcs\": $VPCS," >> "$RAW_DATA_FILE"

# Collect Security Groups
echo "Collecting Security Groups..."
SECURITY_GROUPS=$(aws ec2 describe-security-groups --profile "$PROFILE" --region "$REGION" --output json)
echo "  \"security_groups\": $SECURITY_GROUPS" >> "$RAW_DATA_FILE"

# Close JSON
echo "}" >> "$RAW_DATA_FILE"

echo ""
echo "✓ Raw data collected: $RAW_DATA_FILE"
echo ""
echo "Now generating human-readable report..."

# Generate the report
python3 << 'PYTHON_SCRIPT'
import json
import sys
from datetime import datetime

# Read the raw data
with open("${RAW_DATA_FILE}", 'r') as f:
    data = json.load(f)

# Generate markdown report
report = f"""# AWS Sandbox Environment Resource Audit

**Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}  
**AWS Profile:** {data['profile']}  
**Region:** {data['region']}  
**Account ID:** {data['account']['Account']}  
**User/Role:** {data['account']['Arn']}

---

## Executive Summary

This report provides a comprehensive inventory of AWS resources in the sandbox environment.

### Resource Summary
"""

# Count resources
ecs_cluster_count = len(data.get('ecs_clusters', {}).get('clusterArns', []))
ecr_repo_count = len(data.get('ecr_repositories', {}).get('repositories', []))
alb_count = len(data.get('load_balancers', {}).get('LoadBalancers', []))
ec2_count = sum(len(r['Instances']) for r in data.get('ec2_instances', {}).get('Reservations', []))
s3_count = len(data.get('s3_buckets', {}).get('Buckets', []))
rds_count = len(data.get('rds_instances', {}).get('DBInstances', []))

report += f"""
- **ECS Clusters:** {ecs_cluster_count}
- **ECR Repositories:** {ecr_repo_count}
- **Application Load Balancers:** {alb_count}
- **EC2 Instances:** {ec2_count}
- **S3 Buckets:** {s3_count}
- **RDS Instances:** {rds_count}

---

## ECS Resources

### ECS Clusters
"""

if ecs_cluster_count > 0:
    for cluster_arn in data['ecs_clusters']['clusterArns']:
        cluster_name = cluster_arn.split('/')[-1]
        report += f"\n#### Cluster: {cluster_name}\n"
        report += f"- **ARN:** `{cluster_arn}`\n"
        
        # Find services for this cluster
        for service_data in data.get('ecs_services', []):
            if service_data['cluster'] == cluster_name:
                services = service_data['services'].get('services', [])
                report += f"- **Services Count:** {len(services)}\n\n"
                
                if services:
                    report += "**Services:**\n"
                    for svc in services:
                        report += f"\n##### Service: {svc['serviceName']}\n"
                        report += f"- **ARN:** `{svc['serviceArn']}`\n"
                        report += f"- **Status:** {svc['status']}\n"
                        report += f"- **Desired Count:** {svc['desiredCount']}\n"
                        report += f"- **Running Count:** {svc['runningCount']}\n"
                        report += f"- **Task Definition:** `{svc['taskDefinition']}`\n"
                        report += f"- **Launch Type:** {svc.get('launchType', 'N/A')}\n"
                        
                        # Load Balancer info
                        if svc.get('loadBalancers'):
                            report += f"- **Load Balancers:**\n"
                            for lb in svc['loadBalancers']:
                                report += f"  - Target Group: `{lb.get('targetGroupArn', 'N/A')}`\n"
                                report += f"  - Container: {lb.get('containerName', 'N/A')}:{lb.get('containerPort', 'N/A')}\n"
                        
                        # Network Configuration
                        if svc.get('networkConfiguration'):
                            nc = svc['networkConfiguration'].get('awsvpcConfiguration', {})
                            if nc:
                                report += f"- **Network:**\n"
                                report += f"  - Subnets: {len(nc.get('subnets', []))} subnets\n"
                                report += f"  - Security Groups: {', '.join(nc.get('securityGroups', []))}\n"
                                report += f"  - Public IP: {nc.get('assignPublicIp', 'N/A')}\n"
                        report += "\n"
else:
    report += "\nNo ECS clusters found.\n"

report += """
---

## Container Repositories (ECR)
"""

ecr_repos = data.get('ecr_repositories', {}).get('repositories', [])
if ecr_repos:
    for repo in ecr_repos:
        report += f"\n### Repository: {repo['repositoryName']}\n"
        report += f"- **URI:** `{repo['repositoryUri']}`\n"
        report += f"- **ARN:** `{repo['repositoryArn']}`\n"
        report += f"- **Created:** {repo['createdAt']}\n"
        report += f"- **Image Scan on Push:** {repo.get('imageScanningConfiguration', {}).get('scanOnPush', False)}\n"
        report += f"- **Immutable Tags:** {repo.get('imageTagMutability', 'MUTABLE')}\n\n"
else:
    report += "\nNo ECR repositories found.\n"

report += """
---

## Load Balancers and Domain Configuration
"""

albs = data.get('load_balancers', {}).get('LoadBalancers', [])
if albs:
    for alb in albs:
        report += f"\n### {alb['LoadBalancerName']}\n"
        report += f"- **DNS Name:** `{alb['DNSName']}`\n"
        report += f"- **ARN:** `{alb['LoadBalancerArn']}`\n"
        report += f"- **Scheme:** {alb['Scheme']}\n"
        report += f"- **VPC:** {alb['VpcId']}\n"
        report += f"- **Type:** {alb['Type']}\n"
        report += f"- **State:** {alb['State']['Code']}\n"
        report += f"- **Security Groups:** {', '.join(alb.get('SecurityGroups', []))}\n"
        report += f"- **Availability Zones:**\n"
        for az in alb.get('AvailabilityZones', []):
            report += f"  - {az['ZoneName']}: {az['SubnetId']}\n"
        
        # Find listeners for this ALB
        for listener_data in data.get('listeners', []):
            if listener_data['load_balancer'] == alb['LoadBalancerArn']:
                listeners = listener_data['listeners'].get('Listeners', [])
                if listeners:
                    report += f"\n**Listeners:**\n"
                    for listener in listeners:
                        report += f"- Port {listener['Port']} ({listener['Protocol']})\n"
                        if listener.get('Certificates'):
                            report += f"  - Certificate: `{listener['Certificates'][0]['CertificateArn']}`\n"
                        for action in listener.get('DefaultActions', []):
                            if action['Type'] == 'forward':
                                report += f"  - Forwards to: `{action.get('TargetGroupArn', 'N/A')}`\n"
        report += "\n"
else:
    report += "\nNo Application Load Balancers found.\n"

report += """
---

## EC2 Instances
"""

reservations = data.get('ec2_instances', {}).get('Reservations', [])
instance_found = False
for reservation in reservations:
    for instance in reservation.get('Instances', []):
        instance_found = True
        name_tag = next((tag['Value'] for tag in instance.get('Tags', []) if tag['Key'] == 'Name'), 'N/A')
        report += f"\n### Instance: {name_tag}\n"
        report += f"- **Instance ID:** `{instance['InstanceId']}`\n"
        report += f"- **Instance Type:** {instance['InstanceType']}\n"
        report += f"- **State:** {instance['State']['Name']}\n"
        report += f"- **Private IP:** {instance.get('PrivateIpAddress', 'N/A')}\n"
        report += f"- **Public IP:** {instance.get('PublicIpAddress', 'N/A')}\n"
        report += f"- **VPC:** {instance.get('VpcId', 'N/A')}\n"
        report += f"- **Subnet:** {instance.get('SubnetId', 'N/A')}\n"
        report += f"- **Security Groups:** {', '.join([sg['GroupName'] for sg in instance.get('SecurityGroups', [])])}\n"
        report += f"- **Launch Time:** {instance.get('LaunchTime', 'N/A')}\n"
        report += f"- **IAM Role:** {instance.get('IamInstanceProfile', {}).get('Arn', 'N/A')}\n\n"

if not instance_found:
    report += "\nNo EC2 instances found.\n"

report += """
---

## S3 Buckets
"""

buckets = data.get('s3_buckets', {}).get('Buckets', [])
if buckets:
    # Filter for known buckets
    known_buckets = ['wallet-app-metadata', 'wallet-react-app']
    for bucket in buckets:
        bucket_name = bucket['Name']
        if any(kb in bucket_name for kb in known_buckets):
            report += f"\n### Bucket: {bucket_name}\n"
            report += f"- **Created:** {bucket['CreationDate']}\n"
            report += f"- **Region:** {data['region']}\n\n"
    
    report += "\n**All Buckets:**\n"
    for bucket in buckets:
        report += f"- {bucket['Name']}\n"
else:
    report += "\nNo S3 buckets found.\n"

report += """
---

## RDS Databases
"""

rds_instances = data.get('rds_instances', {}).get('DBInstances', [])
if rds_instances:
    for db in rds_instances:
        report += f"\n### Database: {db['DBInstanceIdentifier']}\n"
        report += f"- **Engine:** {db['Engine']} {db['EngineVersion']}\n"
        report += f"- **Instance Class:** {db['DBInstanceClass']}\n"
        report += f"- **Status:** {db['DBInstanceStatus']}\n"
        report += f"- **Endpoint:** `{db['Endpoint']['Address']}:{db['Endpoint']['Port']}`\n"
        report += f"- **Multi-AZ:** {db['MultiAZ']}\n"
        report += f"- **Storage:** {db['AllocatedStorage']} GB ({db['StorageType']})\n"
        report += f"- **Backup Retention:** {db['BackupRetentionPeriod']} days\n"
        report += f"- **VPC:** {db.get('DBSubnetGroup', {}).get('VpcId', 'N/A')}\n"
        report += f"- **Security Groups:** {', '.join([sg['VpcSecurityGroupId'] for sg in db.get('VpcSecurityGroups', [])])}\n\n"
else:
    report += "\nNo RDS instances found.\n"

report += """
---

## Network Configuration

### VPCs
"""

vpcs = data.get('vpcs', {}).get('Vpcs', [])
if vpcs:
    for vpc in vpcs:
        name_tag = next((tag['Value'] for tag in vpc.get('Tags', []) if tag['Key'] == 'Name'), 'N/A')
        report += f"\n#### VPC: {name_tag}\n"
        report += f"- **VPC ID:** `{vpc['VpcId']}`\n"
        report += f"- **CIDR Block:** {vpc['CidrBlock']}\n"
        report += f"- **State:** {vpc['State']}\n"
        report += f"- **Default:** {vpc['IsDefault']}\n\n"

report += """
---

## Security Groups (Summary)
"""

sgs = data.get('security_groups', {}).get('SecurityGroups', [])
report += f"\nTotal Security Groups: {len(sgs)}\n\n"
report += "**Security Groups:**\n"
for sg in sgs[:10]:  # Show first 10
    report += f"- **{sg['GroupName']}** (`{sg['GroupId']}`): {sg.get('Description', 'No description')}\n"

if len(sgs) > 10:
    report += f"\n... and {len(sgs) - 10} more.\n"

report += """
---

## ECS Services to Domain Mapping

"""

# Try to map services to domains via load balancers
if albs and ecs_cluster_count > 0:
    report += "Based on load balancer configurations:\n\n"
    for service_data in data.get('ecs_services', []):
        services = service_data['services'].get('services', [])
        for svc in services:
            service_name = svc['serviceName']
            report += f"### {service_name}\n"
            
            if svc.get('loadBalancers'):
                for lb in svc['loadBalancers']:
                    tg_arn = lb.get('targetGroupArn')
                    if tg_arn:
                        # Find the ALB that uses this target group
                        for listener_data in data.get('listeners', []):
                            for listener in listener_data['listeners'].get('Listeners', []):
                                for action in listener.get('DefaultActions', []):
                                    if action.get('TargetGroupArn') == tg_arn:
                                        # Find the ALB
                                        alb_arn = listener_data['load_balancer']
                                        alb = next((a for a in albs if a['LoadBalancerArn'] == alb_arn), None)
                                        if alb:
                                            report += f"- **Load Balancer DNS:** `{alb['DNSName']}`\n"
                                            report += f"- **Port:** {listener['Port']}\n"
                                            report += f"- **Protocol:** {listener['Protocol']}\n"
            
            report += f"- **Container Port:** {svc.get('loadBalancers', [{}])[0].get('containerPort', 'N/A')}\n"
            report += "\n"
else:
    report += "No ECS services with load balancers found.\n"

report += """
---

## Route53 DNS Records
"""

zones = data.get('route53_zones', {}).get('HostedZones', [])
if zones:
    for zone in zones:
        report += f"\n### Hosted Zone: {zone['Name']}\n"
        report += f"- **Zone ID:** `{zone['Id']}`\n"
        report += f"- **Record Count:** {zone['ResourceRecordSetCount']}\n"
        report += f"- **Private Zone:** {zone.get('Config', {}).get('PrivateZone', False)}\n\n"
else:
    report += "\nNo Route53 hosted zones found in this account.\n"

report += """
---

## Recommendations

1. **Security:** Review security group rules for least privilege access
2. **Cost Optimization:** Consider right-sizing EC2 and RDS instances based on actual usage
3. **High Availability:** Verify Multi-AZ deployment for critical services
4. **Monitoring:** Ensure CloudWatch alarms are configured for all critical resources
5. **Backups:** Verify backup policies for RDS and important S3 data
6. **Domain Management:** Document all domain-to-service mappings for operational clarity
7. **Container Images:** Implement automated vulnerability scanning for ECR repositories
8. **ECS Capacity:** Review ECS service auto-scaling policies

---

**Report Generated:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}  
**Data File:** ${RAW_DATA_FILE}
"""

# Write the report
with open("${REPORT_FILE}", 'w') as f:
    f.write(report)

print("✓ Report generated successfully")

PYTHON_SCRIPT

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Audit Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Raw Data: $RAW_DATA_FILE"
echo "Report:   $REPORT_FILE"
echo ""
echo "You can now review the markdown report or analyze the JSON data."
