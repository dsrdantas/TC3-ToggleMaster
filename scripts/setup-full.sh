#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================"
echo "  ToggleMaster - terraform+secrets+argocd+applications"
echo "============================================"
echo ""
echo ">>> [0/7] Validacao pre-requisitos e setup de ferramentas..."

# Dependencias (sem root)
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

# Terraform
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

# AWS CLI (instalar local se ausente ou muito antigo)
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


# kubectl (usar versao compatível quando aws cli antigo)
KUBECTL_TARGET_VER="${KUBECTL_TARGET_VER:-}"
if [ -z "$KUBECTL_TARGET_VER" ]; then
  # AWS CLI antigo gera v1alpha1, então usamos kubectl mais antigo
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
  # força instalar a versao compatível no local para usar no script
  echo ">>> Instalando kubectl compatível em $LOCAL_BIN..."
  curl -fsSL "https://dl.k8s.io/release/${KUBECTL_TARGET_VER}/bin/linux/amd64/kubectl" -o "$LOCAL_BIN/kubectl"
  chmod +x "$LOCAL_BIN/kubectl"
fi

# helm
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

# Preferir binarios locais se existirem
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

# git e docker (nao instalados aqui)
if ! command -v git >/dev/null 2>&1; then
  echo "ERRO: git nao encontrado. Instale git antes de continuar." >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "ERRO: docker nao encontrado. Instale docker antes de continuar." >&2
  exit 1
fi

# AWS credentials (suporta env vars OU aws configure)
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

# Passar credenciais para o Terraform (secrets no cluster)
export TF_VAR_aws_access_key_id="${TF_VAR_aws_access_key_id:-$AWS_ACCESS_KEY_ID}"
export TF_VAR_aws_secret_access_key="${TF_VAR_aws_secret_access_key:-$AWS_SECRET_ACCESS_KEY}"
export TF_VAR_aws_session_token="${TF_VAR_aws_session_token:-$AWS_SESSION_TOKEN}"

# Garantir enable_apps=true para evitar destroy acidental do module.apps
export TF_VAR_enable_apps="${TF_VAR_enable_apps:-true}"

TFVARS_FILE="$PROJECT_DIR/terraform/terraform.tfvars"
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

echo ">>> [1/7] Terraform (backend + plan + apply)..."

TERRAFORM_DIR="$PROJECT_DIR/terraform"
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

# Se module.apps ja existe no state, nao rodar apply com enable_apps=false
if terraform state list 2>/dev/null | grep -q '^module.apps\\.'; then
  echo "  [OK] module.apps encontrado no state. Pulando apply infra com enable_apps=false para evitar destroy."
else
  set +e
  terraform plan -detailed-exitcode -var enable_apps=false "${TF_EXTRA_VARS[@]}"
  PLAN_EXIT=$?
  set -e
  if [ "$PLAN_EXIT" -eq 0 ]; then
    echo "  [OK] Nenhuma mudanca na infraestrutura. Pulando apply."
  elif [ "$PLAN_EXIT" -eq 2 ]; then
    terraform apply -auto-approve -var enable_apps=false "${TF_EXTRA_VARS[@]}"
  else
    echo "ERRO: terraform plan falhou (exit $PLAN_EXIT)" >&2
    exit "$PLAN_EXIT"
  fi
fi
cd "$PROJECT_DIR"

echo ""

echo ">>> [2/7] Configurando kubectl"

CLUSTER_NAME=$(grep -m1 '^cluster_name' "$TERRAFORM_DIR/terraform.tfvars" | python3 -c "import sys; print(sys.stdin.read().split('\"')[1])")
if [ -z "$CLUSTER_NAME" ]; then
  CLUSTER_NAME="dsrdantas-cluster"
fi

if ! "$KUBECTL_BIN" cluster-info > /dev/null 2>&1; then
  echo ">>> kubectl nao conectado. Configurando..."
  "$AWS_BIN" eks update-kubeconfig --name "$CLUSTER_NAME" --region us-east-1
  # Ajuste de compatibilidade + forcar uso do aws local no kubeconfig
  python3 - <<PY 2>/dev/null || true
import os, re
path = os.path.expanduser("~/.kube/config")
cluster = os.environ.get("CLUSTER_NAME", "togglemaster-cluster")
region = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
try:
    with open(path, "r", encoding="utf-8") as f:
        data = f.read()
    # troca apiVersion antigo
    data = data.replace("client.authentication.k8s.io/v1alpha1", "client.authentication.k8s.io/v1beta1")

    # força exec command a usar /bin/bash com aws get-token (evita v1alpha1)
    def repl(match):
        indent = match.group(1)
        cmd = f"{indent}command: /bin/bash\n"
        args = (
            f\"{indent}args:\\n\"
            f\"{indent}- -lc\\n\"
            f\"{indent}- aws eks get-token --cluster-name {cluster} --region {region} | sed 's/v1alpha1/v1beta1/g'\\n\"
        )
        return f\"{indent}exec:\\n{indent}  apiVersion: client.authentication.k8s.io/v1beta1\\n{cmd}{args}\"

    data = re.sub(
        r\"(\\s*)exec:\\n(?:\\s*apiVersion:.*\\n)?(?:\\s*command:.*\\n)?(?:\\s*args:\\n(?:\\s*- .*\\n)*)\",
        repl,
        data,
        flags=re.MULTILINE,
    )

    with open(path, "w", encoding="utf-8") as f:
        f.write(data)
except FileNotFoundError:
    pass
PY
fi

"$KUBECTL_BIN" get nodes
echo ""
echo ">>> [3/7] Aplicando ArgoCD via helm com Terraform"
cd "$TERRAFORM_DIR"
set +e
terraform plan -detailed-exitcode -var enable_apps=true -var enable_argocd_apps=false "${TF_EXTRA_VARS[@]}"
PLAN_APPS_EXIT=$?
set -e
if [ "$PLAN_APPS_EXIT" -eq 0 ]; then
  echo "  [OK] Nenhuma mudanca (argocd). Pulando apply."
elif [ "$PLAN_APPS_EXIT" -eq 2 ]; then
  terraform apply -auto-approve -var enable_apps=true -var enable_argocd_apps=false "${TF_EXTRA_VARS[@]}"
else
  echo "ERRO: terraform plan (argocd) falhou (exit $PLAN_APPS_EXIT)" >&2
  exit "$PLAN_APPS_EXIT"
fi
cd "$PROJECT_DIR"
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
cd "$TERRAFORM_DIR"
set +e
terraform plan -detailed-exitcode -var enable_apps=true -var enable_argocd_apps=true "${TF_EXTRA_VARS[@]}"
PLAN_ARGO_APPS_EXIT=$?
set -e
if [ "$PLAN_ARGO_APPS_EXIT" -eq 0 ]; then
  echo "  [OK] Nenhuma mudanca (apps). Pulando apply."
elif [ "$PLAN_ARGO_APPS_EXIT" -eq 2 ]; then
  terraform apply -auto-approve -var enable_apps=true -var enable_argocd_apps=true "${TF_EXTRA_VARS[@]}"
else
  echo "ERRO: terraform plan (apps) falhou (exit $PLAN_ARGO_APPS_EXIT)" >&2
  exit "$PLAN_ARGO_APPS_EXIT"
fi
cd "$PROJECT_DIR"
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
  # Login no ECR
  "$AWS_BIN" ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$ECR_REGISTRY"

  # Verificar se imagens ja existem no ECR
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
echo ""
echo ">>> [5/7] Instalando NGINX Ingress Controller..."
"$KUBECTL_BIN" apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/aws/deploy.yaml 2>/dev/null || true
echo "  [OK] NGINX Ingress instalado"
echo ""
echo ">>> [6/7] Aguardando pods do ToggleMaster ficarem prontos..."
echo "  (isso pode levar 2-5 minutos)"

# Aguardar deployments
for svc in auth-service flag-service targeting-service evaluation-service analytics-service; do
  echo -n "  Aguardando $svc... "
  "$KUBECTL_BIN" rollout status deployment/$svc -n togglemaster --timeout=180s 2>/dev/null || echo "(pode demorar mais)"
done

echo ""
"$KUBECTL_BIN" get pods -n togglemaster
echo ""
echo ">>> [7/7] Gerando SERVICE_API_KEY..."
"$SCRIPT_DIR/generate-api-key.sh"

ARGOCD_URL=$("$KUBECTL_BIN" get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pendente")
ARGOCD_PASS=$("$KUBECTL_BIN" -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "N/A")

echo "ArgoCD:"
echo "  URL:   https://$ARGOCD_URL"
echo "  User:  admin"
echo "  Pass:  $ARGOCD_PASS"