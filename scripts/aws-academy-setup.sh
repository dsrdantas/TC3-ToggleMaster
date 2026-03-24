#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AWS_PROFILE:-default}"
ENV_FILE="${AWS_ENV:-./aws_env}"
REGION_DEFAULT="${AWS_DEFAULT_REGION:-us-east-1}"
PRINT_ONLY=false
NO_PROMPT=false
ACCESS_KEY_ID_ARG=""
SECRET_ACCESS_KEY_ARG=""
SESSION_TOKEN_ARG=""
REGION_ARG=""

usage() {
  cat <<USAGE
Uso:
  ./scripts/aws-academy-setup.sh [--profile default] [--env ./aws_env]
  ./scripts/aws-academy-setup.sh <ACCESS_KEY_ID> <SECRET_ACCESS_KEY> <SESSION_TOKEN> [REGION]
  ./scripts/aws-academy-setup.sh --access-key ... --secret-key ... --session-token ... [--region us-east-1]

Regras:
  - Nao modifica ~/.aws/config nem ~/.aws/credentials
  - Le regiao de ~/.aws/config (se existir) e grava no arquivo AWS_ENV
  - Se ~/.aws/credentials ja tiver Access/Secret, apenas valida o token
  - --print: imprime exports no stdout (nao grava arquivo)
  - --no-prompt: nao pergunta credenciais (falha se faltarem)
USAGE
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"; shift 2 ;;
    --env)
      ENV_FILE="$2"; shift 2 ;;
    --print)
      PRINT_ONLY=true; shift ;;
    --no-prompt)
      NO_PROMPT=true; shift ;;
    --access-key)
      ACCESS_KEY_ID_ARG="$2"; shift 2 ;;
    --secret-key)
      SECRET_ACCESS_KEY_ARG="$2"; shift 2 ;;
    --session-token)
      SESSION_TOKEN_ARG="$2"; shift 2 ;;
    --region)
      REGION_ARG="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

if [[ ${#POSITIONAL[@]} -gt 0 ]]; then
  ACCESS_KEY_ID_ARG="${POSITIONAL[0]:-}"
  SECRET_ACCESS_KEY_ARG="${POSITIONAL[1]:-}"
  SESSION_TOKEN_ARG="${POSITIONAL[2]:-}"
  REGION_ARG="${POSITIONAL[3]:-}"
fi

if [[ "$PRINT_ONLY" = "false" ]]; then
  mkdir -p "$(dirname "$ENV_FILE")"
fi

read_region() {
  local r
  r="$(aws configure get region --profile "$PROFILE" 2>/dev/null || true)"
  if [[ -z "$r" ]]; then
    r="$REGION_DEFAULT"
  fi
  echo "$r"
}

read_creds_from_file() {
  local ak sk st
  ak="$(aws configure get aws_access_key_id --profile "$PROFILE" 2>/dev/null || true)"
  sk="$(aws configure get aws_secret_access_key --profile "$PROFILE" 2>/dev/null || true)"
  st="$(aws configure get aws_session_token --profile "$PROFILE" 2>/dev/null || true)"
  echo "$ak|$sk|$st"
}

prompt_creds_full() {
  local access_key secret_key session_token
  read -r -p "AWS Access Key ID: " access_key
  read -r -p "AWS Secret Access Key: " secret_key
  read -r -p "AWS Session Token: " session_token

  if [[ -z "$access_key" || -z "$secret_key" || -z "$session_token" ]]; then
    echo "Erro: credenciais incompletas." >&2
    exit 1
  fi

  echo "$access_key|$secret_key|$session_token"
}

prompt_token_only() {
  local session_token
  read -r -p "AWS Session Token (renovar): " session_token
  if [[ -z "$session_token" ]]; then
    echo "Erro: token vazio." >&2
    exit 1
  fi
  echo "$session_token"
}

validate_creds() {
  local ak="$1" sk="$2" st="$3" region="$4"
  AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" AWS_SESSION_TOKEN="$st" AWS_DEFAULT_REGION="$region" \
    aws sts get-caller-identity >/dev/null 2>&1
}

REGION="${REGION_ARG:-$(read_region)}"
ACCESS_KEY_ID="${ACCESS_KEY_ID_ARG:-}"
SECRET_ACCESS_KEY="${SECRET_ACCESS_KEY_ARG:-}"
SESSION_TOKEN="${SESSION_TOKEN_ARG:-}"

if [[ -z "$ACCESS_KEY_ID" || -z "$SECRET_ACCESS_KEY" ]]; then
  IFS="|" read -r ACCESS_KEY_ID SECRET_ACCESS_KEY SESSION_TOKEN < <(read_creds_from_file)
fi

if [[ -n "$ACCESS_KEY_ID" && -n "$SECRET_ACCESS_KEY" ]]; then
  if validate_creds "$ACCESS_KEY_ID" "$SECRET_ACCESS_KEY" "$SESSION_TOKEN" "$REGION"; then
    echo "Credenciais validas encontradas para o profile '$PROFILE'."
  else
    echo "Token expirado para o profile '$PROFILE'. Informe um novo token."
    if [[ "$NO_PROMPT" = "true" ]]; then
      echo "Erro: token expirado e --no-prompt habilitado." >&2
      exit 1
    fi
    SESSION_TOKEN="$(prompt_token_only)"
    if ! validate_creds "$ACCESS_KEY_ID" "$SECRET_ACCESS_KEY" "$SESSION_TOKEN" "$REGION"; then
      echo "Erro: token invalido." >&2
      exit 1
    fi
  fi
else
  echo "Credenciais nao encontradas em ~/.aws/credentials. Informe novas credenciais AWS Academy."
  if [[ "$NO_PROMPT" = "true" ]]; then
    echo "Erro: credenciais ausentes e --no-prompt habilitado." >&2
    exit 1
  fi
  IFS="|" read -r ACCESS_KEY_ID SECRET_ACCESS_KEY SESSION_TOKEN < <(prompt_creds_full)
  if ! validate_creds "$ACCESS_KEY_ID" "$SECRET_ACCESS_KEY" "$SESSION_TOKEN" "$REGION"; then
    echo "Erro: credenciais invalidas (verifique Access Key/Secret/Token)." >&2
    exit 1
  fi
fi

if [[ "$PRINT_ONLY" = "true" ]]; then
  cat <<EOT
export AWS_PROFILE="${PROFILE}"
export AWS_ACCESS_KEY_ID="${ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${SECRET_ACCESS_KEY}"
export AWS_SESSION_TOKEN="${SESSION_TOKEN}"
export AWS_DEFAULT_REGION="${REGION}"
EOT
else
  cat > "$ENV_FILE" <<EOT
export AWS_PROFILE="${PROFILE}"
export AWS_ACCESS_KEY_ID="${ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${SECRET_ACCESS_KEY}"
export AWS_SESSION_TOKEN="${SESSION_TOKEN}"
export AWS_DEFAULT_REGION="${REGION}"
EOT

  cat "$ENV_FILE"
fi
