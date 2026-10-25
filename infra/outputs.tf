# ---- Contract section 7 ----
output "api_base_url" {
  description = "Frontend config.js, smoke tests"
  value       = module.serving.api_base_url
}

output "ecr_repository_url" {
  description = "deploy.yml image push"
  value       = module.registry.repository_url
}

output "lambda_function_name" {
  description = "Step Functions update step"
  value       = module.serving.function_name
}

output "frontend_bucket_name" {
  description = "deploy.yml sync"
  value       = module.storage.frontend_bucket_name
}

# state_machine_arn and github_actions_role_arn are outputs of Manik's pipeline
# module. See pipeline.tf; enable it once infra/modules/pipeline/ is merged.

# ---- Extras (handy for demo / debugging) ----
output "frontend_website_url" {
  value = "http://${module.storage.frontend_website_endpoint}"
}

output "model_bucket_name" {
  value = module.storage.model_bucket_name
}

output "predictions_table_name" {
  value = module.database.table_name
}
