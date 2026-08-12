# AWS Sandbox Documentation Index
## Keycloak SSI & EUDI Wallet Infrastructure

**Last Updated:** 2026-08-06  
**Account:** 917848404243 (sandbox)  
**Region:** eu-north-1

---

## 📚 Documentation Suite

This directory contains comprehensive documentation about the AWS sandbox environment, including all Keycloak, issuer, verifier, and wallet-related deployments.

### Recommended Reading Path

1. **[README.md](README.md)** - Scope, repository contents, and refresh instructions
2. **[SUMMARY.md](SUMMARY.md)** - Executive findings and recommended next steps
3. **[VERIFICATION-REPORT.md](VERIFICATION-REPORT.md)** - Evidence for repository-to-deployment mappings
4. **[quick-reference.md](quick-reference.md)** - Day-to-day commands and endpoints

### 🎯 Quick Start

**New to the infrastructure?** Start here:
1. **[quick-reference.md](quick-reference.md)** - Essential commands and endpoints
2. **[comprehensive-aws-analysis.md](comprehensive-aws-analysis.md)** - Full deployment details with GitHub mappings
3. **[aws-sandbox-resources-audit.md](aws-sandbox-resources-audit.md)** - Complete infrastructure inventory

---

## 📖 Document Guide

### Infrastructure Documentation

#### 1. **quick-reference.md** 
*Your everyday operations guide*
- ✅ Active services list with GitHub links
- ✅ Public endpoints (ALBs)
- ✅ Common AWS CLI commands
- ✅ Troubleshooting tips
- **Use when:** You need to quickly find an endpoint or run a common operation

#### 2. **comprehensive-aws-analysis.md**
*Deep dive into deployments*
- ✅ ECS services mapped to GitHub repositories
- ✅ ECR repository analysis with image tags
- ✅ Load balancer to service mappings
- ✅ Container configuration details
- ✅ Security and monitoring recommendations
- **Use when:** Understanding service architecture or investigating deployment issues

#### 3. **aws-sandbox-resources-audit.md**
*Complete infrastructure inventory*
- ✅ All ECS clusters and services
- ✅ All ECR repositories
- ✅ All load balancers and target groups
- ✅ EC2 instances, S3 buckets, RDS databases
- ✅ VPC and security group configurations
- **Use when:** Conducting security audit or cost analysis

---

## 🗂️ Generated Data Files

The collection scripts create local snapshots that are intentionally excluded by
`.gitignore`. They may contain AWS metadata or plaintext task-definition environment
values. Do not commit them unless they have been reviewed and sanitized.


### JSON Data Files
- `sandbox-raw-data-*.json`
  - Complete AWS resource data snapshot
  - Includes: ECS, ECR, ALB, EC2, S3, RDS, VPC, Security Groups

- `deep-analysis-*.json`
  - Extended analysis with task definitions
  - Includes: Container configurations, Lambda functions, Secrets Manager, SSM parameters, ACM certificates

### Collection Scripts
- **collect-sandbox-resources.sh**
  - Automated data collection script
  - Re-run to refresh data: `./collect-sandbox-resources.sh`
  
- **deep-analysis.sh**
  - Extended resource analysis
  - Collects task definitions, ECR images, CloudFormation stacks

---

## 🚀 Active Services Summary

**✅ All repositories verified from GitHub Actions workflows**

| Service | Purpose | GitHub Repo | Branch | Status |
|---------|---------|-------------|--------|--------|
| nginx-cors | CORS proxy for frontend | ✅ eudiw-app | develop | 🟢 Running |
| portal-eudi-verifier | EUDI verifier portal | ✅ fe-eudiw-verifier | develop | 🟢 Running |
| be-kc-client-oid4vc-dev | OID4VC backend issuer | ✅ be-kc-client-oid4vc | develop | 🟢 Running |
| fe-kc-client-oid4vcV1 | OID4VC frontend issuer | ✅ fe-kc-client-oid4vc | develop | 🟢 Running |
| eudiw-verifier-staging | EUDI verifier (Java) | ✅ eudiw-verifier | develop | 🟢 Running |

### Inactive Services (Desired Count: 0)
- deploy_be-kc-client-oid4vc
- portal-eudi-verifier-master
- fe-kc-client-oid4vcV1-main
- eudiw-verifier-main

---

## 🌐 Key Endpoints

### Keycloak
- **Demo Instance:** keycloak-demo-LB-851915636.eu-north-1.elb.amazonaws.com

### OID4VC Issuers
- **Frontend (Active):** fekcissuer-193601116.eu-north-1.elb.amazonaws.com
- **Backend (Dev):** be-kc-client-oid4vc-dev-1732486315.eu-north-1.elb.amazonaws.com

### EUDI Verifiers
- **Portal:** portal-eudi-verifier-486768016.eu-north-1.elb.amazonaws.com
- **Staging:** eudiw-service-staging-LB-1987977187.eu-north-1.elb.amazonaws.com

### Infrastructure
- **CORS Proxy:** corsproxy-2023641953.eu-north-1.elb.amazonaws.com

---

## 🔗 GitHub Repositories

**Legend:** ✅ = Verified from GitHub Actions workflows

### Core Infrastructure
| Repository | Purpose | Organization | Verification |
|------------|---------|--------------|--------------|
| keycloak-ssi-deployment | Deployment configs & Docker | adorsys | ⚠️ Inferred |
| keycloak-oid4vc | OID4VC plugin for Keycloak | adorsys | - |
| keycloak-oid4vp-plugin | OID4VP plugin for Keycloak | ADORSYS-GIS | - |

### Issuer Services
| Repository | Purpose | Organization | Verification |
|------------|---------|--------------|--------------|
| be-kc-client-oid4vc | Backend OID4VC issuer | adorsys | ✅ Verified |
| fe-kc-client-oid4vc | Frontend OID4VC issuer | adorsys | ✅ Verified |

**Deployments:**
- `be-kc-client-oid4vc` (develop) → `be-kc-client-oid4vc-dev` ECR
- `be-kc-client-oid4vc` (main) → `be-kc-client-oid4vc` ECR
- `fe-kc-client-oid4vc` (develop) → `fe-kc-client-oid4vc` ECR
- `fe-kc-client-oid4vc` (main) → `fe-kc-client-oid4vc1-main` ECR

### Verifier Services
| Repository | Purpose | Organization | Verification |
|------------|---------|--------------|--------------|
| eudiw-verifier | EUDI verifier (Java) | adorsys | ✅ Verified |
| fe-eudiw-verifier | Verifier frontend | adorsys | ✅ Verified |

**Deployments:**
- `eudiw-verifier` (develop) → `eudiw-verifier-staging` ECR
- `eudiw-verifier` (main) → `eudiw-verifier` ECR
- `fe-eudiw-verifier` (develop) → `portal-eudi-verifier` ECR
- `fe-eudiw-verifier` (master) → `portal-eudi-verifier-master` ECR

### Wallet & Support
| Repository | Purpose | Organization | Verification |
|------------|---------|--------------|--------------|
| eudiw-app | EUDI Wallet application | adorsys | ✅ Verified (nginx) |
| status-list-server | Credential status service | adorsys | - |
| token-status-link | Token status linking | ADORSYS-GIS | - |

**Deployments:**
- `eudiw-app` (develop, nginx/) → `nginx_datev_wallet` ECR

### Deployment & Infrastructure
| Repository | Purpose | Organization | Verification |
|------------|---------|--------------|--------------|
| datev-argo-apps | ArgoCD application configs | ADORSYS-GIS | - |
| wallet-eks-env | EKS environment setup | ADORSYS-GIS | - |

---

## 🔧 Common Tasks

### View Service Status
```bash
aws ecs list-services --cluster Datev_Wallet --profile sandbox --region eu-north-1
```

### Check Logs
```bash
aws logs tail /ecs/Datev_Wallet/<service-name> --follow --profile sandbox --region eu-north-1
```

### Update Service (Force Redeploy)
```bash
aws ecs update-service --cluster Datev_Wallet --service <service-name> --force-new-deployment --profile sandbox --region eu-north-1
```

### List ECR Images
```bash
aws ecr list-images --repository-name <repo-name> --profile sandbox --region eu-north-1
```

---

## 📊 Resource Statistics

- **ECS Clusters:** 3
- **Total ECS Services:** 9 (5 running, 4 stopped)
- **ECR Repositories:** 14
- **Application Load Balancers:** 10
- **Active Load Balancers:** 10
- **Security Groups:** ~50+
- **VPCs:** Multiple

---

## 🔐 Security Notes

- All secrets stored in AWS Secrets Manager
- Container images in private ECR repositories
- SSL/TLS certificates managed via ACM
- Security groups configured per service
- IAM roles for ECS task execution and tasks

---

## 📅 Maintenance Schedule

### Regular Tasks
- **Weekly:** Review CloudWatch logs for errors
- **Bi-weekly:** Check for ECR image updates
- **Monthly:** Security group audit
- **Quarterly:** Cost optimization review
- **Quarterly:** Update this documentation

### Data Refresh
To refresh the infrastructure data:
```bash
cd /path/to/aws-sandbox-audi
./collect-sandbox-resources.sh
```

---

## 🆘 Troubleshooting

### Service Won't Start
1. Check task definition: `aws ecs describe-task-definition --task-definition <family>`
2. View stopped task reason: `aws ecs describe-tasks --cluster <cluster> --tasks <task-id>`
3. Check CloudWatch logs for errors

### Can't Access Endpoint
1. Verify ALB target health: `aws elbv2 describe-target-health --target-group-arn <arn>`
2. Check security groups on ALB and ECS tasks
3. Verify listener rules: `aws elbv2 describe-listeners --load-balancer-arn <arn>`

### Image Pull Errors
1. Verify ECR repository and tag exist
2. Check task execution role has ECR permissions
3. Test ECR login: `aws ecr get-login-password --region eu-north-1`

---

## 📞 Support

- **Infrastructure Issues:** #devops Slack channel
- **Application Issues:** Open GitHub issue in relevant repository
- **AWS Account Issues:** Contact cloud team
- **Documentation Updates:** Update files in this repository

---

## 🔄 Version History

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2026-08-06 | 1.0 | Initial comprehensive documentation with GitHub mapping | Kiro AI |

---

## 📝 Notes

- This documentation is automatically generated and should be refreshed regularly
- Raw JSON data files contain complete AWS API responses and are ignored by Git
- Collection scripts can be scheduled via cron for automated updates
- Always use the `sandbox` profile for this environment

---

**For the most up-to-date information, regenerate the documentation:**
```bash
cd /path/to/aws-sandbox-audi
./collect-sandbox-resources.sh
```

**Navigation:** [README](README.md) → [Summary](SUMMARY.md) → [Verification report](VERIFICATION-REPORT.md)
