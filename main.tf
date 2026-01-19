terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.16.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
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

# Step 1: Create namespace
resource "kubernetes_namespace" "opmsx_ns" {
  metadata {
    name = var.namespace
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}





# -----------------------------
# Step 1: Clone Helm Chart Repo
# -----------------------------
resource "null_resource" "clone_ssd_chart" {
  triggers = {
    git_repo   = var.git_repo_url
    git_branch = var.git_branch
  }

  provisioner "local-exec" {
    command = <<EOT
      rm -rf /tmp/enterprise-ssd
      git clone --branch ${var.git_branch} ${var.git_repo_url} /tmp/enterprise-ssd
      ls -l /tmp/enterprise-ssd/charts/ssd
    EOT
  }
}

# -----------------------------
# Step 2: Read values.yaml
# -----------------------------
data "local_file" "ssd_values" {
  filename   = "/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
  depends_on = [null_resource.clone_ssd_chart]
}

# -----------------------------
# Step 3: Deploy SSD Helm Releases
# -----------------------------
resource "helm_release" "opsmx_ssd" {
  for_each = toset(var.ingress_hosts)

  depends_on = [null_resource.clone_ssd_chart]

  name      = "ssd-terraform"
  namespace = var.namespace
  chart     = "/tmp/enterprise-ssd/charts/ssd"
  values    = [data.local_file.ssd_values.content]
  version   = "2025.04.00"
  

  set {
    name  = "ingress.enabled"
    value = "true"
  }

  set {
    name  = "global.certManager.installed"
    value = true
  }

  set {
    name  = "global.ssdUI.host"
    value = join(",", var.ingress_hosts) 
  }

  create_namespace = false
  force_update     = true
  recreate_pods    = true
  cleanup_on_fail  = true
  wait             = true

  lifecycle {
    replace_triggered_by = [null_resource.clone_ssd_chart]
  }
}
