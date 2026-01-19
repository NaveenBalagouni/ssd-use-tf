output "helm_release_names" {
  value = { for host, r in helm_release.opsmx_ssd : host => r.name }
}

output "helm_namespaces" {
  value = { for host, r in helm_release.opsmx_ssd : host => r.namespace }
}
