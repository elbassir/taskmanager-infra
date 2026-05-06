output "node_group_arns"         { value = [for ng in aws_eks_node_group.nodes : ng.arn] }
output "node_group_ids"          { value = [for ng in aws_eks_node_group.nodes : ng.id] }
output "node_group_statuses"     { value = [for ng in aws_eks_node_group.nodes : ng.status] }
output "oidc_provider_url"       { value = aws_iam_openid_connect_provider.oidc.url }
output "oidc_provider_arn"       { value = aws_iam_openid_connect_provider.oidc.arn }
