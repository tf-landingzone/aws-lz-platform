################################################################################
# 05-Operations — Outputs
################################################################################

output "budgets" {
  description = "Budgets created."
  value       = var.enable_budget_alerts ? module.budget_alerts[0].budgets : {}
}

output "finops_summary" {
  description = "FinOps summary."
  value       = var.enable_budget_alerts ? module.budget_alerts[0].finops_summary : {}
}

output "ssm" {
  description = "SSM module outputs."
  value       = var.enable_ssm ? module.ssm[0] : null
}

output "backup" {
  description = "Backup module outputs."
  value       = var.enable_backup ? module.backup[0] : null
}

output "cost_reporting" {
  description = "Cost Reporting module outputs."
  value       = var.enable_cost_reporting ? module.cost_reporting[0] : null
}
