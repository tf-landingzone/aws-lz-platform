################################################################################
# 04-Logging — Outputs
################################################################################

output "central_log_bucket" {
  description = "Central log bucket details."
  value = var.enable_centralized_logging ? {
    id  = module.centralized_logging[0].central_log_bucket_id
    arn = module.centralized_logging[0].central_log_bucket_arn
  } : null
}

output "access_log_bucket" {
  description = "Access log bucket details."
  value = var.enable_centralized_logging ? {
    id  = module.centralized_logging[0].access_log_bucket_id
    arn = module.centralized_logging[0].access_log_bucket_arn
  } : null
}

output "kms" {
  description = "KMS module outputs."
  value       = var.enable_kms ? module.kms[0] : null
}
