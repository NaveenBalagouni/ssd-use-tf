git_repo_url    = "https://github.com/OpsMx/enterprise-ssd.git"
git_branch      = "2025-07"         # initial installation branch
# Path to kubeconfig is not needed because we will mount it from Kubernetes Secret
kubeconfig_path = ""
ingress_hosts    = ["ssd-use-tf.ssd-uat.opsmx.org"]
namespace       = "ssd-tf"
cert_manager_installed = true


