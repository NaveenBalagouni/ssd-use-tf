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
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# -----------------------------
# Providers
# -----------------------------
provider "kubernetes" {
  config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
  }
}

# -----------------------------
# Step 1: Namespace 
# -----------------------------
resource "kubernetes_namespace" "opmsx_ns" {
  metadata {
    name = var.namespace
  }

  # This prevents Terraform from deleting the namespace if the stack is destroyed
  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------
# Step 2: Clone SSD Helm Chart
# -----------------------------
resource "terraform_data" "clone_ssd_chart" {
  input = {
    repo   = var.git_repo_url
    branch = var.git_branch
  }

  provisioner "local-exec" {
    command = <<EOT
      rm -rf /tmp/enterprise-ssd
      git clone --branch ${var.git_branch} ${var.git_repo_url} /tmp/enterprise-ssd
    EOT
  }
}

# -----------------------------
# Step 3: Load Helm values.yaml
# -----------------------------
data "local_file" "ssd_values" {
  filename   = "/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
  depends_on = [terraform_data.clone_ssd_chart]
}

# -----------------------------
# Step 4: Deploy / Upgrade SSD
# -----------------------------
resource "helm_release" "opsmx_ssd" {
  name       = "ssd"
  namespace  = kubernetes_namespace.opmsx_ns.metadata[0].name
  chart      = "/tmp/enterprise-ssd/charts/ssd"
  repository = null # Local chart

  # Use the loaded values file
  values = [data.local_file.ssd_values.content]

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

  # Ensure the chart is cloned before Helm tries to install it
  depends_on = [terraform_data.clone_ssd_chart]
}

# -----------------------------
# Step 5: Apply Job YAML
# -----------------------------
resource "terraform_data" "apply_job_yaml" {
  triggers_replace = [
    # Re-run if the template file changes
    hashicls(file("${path.module}/job.yaml")),
    # Re-run if the Helm release is updated
    helm_release.opsmx_ssd.version
  ]

  provisioner "local-exec" {
    command = <<EOT
      cat <<EOF | kubectl apply -f -
      ${templatefile("${path.module}/job.yaml", { namespace = var.namespace })}
      EOF
    EOT
  }

  depends_on = [helm_release.opsmx_ssd]
}
