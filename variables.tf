

# -----------------------------
# Git Repo & Branch
# -----------------------------
variable "git_repo_url" {
  description = "https://github.com/OpsMx/enterprise-ssd.git"
  type        = string
}

variable "git_branch" {
  description = "Git branch to clone (for upgrades)"
  type        = string
  default     = "2025-07"
}

# -----------------------------
# Kubernetes Config
# -----------------------------
variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = ""  # Empty means use in-cluster config
}

variable "namespace" {
  description = "Namespace to deploy OpsMx SSD"
  type        = string
  default     = "ssd-tf"
}

# -----------------------------
# Ingress Hosts
# -----------------------------
variable "ingress_hosts" {
  description = "List of DNS hostnames for SSD UI"
  type        = list(string)
  
}

# -----------------------------
# Helm Release & Cert Manager
# -----------------------------
variable "helm_release_name" {
  description = "Name of Helm release"
  type        = string
  default     = "ssd-opsmx-terraform"
}

variable "cert_manager_installed" {
  description = "Set to true if cert-manager is installed"
  type        = bool
  default     = true
}

