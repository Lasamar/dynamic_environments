
resource "aws_iam_role" "external-secret" {
  name  = "${var.cluster_name}-external-secret-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${local.account_id}:oidc-provider/${local.oidc_url}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${local.oidc_url}:sub": "system:serviceaccount:kube-system:external-secret",
          "${local.oidc_url}:aud": "sts.amazonaws.com"

        }
      }
    }
  ]
}
EOF
  tags = {
    Name = "${var.cluster_name}-external-secret-role"
  }
}

resource "aws_iam_role_policy" "external-secret" {
  
  name_prefix = "${var.cluster_name}-external-secret"
  role        = aws_iam_role.external-secret.name
  policy      = jsonencode({
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "*"
      ]
    },
  ]})
}

resource "kubernetes_service_account" "external-secret" {
  metadata {
    name      = "external-secret"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external-secret.arn
    }
  }
  automount_service_account_token = true
  
  depends_on = [module.eks]
}

resource "helm_release" "external-secrets" {
  name       = "external-secrets"
  namespace  = "kube-system"
  wait       = true
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.4.4"

  set {
    name =  "serviceAccount.name"
    value = "external-secret"
  }

  set {
    name =  "serviceAccount.create"
    value = false
  }

  set {
    name = "env.AWS_REGION"
    value = "${var.region}"
  }

  skip_crds = true

  depends_on = [kubernetes_service_account.external-secret]

}

resource "kubectl_manifest" "external-secret-store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1alpha1
    kind: ClusterSecretStore
    metadata:
      name: secretstore
    spec:
      provider:
        aws:
          service: SecretsManager
          region: ${var.region}
          auth:
            jwt:
              serviceAccountRef:
                name: external-secret
                namespace: kube-system
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}