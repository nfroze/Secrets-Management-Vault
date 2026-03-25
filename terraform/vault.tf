########################################
# Vault Namespace
########################################

resource "kubernetes_namespace" "vault" {
  metadata {
    name = "vault"

    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }

  depends_on = [module.eks]
}

########################################
# StorageClass for Vault Raft PVCs
# WaitForFirstConsumer prevents cross-AZ EBS scheduling failures
########################################

resource "kubernetes_storage_class" "vault" {
  metadata {
    name = "vault-storage"

    labels = {
      "app.kubernetes.io/part-of" = "vault"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }

  depends_on = [module.eks]
}

########################################
# Vault Helm Release
########################################

resource "helm_release" "vault" {
  name       = "vault"
  namespace  = kubernetes_namespace.vault.metadata[0].name
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.27.0"
  timeout    = 600
  wait       = false # Vault pods won't be Ready until initialized

  # Global
  set {
    name  = "global.enabled"
    value = "true"
  }

  set {
    name  = "global.tlsDisable"
    value = "false"
  }

  # Disable injector — using Vault Secrets Operator
  set {
    name  = "injector.enabled"
    value = "false"
  }

  # Server image
  set {
    name  = "server.image.repository"
    value = "hashicorp/vault"
  }

  set {
    name  = "server.image.tag"
    value = "1.15.4"
  }

  # Resources
  set {
    name  = "server.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "server.resources.requests.cpu"
    value = "250m"
  }

  set {
    name  = "server.resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "server.resources.limits.cpu"
    value = "500m"
  }

  # Service account with IRSA annotation
  set {
    name  = "server.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "server.serviceAccount.name"
    value = "vault"
  }

  set {
    name  = "server.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.eks.vault_iam_role_arn
  }

  # Extra volumes — RDS CA certificate
  set {
    name  = "server.extraVolumes[0].type"
    value = "secret"
  }

  set {
    name  = "server.extraVolumes[0].name"
    value = "rds-ca-bundle"
  }

  set {
    name  = "server.extraVolumes[0].path"
    value = "/vault/certs"
  }

  # Extra volumes — Vault TLS certificates
  set {
    name  = "server.extraVolumes[1].type"
    value = "secret"
  }

  set {
    name  = "server.extraVolumes[1].name"
    value = "vault-tls"
  }

  set {
    name  = "server.extraVolumes[1].path"
    value = "/vault/tls"
  }

  # Readiness probe — standby/sealed/uninit pods must stay discoverable
  set {
    name  = "server.readinessProbe.enabled"
    value = "true"
  }

  set {
    name  = "server.readinessProbe.path"
    value = "/v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204"
  }

  # Liveness probe — longer delay for init/unseal
  set {
    name  = "server.livenessProbe.enabled"
    value = "true"
  }

  set {
    name  = "server.livenessProbe.path"
    value = "/v1/sys/health?standbyok=true"
  }

  set {
    name  = "server.livenessProbe.initialDelaySeconds"
    value = "60"
  }

  # Audit storage
  set {
    name  = "server.auditStorage.enabled"
    value = "true"
  }

  set {
    name  = "server.auditStorage.size"
    value = "10Gi"
  }

  set {
    name  = "server.auditStorage.storageClass"
    value = "vault-storage"
  }

  # Data storage
  set {
    name  = "server.dataStorage.enabled"
    value = "true"
  }

  set {
    name  = "server.dataStorage.size"
    value = "10Gi"
  }

  set {
    name  = "server.dataStorage.storageClass"
    value = "vault-storage"
  }

  # HA mode with Raft
  set {
    name  = "server.ha.enabled"
    value = "true"
  }

  set {
    name  = "server.ha.replicas"
    value = "3"
  }

  set {
    name  = "server.ha.raft.enabled"
    value = "true"
  }

  set {
    name  = "server.ha.raft.setNodeId"
    value = "true"
  }

  # Raft config — HCL passed as a single value
  set {
    name  = "server.ha.raft.config"
    value = <<-EOT
      ui = true

      listener "tcp" {
        tls_disable     = false
        address         = "[::]:8200"
        cluster_address = "[::]:8201"
        tls_cert_file   = "/vault/tls/vault-tls/tls.crt"
        tls_key_file    = "/vault/tls/vault-tls/tls.key"
        telemetry {
          unauthenticated_metrics_access = true
        }
      }

      storage "raft" {
        path = "/vault/data"

        retry_join {
          leader_api_addr         = "https://vault-0.vault-internal:8200"
          leader_ca_cert_file     = "/vault/tls/vault-tls/ca.crt"
          leader_client_cert_file = "/vault/tls/vault-tls/tls.crt"
          leader_client_key_file  = "/vault/tls/vault-tls/tls.key"
        }

        retry_join {
          leader_api_addr         = "https://vault-1.vault-internal:8200"
          leader_ca_cert_file     = "/vault/tls/vault-tls/ca.crt"
          leader_client_cert_file = "/vault/tls/vault-tls/tls.crt"
          leader_client_key_file  = "/vault/tls/vault-tls/tls.key"
        }

        retry_join {
          leader_api_addr         = "https://vault-2.vault-internal:8200"
          leader_ca_cert_file     = "/vault/tls/vault-tls/ca.crt"
          leader_client_cert_file = "/vault/tls/vault-tls/tls.crt"
          leader_client_key_file  = "/vault/tls/vault-tls/tls.key"
        }
      }

      seal "awskms" {
        region     = "${var.aws_region}"
        kms_key_id = "${module.kms.vault_unseal_key_id}"
      }

      telemetry {
        prometheus_retention_time = "30s"
        disable_hostname         = true
      }

      service_registration "kubernetes" {}
    EOT
  }

  # Security context — passed as YAML block for correct nested structure
  values = [yamlencode({
    server = {
      securityContext = {
        pod = {
          runAsNonRoot = true
          fsGroup      = 1000
          seccompProfile = {
            type = "RuntimeDefault"
          }
        }
        container = {
          allowPrivilegeEscalation = false
          readOnlyRootFilesystem   = true
          runAsNonRoot             = true
          runAsUser                = 100
          runAsGroup               = 1000
          seccompProfile = {
            type = "RuntimeDefault"
          }
          capabilities = {
            drop = ["ALL"]
          }
        }
      }
    }
  })]

  # Pod disruption budget — maintain Raft quorum
  set {
    name  = "server.disruptionBudget.maxUnavailable"
    value = "1"
  }

  # UI
  set {
    name  = "ui.enabled"
    value = "true"
  }

  set {
    name  = "ui.serviceType"
    value = "ClusterIP"
  }

  depends_on = [
    kubernetes_namespace.vault,
    kubernetes_storage_class.vault,
    module.eks,
    module.kms,
  ]
}
