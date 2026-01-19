variable "git_repo_url" {
  description = "URL of the Git repository containing the OpsMx SSD Helm chart"
  type        = string
  default     = "https://github.com/OpsMx/enterprise-ssd.git"
}

variable "git_branch" {
  description = "Git branch to clone (can be updated for upgrades)"
  type        = string
  default     = "2025-05"
}

variable "kubeconfig_path" {
  description = "Path to your kubeconfig file"
  type        = string
  default     = ""  # Empty means use in-cluster config

}


# Ingress Configuration
# ---------------------------------------------
variable "ingress_hosts" {
  description = "The DNS hostname for the SSD UI (must be lowercase)"
  type        = list(string)
}


variable "namespace" {
  description = "Kubernetes namespace to deploy SSD"
  type        = string
  default     = "ssd-opsmx-tf"
}


variable "helm_release_name" {
  description = "Name of the Helm release"
  type        = string
  default     = "ssd-opsmx-terraform"
}



variable "cert_manager_installed" {
  description = "Set to true if cert-manager is installed"
  type        = bool
  default     = true
}
