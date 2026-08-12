#!/bin/bash

PROFILE="sandbox"
REGION="eu-north-1"
OUTPUT_FILE="deep-analysis-$(date +%Y%m%d_%H%M%S).json"

echo "=== Deep AWS Resource Analysis ==="
echo "Collecting detailed information about all deployments..."

echo "{" > "$OUTPUT_FILE"
echo '  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",' >> "$OUTPUT_FILE"
echo '  "profile": "'$PROFILE'",' >> "$OUTPUT_FILE"
echo '  "region": "'$REGION'",' >> "$OUTPUT_FILE"

# Get detailed ECS task definitions
echo "Collecting detailed ECS task definitions..."
echo '  "task_definitions": [' >> "$OUTPUT_FILE"
TASK_FAMILIES=$(aws ecs list-task-definition-families --profile "$PROFILE" --region "$REGION" --query 'families[]' --output text)
FIRST=true
for family in $TASK_FAMILIES; do
    LATEST_TD=$(aws ecs describe-task-definition --task-definition "$family" --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null)
    if [ $? -eq 0 ]; then
        if [ "$FIRST" = false ]; then
            echo "," >> "$OUTPUT_FILE"
        fi
        FIRST=false
        echo "$LATEST_TD" >> "$OUTPUT_FILE"
    fi
done
echo "" >> "$OUTPUT_FILE"
echo "  ]," >> "$OUTPUT_FILE"

# Get ECR images with tags
echo "Collecting ECR image details..."
echo '  "ecr_images": [' >> "$OUTPUT_FILE"
REPOS=$(aws ecr describe-repositories --profile "$PROFILE" --region "$REGION" --query 'repositories[].repositoryName' --output text 2>/dev/null)
FIRST=true
for repo in $REPOS; do
    IMAGES=$(aws ecr describe-images --repository-name "$repo" --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null)
    if [ $? -eq 0 ]; then
        if [ "$FIRST" = false ]; then
            echo "," >> "$OUTPUT_FILE"
        fi
        FIRST=false
        echo '{"repository": "'$repo'", "images": '$IMAGES'}' >> "$OUTPUT_FILE"
    fi
done
echo "" >> "$OUTPUT_FILE"
echo "  ]," >> "$OUTPUT_FILE"

# Get CloudFormation stacks
echo "Collecting CloudFormation stacks..."
CF_STACKS=$(aws cloudformation describe-stacks --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null || echo '{"Stacks":[]}')
echo '  "cloudformation_stacks": '$CF_STACKS',' >> "$OUTPUT_FILE"

# Get ECS clusters with more details
echo "Collecting detailed ECS cluster information..."
CLUSTER_ARNS=$(aws ecs list-clusters --profile "$PROFILE" --region "$REGION" --query 'clusterArns[]' --output text)
echo '  "cluster_details": [' >> "$OUTPUT_FILE"
FIRST=true
for cluster_arn in $CLUSTER_ARNS; do
    CLUSTER_DETAIL=$(aws ecs describe-clusters --clusters "$cluster_arn" --include TAGS --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null)
    if [ $? -eq 0 ]; then
        if [ "$FIRST" = false ]; then
            echo "," >> "$OUTPUT_FILE"
        fi
        FIRST=false
        echo "$CLUSTER_DETAIL" >> "$OUTPUT_FILE"
    fi
done
echo "" >> "$OUTPUT_FILE"
echo "  ]," >> "$OUTPUT_FILE"

# Get all Lambda functions
echo "Collecting Lambda functions..."
LAMBDAS=$(aws lambda list-functions --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null || echo '{"Functions":[]}')
echo '  "lambda_functions": '$LAMBDAS',' >> "$OUTPUT_FILE"

# Get API Gateway APIs
echo "Collecting API Gateway REST APIs..."
APIS=$(aws apigateway get-rest-apis --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null || echo '{"items":[]}')
echo '  "api_gateway_apis": '$APIS',' >> "$OUTPUT_FILE"

# Get Secrets Manager secrets
echo "Collecting Secrets Manager secrets (names only)..."
SECRETS=$(aws secretsmanager list-secrets --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null || echo '{"SecretList":[]}')
echo '  "secrets": '$SECRETS',' >> "$OUTPUT_FILE"

# Get Systems Manager parameters
echo "Collecting SSM parameters (names only)..."
SSM_PARAMS=$(aws ssm describe-parameters --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null || echo '{"Parameters":[]}')
echo '  "ssm_parameters": '$SSM_PARAMS',' >> "$OUTPUT_FILE"

# Get ACM certificates
echo "Collecting ACM certificates..."
CERTS=$(aws acm list-certificates --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null || echo '{"CertificateSummaryList":[]}')
echo '  "acm_certificates": '$CERTS >> "$OUTPUT_FILE"

echo "}" >> "$OUTPUT_FILE"

echo ""
echo "✓ Deep analysis data collected: $OUTPUT_FILE"
