module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 18.0"

  cluster_name                    = var.cluster_name
  cluster_version                 = var.cluster_version

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnets
  
  node_security_group_tags = {
    "karpenter.sh/discovery/${var.cluster_name}" = var.cluster_name
  }

  node_security_group_additional_rules = {
    # Control plane invoke Karpenter webhook
    # Note, this setup will not enable pods to communicate between different nodes.
    # To enable it you have to expose the specific ports or just open all the ports between nodes inside the private subnets.
    ingress_karpenter_webhook_tcp = {
      description                   = "Control plane invoke Karpenter webhook"
      protocol                      = "tcp"
      from_port                     = 8443
      to_port                       = 8443
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_allow_access_from_control_plane = {
      description                   = "Allow access from control plane to webhook port of AWS load balancer controller"
      protocol                      = "tcp"
      from_port                     = 9443
      to_port                       = 9443
      type                          = "ingress"
      source_cluster_security_group = true
    }
    outbound_allow_access_to_internet = {
      cidr_blocks                   = [ "0.0.0.0/0" ]
      description                   = "Allow access from node to the internet"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "egress"
    }
  }

  manage_aws_auth_configmap = true

  aws_auth_users = [
    {
      userarn  = data.aws_caller_identity.current.arn
      username = data.aws_caller_identity.current.user_id
      groups   = ["system:masters"]
    },
  ]

  eks_managed_node_groups = {
    initial = {
      min_size     = 1
      max_size     = 1
      desired_size = 1

      instance_types = ["t2.medium"]
      capacity_type  = "ON_DEMAND"
      create_security_group = false

      iam_role_additional_policies = [
        # Required by Karpenter
        "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
      ]

      tags = {
        "karpenter.sh/discovery/${var.cluster_name}" = var.cluster_name
      }
    }
  }

}

# resource "aws_iam_policy" "ecr_policy" {
#   name        = "${ var.cluster_name }-worker-nodes-ecr-policy"
#   description = "Added policy to worker nodes to enable cloudwatch insight logging"

#   # Terraform's "jsonencode" function converts a
#   # Terraform expression result to valid JSON syntax.
#   policy = jsonencode({
#     "Version": "2012-10-17",
#       "Statement": [
#           {
#             "Effect": "Allow",
#             "Action": [
#                 "ecr:BatchCheckLayerAvailability",
#                 "ecr:BatchGetImage",
#                 "ecr:GetDownloadUrlForLayer",
#                 "ecr:GetAuthorizationToken"
#             ],
#             "Resource": "*"
#           }
#       ]
#     }
#   )
# }


# resource "aws_iam_role_policy_attachment" "ecr_additional" {
#   for_each = module.eks.eks_managed_node_groups

#   policy_arn = aws_iam_policy.ecr_policy.arn
#   role       = each.value.iam_role_name

#   depends_on = [
#     module.eks
#   ]
# }
