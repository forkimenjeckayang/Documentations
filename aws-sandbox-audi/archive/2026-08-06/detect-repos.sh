#!/bin/bash

PROFILE="sandbox"
REGION="eu-north-1"

echo "=== Detecting Source Repositories from Deployed Resources ==="
echo ""

# Function to check ECR image metadata
check_image_metadata() {
    local repo=$1
    echo "Checking $repo for repository metadata..."
    
    # Get latest image
    latest_image=$(aws ecr describe-images --repository-name "$repo" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'sort_by(imageDetails,& imagePushedAt)[-1]' \
        --output json 2>/dev/null)
    
    if [ $? -eq 0 ] && [ "$latest_image" != "null" ]; then
        echo "$latest_image" | jq -r '
            "  Latest Tag: " + (.imageTags[0] // "untagged"),
            "  Digest: " + (.imageDigest // "N/A"),
            "  Pushed: " + (.imagePushedAt // "N/A")
        '
    fi
    echo ""
}

# Get all task definitions with details
echo "=== Analyzing ECS Task Definitions for Repository Clues ==="
echo ""

TASK_FAMILIES=$(aws ecs list-task-definition-families --profile "$PROFILE" --region "$REGION" --query 'families[]' --output text)

for family in $TASK_FAMILIES; do
    echo "Task Family: $family"
    
    # Get latest task definition
    TASK_DEF=$(aws ecs describe-task-definition --task-definition "$family" --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # Extract container images
        echo "$TASK_DEF" | jq -r '.taskDefinition.containerDefinitions[] | 
            "  Container: " + .name,
            "  Image: " + .image,
            "  Environment Variables:",
            (.environment[]? | "    " + .name + "=" + .value)
        '
        
        # Check tags on task definition
        TAGS=$(echo "$TASK_DEF" | jq -r '.tags[]? | "  Tag: " + .key + "=" + .value')
        if [ -n "$TAGS" ]; then
            echo "  Tags:"
            echo "$TAGS"
        fi
        
        # Extract ECR repo name from image
        ECR_REPO=$(echo "$TASK_DEF" | jq -r '.taskDefinition.containerDefinitions[0].image' | grep -oP '917848404243.dkr.ecr.eu-north-1.amazonaws.com/\K[^:]+' 2>/dev/null)
        if [ -n "$ECR_REPO" ]; then
            check_image_metadata "$ECR_REPO"
        fi
    fi
    echo "---"
done

# Check ECS services for tags
echo ""
echo "=== Checking ECS Service Tags ==="
echo ""

CLUSTER_ARNS=$(aws ecs list-clusters --profile "$PROFILE" --region "$REGION" --query 'clusterArns[]' --output text)

for cluster_arn in $CLUSTER_ARNS; do
    cluster_name=$(basename "$cluster_arn")
    echo "Cluster: $cluster_name"
    
    SERVICE_ARNS=$(aws ecs list-services --cluster "$cluster_arn" --profile "$PROFILE" --region "$REGION" --query 'serviceArns[]' --output text)
    
    for service_arn in $SERVICE_ARNS; do
        service_name=$(basename "$service_arn")
        echo "  Service: $service_name"
        
        # Get service with tags
        SERVICE_DETAIL=$(aws ecs describe-services --cluster "$cluster_arn" --services "$service_arn" --include TAGS --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            TAGS=$(echo "$SERVICE_DETAIL" | jq -r '.services[0].tags[]? | "    " + .key + "=" + .value')
            if [ -n "$TAGS" ]; then
                echo "  Tags:"
                echo "$TAGS"
            fi
        fi
    done
    echo ""
done

# Check CloudFormation stacks for source info
echo ""
echo "=== Checking CloudFormation Stacks ==="
echo ""

CF_STACKS=$(aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --profile "$PROFILE" --region "$REGION" --query 'StackSummaries[].StackName' --output text 2>/dev/null)

for stack in $CF_STACKS; do
    echo "Stack: $stack"
    
    STACK_INFO=$(aws cloudformation describe-stacks --stack-name "$stack" --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # Check parameters for repo info
        PARAMS=$(echo "$STACK_INFO" | jq -r '.Stacks[0].Parameters[]? | 
            select(.ParameterKey | contains("Repo") or contains("Repository") or contains("GitHub") or contains("Git")) | 
            "  " + .ParameterKey + "=" + .ParameterValue')
        
        if [ -n "$PARAMS" ]; then
            echo "  Repository Parameters:"
            echo "$PARAMS"
        fi
        
        # Check tags
        TAGS=$(echo "$STACK_INFO" | jq -r '.Stacks[0].Tags[]? | 
            select(.Key | contains("repo") or contains("Repository") or contains("github") or contains("source")) | 
            "  " + .Key + "=" + .Value')
        
        if [ -n "$TAGS" ]; then
            echo "  Source Tags:"
            echo "$TAGS"
        fi
    fi
    echo ""
done

# Check ECR repositories for additional metadata
echo ""
echo "=== ECR Repository Analysis ==="
echo ""

ECR_REPOS=$(aws ecr describe-repositories --profile "$PROFILE" --region "$REGION" --query 'repositories[].repositoryName' --output text 2>/dev/null)

for repo in $ECR_REPOS; do
    # Only check repos related to our services
    if echo "$repo" | grep -qiE 'keycloak|issuer|verifier|wallet|oid4|eudiw|nginx|portal|cors|kc'; then
        echo "Repository: $repo"
        
        # Get repository tags
        REPO_TAGS=$(aws ecr list-tags-for-resource --resource-arn "arn:aws:ecr:$REGION:917848404243:repository/$repo" --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            TAGS=$(echo "$REPO_TAGS" | jq -r '.tags[]? | 
                select(.Key | contains("repo") or contains("Repository") or contains("github") or contains("source") or contains("project")) | 
                "  " + .Key + "=" + .Value')
            
            if [ -n "$TAGS" ]; then
                echo "  Tags:"
                echo "$TAGS"
            fi
        fi
        
        # Check latest images for build info
        LATEST_IMAGES=$(aws ecr describe-images --repository-name "$repo" \
            --profile "$PROFILE" --region "$REGION" \
            --query 'sort_by(imageDetails,& imagePushedAt)[-3:]' \
            --output json 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            echo "  Recent Images:"
            echo "$LATEST_IMAGES" | jq -r '.[] | 
                "    Tag: " + (.imageTags[0]? // "untagged") + " - Pushed: " + .imagePushedAt'
        fi
        
        echo ""
    fi
done

