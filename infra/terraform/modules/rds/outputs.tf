output "master_db_endpoint"   {
  value     = { for idx, inst in aws_db_instance.main : idx => inst.endpoint }
  sensitive = true
}
output "master_db_identifier" { value = { for idx, inst in aws_db_instance.main : idx => inst.identifier } }
output "master_db_arn"        { value = { for idx, inst in aws_db_instance.main : idx => inst.arn } }
output "rds_security_group_ids" { value = { for idx, sg in aws_security_group.rds_sg : idx => sg.id } }

output "replica_db_endpoint"  {
  value     = { for idx, inst in aws_db_instance.replica : idx => inst.endpoint }
  sensitive = true
}
output "replica_db_identifier" { value = { for idx, inst in aws_db_instance.replica : idx => inst.identifier } }
