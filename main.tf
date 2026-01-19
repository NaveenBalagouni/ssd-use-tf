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

# 2. Clone SSD Helm Chart
resource "terraform_data" "clone_ssd_chart" {
  triggers_replace = [
    var.git_repo_url,
    var.git_branch
  ]

  provisioner "local-exec" {
    command = <<EOT
      rm -rf /tmp/enterprise-ssd
      git clone --branch ${var.git_branch} ${var.git_repo_url} /tmp/enterprise-ssd
    EOT
  }
}

# 3. Deploy / Upgrade SSD
resource "helm_release" "opsmx_ssd" {
  # Explicitly wait for the clone to finish
  depends_on = [terraform_data.clone_ssd_chart, kubernetes_namespace.opmsx_ns]

  name       = "ssd"
  namespace  = var.namespace
  
  # We use the absolute path string. 
  # Helm will look for this folder only when it starts the installation.
  chart      = "/tmp/enterprise-ssd/charts/ssd"
  
  # FIX: Pass the path as a string in the list. 
  # DO NOT use file() or templatefile() here.
  values = [
    "/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
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

# 4. Apply Job YAML
resource "terraform_data" "apply_job_yaml" {
  depends_on = [helm_release.opsmx_ssd]

  triggers_replace = [
    # Using path.module ensures this is checked during Plan safely
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
