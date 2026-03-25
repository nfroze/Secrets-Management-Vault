########################################
# Vault Secrets Operator (VSO) Namespace
########################################

resource "kubernetes_namespace" "vso" {
  metadata {
    name = "vault-secrets-operator-system"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [module.eks]
}

########################################
# Vault Secrets Operator Helm Release
# Syncs secrets from Vault into Kubernetes Secrets natively.
# Applications consume standard K8s Secrets without Vault-specific code.
########################################

resource "helm_release" "vault_secrets_operator" {
  name       = "vault-secrets-operator"
  namespace  = kubernetes_namespace.vso.metadata[0].name
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault-secrets-operator"
  version    = "0.4.3"
  timeout    = 300

  set {
    name  = "defaultVaultConnection.enabled"
    value = "false"
  }

  set {
    name  = "controller.manager.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "controller.manager.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "controller.manager.resources.limits.cpu"
    value = "250m"
  }

  set {
    name  = "controller.manager.resources.limits.memory"
    value = "256Mi"
  }

  depends_on = [
    kubernetes_namespace.vso,
    helm_release.vault,
  ]
}
