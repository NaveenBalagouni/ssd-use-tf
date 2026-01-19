terraform {
  required_version = ">= 1.4.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.16.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
  }
}

# 1. Namespace
resource "kubernetes_namespace" "opmsx_ns" {
  metadata {
    name = var.namespace
  }
  lifecycle {
    prevent_destroy = true
  }
}

# 2. Deploy / Upgrade SSD
resource "helm_release" "opsmx_ssd" {
  depends_on = [kubernetes_namespace.opmsx_ns]

  name       = "ssd"
  namespace  = var.namespace
  chart      = "/tmp/enterprise-ssd/charts/ssd"

  # Safely read the file because our script ensures it exists beforehand
  values = [
    file("/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml")
  ]

  version          = var.ssd_version
  create_namespace = false
  force_update     = true
  recreate_pods    = true
  cleanup_on_fail  = true
  wait             = true
  timeout          = 900

  set {
    name  = "ingress.enabled"
    value = "true"
  }
  set {
    name  = "global.ssdUI.host"
    value = join(",", var.ingress_hosts)
  }
  set {
    name  = "global.certManager.installed"
    value = "true"
  }
}

# 3. Apply Job YAML
resource "terraform_data" "apply_job_yaml" {
  depends_on = [helm_release.opsmx_ssd]
  
  triggers_replace = [
    filebase64sha256("${path.module}/job.yaml"),
    var.ssd_version
  ]

  provisioner "local-exec" {
    command = <<EOT
      cat <<EOF | kubectl apply -f -
      ${templatefile("${path.module}/job.yaml", { namespace = var.namespace })}
      EOF
    EOT
  }
}
