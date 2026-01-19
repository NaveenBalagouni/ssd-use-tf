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

# 1. Namespace (Handled via the import command above)
resource "kubernetes_namespace" "opmsx_ns" {
  metadata {
    name = var.namespace
  }
  lifecycle {
    # This prevents the namespace from being accidentally deleted
    prevent_destroy = true
  }
}

# 2. Clone SSD Helm Chart
resource "terraform_data" "clone_ssd_chart" {
  triggers_replace = [var.git_branch]

  provisioner "local-exec" {
    command = <<EOT
      rm -rf /tmp/enterprise-ssd
      git clone --branch ${var.git_branch} ${var.git_repo_url} /tmp/enterprise-ssd
    EOT
  }
}

# 3. Deploy / Upgrade SSD
resource "helm_release" "opsmx_ssd" {
  # CRITICAL: Ensures cloning finishes before Helm tries to read the file
  depends_on = [terraform_data.clone_ssd_chart, kubernetes_namespace.opmsx_ns]

  name       = "ssd"
  namespace  = var.namespace
  chart      = "/tmp/enterprise-ssd/charts/ssd"

  # We pass the actual file content to avoid "unmarshal" errors
  values = [
    file("/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml")
  ]

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
  set {
    name  = "global.certManager.installed"
    value = "true"
  }
}

# 4. Apply Job YAML
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
