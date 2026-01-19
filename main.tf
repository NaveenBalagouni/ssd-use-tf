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
# 1. Namespace
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
# 2. Clone SSD Helm Chart
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
# 3. Deploy / Upgrade SSD
# -----------------------------
resource "helm_release" "opsmx_ssd" {
  # This tells Terraform: Do not even look at this resource until the clone is done
  depends_on = [terraform_data.clone_ssd_chart, kubernetes_namespace.opmsx_ns]

  name       = "ssd"
  namespace  = var.namespace
  chart      = "/tmp/enterprise-ssd/charts/ssd"
  
  # By using 'templatefile' inside the list, and since it depends on the clone,
  # we avoid the "inconsistent plan" error.
  values = [
    templatefile("/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml", {})
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

# -----------------------------
# 4. Apply Job YAML
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
