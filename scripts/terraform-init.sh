#!/usr/bin/env bash
# ============================================================
# terraform-init.sh — Initialisation de l'infrastructure AWS
# À exécuter une seule fois avant terraform apply
# ============================================================
set -euo pipefail

AWS_REGION="eu-west-3"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="taskmanager-tfstate-${ACCOUNT_ID}"

echo "🏗️  Initialisation du backend Terraform"
echo "   Région  : $AWS_REGION"
echo "   Compte  : $ACCOUNT_ID"
echo "   Bucket  : $BUCKET_NAME"

# Créer le bucket S3 pour le state
echo "📦 Création du bucket S3..."
aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION" 2>/dev/null || echo "   (bucket existant)"

# Activer le versioning (requis pour use_lockfile = true)
echo "🔒 Activation du versioning S3 (requis pour le lock natif)..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# Activer le chiffrement
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

# Bloquer l'accès public au bucket
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Mettre à jour le backend.tf avec le nom du bucket réel
# Compatible macOS et Linux
echo "📝 Mise à jour de backend.tf..."
BACKEND_FILE="../infra/terraform/backend.tf"
if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s|bucket.*=.*\"taskmanager-tfstate-[^\"]*\"|bucket       = \"${BUCKET_NAME}\"|" "$BACKEND_FILE"
else
  sed -i "s|bucket.*=.*\"taskmanager-tfstate-[^\"]*\"|bucket       = \"${BUCKET_NAME}\"|" "$BACKEND_FILE"
fi

echo ""
echo "✅ Backend Terraform prêt !"
echo "   Lock : fichier natif S3 (.tflock) — aucune table DynamoDB nécessaire"
echo ""
echo "Prochaines étapes :"
echo "  1. cp ../infra/terraform/terraform.tfvars.example ../infra/terraform/terraform.tfvars"
echo "  2. Éditer terraform.tfvars avec vos valeurs"
echo "  3. cd ../infra/terraform && terraform init && terraform plan"
