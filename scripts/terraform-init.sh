#!/usr/bin/env bash
# ============================================================
# terraform-init.sh — Initialisation de l'infrastructure AWS
# À exécuter une seule fois avant terraform apply
# ============================================================
set -euo pipefail

AWS_REGION="eu-west-3"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="taskmanager-tfstate-${ACCOUNT_ID}"
DYNAMO_TABLE="taskmanager-tflock"

echo "🏗️  Initialisation du backend Terraform"
echo "   Région  : $AWS_REGION"
echo "   Compte  : $ACCOUNT_ID"
echo "   Bucket  : $BUCKET_NAME"

# Créer le bucket S3 pour le state
echo "📦 Création du bucket S3..."
aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION" 2>/dev/null || echo "   (bucket existant)"

# Activer le versioning
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# Activer le chiffrement
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

# Créer la table DynamoDB pour le lock
echo "🔒 Création de la table DynamoDB pour le lock..."
aws dynamodb create-table \
  --table-name "$DYNAMO_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION" 2>/dev/null || echo "   (table existante)"

# Mettre à jour le backend.tf avec le nom du bucket réel
sed -i "s/taskmanager-tfstate\"/taskmanager-tfstate-${ACCOUNT_ID}\"/" infra/terraform/backend.tf

echo "✅ Backend Terraform prêt !"
echo ""
echo "Prochaines étapes :"
echo "  1. cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars"
echo "  2. Éditer terraform.tfvars avec vos valeurs"
echo "  3. cd infra/terraform && terraform init && terraform plan"
