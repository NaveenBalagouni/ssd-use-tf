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

# 1. Namespace (Import if already exists)
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
  triggers_replace = [var.git_branch]

  provisioner "local-exec" {
    command = <<EOT
      rm -rf /tmp/enterprise-ssd
      git clone --branch ${var.git_branch} ${var.git_repo_url} /tmp/enterprise-ssd
    EOT
  }
}

# 3. Read the values file ONLY after cloning
# We use a data source here because it returns the 'content' specifically.
data "local_file" "ssd_values_content" {
  # This depends_on is the secret sauce
  depends_on = [terraform_data.clone_ssd_chart]
  filename   = "/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
}

# 4. Deploy / Upgrade SSD
resource "helm_release" "opsmx_ssd" {
  depends_on = [kubernetes_namespace.opmsx_ns]

  name       = "ssd"
  namespace  = var.namespace
  chart      = "/tmp/enterprise-ssd/charts/ssd"

  # We pass the content of the file, not the path string
  values = [
    data.local_file.ssd_values_content.content
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

# 5. Apply Job YAML
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
