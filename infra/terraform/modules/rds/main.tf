# ============================================================
# Module RDS PostgreSQL — TaskManager PFE DevOps
# Adapté de terraform-aws-rds (MySQL → PostgreSQL)
# ============================================================

# ---- Security Groups RDS ----
resource "aws_security_group" "rds_sg" {
  for_each = { for idx, cfg in var.database_configurations : idx => cfg }

  name        = each.value.sg_name
  description = each.value.sg_description
  vpc_id      = each.value.vpc_id

  # Accès PostgreSQL depuis le CIDR VPC uniquement
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = each.value.allowed_cidrs
    description = "PostgreSQL access from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name   = each.value.sg_name
    Prefix = var.resource_name_prefix
  }
}

# ---- Instances RDS PostgreSQL ----
resource "aws_db_instance" "main" {
  for_each = { for idx, cfg in var.database_configurations : idx => cfg }

  engine                  = "postgres"
  engine_version          = each.value.engine_version
  identifier              = each.value.identifier
  allocated_storage       = each.value.allocated_storage
  max_allocated_storage   = each.value.allocated_storage * 2   # Autoscaling storage
  instance_class          = each.value.instance_class
  db_name                 = each.value.db_name
  username                = each.value.db_username
  password                = each.value.db_password
  parameter_group_name    = each.value.parameter_group_name
  db_subnet_group_name    = each.value.db_subnet_group_name
  skip_final_snapshot     = each.value.skip_final_snapshot
  final_snapshot_identifier = each.value.skip_final_snapshot ? null : "${each.value.identifier}-final-snapshot"
  publicly_accessible     = each.value.publicly_accessible
  backup_retention_period = each.value.backup_retention_period
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"
  multi_az                = each.value.multi_az
  storage_encrypted       = true
  vpc_security_group_ids  = [aws_security_group.rds_sg[each.key].id]

  # Performance Insights (monitoring avancé)
  performance_insights_enabled = true

  tags = {
    Name   = each.value.identifier
    Prefix = var.resource_name_prefix
  }
}

# ---- Réplica RDS (lecture seule) ----
resource "aws_db_instance" "replica" {
  for_each = var.create_replica ? { for idx, cfg in var.replica_configurations : idx => cfg } : {}

  identifier              = each.value.identifier
  instance_class          = each.value.instance_class
  replicate_source_db     = each.value.replicate_source_db
  skip_final_snapshot     = each.value.skip_final_snapshot
  backup_retention_period = each.value.backup_retention_period
  multi_az                = each.value.multi_az
  apply_immediately       = each.value.apply_immediately
  storage_encrypted       = true

  tags = { Name = "${var.resource_name_prefix}${each.value.identifier}" }
}
