# ============================================================
# Backend S3 — Stockage du state Terraform à distance
# ============================================================
# Avant d'utiliser ce backend :
#   1. Créer le bucket S3 : aws s3 mb s3://taskmanager-tfstate-<account_id>
#   2. Activer le versioning : aws s3api put-bucket-versioning ...
#   3. Créer la table DynamoDB pour le lock :
#      aws dynamodb create-table \
#        --table-name taskmanager-tflock \
#        --attribute-definitions AttributeName=LockID,AttributeType=S \
#        --key-schema AttributeName=LockID,KeyType=HASH \
#        --billing-mode PAY_PER_REQUEST
# ============================================================

terraform {
  backend "s3" {
    bucket         = "taskmanager-tfstate"        # ← Remplacer par votre bucket
    key            = "prod/taskmanager/terraform.tfstate"
    region         = "eu-west-3"
    encrypt        = true
    dynamodb_table = "taskmanager-tflock"          # Lock distribué
  }
}
