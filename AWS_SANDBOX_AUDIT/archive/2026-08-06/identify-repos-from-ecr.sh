#!/bin/bash

PROFILE="sandbox"
REGION="eu-north-1"
ACCOUNT="917848404243"

echo "=== Identifying Source Repositories from ECR Image Labels ==="
echo ""

# Check ECR images for metadata/labels that might indicate source repo
check_ecr_manifest() {
    local repo=$1
    local tag=${2:-latest}
    
    echo "Analyzing: $repo:$tag"
    
    # Get image manifest
    MANIFEST=$(aws ecr batch-get-image \
        --repository-name "$repo" \
        --image-ids imageTag="$tag" \
        --profile "$PROFILE" \
        --region "$REGION" \
        --output json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # Try to parse manifest for labels
        IMAGE_MANIFEST=$(echo "$MANIFEST" | jq -r '.images[0].imageManifest' 2>/dev/null)
        
        if [ -n "$IMAGE_MANIFEST" ] && [ "$IMAGE_MANIFEST" != "null" ]; then
            # Check for GitHub metadata in labels
            echo "$IMAGE_MANIFEST" | jq -r '
                try (
                    .config.Labels // {} | 
                    to_entries[] | 
                    select(.key | test("git|repo|source|vcs|github"; "i")) |
                    "  " + .key + ": " + .value
                ) catch empty
            ' 2>/dev/null || echo "  No git/repo labels found"
        fi
    fi
    echo ""
}

# List of repos to check
REPOS=(
    "be-kc-client-oid4vc"
    "be-kc-client-oid4vc-dev"
    "fe-kc-client-oid4vc"
    "fe-kc-client-oid4vc1-main"
    "eudiw-verifier"
    "eudiw-verifier-staging"
    "portal-eudi-verifier"
    "portal-eudi-verifier-master"
    "nginx_datev_wallet"
    "keycloak-wazuh"
)

for repo in "${REPOS[@]}"; do
    check_ecr_manifest "$repo" "latest"
done

# Check actual domain patterns from environment variables
echo ""
echo "=== Analyzing Service Configurations for Clues ==="
echo ""

# Pattern analysis from URLs and domain names
echo "Based on environment variables and URLs:"
echo ""
echo "Service: be-kc-client-oid4vc-dev"
echo "  Backend URL pattern: kc-issuer.solutions.adorsys.com"
echo "  Frontend URL: kci-portal.solutions.adorsys.com"
echo "  Keycloak: keycloak-demo.solutions.adorsys.com"
echo "  → Likely: backend issuer service"
echo ""

echo "Service: fe-kc-client-oid4vc"
echo "  Backend URL: kc-issuer.solutions.adorsys.com"
echo "  → Likely: frontend for OID4VC issuer"
echo ""

echo "Service: portal-eudi-verifier"
echo "  Verifier URL: eudiwverifier.solutions.adorsys.com"
echo "  Public URL: kcv-portal.solutions.adorsys.com"
echo "  → Likely: frontend portal for verifier"
echo ""

echo "Service: eudiw-verifier / eudiw-verifier-staging"
echo "  DB connections to: kc-ssi-instance-*.rds.amazonaws.com"
echo "  Public URLs: eudiwverifier/eu-verifier.solutions.adorsys.com"
echo "  → Likely: backend verifier service (Java-based from keystore config)"
echo ""

echo "Service: nginx_datev_wallet"
echo "  → Likely: CORS proxy/nginx reverse proxy"
echo ""

