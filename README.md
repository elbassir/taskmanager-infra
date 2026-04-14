# 🏗️ Infrastructure DevOps — TaskManager PFE

Infrastructure complète AWS pour le déploiement de l'API TaskManager,
construite avec Terraform et déployée sur Amazon EKS.

---

## 🏛️ Architecture

```
                        ┌─────────────────────────────────────────────────┐
                        │              AWS — eu-west-3 (Paris)            │
                        │                                                  │
                        │  ┌──────────────────────────────────────────┐   │
                        │  │               VPC 10.0.0.0/16            │   │
                        │  │                                          │   │
                        │  │  Public Subnets (AZ-a / AZ-b)           │   │
                        │  │  ┌─────────────┐  ┌─────────────┐       │   │
Internet ──────────────►│  │  │ NAT Gateway │  │ NAT Gateway │       │   │
         (ALB Ingress)  │  │  └──────┬──────┘  └──────┬──────┘       │   │
                        │  │         │                 │              │   │
                        │  │  Private Subnets (AZ-a / AZ-b)          │   │
                        │  │  ┌──────▼──────────────────▼───────┐    │   │
                        │  │  │    EKS Node Group (t3.medium)    │    │   │
                        │  │  │  ┌─────────┐  ┌─────────┐       │    │   │
                        │  │  │  │  Pod TM │  │  Pod TM │  ...  │    │   │
                        │  │  │  └─────────┘  └─────────┘       │    │   │
                        │  │  └──────────────────────────────────┘    │   │
                        │  │                                          │   │
                        │  │  ┌──────────────────────────────────┐    │   │
                        │  │  │  RDS PostgreSQL (Multi-AZ)       │    │   │
                        │  │  │  Primary ──► Replica (read)      │    │   │
                        │  │  └──────────────────────────────────┘    │   │
                        │  └──────────────────────────────────────────┘   │
                        └─────────────────────────────────────────────────┘
```

## 📁 Structure du projet

```
devops-pfe-infra/
├── infra/terraform/
│   ├── main.tf                  # Orchestration des modules
│   ├── vars.tf                  # Variables
│   ├── outputs.tf               # Sorties
│   ├── versions.tf              # Providers (AWS, K8s, Helm)
│   ├── backend.tf               # State S3 + DynamoDB lock
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── vpc/                 # VPC, subnets, IGW, NAT, routes
│       ├── eks-cluster/         # Control plane EKS + IAM
│       ├── eks-nodegroup/       # Worker nodes + addons + OIDC
│       └── rds/                 # PostgreSQL RDS + replica + SG
├── k8s/
│   ├── 00-namespace-configmap.yml
│   ├── 01-secret.yml
│   ├── 02-deployment.yml
│   └── 03-service-ingress-hpa.yml
├── helm/taskmanager/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── hpa.yaml
├── .github/workflows/
│   ├── ci-cd.yml               # Pipeline complet CI/CD
│   └── terraform-pr.yml        # Terraform plan sur PR
├── monitoring/
│   └── prometheus.yml
└── scripts/
    ├── terraform-init.sh        # Bootstrap du backend S3
    └── deploy.sh                # Déploiement manuel
```

---

## 🚀 Démarrage

### Prérequis
- AWS CLI configuré (`aws configure`)
- Terraform >= 1.5
- kubectl
- helm >= 3

### 1. Initialiser le backend Terraform
```bash
chmod +x scripts/terraform-init.sh
./scripts/terraform-init.sh
```

### 2. Configurer les variables
```bash
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
# Éditer le fichier avec vos valeurs (db_password obligatoire)
```

### 3. Déployer l'infrastructure
```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

### 4. Configurer kubectl
```bash
# La commande exacte est dans les outputs Terraform :
terraform output configure_kubectl
# Ex : aws eks update-kubeconfig --region eu-west-3 --name eks-cluster-taskmanager
```

### 5. Déployer l'application
```bash
# Via Helm (recommandé) :
./scripts/deploy.sh prod latest

# Ou via kubectl (raw manifests) :
kubectl apply -f k8s/
```

---

## 🔑 Secrets GitHub à configurer

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | Clé d'accès IAM pour CI/CD |
| `AWS_SECRET_ACCESS_KEY` | Secret IAM |
| `DB_PASSWORD` | Mot de passe PostgreSQL (min 12 chars) |
| `SONAR_TOKEN` | Token SonarCloud (optionnel) |

---

## 📊 Modules Terraform

| Module | Ressources créées |
|--------|-------------------|
| `vpc` | VPC, subnets pub/priv, IGW, NAT GW, EIP, routes |
| `eks-cluster` | EKS control plane, IAM role cluster |
| `eks-nodegroup` | EC2 worker nodes, IAM role nodes, add-ons, OIDC |
| `rds` | PostgreSQL RDS Multi-AZ, replica, Security Groups |

---

## 💰 Estimation des coûts (eu-west-3)

| Ressource | Type | Coût/mois estimé |
|-----------|------|-----------------|
| EKS Cluster | Control plane | ~73€ |
| EC2 Nodes | 2x t3.medium | ~60€ |
| RDS PostgreSQL | db.t3.micro Multi-AZ | ~40€ |
| RDS Replica | db.t3.micro | ~20€ |
| NAT Gateway | 2x | ~65€ |
| **Total estimé** | | **~258€/mois** |

> 💡 En développement : utiliser `environment=dev` pour désactiver Multi-AZ et le replica.
