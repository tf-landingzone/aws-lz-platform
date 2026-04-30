###############################################################################
# sfn-pipeline — outputs
###############################################################################

output "state_machine_arn" {
  description = "Step Functions state machine ARN — set as SFN_PIPELINE_ARN secret"
  value       = aws_sfn_state_machine.pipeline.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL — set as ECR_REPOSITORY_URL in build-tf-executor.yml"
  value       = aws_ecr_repository.tf_executor.repository_url
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "ecs_task_definition_arn" {
  description = "ECS task definition ARN (latest revision)"
  value       = aws_ecs_task_definition.tf_executor.arn
}

output "ecs_task_role_arn" {
  description = "IAM role ARN for the ECS task (the container identity)"
  value       = aws_iam_role.ecs_task.arn
}

output "inventory_table_name" {
  description = "DynamoDB account inventory table name"
  value       = aws_dynamodb_table.account_inventory.name
}

output "inventory_table_arn" {
  description = "DynamoDB account inventory table ARN"
  value       = aws_dynamodb_table.account_inventory.arn
}

output "sfn_log_group" {
  description = "CloudWatch log group for SFN executions"
  value       = aws_cloudwatch_log_group.sfn.name
}

output "ecs_log_group" {
  description = "CloudWatch log group for ECS task output"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "security_group_id" {
  description = "Security group attached to Fargate tasks"
  value       = aws_security_group.tf_executor.id
}
