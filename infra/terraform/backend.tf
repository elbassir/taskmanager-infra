# ============================================================
# Backend S3 — Stockage du state Terraform à distance
# ============================================================
# Avant d'utiliser ce backend :
#   1. Créer le bucket S3 : aws s3 mb s3://taskmanager-tfstate-<account_id>
#   2. Activer le versioning : aws s3api put-bucket-versioning ...
#   3. Activer le versioning sur le bucket S3 (requis pour use_lockfile) :
#      aws s3api put-bucket-versioning \
#        --bucket taskmanager-tfstate-<account_id> \
#        --versioning-configuration Status=Enabled
# ============================================================

terraform {
  backend "s3" {
    bucket       = "taskmanager-tfstate-878788787" # ← Remplacer par votre bucket
    key          = "prod/taskmanager/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true # Lock natif S3 (remplace dynamodb_table)
  }
}
