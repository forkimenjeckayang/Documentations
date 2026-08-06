# AWS Sandbox Environment Resource Audit

**Generated:** 2026-08-06 13:57:49 UTC  
**AWS Profile:** sandbox  
**Region:** eu-north-1  
**Account ID:** 917848404243  
**User/Role:** Forkim.Akwichek@adorsys.com

---

## Executive Summary

This report provides a comprehensive inventory of AWS resources in the sandbox environment (Account: 917848404243).

### Resource Summary

- **ECS Clusters:** 3
- **ECR Repositories:** 14
- **Application Load Balancers:** 10
- **EC2 Instances:** 2
- **S3 Buckets:** 17
- **RDS Instances:** 3

---

## ECS Resources

### ECS Clusters

#### Cluster: Datev_Wallet
- **ARN:** `arn:aws:ecs:eu-north-1:917848404243:cluster/Datev_Wallet`
- **Services Count:** 7

**Services:**

##### Service: deploy_be-kc-client-oid4vc
- **ARN:** `arn:aws:ecs:eu-north-1:917848404243:service/Datev_Wallet/deploy_be-kc-client-oid4vc`
- **Status:** ACTIVE
- **Desired Count:** 0
- **Running Count:** 0
- **Task Definition:** `arn:aws:ecs:eu-north-1:917848404243:task-definition/be-kc-client-oid4vc-main:5`
- **Launch Type:** N/A
- **Load Balancers:**
  - Target Group: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/bekctest/b9436846314f73fa`
  - Container: be-kc-client-oid4vc:8080
- **Network:**
  - Subnets: 3 subnets
  - Security Groups: sg-55100b3a
  - Public IP: ENABLED


##### Service: nginx-cors
- **ARN:** `arn:aws:ecs:eu-north-1:917848404243:service/Datev_Wallet/nginx-cors`
- **Status:** ACTIVE
- **Desired Count:** 1
- **Running Count:** 1
- **Task Definition:** `arn:aws:ecs:eu-north-1:917848404243:task-definition/cors_proxy:6`
- **Launch Type:** N/A
- **Load Balancers:**
  - Target Group: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/nginx-proxy/b89a51021f98d635`
  - Container: nginx-proxy:8080
- **Network:**
  - Subnets: 3 subnets
  - Security Groups: sg-55100b3a
  - Public IP: ENABLED


##### Service: portal-eudi-verifier
- **ARN:** `arn:aws:ecs:eu-north-1:917848404243:service/Datev_Wallet/portal-eudi-verifier`
- **Status:** ACTIVE
- **Desired Count:** 1
- **Running Count:** 1
- **Task Definition:** `arn:aws:ecs:eu-north-1:917848404243:task-definition/portal-eudi-verifier:7`
- **Launch Type:** N/A
- **Load Balancers:**
  - Target Group: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/ecs-Datev-portal-eudi-verifier/bad185f8057dfdfe`
  - Container: portal-eudi-verifier:80
- **Network:**
  - Subnets: 3 subnets
  - Security Groups: sg-55100b3a
  - Public IP: ENABLED


##### Service: be-kc-client-oid4vc-dev
- **ARN:** `arn:aws:ecs:eu-north-1:917848404243:service/Datev_Wallet/be-kc-client-oid4vc-dev`
- **Status:** ACTIVE
- **Desired Count:** 1
- **Running Count:** 1
- **Task Definition:** `arn:aws:ecs:eu-north-1:917848404243:task-definition/be-kc-client-oid4vc-dev:9`
- **Launch Type:** N/A
- **Load Balancers:**
  - Target Group: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/be-kc-client-oid4vc-dev/4ae5935259039a52`
  - Container: be-kc-client-oid4vc-app:8080
- **Network:**
  - Subnets: 3 subnets
  - Security Groups: sg-55100b3a
  - Public IP: ENABLED


##### Service: portal-eudi-verifier-master
- **ARN:** `arn:aws:ecs:eu-north-1:917848404243:service/Datev_Wallet/portal-eudi-verifier-master`
- **Status:** ACTIVE
- **Desired Count:** 0
- **Running Count:** 0
- **Task Definition:** `arn:aws:ecs:eu-north-1:917848404243:task-definition/portal-eudi-verifier-master-TD:3`
- **Launch Type:** N/A
- **Load Balancers:**
  - Target Group: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/Datev-portal-eudiwv-master/6bddbdda9d624bc4`
  - Container: portal-eudi-verifier-app:80
- **Network:**
  - Subnets: 3 subnets
  - Security Groups: sg-55100b3a
  - Public IP: ENABLED


##### Service: fe-kc-client-oid4vcV1
- **ARN:** `arn:aws:ecs:eu-north-1:917848404243:service/Datev_Wallet/fe-kc-client-oid4vcV1`
- **Status:** ACTIVE
- **Desired Count:** 1
- **Running Count:** 1
- **Task Definition:** `arn:aws:ecs:eu-north-1:917848404243:task-definition/fe-kc-client-oid4vc:6`
- **Launch Type:** N/A
- **Load Balancers:**
  - Target Group: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/fckcissuer/408e8c30d72297a0`
  - Container: fe-kc-client-oid4vc:80
- **Network:**
  - Subnets: 3 subnets
  - Security Groups: sg-55100b3a
  - Public IP: ENABLED


##### Service: fe-kc-client-oid4vcV1-main
- **ARN:** `arn:aws:ecs:eu-north-1:917848404243:service/Datev_Wallet/fe-kc-client-oid4vcV1-main`
- **Status:** ACTIVE
- **Desired Count:** 0
- **Running Count:** 0
- **Task Definition:** `arn:aws:ecs:eu-north-1:917848404243:task-definition/fe-kc-client-oid4vc-main:1`
- **Launch Type:** N/A
- **Load Balancers:**
  - Target Group: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/fckcissuer-main/a31b24e30121b306`
  - Container: fe-kc-client-oid4vc-app:80
- **Network:**
  - Subnets: 3 subnets
  - Security Groups: sg-55100b3a
  - Public IP: ENABLED


#### Cluster: eudiw-verifier-Cluster
- **ARN:** `arn:aws:ecs:eu-north-1:917848404243:cluster/eudiw-verifier-Cluster`
- **Services Count:** 1

**Services:**

##### Service: eudiw-verifier-staging
- **ARN:** `arn:aws:ecs:eu-north-1:917848404243:service/eudiw-verifier-Cluster/eudiw-verifier-staging`
- **Status:** ACTIVE
- **Desired Count:** 1
- **Running Count:** 1
- **Task Definition:** `arn:aws:ecs:eu-north-1:917848404243:task-definition/eudiw-verifier-TD:15`
- **Launch Type:** N/A
- **Network:**
  - Subnets: 3 subnets
  - Security Groups: sg-55100b3a
  - Public IP: ENABLED


#### Cluster: eudiw-verifier
- **ARN:** `arn:aws:ecs:eu-north-1:917848404243:cluster/eudiw-verifier`
- **Services Count:** 1

**Services:**

##### Service: eudiw-verifier-main
- **ARN:** `arn:aws:ecs:eu-north-1:917848404243:service/eudiw-verifier/eudiw-verifier-main`
- **Status:** ACTIVE
- **Desired Count:** 0
- **Running Count:** 0
- **Task Definition:** `arn:aws:ecs:eu-north-1:917848404243:task-definition/eudiw-verifier-main-BE:2`
- **Launch Type:** N/A
- **Load Balancers:**
  - Target Group: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/eudiw-verifier-main/efa013a266e5edfb`
  - Container: eudiw-verifier-main-BE:8080
- **Network:**
  - Subnets: 3 subnets
  - Security Groups: sg-55100b3a
  - Public IP: ENABLED


---

## Container Repositories (ECR)

### Repository: bolan-test-project
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/bolan-test-project`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/bolan-test-project`
- **Created:** 2024-06-18T13:20:20.011000+01:00
- **Image Scan on Push:** False
- **Immutable Tags:** MUTABLE


### Repository: portal-eudi-verifier
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/portal-eudi-verifier`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/portal-eudi-verifier`
- **Created:** 2024-06-22T14:24:25.897000+01:00
- **Image Scan on Push:** False
- **Immutable Tags:** MUTABLE


### Repository: kc_wazuh
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/kc_wazuh`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/kc_wazuh`
- **Created:** 2024-08-09T12:15:46.959000+01:00
- **Image Scan on Push:** False
- **Immutable Tags:** MUTABLE


### Repository: nginx_datev_wallet
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/nginx_datev_wallet`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/nginx_datev_wallet`
- **Created:** 2024-03-22T07:12:06.006000+01:00
- **Image Scan on Push:** True
- **Immutable Tags:** MUTABLE


### Repository: be-kc-client-oid4vc
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/be-kc-client-oid4vc`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/be-kc-client-oid4vc`
- **Created:** 2024-06-07T12:07:06.285000+01:00
- **Image Scan on Push:** True
- **Immutable Tags:** MUTABLE


### Repository: book-test
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/book-test`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/book-test`
- **Created:** 2024-06-19T10:03:46.780000+01:00
- **Image Scan on Push:** False
- **Immutable Tags:** MUTABLE


### Repository: portal-eudi-verifier-master
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/portal-eudi-verifier-master`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/portal-eudi-verifier-master`
- **Created:** 2024-08-02T11:41:33.860000+01:00
- **Image Scan on Push:** False
- **Immutable Tags:** MUTABLE


### Repository: fe-test
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/fe-test`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/fe-test`
- **Created:** 2024-06-18T07:53:43.684000+01:00
- **Image Scan on Push:** False
- **Immutable Tags:** MUTABLE


### Repository: eudiw-verifier
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/eudiw-verifier`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/eudiw-verifier`
- **Created:** 2024-06-11T02:12:00.595000+01:00
- **Image Scan on Push:** False
- **Immutable Tags:** MUTABLE


### Repository: fe-kc-client-oid4vc
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/fe-kc-client-oid4vc`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/fe-kc-client-oid4vc`
- **Created:** 2024-06-11T13:24:47.907000+01:00
- **Image Scan on Push:** False
- **Immutable Tags:** MUTABLE


### Repository: eudiw-verifier-staging
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/eudiw-verifier-staging`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/eudiw-verifier-staging`
- **Created:** 2024-07-19T12:11:54.604000+01:00
- **Image Scan on Push:** False
- **Immutable Tags:** MUTABLE


### Repository: be-kc-client-oid4vc-dev
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/be-kc-client-oid4vc-dev`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/be-kc-client-oid4vc-dev`
- **Created:** 2024-08-05T09:09:19.441000+01:00
- **Image Scan on Push:** False
- **Immutable Tags:** MUTABLE


### Repository: fe-kc-client-oid4vc1-main
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/fe-kc-client-oid4vc1-main`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/fe-kc-client-oid4vc1-main`
- **Created:** 2024-08-05T11:36:19.723000+01:00
- **Image Scan on Push:** False
- **Immutable Tags:** MUTABLE


### Repository: keycloak-wazuh
- **URI:** `917848404243.dkr.ecr.eu-north-1.amazonaws.com/keycloak-wazuh`
- **ARN:** `arn:aws:ecr:eu-north-1:917848404243:repository/keycloak-wazuh`
- **Created:** 2024-08-08T11:14:01.024000+01:00
- **Image Scan on Push:** False
- **Immutable Tags:** MUTABLE


---

## Load Balancers and Domain Configuration

### bekcissuer
- **DNS Name:** `bekcissuer-416400844.eu-north-1.elb.amazonaws.com`
- **ARN:** `arn:aws:elasticloadbalancing:eu-north-1:917848404243:loadbalancer/app/bekcissuer/3bb1bf5be7489136`
- **Scheme:** internet-facing
- **VPC:** vpc-fe2c8e97
- **Type:** application
- **State:** active
- **Security Groups:** sg-55100b3a
- **Availability Zones:**
  - eu-north-1c: subnet-11ea065c
  - eu-north-1a: subnet-b362c1da
  - eu-north-1b: subnet-d037f5ab

**Listeners:**
- Port 443 (HTTPS)
  - Certificate: `arn:aws:acm:eu-north-1:917848404243:certificate/d13668fb-4ac1-452f-bdb8-49bcac601789`
  - Forwards to: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/bekctest/b9436846314f73fa`
- Port 80 (HTTP)
  - Forwards to: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/bekctest/b9436846314f73fa`


### be-kc-client-oid4vc-dev
- **DNS Name:** `be-kc-client-oid4vc-dev-1732486315.eu-north-1.elb.amazonaws.com`
- **ARN:** `arn:aws:elasticloadbalancing:eu-north-1:917848404243:loadbalancer/app/be-kc-client-oid4vc-dev/4fea3409f08ebc86`
- **Scheme:** internet-facing
- **VPC:** vpc-fe2c8e97
- **Type:** application
- **State:** active
- **Security Groups:** sg-55100b3a
- **Availability Zones:**
  - eu-north-1c: subnet-11ea065c
  - eu-north-1a: subnet-b362c1da
  - eu-north-1b: subnet-d037f5ab

**Listeners:**
- Port 443 (HTTPS)
  - Certificate: `arn:aws:acm:eu-north-1:917848404243:certificate/d13668fb-4ac1-452f-bdb8-49bcac601789`
  - Forwards to: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/be-kc-client-oid4vc-dev/4ae5935259039a52`


### fekcissuer-main
- **DNS Name:** `fekcissuer-main-1767873819.eu-north-1.elb.amazonaws.com`
- **ARN:** `arn:aws:elasticloadbalancing:eu-north-1:917848404243:loadbalancer/app/fekcissuer-main/8404ec9b177deb04`
- **Scheme:** internet-facing
- **VPC:** vpc-fe2c8e97
- **Type:** application
- **State:** active
- **Security Groups:** sg-55100b3a
- **Availability Zones:**
  - eu-north-1c: subnet-11ea065c
  - eu-north-1a: subnet-b362c1da
  - eu-north-1b: subnet-d037f5ab

**Listeners:**
- Port 443 (HTTPS)
  - Certificate: `arn:aws:acm:eu-north-1:917848404243:certificate/d13668fb-4ac1-452f-bdb8-49bcac601789`
  - Forwards to: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/fckcissuer-main/a31b24e30121b306`


### corsproxy
- **DNS Name:** `corsproxy-2023641953.eu-north-1.elb.amazonaws.com`
- **ARN:** `arn:aws:elasticloadbalancing:eu-north-1:917848404243:loadbalancer/app/corsproxy/0e046ce88c478453`
- **Scheme:** internet-facing
- **VPC:** vpc-fe2c8e97
- **Type:** application
- **State:** active
- **Security Groups:** sg-55100b3a
- **Availability Zones:**
  - eu-north-1c: subnet-11ea065c
  - eu-north-1a: subnet-b362c1da
  - eu-north-1b: subnet-d037f5ab

**Listeners:**
- Port 443 (HTTPS)
  - Certificate: `arn:aws:acm:eu-north-1:917848404243:certificate/d13668fb-4ac1-452f-bdb8-49bcac601789`
  - Forwards to: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/nginx-proxy/b89a51021f98d635`


### fekcissuer
- **DNS Name:** `fekcissuer-193601116.eu-north-1.elb.amazonaws.com`
- **ARN:** `arn:aws:elasticloadbalancing:eu-north-1:917848404243:loadbalancer/app/fekcissuer/d4cd20cd4df86e66`
- **Scheme:** internet-facing
- **VPC:** vpc-fe2c8e97
- **Type:** application
- **State:** active
- **Security Groups:** sg-55100b3a
- **Availability Zones:**
  - eu-north-1c: subnet-11ea065c
  - eu-north-1a: subnet-b362c1da
  - eu-north-1b: subnet-d037f5ab

**Listeners:**
- Port 443 (HTTPS)
  - Certificate: `arn:aws:acm:eu-north-1:917848404243:certificate/d13668fb-4ac1-452f-bdb8-49bcac601789`
  - Forwards to: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/fckcissuer/408e8c30d72297a0`


### keycloak-demo-LB
- **DNS Name:** `keycloak-demo-LB-851915636.eu-north-1.elb.amazonaws.com`
- **ARN:** `arn:aws:elasticloadbalancing:eu-north-1:917848404243:loadbalancer/app/keycloak-demo-LB/3de593c2e6e8909e`
- **Scheme:** internet-facing
- **VPC:** vpc-fe2c8e97
- **Type:** application
- **State:** active
- **Security Groups:** sg-55100b3a
- **Availability Zones:**
  - eu-north-1c: subnet-11ea065c
  - eu-north-1a: subnet-b362c1da
  - eu-north-1b: subnet-d037f5ab

**Listeners:**
- Port 443 (HTTPS)
  - Certificate: `arn:aws:acm:eu-north-1:917848404243:certificate/d13668fb-4ac1-452f-bdb8-49bcac601789`
  - Forwards to: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/keycloak-demo-TG/d8f0aa71ed7795a9`


### portal-eudi-verifier
- **DNS Name:** `portal-eudi-verifier-486768016.eu-north-1.elb.amazonaws.com`
- **ARN:** `arn:aws:elasticloadbalancing:eu-north-1:917848404243:loadbalancer/app/portal-eudi-verifier/1ec6d42836961fa1`
- **Scheme:** internet-facing
- **VPC:** vpc-fe2c8e97
- **Type:** application
- **State:** active
- **Security Groups:** sg-55100b3a
- **Availability Zones:**
  - eu-north-1c: subnet-11ea065c
  - eu-north-1a: subnet-b362c1da
  - eu-north-1b: subnet-d037f5ab

**Listeners:**
- Port 443 (HTTPS)
  - Certificate: `arn:aws:acm:eu-north-1:917848404243:certificate/d13668fb-4ac1-452f-bdb8-49bcac601789`
  - Forwards to: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/ecs-Datev-portal-eudi-verifier/bad185f8057dfdfe`


### eudiw-service-staging-LB
- **DNS Name:** `eudiw-service-staging-LB-1987977187.eu-north-1.elb.amazonaws.com`
- **ARN:** `arn:aws:elasticloadbalancing:eu-north-1:917848404243:loadbalancer/app/eudiw-service-staging-LB/89dcd8ce175f14cb`
- **Scheme:** internet-facing
- **VPC:** vpc-fe2c8e97
- **Type:** application
- **State:** active
- **Security Groups:** sg-55100b3a
- **Availability Zones:**
  - eu-north-1c: subnet-11ea065c
  - eu-north-1a: subnet-b362c1da
  - eu-north-1b: subnet-d037f5ab

**Listeners:**
- Port 443 (HTTPS)
  - Certificate: `arn:aws:acm:eu-north-1:917848404243:certificate/d13668fb-4ac1-452f-bdb8-49bcac601789`
  - Forwards to: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/eudiw-verifier-stagging/7f1988c0e378320c`


### portal-eudi-verifier-master
- **DNS Name:** `portal-eudi-verifier-master-1747548532.eu-north-1.elb.amazonaws.com`
- **ARN:** `arn:aws:elasticloadbalancing:eu-north-1:917848404243:loadbalancer/app/portal-eudi-verifier-master/a73335764b538e75`
- **Scheme:** internet-facing
- **VPC:** vpc-fe2c8e97
- **Type:** application
- **State:** active
- **Security Groups:** sg-55100b3a
- **Availability Zones:**
  - eu-north-1c: subnet-11ea065c
  - eu-north-1a: subnet-b362c1da
  - eu-north-1b: subnet-d037f5ab

**Listeners:**
- Port 443 (HTTPS)
  - Certificate: `arn:aws:acm:eu-north-1:917848404243:certificate/d13668fb-4ac1-452f-bdb8-49bcac601789`
  - Forwards to: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/Datev-portal-eudiwv-master/6bddbdda9d624bc4`


### eudiw-verifier-main
- **DNS Name:** `eudiw-verifier-main-670292342.eu-north-1.elb.amazonaws.com`
- **ARN:** `arn:aws:elasticloadbalancing:eu-north-1:917848404243:loadbalancer/app/eudiw-verifier-main/69b497dd3ba46dd9`
- **Scheme:** internet-facing
- **VPC:** vpc-fe2c8e97
- **Type:** application
- **State:** active
- **Security Groups:** sg-55100b3a
- **Availability Zones:**
  - eu-north-1c: subnet-11ea065c
  - eu-north-1a: subnet-b362c1da
  - eu-north-1b: subnet-d037f5ab

**Listeners:**
- Port 443 (HTTPS)
  - Certificate: `arn:aws:acm:eu-north-1:917848404243:certificate/d13668fb-4ac1-452f-bdb8-49bcac601789`
  - Forwards to: `arn:aws:elasticloadbalancing:eu-north-1:917848404243:targetgroup/eudiw-verifier-main/efa013a266e5edfb`


---

## EC2 Instances

### Instance: Keycloak-demo
- **Instance ID:** `i-03eac5cc262731ede`
- **Instance Type:** t3.medium
- **State:** running
- **Private IP:** 172.31.21.171
- **Public IP:** 51.20.249.58
- **VPC:** vpc-fe2c8e97
- **Subnet:** subnet-b362c1da
- **Security Groups:** launch-wizard-6
- **Launch Time:** 2024-08-05T12:15:58+00:00
- **IAM Role:** None


### Instance: fifa
- **Instance ID:** `i-0caa2eaf72d879190`
- **Instance Type:** t3.2xlarge
- **State:** running
- **Private IP:** 172.31.31.120
- **Public IP:** 56.228.76.76
- **VPC:** vpc-fe2c8e97
- **Subnet:** subnet-b362c1da
- **Security Groups:** launch-wizard-12
- **Launch Time:** 2026-07-09T09:07:33+00:00
- **IAM Role:** arn:aws:iam::917848404243:instance-profile/worldcup-ec2-s3-role


---

## S3 Buckets
**Known Project Buckets:**

### Bucket: wallet-app-metadata
- **Created:** 2026-04-17T20:53:50+00:00

### Bucket: wallet-react-app
- **Created:** 2026-04-17T20:16:27+00:00


**All Buckets in Account:**
- adorsys-dev-tfstate
- adorsys-services-sandbox-audit
- adorsys-wazuh-dev-tfstate
- event-app0
- k8s-backup-31-07-2023
- launchwizard-hana-lab-de-sap-ysi
- maintenance-web-dashing-gopher
- services-s3bucketpetadoptioncb20dce5-1u78vkkf2nvqo
- services-s3bucketpetadoptioncb20dce5-98k8qb57pey6
- terraform-state-917848404243-eu-central-1-dev
- testacl123456789123456789
- wallet-app-metadata
- wallet-react-app
- wazuh-dev-backup
- wazuh-monitoring-loki-logs
- wazuh-pipeline-test-bucket-praba
- worldcup-2026-api-snapshots

---

## RDS Databases

### Database: kc-ssi-instance-1
- **Engine:** postgres 16.13
- **Instance Class:** db.c6gd.medium
- **Status:** available
- **Endpoint:** `kc-ssi-instance-1.clh0lvey1bcg.eu-north-1.rds.amazonaws.com:5432`
- **Multi-AZ:** False
- **Storage:** 200 GB (gp3)
- **Backup Retention:** 7 days
- **VPC:** vpc-fe2c8e97
- **Security Groups:** sg-55100b3a


### Database: kc-ssi-instance-2
- **Engine:** postgres 16.13
- **Instance Class:** db.c6gd.medium
- **Status:** available
- **Endpoint:** `kc-ssi-instance-2.clh0lvey1bcg.eu-north-1.rds.amazonaws.com:5432`
- **Multi-AZ:** False
- **Storage:** 200 GB (gp3)
- **Backup Retention:** 7 days
- **VPC:** vpc-fe2c8e97
- **Security Groups:** sg-55100b3a


### Database: kc-ssi-instance-3
- **Engine:** postgres 16.13
- **Instance Class:** db.c6gd.medium
- **Status:** available
- **Endpoint:** `kc-ssi-instance-3.clh0lvey1bcg.eu-north-1.rds.amazonaws.com:5432`
- **Multi-AZ:** False
- **Storage:** 200 GB (gp3)
- **Backup Retention:** 7 days
- **VPC:** vpc-fe2c8e97
- **Security Groups:** sg-55100b3a


---

## Network Configuration

### VPCs

#### VPC: Unnamed
- **VPC ID:** `vpc-fe2c8e97`
- **CIDR Block:** 172.31.0.0/16
- **State:** available
- **Default:** True


---

## Security Groups (Summary)

Total Security Groups: 17

**Key Security Groups:**
- **launch-wizard-3** (`sg-038486cb32415c2b8`): launch-wizard-3 created 2024-06-26T18:45:48.427Z
- **default** (`sg-55100b3a`): default VPC security group
- **ec2group** (`sg-0b435a0b0a2c93ad5`): ec2group
- **launch-wizard-4** (`sg-0debec4ea0f5b3686`): launch-wizard-4 created 2024-06-26T19:02:07.708Z
- **launch-wizard-11** (`sg-0fc853f94e0d95b50`): launch-wizard-11 created 2024-11-29T01:48:13.793Z
- **launch-wizard-2** (`sg-00b217ce8096aa2dc`): launch-wizard-2 created 2024-06-24T11:56:23.464Z
- **launch-wizard-12** (`sg-09da1ed77d6d01d12`): launch-wizard-12 created 2026-06-08T13:08:38.440Z
- **launch-wizard-5** (`sg-04f6c2f84224e81a2`): launch-wizard-5 created 2024-06-27T16:26:23.166Z
- **launch-wizard-9** (`sg-0823755942d3b9ede`): launch-wizard-9 created 2024-10-31T10:21:13.768Z
- **launch-wizard-8** (`sg-0a978a2825847512c`): launch-wizard-8 created 2024-10-24T09:50:51.102Z
- **launch-wizard-10** (`sg-0e20bed5c514fb5f3`): launch-wizard-10 created 2024-11-28T14:33:29.275Z
- **launch-wizard-7** (`sg-078801184484a360e`): launch-wizard-7 created 2024-07-17T14:31:13.671Z
- **ec2group1** (`sg-097b4b9ebe1c89d9d`): ec2group1
- **ec2group12** (`sg-0ea32e32b4758a670`): ec2group12
- **launch-wizard-6** (`sg-0a62bfcc00372bbae`): launch-wizard-6 created 2024-07-11T09:47:18.309Z

... and 2 more.

---

## ECS Services to Domain Mapping

Based on load balancer configurations:

### deploy_be-kc-client-oid4vc
- **Cluster:** Datev_Wallet
- **Load Balancer:** bekcissuer
- **Load Balancer DNS:** `bekcissuer-416400844.eu-north-1.elb.amazonaws.com`
- **Listener Port:** 443
- **Protocol:** HTTPS
- **Load Balancer:** bekcissuer
- **Load Balancer DNS:** `bekcissuer-416400844.eu-north-1.elb.amazonaws.com`
- **Listener Port:** 80
- **Protocol:** HTTP
- **Container Port:** 8080

### nginx-cors
- **Cluster:** Datev_Wallet
- **Load Balancer:** corsproxy
- **Load Balancer DNS:** `corsproxy-2023641953.eu-north-1.elb.amazonaws.com`
- **Listener Port:** 443
- **Protocol:** HTTPS
- **Container Port:** 8080

### portal-eudi-verifier
- **Cluster:** Datev_Wallet
- **Load Balancer:** portal-eudi-verifier
- **Load Balancer DNS:** `portal-eudi-verifier-486768016.eu-north-1.elb.amazonaws.com`
- **Listener Port:** 443
- **Protocol:** HTTPS
- **Container Port:** 80

### be-kc-client-oid4vc-dev
- **Cluster:** Datev_Wallet
- **Load Balancer:** be-kc-client-oid4vc-dev
- **Load Balancer DNS:** `be-kc-client-oid4vc-dev-1732486315.eu-north-1.elb.amazonaws.com`
- **Listener Port:** 443
- **Protocol:** HTTPS
- **Container Port:** 8080

### portal-eudi-verifier-master
- **Cluster:** Datev_Wallet
- **Load Balancer:** portal-eudi-verifier-master
- **Load Balancer DNS:** `portal-eudi-verifier-master-1747548532.eu-north-1.elb.amazonaws.com`
- **Listener Port:** 443
- **Protocol:** HTTPS
- **Container Port:** 80

### fe-kc-client-oid4vcV1
- **Cluster:** Datev_Wallet
- **Load Balancer:** fekcissuer
- **Load Balancer DNS:** `fekcissuer-193601116.eu-north-1.elb.amazonaws.com`
- **Listener Port:** 443
- **Protocol:** HTTPS
- **Container Port:** 80

### fe-kc-client-oid4vcV1-main
- **Cluster:** Datev_Wallet
- **Load Balancer:** fekcissuer-main
- **Load Balancer DNS:** `fekcissuer-main-1767873819.eu-north-1.elb.amazonaws.com`
- **Listener Port:** 443
- **Protocol:** HTTPS
- **Container Port:** 80

### eudiw-verifier-staging
- **Cluster:** eudiw-verifier-Cluster
- **Load Balancer:** None (service may use service discovery or direct connection)
- **Container Port:** N/A

### eudiw-verifier-main
- **Cluster:** eudiw-verifier
- **Load Balancer:** eudiw-verifier-main
- **Load Balancer DNS:** `eudiw-verifier-main-670292342.eu-north-1.elb.amazonaws.com`
- **Listener Port:** 443
- **Protocol:** HTTPS
- **Container Port:** 8080


---

## Route53 DNS Records

### Hosted Zone: dev.wazuh.adorsys.team.
- **Zone ID:** `/hostedzone/Z05231162DYJ9PGZPA10W`
- **Record Count:** 61
- **Private Zone:** False


### Hosted Zone: solutions.adorsys.com.
- **Zone ID:** `/hostedzone/Z02911502N07V5SNAMLHL`
- **Record Count:** 19
- **Private Zone:** False


### Hosted Zone: ai.dericking.kivoyo.com.
- **Zone ID:** `/hostedzone/Z10195693A0AO6O3RWJHA`
- **Record Count:** 2
- **Private Zone:** False


### Hosted Zone: local.
- **Zone ID:** `/hostedzone/Z0799517Q74A3QJ58Q2T`
- **Record Count:** 2
- **Private Zone:** True


### Hosted Zone: nfttheworld.
- **Zone ID:** `/hostedzone/Z04063751WQU37H6HV7J0`
- **Record Count:** 2
- **Private Zone:** True

