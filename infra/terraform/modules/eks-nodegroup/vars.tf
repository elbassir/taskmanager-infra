variable "eks_cluster_name" {
  type = string
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
variable "default_scaling_config" {
  type    = object({ desired_size = number, max_size = number, min_size = number })
  default = { desired_size = 2, max_size = 4, min_size = 1 }
}
variable "node_groups" {
  type = list(object({
    name           = string
    ami_type       = string
    instance_types = list(string)
    capacity_type  = string
    disk_size      = number
    scaling_config = optional(object({
      desired_size = number
      max_size     = number
      min_size     = number
    }))
  }))
  default = []
}
variable "addons" {
  type    = list(object({ name = string, version = string }))
  default = []
}
