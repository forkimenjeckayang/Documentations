terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

# Existing-cluster teaching example. Use your existing state/backend and add-on
# owner when integrating this code; do not create a second owner for this release.
variable "cluster_name" { type = string }
variable "aws_region" { type = string }
variable "aws_account_id" { type = string }
variable "eso_role_name" { type = string }
variable "enable_monitoring" {
  type    = bool
  default = false
}
variable "grafana_secret_arn" {
  type    = string
  default = ""
}
variable "platform_receiver_secret_arn" {
  type    = string
  default = ""
}

provider "aws" {
  region              = var.aws_region
  allowed_account_ids = [var.aws_account_id]
}

data "aws_eks_cluster" "this" { name = var.cluster_name }
data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# These providers use the intended cluster endpoint/CA, not an ambient kubecontext.
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
  }
}
provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
    }
  }
}

locals {
  # Identifiers only: Terraform never fetches the SecretString credential values.
  platform_manifests = yamldecode(templatefile("${path.module}/platform-manifests.yaml.tftpl", {
    aws_region                   = var.aws_region
    grafana_secret_arn           = trimspace(var.grafana_secret_arn)
    platform_receiver_secret_arn = trimspace(var.platform_receiver_secret_arn)
  }))
}

resource "kubernetes_namespace_v1" "monitoring" {
  count = var.enable_monitoring ? 1 : 0
  metadata { name = "monitoring" }
  lifecycle {
    precondition {
      condition = (
        trimspace(var.grafana_secret_arn) != "" &&
        trimspace(var.platform_receiver_secret_arn) != ""
      )
      error_message = "Enabled monitoring requires Grafana and a real platform receiver secret ARN."
    }
  }
}

# EC2-backed EKS example: requires a working standard EBS CSI driver and IAM.
# EKS Auto Mode uses a different provisioner; see the guide before adapting.
resource "kubernetes_storage_class_v1" "monitoring" {
  count                  = var.enable_monitoring ? 1 : 0
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  metadata { name = "monitoring-gp3" }
  parameters = {
    type                        = "gp3"
    encrypted                   = "true"
    "csi.storage.k8s.io/fstype" = "ext4"
  }
}

resource "aws_iam_policy" "monitoring_secrets" {
  count = var.enable_monitoring ? 1 : 0
  name  = format("%s-monitoring-secrets", var.cluster_name)
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = [trimspace(var.grafana_secret_arn), trimspace(var.platform_receiver_secret_arn)]
    }]
  })
}
resource "aws_iam_role_policy_attachment" "monitoring_secrets" {
  count      = var.enable_monitoring ? 1 : 0
  role       = var.eso_role_name
  policy_arn = aws_iam_policy.monitoring_secrets[0].arn
}

# A Helm-based Blueprints add-on, NOT an AWS-managed aws_eks_addon resource.
# Module version is a known, verified interface pin, not a claim it is newest.
module "addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "1.21.0"

  cluster_name      = data.aws_eks_cluster.this.name
  cluster_endpoint  = data.aws_eks_cluster.this.endpoint
  cluster_version   = data.aws_eks_cluster.this.version
  oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn

  enable_kube_prometheus_stack = var.enable_monitoring
  kube_prometheus_stack = {
    name             = "kube-prometheus-stack"
    namespace        = "monitoring"
    create_namespace = false
    chart_version    = "91.4.0"
    values = [
      file("${path.module}/values.yaml"),
      yamlencode({ extraManifests = local.platform_manifests }),
    ]
    wait            = true
    wait_for_jobs   = true
    atomic          = true
    cleanup_on_fail = true
    timeout         = 1200
  }
  tags = { Purpose = "cluster-monitoring" }

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    kubernetes_storage_class_v1.monitoring,
    aws_iam_role_policy_attachment.monitoring_secrets,
  ]
}

output "monitoring_enabled" { value = var.enable_monitoring }
output "monitoring_contract" {
  value = {
    namespace      = "monitoring"
    release_label  = "kube-prometheus-stack"
    root_config    = "platform-routing"
    datasource_uid = "prometheus"
  }
}
