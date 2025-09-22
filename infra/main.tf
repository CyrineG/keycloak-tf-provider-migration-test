terraform {

  required_version = ">=1.2.4"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.38.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.0.2"
    }
    keycloak = {
      source  = "local/mrparkers-sorted/keycloak"
      version = "4.4.0"
    }
  }
}



provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
    config_context = "kind-keycloak-migration-test"
  }
}


locals {
  argo_cd_config = yamldecode(file("./../clusters/kind-local/argocd-applications/templates/argocd.yaml"))
  argo_cd_chart_version = local.argo_cd_config.spec.source.targetRevision
  argo_cd_values = yamlencode(local.argo_cd_config.spec.source.helm.valuesObject)
}

# Install ArgoCD via Helm chart
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version = local.argo_cd_chart_version # Pin a stable version
  namespace  = "argocd"
  timeout = 60

  values = [local.argo_cd_values]
}

resource "helm_release" "argo_cd_apps" {
  name       = "argo-cd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.2"
  namespace  = "argocd"

  values = [
    yamlencode({
      applications = {
        # Deployment of umbrella helm charts for infra (deployment/infra/infra-chart)
        infra = {
          namespace  = "argocd"
          project    = "default"
          source     = {
            repoURL        = "https://github.com/CyrineG/keycloak-tf-provider-migration-test.git"
            targetRevision = "main"
            path           = "clusters/kind-local/argocd-applications"
            directory = {
              recurse = true
              exclude = "**/.terraform/**"  # Exclude terraform directories
              include = "**/*.yaml,**/*.yml,charts/**"  # Only include specific files
            }
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "argocd"
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
          }
        },
      }
    })
  ]
  wait = true

  depends_on = [
    helm_release.argocd,
  ]
}
