# Guide de déploiement — TaskManager PFE DevOps

Durée totale estimée : 3h environ.

## Prérequis

Vérifier que les outils sont installés :

```bash
java --version        # Java 21
mvn --version         # Maven 3.9+
docker --version
terraform --version   # >= 1.10
kubectl version --client
helm version          # >= 3
aws --version
```

Configurer AWS CLI :

```bash
aws configure
# region : eu-west-3
# output : json

aws sts get-caller-identity  # vérifier que ça répond
```

## Phase 1 — Application en local

Cloner le dépôt de l'application :

```bash
git clone https://github.com/elbassir/taskmanager.git
cd taskmanager
```

Compiler et lancer les tests :

```bash
mvn compile
mvn test
# 7 tests, 0 failures
```

Démarrer en local (profil dev, base H2 en mémoire) :

```bash
mvn spring-boot:run
# démarré sur le port 8080
```

Tester quelques endpoints depuis un autre terminal :

```bash
curl http://localhost:8080/actuator/health
curl -X POST http://localhost:8080/api/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{"title":"test","priority":"HIGH"}'
curl http://localhost:8080/api/v1/tasks
```

Vérifier les métriques Prometheus :

```bash
curl http://localhost:8080/actuator/prometheus | head -20
```

Arrêter avec Ctrl+C.

## Phase 2 — Docker

Builder l'image :

```bash
docker build -t taskmanager:latest .
docker images taskmanager
```

Tester avec Docker Compose (app + PostgreSQL + Prometheus + Grafana) :

```bash
docker compose up -d
docker compose ps
docker compose logs app  # chercher "Started TaskManagerApplication"

curl http://localhost:8080/actuator/health
# le composant db doit être UP

docker compose down
```

Pousser l'image sur GHCR :

```bash
echo VOTRE_TOKEN | docker login ghcr.io -u VOTRE_USERNAME --password-stdin
docker tag taskmanager:latest ghcr.io/VOTRE_USERNAME/taskmanager:latest
docker push ghcr.io/VOTRE_USERNAME/taskmanager:latest
```

## Phase 3 — GitHub

Créer le dépôt et pousser le code si ce n'est pas déjà fait :

```bash
git init
git add .
git commit -m "initial commit"
git remote add origin https://github.com/VOTRE_USERNAME/taskmanager.git
git push -u origin main
```

Ajouter les secrets dans Settings → Secrets and variables → Actions :

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `DB_PASSWORD` (min 12 caractères)
- `GHCR_USERNAME`
- `GHCR_TOKEN` (scope read:packages + write:packages)
- `GRAFANA_ADMIN_PASSWORD`

## Phase 4 — Infrastructure Terraform

Cloner le dépôt d'infra :

```bash
git clone https://github.com/elbassir/devops-pfe-infra.git
cd devops-pfe-infra/infra/terraform
```

Créer le bucket S3 pour le state :

```bash
chmod +x ../../scripts/terraform-init.sh
../../scripts/terraform-init.sh
```

Configurer les variables :

```bash
cp terraform.tfvars.example terraform.tfvars
```

Contenu de `terraform.tfvars` :

```hcl
aws_region  = "eu-west-3"
environment = "dev"

vpc_cidr             = "10.0.0.0/16"
public_subnets_cidr  = ["10.0.0.0/20", "10.0.128.0/20"]
private_subnets_cidr = ["10.0.16.0/20", "10.0.144.0/20"]

eks_version       = "1.30"
node_desired_size = 2
node_max_size     = 4
node_min_size     = 1

rds_instance_class = "db.t3.micro"
db_password        = "VotreMotDePasse!"

ghcr_username          = "VOTRE_USERNAME"
ghcr_token             = "ghp_xxxxxxxxxxxx"
grafana_admin_password = "VotreMotDePasseGrafana!"
```

Ne jamais commiter ce fichier.

Initialiser et déployer :

```bash
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Ça prend environ 20-30 minutes. Les étapes longues : EKS cluster (~10 min), node group (~5 min), RDS (~5 min).

En fin d'apply, récupérer les outputs :

```bash
terraform output
```

Configurer kubectl :

```bash
aws eks update-kubeconfig --region eu-west-3 --name eks-cluster-taskmanager
kubectl get nodes  # 2 nœuds Ready
```

Vérifier dans AWS :

```bash
aws eks describe-cluster --name eks-cluster-taskmanager --region eu-west-3 \
  --query 'cluster.status'
# "ACTIVE"

aws rds describe-db-instances --region eu-west-3 \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]' --output table
```

## Phase 5 — Déploiement Kubernetes

Le secret de base de données est déjà créé par Terraform. Ne pas appliquer `01-secret.yml`.

```bash
cd ../../k8s/

kubectl apply -f 00-namespace-configmap.yml
kubectl apply -f 02-deployment.yml
kubectl apply -f 03-service-ingress-hpa.yml

kubectl get pods -n taskmanager -w
# attendre 1/1 Running

kubectl get ingress -n taskmanager
# récupérer l'ADDRESS de l'ALB (peut prendre 2-3 minutes à apparaître)
```

Tester via l'ALB :

```bash
ALB_URL=$(kubectl get ingress taskmanager-ingress -n taskmanager \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl http://$ALB_URL/actuator/health
curl http://$ALB_URL/api/v1/tasks
```

## Phase 6 — Helm

Préparer les ressources existantes pour Helm (si déjà déployé via kubectl) :

```bash
for resource in deployment/taskmanager service/taskmanager-svc ingress/taskmanager-ingress hpa/taskmanager-hpa; do
  kubectl label $resource -n taskmanager app.kubernetes.io/managed-by=Helm --overwrite 2>/dev/null
  kubectl annotate $resource -n taskmanager \
    meta.helm.sh/release-name=taskmanager \
    meta.helm.sh/release-namespace=taskmanager --overwrite 2>/dev/null
done
```

Déployer via Helm :

```bash
cd ..
helm lint ./helm/taskmanager
helm upgrade --install taskmanager ./helm/taskmanager \
  --namespace taskmanager \
  --create-namespace \
  --set image.tag=latest \
  --set 'imagePullSecrets[0].name=ghcr-secret' \
  --wait --timeout 5m

helm list -n taskmanager
```

## Phase 7 — Pipeline CI/CD

Déclencher le pipeline :

```bash
echo '# trigger' >> README.md
git add README.md
git commit -m "trigger pipeline"
git push origin main
```

Suivre dans GitHub Actions. Le pipeline fait : tests → build Docker → push GHCR → terraform apply → helm deploy.

Vérifier le rolling update :

```bash
kubectl get pods -n taskmanager -w
```

## Phase 8 — Monitoring

Prometheus et Grafana sont déjà déployés par Terraform dans le namespace `monitoring`.

```bash
kubectl get pods -n monitoring  # tous Running

# Accès Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
# http://localhost:9090 → Status → Targets → vérifier taskmanager UP

# Accès Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
# http://localhost:3000 → admin / [grafana_admin_password]
```

Les 4 dashboards sont importés automatiquement : JVM Micrometer, Kubernetes Cluster, Node Exporter, Spring Boot.

Générer du trafic pour alimenter les graphiques :

```bash
for i in {1..20}; do curl http://$ALB_URL/api/v1/tasks; done
for i in {1..5}; do
  curl -X POST http://$ALB_URL/api/v1/tasks \
    -H 'Content-Type: application/json' \
    -d '{"title":"Tâche '$i'","priority":"MEDIUM"}'
done
```

## Vérification finale

```bash
kubectl get nodes
kubectl get all,ingress -n taskmanager
kubectl get hpa -n taskmanager
helm list -n taskmanager
kubectl get pods -n monitoring

curl http://$ALB_URL/actuator/health
curl http://$ALB_URL/api/v1/tasks/stats
```

## Nettoyage

À faire dans cet ordre pour éviter que l'ALB bloque la suppression du VPC :

```bash
helm uninstall taskmanager -n taskmanager
kubectl get ingress -n taskmanager  # attendre que l'ingress disparaisse

helm uninstall prometheus -n monitoring
helm uninstall aws-load-balancer-controller -n kube-system

kubectl delete ns taskmanager monitoring

cd infra/terraform
terraform destroy

# supprimer le bucket S3 si plus besoin
BUCKET="taskmanager-tfstate-$(aws sts get-caller-identity --query Account --output text)"
aws s3 rm "s3://${BUCKET}" --recursive --region eu-west-3
aws s3 rb "s3://${BUCKET}" --region eu-west-3
```
