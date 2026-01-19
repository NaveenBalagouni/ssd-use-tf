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
# Step 1: Namespace (Handled via import)
# -----------------------------
resource "kubernetes_namespace" "opmsx_ns" {
  metadata {
    name = var.namespace
  }
  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------
# Step 2: Clone SSD Helm Chart
# -----------------------------
resource "terraform_data" "clone_ssd_chart" {
  triggers_replace = [var.git_branch]

  provisioner "local-exec" {
    command = <<EOT
      rm -rf /tmp/enterprise-ssd
      git clone --branch ${var.git_branch} ${var.git_repo_url} /tmp/enterprise-ssd
    EOT
  }
}

# -----------------------------
# Step 3: Read Values (Plan-Safe)
# -----------------------------
# This data source waits for the clone to finish before looking for the file
data "local_file" "ssd_values" {
  depends_on = [terraform_data.clone_ssd_chart]
  filename   = "/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
}

# -----------------------------
# Step 4: Deploy / Upgrade SSD
# -----------------------------
resource "helm_release" "opsmx_ssd" {
  depends_on = [
    kubernetes_namespace.opmsx_ns,
    terraform_data.clone_ssd_chart
  ]

  name       = "ssd"
  namespace  = var.namespace
  chart      = "/tmp/enterprise-ssd/charts/ssd"
  
  # Pass the ACTUAL CONTENT from the data source to avoid JSON errors
  values = [data.local_file.ssd_values.content]

  version          = var.ssd_version
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
}

# -----------------------------
# Step 5: Apply Job YAML
# -----------------------------
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
