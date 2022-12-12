
resource "kubernetes_namespace" "cm" {
  metadata {
    name = "cert-manager"
  }

  depends_on = [module.eks]

}

resource "helm_release" "cm" {
  name             = "cert-manager"
  namespace        = kubernetes_namespace.cm.metadata[0].name
  create_namespace = true
  chart            = "cert-manager"
  repository       = "https://charts.jetstack.io"
  version          = "v1.9.1"

  set {
    name  = "installCRDs"
    value = true
  }

  set {
    name  = "prometheus.enabled"
    value = false
  }
  
  depends_on = [resource.helm_release.karpenter]
}

resource "kubernetes_namespace" "arc" {
  metadata {
    name = "actions-runner-system"
  }
}

resource "helm_release" "actions-runner-controller" {
  name             = "actions-runner-controller"
  namespace        = kubernetes_namespace.arc.metadata[0].name
  create_namespace = true
  chart            = "actions-runner-controller"
  repository       = "https://actions-runner-controller.github.io/actions-runner-controller"
  version          = "0.21.1"
  values = [<<EOF
    authSecret:
      github_token: ${var.github_arc_token}
      create: true
  EOF
  ]

  provisioner "local-exec" {
    command = "./gh_arc_cleanup_webhookconfig.sh ${var.region} ${var.cluster_name}"
  }

  depends_on = [resource.helm_release.cm]
}

