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

# 3. Safe File Reader
# This data source will wait for the clone to finish before trying to read.
data "local_file" "ssd_values" {
  filename   = "/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
  depends_on = [terraform_data.clone_ssd_chart]
}

# 4. Deploy / Upgrade SSD

resource "helm_release" "opsmx_ssd" {
  depends_on = [kubernetes_namespace.opmsx_ns, terraform_data.clone_ssd_chart]

  name       = "ssd"
  namespace  = var.namespace
  chart      = "/tmp/enterprise-ssd/charts/ssd"

  # We use the content from the data source
  values = [
    data.local_file.ssd_values.content
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
