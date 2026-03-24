# ToggleMaster - Tech Challenge Fase 3

Plataforma de Feature Flags com 5 microsservicos, infraestrutura automatizada via Terraform, CI/CD com DevSecOps (GitHub Actions) e GitOps (ArgoCD).

**Repositorio:** [github.com/dsrdantas/TC3-ToggleMaster](https://github.com/dsrdantas/TC3-ToggleMaster)

> **Nota:** Os manifestos em `gitops/` e `argocd/` usam placeholders (`<AWS_ACCOUNT_ID>`, `<GITHUB_USER>`) que sao substituidos automaticamente pelo script `setup-full.sh` durante o setup.

---

## Estrutura do Projeto

```
TC3-ToggleMaster/
├── terraform/              # IaC - Infraestrutura AWS (VPC, EKS, RDS, Redis, SQS, DynamoDB, ECR)
│   ├── main.tf             # Orquestracao dos modulos
│   ├── backend.tf          # Backend remoto S3 + DynamoDB lock
│   ├── variables.tf        # Variaveis do projeto
│   ├── outputs.tf          # Outputs dos recursos criados
│   ├── providers.tf        # Provider AWS
│   ├── terraform.tfvars          # Variaveis do projeto
│   ├── terraform.tfvars.example  # Exemplo de variaveis
│   └── modules/
│       ├── networking/     # VPC, Subnets, IGW, NAT, Route Tables, Security Groups
│       ├── eks/            # Cluster EKS + Node Group (com LabRole)
│       ├── databases/      # 3x RDS PostgreSQL + Redis + DynamoDB
│       ├── messaging/      # Fila SQS
│       ├── ecr/            # 5 repositorios ECR
│       └── apps/           # ArgoCD + Secrets + Applications (GitOps)
├── microservices/          # Codigo fonte dos 5 microsservicos
│   ├── auth-service/       # Go 1.21 - Gerenciamento de API keys (porta 8001)
│   ├── flag-service/       # Python 3.12 - CRUD de feature flags (porta 8002)
│   ├── targeting-service/  # Python 3.12 - Regras de segmentacao (porta 8003)
│   ├── evaluation-service/ # Go 1.21 - Avaliacao de flags em tempo real (porta 8004)
│   └── analytics-service/  # Python 3.12 - Analytics via SQS/DynamoDB (porta 8005)
├── gitops/                 # Manifestos Kubernetes monitorados pelo ArgoCD
│   ├── namespace.yaml      # Namespace togglemaster
│   ├── ingress.yaml        # NGINX Ingress rules
│   ├── auth-service/       # Deployment, Service, DB init (Job + ConfigMap + Secret)
│   ├── flag-service/       # Deployment, Service, DB init
│   ├── targeting-service/  # Deployment, Service, DB init
│   ├── evaluation-service/ # Deployment, Service, HPA
│   └── analytics-service/  # Deployment, Service
├── argocd/                 # Configuracao do ArgoCD (referencia)
│   └── applications.yaml   # AppProject + 6 Applications (referencia)
├── .github/workflows/      # Pipelines CI/CD com DevSecOps
│   ├── auth-service.yaml
│   ├── flag-service.yaml
│   ├── targeting-service.yaml
│   ├── evaluation-service.yaml
│   └── analytics-service.yaml
├── scripts/                # Scripts de automacao
│   ├── setup-full.sh       # Setup completo (orquestra tudo)
│   ├── destroy-all.sh      # Destruir tudo criado via Terraform
│   ├── aws-academy-setup.sh# Configura/valida credenciais AWS Academy
│   ├── generate-api-key.sh # Gera SERVICE_API_KEY via auth-service
│   └── generate-report-pdf.py  # Gera relatorio de entrega em PDF
└── .gitignore              # Arquivos ignorados
```

---

## Pre-requisitos

| Ferramenta | Versao Minima | Finalidade |
|------------|--------------|------------|
| AWS CLI | v2 | Acesso a AWS |
| Terraform | >= 1.5 | Provisionamento de infra |
| kubectl | >= 1.23 | Gerenciamento do cluster (AWS CLI antigo exige versão compatível) |
| Docker | >= 24 | Build de imagens |
| Git | >= 2.0 | Versionamento |

**AWS Academy:** Sessao ativa com credenciais temporarias (4h de duracao). O `setup-full.sh` foi desenhado para rodar dentro do shell do AWS Academy e valida credenciais, alem de ajustar ferramentas sem root.

---

## Guia Rapido - Subir o Ambiente do Zero

### Passo 1: Configurar credenciais AWS (AWS Academy)

**Opcao A — Variaveis de ambiente:**
```bash
export AWS_ACCESS_KEY_ID="<seu-access-key>"
export AWS_SECRET_ACCESS_KEY="<seu-secret-key>"
export AWS_SESSION_TOKEN="<seu-session-token>"
export AWS_DEFAULT_REGION="us-east-1"
```

**Opcao B — Via `aws configure`:**
```bash
aws configure
# Informar: Access Key, Secret Key, Region (us-east-1), Output (json)
aws configure set aws_session_token "<seu-session-token>"
```

Verificar:
```bash
aws sts get-caller-identity
```

### Passo 2: Ajustar `terraform/terraform.tfvars`

Edite o arquivo com suas variáveis (ex.: `lab_role_arn`, `db_password`, `cluster_name`).

### Passo 3: Setup automatizado (Terraform + ArgoCD + Secrets + Deploy)

Opcao A — **Setup completo automatizado** (recomendado):
```bash
./scripts/setup-full.sh
```
Este script executa os passos principais: valida ferramentas, aplica Terraform (infra + ArgoCD + apps), configura kubectl, cria secrets via Terraform, atualiza placeholders, faz build/push (se tiver acesso ao Docker), instala NGINX Ingress e gera a SERVICE_API_KEY.  
Ele foi pensado para ser executado diretamente no shell do AWS Academy.

> **Nota:** O build/push pode ser pulado — o script detecta se as imagens ja existem no ECR e faz o build automaticamente se necessario.

Opcao B — **Terraform plan/apply manual (avancado)**:
```bash
# Terraform (infra + ArgoCD + secrets)
cd terraform
terraform init -reconfigure
terraform plan -var enable_apps=true -var enable_argocd_apps=true
terraform apply -auto-approve -var enable_apps=true -var enable_argocd_apps=true
 
# Instalar NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/aws/deploy.yaml

# Aguardar pods e gerar API key
kubectl get pods -n togglemaster -w
./scripts/generate-api-key.sh
```

> **Nota:** Os secrets Kubernetes são gerenciados pelo Terraform (módulo `apps`), não há arquivos `secret.yaml` no git.

### Passo 4: Verificar tudo rodando

```bash
# Todos os pods devem estar Running (10 pods + 3 jobs Completed)
kubectl get pods -n togglemaster

# Verificar health dos servicos
kubectl port-forward svc/auth-service 8001:8001 -n togglemaster &
curl http://localhost:8001/health

# Acessar ArgoCD
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo
```

### Passo 5: Configurar GitHub Secrets para CI/CD

No GitHub: Settings > Secrets and variables > Actions:

| Secret | Valor |
|--------|-------|
| `AWS_ACCESS_KEY_ID` | Access Key da sessao |
| `AWS_SECRET_ACCESS_KEY` | Secret Key |
| `AWS_SESSION_TOKEN` | Session Token |
| `ECR_REGISTRY` | `<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com` |

> **IMPORTANTE:** Atualizar `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN` a cada nova sessao AWS Academy.

---

## Pipeline CI/CD (DevSecOps)

Cada microsservico tem seu proprio workflow que dispara em push/PR na main:

```
Push (microservices/<service>/**)
  │
  ├── 1. Build & Unit Test
  │     Go: go build + go test
  │     Python: pip install + pytest
  │
  ├── 2. Linter / Static Analysis
  │     Go: golangci-lint v1.61
  │     Python: flake8
  │
  ├── 3. Security Scan (SAST & SCA)
  │     SCA: Trivy filesystem scan (CRITICAL + HIGH)
  │     SAST: gosec v2.20.0 (Go) / bandit (Python)
  │
  ├── 4. Docker Build & Push to ECR
  │     Build imagem → Trivy container scan → Push ECR (tag: <commit-sha>)
  │
  └── 5. Update GitOps Manifests
        Atualiza image tag em gitops/<service>/deployment.yaml
        Commit automatico via github-actions[bot]
```

---

## GitOps com ArgoCD

O ArgoCD monitora a pasta `gitops/` e sincroniza automaticamente:

| Application | Path | Descricao |
|-------------|------|-----------|
| auth-service | `gitops/auth-service` | Deployment + Service + DB init (Job/ConfigMap/Secret) |
| flag-service | `gitops/flag-service` | Deployment + Service + DB init |
| targeting-service | `gitops/targeting-service` | Deployment + Service + DB init |
| evaluation-service | `gitops/evaluation-service` | Deployment + Service + HPA |
| analytics-service | `gitops/analytics-service` | Deployment + Service |
| togglemaster-shared | `gitops/` | Namespace + Ingress |

**Sync Policy:** Automatico com `prune: true` e `selfHeal: true`.

---

## Variaveis de Ambiente por Servico

### auth-service
- `DATABASE_URL` - Connection string PostgreSQL
- `MASTER_KEY` - Chave mestra para criar API keys
- `PORT` - Porta (default: 8001)

### flag-service
- `DATABASE_URL` - Connection string PostgreSQL
- `AUTH_SERVICE_URL` - URL do auth-service para validacao
- `PORT` - Porta (default: 8002)

### targeting-service
- `DATABASE_URL` - Connection string PostgreSQL
- `AUTH_SERVICE_URL` - URL do auth-service
- `PORT` - Porta (default: 8003)

### evaluation-service
- `REDIS_ADDR` - Endpoint do Redis
- `FLAG_SERVICE_URL` - URL do flag-service
- `TARGETING_SERVICE_URL` - URL do targeting-service
- `SQS_QUEUE_URL` - URL da fila SQS
- `SERVICE_API_KEY` - API key gerada pelo auth-service
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` - Credenciais AWS
- `PORT` - Porta (default: 8004)

### analytics-service
- `SQS_QUEUE_URL` - URL da fila SQS
- `DYNAMODB_TABLE` - Nome da tabela DynamoDB
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` - Credenciais AWS
- `AWS_DEFAULT_REGION` - Regiao AWS
- `PORT` - Porta (default: 8005)

---

## Destruir o Ambiente

```bash
# Destruir tudo criado via Terraform (EKS, RDS, Redis, VPC, etc.)
./scripts/destroy-all.sh
```

---
