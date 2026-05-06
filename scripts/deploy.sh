#!/usr/bin/env bash
# ============================================================
# deploy.sh — Script de déploiement manuel TaskManager
# Usage : ./scripts/deploy.sh [dev|staging|prod] [image_tag]
# ============================================================
set -euo pipefail

ENV=${1:-prod}
IMAGE_TAG=${2:-latest}
AWS_REGION="eu-west-3"
CLUSTER_NAME="eks-cluster-taskmanager"
NAMESPACE="taskmanager"

echo "Déploiement TaskManager - Env: $ENV | Tag: $IMAGE_TAG"

# 1. Configurer kubectl
echo "Connexion au cluster EKS..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

# 2. Vérifier le namespace
kubectl get namespace "$NAMESPACE" &>/dev/null || kubectl create namespace "$NAMESPACE"

# 3. Déploiement Helm
echo "Déploiement Helm..."
helm upgrade --install taskmanager ./helm/taskmanager \
  --namespace "$NAMESPACE" \
  --set image.tag="$IMAGE_TAG" \
  --set environment="$ENV" \
  --wait --timeout 5m

# 4. Vérification
echo "Vérification du déploiement..."
kubectl rollout status deployment/taskmanager -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE"
kubectl get ingress -n "$NAMESPACE"

echo "Déploiement terminé"
echo "   → API : $(kubectl get ingress taskmanager-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
