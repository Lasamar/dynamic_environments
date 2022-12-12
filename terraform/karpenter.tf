################################################################################
# Karpenter
################################################################################

# The module karpenter_irsa should take care of all the IAM policy required by Karpenter to instanciate new nodes.
# But, the specific version of the module has different set between cdk and terraform version. So we have to add the remaining one separately.
resource "aws_iam_policy" "extra_policy" {
  name        = "${ var.cluster_name }-karpenter-extra-policy"
  description = "Added policy to karpenter"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "ec2:DescribeImages",
            "ec2:DescribeSpotPriceHistory",
            "pricing:GetProducts",
            "iam:CreateServiceLinkedRole",
            "iam:ListRoles",
            "iam:ListInstanceProfiles",
            "ec2:RequestSpotInstances",
          ],
          "Resource": ["*"]
        }
      ]
    }
  )
}

module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.0.0"

  role_name                          = "karpenter-controller-${var.cluster_name}"
  attach_karpenter_controller_policy = true

  karpenter_tag_key = "karpenter.sh/discovery/${var.cluster_name}"
  karpenter_controller_cluster_id = module.eks.cluster_id
  karpenter_controller_node_iam_role_arns = [
    module.eks.eks_managed_node_groups["initial"].iam_role_arn
  ]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }

  depends_on = [
    module.eks
  ]
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile-${var.cluster_name}"
  role = module.eks.eks_managed_node_groups["initial"].iam_role_name
}



resource "aws_iam_role_policy_attachment" "karpenter-extra" {
  policy_arn = aws_iam_policy.extra_policy.arn
  role       = module.karpenter_irsa.iam_role_name
}


resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  version    = "v0.16.3"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter_irsa.iam_role_arn
  }

  set {
    name  = "clusterName"
    value = module.eks.cluster_id
  }

  set {
    name  = "clusterEndpoint"
    value = module.eks.cluster_endpoint
  }

  set {
    name  = "aws.defaultInstanceProfile"
    value = aws_iam_instance_profile.karpenter.name
  }

  depends_on = [
    module.karpenter_irsa
  ]
}
# # Workaround - https://github.com/hashicorp/terraform-provider-kubernetes/issues/1380#issuecomment-967022975
resource "kubectl_manifest" "karpenter_spot_provider_ref" {
  yaml_body = <<-YAML
  apiVersion: karpenter.k8s.aws/v1alpha1
  kind: AWSNodeTemplate
  metadata:
    name: default
  spec:
    subnetSelector:
      karpenter.sh/discovery/${module.eks.cluster_id}: ${module.eks.cluster_id}
    securityGroupSelector:
      karpenter.sh/discovery/${module.eks.cluster_id}: ${module.eks.cluster_id}
    tags:
      karpenter.sh/discovery/${module.eks.cluster_id}: ${module.eks.cluster_id}
      team: devops
      karpenter.sh/provisioner-name: spot-provider
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

# # Workaround - https://github.com/hashicorp/terraform-provider-kubernetes/issues/1380#issuecomment-967022975
resource "kubectl_manifest" "karpenter_spot_provisioner" {
  yaml_body = <<-YAML
  apiVersion: karpenter.sh/v1alpha5
  kind: Provisioner
  metadata:
    name: spot-provider
  spec:
    consolidation:
      enabled: true
    labels:
      type: karpenter-spot-provisioner
      team: devops
    requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot"]
      - key: topology.kubernetes.io/zone
        operator: In
        values: [${var.region}a, ${var.region}b, ${var.region}c]
    limits:
      resources: 
        cpu: 1000
    providerRef:
      name: default
    weight: 10
  YAML

  depends_on = [
    kubectl_manifest.karpenter_spot_provider_ref
  ]
}



