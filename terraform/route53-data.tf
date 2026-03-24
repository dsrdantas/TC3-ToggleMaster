resource "time_sleep" "wait_for_lb" {
  create_duration = "120s"
  depends_on      = [module.apps]
}

data "kubernetes_service_v1" "argocd" {
  count = var.enable_route53 ? 1 : 0

  metadata {
    name      = "argocd-server"
    namespace = "argocd"
  }

  depends_on = [time_sleep.wait_for_lb]
}

data "kubernetes_service_v1" "nginx" {
  count = var.enable_route53 ? 1 : 0

  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [time_sleep.wait_for_lb]
}
