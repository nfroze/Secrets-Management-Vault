########################################
# Monitoring Namespace
########################################

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [module.eks]
}

########################################
# Prometheus Stack (kube-prometheus-stack)
# Includes Prometheus, Grafana, and Alertmanager
########################################

resource "helm_release" "prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "55.5.0"
  timeout    = 900
  wait       = false

  # Grafana
  set {
    name  = "grafana.enabled"
    value = "true"
  }

  set {
    name  = "grafana.adminPassword"
    value = "vault-demo-admin"
  }

  set {
    name  = "grafana.service.type"
    value = "ClusterIP"
  }

  # Grafana dashboard provisioning — auto-load Vault dashboard
  set {
    name  = "grafana.dashboardProviders.dashboardproviders\\.yaml.apiVersion"
    value = "1"
  }

  set {
    name  = "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].name"
    value = "vault"
  }

  set {
    name  = "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].orgId"
    value = "1"
  }

  set {
    name  = "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].folder"
    value = "Vault"
  }

  set {
    name  = "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].type"
    value = "file"
  }

  set {
    name  = "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].disableDeletion"
    value = "false"
  }

  set {
    name  = "grafana.dashboardProviders.dashboardproviders\\.yaml.providers[0].options.path"
    value = "/var/lib/grafana/dashboards/vault"
  }

  set {
    name  = "grafana.dashboardsConfigMaps.vault"
    value = "vault-grafana-dashboard"
  }

  # Prometheus
  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "7d"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "512Mi"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.requests.cpu"
    value = "250m"
  }

  # Alertmanager — minimal config for dev
  set {
    name  = "alertmanager.enabled"
    value = "true"
  }

  depends_on = [
    kubernetes_namespace.monitoring,
    module.eks,
  ]
}
