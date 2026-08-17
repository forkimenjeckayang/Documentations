# AWS Sandbox Infrastructure Audit
## Complete Documentation & Analysis

**Account:** 917848404243 (sandbox)  
**Region:** eu-north-1  
**Last Updated:** 2026-08-06  
**Status:** ✅ All repositories verified from GitHub Actions workflows

---

## 📚 Documentation Structure

### 🎯 Start Here

**[INDEX.md](INDEX.md)** - Master index and navigation guide
- Overview of all documentation
- Quick stats and summary
- Links to all resources

**Suggested reading order:** [INDEX.md](INDEX.md) → **README.md** →
[SUMMARY.md](SUMMARY.md) → [VERIFICATION-REPORT.md](VERIFICATION-REPORT.md)

---

## 📖 Main Documentation

### 1. [quick-reference.md](quick-reference.md)
**Your daily operations guide**

Contains:
- ✅ Active services table with verified GitHub repos
- 🌐 Public endpoints (all 10 ALBs)
- 📦 ECR repository mappings
- 🔧 Common AWS CLI commands
- 🆘 Troubleshooting guide

**Use when:** You need to quickly find an endpoint or run a common operation

---

### 2. [comprehensive-aws-analysis.md](comprehensive-aws-analysis.md)
**Deep dive into all deployments**

Contains:
- ✅ All ECS services mapped to verified GitHub repositories
- 📊 ECR repository analysis with image tags
- 🔗 Load balancer to service mappings
- 🏗️ Architecture diagram
- 📋 Detailed container configurations
- 💡 Security and monitoring recommendations

**Use when:** Understanding service architecture or investigating deployment issues

---

### 3. [VERIFICATION-REPORT.md](VERIFICATION-REPORT.md)
**Proof of GitHub repository mappings**

Contains:
- ✅ Verification methodology
- 📝 Detailed evidence for each mapping
- ❌ Common misconceptions clarified
- 🔍 Workflow analysis results
- 📊 Verification summary statistics

**Use when:** Need to confirm source repositories or understand deployment pipelines

---

### 4. [aws-sandbox-resources-audit.md](aws-sandbox-resources-audit.md)
**Complete infrastructure inventory**

Contains:
- 📦 All ECS clusters and services
- 🗃️ All ECR repositories
- ⚖️ All load balancers and target groups
- 🖥️ EC2 instances, S3 buckets, RDS databases
- 🔐 VPC and security group configurations
- 🌐 Network architecture

**Use when:** Conducting security audit, cost analysis, or infrastructure review

---

## 📊 Data Files

### Generated Raw Data (local only)

**`sandbox-raw-data-*.json`**
- Complete AWS resource snapshot
- ECS, ECR, ALB, EC2, S3, RDS, VPC, Security Groups
- Source: AWS API responses

**`deep-analysis-*.json`**
- Extended analysis with task definitions
- Container configurations, environment variables
- Lambda functions, Secrets Manager, SSM parameters
- ACM certificates, CloudFormation stacks

**[verified-repo-mappings.json](verified-repo-mappings.json)** (2.7 KB)
These generated files are excluded by `.gitignore` because they can contain
sensitive AWS metadata and plaintext task-definition environment values. Review
and sanitize a snapshot before sharing or committing it.

- Machine-readable GitHub → ECR mappings
- Verification status and workflow paths
- Branch information and descriptions

---

## 🔧 Scripts

### Data Collection

**[collect-sandbox-resources.sh](collect-sandbox-resources.sh)**
- Automated AWS resource data collection
- Collects ECS, ECR, ALB, EC2, RDS, VPC data
- Generates both JSON and markdown reports
- **Usage:** `./collect-sandbox-resources.sh`

**[deep-analysis.sh](deep-analysis.sh)**
- Extended resource analysis
- Collects task definitions, ECR image details
- CloudFormation stacks, Lambda functions
- **Usage:** `./deep-analysis.sh`

### Repository Detection

**[detect-repos.sh](detect-repos.sh)**
- Analyzes deployed resources for GitHub clues
- Examines task definitions and environment variables
- Checks for metadata and tags
- Output: `repo-detection-output.txt`

**[identify-repos-from-ecr.sh](identify-repos-from-ecr.sh)**
- ECR image manifest analysis
- Pattern matching for repository sources
- Configuration analysis

---

## 📈 Key Findings

### Active Services (5)
1. **nginx-cors** - CORS proxy (eudiw-app/nginx)
2. **portal-eudi-verifier** - Verifier portal (fe-eudiw-verifier)
3. **be-kc-client-oid4vc-dev** - Backend issuer (be-kc-client-oid4vc)
4. **fe-kc-client-oid4vcV1** - Frontend issuer (fe-kc-client-oid4vc)
5. **eudiw-verifier-staging** - EUDI verifier (eudiw-verifier Java)

### Verified Repositories (9)
- ✅ adorsys/be-kc-client-oid4vc
- ✅ adorsys/fe-kc-client-oid4vc
- ✅ adorsys/eudiw-verifier (Java)
- ✅ adorsys/fe-eudiw-verifier
- ✅ adorsys/eudiw-app (nginx only)

### Infrastructure
- **3 ECS Clusters**
- **14 ECR Repositories**
- **10 Load Balancers**
- **~50 Security Groups**

---

## ✅ Verification Status

| Item | Count | Verified | Percentage |
|------|-------|----------|------------|
| ECR Repositories | 11 | 9 | 82% |
| Active Services | 5 | 5 | 100% |
| GitHub Repos | 5 | 5 | 100% |

**Verification Method:** GitHub Actions workflow analysis

---

## 🔄 Updating Documentation

To refresh the data and regenerate reports:

```bash
cd /path/to/aws-sandbox-audi

# Ensure sandbox credentials are active
aws sts get-caller-identity --profile sandbox --region eu-north-1

# Collect fresh data
./collect-sandbox-resources.sh

# Run deep analysis
./deep-analysis.sh
```

The scripts will:
1. Collect current AWS resource state
2. Generate new JSON data files with timestamps
3. Update markdown reports with latest information

---

## 🗂️ File Sizes

```
Quick Reference:           8.2 KB
Comprehensive Analysis:   16.0 KB
Verification Report:       8.7 KB
Infrastructure Audit:     27.0 KB
Raw Data JSON:           403.0 KB
Deep Analysis JSON:      602.0 KB
```

**Total Size:** ~1.1 MB

---

## 📞 Support

- **Infrastructure Issues:** #devops Slack channel
- **Application Issues:** Open GitHub issue in relevant repository
- **Documentation Updates:** Update files in this directory
- **AWS Account Issues:** Contact cloud team

---

## 🔐 Security Notes

- All secrets stored in AWS Secrets Manager
- No credentials or secrets in this documentation
- ECR repositories are private
- Security groups configured per service
- IAM roles follow least privilege principle

---

## 📅 Maintenance Schedule

- **Weekly:** Review for service changes
- **Monthly:** Refresh data with collection scripts
- **Quarterly:** Full security and cost audit
- **As Needed:** Update after infrastructure changes

---

## 🚀 Quick Commands

```bash
# View active services
cat quick-reference.md | grep "🚀 Active"

# List all GitHub repos
cat verified-repo-mappings.json | jq -r '.[] | .github'

# Check ECS services
aws ecs list-services --cluster Datev_Wallet --profile sandbox --region eu-north-1

# View service logs
aws logs tail /ecs/Datev_Wallet/<service-name> --follow --profile sandbox --region eu-north-1
```

---

## 📝 Version History

| Date | Version | Changes |
|------|---------|---------|
| 2026-08-06 | 1.0 | Initial comprehensive audit with verified GitHub mappings |

---

## 📄 Related Resources

- **GitHub Organizations:**
  - https://github.com/adorsys
  - https://github.com/ADORSYS-GIS

- **AWS Console:**
  - Account: 917848404243
  - Region: eu-north-1
  - [ECS Console](https://eu-north-1.console.aws.amazon.com/ecs/)
  - [ECR Console](https://eu-north-1.console.aws.amazon.com/ecr/)

---

**Continue reading:** [Executive summary](SUMMARY.md) → [Verification report](VERIFICATION-REPORT.md)

**Last Updated:** 2026-08-06 15:15 UTC  
**Next Review:** After major infrastructure changes or monthly refresh
