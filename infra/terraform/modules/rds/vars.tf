variable "aws_region" {
  type    = string
  default = "eu-west-3"
}
variable "resource_name_prefix" {
  type    = string
  default = "taskmanager-"
}
variable "create_replica" {
  type    = bool
  default = false
}
variable "database_configurations" {
  type = list(object({
    identifier              = string
    engine                  = string
    engine_version          = string
    allocated_storage       = number
    instance_class          = string
    db_name                 = string
    db_username             = string
    db_password             = string
    parameter_group_name    = string
    db_subnet_group_name    = string
    skip_final_snapshot     = bool
    publicly_accessible     = bool
    backup_retention_period = number
    multi_az                = bool
    vpc_id                  = string
    allowed_cidrs           = list(string)
    sg_name                 = string
    sg_description          = string
    port                    = optional(number, 5432)
  }))
  default = []
}
variable "replica_configurations" {
  type = list(object({
    identifier              = string
    instance_class          = string
    skip_final_snapshot     = bool
    backup_retention_period = number
    replicate_source_db     = string
    multi_az                = bool
    apply_immediately       = bool
  }))
  default = []
}
