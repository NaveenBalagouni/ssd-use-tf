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

# 1. Clone Chart Logic (Moved back to Terraform but isolated)
resource "terraform_data" "clone_ssd" {
  triggers_replace = [var.git_branch]

  provisioner "local-exec" {
    command = <<EOT
      rm -rf /tmp/enterprise-ssd
      git clone --branch ${var.git_branch} ${var.git_repo_url} /tmp/enterprise-ssd
    EOT
  }
}

# 2. Namespace (Import if already exists)
resource "kubernetes_namespace" "opmsx_ns" {
  metadata {
    name = var.namespace
  }
  lifecycle {
    prevent_destroy = true
  }
}

# 3. Deploy / Upgrade SSD
resource "helm_release" "opsmx_ssd" {
  # This dependency is critical: Helm won't start until cloning is done
  depends_on = [terraform_data.clone_ssd, kubernetes_namespace.opmsx_ns]

  name       = "ssd"
  namespace  = var.namespace
  chart      = "/tmp/enterprise-ssd/charts/ssd"

  # FIX: We pass the PATH as a string, not the file() function.
  # The Helm provider will read the file during the Apply phase.
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
