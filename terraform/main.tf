resource "google_service_account" "default" {
  account_id   = "istio-k8s-demo"
  display_name = "Service Account"
}

resource "google_container_cluster" "primary" {
  name               = "istio-jwt-demo"
  location           = "us-central1-a"
  initial_node_count = 1
  node_config {
    machine_type = "n1-standard-2"
    service_account = google_service_account.default.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  timeouts {
    create = "30m"
    update = "40m"
  }
}

data "google_client_config" "provider" {}

provider "kubernetes" {
  host  = "https://${google_container_cluster.primary.endpoint}"
  token = data.google_client_config.provider.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.primary.master_auth[0].cluster_ca_certificate,
  )
}

resource "kubernetes_namespace" "istio-system" {
  metadata {
    name = "istio-system"
  }
}

resource "helm_release" "istio-base" {
  name       = "istio-base"
  namespace = kubernetes_namespace.istio-system.metadata[0].name
  chart = "./istio-1.10.2/manifests/charts/base"
}


resource "helm_release" "istiod" {
  name       = "istiod"
  namespace = kubernetes_namespace.istio-system.metadata[0].name
  chart = "./istio-1.10.2/manifests/charts/istio-control/istio-discovery"
}

resource "helm_release" "ingress-gateway" {
  name       = "istio-ingress"
  namespace = kubernetes_namespace.istio-system.metadata[0].name
  chart = "./istio-1.10.2/manifests/charts/gateways/istio-ingress"
}

resource "kubernetes_manifest" "gateway_demo_gateway" {
  provider = kubernetes-alpha
  manifest = {
    "apiVersion" = "networking.istio.io/v1alpha3"
    "kind" = "Gateway"
    "metadata" = {
      "name" = "demo-gateway"
      "namespace" = "default"
    }
    "spec" = {
      "selector" = {
        "istio" = "ingressgateway"
      }
      "servers" = [
        {
          "hosts" = [
            "*",
          ]
          "port" = {
            "name" = "http"
            "number" = 80
            "protocol" = "HTTP"
          }
        },
      ]
    }
  }
}

resource "kubernetes_manifest" "authorizationpolicy_require_jwt" {
  provider = kubernetes-alpha
  manifest = {
    "apiVersion" = "security.istio.io/v1beta1"
    "kind" = "AuthorizationPolicy"
    "metadata" = {
      "name" = "require-jwt"
      "namespace" = "istio-system"
    }
    "spec" = {
      "action" = "ALLOW"
      "rules" = [
        {
          "from" = [
            {
              "source" = {
                "requestPrincipals" = [
                  "test/*",
                ]
              }
            },
          ]
        },
      ]
      "selector" = {
        "matchLabels" = {
          "istio" = "ingressgateway"
        }
      }
    }
  }
}
