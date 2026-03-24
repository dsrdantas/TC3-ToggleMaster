locals {
  apps_yaml = templatefile("${path.module}/applications.yaml.tftpl", {
    argocd_namespace      = var.argocd_namespace
    gitops_namespace      = var.gitops_namespace
    gitops_repo_url       = var.gitops_repo_url
    gitops_target_revision = var.gitops_target_revision
    gitops_project        = var.gitops_project
  })

  master_key = var.master_key != "" ? var.master_key : random_id.master_key.hex
  db_user = "tm_user"

  auth_db_host      = split(":", var.auth_db_endpoint)[0]
  flag_db_host      = split(":", var.flag_db_endpoint)[0]
  targeting_db_host = split(":", var.targeting_db_endpoint)[0]

  auth_db_url      = "postgres://${local.db_user}:${var.db_password}@${local.auth_db_host}:5432/auth_db"
  flag_db_url      = "postgres://${local.db_user}:${var.db_password}@${local.flag_db_host}:5432/flag_db"
  targeting_db_url = "postgres://${local.db_user}:${var.db_password}@${local.targeting_db_host}:5432/targeting_db"

  apps_docs = [
    for doc in split("\n---\n", trimspace(local.apps_yaml)) : yamldecode(doc)
  ]
}

resource "random_id" "master_key" {
  byte_length = 32
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = var.argocd_namespace
  create_namespace = true

  version = var.argocd_chart_version

  timeout = 600
  wait    = true

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }
}

resource "time_sleep" "wait_for_crds" {
  depends_on = [helm_release.argocd]
  create_duration = "60s"
}

resource "kubernetes_namespace_v1" "ns" {
  metadata {
    name = var.gitops_namespace
  }
}

resource "kubernetes_secret_v1" "auth_service_secret" {
  metadata {
    name      = "auth-service-secret"
    namespace = var.gitops_namespace
  }
  type = "Opaque"
  data = {
    POSTGRES_PASSWORD = var.db_password
    MASTER_KEY        = local.master_key
    DATABASE_URL      = local.auth_db_url
  }
  depends_on = [kubernetes_namespace_v1.ns]
}

resource "kubernetes_secret_v1" "auth_db_secret" {
  metadata {
    name      = "auth-db-secret"
    namespace = var.gitops_namespace
  }
  type = "Opaque"
  data = {
    POSTGRES_HOST     = local.auth_db_host
    POSTGRES_DB       = "auth_db"
    POSTGRES_USER     = local.db_user
    POSTGRES_PASSWORD = var.db_password
  }
  depends_on = [kubernetes_namespace_v1.ns]
}

resource "kubernetes_secret_v1" "flag_service_secret" {
  metadata {
    name      = "flag-service-secret"
    namespace = var.gitops_namespace
  }
  type = "Opaque"
  data = {
    POSTGRES_PASSWORD = var.db_password
    DATABASE_URL      = local.flag_db_url
  }
  depends_on = [kubernetes_namespace_v1.ns]
}

resource "kubernetes_secret_v1" "flag_db_secret" {
  metadata {
    name      = "flag-db-secret"
    namespace = var.gitops_namespace
  }
  type = "Opaque"
  data = {
    POSTGRES_HOST     = local.flag_db_host
    POSTGRES_DB       = "flag_db"
    POSTGRES_USER     = local.db_user
    POSTGRES_PASSWORD = var.db_password
  }
  depends_on = [kubernetes_namespace_v1.ns]
}

resource "kubernetes_secret_v1" "targeting_service_secret" {
  metadata {
    name      = "targeting-service-secret"
    namespace = var.gitops_namespace
  }
  type = "Opaque"
  data = {
    POSTGRES_PASSWORD = var.db_password
    DATABASE_URL      = local.targeting_db_url
  }
  depends_on = [kubernetes_namespace_v1.ns]
}

resource "kubernetes_secret_v1" "targeting_db_secret" {
  metadata {
    name      = "targeting-db-secret"
    namespace = var.gitops_namespace
  }
  type = "Opaque"
  data = {
    POSTGRES_HOST     = local.targeting_db_host
    POSTGRES_DB       = "targeting_db"
    POSTGRES_USER     = local.db_user
    POSTGRES_PASSWORD = var.db_password
  }
  depends_on = [kubernetes_namespace_v1.ns]
}

resource "kubernetes_secret_v1" "evaluation_service_secret" {
  metadata {
    name      = "evaluation-service-secret"
    namespace = var.gitops_namespace
  }
  type = "Opaque"
  data = {
    REDIS_URL             = "redis://${var.redis_endpoint}:6379"
    SERVICE_API_KEY       = var.service_api_key
    AWS_SQS_URL           = var.sqs_queue_url
    AWS_ACCESS_KEY_ID     = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
    AWS_SESSION_TOKEN     = var.aws_session_token
  }
  depends_on = [kubernetes_namespace_v1.ns]
}

resource "kubernetes_secret_v1" "analytics_service_secret" {
  metadata {
    name      = "analytics-service-secret"
    namespace = var.gitops_namespace
  }
  type = "Opaque"
  data = {
    AWS_SQS_URL           = var.sqs_queue_url
    AWS_ACCESS_KEY_ID     = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
    AWS_SESSION_TOKEN     = var.aws_session_token
  }
  depends_on = [kubernetes_namespace_v1.ns]
}

resource "kubernetes_manifest" "apps" {
  for_each = {
    for idx, doc in local.apps_docs : tostring(idx) => doc
    if var.enable_argocd_apps
  }

  manifest = each.value

  depends_on = [
    time_sleep.wait_for_crds,
    kubernetes_namespace_v1.ns,
    kubernetes_secret_v1.auth_service_secret,
    kubernetes_secret_v1.auth_db_secret,
    kubernetes_secret_v1.flag_service_secret,
    kubernetes_secret_v1.flag_db_secret,
    kubernetes_secret_v1.targeting_service_secret,
    kubernetes_secret_v1.targeting_db_secret,
    kubernetes_secret_v1.evaluation_service_secret,
    kubernetes_secret_v1.analytics_service_secret
  ]
}
