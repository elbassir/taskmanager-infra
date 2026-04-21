variable "cluster_config" {
  type = object({ name = string, version = string })
}
variable "public_subnets_ids" {
  type = list(string)
}
variable "private_subnets_ids" {
  type = list(string)
}
variable "resource_name_prefix" {
  type    = string
  default = "taskmanager-"
}
