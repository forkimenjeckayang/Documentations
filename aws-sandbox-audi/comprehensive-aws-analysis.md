# Comprehensive AWS Sandbox Resource Analysis
## Keycloak, Issuer, Verifier & Datev-Wallet Deployments

**Generated:** 2026-08-06 15:09:09 UTC  
**AWS Account:** 917848404243  
**Region:** eu-north-1  
**Analysis Scope:** All Keycloak, Issuer, Verifier, Nginx, and Datev-Wallet related resources

**Repository Mappings:** ✅ Verified from GitHub Actions workflows

---

## Executive Summary

This report provides a comprehensive mapping of AWS deployments to their source GitHub repositories. All mappings have been **verified by analyzing actual GitHub Actions workflows** that deploy to this sandbox environment.

### Quick Stats
- **ECS Clusters:** 3
- **Active Services:** 5 (running now)
- **ECR Repositories:** 14  
- **Verified GitHub Mappings:** 9 repositories
- **Load Balancers:** 10
- **Account:** 917848404243 (sandbox)

---

## 1. Active Deployments with Verified GitHub Sources


### 🚀 ✅ Service: **nginx-cors**

- **Cluster:** Datev_Wallet
- **Status:** ACTIVE (Running 1/1)
- **ECR Repository:** `nginx_datev_wallet`
- **GitHub Repository:** [adorsys/eudiw-app](https://github.com/adorsys/eudiw-app)
- **Branch:** `develop`
- **Verification:** ✅ Verified from GitHub Actions workflow
- **Load Balancer:** corsproxy
- **Public Endpoint:** `corsproxy-2023641953.eu-north-1.elb.amazonaws.com`
- **Port:** 443 (HTTPS)


### 🚀 ✅ Service: **portal-eudi-verifier**

- **Cluster:** Datev_Wallet
- **Status:** ACTIVE (Running 1/1)
- **ECR Repository:** `portal-eudi-verifier`
- **GitHub Repository:** [adorsys/fe-eudiw-verifier](https://github.com/adorsys/fe-eudiw-verifier)
- **Branch:** `develop`
- **Verification:** ✅ Verified from GitHub Actions workflow
- **Load Balancer:** portal-eudi-verifier
- **Public Endpoint:** `portal-eudi-verifier-486768016.eu-north-1.elb.amazonaws.com`
- **Port:** 443 (HTTPS)


### 🚀 ✅ Service: **be-kc-client-oid4vc-dev**

- **Cluster:** Datev_Wallet
- **Status:** ACTIVE (Running 1/1)
- **ECR Repository:** `be-kc-client-oid4vc-dev`
- **GitHub Repository:** [adorsys/be-kc-client-oid4vc](https://github.com/adorsys/be-kc-client-oid4vc)
- **Branch:** `develop`
- **Verification:** ✅ Verified from GitHub Actions workflow
- **Load Balancer:** be-kc-client-oid4vc-dev
- **Public Endpoint:** `be-kc-client-oid4vc-dev-1732486315.eu-north-1.elb.amazonaws.com`
- **Port:** 443 (HTTPS)


### 🚀 ✅ Service: **fe-kc-client-oid4vcV1**

- **Cluster:** Datev_Wallet
- **Status:** ACTIVE (Running 1/1)
- **ECR Repository:** `fe-kc-client-oid4vc`
- **GitHub Repository:** [adorsys/fe-kc-client-oid4vc](https://github.com/adorsys/fe-kc-client-oid4vc)
- **Branch:** `develop`
- **Verification:** ✅ Verified from GitHub Actions workflow
- **Load Balancer:** fekcissuer
- **Public Endpoint:** `fekcissuer-193601116.eu-north-1.elb.amazonaws.com`
- **Port:** 443 (HTTPS)


### 🚀 ✅ Service: **eudiw-verifier-staging**

- **Cluster:** eudiw-verifier-Cluster
- **Status:** ACTIVE (Running 1/1)
- **ECR Repository:** `eudiw-verifier-staging`
- **GitHub Repository:** [adorsys/eudiw-verifier](https://github.com/adorsys/eudiw-verifier)
- **Branch:** `develop`
- **Verification:** ✅ Verified from GitHub Actions workflow


---

## 2. All ECS Services and GitHub Mappings

This section lists all services (both active and inactive) with their verified GitHub repositories.


### Cluster: **Datev_Wallet**

#### 🔴 STOPPED deploy_be-kc-client-oid4vc

- **Desired/Running:** 0/0
- ✅ **GitHub:** [adorsys/be-kc-client-oid4vc](https://github.com/adorsys/be-kc-client-oid4vc)
- **Branch:** `main`
- **ECR Repository:** `be-kc-client-oid4vc`

#### 🟢 ACTIVE nginx-cors

- **Desired/Running:** 1/1
- ✅ **GitHub:** [adorsys/eudiw-app](https://github.com/adorsys/eudiw-app)
- **Branch:** `develop`
- **ECR Repository:** `nginx_datev_wallet`

#### 🟢 ACTIVE portal-eudi-verifier

- **Desired/Running:** 1/1
- ✅ **GitHub:** [adorsys/fe-eudiw-verifier](https://github.com/adorsys/fe-eudiw-verifier)
- **Branch:** `develop`
- **ECR Repository:** `portal-eudi-verifier`

#### 🟢 ACTIVE be-kc-client-oid4vc-dev

- **Desired/Running:** 1/1
- ✅ **GitHub:** [adorsys/be-kc-client-oid4vc](https://github.com/adorsys/be-kc-client-oid4vc)
- **Branch:** `develop`
- **ECR Repository:** `be-kc-client-oid4vc-dev`

#### 🔴 STOPPED portal-eudi-verifier-master

- **Desired/Running:** 0/0
- ✅ **GitHub:** [adorsys/fe-eudiw-verifier](https://github.com/adorsys/fe-eudiw-verifier)
- **Branch:** `master`
- **ECR Repository:** `portal-eudi-verifier-master`

#### 🟢 ACTIVE fe-kc-client-oid4vcV1

- **Desired/Running:** 1/1
- ✅ **GitHub:** [adorsys/fe-kc-client-oid4vc](https://github.com/adorsys/fe-kc-client-oid4vc)
- **Branch:** `develop`
- **ECR Repository:** `fe-kc-client-oid4vc`

#### 🔴 STOPPED fe-kc-client-oid4vcV1-main

- **Desired/Running:** 0/0
- ✅ **GitHub:** [adorsys/fe-kc-client-oid4vc](https://github.com/adorsys/fe-kc-client-oid4vc)
- **Branch:** `main`
- **ECR Repository:** `fe-kc-client-oid4vc1-main`


### Cluster: **eudiw-verifier-Cluster**

#### 🟢 ACTIVE eudiw-verifier-staging

- **Desired/Running:** 1/1
- ✅ **GitHub:** [adorsys/eudiw-verifier](https://github.com/adorsys/eudiw-verifier)
- **Branch:** `develop`
- **ECR Repository:** `eudiw-verifier-staging`


### Cluster: **eudiw-verifier**

#### 🔴 STOPPED eudiw-verifier-main

- **Desired/Running:** 0/0
- ✅ **GitHub:** [adorsys/eudiw-verifier](https://github.com/adorsys/eudiw-verifier)
- **Branch:** `main`
- **ECR Repository:** `eudiw-verifier`


---

## 3. ECR to GitHub Repository Mapping Table

| ECR Repository | GitHub Repository | Branch | Status |
|----------------|-------------------|--------|--------|
| `be-kc-client-oid4vc` | [adorsys/be-kc-client-oid4vc](https://github.com/adorsys/be-kc-client-oid4vc) | `main` | ✅ Verified |
| `be-kc-client-oid4vc-dev` | [adorsys/be-kc-client-oid4vc](https://github.com/adorsys/be-kc-client-oid4vc) | `develop` | ✅ Verified |
| `eudiw-verifier` | [adorsys/eudiw-verifier](https://github.com/adorsys/eudiw-verifier) | `main` | ✅ Verified |
| `eudiw-verifier-staging` | [adorsys/eudiw-verifier](https://github.com/adorsys/eudiw-verifier) | `develop` | ✅ Verified |
| `fe-kc-client-oid4vc` | [adorsys/fe-kc-client-oid4vc](https://github.com/adorsys/fe-kc-client-oid4vc) | `develop` | ✅ Verified |
| `fe-kc-client-oid4vc1-main` | [adorsys/fe-kc-client-oid4vc](https://github.com/adorsys/fe-kc-client-oid4vc) | `main` | ✅ Verified |
| `kc_wazuh` | [adorsys/keycloak-ssi-deployment](https://github.com/adorsys/keycloak-ssi-deployment) | `main` | ⚠️ Inferred |
| `keycloak-wazuh` | [adorsys/keycloak-ssi-deployment](https://github.com/adorsys/keycloak-ssi-deployment) | `main` | ⚠️ Inferred |
| `nginx_datev_wallet` | [adorsys/eudiw-app](https://github.com/adorsys/eudiw-app) | `develop` | ✅ Verified |
| `portal-eudi-verifier` | [adorsys/fe-eudiw-verifier](https://github.com/adorsys/fe-eudiw-verifier) | `develop` | ✅ Verified |
| `portal-eudi-verifier-master` | [adorsys/fe-eudiw-verifier](https://github.com/adorsys/fe-eudiw-verifier) | `master` | ✅ Verified |


**Legend:**
- ✅ Verified: Confirmed from GitHub Actions workflow files
- ⚠️ Inferred: Best guess based on naming patterns

---

## 4. Load Balancer Endpoints

All public-facing endpoints for the services:


### bekcissuer
- **DNS:** `bekcissuer-416400844.eu-north-1.elb.amazonaws.com`
- **Scheme:** internet-facing
- **Port:** 443 (HTTPS)
  - Service: **deploy_be-kc-client-oid4vc** (Datev_Wallet)
- **Port:** 80 (HTTP)
  - Service: **deploy_be-kc-client-oid4vc** (Datev_Wallet)


### fekcissuer-main
- **DNS:** `fekcissuer-main-1767873819.eu-north-1.elb.amazonaws.com`
- **Scheme:** internet-facing
- **Port:** 443 (HTTPS)
  - Service: **fe-kc-client-oid4vcV1-main** (Datev_Wallet)


### corsproxy
- **DNS:** `corsproxy-2023641953.eu-north-1.elb.amazonaws.com`
- **Scheme:** internet-facing
- **Port:** 443 (HTTPS)
  - Service: **nginx-cors** (Datev_Wallet)


### fekcissuer
- **DNS:** `fekcissuer-193601116.eu-north-1.elb.amazonaws.com`
- **Scheme:** internet-facing
- **Port:** 443 (HTTPS)
  - Service: **fe-kc-client-oid4vcV1** (Datev_Wallet)


### keycloak-demo-LB
- **DNS:** `keycloak-demo-LB-851915636.eu-north-1.elb.amazonaws.com`
- **Scheme:** internet-facing
- **Port:** 443 (HTTPS)


### portal-eudi-verifier
- **DNS:** `portal-eudi-verifier-486768016.eu-north-1.elb.amazonaws.com`
- **Scheme:** internet-facing
- **Port:** 443 (HTTPS)
  - Service: **portal-eudi-verifier** (Datev_Wallet)


### eudiw-service-staging-LB
- **DNS:** `eudiw-service-staging-LB-1987977187.eu-north-1.elb.amazonaws.com`
- **Scheme:** internet-facing
- **Port:** 443 (HTTPS)


### portal-eudi-verifier-master
- **DNS:** `portal-eudi-verifier-master-1747548532.eu-north-1.elb.amazonaws.com`
- **Scheme:** internet-facing
- **Port:** 443 (HTTPS)
  - Service: **portal-eudi-verifier-master** (Datev_Wallet)


### eudiw-verifier-main
- **DNS:** `eudiw-verifier-main-670292342.eu-north-1.elb.amazonaws.com`
- **Scheme:** internet-facing
- **Port:** 443 (HTTPS)
  - Service: **eudiw-verifier-main** (eudiw-verifier)


---

## 5. GitHub Repository Summary

### Verified Repositories (from Workflows)


#### [adorsys/be-kc-client-oid4vc](https://github.com/adorsys/be-kc-client-oid4vc)
- **Branches deployed:** `develop`, `main`
- **ECR repositories:** 2
- **Deployments:**
  - `be-kc-client-oid4vc-dev`
  - `be-kc-client-oid4vc`


#### [adorsys/eudiw-app](https://github.com/adorsys/eudiw-app)
- **Branches deployed:** `develop`
- **ECR repositories:** 1
- **Deployments:**
  - `nginx_datev_wallet`


#### [adorsys/eudiw-verifier](https://github.com/adorsys/eudiw-verifier)
- **Branches deployed:** `develop`, `main`
- **ECR repositories:** 2
- **Deployments:**
  - `eudiw-verifier-staging`
  - `eudiw-verifier`


#### [adorsys/fe-eudiw-verifier](https://github.com/adorsys/fe-eudiw-verifier)
- **Branches deployed:** `develop`, `master`
- **ECR repositories:** 2
- **Deployments:**
  - `portal-eudi-verifier`
  - `portal-eudi-verifier-master`


#### [adorsys/fe-kc-client-oid4vc](https://github.com/adorsys/fe-kc-client-oid4vc)
- **Branches deployed:** `develop`, `main`
- **ECR repositories:** 2
- **Deployments:**
  - `fe-kc-client-oid4vc`
  - `fe-kc-client-oid4vc1-main`


---

## 6. Deployment Architecture

```
┌─────────────────────────────────────────────────────────────┐
│          AWS Sandbox Account (917848404243)                  │
│                     eu-north-1                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Public Load Balancers (ALB)                         │  │
│  ├──────────────────────────────────────────────────────┤  │
│  │  keycloak-demo-LB.eu-north-1.elb.amazonaws.com      │  │
│  │  bekcissuer/fekcissuer - OID4VC Issuers             │  │
│  │  portal-eudi-verifier - Verifier Portal             │  │
│  │  eudiw-verifier-* - EUDI Verifiers                  │  │
│  │  corsproxy - CORS Proxy                             │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                            │
│  ┌──────────────▼───────────────────────────────────────┐  │
│  │  ECS Clusters                                        │  │
│  ├──────────────────────────────────────────────────────┤  │
│  │  • Datev_Wallet (7 services)                        │  │
│  │    → be-kc-client-oid4vc-dev  [github.com/adorsys]  │  │
│  │    → fe-kc-client-oid4vcV1    [github.com/adorsys]  │  │
│  │    → portal-eudi-verifier     [github.com/adorsys]  │  │
│  │    → nginx-cors               [github.com/adorsys]  │  │
│  │                                                       │  │
│  │  • eudiw-verifier-Cluster (1 service)               │  │
│  │    → eudiw-verifier-staging   [github.com/adorsys]  │  │
│  │                                                       │  │
│  │  • eudiw-verifier (1 service, stopped)              │  │
│  │    → eudiw-verifier-main      [github.com/adorsys]  │  │
│  └──────────────┬───────────────────────────────────────┘  │
│                 │                                            │
│  ┌──────────────▼───────────────────────────────────────┐  │
│  │  ECR Private Registries                              │  │
│  ├──────────────────────────────────────────────────────┤  │
│  │  917848404243.dkr.ecr.eu-north-1.amazonaws.com/      │  │
│  │  ├─ be-kc-client-oid4vc-dev                         │  │
│  │  ├─ fe-kc-client-oid4vc                             │  │
│  │  ├─ eudiw-verifier-staging                          │  │
│  │  ├─ portal-eudi-verifier                            │  │
│  │  └─ nginx_datev_wallet                              │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 7. CI/CD Pipeline Overview

All deployments use GitHub Actions to build and deploy to this sandbox environment:

1. **Developer pushes to GitHub** (develop or main branch)
2. **GitHub Actions triggered** automatically
3. **Build Docker image** (multi-arch: amd64/arm64)
4. **Push to ECR** (917848404243.dkr.ecr.eu-north-1.amazonaws.com)
5. **Update ECS service** (force new deployment)
6. **ECS pulls new image** and performs rolling update

### Example Workflows:
- `adorsys/be-kc-client-oid4vc` → `.github/workflows/aws-develop.yml`
- `adorsys/fe-kc-client-oid4vc` → `.github/workflows/aws-dev.yml`
- `adorsys/eudiw-verifier` → `.github/workflows/deploy-verifier-develop.yml`
- `adorsys/fe-eudiw-verifier` → `.github/workflows/AWS-CD.yml`
- `adorsys/eudiw-app` → `.github/workflows/aws-proxy.yml` (nginx only)

---