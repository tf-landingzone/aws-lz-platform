################################################################################
# 06-Workload-Support — Outputs
################################################################################

output "account_factory_trigger" {
  description = "Account Factory EventBridge trigger details."
  value = var.enable_account_factory_trigger ? {
    event_rule_arn = module.account_factory_trigger[0].event_rule_arn
    sns_topic_arn  = module.account_factory_trigger[0].sns_topic_arn
    lambda_arn     = module.account_factory_trigger[0].lambda_function_arn
  } : null
}

output "iam_resources" {
  description = "IAM Resources module outputs."
  value       = var.enable_iam_resources ? module.iam_resources[0] : null
}

output "customizations" {
  description = "Customizations module outputs."
  value       = var.enable_customizations ? module.customizations[0] : null
}

output "acm" {
  description = "ACM module outputs."
  value       = var.enable_acm ? module.acm[0] : null
}
