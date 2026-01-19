# Output Helm Release Names
output "helm_release_name" {
  value = [for r in helm_release.tf_ssd : r.name]
}


output "helm_namespace" {
  value = var.namespace
}

# Output Ingress Hosts
output "ssd_ingress_host" {
  value = var.ingress_hosts
}


