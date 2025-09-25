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
  }
}



provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
    config_context = "kind-keycloak-migration-test"
  }
}


locals {
  config = yamldecode(file("./secrets.yaml"))

  argo_cd_config = yamldecode(replace(replace(replace(
    file("./../clusters/kind-local/argocd-applications/templates/argocd.yaml"), "{{ .Values.keycloak.dev_realm.clients.argocd.clientId }}", local.config.keycloak.dev_realm.clients.argocd.clientId),
    "{{ .Values.keycloak.dev_realm.clients.argocd.clientSecret }}", local.config.keycloak.dev_realm.clients.argocd.clientSecret),
    "{{ .Values.keycloakDevRealmUrl }}", local.config.keycloak_dev_realm_url)
  )
  argo_cd_chart_version = local.argo_cd_config.spec.source.targetRevision
  argo_cd_values = yamlencode(local.argo_cd_config.spec.source.helm.valuesObject)


  project_members = yamldecode(file("./project_members.yaml"))

  # Add a list of rights to project_members. Look up the rights for each assigned role, join the lists and remove duplicates
  project_members_with_rights = [
    for m in local.project_members.project_members : merge(
      m,
      {
        rights : length(m.roles) > 0 ? toset(concat([for role in m.roles : local.config.project_member_roles[role].rights]...)) : []
      })
  ]

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
            path           = "clusters/kind-local/argocd-applications/templates"
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

module "keycloak" {
  source = "./keycloak"
  base_domain_name                  = local.config.base_domain_name
  admin_credentials                 = local.config.keycloak.admin
  external_technical_user_passwords = local.config.external_technical_user_passwords
  dev_realm                         = local.config.keycloak.dev_realm
  project_members                   = local.project_members_with_rights #
  access_token_lifespan             = local.config.keycloak.access_token_lifespan
}
