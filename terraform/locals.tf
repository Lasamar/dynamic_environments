data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

locals {

  partition       = data.aws_partition.current.partition
  
  account_id = data.aws_caller_identity.current.account_id

  oidc_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")

  tags = {
    EKS-Cluster    = var.cluster_name

  }
}


