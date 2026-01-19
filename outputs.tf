output "helm_release_name" {
  description = "SSD Helm release name"
  value       = helm_release.opsmx_ssd.name
}

output "helm_release_namespace" {
  description = "Namespace where SSD is deployed"
  value       = helm_release.opsmx_ssd.namespace
}

output "ssd_version" {
  description = "SSD Helm chart version deployed"
  value       = helm_release.opsmx_ssd.version
}
