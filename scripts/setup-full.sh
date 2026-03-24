#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_DIR/terraform"
TFVARS_FILE="$TERRAFORM_DIR/terraform.tfvars"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
  echo "Uso: $0 [--plan | --apply | --create | --destroy-all]"
  echo "  --plan        Executa apenas terraform plan"
  echo "  --apply       Executa apenas terraform apply"
  echo "  --create      Executa plan+apply e etapas adicionais (default)"
  echo "  --gen-api-key Gera apenas a SERVICE_API_KEY"
  echo "  --destroy-all Remove toda a infraestrutura"
}

ACTION=""
if [ $# -gt 1 ]; then
  usage
  exit 1
elif [ $# -eq 0 ]; then
  usage
  exit 0
else
  case "$1" in
    --plan) ACTION="plan" ;;
    --apply) ACTION="apply" ;;
    --create) ACTION="create" ;;
    --gen-api-key) ACTION="gen-api-key" ;;
    --destroy-all) ACTION="destroy-all" ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
fi

preflight_setup() {
  echo "============================================"
  echo "  ToggleMaster - terraform+secrets+argocd+applications"
  echo "============================================"
  echo ""
  echo ">>> [0/7] Validacao pre-requisitos e setup de ferramentas..."

  if ! command -v curl >/dev/null 2>&1; then
    echo "ERRO: curl nao encontrado. Instale curl antes de continuar." >&2
    exit 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERRO: python3 nao encontrado. Instale python3 antes de continuar." >&2
    exit 1
  fi

  LOCAL_BIN="$HOME/.local/bin"
  mkdir -p "$LOCAL_BIN"
  export PATH="$LOCAL_BIN:$PATH"

  if ! command -v terraform >/dev/null 2>&1; then
    echo ">>> Terraform nao encontrado. Instalando localmente..."
    TF_VERSION="${TF_VERSION:-1.6.6}"
    OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
    ARCH="$(uname -m)"
    case "$ARCH" in
      x86_64|amd64) ARCH="amd64" ;;
      aarch64|arm64) ARCH="arm64" ;;
      *) echo "ERRO: arquitetura nao suportada: $ARCH" >&2; exit 1 ;;
    esac

    TF_ZIP="terraform_${TF_VERSION}_${OS}_${ARCH}.zip"
    TF_URL="https://releases.hashicorp.com/terraform/${TF_VERSION}/${TF_ZIP}"

    curl -fsSL "$TF_URL" -o "/tmp/$TF_ZIP"
    python3 - <<PY
import zipfile
zipfile.ZipFile("/tmp/$TF_ZIP").extract("terraform", "$LOCAL_BIN")
PY
    chmod +x "$LOCAL_BIN/terraform"
    echo "  Terraform instalado em $LOCAL_BIN/terraform"
  fi

  AWS_NEEDS_INSTALL=false
  AWS_OLD=false
  if ! command -v aws >/dev/null 2>&1; then
    AWS_NEEDS_INSTALL=true
  else
    AWS_VER_RAW="$(aws --version 2>/dev/null | awk '{print $1}' | cut -d/ -f2)"
    AWS_MAJOR="$(echo "$AWS_VER_RAW" | cut -d. -f1)"
    AWS_MINOR="$(echo "$AWS_VER_RAW" | cut -d. -f2)"
    if [ "${AWS_MAJOR:-0}" -lt 2 ] || { [ "${AWS_MAJOR:-0}" -eq 2 ] && [ "${AWS_MINOR:-0}" -lt 7 ]; }; then
      AWS_OLD=true
    fi
  fi

  if [ "$AWS_NEEDS_INSTALL" = "true" ]; then
    echo ">>> AWS CLI nao encontrado. Instalando localmente..."
    ARCH="$(uname -m)"
    case "$ARCH" in
      x86_64|amd64) AWS_ARCH="x86_64" ;;
      aarch64|arm64) AWS_ARCH="aarch64" ;;
      *) echo "ERRO: arquitetura nao suportada: $ARCH" >&2; exit 1 ;;
    esac
    TMPDIR_LOCAL="$HOME/.local/tmp"
    mkdir -p "$TMPDIR_LOCAL"
    AWS_CLI_ZIP="$TMPDIR_LOCAL/awscliv2.zip"
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o "$AWS_CLI_ZIP"
    python3 - <<PY
import zipfile
zipfile.ZipFile("$AWS_CLI_ZIP").extractall("$TMPDIR_LOCAL")
PY
    chmod +x "$TMPDIR_LOCAL/aws/install" 2>/dev/null || true
    INSTALL_ARGS=(-i "$HOME/.local/aws-cli" -b "$LOCAL_BIN")
    if [ -d "$HOME/.local/aws-cli/v2/current" ]; then
      INSTALL_ARGS+=(--update)
    fi
    "$TMPDIR_LOCAL/aws/install" "${INSTALL_ARGS[@]}" >/dev/null || true
    if [ -x "$LOCAL_BIN/aws" ]; then
      echo "  AWS CLI instalado em $LOCAL_BIN/aws"
    else
      echo "WARN: nao foi possivel instalar AWS CLI localmente. Usando aws do sistema." >&2
    fi
  fi

  KUBECTL_TARGET_VER="${KUBECTL_TARGET_VER:-}"
  if [ -z "$KUBECTL_TARGET_VER" ]; then
    if [ "${AWS_OLD:-false}" = "true" ]; then
      KUBECTL_TARGET_VER="v1.23.17"
    else
      KUBECTL_TARGET_VER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    fi
  fi

  if ! command -v kubectl >/dev/null 2>&1; then
    echo ">>> kubectl nao encontrado. Instalando localmente..."
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_TARGET_VER}/bin/linux/amd64/kubectl" -o "$LOCAL_BIN/kubectl"
    chmod +x "$LOCAL_BIN/kubectl"
    echo "  kubectl instalado em $LOCAL_BIN/kubectl"
  else
    echo ">>> Instalando kubectl compatível em $LOCAL_BIN..."
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_TARGET_VER}/bin/linux/amd64/kubectl" -o "$LOCAL_BIN/kubectl"
    chmod +x "$LOCAL_BIN/kubectl"
  fi

  if ! command -v helm >/dev/null 2>&1; then
    echo ">>> helm nao encontrado. Instalando localmente..."
    HELM_VERSION="${HELM_VERSION:-v3.14.4}"
    ARCH="$(uname -m)"
    case "$ARCH" in
      x86_64|amd64) ARCH="amd64" ;;
      aarch64|arm64) ARCH="arm64" ;;
      *) echo "ERRO: arquitetura nao suportada: $ARCH" >&2; exit 1 ;;
    esac
    HELM_TGZ="helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
    curl -fsSL "https://get.helm.sh/${HELM_TGZ}" -o "/tmp/${HELM_TGZ}"
    tar -xzf "/tmp/${HELM_TGZ}" -C /tmp
    mv "/tmp/linux-${ARCH}/helm" "$LOCAL_BIN/helm"
    chmod +x "$LOCAL_BIN/helm"
    echo "  helm instalado em $LOCAL_BIN/helm"
  fi

  if [ -x "$LOCAL_BIN/aws" ]; then
    AWS_BIN="$LOCAL_BIN/aws"
  else
    AWS_BIN="$(command -v aws)"
  fi
  if [ -x "$LOCAL_BIN/kubectl" ]; then
    KUBECTL_BIN="$LOCAL_BIN/kubectl"
  else
    KUBECTL_BIN="$(command -v kubectl)"
  fi

  if ! command -v git >/dev/null 2>&1; then
    echo "ERRO: git nao encontrado. Instale git antes de continuar." >&2
    exit 1
  fi
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERRO: docker nao encontrado. Instale docker antes de continuar." >&2
    exit 1
  fi

  if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    AWS_ACCESS_KEY_ID=$("$AWS_BIN" configure get aws_access_key_id 2>/dev/null || echo "")
  fi
  if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_SECRET_ACCESS_KEY=$("$AWS_BIN" configure get aws_secret_access_key 2>/dev/null || echo "")
  fi
  if [ -z "$AWS_SESSION_TOKEN" ]; then
    AWS_SESSION_TOKEN=$("$AWS_BIN" configure get aws_session_token 2>/dev/null || echo "")
  fi

  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "ERRO: Credenciais AWS nao encontradas (nem em env vars, nem em aws configure)."
    exit 1
  fi
  echo "  AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:12}..."

  export TF_VAR_aws_access_key_id="${TF_VAR_aws_access_key_id:-$AWS_ACCESS_KEY_ID}"
  export TF_VAR_aws_secret_access_key="${TF_VAR_aws_secret_access_key:-$AWS_SECRET_ACCESS_KEY}"
  export TF_VAR_aws_session_token="${TF_VAR_aws_session_token:-$AWS_SESSION_TOKEN}"

  export TF_VAR_enable_apps="${TF_VAR_enable_apps:-true}"

  tfvars_get() {
    local key="$1"
    python3 - <<PY 2>/dev/null || true
import re, sys
path = "$TFVARS_FILE"
key = "$key"
try:
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            m = re.match(rf"^\\s*{re.escape(key)}\\s*=\\s*\\\"(.*)\\\"\\s*$", line)
            if m:
                print(m.group(1))
                sys.exit(0)
except FileNotFoundError:
    pass
PY
  }

  TF_EXTRA_VARS=()
  AWS_ID_TF=$(tfvars_get "aws_access_key_id")
  AWS_SECRET_TF=$(tfvars_get "aws_secret_access_key")
  AWS_TOKEN_TF=$(tfvars_get "aws_session_token")

  if [ -z "$AWS_ID_TF" ]; then
    TF_EXTRA_VARS+=("-var" "aws_access_key_id=$AWS_ACCESS_KEY_ID")
  fi
  if [ -z "$AWS_SECRET_TF" ]; then
    TF_EXTRA_VARS+=("-var" "aws_secret_access_key=$AWS_SECRET_ACCESS_KEY")
  fi
  if [ -z "$AWS_TOKEN_TF" ]; then
    TF_EXTRA_VARS+=("-var" "aws_session_token=$AWS_SESSION_TOKEN")
  fi
}

ensure_backend() {
  echo ">>> [1/7] Terraform (backend + plan + apply)..."

  BACKEND_FILE="$TERRAFORM_DIR/backend.tf"
  if [ ! -f "$BACKEND_FILE" ]; then
    echo "ERRO: backend.tf nao encontrado em $TERRAFORM_DIR" >&2
    exit 1
  fi

  BACKEND_BUCKET=$(awk -F'=' '/bucket/ {gsub(/[ "]/,"",$2); print $2; exit}' "$BACKEND_FILE")
  BACKEND_TABLE=$(awk -F'=' '/dynamodb_table/ {gsub(/[ "]/,"",$2); print $2; exit}' "$BACKEND_FILE")
  BACKEND_REGION=$(awk -F'=' '/region/ {gsub(/[ "]/,"",$2); print $2; exit}' "$BACKEND_FILE")

  if [ -z "$BACKEND_BUCKET" ] || [ -z "$BACKEND_TABLE" ] || [ -z "$BACKEND_REGION" ]; then
    echo "ERRO: nao foi possivel ler bucket/region/dynamodb_table do backend.tf" >&2
    exit 1
  fi

  echo "  Backend bucket:  $BACKEND_BUCKET"
  echo "  Backend table:   $BACKEND_TABLE"
  echo "  Backend region:  $BACKEND_REGION"

  if ! "$AWS_BIN" s3api head-bucket --bucket "$BACKEND_BUCKET" >/dev/null 2>&1; then
    echo ">>> Bucket do backend nao existe. Criando..."
    if [ "$BACKEND_REGION" = "us-east-1" ]; then
      "$AWS_BIN" s3api create-bucket --bucket "$BACKEND_BUCKET" --region "$BACKEND_REGION" >/dev/null
    else
      "$AWS_BIN" s3api create-bucket --bucket "$BACKEND_BUCKET" --region "$BACKEND_REGION" \
        --create-bucket-configuration LocationConstraint="$BACKEND_REGION" >/dev/null
    fi
  fi

  if ! "$AWS_BIN" dynamodb describe-table --table-name "$BACKEND_TABLE" --region "$BACKEND_REGION" >/dev/null 2>&1; then
    echo ">>> Tabela DynamoDB do backend nao existe. Criando..."
    "$AWS_BIN" dynamodb create-table \
      --table-name "$BACKEND_TABLE" \
      --attribute-definitions AttributeName=LockID,AttributeType=S \
      --key-schema AttributeName=LockID,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --region "$BACKEND_REGION" >/dev/null
    "$AWS_BIN" dynamodb wait table-exists --table-name "$BACKEND_TABLE" --region "$BACKEND_REGION" >/dev/null
  fi

  cd "$TERRAFORM_DIR"
  terraform init
}

has_module_apps() {
  terraform state list 2>/dev/null | grep -q '^module.apps\.'
}

tf_plan_only() {
  local label="$1"
  shift
  set +e
  terraform plan -detailed-exitcode "$@" "${TF_EXTRA_VARS[@]}"
  local plan_exit=$?
  set -e

  if [ "$plan_exit" -eq 0 ]; then
    echo "  [OK] Nenhuma mudanca ($label)."
  elif [ "$plan_exit" -eq 2 ]; then
    echo "  [OK] Mudancas detectadas ($label)."
  else
    echo "ERRO: terraform plan ($label) falhou (exit $plan_exit)" >&2
    exit "$plan_exit"
  fi
}

tf_apply() {
  local label="$1"
  shift
  set +e
  terraform plan -detailed-exitcode "$@" "${TF_EXTRA_VARS[@]}"
  local plan_exit=$?
  set -e

  if [ "$plan_exit" -eq 0 ]; then
    echo "  [OK] Nenhuma mudanca ($label). Pulando apply."
  elif [ "$plan_exit" -eq 2 ]; then
    terraform apply -auto-approve "$@" "${TF_EXTRA_VARS[@]}"
  else
    echo "ERRO: terraform plan ($label) falhou (exit $plan_exit)" >&2
    exit "$plan_exit"
  fi
}

configure_kubectl() {
  echo ""
  echo ">>> [2/7] Configurando kubectl"

  CLUSTER_NAME=$(grep -m1 '^cluster_name' "$TERRAFORM_DIR/terraform.tfvars" | python3 -c "import sys; print(sys.stdin.read().split('\"')[1])")
  if [ -z "$CLUSTER_NAME" ]; then
    CLUSTER_NAME="dsrdantas-cluster"
  fi

  if ! "$KUBECTL_BIN" cluster-info > /dev/null 2>&1; then
    echo ">>> kubectl nao conectado. Configurando..."
    "$AWS_BIN" eks update-kubeconfig --name "$CLUSTER_NAME" --region us-east-1
    python3 - <<PY 2>/dev/null || true
import os
path = os.path.expanduser("~/.kube/config")
aws_old = os.environ.get("AWS_OLD", "false").lower() == "true"
try:
    with open(path, "r", encoding="utf-8") as f:
        data = f.read()
    # Se AWS CLI for antigo, mantenha v1alpha1; caso contrario, use v1beta1
    if aws_old:
        if "client.authentication.k8s.io/v1beta1" in data:
            data = data.replace("client.authentication.k8s.io/v1beta1", "client.authentication.k8s.io/v1alpha1")
    else:
        if "client.authentication.k8s.io/v1alpha1" in data:
            data = data.replace("client.authentication.k8s.io/v1alpha1", "client.authentication.k8s.io/v1beta1")
    with open(path, "w", encoding="utf-8") as f:
        f.write(data)
except FileNotFoundError:
    pass
PY
  fi

  "$KUBECTL_BIN" get nodes
}

terraform_plan_flow() {
  if has_module_apps; then
    echo "  [OK] module.apps encontrado no state. Pulando plan infra com enable_apps=false."
  else
    tf_plan_only "infra" -var enable_apps=false
  fi
  tf_plan_only "argocd" -var enable_apps=true -var enable_argocd_apps=false
  tf_plan_only "apps" -var enable_apps=true -var enable_argocd_apps=true
}

terraform_apply_flow() {
  if has_module_apps; then
    echo "  [OK] module.apps encontrado no state. Pulando apply infra com enable_apps=false para evitar destroy."
  else
    tf_apply "infra" -var enable_apps=false
  fi

  configure_kubectl
  install_ingress
  wait_ingress_controller_service

  echo ""
  echo ">>> [3/7] Aplicando ArgoCD via helm com Terraform"
  tf_apply "argocd" -var enable_apps=true -var enable_argocd_apps=false

  echo ""
  echo ">>> Aguardando CRDs do ArgoCD..."
  for i in $(seq 1 30); do
    if "$KUBECTL_BIN" get crd applications.argoproj.io >/dev/null 2>&1; then
      echo "  [OK] CRDs prontas"
      break
    fi
    echo "  aguardando... ($i/30)"
    sleep 5
  done

  echo ">>> Aplicando Applications do ArgoCD via Terraform..."
  tf_apply "apps" -var enable_apps=true -var enable_argocd_apps=true
}

build_and_push_images() {
  echo ""
  echo ">>> [4/7] Build e push de imagens Docker..."

  ACCOUNT_ID=$("$AWS_BIN" sts get-caller-identity --query Account --output text)
  ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"
  GITHUB_REPO_URL=$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||')
  GITHUB_USER=$(echo "$GITHUB_REPO_URL" | sed 's|https://github.com/||' | cut -d/ -f1)

  echo "  ECR Registry: $ECR_REGISTRY"
  echo "  GitHub User:  $GITHUB_USER"
  echo "  GitHub Repo:  $GITHUB_REPO_URL"

  echo "  Atualizando arquivos yaml"
  for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
    DEPLOY_FILE="$PROJECT_DIR/gitops/$svc/deployment.yaml"
    if grep -q '<AWS_ACCOUNT_ID>' "$DEPLOY_FILE" 2>/dev/null; then
      sed -i.bak "s|<AWS_ACCOUNT_ID>|$ACCOUNT_ID|g" "$DEPLOY_FILE" && rm -f "$DEPLOY_FILE.bak"
      echo "    [OK] $svc deployment.yaml atualizado"
    fi
  done

  echo "Verificando acesso ao Docker"
  DOCKER_OK=true
  if [ ! -S /var/run/docker.sock ] || [ ! -r /var/run/docker.sock ] || [ ! -w /var/run/docker.sock ]; then
    DOCKER_OK=false
  fi

  if [ "$DOCKER_OK" = "false" ]; then
    echo "WARN: Sem acesso ao Docker (/var/run/docker.sock). Pulando build/push."
  else
    "$AWS_BIN" ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$ECR_REGISTRY"

    SKIP_BUILD=true
    for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
      IMAGE_COUNT=$("$AWS_BIN" ecr list-images --repository-name "$svc" --region us-east-1 --query 'length(imageIds)' --output text 2>/dev/null || echo "0")
      if [ "$IMAGE_COUNT" = "0" ] || [ "$IMAGE_COUNT" = "None" ]; then
        SKIP_BUILD=false
        break
      fi
    done

    if [ "$SKIP_BUILD" = "true" ]; then
      echo "  Imagens ja existem no ECR, pulando build."
    else
      echo "  Construindo e enviando imagens (isso pode levar 5-10 minutos)..."
      for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
        echo "  >>> Building $svc..."
        docker build --platform linux/amd64 -t "$ECR_REGISTRY/$svc:latest" "$PROJECT_DIR/microservices/$svc"
        docker push "$ECR_REGISTRY/$svc:latest"
        echo "  [OK] $svc"
      done
    fi
  fi
}

install_ingress() {
  echo ""
  echo ">>> [5/7] Instalando NGINX Ingress Controller..."
  "$KUBECTL_BIN" apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/aws/deploy.yaml 2>/dev/null || true
  echo "  [OK] NGINX Ingress instalado"
}

wait_ingress_controller_service() {
  echo ">>> Aguardando Service ingress-nginx-controller..."
  for i in $(seq 1 24); do
    if "$KUBECTL_BIN" get svc ingress-nginx-controller -n ingress-nginx >/dev/null 2>&1; then
      echo "  [OK] Service ingress-nginx-controller encontrado"
      return
    fi
    echo "  aguardando... ($i/24)"
    sleep 5
  done
  echo "WARN: Service ingress-nginx-controller nao encontrado; DNS pode falhar."
}
wait_pods_ready() {
  echo ""
  echo ">>> [6/7] Aguardando pods do ToggleMaster ficarem prontos..."
  echo "  (isso pode levar 2-5 minutos)"

  for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
    echo -n "  Aguardando $svc... "
    "$KUBECTL_BIN" rollout status deployment/$svc -n togglemaster --timeout=180s 2>/dev/null || echo "(pode demorar mais)"
  done

  echo ""
  "$KUBECTL_BIN" get pods -n togglemaster
}

generate_api_key() {
  echo ""
  echo ">>> [7/7] Gerando SERVICE_API_KEY..."
  echo "============================================"
  echo "  ToggleMaster - Gerar SERVICE_API_KEY"
  echo "============================================"
  echo ""

  echo ">>> Verificando se auth-service esta Running..."
  AUTH_STATUS=$("$KUBECTL_BIN" get pods -n togglemaster -l app=auth-service -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")

  if [ "$AUTH_STATUS" != "Running" ]; then
    echo "ERRO: auth-service nao esta Running (status: $AUTH_STATUS)"
    echo "Aguarde os pods subirem: kubectl get pods -n togglemaster -w"
    exit 1
  fi
  echo "  [OK] auth-service esta Running"
  echo ""

  if command -v lsof >/dev/null 2>&1; then
    if lsof -i :8001 > /dev/null 2>&1; then
      echo "  AVISO: Porta 8001 ja em uso. Tentando liberar..."
      kill $(lsof -t -i :8001) 2>/dev/null || true
      sleep 2
    fi
  else
    echo "  AVISO: lsof nao encontrado. Se a porta 8001 estiver em uso, o port-forward pode falhar."
  fi

  echo ">>> Abrindo port-forward para auth-service..."
  "$KUBECTL_BIN" port-forward svc/auth-service 8001:8001 -n togglemaster &
  PF_PID=$!
  sleep 3

  cleanup() {
    if [ -n "${PF_PID:-}" ]; then
      kill "$PF_PID" 2>/dev/null || true
    fi
  }
  trap cleanup EXIT

  echo ">>> Obtendo MASTER_KEY do secret..."
  MASTER_KEY=$("$KUBECTL_BIN" get secret auth-service-secret -n togglemaster \
    -o jsonpath='{.data.MASTER_KEY}' | base64 -d)

  if [ -z "$MASTER_KEY" ]; then
    echo "ERRO: MASTER_KEY nao encontrada no secret auth-service-secret"
    exit 1
  fi
  echo "  [OK] MASTER_KEY: ${MASTER_KEY:0:8}..."
  echo ""

  echo ">>> Gerando API key via auth-service..."
  RESPONSE=$(curl -s -X POST http://localhost:8001/admin/keys \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $MASTER_KEY" \
    -d '{"name": "evaluation-service"}')

  API_KEY=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null || echo "")

  if [ -z "$API_KEY" ]; then
    echo "ERRO: Nao foi possivel gerar a API key."
    echo "Resposta do auth-service: $RESPONSE"
    exit 1
  fi
  echo "  [OK] API Key gerada: ${API_KEY:0:15}..."
  echo ""

  echo ">>> Atualizando evaluation-service-secret com a nova API key..."
  API_KEY_B64=$(printf '%s' "$API_KEY" | base64 | tr -d '\n')

  "$KUBECTL_BIN" patch secret evaluation-service-secret -n togglemaster \
    -p "{\"data\":{\"SERVICE_API_KEY\":\"$API_KEY_B64\"}}"

  echo "  [OK] evaluation-service-secret atualizado"
  echo ""

  echo ">>> Reiniciando pods do evaluation-service..."
  "$KUBECTL_BIN" rollout restart deployment/evaluation-service -n togglemaster
  "$KUBECTL_BIN" rollout status deployment/evaluation-service -n togglemaster --timeout=120s
  echo ""

  echo "============================================"
  echo "  SERVICE_API_KEY configurada com sucesso!"
  echo "============================================"
  echo ""
  echo "API Key: $API_KEY"
  echo ""
  echo "Todos os servicos devem estar operacionais agora."
  echo "Verifique: kubectl get pods -n togglemaster"
  echo ""

  ARGOCD_URL=$("$KUBECTL_BIN" get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pendente")
  ARGOCD_PASS=$("$KUBECTL_BIN" -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "N/A")

  echo "ArgoCD:"
  echo "  URL:   https://$ARGOCD_URL"
  echo "  User:  admin"
  echo "  Pass:  $ARGOCD_PASS"
}

destroy_all() {
  log_info "Verificando credenciais AWS..."
  if ! aws sts get-caller-identity &>/dev/null; then
    log_error "Credenciais AWS invalidas. Configure as variaveis de ambiente"
    exit 1
  fi
  log_ok "Credenciais AWS validas"
  log_info "Verificando se cluster EKS '$CLUSTER_NAME' existe..."

  if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" &>/dev/null; then
    log_info "Cluster EKS encontrado. Atualizando kubeconfig..."
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" 2>/dev/null

    log_info "Buscando Services do tipo LoadBalancer..."
    LB_SERVICES=$(kubectl get svc --all-namespaces -o json 2>/dev/null | \
      python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    if item.get('spec', {}).get('type') == 'LoadBalancer':
        ns = item['metadata']['namespace']
        name = item['metadata']['name']
        print(f'{ns}/{name}')
" 2>/dev/null || true)

    if [ -n "$LB_SERVICES" ]; then
      log_warn "Encontrados Services LoadBalancer que bloqueiam o destroy:"
      echo "$LB_SERVICES"
      echo ""

      for svc in $LB_SERVICES; do
        NS=$(echo "$svc" | cut -d/ -f1)
        NAME=$(echo "$svc" | cut -d/ -f2)
        log_info "Deletando Service $NS/$NAME..."
        kubectl delete svc "$NAME" -n "$NS" --timeout=60s 2>/dev/null || true
      done

      log_info "Aguardando LoadBalancers serem removidos da AWS (ate 120s)..."
      for i in $(seq 1 24); do
        ELB_COUNT=$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions | length(@)' --output text 2>/dev/null || echo "0")
        NLB_COUNT=$(aws elbv2 describe-load-balancers --query 'LoadBalancers | length(@)' --output text 2>/dev/null || echo "0")
        TOTAL=$((ELB_COUNT + NLB_COUNT))
        if [ "$TOTAL" -eq 0 ]; then
          log_ok "Todos os LoadBalancers removidos"
          break
        fi
        echo "  Aguardando... ($TOTAL LBs restantes, tentativa $i/24)"
        sleep 5
      done
    else
      log_ok "Nenhum Service LoadBalancer encontrado"
    fi

    log_info "Deletando Ingress resources..."
    kubectl delete ingress --all --all-namespaces --timeout=60s 2>/dev/null || true

    log_info "Deletando namespaces customizados..."
    CUSTOM_NS=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | \
      grep -v -E '^(default|kube-system|kube-public|kube-node-lease|argocd)$' || true)
    for ns in $CUSTOM_NS; do
      log_info "Deletando namespace $ns..."
      kubectl delete ns "$ns" --timeout=120s 2>/dev/null || true
    done

    log_info "Deletando namespace argocd..."
    kubectl delete ns argocd --timeout=120s 2>/dev/null || true

    log_info "Aguardando 30s para ENIs serem liberadas..."
    sleep 30

  else
    log_warn "Cluster EKS '$CLUSTER_NAME' nao encontrado. Pulando limpeza K8s."
  fi

  log_info "Verificando LoadBalancers orfaos..."

  ELBS=$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions[*].LoadBalancerName' --output text 2>/dev/null || true)
  if [ -n "$ELBS" ]; then
    for elb in $ELBS; do
      log_warn "Deletando Classic ELB orfao: $elb"
      aws elb delete-load-balancer --load-balancer-name "$elb" 2>/dev/null || true
    done
  fi

  ELBV2_ARNS=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[*].LoadBalancerArn' --output text 2>/dev/null || true)
  if [ -n "$ELBV2_ARNS" ]; then
    for arn in $ELBV2_ARNS; do
      NAME=$(aws elbv2 describe-load-balancers --load-balancer-arns "$arn" --query 'LoadBalancers[0].LoadBalancerName' --output text 2>/dev/null)
      log_warn "Deletando ALB/NLB orfao: $NAME"
      LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn "$arn" --query 'Listeners[*].ListenerArn' --output text 2>/dev/null || true)
      for listener in $LISTENERS; do
        aws elbv2 delete-listener --listener-arn "$listener" 2>/dev/null || true
      done
      aws elbv2 delete-load-balancer --load-balancer-arn "$arn" 2>/dev/null || true
    done
    log_info "Aguardando 30s para LBs serem removidos..."
    sleep 30
  fi

  TG_ARNS=$(aws elbv2 describe-target-groups --query 'TargetGroups[*].TargetGroupArn' --output text 2>/dev/null || true)
  if [ -n "$TG_ARNS" ]; then
    for tg_arn in $TG_ARNS; do
      TG_NAME=$(aws elbv2 describe-target-groups --target-group-arns "$tg_arn" --query 'TargetGroups[0].TargetGroupName' --output text 2>/dev/null)
      log_warn "Deletando Target Group orfao: $TG_NAME"
      aws elbv2 delete-target-group --target-group-arn "$tg_arn" 2>/dev/null || true
    done
  fi

  log_ok "Limpeza de LoadBalancers concluida"

  log_info "Verificando VPC do projeto..."
  VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${PROJECT_NAME}-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)

  if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    log_info "VPC encontrada: $VPC_ID. Limpando ENIs orfas..."

    ENIS=$(aws ec2 describe-network-interfaces \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=available" \
      --query 'NetworkInterfaces[*].NetworkInterfaceId' --output text 2>/dev/null || true)

    if [ -n "$ENIS" ]; then
      for eni in $ENIS; do
        log_warn "Deletando ENI orfa: $eni"
        aws ec2 delete-network-interface --network-interface-id "$eni" 2>/dev/null || true
      done
    fi

    ENIS_INUSE=$(aws ec2 describe-network-interfaces \
      --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=in-use" \
      --query 'NetworkInterfaces[*].{Id:NetworkInterfaceId,Desc:Description,AttachId:Attachment.AttachmentId}' \
      --output json 2>/dev/null || echo "[]")

    ENI_COUNT=$(echo "$ENIS_INUSE" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    if [ "$ENI_COUNT" -gt 0 ]; then
      log_warn "Encontradas $ENI_COUNT ENIs in-use. Tentando desanexar e deletar..."
      echo "$ENIS_INUSE" | python3 -c "
import json, sys
enis = json.load(sys.stdin)
for eni in enis:
    eni_id = eni['Id']
    attach_id = eni.get('AttachId', '')
    desc = eni.get('Desc', '')
    print(f'{eni_id}|{attach_id}|{desc}')
" | while IFS='|' read -r eni_id attach_id desc; do
        if [ -n "$attach_id" ]; then
          log_info "  Desanexando ENI $eni_id ($desc)..."
          aws ec2 detach-network-interface --attachment-id "$attach_id" --force 2>/dev/null || true
          sleep 5
        fi
        log_info "  Deletando ENI $eni_id..."
        aws ec2 delete-network-interface --network-interface-id "$eni_id" 2>/dev/null || true
      done
    fi

    log_info "Limpando Security Groups customizados na VPC..."
    SG_IDS=$(aws ec2 describe-security-groups \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || true)

    if [ -n "$SG_IDS" ]; then
      for sg in $SG_IDS; do
        log_info "  Limpando regras do SG $sg..."
        aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$sg" \
          --query 'SecurityGroupRules[*].SecurityGroupRuleId' --output text 2>/dev/null | \
          tr '\t' '\n' | while read -r rule_id; do
            [ -n "$rule_id" ] && aws ec2 revoke-security-group-ingress --group-id "$sg" --security-group-rule-ids "$rule_id" 2>/dev/null || true
            [ -n "$rule_id" ] && aws ec2 revoke-security-group-egress --group-id "$sg" --security-group-rule-ids "$rule_id" 2>/dev/null || true
          done
        log_warn "  Deletando SG $sg..."
        aws ec2 delete-security-group --group-id "$sg" 2>/dev/null || true
      done
    fi

    log_ok "Limpeza de VPC concluida"
  else
    log_ok "VPC ${PROJECT_NAME}-vpc nao encontrada (ja deletada)"
  fi

  log_info "Verificando terraform state..."
  cd "$TERRAFORM_DIR"

  if ! terraform init -reconfigure -input=false >/dev/null 2>&1; then
    log_error "Falha ao inicializar o backend do Terraform. Verifique credenciais AWS."
    exit 1
  fi

  set +e
  STATE_LIST=$(terraform state list 2>/dev/null)
  STATE_EXIT=$?
  set -e

  if [ "$STATE_EXIT" -ne 0 ]; then
    log_error "Nao foi possivel ler o state remoto. Abortando para evitar destruicao incorreta."
    exit 1
  fi

  STATE_COUNT=$(echo "$STATE_LIST" | wc -l | tr -d ' ')
  if [ "$STATE_COUNT" -gt 0 ]; then
    log_info "Encontrados $STATE_COUNT recursos no terraform state. Executando destroy..."
    echo "$STATE_LIST"
    echo ""

    LOCK_ID=$(terraform plan -no-color -var enable_apps=true -var enable_argocd_apps=true 2>&1 | grep -oP 'ID:\s+\K[\w-]+' || true)
    if [ -n "$LOCK_ID" ]; then
      log_warn "State locked. Forcando unlock (ID: $LOCK_ID)..."
      printf 'yes\n' | terraform force-unlock "$LOCK_ID" 2>/dev/null || true
    fi

    terraform destroy -auto-approve -var enable_apps=true -var enable_argocd_apps=true 2>&1
    DESTROY_EXIT=$?

    if [ $DESTROY_EXIT -eq 0 ]; then
      log_ok "Terraform destroy concluido com sucesso!"
    else
      log_error "Terraform destroy falhou (exit code: $DESTROY_EXIT)"
      log_info "Tentando remover recursos restantes do state..."
      for resource in $(terraform state list 2>/dev/null); do
        log_warn "  Removendo $resource do state..."
        terraform state rm "$resource" 2>/dev/null || true
      done
    fi
  else
    log_ok "Terraform state vazio - nada para destruir"
  fi

  echo ""
  echo "========================================="
  log_info "VERIFICACAO FINAL"
  echo "========================================="

  sanitize_count() {
    local v="$1"
    if [ -z "$v" ] || [ "$v" = "None" ]; then
      echo "0"
    else
      echo "$v"
    fi
  }

  VPC_COUNT=$(sanitize_count "$(aws ec2 describe-vpcs --filters "Name=is-default,Values=false" --query 'Vpcs | length(@)' --output text 2>/dev/null)")
  EKS_COUNT=$(sanitize_count "$(aws eks list-clusters --query 'clusters | length(@)' --output text 2>/dev/null)")
  RDS_COUNT=$(sanitize_count "$(aws rds describe-db-instances --query 'DBInstances | length(@)' --output text 2>/dev/null)")
  EC_COUNT=$(sanitize_count "$(aws elasticache describe-cache-clusters --query 'CacheClusters | length(@)' --output text 2>/dev/null)")
  ECR_COUNT=$(sanitize_count "$(aws ecr describe-repositories --query 'repositories | length(@)' --output text 2>/dev/null)")
  ELB_COUNT=$(sanitize_count "$(aws elb describe-load-balancers --query 'LoadBalancerDescriptions | length(@)' --output text 2>/dev/null)")
  ELBV2_COUNT=$(sanitize_count "$(aws elbv2 describe-load-balancers --query 'LoadBalancers | length(@)' --output text 2>/dev/null)")
  NAT_COUNT=$(sanitize_count "$(aws ec2 describe-nat-gateways --filter "Name=state,Values=available,pending" --query 'NatGateways | length(@)' --output text 2>/dev/null)")
  EIP_COUNT=$(sanitize_count "$(aws ec2 describe-addresses --query 'Addresses | length(@)' --output text 2>/dev/null)")

  MISSING=0
  SUMMARY=()

  if [ "$VPC_COUNT" -gt 0 ]; then SUMMARY+=("VPCs nao-default: $VPC_COUNT"); MISSING=1; fi
  if [ "$EKS_COUNT" -gt 0 ]; then SUMMARY+=("EKS clusters: $EKS_COUNT"); MISSING=1; fi
  if [ "$RDS_COUNT" -gt 0 ]; then SUMMARY+=("RDS instances: $RDS_COUNT"); MISSING=1; fi
  if [ "$EC_COUNT" -gt 0 ]; then SUMMARY+=("ElastiCache clusters: $EC_COUNT"); MISSING=1; fi
  if [ "$ECR_COUNT" -gt 0 ]; then SUMMARY+=("ECR repositories: $ECR_COUNT"); MISSING=1; fi
  if [ "$ELB_COUNT" -gt 0 ]; then SUMMARY+=("Load Balancers (classic): $ELB_COUNT"); MISSING=1; fi
  if [ "$ELBV2_COUNT" -gt 0 ]; then SUMMARY+=("Load Balancers (v2): $ELBV2_COUNT"); MISSING=1; fi
  if [ "$NAT_COUNT" -gt 0 ]; then SUMMARY+=("NAT Gateways: $NAT_COUNT"); MISSING=1; fi
  if [ "$EIP_COUNT" -gt 0 ]; then SUMMARY+=("Elastic IPs: $EIP_COUNT"); MISSING=1; fi

  if [ "$MISSING" -eq 0 ]; then
    echo "Tudo removido"
  else
    for item in "${SUMMARY[@]}"; do
      echo "$item"
    done
  fi

  echo ""
}

if [ "$ACTION" = "destroy-all" ]; then
  if [ -f "$TFVARS_FILE" ]; then
    CLUSTER_NAME=$(grep -m1 '^cluster_name' "$TFVARS_FILE" | python3 -c "import sys; print(sys.stdin.read().split('\"')[1])")
    PROJECT_NAME=$(grep -m1 '^project_name' "$TFVARS_FILE" | python3 -c "import sys; print(sys.stdin.read().split('\"')[1])")
  else
    CLUSTER_NAME=""
    PROJECT_NAME=""
  fi
  CLUSTER_NAME="${CLUSTER_NAME:-togglemaster-cluster}"
  PROJECT_NAME="${PROJECT_NAME:-togglemaster}"

  destroy_all
  exit 0
fi

if [ "$ACTION" = "gen-api-key" ]; then
  preflight_setup
  configure_kubectl
  generate_api_key
  exit 0
fi

preflight_setup
ensure_backend

cd "$TERRAFORM_DIR"

if [ "$ACTION" = "plan" ]; then
  terraform_plan_flow
  exit 0
fi

if [ "$ACTION" = "apply" ]; then
  terraform_apply_flow
  exit 0
fi

terraform_apply_flow
cd "$PROJECT_DIR"

build_and_push_images
wait_pods_ready
generate_api_key
