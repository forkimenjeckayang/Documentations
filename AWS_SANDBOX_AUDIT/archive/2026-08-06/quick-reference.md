# AWS Sandbox Quick Reference Guide
## Keycloak SSI & Wallet Infrastructure

**Last Updated:** 2026-08-06  
**Region:** eu-north-1  
**Account:** 917848404243

**✅ All GitHub repositories verified from actual GitHub Actions workflows**

---

## 🚀 Active Services (Running Now)

| Service | Cluster | ALB | GitHub Repo | Branch |
|---------|---------|-----|-------------|--------|
| **nginx-cors** | Datev_Wallet | corsproxy | ✅ [eudiw-app](https://github.com/adorsys/eudiw-app) | develop |
| **portal-eudi-verifier** | Datev_Wallet | portal-eudi-verifier | ✅ [fe-eudiw-verifier](https://github.com/adorsys/fe-eudiw-verifier) | develop |
| **be-kc-client-oid4vc-dev** | Datev_Wallet | be-kc-client-oid4vc-dev | ✅ [be-kc-client-oid4vc](https://github.com/adorsys/be-kc-client-oid4vc) | develop |
| **fe-kc-client-oid4vcV1** | Datev_Wallet | fekcissuer | ✅ [fe-kc-client-oid4vc](https://github.com/adorsys/fe-kc-client-oid4vc) | develop |
| **eudiw-verifier-staging** | eudiw-verifier-Cluster | eudiw-service-staging-LB | ✅ [eudiw-verifier](https://github.com/adorsys/eudiw-verifier) | develop |

---

## 🌐 Public Endpoints

### Keycloak Services
- **keycloak-demo-LB:** `keycloak-demo-LB-851915636.eu-north-1.elb.amazonaws.com`
  - Port: 443 (HTTPS)
  - Backend: Keycloak SSI instance

### OID4VC Issuers
- **Frontend Issuer (Main):** `fekcissuer-main-1767873819.eu-north-1.elb.amazonaws.com`
- **Frontend Issuer (V1):** `fekcissuer-193601116.eu-north-1.elb.amazonaws.com`
- **Backend Issuer:** `bekcissuer-416400844.eu-north-1.elb.amazonaws.com`
- **Backend Issuer (Dev):** `be-kc-client-oid4vc-dev-1732486315.eu-north-1.elb.amazonaws.com`

### EUDI Wallet Verifiers
- **Verifier Portal:** `portal-eudi-verifier-486768016.eu-north-1.elb.amazonaws.com`
- **Verifier Portal (Master):** `portal-eudi-verifier-master-1747548532.eu-north-1.elb.amazonaws.com`
- **EUDI Verifier (Main):** `eudiw-verifier-main-670292342.eu-north-1.elb.amazonaws.com`
- **EUDI Verifier (Staging):** `eudiw-service-staging-LB-1987977187.eu-north-1.elb.amazonaws.com`

### Infrastructure Services
- **CORS Proxy:** `corsproxy-2023641953.eu-north-1.elb.amazonaws.com`

---

## 📦 ECR Repositories

### Keycloak Related
- `keycloak-wazuh` (Monitoring)
- `kc_wazuh` (Security)

### OID4VC Components
- ✅ `be-kc-client-oid4vc` → [be-kc-client-oid4vc](https://github.com/adorsys/be-kc-client-oid4vc) (main)
- ✅ `be-kc-client-oid4vc-dev` → [be-kc-client-oid4vc](https://github.com/adorsys/be-kc-client-oid4vc) (develop)
- ✅ `fe-kc-client-oid4vc` → [fe-kc-client-oid4vc](https://github.com/adorsys/fe-kc-client-oid4vc) (develop)
- ✅ `fe-kc-client-oid4vc1-main` → [fe-kc-client-oid4vc](https://github.com/adorsys/fe-kc-client-oid4vc) (main)

### Verifier Components
- ✅ `eudiw-verifier` → [eudiw-verifier](https://github.com/adorsys/eudiw-verifier) (main, Java)
- ✅ `eudiw-verifier-staging` → [eudiw-verifier](https://github.com/adorsys/eudiw-verifier) (develop, Java)
- ✅ `portal-eudi-verifier` → [fe-eudiw-verifier](https://github.com/adorsys/fe-eudiw-verifier) (develop)
- ✅ `portal-eudi-verifier-master` → [fe-eudiw-verifier](https://github.com/adorsys/fe-eudiw-verifier) (master)

### Infrastructure
- ✅ `nginx_datev_wallet` → [eudiw-app](https://github.com/adorsys/eudiw-app) (nginx/ folder)

---

## 🔧 Common Operations

### Check Service Status
```bash
# List all services in a cluster
aws ecs list-services --cluster Datev_Wallet --profile sandbox --region eu-north-1

# Describe specific service
aws ecs describe-services --cluster Datev_Wallet --services nginx-cors --profile sandbox --region eu-north-1
```

### View Service Logs
```bash
# Find log group for a service
aws logs describe-log-groups --profile sandbox --region eu-north-1 | grep <service-name>

# Tail logs
aws logs tail /ecs/<cluster>/<service> --follow --profile sandbox --region eu-north-1
```

### Update Service
```bash
# Force new deployment
aws ecs update-service --cluster Datev_Wallet --service nginx-cors --force-new-deployment --profile sandbox --region eu-north-1
```

### Check ALB Target Health
```bash
# List target groups
aws elbv2 describe-target-groups --profile sandbox --region eu-north-1

# Check target health
aws elbv2 describe-target-health --target-group-arn <arn> --profile sandbox --region eu-north-1
```

### ECR Operations
```bash
# List images in repository
aws ecr list-images --repository-name be-kc-client-oid4vc --profile sandbox --region eu-north-1

# Get login for ECR
aws ecr get-login-password --region eu-north-1 --profile sandbox | docker login --username AWS --password-stdin 917848404243.dkr.ecr.eu-north-1.amazonaws.com
```

---

## 🗂️ GitHub Repositories

**✅ = Verified from GitHub Actions workflows**

### Core Keycloak & Identity
- ⚠️ [keycloak-ssi-deployment](https://github.com/adorsys/keycloak-ssi-deployment) - Main deployment configs
- [keycloak-oid4vc](https://github.com/adorsys/keycloak-oid4vc) - OID4VC plugin
- [keycloak-oid4vp-plugin](https://github.com/ADORSYS-GIS/keycloak-oid4vp-plugin) - VP plugin
- [keycloak-oauth-sig](https://github.com/keycloak/keycloak-oauth-sig) - OAuth signatures

### OID4VC Issuer (Frontend & Backend)
- ✅ [fe-kc-client-oid4vc](https://github.com/adorsys/fe-kc-client-oid4vc) - Frontend issuer (develop→fekcissuer, main→fekcissuer-main)
- ✅ [be-kc-client-oid4vc](https://github.com/adorsys/be-kc-client-oid4vc) - Backend issuer (develop→be-kc-client-oid4vc-dev, main→be-kc-client-oid4vc)

### EUDI Wallet & Verifiers
- ✅ [eudiw-app](https://github.com/adorsys/eudiw-app) - EUDI Wallet app (nginx proxy deployed from here)
- ✅ [eudiw-verifier](https://github.com/adorsys/eudiw-verifier) - Verifier (Java) (develop→eudiw-verifier-staging, main→eudiw-verifier)
- ✅ [fe-eudiw-verifier](https://github.com/adorsys/fe-eudiw-verifier) - Verifier portal frontend (develop→portal-eudi-verifier, master→portal-eudi-verifier-master)
- [fe-eudiw-playground](https://github.com/ADORSYS-GIS/fe-eudiw-playground) - Testing playground

### Infrastructure & Deployment
- [datev-argo-apps](https://github.com/ADORSYS-GIS/datev-argo-apps) - ArgoCD configs
- [wallet-eks-env](https://github.com/ADORSYS-GIS/wallet-eks-env) - EKS environment

### Supporting Services
- [status-list-server](https://github.com/adorsys/status-list-server) - Status list service
- [token-status-link](https://github.com/ADORSYS-GIS/token-status-link) - Token status

---

## 🔐 Security Resources

### Secrets Manager
- Check for secrets: `aws secretsmanager list-secrets --profile sandbox --region eu-north-1`
- Get secret value: `aws secretsmanager get-secret-value --secret-id <name> --profile sandbox --region eu-north-1`

### Security Groups
- Use comprehensive report to identify security groups per service
- Review ingress/egress rules regularly

---

## 📊 Monitoring

### CloudWatch
- **Metric Namespace:** AWS/ECS
- **Key Metrics:**
  - CPUUtilization
  - MemoryUtilization
  - RunningTaskCount
  - TargetResponseTime (ALB)

### Logs
- ECS task logs in CloudWatch Logs
- ALB access logs (if enabled)
- Application logs from containers

---

## 🆘 Troubleshooting

### Service Won't Start
1. Check task definition for correct image URI
2. Verify security groups allow required ports
3. Check CloudWatch logs for container errors
4. Ensure task execution role has ECR pull permissions

### Can't Access via ALB
1. Verify target group health checks
2. Check security group rules on ALB and tasks
3. Confirm listener rules are correct
4. Test direct task IP access (if possible)

### Image Pull Errors
1. Verify ECR repository exists
2. Check image tag exists
3. Ensure task execution role has `ecr:GetAuthorizationToken` and `ecr:BatchGetImage`

---

## 📞 Key Contacts

- **Infrastructure Team:** Use #devops or #infrastructure Slack channel
- **GitHub Issues:** Open in respective repository
- **AWS Support:** Account 917848404243

---

## 🔄 Deployment Workflow

1. **Code Changes** → Push to GitHub
2. **CI/CD** → GitHub Actions builds and pushes to ECR
3. **Deployment** → Manual or automated ECS service update
4. **Verification** → Check service health and logs
5. **Monitoring** → Watch CloudWatch metrics

---

**For detailed analysis, see:**
- `comprehensive-aws-analysis.md` - Full deployment mapping
- `aws-sandbox-resources-audit.md` - Infrastructure details
