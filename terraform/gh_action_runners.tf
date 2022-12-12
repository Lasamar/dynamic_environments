resource "kubernetes_namespace" "runners" {
  metadata {
    name = "runners"
  }

  depends_on = [
    resource.helm_release.actions-runner-controller
  ]
}

resource "kubernetes_cluster_role" "base_runner_role_helm_lifecycle" {
  metadata {
    name      = "base-runner-role-helm-lifecycle"
  }

  rule {
    verbs          = ["get", "watch", "list", "patch", "update", "delete"]
    api_groups     = ["", "apps", "networking.k8s.io", "extensions"]
    resources      = ["deployments", "services", "configmaps", "secrets", "ingresses"]
  }
}

resource "kubernetes_service_account" "base-runner" {
  metadata {
    name = "base-runner"
    namespace = resource.kubernetes_namespace.runners.metadata[0].name
  }
  depends_on = [
    resource.kubernetes_namespace.runners
  ]
}


resource "kubernetes_cluster_role_binding" "base_runner_cluster_role_binding" {
  metadata {
    name = "base-runner-cluster-role-binding"
  }

  subject {
    kind      = "ServiceAccount"
    name      = resource.kubernetes_service_account.base-runner.metadata[0].name
    namespace = resource.kubernetes_namespace.runners.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "ClusterRole"
    name = "cluster-admin"
  }

  depends_on = [
    resource.kubernetes_namespace.runners
  ]
}


resource "kubectl_manifest" "base-runner" {
  yaml_body = <<YAML
  apiVersion: actions.summerwind.dev/v1alpha1
  kind: RunnerDeployment
  metadata:
    name: base-runner
    namespace: ${resource.kubernetes_namespace.runners.metadata[0].name}
  spec:
    template:
      spec:
        repository: ${var.repository}
        serviceAccountName: base-runner
        automountServiceAccountToken: true
        labels:
          - base-runners
        env: []
  YAML

  depends_on = [
    resource.kubernetes_namespace.runners
  ]
}



resource "kubectl_manifest" "hra-base-runner" {
  yaml_body = <<YAML
apiVersion: actions.summerwind.dev/v1alpha1
kind: HorizontalRunnerAutoscaler
metadata:
  name: base-runners-autoscaler
  namespace: ${resource.kubernetes_namespace.runners.metadata[0].name}
spec:
  scaleTargetRef:
    name: base-runner
  scaleDownDelaySecondsAfterScaleOut: 300
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: PercentageRunnersBusy
    scaleUpThreshold: '0.75'
    scaleDownThreshold: '0.25'
    scaleUpFactor: '2'
    scaleDownFactor: '0.5'
YAML

  depends_on = [
    resource.kubernetes_namespace.runners
  ]
}

