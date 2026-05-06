# Infrastructure — Notes techniques

## Vue d'ensemble

L'infra tourne sur AWS eu-west-3 (Paris). Elle est entièrement provisionnée par Terraform et organisée en modules.

## Réseau (VPC)

Le VPC couvre `10.0.0.0/16`. Il est découpé en 4 subnets répartis sur 2 zones de disponibilité (eu-west-3a et eu-west-3b) :

- **Subnets publics** : `10.0.0.0/20` et `10.0.128.0/20` — hébergent les NAT Gateways et l'ALB
- **Subnets privés** : `10.0.16.0/20` et `10.0.144.0/20` — hébergent les nœuds EKS et RDS

Les nœuds privés accèdent à Internet via les NAT Gateways (un par AZ). On en a deux pour la résilience — si une AZ tombe, l'autre continue.

## EKS

Kubernetes 1.30 managé par AWS. Le control plane est géré par AWS, on ne voit que les nœuds.

Node group : instances `t3.small` en On-Demand, dans les subnets privés. Min 1 / normal 2 / max 4 nœuds.

Add-ons installés : `kube-proxy`, `vpc-cni`, `coredns`, `aws-ebs-csi-driver`.

Le driver EBS a besoin d'un IAM role dédié (IRSA). Sans ça il démarre sans permissions et reste bloqué. Le role `taskmanager-EBSCSIDriverRole` est créé automatiquement et passé via `service_account_role_arn`.

### IRSA

Les pods qui ont besoin de droits AWS (ALB controller, EBS CSI) utilisent IRSA plutôt que des credentials en dur. Le principe : un IAM role est associé à un Service Account Kubernetes via l'OIDC provider du cluster. Le pod reçoit des credentials temporaires automatiquement.

| Composant | Service Account | IAM Role |
| --- | --- | --- |
| ALB Controller | `kube-system/aws-load-balancer-controller` | `AmazonEKSLoadBalancerControllerRole` |
| EBS CSI Driver | `kube-system/ebs-csi-controller-sa` | `taskmanager-EBSCSIDriverRole` |

## RDS

PostgreSQL 16.6 sur `db.t3.micro`, 20 Go de stockage (auto-expand jusqu'à 40 Go). Base : `taskdb`, user : `taskadmin`.

Accessible uniquement depuis le VPC sur le port 5432. Depuis Internet c'est bloqué par le Security Group.

Comportement selon l'environnement :

| | dev | prod |
| --- | --- | --- |
| Multi-AZ | non | oui |
| Backups | aucun | 7 jours |
| Replica lecture | non | oui |

## ALB et Ingress

Le trafic arrive sur un Application Load Balancer dans les subnets publics, qui forward vers les pods dans les subnets privés.

L'ALB n'est pas créé directement par Terraform — c'est le AWS Load Balancer Controller (installé via Helm) qui le crée automatiquement quand il détecte une ressource Ingress dans Kubernetes.

**Important pour le destroy** : l'ALB est hors du state Terraform. Il faut désinstaller le chart Helm de l'application avant `terraform destroy`, sinon l'ALB reste et bloque la suppression du VPC.

## Application dans Kubernetes

2 replicas avec anti-affinité (les pods sont placés sur des nœuds différents si possible). Rolling update avec `maxUnavailable: 0` — le nouveau pod démarre avant que l'ancien soit coupé.

Variables d'environnement injectées depuis des Secrets Kubernetes (URL BDD, credentials). Le code ne contient aucun mot de passe.

HPA configuré : scale up si CPU > 70% ou mémoire > 80%, jusqu'à 6 pods maximum.

## State Terraform

Le state est stocké dans un bucket S3 avec versioning et chiffrement activés. Le lock natif S3 (`use_lockfile = true`, Terraform >= 1.10) empêche deux apply simultanés — plus besoin de table DynamoDB.

## Monitoring

kube-prometheus-stack déployé dans le namespace `monitoring` via Terraform. Inclut Prometheus, Grafana, Node Exporter et kube-state-metrics.

L'application expose ses métriques sur `/actuator/prometheus`. Un PodMonitor les scrape automatiquement.

Dashboards importés automatiquement dans Grafana : JVM Micrometer (4701), Kubernetes Cluster (315), Node Exporter (1860), Spring Boot (19004).

```bash
# Accès local Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# Accès local Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

## Ordre de destruction propre

```bash
# 1. Désinstaller l'application (libère l'ALB)
helm uninstall taskmanager -n taskmanager
kubectl get ingress -n taskmanager  # attendre que l'ingress disparaisse

# 2. Désinstaller monitoring et ALB controller
helm uninstall prometheus -n monitoring
helm uninstall aws-load-balancer-controller -n kube-system

# 3. Supprimer les namespaces
kubectl delete ns taskmanager monitoring

# 4. Détruire l'infra
cd infra/terraform
terraform destroy

# 5. Vider et supprimer le bucket S3 (optionnel)
BUCKET="taskmanager-tfstate-$(aws sts get-caller-identity --query Account --output text)"
aws s3 rm "s3://${BUCKET}" --recursive --region eu-west-3
aws s3 rb "s3://${BUCKET}" --region eu-west-3
```

Si `terraform destroy` échoue avec `DependencyViolation` sur le VPC, des ressources AWS orphelines traînent (ALB ou Security Groups créés par Kubernetes). Les identifier :

```bash
VPC_ID="<vpc-id>"
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].[LoadBalancerArn,LoadBalancerName]" \
  --output table --region eu-west-3
```
