###############################################################################
# sfn-pipeline — variables
###############################################################################

variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "tf_state_bucket" {
  description = "S3 bucket used for Terraform state AND SFN job manifests"
  type        = string
}

variable "vpc_id" {
  description = "VPC for the Fargate security group"
  type        = string
}

variable "subnet_ids" {
  description = <<-EOF
    Subnet IDs where Fargate tasks run. For egress-only (no NAT):
    use private subnets with VPC endpoints for ECR, S3, DynamoDB, STS,
    CloudWatch Logs, and Step Functions. For simplicity, public subnets with
    assign_public_ip=true also work but are not recommended for production.
  EOF
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Give the Fargate task a public IP (set true only for public subnets without VPC endpoints)"
  type        = bool
  default     = false
}

variable "ecr_image_tag" {
  description = "ECR image tag for tf-executor (updated by build-tf-executor.yml)"
  type        = string
  default     = "latest"
}

variable "task_cpu" {
  description = "Fargate task vCPU (256=0.25, 512=0.5, 1024=1, 2048=2)"
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "Fargate task memory in MiB"
  type        = number
  default     = 2048
}

variable "sfn_max_concurrency" {
  description = "Max concurrent Fargate tasks in Distributed Map. 0 = unlimited (Step Functions manages)"
  type        = number
  default     = 0
}

variable "tolerated_failure_percentage" {
  description = "SFN Distributed Map tolerated failure % before aborting the run"
  type        = number
  default     = 20
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for deployment notifications (leave empty to disable)"
  type        = string
  default     = ""
}

variable "inventory_table_name" {
  description = "DynamoDB table name for account inventory"
  type        = string
  default     = "lz-account-inventory"
}

variable "deploy_state_table_name" {
  description = "DynamoDB table name for deploy run state"
  type        = string
  default     = "lz-deploy-run-state"
}

variable "log_retention_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 30
}
