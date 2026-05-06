# devops-pfe-infra

Infrastructure AWS pour le déploiement de l'API TaskManager (Spring Boot), provisionnée avec Terraform et déployée sur EKS.

## Architecture

- VPC avec subnets publics/privés sur 2 zones (eu-west-3a, eu-west-3b)
- EKS 1.30 avec node group t3.small (2 nœuds par défaut)
- RDS PostgreSQL 16 en subnet privé
- ALB créé automatiquement via l'Ingress Kubernetes (AWS Load Balancer Controller)
- Prometheus + Grafana déployés dans le namespace `monitoring`

## Structure

```text
devops-pfe-infra/
├── infra/terraform/
│   ├── main.tf
│   ├── vars.tf
│   ├── backend.tf
│   └── modules/
│       ├── vpc/
│       ├── eks-cluster/
│       ├── eks-nodegroup/
│       └── rds/
├── k8s/
│   ├── 00-namespace-configmap.yml
│   ├── 01-secret.yml          # ne pas appliquer manuellement, géré par Terraform
│   ├── 02-deployment.yml
│   └── 03-service-ingress-hpa.yml
├── helm/taskmanager/
└── .github/workflows/
    ├── ci-cd.yml
    └── terraform-pr.yml
```

## Démarrage rapide

### Prérequis

- AWS CLI configuré
- Terraform >= 1.10
- kubectl + helm

### 1. Initialiser le backend S3

```bash
chmod +x scripts/terraform-init.sh
./scripts/terraform-init.sh
```

### 2. Configurer les variables

```bash
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
# remplir db_password, ghcr_username, ghcr_token, grafana_admin_password
```

### 3. Déployer

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

### 4. Configurer kubectl

```bash
terraform output configure_kubectl
# copier-coller la commande retournée
```

### 5. Déployer l'application

```bash
./scripts/deploy.sh dev latest
```

## Secrets GitHub à configurer

| Secret | Description |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | Clé IAM pour le CI/CD |
| `AWS_SECRET_ACCESS_KEY` | Secret IAM |
| `DB_PASSWORD` | Mot de passe PostgreSQL |
| `GHCR_USERNAME` | Username GitHub |
| `GHCR_TOKEN` | PAT GitHub (scope: read:packages) |
| `GRAFANA_ADMIN_PASSWORD` | Mot de passe Grafana |

## Coût estimé (eu-west-3)

EKS ~73€ + 2x t3.small ~30€ + RDS ~40€ + NAT Gateways ~65€ = ~210€/mois

En dev, passer `environment=dev` pour désactiver le Multi-AZ et réduire les coûts.
